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
## The hub serves multiple games; rooms are namespaced per game id so codes
## never collide across games.
const GAME_ID := "abyssal"

var rtc: WebRTCMultiplayerPeer
var room_code := ""

var _ws := WebSocketPeer.new()
var _active := false
var _join_sent := false
var _room_to_join := ""
var _pending_peers: Array[int] = []  # peer_connects that arrived before "id"
# Handshake telemetry. We used to log only the descriptions we SENT, which is
# why a browser report could show a completed offer/answer exchange and still
# leave the interesting part — did the answer arrive, did candidates flow, what
# state did the connection reach — entirely invisible.
var _cand_out := {}  # peer id -> candidates we sent
var _cand_in := {}  # peer id -> candidates we received
var _peer_snap := {}  # peer id -> last reported state, so we log transitions
var _status_report := 0.0
var _last_status := -1


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


func _process(delta: float) -> void:
	_report_handshake(delta)
	if not _active:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _join_sent:
				_join_sent = true
				_send({"type": "join", "room": _room_to_join, "game": GAME_ID})
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
				var set_err := rtc.get_peer(int(msg.id)).connection.set_remote_description(
						str(msg.type), str(msg.sdp))
				# The offering side never fires session_description_created for an
				# incoming answer, so without this line there is no evidence the
				# answer ever landed.
				print("[signaling] remote %s from peer %d: set=%s" % [
						str(msg.type), int(msg.id), error_string(set_err)])
			else:
				print("[signaling] dropped %s from peer %s (no such peer)" % [
						str(msg.type), str(msg.id)])
		"candidate":
			if rtc != null and rtc.has_peer(int(msg.id)):
				var pid := int(msg.id)
				var add_err := rtc.get_peer(pid).connection.add_ice_candidate(
					str(msg.mid), int(msg.index), str(msg.name))
				_cand_in[pid] = int(_cand_in.get(pid, 0)) + 1
				if add_err != OK:
					print("[signaling] candidate %d from peer %d rejected: %s" % [
							_cand_in[pid], pid, error_string(add_err)])
			else:
				print("[signaling] dropped candidate from peer %s (no such peer)" % str(msg.id))
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
	_cand_out[id] = int(_cand_out.get(id, 0)) + 1
	_send({"type": "candidate", "id": id, "mid": mid, "index": index, "name": sdp_name})


## Log the handshake's actual progress: per-peer connection state and how many
## ICE candidates crossed in each direction. Reports on change, plus a heartbeat
## while the mesh is still not connected — a stall then says which stage it
## reached instead of going quiet.
func _report_handshake(delta: float) -> void:
	if rtc == null:
		return
	var status := rtc.get_connection_status()
	if status != _last_status:
		_last_status = status
		print("[signaling] mesh status=%d (0=disconnected 1=connecting 2=connected)" % status)
	_status_report -= delta
	var heartbeat := false
	if status != MultiplayerPeer.CONNECTION_CONNECTED and _status_report <= 0.0:
		_status_report = 3.0
		heartbeat = true
	for key in rtc.get_peers():
		var id := int(key)
		var info: Dictionary = rtc.get_peer(id)
		var pc: WebRTCPeerConnection = info.get("connection")
		var conn := -1
		var gather := -1
		var sig := -1
		if pc != null:
			conn = pc.get_connection_state()
			# Guarded: these two are the least portable part of the API, and this
			# code ships to browsers where a missing method would be fatal.
			if pc.has_method("get_gathering_state"):
				gather = pc.get_gathering_state()
			if pc.has_method("get_signaling_state"):
				sig = pc.get_signaling_state()
		var snap := "%s/%d/%d/%d/%d/%d" % [info.get("connected", false), conn, gather, sig,
				int(_cand_out.get(id, 0)), int(_cand_in.get(id, 0))]
		if heartbeat or _peer_snap.get(id, "") != snap:
			_peer_snap[id] = snap
			print("[signaling] peer %d: connected=%s conn=%d gathering=%d signaling=%d candidates out=%d in=%d" % [
					id, info.get("connected", false), conn, gather, sig,
					int(_cand_out.get(id, 0)), int(_cand_in.get(id, 0))])


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
