extends Node
## Dedicated-server end-to-end monitor. Three processes, one scene, role set by
## tests/e2e_dedicated_boot.gd from E2E_ROLE: one `server` (no diver of its own)
## plus two divers, `lead` and `follower`.
##
## Parented to /root by the boot scene, NOT part of the current scene — it changes
## scenes itself, and a node that is the current scene gets freed when it does.
##
## This exists to cover what the WebRTC e2e cannot: that the server is NOT a
## player. The assertions below are chosen to fail on the specific mistakes this
## refactor could make —
##   * crew must be 2, not 3. player_count() used to be get_peers()+1, which counts
##     the server itself, and that number sets enemy counts and HP scaling.
##   * the deck must hold 2 divers, not 3 — no phantom body for the server.
##   * a DIVER must be able to start the dive. It used to be gated on is_server(),
##     which with no host player would leave a crew stuck in the sub forever.
##   * clients must learn the crew size from the server. In a client-server
##     topology a client's peer list holds only the server, so anything derived
##     locally would report 2 divers regardless of who is aboard.
##
## Prints E2E_SERVER_OK / E2E_LEAD_OK / E2E_FOLLOWER_OK.

const SERVER_PORT := 9155
const START_DEPTH := 1
## The server runs WITH a password, so the happy path exercises authentication
## rather than only the open case. The intruder role presents a wrong one.
const PASSWORD := "correct-horse"

var role := "server"

var _phase := "connect"
var _elapsed := 0.0
var _reported := {}
var _dive_requested := false


func _ready() -> void:
	# `role` is set by tests/e2e_dedicated_boot.gd before this is added to /root.
	Net.status_changed.connect(func(t: String) -> void: print("[%s] %s" % [role, t]))
	if role == "intruder":
		# Refusal is the pass condition here. Godot drops an unauthenticated peer
		# before it is ever "connected", so this can never have sent an RPC.
		Net.failed_to_join.connect(func() -> void:
			print("[intruder] refused, as it should be")
			print("E2E_INTRUDER_REFUSED")
			get_tree().quit(0))
	Net.entered_lobby.connect(func(_r: String, _h: bool) -> void:
		get_tree().change_scene_to_file(Net.SUB_SCENE))

	if role == "server":
		# is_dedicated() reads --dedicated from the user args the harness passes, so
		# the decoupling paths under test are the real ones, not a test-only branch.
		print("[server] dedicated=%s" % Net.is_dedicated())
		Net.host_dedicated(SERVER_PORT)
	else:
		# Distinct names, so "did the OTHER diver's profile arrive" is answerable.
		Station.profile = Appearance.sanitize({
			"name": role, "suit": "#3fa9d9" if role == "lead" else "#d94f3d"})
		Station.dive_depth = START_DEPTH
		Net.join_server("ws://127.0.0.1:%d" % SERVER_PORT,
				PASSWORD if role != "intruder" else "wrong-password")


func _process(delta: float) -> void:
	_elapsed += delta
	var scene := get_tree().current_scene
	if scene == null:
		return
	match _phase:
		"connect":
			# Heartbeat here too: the first version printed nothing at all while
			# stuck in this phase, which made a dead monitor look identical to a
			# server that was simply waiting.
			_beat("connecting... scene=%s" % scene.name)
			if scene.name == "Sub":
				_phase = "lobby"
		"lobby":
			# Driven by which scene is actually loaded rather than by manual
			# transitions. The server used to report its lobby marker and never
			# advance, so once the dive started it kept probing `scene.divers` on the
			# Game scene — 38 script errors from one missing state change. Keying the
			# phase off the scene makes that class of mistake unreachable.
			if scene.name == "Sub":
				_check_lobby(scene)
			else:
				_phase = "dive"
		"dive":
			_check_dive(scene)


func _check_lobby(scene: Node) -> void:
	var crew := Net.player_count()
	var aboard: int = scene.divers.get_child_count()
	_beat("lobby crew=%d aboard=%d" % [crew, aboard])

	# The crew is TWO divers. A server that counted itself would say three, and
	# every enemy in the trench would be scaled for a diver who is not there.
	if crew != 2 or aboard != 2:
		return

	if role == "server":
		# No phantom diver for the server, and no seat in its own roster.
		# Explicit Node: `divers` is not a member of Node, so reaching through it is
		# a Variant call and `:=` cannot infer — the same trap that has broken this
		# project's parse six times now.
		var mine: Node = scene.divers.get_node_or_null("D1")
		if mine != null:
			_fail("the server seated itself as a diver (D1 exists)")
			return
		_once("E2E_SERVER_LOBBY_OK", "crew=2 aboard=2, server holds no seat")
		return

	# Divers must be able to read each other's chosen names off the roster.
	var theirs := "FOLLOWER" if role == "lead" else "LEAD"
	var saw := false
	for child in scene.divers.get_children():
		if str(child.get_node("Name").text).contains(theirs):
			saw = true
	if not saw:
		return
	_once("E2E_%s_LOBBY_OK" % role.to_upper(), "saw crewmate %s" % theirs)

	# A DIVER starts the dive — not the server, which has no button and no Station.
	if role == "lead" and not _dive_requested:
		_dive_requested = true
		print("[lead] requesting the dive at depth %d" % START_DEPTH)
		Net.request_dive.rpc_id(1, START_DEPTH)


func _check_dive(scene: Node) -> void:
	if scene.name != "Game":
		_beat("waiting for the dive to start")
		return
	var players := get_tree().get_nodes_in_group("players").size()
	var pen := scene.get_node_or_null("Enemies")
	var enemies: int = pen.get_child_count() if pen != null else 0
	_beat("in game players=%d enemies=%d depth=%d" % [players, enemies, scene.depth])

	if scene.depth != START_DEPTH:
		_fail("dive started at depth %d, not the requested %d" % [scene.depth, START_DEPTH])
		return
	# Two divers spawned, not three: the server must not have marked itself ready.
	if players != 2:
		return
	# Every role waits for the same evidence: two divers AND a live wave. The server
	# used to finish on players alone, so it quit a second later and tore down the
	# session before any enemy existed — leaving both clients waiting forever for a
	# wave that could never come. A server that exits first ends the test for
	# everyone, so its bar has to be at least as high as theirs.
	if enemies < 1:
		return
	if role == "server":
		_once("E2E_SERVER_OK", "2 players spawned and %d enemies live" % enemies)
	else:
		_once("E2E_%s_OK" % role.to_upper(), "2 players and %d enemies replicated" % enemies)


func _once(marker: String, detail: String) -> void:
	if _reported.has(marker):
		return
	_reported[marker] = true
	print("[%s] %s" % [role, detail])
	print(marker)
	# Every role has exactly one terminal marker; the harness collects them.
	if marker.ends_with("_OK") and not marker.ends_with("_LOBBY_OK"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _fail(why: String) -> void:
	if _reported.has("fail"):
		return
	_reported["fail"] = true
	print("[%s] E2E_DEDICATED_FAIL: %s" % [role, why])
	get_tree().quit(1)


var _beat_at := 0.0


func _beat(text: String) -> void:
	if _elapsed - _beat_at < 3.0:
		return
	_beat_at = _elapsed
	print("[%s] %.0fs %s" % [role, _elapsed, text])
