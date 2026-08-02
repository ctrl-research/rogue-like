extends Node
## Sound playback (autoload "Sfx"). All effects are procedurally generated
## WAVs (tools/gen_sfx.py). A lowpass on the Master bus sells "underwater".
##
## Everything here is local-only cosmetics: callers trigger sounds from
## already-replicated state, so peers stay in sync for free.

# Loaded at runtime (not preload): during the very first editor import the
# wavs aren't imported yet when autoload scripts get parsed, and a preload
# there is a hard parse error that fails CI.
const NAMES: Array[String] = [
	"shoot", "hit", "kill", "pickup", "crate", "levelup", "explosion",
	"sonar", "downed", "revive", "bell", "extract", "defeat", "warning",
]

const MAX_VOICES := 24

var _streams := {}
var _ambient: AudioStreamPlayer


func _ready() -> void:
	for name in NAMES:
		_streams[name] = load("res://assets/sfx/%s.wav" % name)

	# Underwater: everything below ~2.4kHz, gentle.
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 2400.0
	AudioServer.add_bus_effect(0, lowpass)

	_ambient = AudioStreamPlayer.new()
	_ambient.stream = load("res://assets/sfx/ambient.wav")
	_ambient.volume_db = -14.0
	_ambient.finished.connect(_ambient.play)  # seamless-enough loop
	add_child(_ambient)
	_ambient.play()


## Non-positional UI/global cue.
func play(name: String, volume_db := -6.0, pitch_jitter := 0.06) -> void:
	if _voices() >= MAX_VOICES:
		return
	var p := AudioStreamPlayer.new()
	_setup(p, name, volume_db, pitch_jitter)


## Positional world cue (2D falloff around the listener).
func play_at(name: String, pos: Vector2, volume_db := -3.0, pitch_jitter := 0.08) -> void:
	if _voices() >= MAX_VOICES:
		return
	var p := AudioStreamPlayer2D.new()
	p.position = pos  # parent is a plain Node, so position == world coords
	p.max_distance = 480.0
	p.attenuation = 1.4
	_setup(p, name, volume_db, pitch_jitter)


func _setup(p: Node, name: String, volume_db: float, pitch_jitter: float) -> void:
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.add_to_group("sfx_voice")
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func _voices() -> int:
	return get_tree().get_nodes_in_group("sfx_voice").size()
