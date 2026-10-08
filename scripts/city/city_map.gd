class_name CityMap
extends RefCounted
## The spatial model of the city: an unbounded tile grid (1 tile = 4 world units).
##
## The world is divided into 4x4-tile DISTRICTS. A district's west column and north row are road.
## Its 3x3 interior holds 8 building lots and one central green. Claiming a district adds it to the
## city: its roads appear and its lots become buildable. Terrain (water, forest) is generated on
## demand from the seed, so there is no edge to the world.
##
## Tile coordinates are integers; tile (x, y) is centred at world (x * TILE, 0, y * TILE).

const TILE := 4.0
const DISTRICT := 4
const NEIGHBORS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]

var world_seed := 1337
var claimed: Dictionary = {}  # district Vector2i -> true
var occupied: Dictionary = {}  # tile Vector2i -> building id
var solid_tiles: Dictionary = {}  # tiles blocked by a solid building
var nav := AStarGrid2D.new()
var nav_rect := Rect2i()

var _water := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init(seed_: int = 1337) -> void:
	set_seed(seed_)


func set_seed(seed_: int) -> void:
	world_seed = seed_
	_water.seed = seed_
	_water.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_water.frequency = 0.05
	_forest.seed = seed_ + 7
	_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest.frequency = 0.07


# --- coordinates -----------------------------------------------------------------------

static func district_of(t: Vector2i) -> Vector2i:
	return Vector2i(floori(t.x / float(DISTRICT)), floori(t.y / float(DISTRICT)))


static func local_of(t: Vector2i) -> Vector2i:
	return Vector2i(posmod(t.x, DISTRICT), posmod(t.y, DISTRICT))


static func tile_to_world(t: Vector2i) -> Vector3:
	return Vector3(t.x * TILE, 0.0, t.y * TILE)


static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / TILE), roundi(p.z / TILE))


static func tile_pos_to_world(p: Vector2) -> Vector3:
	return Vector3(p.x * TILE, 0.0, p.y * TILE)


func _hash(t: Vector2i, salt: int = 0) -> int:
	return ((t.x * 73856093) ^ (t.y * 19349663) ^ ((world_seed + salt) * 83492791)) & 0x7fffffff


## Stable pseudo-random number for a tile (used to scatter decoration).
func tile_hash(t: Vector2i, salt: int = 0) -> int:
	return _hash(t, salt)


# --- terrain -------------------------------------------------------------------------------

func is_water(t: Vector2i) -> bool:
	if absi(t.x) + absi(t.y) < 22:
		return false
	return _water.get_noise_2d(t.x, t.y) < -0.42


## Wild trees (decoration, and wood when the land is claimed). Dense in forest clusters.
func has_trees(t: Vector2i) -> bool:
	if is_water(t):
		return false
	var dense := _forest.get_noise_2d(t.x, t.y) > 0.05
	return _hash(t, 3) % 100 < (62 if dense else 11)


func has_rock(t: Vector2i) -> bool:
	return not is_water(t) and _hash(t, 5) % 100 < 4


# --- structure of the city -----------------------------------------------------------------

func is_claimed_tile(t: Vector2i) -> bool:
	return claimed.has(district_of(t))


## Roads exist on the west/north edges of every claimed district, which also closes the east/south
## edges against claimed neighbours. Roads are derived from the claimed set, never stored.
func is_road(t: Vector2i) -> bool:
	var l := local_of(t)
	var d := district_of(t)
	if l.x == 0 and l.y == 0:
		return claimed.has(d) or claimed.has(d - Vector2i(1, 0)) or claimed.has(d - Vector2i(0, 1)) or claimed.has(d - Vector2i(1, 1))
	if l.x == 0:
		return claimed.has(d) or claimed.has(d - Vector2i(1, 0))
	if l.y == 0:
		return claimed.has(d) or claimed.has(d - Vector2i(0, 1))
	return false


static func is_lot(t: Vector2i) -> bool:
	var l := local_of(t)
	return l.x >= 1 and l.y >= 1 and not (l.x == 2 and l.y == 2)


static func is_green(t: Vector2i) -> bool:
	var l := local_of(t)
	return l.x == 2 and l.y == 2


func is_buildable(t: Vector2i) -> bool:
	return is_lot(t) and is_claimed_tile(t) and not occupied.has(t) and not is_water(t)


func walkable(t: Vector2i) -> bool:
	if is_water(t) or solid_tiles.has(t):
		return false
	if is_road(t):
		return true
	return is_claimed_tile(t)


## Free lots in claimed districts, nearest to `origin` first.
func free_lots(origin: Vector2i = Vector2i(2, 2)) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in claimed:
		for lx in range(1, DISTRICT):
			for ly in range(1, DISTRICT):
				var t: Vector2i = d * DISTRICT + Vector2i(lx, ly)
				if is_buildable(t):
					out.append(t)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a, origin) < _dist2(b, origin))
	return out


