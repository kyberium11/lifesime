class_name World
extends Node2D
## Tile world: terrain layer + object layer (trees, rocks, bushes, buildings) and A* pathfinding.
## Objects live in `objs` (cell -> {kind, amount, regrow_at}); everything is data-driven via Data.game.

const W := 64
const H := 48
const T := 16
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const WATER := 2

var ground: TileMapLayer
var objects: TileMapLayer
var terrain := PackedByteArray()  # 0 grass, 1 dirt, 2 water
var objs: Dictionary = {}
var regrowing: Dictionary = {}
var water_cells: Array[Vector2i] = []
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var world_seed := 0
var center := Vector2i(W / 2, H / 2)


func _ready() -> void:
	var tex := ImageTexture.create_from_image(Art.tileset_image())
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(T, T)
	for i in range(Art.TILES.size()):
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	ground = TileMapLayer.new()
	ground.tile_set = ts
	add_child(ground)
	objects = TileMapLayer.new()
	objects.tile_set = ts
	add_child(objects)


# --- generation ------------------------------------------------------------

func generate_new(seed_: int) -> void:
	_build_terrain(seed_)
	objs.clear()
	regrowing.clear()
	_populate()
	_finish()


func _build_terrain(seed_: int) -> void:
	world_seed = seed_
	rng.seed = seed_
	terrain.resize(W * H)
	terrain.fill(0)
	water_cells.clear()
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.07
	var pond := center + Vector2i(10, 2)
	for y in range(H):
		for x in range(W):
			var c := Vector2i(x, y)
			var d := Vector2(c - center).length()
			var edge := mini(mini(x, W - 1 - x), mini(y, H - 1 - y))
			var t := 0
			if edge < 2:
				t = WATER
			elif d > 7.0 and noise.get_noise_2d(x, y) < -0.38:
				t = WATER
			elif d < 2.5 and ((x * 73856093) ^ (y * 19349663)) % 100 < 70:
				t = 1
			if Vector2(c - pond).length() < 3.2:
				t = WATER
			terrain[y * W + x] = t
			if t == WATER:
				water_cells.append(c)


func _populate() -> void:
	var tree_noise := FastNoiseLite.new()
	tree_noise.seed = world_seed + 1
	tree_noise.frequency = 0.09
	for y in range(H):
		for x in range(W):
			var c := Vector2i(x, y)
			if terrain[y * W + x] == WATER:
				continue
			if Vector2(c - center).length() < 6.5:
				continue
			if mini(mini(x, W - 1 - x), mini(y, H - 1 - y)) < 3:
				continue
			var p_tree := 0.05 + maxf(0.0, tree_noise.get_noise_2d(x, y)) * 0.25
			var r := rng.randf()
			if r < p_tree:
				set_object(c, "tree", Data.game.resources.tree.amount)
			elif r < p_tree + 0.012:
				set_object(c, "rock", Data.game.resources.rock.amount)
			elif r < p_tree + 0.02:
				set_object(c, "bush", Data.game.resources.bush.amount)
	# Guarantee a starter kit near the clearing so the first days are survivable.
	_scatter("tree", 6)
	_scatter("rock", 3)
	_scatter("bush", 3)
	set_object(center, "sign", 1)


