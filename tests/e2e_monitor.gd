extends Node
## WebRTC end-to-end monitor. Parented to /root (not the current scene) so it
## survives the menu -> game scene change. The host creates an online room and
## prints E2E_ROOM=<code>; the client joins via the E2E_ROOM env var; once
## in-game, each side verifies both players spawned and enemies replicate,
## then prints E2E_<ROLE>_OK for the orchestrating script to grep.

var role := "host"

var _game: Node2D
var _checked := false
var _quitting := false


func _ready() -> void:
	Net.status_changed.connect(func(t: String) -> void: print("[e2e-%s] %s" % [role, t]))
	Net.entered_lobby.connect(_on_lobby)
	multiplayer.peer_connected.connect(_on_peer_connected)
	if role == "host":
		Net.host_online()
	else:
		var code := OS.get_environment("E2E_ROOM")
		print("[e2e-client] joining room %s" % code)
		Net.join_online(code)


func _on_lobby(room: String, is_host: bool) -> void:
	if is_host:
		print("E2E_ROOM=%s" % room)


func _on_peer_connected(id: int) -> void:
	print("[e2e-%s] peer_connected %d" % [role, id])
	if role == "host" and multiplayer.is_server():
		await get_tree().create_timer(1.5).timeout
		print("[e2e-host] starting dive")
		Net.start_dive()


func _process(_delta: float) -> void:
	if _checked:
		_maybe_quit()
		return
	var cs := get_tree().current_scene
	if cs == null or cs.name != "Game":
		return
	_game = cs
	# `elapsed` mirrors to clients via the HUD rpc, so >= 8s proves live
	# server->client state flow, not just the initial spawn.
	if _game.elapsed >= 8.0:
		_checked = true
		var player_count: int = _game.players.get_child_count()
		var enemy_count: int = _game.enemies.get_child_count()
		print("[e2e-%s] players=%d enemies=%d elapsed=%.1f" % [role, player_count, enemy_count, _game.elapsed])
		if player_count == 2 and enemy_count > 0:
			print("E2E_%s_OK" % role.to_upper())
		else:
			print("E2E_%s_FAIL" % role.to_upper())
		if role == "client":
			_quit_soon()


func _maybe_quit() -> void:
	# The host outlives the client so the room doesn't tear down while the
	# client is still verifying; it leaves once the client disconnects.
	if role == "host" and not _quitting and multiplayer.get_peers().is_empty():
		_quit_soon()


func _quit_soon() -> void:
	if _quitting:
		return
	_quitting = true
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
