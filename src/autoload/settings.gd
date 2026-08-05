extends Node
## Display settings (autoload "Settings"). Deliberately separate from Station:
## that file is the crew's progress, this is about the screen in front of you,
## and the two shouldn't travel together.
##
## Brightness exists because the trench is near-black outside a lamp, and
## "near-black" is not a fixed thing — the ambient that reads as a faint
## silhouette of rock on one panel is indistinguishable from pure black on
## another, and blinding on a third. So the menu offers a calibration strip and
## the player sets it by eye, which is the only way to get this right across
## displays we can't see.

signal changed

const SAVE_PATH := "user://settings.json"

## Ambient light in the trench, before brightness. Unlit terrain sits at these
## values, which is exactly why the calibration patch is drawn in the same
## shade: tune it until that patch is barely visible and unlit rock will be too.
##
## Stepped down by a fixed amount per descent rather than interpolated across a
## span, for the same reason lamp reach is measured in pixels: a constant unit
## per depth is a thing you can weigh against the light you're carrying, while a
## fraction of an arbitrary range is not. All three channels reach the floor
## together around depth 15.
const AMBIENT_SURFACE := Color(0.062, 0.082, 0.115)
const AMBIENT_DEPTH_LOSS := Color(0.003, 0.004, 0.0055)  # per descent
const AMBIENT_FLOOR := Color(0.020, 0.028, 0.038)

const BRIGHTNESS_MIN := 0.5
const BRIGHTNESS_MAX := 2.2

var brightness := 1.0

var _save_path := SAVE_PATH


func _ready() -> void:
	load_data()


## The CanvasModulate colour for a depth, with the player's brightness applied.
func ambient_for_depth(depth: int) -> Color:
	var descents := maxi(0, depth - 1)
	return scaled(Color(
		maxf(AMBIENT_FLOOR.r, AMBIENT_SURFACE.r - AMBIENT_DEPTH_LOSS.r * descents),
		maxf(AMBIENT_FLOOR.g, AMBIENT_SURFACE.g - AMBIENT_DEPTH_LOSS.g * descents),
		maxf(AMBIENT_FLOOR.b, AMBIENT_SURFACE.b - AMBIENT_DEPTH_LOSS.b * descents),
	))


## A shade with brightness applied. Clamped per channel so a high setting lifts
## the dark without inverting the relationship between shades.
func scaled(shade: Color) -> Color:
	return Color(
		minf(1.0, shade.r * brightness),
		minf(1.0, shade.g * brightness),
		minf(1.0, shade.b * brightness),
	)


func set_brightness(value: float) -> void:
	var next := clampf(value, BRIGHTNESS_MIN, BRIGHTNESS_MAX)
	if is_equal_approx(next, brightness):
		return
	brightness = next
	save_data()
	changed.emit()


func load_data() -> void:
	brightness = 1.0
	if not FileAccess.file_exists(_save_path):
		return
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		brightness = clampf(
			float(parsed.get("brightness", 1.0)), BRIGHTNESS_MIN, BRIGHTNESS_MAX)


func save_data() -> void:
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: could not write %s" % _save_path)
		return
	file.store_string(JSON.stringify({"brightness": brightness}))
