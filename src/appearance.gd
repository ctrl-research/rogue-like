class_name Appearance
## Per-player identity: chosen name plus the two colours that recolour the diver
## sprite (suit, helmet screen). Everything here is static — this is a shared
## vocabulary for the customization UI, the sub lobby, the in-game diver, and the
## network payload, so all four agree on what a valid profile is.
##
## Profiles travel as plain strings (hex colours, not Color values) because they
## ride two very different channels: Station.meta_dict() over RPC, and
## Station's JSON save file. JSON.stringify cannot represent a Color, so hex is
## the one representation that survives both without a special case.

const SPRITE_PATH := "res://assets/sprites/diver.png"
const SHADER_PATH := "res://assets/shaders/diver_recolor.gdshader"

## The diver sprite's own palette — the four tones the shader is allowed to
## replace. These MUST stay in step with the DIVER palette in
## tools/gen_pixel_art.py; tests/palette_check.py fails CI if they drift.
const KEY_SUIT_LIT := "#d9a521"
const KEY_SUIT_DARK := "#8a6508"
const KEY_SCREEN_LIT := "#9fe8ff"
const KEY_SCREEN_DARK := "#0e3a52"

## Preset colours offered in the picker. Not a restriction — the picker accepts
## any colour, and these are seeded into it as presets so there is something
## coherent to start from rather than a blank gradient.
const SUIT_PRESETS: Array[String] = [
	"#d9a521",  # brass (stock)
	"#d94f3d",  # rust
	"#3fa9d9",  # cyan
	"#7dd93f",  # kelp
	"#b06fd9",  # violet
	"#d97fb0",  # coral
	"#4fd9a9",  # seafoam
	"#d97a2b",  # amber
	"#8f9ed9",  # steel
	"#d9d0a8",  # bone
]
const SCREEN_PRESETS: Array[String] = [
	"#9fe8ff",  # ice (stock)
	"#ffe89f",  # lamp
	"#b6ff9f",  # phosphor
	"#ff9fc2",  # rose
	"#c9b6ff",  # lilac
	"#9fffe8",  # mint
	"#ffc99f",  # ember
	"#ffffff",  # white
]

## The one colour constraint, and it is functional rather than taste: 2D lights
## MULTIPLY. A pure black suit is still black under a lamp however much light
## lands on it, so it doesn't read as "a dark diver" — it reads as no diver.
##
## Measured on the BRIGHTEST channel, not on luminance. Luminance weights blue at
## 0.07, so a luminance floor would have declared #0000ff too dark and lightened
## it into a pastel — breaking "pick any colour" for a colour that multiplies
## light perfectly well. The brightest channel is what decides whether anything
## survives the multiply, which is the actual question.
const MIN_CHANNEL := 0.35

const DEFAULT_SUIT := "#d9a521"
const DEFAULT_SCREEN := "#9fe8ff"

## Short enough that the label above a 16px diver stays readable at 640x360.
const NAME_MAX := 12


static func default_profile() -> Dictionary:
	return {"name": "", "suit": DEFAULT_SUIT, "screen": DEFAULT_SCREEN}


## Names are upper-cased to match the rest of the game's typography (every label
## in the HUD, station and sub is caps), and stripped of anything that could
## break layout — newlines would push a multi-line label over other divers, and
## control characters have no glyph.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		# Explicit String: indexing a String is an operator call, which the
		# analyzer types as Variant — `:=` here fails to infer and breaks the
		# whole script's parse.
		var c: String = raw[i]
		if c.unicode_at(0) < 32:
			continue  # control chars, newlines, tabs
		out += c
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > NAME_MAX:
		out = out.substr(0, NAME_MAX)
	return out.to_upper()


## Any colour the player likes, with one floor applied (see MIN_CHANNEL). Total by
## construction — unparseable, absent or non-string input yields the fallback —
## so no caller needs an error path, and a hostile payload from a peer degrades
## to something drawable rather than to an invisible diver.
static func normalize_color(raw: Variant, fallback: String) -> String:
	if not raw is String or str(raw).is_empty():
		return fallback
	var text := str(raw)
	if not text.begins_with("#"):
		text = "#" + text
	if not Color.html_is_valid(text.substr(1)):
		return fallback
	return "#" + lift(Color.from_string(text, Color.WHITE)).to_html(false)