func _scatter(kind: String, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 500:
		tries += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(5.5, 9.5)
		var c := center + Vector2i(Vector2.from_angle(ang) * dist)
		if in_bounds(c) and terrain[c.y * W + c.x] != WATER and not objs.has(c):
			set_object(c, kind, Data.game.resources[kind].amount)
			placed += 1


func _finish() -> void:
	ground.clear()
	objects.clear()
	for y in range(H):
		for x in range(W):
			var t := terrain[y * W + x]
			var name := "grass"
			if t == WATER:
				name = "water"
			elif t == 1:
				name = "dirt"
			elif (x * 7 + y * 13) % 5 == 0:
				name = "grass2"
			ground.set_cell(Vector2i(x, y), 0, Vector2i(Art.TILES[name], 0))
	for c in objs:
		_draw_object(c)
	_rebuild_astar()


func _rebuild_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in range(H):
		for x in range(W):
			var c := Vector2i(x, y)
			astar.set_point_solid(c, terrain[y * W + x] == WATER or objs.has(c))


# --- objects ---------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and terrain[c.y * W + c.x] == WATER


func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_water(c) and not objs.has(c)


func is_free_ground(c: Vector2i) -> bool:
	return walkable(c)


func set_object(c: Vector2i, kind: String, amount: int) -> void:
	objs[c] = {"kind": kind, "amount": amount, "regrow_at": 0.0}
	if objects != null:
		_draw_object(c)
	if astar.region.has_area():
		astar.set_point_solid(c, true)


func remove_object(c: Vector2i) -> void:
	objs.erase(c)
	regrowing.erase(c)
	objects.erase_cell(c)
	if not is_water(c):
		astar.set_point_solid(c, false)


func _draw_object(c: Vector2i) -> void:
	var o: Dictionary = objs[c]
	var tile_name: String = o.kind
	if o.amount <= 0 and Art.TILES.has(o.kind + "_empty"):
		tile_name = o.kind + "_empty"
	objects.set_cell(c, 0, Vector2i(Art.TILES[tile_name], 0))


## Harvest everything available at `c`. Returns {item, qty} (qty 0 if nothing).
func harvest(c: Vector2i) -> Dictionary:
	if is_water(c):
		var w: Dictionary = Data.game.resources.water
		return {"item": w.item, "qty": int(w.amount)}
	if not objs.has(c):
		return {"item": "", "qty": 0}
	var o: Dictionary = objs[c]
	var def: Dictionary = Data.game.resources.get(o.kind, {})
	if def.is_empty() or o.amount <= 0:
		return {"item": "", "qty": 0}
	var qty: int = o.amount
	if def.has("regrow_minutes"):
		o.amount = 0
		o.regrow_at = GameClock.minutes + float(def.regrow_minutes)
		regrowing[c] = true
		_draw_object(c)
	else:
		remove_object(c)
	return {"item": def.item, "qty": qty}


func tick() -> void:
	for c in regrowing.keys():
		var o: Dictionary = objs.get(c, {})
		if o.is_empty():
			regrowing.erase(c)
		elif GameClock.minutes >= o.regrow_at:
			o.amount = int(Data.game.resources[o.kind].amount)
			regrowing.erase(c)
			_draw_object(c)


# --- queries ---------------------------------------------------------------

func cell_to_pos(c: Vector2i) -> Vector2:
	return Vector2(c) * float(T) + Vector2(T * 0.5, T * 0.5)


func pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


## Cells of `kind` (resource or building) with something to offer, nearest first.
func find_all(kind: String, from: Vector2i, max_dist: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if kind == "water":
		for c in water_cells:
			if _manhattan(c, from) <= max_dist and _touches_land(c):
				out.append(c)
	else:
		for c in objs:
			var o: Dictionary = objs[c]
			if o.kind == kind and _manhattan(c, from) <= max_dist:
				if Data.game.resources.has(kind) and o.amount <= 0:
					continue
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _manhattan(a, from) < _manhattan(b, from))
	return out


func _touches_land(c: Vector2i) -> bool:
	for d in DIRS:
		if walkable(c + d):
			return true
	return false


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Summary of what is within `radius` tiles: kind -> {count, nearest, dist}.
func scan(from: Vector2i, radius: int, kinds: Array) -> Dictionary:
	var out := {}
	for k in kinds:
		var cells := find_all(k, from, radius)
		if not cells.is_empty():
			out[k] = {"count": cells.size(), "nearest": cells[0], "dist": _manhattan(cells[0], from)}
	return out


## Path (list of cells, excluding `from`) to a walkable cell next to `target`.
## Returns null if unreachable; [] if already adjacent.
func path_to_adjacent(from: Vector2i, target: Vector2i) -> Variant:
	if _manhattan(from, target) == 1:
		return []
	var best: Variant = null
	for d in DIRS:
		var n := target + d
		if not walkable(n):
			continue
		var p := astar.get_id_path(from, n)
		if p.is_empty():
			continue
		if best == null or p.size() - 1 < best.size():
			best = p.slice(1)
	return best


func path_to(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not walkable(to):
		return []
	var p := astar.get_id_path(from, to)
	if p.size() <= 1:
		return []
	return p.slice(1)


## Free walkable cell near `around` (searching outward) for placing a building.
func find_build_spot(around: Vector2i, avoid: Vector2i) -> Variant:
	for r in range(1, 5):
		var cells: Array[Vector2i] = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := around + Vector2i(dx, dy)
				if c != avoid and walkable(c) and not _blocks_path(c):
					cells.append(c)
		if not cells.is_empty():
			return cells[rng.randi() % cells.size()]
	return null


## True if filling `c` would wall in one of its walkable neighbours (keeps the pet unstuck).
func _blocks_path(c: Vector2i) -> bool:
	var open := 0
	for d in DIRS:
		if walkable(c + d):
			open += 1
	return open < 2


# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	var list := []
	for c in objs:
		var o: Dictionary = objs[c]
		list.append([c.x, c.y, o.kind, o.amount, o.regrow_at])
	return {"seed": world_seed, "objs": list}


func from_dict(d: Dictionary) -> void:
	_build_terrain(int(d.seed))
	objs.clear()
	regrowing.clear()
	for e in d.objs:
		var c := Vector2i(int(e[0]), int(e[1]))
		objs[c] = {"kind": e[2], "amount": int(e[3]), "regrow_at": float(e[4])}
		if float(e[4]) > 0.0 and int(e[3]) <= 0:
			regrowing[c] = true
	_finish()
