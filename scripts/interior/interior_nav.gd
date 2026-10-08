class_name InteriorNav
extends RefCounted
## Walking inside a room: a grid over the floor with furniture and walls blocked, and A* paths between points.

const CELL := 0.3
const PAD := 0.07

var size := Vector2(6, 5)
var _grid := AStarGrid2D.new()
var _cols := 0
var _rows := 0
var signature := ""


func build(b: Dictionary) -> void:
	size = Interiors.dims(str(b.kind), int(b.level))
	_cols = int(ceil(size.x / CELL))
	_rows = int(ceil(size.y / CELL))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _cols, _rows)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = Vector2(CELL * 0.5, CELL * 0.5)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var door := Interiors.door_x(size)
	var rects: Array = []
	for it in Interiors.furniture_of(b):
		if str(it.role) in ["rug", "tv", "computer", "decor", "lamp"] or float(it.get("y", 0.0)) > 0.0:
			continue
		rects.append(Interiors.rect_of(str(it.model), int(it.rot), float(it.x), float(it.z)).grow(PAD))
	for cx in range(_cols):
		for cy in range(_rows):
			var p := Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL)
			var solid := p.x < 0.18 or p.y < 0.18 or p.x > size.x - 0.18 or p.y > size.y - 0.18
			for r in rects:
				if (r as Rect2).has_point(p):
					solid = true
					break
			# The doorway column stays open down to the wall.
			if absf(p.x - door) < 0.45 and p.y > size.y - 1.2:
				solid = false
			_grid.set_point_solid(Vector2i(cx, cy), solid)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, _cols - 1), clampi(int(p.y / CELL), 0, _rows - 1))


func is_open(p: Vector2) -> bool:
	return not _grid.is_point_solid(_cell_of(p))


## The open cell closest to a point (the point itself if it is open).
func nearest_open(p: Vector2) -> Vector2:
	var c := _cell_of(p)
	if not _grid.is_point_solid(c):
		return Vector2((float(c.x) + 0.5) * CELL, (float(c.y) + 0.5) * CELL)
	for ring in range(1, 14):
		var best := Vector2i(-1, -1)
		var best_d := 1.0e9
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var n := Vector2i(c.x + dx, c.y + dy)
				if n.x < 0 or n.y < 0 or n.x >= _cols or n.y >= _rows or _grid.is_point_solid(n):
					continue
				var d := float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = n
		if best.x >= 0:
			return Vector2((float(best.x) + 0.5) * CELL, (float(best.y) + 0.5) * CELL)
	return p


## A route from one point to another, as room positions (empty if there is none).
func path(from: Vector2, to: Vector2) -> Array:
	var a := nearest_open(from)
	var b := nearest_open(to)
	var ids := _grid.get_id_path(_cell_of(a), _cell_of(b))
	var out: Array = []
	for id in ids:
		out.append(Vector2((float(id.x) + 0.5) * CELL, (float(id.y) + 0.5) * CELL))
	if not out.is_empty():
		out.remove_at(0)
	return out