func _dist2(a: Vector2i, b: Vector2i) -> int:
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


## The walkable tile a building's entrance faces: a road neighbour, preferring the one nearest town centre.
func door_for(tile: Vector2i) -> Vector2i:
	var best := tile
	var best_d := 1 << 30
	for pass_index in range(2):
		for n in NEIGHBORS:
			var c := tile + n
			var ok := is_road(c) if pass_index == 0 else walkable(c)
			if ok:
				var d := _dist2(c, Vector2i(2, 2))
				if d < best_d:
					best_d = d
					best = c
		if best != tile:
			return best
	return best


# --- districts ---------------------------------------------------------------------------------

func district_water(d: Vector2i) -> int:
	var count := 0
	for x in range(DISTRICT):
		for y in range(DISTRICT):
			if is_water(d * DISTRICT + Vector2i(x, y)):
				count += 1
	return count


## Wild trees standing on a district's interior (they are cleared, for wood, when it is claimed).
func district_trees(d: Vector2i) -> int:
	var count := 0
	for x in range(1, DISTRICT):
		for y in range(1, DISTRICT):
			if has_trees(d * DISTRICT + Vector2i(x, y)):
				count += 1
	return count


## Unclaimed districts that touch the city, most promising first (near the centre, little water).
func frontier() -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for d in claimed:
		for n in NEIGHBORS:
			var c: Vector2i = d + n
			if claimed.has(c) or seen.has(c):
				continue
			seen[c] = true
			if district_water(c) <= 4:
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	return out


func claim_district(d: Vector2i) -> void:
	claimed[d] = true
	rebuild_nav()


func bounds() -> Rect2i:
	if claimed.is_empty():
		return Rect2i(0, 0, 1, 1)
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for d in claimed:
		lo = Vector2i(mini(lo.x, d.x), mini(lo.y, d.y))
		hi = Vector2i(maxi(hi.x, d.x), maxi(hi.y, d.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


# --- navigation --------------------------------------------------------------------------------

func rebuild_nav() -> void:
	if claimed.is_empty():
		return
	var b := bounds()
	nav_rect = Rect2i(b.position * DISTRICT - Vector2i.ONE, b.size * DISTRICT + Vector2i(3, 3))
	nav.region = nav_rect
	nav.cell_size = Vector2.ONE
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	nav.fill_solid_region(nav_rect, true)
	for d in claimed:
		for x in range(DISTRICT + 1):
			for y in range(DISTRICT + 1):
				var t: Vector2i = d * DISTRICT + Vector2i(x, y)
				if nav_rect.has_point(t) and walkable(t):
					nav.set_point_solid(t, false)


func set_building_tile(id: int, tile: Vector2i, solid: bool) -> void:
	occupied[tile] = id
	if solid:
		solid_tiles[tile] = true
		if nav_rect.has_point(tile):
			nav.set_point_solid(tile, true)


func clear_building_tile(tile: Vector2i) -> void:
	occupied.erase(tile)
	if solid_tiles.erase(tile) and nav_rect.has_point(tile) and walkable(tile):
		nav.set_point_solid(tile, false)


## Tiles to walk (excluding the start). Empty if either end is unreachable or already there.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	if not nav_rect.has_point(from) or not nav_rect.has_point(to):
		return []
	if nav.is_point_solid(to) or nav.is_point_solid(from):
		return []
	var p := nav.get_id_path(from, to)
	if p.size() <= 1:
		return []
	return Array(p.slice(1))


func nearest_walkable(t: Vector2i) -> Vector2i:
	if walkable(t) and not nav.is_point_solid(t):
		return t
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					var c := t + Vector2i(dx, dy)
					if nav_rect.has_point(c) and not nav.is_point_solid(c):
						return c
	return t


# --- persistence ---------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list := []
	for d in claimed:
		list.append([d.x, d.y])
	return {"seed": world_seed, "claimed": list}


func load_dict(data: Dictionary) -> bool:
	if not data.get("claimed") is Array or not _is_number(data.get("seed")):
		return false
	for e in data.claimed:
		if not e is Array or e.size() != 2 or not _is_number(e[0]) or not _is_number(e[1]):
			return false
		if absf(e[0]) > 100000 or absf(e[1]) > 100000:
			return false
	set_seed(int(data.seed))
	claimed.clear()
	for e in data.claimed:
		claimed[Vector2i(int(e[0]), int(e[1]))] = true
	occupied.clear()
	solid_tiles.clear()
	rebuild_nav()
	return not claimed.is_empty()


static func _is_number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))
