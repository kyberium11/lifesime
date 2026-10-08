class_name RivalArt
extends RefCounted
## Builds the rival town of Redmarch (a walled town with a keep, towers and red banners) and the signpost that points
## towards it. Positions are local: the town centre is the origin, x runs east, the gate faces west towards the village.

const STONE := Color("8d8a86")
const DARK_STONE := Color("6f6c69")
const RED := Color("a4272b")
const ROOF := Color("8a3a2c")
const PLASTER := Color("d8c9a8")
const TIMBER := Color("6b4a2e")
const HALF := 34.0
const WALL_H := 3.6
const GATE_W := 9.0


static func build_town(art: CityArt) -> Node3D:
	var root := Node3D.new()
	root.name = "Redmarch"
	# Courtyard paving and the road to the gate.
	art.box(root, Vector3(0, 0.04, 0), Vector3(HALF * 2.0, 0.08, HALF * 2.0), Color("9a8f7c"))
	art.box(root, Vector3(-HALF - 14.0, 0.05, 0), Vector3(30.0, 0.06, 5.0), Color("8f8672"))
	# Walls: north, south, east solid; west with a gate gap.
	_wall(art, root, Vector3(0, 0, -HALF), Vector3(HALF * 2.0 + 1.0, WALL_H, 1.2))
	_wall(art, root, Vector3(0, 0, HALF), Vector3(HALF * 2.0 + 1.0, WALL_H, 1.2))
	_wall(art, root, Vector3(HALF, 0, 0), Vector3(1.2, WALL_H, HALF * 2.0 + 1.0))
	var side := (HALF * 2.0 - GATE_W) * 0.5
	_wall(art, root, Vector3(-HALF, 0, -(GATE_W * 0.5 + side * 0.5)), Vector3(1.2, WALL_H, side))
	_wall(art, root, Vector3(-HALF, 0, GATE_W * 0.5 + side * 0.5), Vector3(1.2, WALL_H, side))
	# Gatehouse: two towers and a beam over the opening.
	for z in [-1.0, 1.0]:
		_tower(art, root, Vector3(-HALF, 0, z * (GATE_W * 0.5 + 1.8)), 3.4, 9.0)
	art.box(root, Vector3(-HALF, WALL_H + 1.6, 0), Vector3(1.6, 1.4, GATE_W), TIMBER)
	for z in [-3.0, -1.0, 1.0, 3.0]:
		art.box(root, Vector3(-HALF - 0.2, 1.6, z), Vector3(0.18, 3.2, 0.18), Color("3a3a3c"))
	_banner(art, root, Vector3(-HALF - 1.0, WALL_H + 3.4, 0), 2.2)
	# Corner towers.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			if sx < 0.0:
				continue
			_tower(art, root, Vector3(sx * HALF, 0, sz * HALF), 4.4, 10.0)
	for sz in [-1.0, 1.0]:
		_tower(art, root, Vector3(-HALF, 0, sz * HALF), 4.4, 10.0)
	# The keep.
	art.box(root, Vector3(12, 5.5, 0), Vector3(13, 11, 13), DARK_STONE)
	art.box(root, Vector3(12, 11.4, 0), Vector3(14, 0.8, 14), STONE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_tower(art, root, Vector3(12 + sx * 7.0, 0, sz * 7.0), 2.6, 13.0)
	_banner(art, root, Vector3(12, 12.0, 0), 4.0)
	art.box(root, Vector3(5.4, 1.6, 0), Vector3(0.4, 3.2, 3.4), TIMBER)
	# Houses in rows, with steep roofs.
	var i := 0
	for hx in [-24.0, -12.0, -1.0]:
		for hz in [-24.0, -15.0, 15.0, 24.0]:
			_house(art, root, Vector3(hx + (3.0 if i % 2 == 0 else -2.0), 0, hz), i)
			i += 1
	for hz in [-24.0, 24.0]:
		_house(art, root, Vector3(24, 0, hz), i)
		i += 1
	# A drill yard with weapon racks and a banner pole.
	art.box(root, Vector3(24, 0.1, 0), Vector3(14, 0.1, 10), Color("7d725f"))
	for k in range(3):
		art.box(root, Vector3(20.0 + float(k) * 3.5, 1.0, 3.5), Vector3(0.3, 2.0, 2.4), TIMBER)
		art.box(root, Vector3(20.0 + float(k) * 3.5, 1.5, 3.5), Vector3(0.1, 0.1, 2.2), Color("c2c8cc"))
	var label := Label3D.new()
	label.text = "REDMARCH"
	label.font_size = 160
	label.pixel_size = 0.022
	label.modulate = Color("f2d9b8")
	label.outline_size = 24
	label.outline_modulate = Color("3a0f10")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(-HALF - 3.0, WALL_H + 11.0, 0)
	root.add_child(label)
	return root


static func _wall(art: CityArt, parent: Node3D, pos: Vector3, size: Vector3) -> void:
	art.box(parent, pos + Vector3(0, size.y * 0.5, 0), size, STONE)
	var along_x := size.x > size.z
	var length := size.x if along_x else size.z
	var n := int(length / 2.6)
	for k in range(n):
		var t := -length * 0.5 + (float(k) + 0.5) * length / float(n)
		var at := pos + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)) + Vector3(0, size.y + 0.35, 0)
		art.box(parent, at, Vector3(1.0 if along_x else size.x * 0.9, 0.7, size.z * 0.9 if along_x else 1.0), DARK_STONE)


