class_name Terrain
extends TileMapLayer
## Procedurally generated destructible rock. Every peer builds the identical
## layout from the seed + crate spots the server broadcasts (see
## game._rpc_build_site), so only destruction needs replicating — the server
## sends compact cell-index batches via _rpc_destroy.
##
## Reachability is guaranteed by construction: clearings are carved at the
## spawn point and every crate, plus a corridor from the center to each
## crate. No pathfinding required — and fauna chew through rock anyway.

const CELL := 16
const GRID_W := 100  # ARENA_SIZE / CELL
const GRID_H := 100
const WALL_LAYER := 4
const SPAWN_CLEARING := 100.0
const CRATE_CLEARING := 56.0
const CORRIDOR_HALF_WIDTH := 1  # cells on each side of the carved line
const VARIANTS := 3
const ORE_VARIANT := 3  # atlas column after the plain-rock variants
const ORE_POCKET_RADIUS := 1.6  # cells — a pocket converts ~5-8 rock cells

## Server broadcasts destruction; ore cells also announce themselves here so
## the game can drop salvage nuggets (server only).
signal ore_mined(world_pos: Vector2)

var initial_ore_cells := 0  # determinism fingerprint (see e2e)

## Rock coverage rises with depth: more drilling the deeper you go.
static func rock_threshold(depth: int) -> float:
	return clampf(0.62 - 0.03 * (depth - 1), 0.45, 0.62)


## Richer seams the deeper you go.
static func ore_pocket_count(depth: int) -> int:
	return 5 + depth


func _ready() -> void:
	tile_set = _build_tile_set()


## Deterministic build — same inputs on every peer, same rocks everywhere.
func build(map_seed: int, depth: int, crate_spots: PackedVector2Array) -> void:
	clear()
	var noise := FastNoiseLite.new()
	noise.seed = map_seed
	noise.frequency = 0.09
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var threshold := rock_threshold(depth)
	var variant_rng := RandomNumberGenerator.new()
	variant_rng.seed = map_seed

	for y in range(1, GRID_H - 1):
		for x in range(1, GRID_W - 1):
			# noise in [-1,1] -> rock where it beats the coverage threshold
			if noise.get_noise_2d(x, y) > (threshold * 2.0 - 1.0):
				set_cell(Vector2i(x, y), 0, Vector2i(variant_rng.randi() % VARIANTS, 0))

	var center := Vector2(GRID_W, GRID_H) * CELL / 2.0
	_carve_circle(center, SPAWN_CLEARING)
	for spot in crate_spots:
		_carve_circle(spot, CRATE_CLEARING)
		_carve_corridor(center, spot)

	_seed_ore(map_seed, depth)


## Ore only replaces rock that survived carving, so every pocket is buried —
## you have to dig for the bonus. Deterministic like everything above it.
func _seed_ore(map_seed: int, depth: int) -> void:
	initial_ore_cells = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 1  # variant_rng consumed map_seed's sequence
	for i in ore_pocket_count(depth):
		var cx := rng.randi_range(2, GRID_W - 3)
		var cy := rng.randi_range(2, GRID_H - 3)
		var r0 := int(ORE_POCKET_RADIUS)
		for y in range(cy - r0 - 1, cy + r0 + 2):
			for x in range(cx - r0 - 1, cx + r0 + 2):
				var cell := Vector2i(x, y)
				if get_cell_source_id(cell) == -1 or _is_ore(cell):
					continue
				if Vector2(cx, cy).distance_to(Vector2(x, y)) <= ORE_POCKET_RADIUS:
					set_cell(cell, 0, Vector2i(ORE_VARIANT, 0))
					initial_ore_cells += 1


func _is_ore(cell: Vector2i) -> bool:
	return get_cell_atlas_coords(cell).x == ORE_VARIANT


## Server only: destroy rock cells and replicate to everyone.
func destroy_in_radius(world_pos: Vector2, radius: float) -> int:
	if not multiplayer.is_server():
		return 0
	var cells := PackedInt32Array()
	var ore_spots := PackedVector2Array()
	var c0 := local_to_map(to_local(world_pos - Vector2.ONE * radius))
	var c1 := local_to_map(to_local(world_pos + Vector2.ONE * radius))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var cell := Vector2i(x, y)
			if get_cell_source_id(cell) == -1:
				continue
			if world_pos.distance_to(to_global(map_to_local(cell))) <= radius:
				cells.append(cell.y * GRID_W + cell.x)
				if _is_ore(cell):
					ore_spots.append(to_global(map_to_local(cell)))
	if not cells.is_empty():
		_rpc_destroy.rpc(cells)
	for spot in ore_spots:
		ore_mined.emit(spot)
	return cells.size()


func is_open(world_pos: Vector2) -> bool:
	return get_cell_source_id(local_to_map(to_local(world_pos))) == -1


## Nearest open spot to a desired position (spiral out by cells).
func find_open_near(world_pos: Vector2) -> Vector2:
	if is_open(world_pos):
		return world_pos
	var origin := local_to_map(to_local(world_pos))
	for r in range(1, 12):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) != r:
					continue
				var cell := origin + Vector2i(x, y)
				if get_cell_source_id(cell) == -1:
					return to_global(map_to_local(cell))
	return world_pos


@rpc("authority", "call_local", "reliable")
func _rpc_destroy(cells: PackedInt32Array) -> void:
	var fx_budget := 6  # don't drown big blasts in particles
	for idx in cells:
		var cell := Vector2i(idx % GRID_W, idx / GRID_W)
		if get_cell_source_id(cell) == -1:
			continue
		var was_ore := _is_ore(cell)
		erase_cell(cell)
		if was_ore or fx_budget > 0:  # a struck seam always glints
			fx_budget -= 1
			var pos := to_global(map_to_local(cell))
			var tint := Color(0.85, 0.64, 0.24) if was_ore else Color(0.45, 0.55, 0.62)
			Fx.poof(self, pos, tint)
			Sfx.play_at("dig", pos, -12.0)


func _carve_circle(world_pos: Vector2, radius: float) -> void:
	var c0 := local_to_map(to_local(world_pos - Vector2.ONE * radius))
	var c1 := local_to_map(to_local(world_pos + Vector2.ONE * radius))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var cell := Vector2i(x, y)
			if world_pos.distance_to(to_global(map_to_local(cell))) <= radius:
				erase_cell(cell)


func _carve_corridor(from: Vector2, to: Vector2) -> void:
	var steps := int(from.distance_to(to) / (CELL * 0.5)) + 1
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		var origin := local_to_map(to_local(p))
		for y in range(-CORRIDOR_HALF_WIDTH, CORRIDOR_HALF_WIDTH + 1):
			for x in range(-CORRIDOR_HALF_WIDTH, CORRIDOR_HALF_WIDTH + 1):
				erase_cell(origin + Vector2i(x, y))


func _build_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, WALL_LAYER)
	ts.set_physics_layer_collision_mask(0, 0)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/sprites/rock.png")
	src.texture_region_size = Vector2i(CELL, CELL)
	# The source must belong to the tileset BEFORE configuring per-tile
	# physics — TileData resolves physics layers through its owner.
	ts.add_source(src, 0)
	var half := CELL / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for v in VARIANTS + 1:  # plain variants + the ore column
		src.create_tile(Vector2i(v, 0))
		var data := src.get_tile_data(Vector2i(v, 0), 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, square)
	return ts
