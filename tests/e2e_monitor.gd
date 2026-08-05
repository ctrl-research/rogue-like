extends Node
## WebRTC end-to-end monitor. Parented to /root (not the current scene) so it
## survives scene changes. The host creates an online room and prints
## E2E_ROOM=<code>; the client joins via the E2E_ROOM env var.
##
## Two runs are verified to cover the post-game lobby-retry flow:
##   run 1 in-game checks   -> E2E_<ROLE>_OK
##   host: return_to_lobby  -> both peers land back aboard the sub, room intact
##   host: start_dive again -> run 2 in-game checks -> E2E_<ROLE>_RETRY_OK

var role := "host"

var _phase := "run1"
var _evaluated := false  # one verification per run phase
var _quitting := false
var _saw_downed := false  # client: its diver was reported down
var _revive_reported := false


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
				_phase = "revive"
				if role == "host":
					_run_revive_drill()
		"revive":
			# The client watches its OWN diver go down and come back, which is
			# the half of this that proves the state replicated. The host drives
			# the drill and reports separately. Falls through to the lobby when
			# the host brings the crew back up.
			if role == "client":
				_watch_own_revive()
			var cs := get_tree().current_scene
			if cs != null and cs.name == "Sub":
				print("[e2e-%s] back aboard the sub, session alive=%s room=%s" % [role, Net.is_online, Net.room_code])
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


## Host: put the client's diver down, walk ours over, and assert it gets back
## up. Revive is inherently two-player — the solo sim can't reach it at all
## (_go_down kills a lone diver outright), and the sim's survival assist means
## unlucky runs no longer stumble into it either. So this is the only place the
## co-op mechanic gets tested.
func _run_revive_drill() -> void:
	# Let the client finish its own run-1 verification first. It evaluates from
	# its synced `elapsed`, so it lands a moment after the host does — and it
	# checks enemies are replicating, once. Clearing the arena below before that
	# happens fails that check permanently and the client never gets past run 1.
	await get_tree().create_timer(3.0).timeout
	var cs := get_tree().current_scene
	var casualty: Player = null
	var rescuer: Player = null
	for p in cs.players.get_children():
		if p is Player:
			if p.peer_id == 1:
				rescuer = p
			else:
				casualty = p
	if casualty == null or rescuer == null:
		print("E2E_REVIVE_FAIL: expected two divers")
		_return_crew_to_lobby()
		return

	# Clear the arena first. A downed diver holds 40% hull and bleeds slowly,
	# but fauna chewing on it deal ~10hp/s and would kill it mid-drill — which
	# would look like a revive failure (or worse, a pass, since a dead diver is
	# also "not downed").
	for e in cs.enemies.get_children():
		e.queue_free()

	# Park the rescuer out of range first, so revive progress can't start by
	# accident and pass this test for the wrong reason.
	rescuer.teleport.rpc(casualty.global_position + Vector2(240, 0))
	await get_tree().create_timer(0.5).timeout
	print("[e2e-host] putting the client's diver down")
	casualty._go_down()
	await get_tree().create_timer(1.0).timeout
	if not casualty.downed:
		print("E2E_REVIVE_FAIL: diver did not go down")
		_return_crew_to_lobby()
		return
	if casualty.revive_progress > 0.0:
		print("E2E_REVIVE_FAIL: reviving with no rescuer in range")
		_return_crew_to_lobby()
		return

	print("[e2e-host] rescuer closing in")
	rescuer.teleport.rpc(casualty.global_position + Vector2(10, 0))
	# Polled rather than a flat sleep, so this also asserts the revive lands
	# inside a bound and cuts the window where a fresh wave could reach us.
	var deadline := GameRules.REVIVE_TIME + 3.0
	var waited := 0.0
	while waited < deadline and casualty.downed and not casualty.dead:
		await get_tree().process_frame
		waited += get_process_delta_time()
	# A dead diver is also "not downed" — check it explicitly, or bleeding out
	# mid-drill would report as a successful revive.
	if casualty.dead:
		print("E2E_REVIVE_FAIL: diver died before the revive landed")
	elif casualty.downed:
		print("E2E_REVIVE_FAIL: still down after %.1fs (progress %.2f)" % [
			waited, casualty.revive_progress])
	else:
		print("[e2e-host] revived in %.1fs" % waited)
		print("E2E_HOST_REVIVE_OK")
	_return_crew_to_lobby()


## Client: its own diver going down and standing back up, observed purely from
## replicated state — no local logic involved.
func _watch_own_revive() -> void:
	var cs := get_tree().current_scene
	if cs == null or cs.name != "Game" or _revive_reported:
		return
	for p in cs.players.get_children():
		if p is Player and p.peer_id == multiplayer.get_unique_id():
			if p.downed:
				_saw_downed = true
			elif _saw_downed:
				_revive_reported = true
				print("E2E_CLIENT_REVIVE_OK")
			return


func _return_crew_to_lobby() -> void:
	# Short pause so the client can log its revive observation before the scene
	# changes underneath it. The wait that protects run-1 verification now lives
	# at the top of the revive drill, which runs before this.
	await get_tree().create_timer(1.0).timeout
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