## Scale a too-dark colour up until its brightest channel reaches the floor.
## Scaling all three channels by the same factor preserves the hue and the
## saturation exactly, so the pick is honoured — only its brightness moves. Pure
## black is the single input with no hue to preserve, and becomes a grey.
static func lift(c: Color) -> Color:
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak >= MIN_CHANNEL:
		return c
	if peak <= 0.0001:
		return Color(MIN_CHANNEL, MIN_CHANNEL, MIN_CHANNEL)
	var scale := MIN_CHANNEL / peak
	return Color(c.r * scale, c.g * scale, c.b * scale)


## Never trust a profile that arrived over the network — or one loaded from a
## save file a player may have hand-edited.
static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return default_profile()
	var d: Dictionary = raw
	return {
		"name": sanitize_name(str(d.get("name", ""))),
		"suit": normalize_color(d.get("suit", DEFAULT_SUIT), DEFAULT_SUIT),
		"screen": normalize_color(d.get("screen", DEFAULT_SCREEN), DEFAULT_SCREEN),
	}


## A "seat" is what the sub roster stores per peer: which diver class they are
## bringing plus how they look. Bundled because they always travel together and
## always change together.
static func make_seat(diver_id: String, prof: Dictionary) -> Dictionary:
	return {"diver": diver_id, "profile": sanitize(prof)}


static func sanitize_seat(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return make_seat(Divers.DEFAULT, default_profile())
	var d: Dictionary = raw
	var id := str(d.get("diver", Divers.DEFAULT))
	return make_seat(id if Divers.valid(id) else Divers.DEFAULT,
			d.get("profile", {}) if d.get("profile") is Dictionary else {})


## Canonical comparison key for a seat. Spelled out field by field rather than
## comparing dictionaries directly: Dictionary equality semantics differ between
## shallow and recursive comparison, and change detection driving a roster
## broadcast is not a place to depend on which one applies.
static func seat_key(seat: Variant) -> String:
	var s := sanitize_seat(seat)
	var p: Dictionary = s.profile
	return "%s|%s|%s|%s" % [s.diver, p.name, p.suit, p.screen]


## The name to show for a peer: their chosen one, else a stable positional
## fallback so an unnamed diver is still addressable ("cover P3").
static func label_for(profile: Variant, player_index: int) -> String:
	var chosen := sanitize_name(str((profile as Dictionary).get("name", "")) \
			if profile is Dictionary else "")
	return chosen if not chosen.is_empty() else "P%d" % (player_index + 1)


## One material per sprite, never a shared subresource: a ShaderMaterial holds
## its own uniform values, so sharing one would make every diver in the scene
## take the colours of whichever was configured last.
static func make_material(suit_hex: String, screen_hex: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("key_suit_lit", Color.from_string(KEY_SUIT_LIT, Color.WHITE))
	mat.set_shader_parameter("key_suit_dark", Color.from_string(KEY_SUIT_DARK, Color.WHITE))
	mat.set_shader_parameter("key_screen_lit", Color.from_string(KEY_SCREEN_LIT, Color.WHITE))
	mat.set_shader_parameter("key_screen_dark", Color.from_string(KEY_SCREEN_DARK, Color.WHITE))
	mat.set_shader_parameter("suit", Color.from_string(suit_hex, Color.WHITE))
	mat.set_shader_parameter("screen", Color.from_string(screen_hex, Color.WHITE))
	return mat


## Recolour a diver sprite from a profile. Safe to call with a partial or absent
## profile: sanitize() fills in the stock colours.
static func apply(sprite: CanvasItem, profile: Variant) -> void:
	if sprite == null:
		return
	var clean := sanitize(profile)
	sprite.material = make_material(str(clean.suit), str(clean.screen))


## The downed look — reddened and slightly transparent. Lives here because the
## shader owns sprite colour and alpha now; setting modulate instead would
## multiply into the swap, and writing COLOR in the shader would discard the
## alpha modulate used to carry.
static func set_downed(sprite: CanvasItem, on: bool) -> void:
	if sprite == null or sprite.material == null:
		return
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("flash", 1.0 if on else 0.0)
	mat.set_shader_parameter("alpha", 0.9 if on else 1.0)
