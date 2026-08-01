class_name Player
extends CharacterBody2D
## A diver. Movement is client-authoritative (synced via MovementSync, whose
## authority is the owning peer); hp/downed/dead are server-authoritative
## (StateSync, authority 1). Weapons auto-fire on the server only.
##
## Level-up offers flow server -> owning peer (_rpc_offer), picks flow back
## (_rpc_pick), and the applied result broadcasts to everyone (apply_pick) so
## stats stay consistent on every peer.

signal upgrade_offered(options: Array)

const TINTS: Array[Color] = [
	Color.WHITE,
	Color(0.65, 0.9, 1.0),
	Color(0.7, 1.0, 0.7),
	Color(1.0, 0.75, 0.85),
]
const BASE_SPEED := 90.0
const BASE_MAX_HP := 100.0
const BASE_PICKUP_RADIUS := 28.0
const BASE_LAMP_SCALE := 2.2
const LANCE_TINT := Color(0.55, 0.95, 1.0)

var peer_id := 1
var player_index := 0
var game  # the Game node; untyped to avoid a class_name dependency cycle

var move_speed := BASE_SPEED
var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP
var dead := false:
	set = _set_dead
var downed := false:
	set = _set_downed
var revive_progress := 0.0

var weapons := {"harpoon": 1}  # id -> level
var passives := {}  # id -> level

var _cooldowns := {}
var _pending_offers: Array = []  # server-only queue of offers (Array[Array])
var _pickup_shape: CircleShape2D


func _ready() -> void:
	$MovementSync.set_multiplayer_authority(peer_id)
	$Camera.enabled = _is_local()
	$Sprite.self_modulate = TINTS[player_index % TINTS.size()]
	$NameLabel.text = display_name()
	$Camera.limit_left = 0
	$Camera.limit_top = 0
	$Camera.limit_right = int(GameRules.ARENA_SIZE.x)
	$Camera.limit_bottom = int(GameRules.ARENA_SIZE.y)
	# Per-instance pickup shape (a shared subresource would make one player's
	# magnet upgrade grow everyone's radius).
	_pickup_shape = CircleShape2D.new()
	_pickup_shape.radius = BASE_PICKUP_RADIUS
	$Pickup/Shape.shape = _pickup_shape
	if multiplayer.is_server():
		$Pickup.area_entered.connect(_on_pickup)


func _physics_process(delta: float) -> void:
	$ReviveBar.visible = downed
	$ReviveBar.value = revive_progress

	if game == null or game.game_over or dead:
		return

	if _is_local():
		velocity = Vector2.ZERO
		if not downed:
			velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed
			move_and_slide()

	if velocity.x != 0.0:
		$Sprite.flip_h = velocity.x < 0.0

	if multiplayer.is_server():
		if downed:
			_server_downed_tick(delta)
		else:
			_server_combat(delta)


func display_name() -> String:
	return "P%d" % (player_index + 1)


## Server only.
func take_damage(amount: float) -> void:
	if dead or downed:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_go_down()


# --- Level-up offers -------------------------------------------------------


## Server: queue a 3-option offer; it is presented to the owning peer as soon
## as earlier offers are resolved.
func queue_offer(options: Array) -> void:
	if options.is_empty():
		return
	_pending_offers.append(options)
	if _pending_offers.size() == 1:
		_send_current_offer()


## Owning peer (HUD): choose an option from the currently shown offer.
func request_pick(id: String) -> void:
	if multiplayer.is_server():
		_server_pick(id)
	else:
		_rpc_pick.rpc_id(1, id)


func _send_current_offer() -> void:
	var options: Array = _pending_offers[0]
	if peer_id == 1:
		upgrade_offered.emit(options)
	else:
		_rpc_offer.rpc_id(peer_id, options)


@rpc("authority", "reliable")
func _rpc_offer(options: Array) -> void:
	upgrade_offered.emit(options)


