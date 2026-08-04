extends Node
## WebRTC end-to-end monitor. Parented to /root (not the current scene) so it
## survives scene changes. The host creates an online room and prints
## E2E_ROOM=<code>; the client joins via the E2E_ROOM env var.
##
## Two runs are verified to cover the post-game lobby-retry flow:
##   run 1 in-game checks   -> E2E_<ROLE>_OK
##   host: return_to_lobby  -> both peers land back in the menu, room intact
##   host: start_dive again -> run 2 in-game checks -> E2E_<ROLE>_RETRY_OK

var role := "host"

var _phase := "run1"
var _evaluated := false  # one verification per run phase
var _quitting := false


func _ready() -> void:
	Net.status_changed.connect(func(t: String) -> void: print("[e2e-%s] %s" % [role, t]))
	Net.entered_lobby.connect(_on_lobby)
	multiplayer.peer_connected.connect(_on_peer_connected)
	if role == "host":
		Net.host_online()
	else:
		# Dive as a non-default kit so the host-side check proves diver kits
		# replicate through the meta handshake (test-only forced unlock).
		Station.unlocked_divers = [Divers.DEFAULT, "lancer"]
		Station.diver = "lancer"
		var code := OS.get_environment("E2E_ROOM")
		print("[e2e-client] joining room %s" % code)
		Net.join_online(code)


func _on_lobby(room: String, is_host: bool) -> void:
	if is_host:
		print("E2E_ROOM=%s" % room)


func _on_peer_connected(id: int) -> void:
	print("[e2e-%s] peer_connected %d" % [role, id])
	if role == "host" and multiplayer.is_server() and _phase == "run1" and not Net.in_game:
		await get_tree().create_timer(1.5).timeout
		print("[e2e-host] starting dive")
		Net.start_dive()


func _process(_delta: float) -> void:
	match _phase:
		"run1":
			if _run_verified(8.0):
				print("E2E_%s_OK" % role.to_upper())
				_phase = "lobby"
				if role == "host":
					_return_crew_to_lobby()
		"lobby":
			var cs := get_tree().current_scene
			if cs != null and cs.name == "MainMenu":
				print("[e2e-%s] back in lobby, session alive=%s room=%s" % [role, Net.is_online, Net.room_code])
				_phase = "run2"
				_evaluated = false
				if role == "host":
					_start_second_dive()
		"run2":
			if _run_verified(5.0):
				print("E2E_%s_RETRY_OK" % role.to_upper())
				_phase = "done"
				if role == "client":
					_quit_soon()
		"done":
			# The host outlives the client so the room doesn't tear down
			# while the client is still verifying.
			if role == "host" and not _quitting and multiplayer.get_peers().is_empty():
				_quit_soon()


## Evaluates once per run, when the game scene's `elapsed` (mirrored over
## the network on clients) passes the threshold: both players spawned and
## enemies replicating.
func _run_verified(min_elapsed: float) -> bool:
	if _evaluated:
		return false
	var cs := get_tree().current_scene
	if cs == null or cs.name != "Game":
		return false
	if cs.elapsed < min_elapsed:
		return false
	_evaluated = true
	var player_count: int = cs.players.get_child_count()
	var enemy_count: int = cs.enemies.get_child_count()
	print("[e2e-%s] players=%d enemies=%d elapsed=%.1f" % [role, player_count, enemy_count, cs.elapsed])
	if _phase == "run1":
		# Terrain determinism fingerprint: both peers must have built the
		# exact same rock count from the broadcast seed (compared by the
		# orchestrating script).
		print("[e2e-%s] terrain_cells=%d ore_cells=%d" % [
				role, cs.terrain_initial_cells, cs.terrain_initial_ore])
	if role == "host" and _phase == "run1":
		# The client dives as the Lancer; its kit must exist on OUR copy of
		# its player node (spawn-data meta replication).
		for p in cs.players.get_children():
			if p is Player and p.peer_id != 1:
				print("E2E_KIT_%s" % ("OK" if p.weapons.has("lance") else "FAIL"))
	return player_count == 2 and enemy_count > 0


func _return_crew_to_lobby() -> void:
	# Give the client time to finish its own run-1 verification first.
	await get_tree().create_timer(3.0).timeout
	print("[e2e-host] returning crew to lobby")
	Net.return_to_lobby()


func _start_second_dive() -> void:
	await get_tree().create_timer(2.0).timeout
	print("[e2e-host] starting second dive")
	Net.start_dive()


func _quit_soon() -> void:
	if _quitting:
		return
	_quitting = true
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
