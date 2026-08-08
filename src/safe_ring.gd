extends Node2D
## The pulsing dashed ring marking the bell's safe zone.
##
## A child of the bell rather than something the game spawns, so it appears on every
## peer the moment the bell does and cannot drift out of sync with it — the ring has to
## agree with GameRules.BELL_SAFE_RADIUS exactly, because that is the same number the
## movement clamp and the damage check use. A ring that lied about where safety ended
## would be worse than no ring at all.

## Dashes, not a solid circle: a solid ring reads as a wall, and this is a threshold.
const DASHES := 28
## Fraction of each dash segment that is drawn rather than gap.
const DASH_FILL := 0.55
const WIDTH := 1.0
const COLOR := Color(0.62, 0.9, 1.0)
## Pulse bounds. Kept narrow — this sits under a diver during a lull, so it should
## breathe rather than flash.
const ALPHA_MIN := 0.30
const ALPHA_MAX := 0.70
const PULSE_HZ := 0.6
## Very slight rotation, so the dashes read as alive without drawing the eye.
const SPIN := 0.25

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var radius := GameRules.BELL_SAFE_RADIUS
	# sin is -1..1; remapped so the pulse spends equal time either side of centre.
	var pulse := 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	var col := COLOR
	col.a = lerpf(ALPHA_MIN, ALPHA_MAX, pulse)
	var spin := _t * SPIN
	var step := TAU / float(DASHES)
	for i in DASHES:
		var start := spin + step * float(i)
		draw_arc(Vector2.ZERO, radius, start, start + step * DASH_FILL,
				6, col, WIDTH, false)
