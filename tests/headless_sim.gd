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
var _bell_wait := 0.0
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
		print("[sim] t=%3ds hp=%d/%d lv=%d xp=%d/%d enemies=%d depth=%d crates=%d haul=%d choice=%s over=%s" % [
			int(_game.elapsed), int(_player.hp), int(_player.max_hp),
			_game.team_level, _game.team_xp, _game.xp_needed,
			_game.enemies.get_child_count(), _game.depth, _game.crates_left,
			_game.salvage_earned, _game.awaiting_choice, _game.game_over,
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

	# If the bot can't fight its way onto the bell (the Maw camps it), warp
	# it there so the descend/extract flow still gets exercised.
	if multiplayer.is_server() and _game.crates_left == 0 and not _game.awaiting_choice \
			and not _game.game_over:
		_bell_wait += delta
		if _bell_wait > 25.0 and not _player.dead and not _player.downed:
			var bell := _nearest_in_group("bell", _player.global_position, INF)
			if bell != null:
				_player.teleport(bell.global_position)
	else:
		_bell_wait = 0.0

	# Exercise both bell outcomes: descend twice (deeper spawn table:
	# lurkers, jellies, the Maw), then extract from depth 3.
	if _game.awaiting_choice and multiplayer.is_server():
		if _game.depth < 3:
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
	var obj_group: String = "crates" if _game.crates_left > 0 else "bell"
	var objective := _nearest_in_group(obj_group, pos, INF)
	var threat := _nearest_in_group("enemies", pos, 90.0)
	# Flee is suppressed near the bell — the Maw guards it, and a bot that
	# always flees never extracts.
	var flee_weight := 0.5 if obj_group == "bell" else 1.5
	if threat != null:
		dir -= (threat.global_position - pos).normalized() * flee_weight
	var gem := _nearest_in_group("gems", pos, 180.0)
	if gem != null:
		dir += (gem.global_position - pos).normalized()
	if objective != null:
		var weight := 0.8
		if obj_group == "bell" and pos.distance_to(objective.global_position) < 130.0:
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
			# Preload a maxed harpoon + magnet so the evolution card (and the
			# chain-harpoon behavior) is exercised from the first level-up,
			# plus a drill so wandering into rock exercises destruction.
			_player.weapons["harpoon"] = GameRules.WEAPON_MAX_LEVEL
			_player.weapons["drill"] = 1
			_player.passives["magnet"] = 1
			return


func _on_offer(options: Array) -> void:
	await get_tree().create_timer(0.3).timeout
	if not options.is_empty() and is_instance_valid(_player):
		var pick: String = options[_rng.randi() % options.size()]
		if str(options[0]).begins_with("evolve_"):
			pick = options[0]  # always take the jackpot card
		print("[sim] offered %s -> picked %s (weapons=%s passives=%s)" % [
			options, pick, _player.weapons, _player.passives,
		])
		_player.request_pick(pick)