static func _tower(art: CityArt, parent: Node3D, pos: Vector3, width: float, height: float) -> void:
	art.box(parent, pos + Vector3(0, height * 0.5, 0), Vector3(width, height, width), STONE)
	art.box(parent, pos + Vector3(0, height + 0.3, 0), Vector3(width + 0.8, 0.6, width + 0.8), DARK_STONE)
	art.cone(parent, pos + Vector3(0, height + 0.6 + width * 0.45, 0), width * 0.75, width * 0.9, RED, 0.0)


static func _banner(art: CityArt, parent: Node3D, pos: Vector3, size: float) -> void:
	art.box(parent, pos + Vector3(0, size * 0.6, 0), Vector3(0.18, size * 1.4, 0.18), TIMBER)
	art.box(parent, pos + Vector3(0, size * 1.0, size * 0.55), Vector3(0.08, size * 0.9, size * 1.0), RED)
	art.box(parent, pos + Vector3(0.05, size * 1.0, size * 0.55), Vector3(0.04, size * 0.4, size * 0.4), Color("e8c36a"))


static func _house(art: CityArt, parent: Node3D, pos: Vector3, index: int) -> void:
	var w := 6.0 + float(index % 3)
	var d := 4.6
	var body := PLASTER.darkened(0.06 * float(index % 3))
	art.box(parent, pos + Vector3(0, 1.8, 0), Vector3(w, 3.6, d), body)
	for side in [-1.0, 1.0]:
		var slab := art.box(parent, pos + Vector3(0, 4.4, side * d * 0.27), Vector3(w + 0.8, 0.35, d * 0.62), ROOF.darkened(0.05 * float(index % 4)))
		slab.rotation.x = side * deg_to_rad(-34.0) * -1.0
	art.box(parent, pos + Vector3(0, 1.0, d * 0.5 + 0.02), Vector3(1.0, 2.0, 0.08), TIMBER)
	art.box(parent, pos + Vector3(w * 0.25, 2.3, d * 0.5 + 0.02), Vector3(0.9, 0.9, 0.08), Color("f1d98a"))
	art.box(parent, pos + Vector3(w * 0.3, 5.0, -0.8), Vector3(0.8, 2.0, 0.8), DARK_STONE)


## A signpost at the village's edge pointing east to Redmarch.
static func build_signpost(art: CityArt, metres: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Signpost"
	art.box(root, Vector3(0, 1.5, 0), Vector3(0.3, 3.0, 0.3), TIMBER)
	var board := art.box(root, Vector3(1.4, 2.5, 0), Vector3(2.8, 0.7, 0.14), Color("c9b48a"))
	board.name = "board"
	art.box(root, Vector3(3.0, 2.5, 0), Vector3(0.5, 0.7, 0.14), Color("c9b48a")).rotation.y = deg_to_rad(45.0)
	var label := Label3D.new()
	label.text = "Redmarch  %d m" % (int(round(metres / 10.0)) * 10)
	label.font_size = 56
	label.pixel_size = 0.014
	label.modulate = Color("3a2412")
	label.position = Vector3(1.4, 2.5, 0.09)
	root.add_child(label)
	var back := Label3D.new()
	back.text = "Redmarch  %d m" % (int(round(metres / 10.0)) * 10)
	back.font_size = 56
	back.pixel_size = 0.014
	back.modulate = Color("3a2412")
	back.position = Vector3(1.4, 2.5, -0.09)
	back.rotation.y = PI
	root.add_child(back)
	return root
