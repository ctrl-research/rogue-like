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
const SOLAR_TINT := Color(1.0, 0.72, 0.3)
const DRONE_TEXTURE := preload("res://assets/sprites/drone.png")
const DRONE_ORBIT_RADIUS := 34.0
const DRONE_ORBIT_SPEED := 2.4  # rad/s
const DRONE_HIT_RANGE := 16.0

var peer_id := 1
var player_index := 0
var meta := {}  # station upgrade levels, set via spawn data on every peer
var game  # the Game node; untyped to avoid a class_name dependency cycle

var move_speed := BASE_SPEED
var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP:
	set = _set_hp
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
var _drones: Array[Sprite2D] = []
var _shake := 0.0


func _enter_tree() -> void:
	# Must happen before _ready: changing a synchronizer's authority during
	# _ready breaks spawn registration for the scene's other synchronizers
	# (peer_id is set by the spawn function before the node enters the tree).
	$MovementSync.set_multiplayer_authority(peer_id)


func _ready() -> void:
	add_to_group("players")
	$Camera.enabled = is_local()
	_add_bubbles()
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
	_apply_passives()
	hp = max_hp
	if multiplayer.is_server():
		$Pickup.area_entered.connect(_on_pickup)


func _physics_process(delta: float) -> void:
	$ReviveBar.visible = downed
	$ReviveBar.value = revive_progress

	if _shake > 0.05:
		_shake = lerpf(_shake, 0.0, minf(10.0 * delta, 1.0))
		$Camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	elif $Camera.offset != Vector2.ZERO:
		$Camera.offset = Vector2.ZERO

	if game == null or game.game_over or dead:
		return

	if is_local():
		velocity = Vector2.ZERO
		if not downed:
			velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed
			move_and_slide()

	if velocity.x != 0.0:
		$Sprite.flip_h = velocity.x < 0.0

	# Drones orbit deterministically on every peer (cosmetic on clients; the
	# server's copies are the ones that deal damage).
	if not _drones.is_empty():
		var t := Time.get_ticks_msec() / 1000.0
		for i in _drones.size():
			var angle := t * DRONE_ORBIT_SPEED + TAU * i / _drones.size()
			_drones[i].position = Vector2.from_angle(angle) * DRONE_ORBIT_RADIUS

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
	if id.begins_with("evolve_"):
		game.announce("%s evolved the %s!" % [display_name(), Weapons.title(id)])
	elif Weapons.is_weapon(id) and weapons[id] == 1:
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
	if id.begins_with("evolve_"):
		weapons[id.trim_prefix("evolve_")] = Weapons.EVOLVED_LEVEL
	elif Weapons.is_weapon(id):
		weapons[id] = mini(weapons.get(id, 0) + 1, GameRules.WEAPON_MAX_LEVEL)
	else:
		passives[id] = mini(passives.get(id, 0) + 1, GameRules.PASSIVE_MAX_LEVEL)
		_apply_passives()
	_update_drones()


## Keep one orbiting drone sprite per drone level, on every peer.
func _update_drones() -> void:
	var want := weapons.get("drone", 0) as int
	while _drones.size() < want:
		var drone := Sprite2D.new()
		drone.texture = DRONE_TEXTURE
		add_child(drone)
		_drones.append(drone)
	while _drones.size() > want:
		_drones.pop_back().queue_free()


## Recompute derived stats from station meta (permanent) + in-run passives.
func _apply_passives() -> void:
	var meta_speed := 1.0 + Station.FINS_PER_LEVEL * int(meta.get("fins", 0))
	move_speed = BASE_SPEED * meta_speed * pow(1.10, passives.get("fins", 0))
	max_hp = BASE_MAX_HP + Station.HULL_PER_LEVEL * int(meta.get("hull", 0)) \
			+ 20.0 * passives.get("suit", 0)
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


