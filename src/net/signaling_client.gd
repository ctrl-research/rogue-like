class_name SignalingClient
extends Node
## WebRTC lobby client. Speaks the signaling broker's protocol (see
## signaling/server.js — it matches Godot's official webrtc_signaling demo):
## joins/creates a room over WebSocket, then brokers one WebRTCPeerConnection
## per roommate into a WebRTCMultiplayerPeer mesh. The broker assigns the
## host peer id 1, which is exactly what our server-authoritative game code
## expects from multiplayer.is_server().

signal lobby_joined(peer_id: int, room: String, is_host: bool)
signal failed(reason: String)

const DEFAULT_URL := "ws://localhost:9080"
const DEFAULT_ICE := [{"urls": ["stun:stun.l.google.com:19302"]}]

var rtc: WebRTCMultiplayerPeer
var room_code := ""

var _ws := WebSocketPeer.new()
var _active := false
var _join_sent := false
var _room_to_join := ""
var _pending_peers: Array[int] = []  # peer_connects that arrived before "id"


static func webrtc_available() -> bool:
	if OS.has_feature("web"):
		return true  # built into the web export
	# Desktop needs the webrtc-native GDExtension (scripts/fetch_webrtc.sh);
	# without it, initialize() on the stub base class fails.
	return WebRTCPeerConnection.new().initialize({}) == OK


static func signaling_url() -> String:
	# Env override for local development and the e2e test (no env on web,
	# where the project setting — the production broker — always applies).
	var env_url := OS.get_environment("SIGNALING_URL")
	if not env_url.is_empty():
		return env_url
	return str(ProjectSettings.get_setting("network/signaling/url", DEFAULT_URL))


static func ice_servers() -> Array:
	var raw := str(ProjectSettings.get_setting("network/signaling/ice_servers", ""))
	if not raw.is_empty():
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Array:
			return parsed
	return DEFAULT_ICE


## Connect to the broker. Empty room code = create a room and host it.
func start(room: String) -> Error:
	stop()
	_room_to_join = room.to_upper().strip_edges()
	var err := _ws.connect_to_url(signaling_url())
	if err != OK:
		failed.emit("Could not reach dive control (%s)." % signaling_url())
		return err
	_active = true
	return OK


func stop() -> void:
	_active = false
	_join_sent = false
	room_code = ""
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	_ws = WebSocketPeer.new()
	rtc = null


## Host only: lock the room so no one else can join mid-run.
func seal() -> void:
	_send({"type": "seal"})


## Host only: reopen the room for the post-game lobby.
func unseal() -> void:
	_send({"type": "unseal"})


func _process(_delta: float) -> void:
	if not _active:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _join_sent:
				_join_sent = true
				_send({"type": "join", "room": _room_to_join})
			while _ws.get_available_packet_count() > 0:
				_handle(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_active = false
			if rtc == null:
				failed.emit("Lost contact with dive control (code %d)." % _ws.get_close_code())


func _send(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _handle(raw: String) -> void:
	var msg: Variant = JSON.parse_string(raw)
	if not msg is Dictionary or not msg.has("type"):
		return
	match str(msg.type):
		"id":
			rtc = WebRTCMultiplayerPeer.new()
			rtc.create_mesh(int(msg.id))
			room_code = str(msg.room)
			lobby_joined.emit(int(msg.id), room_code, bool(msg.host))
			for pid in _pending_peers:
				_create_peer(pid)
			_pending_peers.clear()
		"peer_connect":
			# Defensive: buffer if the broker introduces peers before "id".
			if rtc == null:
				_pending_peers.append(int(msg.id))
			else:
				_create_peer(int(msg.id))
		"peer_disconnect":
			if rtc != null and rtc.has_peer(int(msg.id)):
				rtc.remove_peer(int(msg.id))
		"offer", "answer":
			if rtc != null and rtc.has_peer(int(msg.id)):
				rtc.get_peer(int(msg.id)).connection.set_remote_description(str(msg.type), str(msg.sdp))
		"candidate":
			if rtc != null and rtc.has_peer(int(msg.id)):
				rtc.get_peer(int(msg.id)).connection.add_ice_candidate(
					str(msg.mid), int(msg.index), str(msg.name))
		"seal":
			pass  # room locked; nothing to do client-side
		"error":
			var reason := str(msg.get("reason", "unknown"))
			failed.emit(_friendly_error(reason))


func _create_peer(id: int) -> void:
	if rtc == null:
		return
	var pc := WebRTCPeerConnection.new()
	var err := pc.initialize({"iceServers": ice_servers()})
	if err != OK:
		failed.emit("WebRTC is unavailable on this platform.")
		return
	pc.session_description_created.connect(_on_description.bind(id, pc))
	pc.ice_candidate_created.connect(_on_candidate.bind(id))
	var add_err := rtc.add_peer(pc, id)
	# Both sides learn about each other; the newer peer (higher id) offers.
	var offering := id < rtc.get_unique_id()
	var offer_err := pc.create_offer() if offering else OK
	print("[signaling] peer %d: add=%s offering=%s offer=%s" % [
		id, error_string(add_err), offering, error_string(offer_err)])


func _on_description(type: String, sdp: String, id: int, pc: WebRTCPeerConnection) -> void:
	print("[signaling] local %s for peer %d" % [type, id])
	pc.set_local_description(type, sdp)
	_send({"type": type, "id": id, "sdp": sdp})


func _on_candidate(mid: String, index: int, sdp_name: String, id: int) -> void:
	_send({"type": "candidate", "id": id, "mid": mid, "index": index, "name": sdp_name})


func _friendly_error(reason: String) -> String:
	match reason:
		"room_not_found":
			return "No dive with that room code."
		"room_sealed":
			return "That dive has already started."
		"room_full":
			return "That dive crew is full."
		"server_full", "too_many_connections", "rate_limited":
			return "Dive control is overloaded — try again shortly."
	return "Dive control error: %s" % reason
