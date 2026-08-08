extends Node
## Session/network manager (autoload "Net").
##
## Three transports, one game:
##  - OFFLINE: solo. Default OfflineMultiplayerPeer, so the same
##    server-authoritative code paths run everywhere (including web).
##  - ENET: desktop LAN / direct-IP co-op (host is the server).
##  - WEBRTC: online co-op via room codes. A signaling broker (signaling/)
##    brokers the handshake, then traffic is peer-to-peer. Being retired in
##    favour of WEBSOCKET — kept until the dedicated server has equivalent
##    test cover, so there is always a working online path.
##  - WEBSOCKET: a dedicated server everyone dials. Clients connect OUTBOUND to
##    one reachable endpoint, which is the whole point: outbound works from
##    behind CGNAT and mobile NAT, so no hole punching and no TURN relay. The
##    server speaks plain ws and TLS terminates at the tunnel in front of it.

signal status_changed(text: String)
signal player_count_changed
signal entered_lobby(room_code: String, is_host: bool)
signal session_ended  # emitted when the session dies while sitting in a menu/lobby

enum Mode { OFFLINE, ENET, WEBRTC, WEBSOCKET }

const DEFAULT_PORT := 7777
const SERVER_PORT := 9100  # dedicated server; ENet LAN keeps 7777
const DEFAULT_SERVER_URL := "ws://localhost:9100"
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const SUB_SCENE := "res://scenes/sub.tscn"  # the walkable lobby/homebase

var mode := Mode.OFFLINE
var is_online := false
var in_game := false
var room_code := ""

var _signaling := SignalingClient.new()
## Crew size, replicated from the server. Deliberately not derived from
## multiplayer.get_peers(): in a client-server topology a client's peer list holds
## only the server, so a derived count would report 2 divers however many are
## aboard — and this number sets enemy counts and HP scaling in game.gd.
var _crew := 1
## Depth the dive was requested at. With a dedicated server no player is the
## server, so the diver who starts the dive sends their own winch depth and the
## server runs with it — see request_dive.
var requested_depth := 1


func _ready() -> void:
	add_child(_signaling)
	_signaling.lobby_joined.connect(_on_lobby_joined)
	_signaling.failed.connect(_on_signaling_failed)
	multiplayer.peer_connected.connect(func(_id: int) -> void:
		player_count_changed.emit()
		_refresh_crew())
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func webrtc_available() -> bool:
	return SignalingClient.webrtc_available()


## Is this process a dedicated server — a host with no diver of its own?
##
## The export preset sets the feature tag; the flag is for running from source
## (`godot --headless -- --dedicated`).
static func is_dedicated() -> bool:
	return OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--dedicated")


## Port the dedicated server listens on: `--port N` in the game's own args (after
## `--`), else PORT from the environment, else the default. The container passes
## both, so either works.
static func dedicated_port() -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--port")
	if at != -1 and at + 1 < args.size() and args[at + 1].is_valid_int():
		return int(args[at + 1])
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		return int(env_port)
	return SERVER_PORT


## Where clients dial. Env override for tests, then the project setting.
static func server_url() -> String:
	var env_url := OS.get_environment("GAME_SERVER_URL")
	if not env_url.is_empty():
		return env_url
	return str(ProjectSettings.get_setting("network/game_server/url", DEFAULT_SERVER_URL))


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


# --- Dedicated server (WebSocket) -------------------------------------------
## WebSocket rather than ENet or WebRTC because the browser is the primary target
## and a browser cannot open a raw socket. It also means the server sits behind the
## same kind of tunnel the signalling hub already uses: TLS terminates there, so
## the container speaks plain ws and carries no certificate.


