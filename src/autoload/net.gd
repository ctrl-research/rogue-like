extends Node
## Session/network manager (autoload "Net").
##
## Three transports, one game:
##  - OFFLINE: solo. Default OfflineMultiplayerPeer, so the same
##    server-authoritative code paths run everywhere (including web).
##  - ENET: desktop LAN / direct-IP co-op (host is the server).
##  - WEBRTC: online co-op via room codes. A signaling broker (signaling/)
##    brokers the handshake, then traffic is peer-to-peer. The broker gives
##    the host peer id 1, so multiplayer.is_server() works unchanged. Works
##    in the browser build.

signal status_changed(text: String)
signal player_count_changed
signal entered_lobby(room_code: String, is_host: bool)
signal session_ended  # emitted when the session dies while sitting in a menu/lobby

enum Mode { OFFLINE, ENET, WEBRTC }

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const SUB_SCENE := "res://scenes/sub.tscn"  # the walkable lobby/homebase

var mode := Mode.OFFLINE
var is_online := false
var in_game := false
var room_code := ""

var _signaling := SignalingClient.new()


func _ready() -> void:
	add_child(_signaling)
	_signaling.lobby_joined.connect(_on_lobby_joined)
	_signaling.failed.connect(_on_signaling_failed)
	multiplayer.peer_connected.connect(func(_id: int) -> void: player_count_changed.emit())
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func webrtc_available() -> bool:
	return SignalingClient.webrtc_available()


## Solo divers board the sub too — the hatch starts the actual dive.
func start_solo() -> void:
	_reset_peer()
	get_tree().change_scene_to_file(SUB_SCENE)


# --- Online (WebRTC room codes) --------------------------------------------


func host_online() -> void:
	_reset_peer()
	if _signaling.start("") == OK:
		status_changed.emit("Contacting dive control...")


func join_online(code: String) -> void:
	_reset_peer()
	if code.strip_edges().is_empty():
		status_changed.emit("Enter a room code to join.")
		return
	if _signaling.start(code) == OK:
		status_changed.emit("Contacting dive control...")


func _on_lobby_joined(_peer_id: int, room: String, is_host: bool) -> void:
	multiplayer.multiplayer_peer = _signaling.rtc
	mode = Mode.WEBRTC
	is_online = true
	room_code = room
	if is_host:
		status_changed.emit("Room %s open — share the code!" % room)
	else:
		status_changed.emit("Joined room %s — linking with the crew..." % room)
	entered_lobby.emit(room, is_host)
	player_count_changed.emit()


func _on_signaling_failed(reason: String) -> void:
	if mode == Mode.WEBRTC or not is_online:
		_reset_peer()
		status_changed.emit(reason)


# --- LAN (ENet) -------------------------------------------------------------


func host_lan() -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS - 1)
	if err != OK:
		status_changed.emit("Failed to host (is port %d already in use?)" % DEFAULT_PORT)
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.ENET
	is_online = true
	status_changed.emit("Hosting on port %d — waiting for divers..." % DEFAULT_PORT)
	entered_lobby.emit("", true)
	player_count_changed.emit()
	return OK


func join_lan(address: String) -> Error:
	_reset_peer()
	if address.strip_edges().is_empty():
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), DEFAULT_PORT)
	if err != OK:
		status_changed.emit("Invalid address: %s" % address)
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.ENET
	is_online = true
	status_changed.emit("Connecting to %s..." % address)
	entered_lobby.emit("", false)
	return OK


# --- Shared lifecycle --------------------------------------------------------


## Host only: lock the lobby and move everyone into the game scene. The host
## loads its own scene FIRST and only then tells clients: their game scene's
## ready-handshake rpc targets /root/Game on the server, and Godot drops
## rpcs whose target node doesn't exist yet.
func start_dive() -> void:
	if not multiplayer.is_server():
		return
	match mode:
		Mode.ENET:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				multiplayer.multiplayer_peer.refuse_new_connections = true
		Mode.WEBRTC:
			_signaling.seal()
	_change_to_game()
	await get_tree().process_frame
	await get_tree().process_frame
	_rpc_change_to_game.rpc()


