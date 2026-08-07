class_name LampTexture
## Crisp lamp discs, built at exactly the size they will be drawn.
##
## The lamp used one 128px light.png scaled to reach: `texture_scale = reach /
## 63.5`. That scale is fractional — 136px of reach is 2.142x — so even with a
## hard-edged source and nearest filtering, some source pixels landed on two
## screen pixels and others on three, unevenly around a curve, none of them on
## the game's pixel grid. Every edge was technically hard and the result still
## read as soft.
##
## Generating the disc at 1:1 and leaving texture_scale at 1.0 means one texture
## pixel is one game pixel, so the stepped edge lands on the same grid as the
## 16px sprites it sits under.
##
## Reach changes only on a descent or an upgrade, and identical reaches share a
## texture, so this builds a handful of images per run rather than one per frame.

## Matches the bands gen_pixel_art.gen_light() drew, as fractions of the radius:
## the light still falls off toward the rim, in steps you can count.
const BANDS: Array[Array] = [
	[1.00, 0.52],
	[0.87, 0.80],
	[0.63, 1.00],
]
const TINT := Color(1.0, 0.96, 0.86)
## Below this the disc is too small to show bands; above it, larger than any
## reach GameRules can produce (base + every upgrade).
const MIN_RADIUS := 8
const MAX_RADIUS := 512

static var _cache := {}


## The disc for a given reach in pixels. Cached, so four divers at the same reach
## share one image.
static func for_radius(radius: int) -> ImageTexture:
	var r := clampi(radius, MIN_RADIUS, MAX_RADIUS)
	if _cache.has(r):
		return _cache[r]
	var tex := ImageTexture.create_from_image(_build(r))
	_cache[r] = tex
	return tex


static func _build(r: int) -> Image:
	var size := r * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(TINT.r, TINT.g, TINT.b, 0.0))
	# Centre on the pixel grid: for an even width the middle sits between the two
	# central pixels, and rounding it to one of them would make the disc lopsided.
	var centre := (float(size) - 1.0) / 2.0
	# Filled as horizontal runs from the circle equation rather than per pixel:
	# three fill_rect calls per row instead of `size` set_pixel calls, which keeps
	# even the largest disc to a few thousand operations instead of ~450k.
	for y in size:
		var dy := float(y) - centre
		for band in BANDS:
			var band_r := float(band[0]) * float(r)
			var span := band_r * band_r - dy * dy
			if span <= 0.0:
				continue  # this row is outside this band entirely
			var half := sqrt(span)
			# Inclusive endpoints, both derived from the centre: a pixel is inside
			# when its centre is within `half` of the disc's. Rounding a start and
			# a width independently biases one side and produced a disc that was
			# visibly lopsided left-to-right.
			var x0 := int(ceil(centre - half))
			var x1 := int(floor(centre + half))
			if x1 < x0:
				continue
			x0 = clampi(x0, 0, size - 1)
			x1 = clampi(x1, 0, size - 1)
			var width := x1 - x0 + 1
			# Bands run widest first, so each narrower, brighter band overwrites
			# the middle of the one before it.
			img.fill_rect(Rect2i(x0, y, width, 1),
					Color(TINT.r, TINT.g, TINT.b, float(band[1])))
	return img