## The dedicated server itself. One lobby per process.
func host_dedicated(port: int = SERVER_PORT) -> Error:
	_reset_peer()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		status_changed.emit("Failed to listen on port %d." % port)
		push_error("dedicated server could not listen on %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.WEBSOCKET
	is_online = true
	print("[server] listening on ws://0.0.0.0:%d — one lobby, up to %d divers"
			% [port, MAX_PLAYERS])
	status_changed.emit("Listening on port %d." % port)
	_refresh_crew()
	# The server boards the sub too: sub.gd owns the roster and the dive hatch. It
	# simply takes no seat of its own (see _my_seat / _keep_self_aboard there).
	entered_lobby.emit("", true)
	return OK


## A diver joining the dedicated server.
func join_server(url: String = "") -> Error:
	_reset_peer()
	var target := url.strip_edges()
	if target.is_empty():
		target = server_url()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(target)
	if err != OK:
		status_changed.emit("Could not reach the server (%s)." % target)
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.WEBSOCKET
	is_online = true
	status_changed.emit("Connecting to %s..." % target)
	entered_lobby.emit("", false)
	return OK


# --- Shared lifecycle --------------------------------------------------------


## Host only: lock the lobby and move everyone into the game scene. The host
## loads its own scene FIRST and only then tells clients: their game scene's
## ready-handshake rpc targets /root/Game on the server, and Godot drops
## rpcs whose target node doesn't exist yet.
## Any diver may ask for the dive. There is no host player on a dedicated server,
## so gating this on is_server() would leave a crew unable to ever start.
##
## The requester's own winch sets the depth. It cannot be verified — progression is
## client-owned by design (every peer banks its own salvage; see game.gd's
## _rpc_game_over) — so it is clamped rather than trusted. Among friends that is
## the right trade; a competitive game would need server-side progression.
@rpc("any_peer", "reliable")
func request_dive(depth: int) -> void:
	if not multiplayer.is_server():
		return
	requested_depth = depth if GameRules.valid_start_depth(depth) else 1
	start_dive()


func start_dive() -> void:
	if not multiplayer.is_server():
		return
	match mode:
		Mode.ENET, Mode.WEBSOCKET:
			# refuse_new_connections lives on MultiplayerPeer, so this covers both
			# transports; WebRTC needs the broker to seal the room instead.
			if multiplayer.multiplayer_peer != null:
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
		Mode.ENET, Mode.WEBSOCKET:
			if multiplayer.multiplayer_peer != null:
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
## Client-authoritative synchronizers are hushed first — they'd otherwise
## keep streaming into the gap between the host's despawn and the clients'.
func _despawn_game_nodes() -> void:
	var cs := get_tree().current_scene
	if cs == null or not cs.has_method("despawn_all"):
		return
	if cs.has_method("quiesce_sync"):
		cs.quiesce_sync()
		await get_tree().create_timer(0.1).timeout
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


## Crew size as the server sees it, replicated to everyone.
func player_count() -> int:
	return _crew


## Server: recount and tell the crew. A dedicated server excludes itself — it has
## no diver, and counting it would scale the trench's difficulty for a player who
## does not exist.
func _refresh_crew() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var size := multiplayer.get_peers().size() + (0 if is_dedicated() else 1)
	_rpc_crew.rpc(maxi(size, 0))


@rpc("authority", "call_local", "reliable")
func _rpc_crew(size: int) -> void:
	_crew = size
	player_count_changed.emit()


# --- Sub (lobby) channel -----------------------------------------------------
## Peers enter and leave the sub at different moments — start_dive() moves the
## host into the game scene BEFORE telling the crew, so for a few frames a
## client is still walking the sub while the host is already diving. RPCs
## addressed to a node inside the sub scene would land on a peer that no
## longer has it ("node not found", and the same for synchronizer traffic), so
## the sub's roster and movement ride this autoload instead: a path that
## always exists. Peers no longer aboard simply have nothing connected to
## these signals, so the message is dropped harmlessly.

signal sub_aboard_received(pid: int, seat: Dictionary)
signal sub_roster_received(roster: Dictionary)
signal sub_pos_received(pid: int, pos: Vector2)


## Client -> host: "I'm aboard as this class, looking like this."
##
## The payload is a seat dict {diver, profile} rather than the bare diver id it
## used to be, so the lobby can show names and colours. Appearance is cosmetic
## and unvalidated by design — but it is sanitized on arrival (see Sub), because
## "cosmetic" still means "rendered", and an unbounded string from a peer would
## be drawn on everyone's screen.
@rpc("any_peer", "reliable")
func sub_aboard(seat: Dictionary) -> void:
	sub_aboard_received.emit(multiplayer.get_remote_sender_id(), seat)


## Host -> everyone: the authoritative pid -> seat roster.
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
	# Solo is a crew of one; leaving a stale count here would scale the next
	# session's difficulty from the last one's crew.
	_crew = 1


func _on_connected_to_server() -> void:
	status_changed.emit("Connected — waiting for the host to start the dive...")
	player_count_changed.emit()


func _on_connection_failed() -> void:
	_reset_peer()
	status_changed.emit("Connection failed.")


func _on_peer_disconnected(id: int) -> void:
	player_count_changed.emit()
	_refresh_crew()
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