@rpc("any_peer", "reliable")
func _rpc_pick(id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_server_pick(id)


func _server_pick(id: String) -> void:
	if _pending_offers.is_empty() or not (_pending_offers[0] as Array).has(id):
		return
	_pending_offers.pop_front()
	apply_pick.rpc(id)
	if Weapons.is_weapon(id) and weapons[id] == 1:
		game.announce("%s armed the %s" % [display_name(), Weapons.title(id)])
	match id:
		"rebreather":
			game.add_oxygen(Weapons.REBREATHER_OXYGEN)
		"suit":
			hp = minf(hp + 25.0, max_hp)
	if not _pending_offers.is_empty():
		_send_current_offer()


@rpc("authority", "call_local", "reliable")
func apply_pick(id: String) -> void:
	if Weapons.is_weapon(id):
		weapons[id] = mini(weapons.get(id, 0) + 1, GameRules.WEAPON_MAX_LEVEL)
	else:
		passives[id] = mini(passives.get(id, 0) + 1, GameRules.PASSIVE_MAX_LEVEL)
		_apply_passives()


func _apply_passives() -> void:
	move_speed = BASE_SPEED * pow(1.10, passives.get("fins", 0))
	max_hp = BASE_MAX_HP + 20.0 * passives.get("suit", 0)
	$Lamp.texture_scale = BASE_LAMP_SCALE * pow(1.25, passives.get("lamp", 0))
	_pickup_shape.radius = BASE_PICKUP_RADIUS * pow(1.4, passives.get("magnet", 0))


# --- Combat (server) -------------------------------------------------------


func _server_combat(delta: float) -> void:
	for id in weapons:
		_cooldowns[id] = _cooldowns.get(id, 0.0) - delta
		if _cooldowns[id] > 0.0:
			continue
		if _fire_weapon(id):
			_cooldowns[id] = Weapons.weapon_cd(id, weapons[id])


func _fire_weapon(id: String) -> bool:
	var dmg := Weapons.weapon_damage(id, weapons[id])
	var reach: float = Weapons.WEAPONS[id]["range"]
	match id:
		"harpoon":
			var target := _nearest_enemy(reach)
			if target == null:
				return false
			var dir := (target.global_position - global_position).normalized()
			game.fire_bolt(global_position, dir, dmg, 1, Color.WHITE, Vector2.ONE, 260.0)
		"lance":
			var target := _nearest_enemy(reach)
			if target == null:
				return false
			var dir := (target.global_position - global_position).normalized()
			game.fire_bolt(global_position, dir, dmg, 99, LANCE_TINT, Vector2(1.9, 1.3), 420.0)
		"charge":
			var target := _random_enemy(reach)
			if target == null:
				return false
			game.drop_charge(target.global_position, dmg, Weapons.WEAPONS[id]["radius"])
	return true


func _nearest_enemy(reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := reach * reach
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Node2D
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _random_enemy(reach: float) -> Node2D:
	var in_range: Array[Node2D] = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Node2D
		if global_position.distance_squared_to(enemy.global_position) <= reach * reach:
			in_range.append(enemy)
	if in_range.is_empty():
		return null
	return in_range.pick_random()


# --- Downed / revive (server) ----------------------------------------------


func _go_down() -> void:
	if Net.player_count() == 1:
		# No one can revive a solo diver.
		_die()
		return
	downed = true
	revive_progress = 0.0
	hp = max_hp * GameRules.BLEED_FRACTION
	game.on_player_downed(self)


func _server_downed_tick(delta: float) -> void:
	# Bleed out (the hp bar doubles as the bleed-out timer)...
	hp -= max_hp * GameRules.BLEED_FRACTION / GameRules.BLEED_TIME * delta
	if hp <= 0.0:
		hp = 0.0
		_die()
		return
	# ...unless a teammate holds position nearby to revive.
	var rescuer_near := false
	for p in game.players.get_children():
		if p is Player and p != self and not p.dead and not p.downed \
				and global_position.distance_to(p.global_position) <= GameRules.REVIVE_RANGE:
			rescuer_near = true
			break
	if rescuer_near:
		revive_progress = minf(1.0, revive_progress + delta / GameRules.REVIVE_TIME)
		if revive_progress >= 1.0:
			_revive()
	else:
		revive_progress = maxf(0.0, revive_progress - 2.0 * delta / GameRules.REVIVE_TIME)


func _revive() -> void:
	downed = false
	revive_progress = 0.0
	hp = max_hp * GameRules.BLEED_FRACTION
	game.announce("%s is back on their feet!" % display_name())


func _die() -> void:
	downed = false
	revive_progress = 0.0
	dead = true
	game.on_player_died()


# --- Pickups (server) ------------------------------------------------------


func _on_pickup(area: Area2D) -> void:
	if dead or downed:
		return
	if area.is_in_group("gems") and not area.is_queued_for_deletion():
		game.add_xp(GameRules.XP_PER_GEM)
		area.queue_free()


# --- State visuals (run on every peer via synced setters) ------------------


func _is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func _set_dead(value: bool) -> void:
	dead = value
	if not is_node_ready():
		return
	visible = not value
	$Collision.set_deferred("disabled", value)


func _set_downed(value: bool) -> void:
	downed = value
	if not is_node_ready():
		return
	$Sprite.rotation = -PI / 2 if value else 0.0
	$Sprite.modulate = Color(1.0, 0.55, 0.55, 0.9) if value else Color.WHITE
