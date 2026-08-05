extends CanvasLayer
## The water between the camera and the deck: drifting particulate, and the
## murk that closes in as the crew descends.
##
## Looking straight down, there is nothing *behind* the seabed to parallax
## against — the volume the eye can read is the column above it. So these
## layers sit on a CanvasLayer over the world and scroll FASTER than it: things
## nearer the camera sweep further across the view as the camera pans. A layer
## drifting slower would read as beneath the floor, which is nowhere.
##
## Entirely local and cosmetic. Nothing here is simulated or replicated, so
## peers drifting a frame apart has no consequence.

const NEAR_TEXTURE := preload("res://assets/sprites/motes_near.png")
const FAR_TEXTURE := preload("res://assets/sprites/motes_far.png")

# Parallax factors: >1 means nearer the camera than the deck.
const NEAR_FACTOR := 1.55
const FAR_FACTOR := 1.2
# A slow current, so the water still breathes when nobody is moving.
const NEAR_DRIFT := Vector2(-7.0, 3.5)
const FAR_DRIFT := Vector2(-3.0, 1.5)

# Lighter than it was: with the ambient crushed for light-based visibility the
# dark already does most of this job, and a heavy vignette on top just fights
# the lamp.
const HAZE_NEAR := Color(0.03, 0.07, 0.10)  # colour of the closing dark
const HAZE_MIN_ALPHA := 0.14  # vignette at the surface
const HAZE_MAX_ALPHA := 0.34  # vignette deep down
const HAZE_DEPTH_SPAN := 8.0  # depths over which the murk thickens

var _near: Sprite2D
var _far: Sprite2D
var _haze: TextureRect
var _view := Vector2.ZERO
var _elapsed := 0.0


func _ready() -> void:
	_view = get_viewport().get_visible_rect().size
	_far = _build_layer(FAR_TEXTURE, _view)
	_near = _build_layer(NEAR_TEXTURE, _view)
	_haze = _build_haze(_view)
	set_depth(1)


func _process(delta: float) -> void:
	_elapsed += delta
	# The active camera belongs to whichever diver is ours, so ask the viewport
	# rather than reaching into the player — this also survives the diver dying.
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var eye := camera.get_screen_center_position()
	# Whole Rect2 rewritten rather than poking .position: assigning through two
	# levels of value type is the kind of thing that silently does nothing.
	_far.region_rect = Rect2(eye * FAR_FACTOR + FAR_DRIFT * _elapsed, _view)
	_near.region_rect = Rect2(eye * NEAR_FACTOR + NEAR_DRIFT * _elapsed, _view)


## Thicken the murk as the crew descends. Called on every peer from the site
## build, so clients dim in step with the host.
func set_depth(depth: int) -> void:
	if _haze == null:
		return
	var sink := clampf((depth - 1) / HAZE_DEPTH_SPAN, 0.0, 1.0)
	_haze.modulate.a = lerpf(HAZE_MIN_ALPHA, HAZE_MAX_ALPHA, sink)


func _build_layer(texture: Texture2D, view: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	# Region + repeat is what lets one small tile cover the screen and scroll:
	# moving the region's origin slides the pattern without moving the node.
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, view)
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(sprite)
	return sprite


func _build_haze(view: Vector2) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(HAZE_NEAR, 0.0))
	gradient.set_color(1, Color(HAZE_NEAR, 1.0))
	# Hold the centre clear so the murk only closes in around the edges of
	# vision, rather than veiling the diver's own lamp.
	gradient.add_point(0.55, Color(HAZE_NEAR, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 160
	texture.height = 90
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = view
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect
