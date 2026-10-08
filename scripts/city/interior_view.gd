class_name InteriorView
extends Node3D
## One building's inside, built from its furniture list and kept in step with the residents who are in it.
## The room sits far from the city (at ORIGIN) so the same scene can show it. Room units are metres of the
## furniture kit; villagers are drawn at FurnitureDb.VILLAGER_SCALE so counters reach their waist.

const ORIGIN := Vector3(4000.0, 0.0, 4000.0)
const WALL_SCALE := 1.0
const CHIEF_RADIUS := 0.24
const FLOOR_Y := 0.0

var sim: LifeSim
var building: Dictionary = {}
var size := Vector2(6, 5)
var art: CityArt
var _furniture_nodes: Dictionary = {}  # item id -> Node3D
var _actors: Dictionary = {}  # resident index -> Node3D
var _scene_cache: Dictionary = {}
var _lights: Array = []
var _built_signature := ""
var nav := InteriorNav.new()
var _animals: Dictionary = {}


func to_world(p: Vector2) -> Vector3:
	return ORIGIN + Vector3(p.x, 0.0, p.y)


func to_room(world: Vector3) -> Vector2:
	return Vector2(world.x - ORIGIN.x, world.z - ORIGIN.z)


func _scene(model: String) -> PackedScene:
	if not _scene_cache.has(model):
		_scene_cache[model] = load("res://assets/kenney/furniture/%s.glb" % model)
	return _scene_cache[model]


func _spawn(model: String, parent: Node3D, scale_: float) -> Node3D:
	var node: Node3D = (_scene(model) as PackedScene).instantiate()
	node.scale = Vector3.ONE * scale_
	parent.add_child(node)
	return node


func setup(sim_: LifeSim, art_: CityArt, b: Dictionary) -> void:
	sim = sim_
	art = art_
	building = b
	position = ORIGIN
	Interiors.ensure(sim, b)
	size = Interiors.dims(str(b.kind), int(b.level))
	_build_room()
	_sync_furniture()


func _signature() -> String:
	var parts: Array = [str(building.id), str(building.level)]
	for it in Interiors.furniture_of(building):
		parts.append("%d:%s:%.2f:%.2f:%d" % [int(it.id), it.model, float(it.x), float(it.z), int(it.rot)])
	return "|".join(parts)


# --- the shell: floor, walls, door, windows, light -----------------------------------------------------------------

func _build_room() -> void:
	for c in get_children():
		c.queue_free()
	_furniture_nodes.clear()
	_animals.clear()
	_actors.clear()
	_lights.clear()
	var w := int(size.x)
	var d := int(size.y)
	var floor_color := _floor_color()
	# A slab under the whole room so there are no gaps, with the kit's floor tiles on top.
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(size.x + 0.4, 0.2, size.y + 0.4)
	slab.mesh = slab_mesh
	var slab_material := StandardMaterial3D.new()
	slab_material.albedo_color = Color("3b3a42")
	slab.material_override = slab_material
	slab.position = Vector3(size.x * 0.5, -0.12, size.y * 0.5)
	add_child(slab)
	for ix in range(w):
		for iz in range(d):
			var tile := _spawn("floorFull", self, 1.0)
			tile.position = Vector3(float(ix), -0.02, float(iz) + 1.0)
			_tint(tile, floor_color.lerp(floor_color.darkened(0.06), float((ix + iz) % 2)))
	var door_cell := int(Interiors.door_x(size))
	# North wall faces south (rot 0); windows now and then.
	for ix in range(w):
		var piece := "wallWindow" if ix % 3 == 1 and str(building.kind) != "bathhouse" else "wall"
		var n := _spawn(piece, self, WALL_SCALE)
		n.position = Vector3(float(ix), 0.0, 0.0)
		_tint_wall(n)
	# South wall faces north (rot 180) with the doorway.
	for ix in range(w):
		var piece2 := "wallDoorway" if ix == door_cell else ("wallWindow" if ix % 3 == 0 and ix != door_cell and str(building.kind) != "bathhouse" else "wall")
		var s := _spawn(piece2, self, WALL_SCALE)
		s.position = Vector3(float(ix) + 1.0, 0.0, size.y)
		s.rotation.y = PI
		_tint_wall(s)
	for iz in range(d):
		var wpiece := "wallWindow" if iz % 3 == 1 else "wall"
		var west := _spawn(wpiece, self, WALL_SCALE)
		west.position = Vector3(0.0, 0.0, float(iz) + 1.0)
		west.rotation.y = PI * 0.5
		_tint_wall(west)
		var east := _spawn("wall", self, WALL_SCALE)
		east.position = Vector3(size.x, 0.0, float(iz))
		east.rotation.y = PI * 1.5
		_tint_wall(east)
	# Warm lights so the room is lit by day and night.
	var rows := maxi(1, int(size.y / 4.0) + 1)
	var cols := maxi(1, int(size.x / 4.0) + 1)
	for ix in range(cols):
		for iz in range(rows):
			var lamp := OmniLight3D.new()
			lamp.position = Vector3((float(ix) + 0.5) * size.x / float(cols), 2.6, (float(iz) + 0.5) * size.y / float(rows))
			lamp.omni_range = 7.5
			lamp.light_energy = 0.55
			lamp.light_color = Color("ffe2b0")
			lamp.shadow_enabled = false
			add_child(lamp)
			_lights.append(lamp)


func _floor_color() -> Color:
	match str(building.kind):
		"home": return Color("c9a77c")
		"market": return Color("b8b2a2")
		"workshop": return Color("8f8a82")
		"library": return Color("a8845a")
		"bathhouse": return Color("a9c4cc")
		"office": return Color("9aa3ad")
		"clinic": return Color("d7e3e6")
	return Color("c9a77c")


func _wall_color() -> Color:
	match str(building.kind):
		"home": return Color("e9dcc3")
		"market": return Color("e2d5b0")
		"workshop": return Color("c4bfb4")
		"library": return Color("d6c4a2")
		"bathhouse": return Color("cfe3e8")
		"office": return Color("dfe3e8")
		"clinic": return Color("eef4f4")
	return Color("e9dcc3")


func _tint(node: Node3D, color: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		(mi as MeshInstance3D).material_override = m


func _tint_wall(node: Node3D) -> void:
	var color := _wall_color()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		var original: Material = mesh_instance.get_active_material(0)
		if original is StandardMaterial3D:
			var m := (original as StandardMaterial3D).duplicate() as StandardMaterial3D
			# Keep window glass and door frames as they are; paint the plain wall.
			if (original as StandardMaterial3D).albedo_color.get_luminance() > 0.7 and not (original as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				m.albedo_color = color
			mesh_instance.material_override = m


# --- furniture ---------------------------------------------------------------------------------------------------------

func _node_position(it: Dictionary) -> Vector3:
	var model := str(it.model)
	var s := FurnitureDb.scale_of(model)
	var rot := deg_to_rad(float(it.rot))
	var c := FurnitureDb.center_offset(model) * s
	# World offset of the footprint centre from the model origin after rotating about the vertical axis.
	var rc := Vector2(c.x * cos(rot) + c.y * sin(rot), -c.x * sin(rot) + c.y * cos(rot))
	return Vector3(float(it.x) - rc.x, float(it.get("y", 0.0)), float(it.z) - rc.y)


func _sync_furniture() -> void:
	var seen := {}
	for it in Interiors.furniture_of(building):
		var id := int(it.id)
		seen[id] = true
		if _furniture_nodes.has(id) and is_instance_valid(_furniture_nodes[id]):
			continue
		var model := str(it.model)
		var node := _spawn(model, self, FurnitureDb.scale_of(model))
		node.position = _node_position(it)
		node.rotation.y = deg_to_rad(float(it.rot))
		node.set_meta("item_id", id)
		if str(building.kind) == "farm" and str(it.role) == "crate":
			_tint(node, Color("d9b95b") if str(it.model) == "cardboardBoxOpen" else Color("c9a46a"))
		_furniture_nodes[id] = node
		if str(it.role) == "lamp":
			var glow := OmniLight3D.new()
			glow.position = Vector3(float(it.x), FurnitureDb.height(model) + 0.15, float(it.z))
			glow.omni_range = 2.8
			glow.light_energy = 0.7
			glow.light_color = Color("ffd89a")
			add_child(glow)
			node.set_meta("glow", glow)
	for id in _furniture_nodes.keys():
		if not seen.has(id):
			var gone: Node3D = _furniture_nodes[id]
			_furniture_nodes.erase(id)
			if is_instance_valid(gone):
				if gone.has_meta("glow"):
					(gone.get_meta("glow") as Node).queue_free()
				gone.queue_free()
	_built_signature = _signature()
	nav.build(building)


## Rebuild the furniture if the list changed (something was bought, moved or removed).
func refresh_if_changed() -> void:
	if _signature() != _built_signature:
		_sync_furniture()


# --- residents inside ---------------------------------------------------------------------------------------------------

func _who_is_inside() -> Array:
	var out: Array = []
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if sim.is_inside(r) and int(r.target_id) == int(building.id):
			out.append(i)
		elif str(building.kind) == "farm" and str(r.action) == "farm" and int(r.target_id) == int(building.id) and r.route.is_empty() and float(r.remaining) > 0.0:
			out.append(i)
	return out


## Where someone does their current activity. Resting people drift between the armchair, sofa and bench.
func _pick_item(r: Dictionary, index: int) -> Dictionary:
	var action := str(r.action)
	var who := str(r.name)
	if action in ["rest", "socialize"]:
		var options: Array = []
		for role in ["armchair", "sofa", "bench"]:
			for it in Interiors.furniture_of(building):
				if str(it.role) == role and Ownership.may_use(sim, who, it):
					options.append(it)
		if not options.is_empty():
			return options[(int(Time.get_ticks_msec() / 30000) + index) % options.size()]
	return Interiors.find_item(sim, building, action, who)


const WALK_SPEED := 1.5


func _sync_actors(dt: float) -> void:
	var inside := _who_is_inside()
	var used := {}
	for i in inside:
		var r: Dictionary = sim.residents[i]
		var node: Node3D = _actors.get(i, null)
		var look: String = Catalog.LOOKS[int(r.look) % Catalog.LOOKS.size()]
		if node == null or not is_instance_valid(node):
			node = art.build_character(look, FurnitureDb.VILLAGER_SCALE * (0.9 if int(r.age) < 18 else 1.0))
			add_child(node)
			node.position = Vector3(Interiors.door_x(size), FLOOR_Y, size.y - 0.3)
			node.set_meta("goal", Vector2(-99, -99))
			node.set_meta("path", [])
			_actors[i] = node
		var item := _pick_item(r, i)
		var anim_name := "idle"
		var goal := Vector2(Interiors.door_x(size), size.y - 0.9)
		var face := PI
		var pose := "stand"
		if not item.is_empty():
			var index := int(used.get(int(item.id), 0))
			used[int(item.id)] = index + 1
			var slot := Interiors.slot_of(item, index)
			goal = slot.pos
			face = deg_to_rad(float(slot.face))
			pose = str(slot.pose)
			if pose == "stand":
				anim_name = {"cook": "interact-right", "work": "interact-left", "study": "pick-up", "wash": "emote-yes"}.get(str(r.action), "idle")
		# Plan a walk round the furniture whenever the destination changes.
		var here := Vector2(node.position.x, node.position.z)
		var last_goal: Vector2 = node.get_meta("goal")
		if goal.distance_to(last_goal) > 0.15:
			node.set_meta("goal", goal)
			node.set_meta("path", nav.path(here, goal))
		var path: Array = node.get_meta("path")
		var walking := false
		if not path.is_empty():
			walking = true
			var next: Vector2 = path[0]
			var to_next := next - here
			if to_next.length() < 0.07:
				path.pop_front()
			else:
				var step := minf(to_next.length(), WALK_SPEED * dt)
				var moved := here + to_next.normalized() * step
				node.position = Vector3(moved.x, FLOOR_Y, moved.y)
				node.rotation.y = lerp_angle(node.rotation.y, atan2(to_next.x, to_next.y), minf(1.0, dt * 9.0))
		var model: Node3D = node.get_child(0)
		if walking:
			model.rotation.x = lerpf(model.rotation.x, 0.0, minf(1.0, dt * 8.0))
			model.position.y = lerpf(model.position.y, 0.0, minf(1.0, dt * 8.0))
			art.play(node, "walk", 1.0)
			continue
		# Arrived: settle onto the spot (a bed, a seat, a place at the stove).
		var target := Vector3(goal.x, FLOOR_Y, goal.y)
		node.position = node.position.lerp(target, minf(1.0, dt * 5.0))
		node.rotation.y = lerp_angle(node.rotation.y, face, minf(1.0, dt * 6.0))
		if pose == "lie":
			model.rotation.x = lerpf(model.rotation.x, -PI * 0.5, minf(1.0, dt * 4.0))
			model.position.y = lerpf(model.position.y, 0.55, minf(1.0, dt * 4.0))
			art.play(node, "idle", 0.2)
		else:
			model.rotation.x = lerpf(model.rotation.x, 0.0, minf(1.0, dt * 6.0))
			model.position.y = lerpf(model.position.y, 0.0, minf(1.0, dt * 6.0))
			art.play(node, "sit" if pose == "sit" else anim_name, 1.0)
	for i in _actors.keys():
		if not i in inside:
			var gone: Node3D = _actors[i]
			_actors.erase(i)
			if is_instance_valid(gone):
				gone.queue_free()


func _process(dt: float) -> void:
	if sim == null:
		return
	refresh_if_changed()
	_sync_actors(dt)
	if str(building.kind) == "farm":
		_sync_animals(dt)


## The barn's animals wander between open spots on the floor.
func _sync_animals(dt: float) -> void:
	var herd := Farming.animals_of(building)
	var alive := {}
	var day := sim.day()
	for a in herd:
		var id := int(a.id)
		alive[id] = true
		var node: Node3D = _animals.get(id, null)
		if node == null or not is_instance_valid(node):
			node = art._make_animal(str(a.kind))
			add_child(node)
			var spawn_at := nav.nearest_open(Vector2(1.5 + fmod(float(id) * 1.7, size.x - 3.0), 1.5 + fmod(float(id) * 2.3, size.y - 3.0)))
			node.position = Vector3(spawn_at.x, FLOOR_Y, spawn_at.y)
			node.set_meta("goal", spawn_at)
			node.set_meta("wait", randf() * 3.0)
			_animals[id] = node
		var spec: Dictionary = Farming.ANIMALS[str(a.kind)]
		var growth := clampf(float(day - int(a.born)) / float(spec.adult_days), 0.0, 1.0)
		node.scale = Vector3.ONE * lerpf(0.5, 1.0, growth) * {"chicken": 0.9, "sheep": 1.0, "cow": 1.05, "pig": 1.0}[str(a.kind)]
		var wait := float(node.get_meta("wait")) - dt
		var goal: Vector2 = node.get_meta("goal")
		if wait <= 0.0:
			goal = nav.nearest_open(Vector2(randf_range(1.0, size.x - 1.0), randf_range(1.0, size.y - 1.4)))
			node.set_meta("goal", goal)
			wait = randf_range(2.0, 6.0)
		node.set_meta("wait", wait)
		var to_goal := goal - Vector2(node.position.x, node.position.z)
		if to_goal.length() > 0.05:
			var speed_ := 0.5 if str(a.kind) == "chicken" else 0.3
			var step := to_goal.normalized() * minf(to_goal.length(), speed_ * dt)
			node.position += Vector3(step.x, 0.0, step.y)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(to_goal.x, to_goal.y), minf(1.0, dt * 6.0))
	for id in _animals.keys():
		if not alive.has(id):
			var gone: Node3D = _animals[id]
			_animals.erase(id)
			if is_instance_valid(gone):
				gone.queue_free()


# --- queries for the player ---------------------------------------------------------------------------------------------

## Is this room position blocked for a person standing there?
func blocked(p: Vector2) -> bool:
	if p.x < CHIEF_RADIUS or p.y < CHIEF_RADIUS or p.x > size.x - CHIEF_RADIUS or p.y > size.y - CHIEF_RADIUS - 0.0:
		# The doorway in the south wall lets people out.
		var door := Interiors.door_x(size)
		if p.y > size.y - CHIEF_RADIUS and absf(p.x - door) < 0.45 and p.y < size.y + 0.8:
			return false
		return true
	for it in Interiors.furniture_of(building):
		if str(it.role) in ["rug", "decor", "lamp"]:
			continue
		var r := Interiors.rect_of(str(it.model), int(it.rot), float(it.x), float(it.z)).grow(CHIEF_RADIUS * 0.6)
		if str(it.role) in ["bed", "sofa", "armchair", "seat", "bench"] and Vector2(float(it.x), float(it.z)).distance_to(p) < 0.45:
			continue
		if r.has_point(p):
			return true
	return false


func at_door(p: Vector2) -> bool:
	return p.y > size.y - 0.9 and absf(p.x - Interiors.door_x(size)) < 0.9


## The furniture closest to a room position, within `radius`.
func nearest_item(p: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for it in Interiors.furniture_of(building):
		if str(it.role) == "rug":
			continue
		var rect := Interiors.rect_of(str(it.model), int(it.rot), float(it.x), float(it.z))
		var nearest := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		var d := p.distance_to(nearest)
		if d < best_d:
			best_d = d
			best = it
	return best


func item_anchor(it: Dictionary) -> Vector3:
	var model := str(it.model)
	return to_world(Vector2(float(it.x), float(it.z))) + Vector3(0, FurnitureDb.height(model) + 0.25, 0)


func actor_anchor(index: int) -> Vector3:
	var node: Node3D = _actors.get(index, null)
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	return node.global_position + Vector3(0, 1.45, 0)


func actor_indices() -> Array:
	return _actors.keys()