## Host only: bring the whole crew back to the lobby after a run. The room
## stays open (and reopens to new joiners) until the host disbands it.
func return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	await _despawn_game_nodes()
	match mode:
		Mode.ENET:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				multiplayer.multiplayer_peer.refuse_new_connections = false
		Mode.WEBRTC:
			_signaling.unseal()
	_rpc_return_to_lobby.rpc()


## Host only: close the room for everyone.
func close_room() -> void:
	if not multiplayer.is_server():
		return
	await _despawn_game_nodes()
	_rpc_room_closed.rpc()
	# Let the rpc flush before tearing down the transport.
	await get_tree().create_timer(0.3).timeout
	leave()


## Replicate despawns for all game nodes while every peer still has the
## game scene, so the scene change that follows is silent on the network.
func _despawn_game_nodes() -> void:
	var cs := get_tree().current_scene
	if cs != null and cs.has_method("despawn_all"):
		cs.despawn_all()
		await get_tree().create_timer(0.25).timeout


@rpc("authority", "call_local", "reliable")
func _rpc_return_to_lobby() -> void:
	in_game = false
	get_tree().change_scene_to_file(SUB_SCENE)


@rpc("authority", "reliable")
func _rpc_room_closed() -> void:
	leave()


## Leave the current session (or game-over screen) and return to the menu.
func leave() -> void:
	_reset_peer()
	get_tree().change_scene_to_file(MENU_SCENE)


func player_count() -> int:
	return multiplayer.get_peers().size() + 1


# --- Sub (lobby) channel -----------------------------------------------------
## Peers enter and leave the sub at different moments — start_dive() moves the
## host into the game scene BEFORE telling the crew, so for a few frames a
## client is still walking the sub while the host is already diving. RPCs
## addressed to a node inside the sub scene would land on a peer that no
## longer has it ("node not found", and the same for synchronizer traffic), so
## the sub's roster and movement ride this autoload instead: a path that
## always exists. Peers no longer aboard simply have nothing connected to
## these signals, so the message is dropped harmlessly.

signal sub_aboard_received(pid: int, diver_id: String)
signal sub_roster_received(roster: Dictionary)
signal sub_pos_received(pid: int, pos: Vector2)


## Client -> host: "I'm aboard, diving as this class."
@rpc("any_peer", "reliable")
func sub_aboard(diver_id: String) -> void:
	sub_aboard_received.emit(multiplayer.get_remote_sender_id(), diver_id)


## Host -> everyone: the authoritative pid -> diver_id roster.
@rpc("authority", "call_local", "reliable")
func sub_roster(roster: Dictionary) -> void:
	sub_roster_received.emit(roster)


## Anyone -> everyone: where my diver is standing (movement is owner-driven).
@rpc("any_peer", "unreliable_ordered")
func sub_pos(pos: Vector2) -> void:
	sub_pos_received.emit(multiplayer.get_remote_sender_id(), pos)


@rpc("authority", "reliable")
func _rpc_change_to_game() -> void:
	_change_to_game()


func _change_to_game() -> void:
	in_game = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _reset_peer() -> void:
	_signaling.stop()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	is_online = false
	in_game = false
	room_code = ""


func _on_connected_to_server() -> void:
	status_changed.emit("Connected — waiting for the host to start the dive...")
	player_count_changed.emit()


func _on_connection_failed() -> void:
	_reset_peer()
	status_changed.emit("Connection failed.")


func _on_peer_disconnected(id: int) -> void:
	player_count_changed.emit()
	# In a WebRTC mesh there is no server_disconnected signal — detect the
	# host (peer 1) vanishing ourselves.
	if mode == Mode.WEBRTC and id == 1 and not multiplayer.is_server():
		_on_server_disconnected()


func _on_server_disconnected() -> void:
	var was_in_game := in_game
	_reset_peer()
	if was_in_game:
		leave()
	else:
		status_changed.emit("The host closed the room.")
		session_ended.emit()
