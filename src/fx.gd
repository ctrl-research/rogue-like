class_name Fx
## Local-only cosmetic effects (damage numbers, poofs, screen shake). All
## callers trigger these from already-replicated state, so every peer sees
## the same thing without any extra netcode. Hard caps keep horde-scale
## fights from drowning in nodes.

const MAX_DAMAGE_NUMBERS := 40
const MAX_POOFS := 24

const SHADOW_TEXTURE := preload("res://assets/sprites/shadow.png")
const LIGHT_TEXTURE := preload("res://assets/sprites/light.png")


## Anchor a sprite to the deck. Without a contact shadow a flat sprite reads as
## a sticker sliding over the floor rather than something standing in the
## trench — and now that rock has visible fronts, that mismatch is obvious.
## Added as the host's first child so it draws beneath the host's own art, and
## inherits the host's scale, so bigger fauna cast bigger shadows for free.
static func attach_shadow(host: Node2D, spread := 1.0, drop := 8.0) -> void:
	var shadow := Sprite2D.new()
	shadow.texture = SHADOW_TEXTURE
	shadow.scale = Vector2.ONE * spread
	shadow.position = Vector2(0, drop)
	host.add_child(shadow)
	host.move_child(shadow, 0)


## A marker light on an objective. Once the ambient is dark enough to hide what
## it touches, anything the crew is sent to find has to carry its own glow or
## the quest becomes a search of an unlit room. These are the first of the
## "other light sources" from issue #20, and they light the rock around them for
## the whole crew exactly like a diver's lamp does.
static func attach_beacon(host: Node2D, color: Color, energy := 0.45, spread := 0.7) -> void:
	var light := PointLight2D.new()
	light.texture = LIGHT_TEXTURE
	light.color = color
	light.energy = energy
	light.texture_scale = spread
	host.add_child(light)


static func damage_number(ctx: Node, pos: Vector2, amount: float, color := Color(1.0, 0.9, 0.5)) -> void:
	var tree := ctx.get_tree()
	if tree == null or tree.current_scene == null:
		return
	if tree.get_nodes_in_group("fx_dmg").size() >= MAX_DAMAGE_NUMBERS:
		return
	var label := Label.new()
	label.text = str(maxi(1, roundi(amount)))
	label.add_theme_font_size_override("font_size", 8)
	label.modulate = color
	label.z_index = 50
	label.position = pos + Vector2(randf_range(-7.0, 7.0), -8.0)
	label.add_to_group("fx_dmg")
	# Deferred: fx spawn from physics callbacks and node-teardown signals,
	# when the parent may be mid-child-setup.
	label.tree_entered.connect(func() -> void:
		var tween := label.create_tween()
		tween.set_parallel(true)
		tween.tween_property(label, "position", label.position + Vector2(0, -16), 0.55)
		tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.15)
		tween.chain().tween_callback(label.queue_free))
	tree.current_scene.add_child.call_deferred(label)


static func poof(ctx: Node, pos: Vector2, color := Color(0.5, 0.85, 0.9)) -> void:
	var tree := ctx.get_tree()
	if tree == null or tree.current_scene == null:
		return
	if tree.get_nodes_in_group("fx_poof").size() >= MAX_POOFS:
		return
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.amount = 8
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 70.0
	particles.gravity = Vector2(0, -25)  # debris drifts up, we're underwater
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.color = color
	particles.position = pos
	particles.add_to_group("fx_poof")
	tree.current_scene.add_child.call_deferred(particles)
	tree.create_timer(0.8).timeout.connect(particles.queue_free)


## Shake the local player's camera if they're within range of the impact.
static func shake_near(ctx: Node, pos: Vector2, radius: float, amount: float) -> void:
	var tree := ctx.get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("players"):
		if p.is_local() and p.global_position.distance_to(pos) <= radius:
			p.shake(amount)
