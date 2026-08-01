extends Node
## Session/network manager (autoload "Net").
##
## Solo play uses the default OfflineMultiplayerPeer so the exact same
## server-authoritative code paths run everywhere — including the web build,
## where ENet is unavailable. Online co-op (desktop builds) hosts an ENet
## server; browser co-op will arrive later via WebRTC + signaling (M2).

signal status_changed(text: String)
signal player_count_changed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var is_online := false
var in_game := false


func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id: int) -> void: player_count_changed.emit())
	multiplayer.peer_disconnected.connect(func(_id: int) -> void: player_count_changed.emit())
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_solo() -> void:
	_reset_peer()
	is_online = false
	_change_to_game()


func host_game() -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS - 1)
	if err != OK:
		status_changed.emit("Failed to host (is port %d already in use?)" % DEFAULT_PORT)
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	status_changed.emit("Hosting on port %d — waiting for divers..." % DEFAULT_PORT)
	player_count_changed.emit()
	return OK


func join_game(address: String) -> Error:
	_reset_peer()
	if address.strip_edges().is_empty():
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), DEFAULT_PORT)
	if err != OK:
		status_changed.emit("Invalid address: %s" % address)
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	status_changed.emit("Connecting to %s..." % address)
	return OK


## Host only: lock the lobby and move everyone into the game scene.
func start_dive() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.refuse_new_connections = true
	_rpc_change_to_game.rpc()


## Leave the current session (or game-over screen) and return to the menu.
func leave() -> void:
	_reset_peer()
	is_online = false
	in_game = false
	get_tree().change_scene_to_file(MENU_SCENE)


func player_count() -> int:
	return multiplayer.get_peers().size() + 1


@rpc("authority", "call_local", "reliable")
func _rpc_change_to_game() -> void:
	_change_to_game()


func _change_to_game() -> void:
	in_game = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_connected_to_server() -> void:
	status_changed.emit("Connected — waiting for the host to start the dive...")
	player_count_changed.emit()


func _on_connection_failed() -> void:
	_reset_peer()
	is_online = false
	status_changed.emit("Connection failed.")


func _on_server_disconnected() -> void:
	is_online = false
	_reset_peer()
	if in_game:
		leave()
	else:
		status_changed.emit("Host disconnected.")