## Server-teleport that survives client-authoritative movement: runs on every
## peer (including the owner, whose copy is the one that syncs onward).
@rpc("authority", "call_local", "reliable")
func teleport(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO


func _fire_weapon(id: String) -> bool:
	var lvl: int = weapons[id]
	var evolved := lvl >= Weapons.EVOLVED_LEVEL
	var dmg := Weapons.weapon_damage(id, lvl)
	if id == "harpoon":
		dmg *= 1.0 + Station.HARPOON_PER_LEVEL * int(meta.get("harpoon", 0))
	var reach: float = Weapons.WEAPONS[id]["range"]
	match id:
		"harpoon":
			var target := _nearest_enemy(reach)
			if target == null:
				return false
			var dir := (target.global_position - global_position).normalized()
			if evolved:  # Chain Harpoon: arcs between prey
				game.fire_bolt(global_position, dir, dmg, 1, Color(0.6, 1.0, 0.85), Vector2(1.2, 1.2), 300.0, 3)
			else:
				game.fire_bolt(global_position, dir, dmg, 1, Color.WHITE, Vector2.ONE, 260.0)
		"lance":
			var target := _nearest_enemy(reach)
			if target == null:
				return false
			var dir := (target.global_position - global_position).normalized()
			if evolved:  # Solar Lance: a spear of burning light
				game.fire_bolt(global_position, dir, dmg * 2.0, 999, SOLAR_TINT, Vector2(2.5, 1.6), 520.0)
			else:
				game.fire_bolt(global_position, dir, dmg, 99, LANCE_TINT, Vector2(1.9, 1.3), 420.0)
		"charge":
			var target := _random_enemy(reach)
			if target == null:
				return false
			var radius: float = Weapons.WEAPONS[id]["radius"]
			if evolved:  # Pressure Bomb: implodes and stuns
				game.drop_charge(target.global_position, dmg * 1.8, radius * 1.7, 1.5)
			else:
				game.drop_charge(target.global_position, dmg, radius)
		"drone":
			# Contact tick: each drone shreds fauna it touches.
			for drone in _drones:
				for e in get_tree().get_nodes_in_group("enemies"):
					var enemy := e as Enemy
					if not enemy.is_queued_for_deletion() \
							and drone.global_position.distance_to(enemy.global_position) <= DRONE_HIT_RANGE:
						enemy.take_damage(dmg)
		"sonar":
			var radius := Weapons.sonar_radius(lvl)
			var any_hit := false
			for e in get_tree().get_nodes_in_group("enemies"):
				var enemy := e as Enemy
				var offset := enemy.global_position - global_position
				if offset.length() <= radius and not enemy.is_queued_for_deletion():
					any_hit = true
					enemy.global_position += offset.normalized() * 28.0
					enemy.take_damage(dmg)
			if not any_hit:
				return false
			game.spawn_ring(global_position, radius)
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


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


## Kick the local camera (decays automatically).
func shake(amount: float) -> void:
	if is_local():
		_shake = maxf(_shake, amount)


func _set_hp(value: float) -> void:
	var old := hp
	hp = value
	if not is_node_ready() or value >= old or dead:
		return
	# Hurt feedback: hp replicates, so this runs on every peer; the shake
	# and heavy sound only land for the diver who owns the pain.
	if is_local():
		shake(3.0)
		Sfx.play("hit", -4.0, 0.15)
	else:
		Sfx.play_at("hit", global_position, -12.0)


func _add_bubbles() -> void:
	var bubbles := CPUParticles2D.new()
	bubbles.amount = 5
	bubbles.lifetime = 1.8
	bubbles.preprocess = 1.0
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = 5.0
	bubbles.direction = Vector2.UP
	bubbles.spread = 15.0
	bubbles.initial_velocity_min = 10.0
	bubbles.initial_velocity_max = 22.0
	bubbles.gravity = Vector2(0, -20)
	bubbles.scale_amount_min = 0.6
	bubbles.scale_amount_max = 1.4
	bubbles.color = Color(0.75, 0.92, 1.0, 0.30)
	bubbles.position = Vector2(0, -6)
	add_child(bubbles)


func _set_dead(value: bool) -> void:
	dead = value
	if not is_node_ready():
		return
	visible = not value
	$Collision.set_deferred("disabled", value)


func _set_downed(value: bool) -> void:
	var was := downed
	downed = value
	if not is_node_ready():
		return
	$Sprite.rotation = -PI / 2 if value else 0.0
	$Sprite.modulate = Color(1.0, 0.55, 0.55, 0.9) if value else Color.WHITE
	if value and not was:
		if is_local():
			Sfx.play("downed", -4.0, 0.0)
			shake(4.0)
		else:
			Sfx.play_at("downed", global_position, -10.0)
	elif was and not value:
		Sfx.play_at("revive", global_position, -6.0)
