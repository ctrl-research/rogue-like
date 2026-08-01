extends Node
## Self-playing smoke-test harness: runs the game scene solo with random
## movement and auto-picked level-up upgrades, so headless CI exercises
## combat, weapon unlocks, pickups, and the offer/pick flow. Run with:
##
##   godot --headless --path . --quit-after 6000 tests/headless_sim.tscn

const GAME_SCENE := preload("res://scenes/game.tscn")
const ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]

var _game: Node2D
var _player: Player
var _steer_cd := 0.0
var _status_cd := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Keep the sim's banked salvage out of the developer's real save.
	Station._save_path = "user://station_sim.json"
	Station.bank = 0
	Station.levels = {}
	_rng.randomize()
	_game = GAME_SCENE.instantiate()
	add_child(_game)


func _process(delta: float) -> void:
	if _player == null:
		_wire_player()
		return
	_status_cd -= delta
	if _status_cd <= 0.0:
		_status_cd = 10.0
		print("[sim] t=%3ds hp=%d/%d downed=%s dead=%s lv=%d xp=%d/%d enemies=%d over=%s" % [
			int(_game.elapsed), int(_player.hp), int(_player.max_hp), _player.downed,
			_player.dead, _game.team_level, _game.team_xp, _game.xp_needed,
			_game.enemies.get_child_count(), _game.game_over,
		])
	_steer_cd -= delta
	if _steer_cd <= 0.0:
		_steer_cd = 0.2
		_steer()
	# The bot is a poor crate courier, so after a grace period the harness
	# collects crates server-side (one per tick) to deterministically reach
	# the bell -> descend -> extract loop.
	if multiplayer.is_server() and _game.crates_left > 0 and _game.elapsed > 20.0 * _game.depth:
		for c in get_tree().get_nodes_in_group("crates"):
			if not c.is_queued_for_deletion():
				_game.on_crate_collected()
				c.queue_free()
				break

	# Exercise both bell outcomes: descend once, extract from depth 2.
	if _game.awaiting_choice and multiplayer.is_server():
		if _game.depth == 1:
			print("[sim] bell secured -> descending")
			_game.choose_descend()
		else:
			print("[sim] bell secured -> extracting with %d salvage (bank=%d)" % [
				_game.salvage_earned, Station.bank])
			_game.choose_extract()


## Kite like a (mediocre) player: flee nearby enemies, drift toward gems,
## work the objective (crates, then the bell), otherwise wander. Enough to
## survive, level, and sometimes complete sites so the descend/extract flow
## gets exercised.
func _steer() -> void:
	var pos := _player.global_position
	var dir := Vector2.ZERO
	var threat := _nearest_in_group("enemies", pos, 90.0)
	if threat != null:
		dir -= (threat.global_position - pos).normalized() * 1.5
	var gem := _nearest_in_group("gems", pos, 180.0)
	if gem != null:
		dir += (gem.global_position - pos).normalized()
	var obj_group: String = "crates" if _game.crates_left > 0 else "bell"
	var objective := _nearest_in_group(obj_group, pos, INF)
	if objective != null:
		var weight := 0.8
		if obj_group == "bell" and pos.distance_to(objective.global_position) < 60.0:
			dir = Vector2.ZERO  # commit: hold the bell even under fire
			weight = 2.5
		dir += (objective.global_position - pos).normalized() * weight
	if dir.length() < 0.2:
		dir = Vector2.from_angle(_rng.randf() * TAU)
	# Steer away from arena edges so fleeing doesn't pin the bot in a corner.
	var margin := 120.0
	if pos.x < margin:
		dir.x += 1.0
	elif pos.x > GameRules.ARENA_SIZE.x - margin:
		dir.x -= 1.0
	if pos.y < margin:
		dir.y += 1.0
	elif pos.y > GameRules.ARENA_SIZE.y - margin:
		dir.y -= 1.0
	for a in ACTIONS:
		Input.action_release(a)
	if dir.x < -0.3:
		Input.action_press("move_left")
	elif dir.x > 0.3:
		Input.action_press("move_right")
	if dir.y < -0.3:
		Input.action_press("move_up")
	elif dir.y > 0.3:
		Input.action_press("move_down")


func _nearest_in_group(group: String, pos: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist * max_dist
	for n in get_tree().get_nodes_in_group(group):
		var node := n as Node2D
		var d := pos.distance_squared_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _wire_player() -> void:
	for p in _game.players.get_children():
		if p is Player and p.peer_id == multiplayer.get_unique_id():
			_player = p
			_player.upgrade_offered.connect(_on_offer)
			return


func _on_offer(options: Array) -> void:
	await get_tree().create_timer(0.3).timeout
	if not options.is_empty() and is_instance_valid(_player):
		var pick: String = options[_rng.randi() % options.size()]
		print("[sim] offered %s -> picked %s (weapons=%s passives=%s)" % [
			options, pick, _player.weapons, _player.passives,
		])
		_player.request_pick(pick)
