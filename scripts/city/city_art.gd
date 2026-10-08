class_name CityArt
extends Node3D
## Renders the city with Kenney (CC0) models: endless terrain in chunks, auto-tiled roads, buildings that
## swap models as they level up, construction sites, crops that grow, animated residents and the chief.
## Everything is driven by LifeSim state; nothing here changes the simulation.

const PACK_SCALE := {"suburban": 4.0, "commercial": 4.0, "industrial": 4.0, "roads": 4.0, "nature": 2.4, "characters": 0.55}
const FIT_WIDTH := 3.3
const CHUNK_RADIUS := 5
const DISTRICT_UNITS := CityMap.DISTRICT * CityMap.TILE
## Directions in the order road pieces rotate: E, N, W, S.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1)]
const TREES := ["tree_default", "tree_oak", "tree_fat", "tree_simple", "tree_detailed", "tree_tall", "tree_thin", "tree_small"]
const PINES := ["tree_pineDefaultA", "tree_pineRoundA", "tree_pineTallA", "tree_pineSmallA", "tree_pineRoundC"]
const FALL_OK := ["tree_default", "tree_oak", "tree_fat", "tree_simple", "tree_detailed", "tree_tall", "tree_thin", "tree_small"]
const ROCKS := ["rock_largeA", "rock_largeB", "rock_smallA", "rock_smallC", "stone_largeA", "rock_tallA"]
const FLOWERS := ["flower_redA", "flower_yellowA", "flower_purpleA", "flower_redB", "flower_yellowB", "flower_purpleB", "flower_redC"]
const GROUND_CLAIMED := {"Spring": Color("86bd62"), "Summer": Color("7bb85a"), "Autumn": Color("b9a560"), "Winter": Color("dfe8ee")}
const GROUND_WILD := {"Spring": Color("5f9a4a"), "Summer": Color("579244"), "Autumn": Color("94803f"), "Winter": Color("c9d5dc")}

var sim: LifeSim
var actors: Array[Node3D] = []
var chief: Node3D
var select_ring: MeshInstance3D
var hover_zone: MeshInstance3D
var sun: DirectionalLight3D
var sky_environment: Environment
var rain: Node3D
var material_cache := {}
var chunks: Dictionary = {}
var _festival_node: Node3D = null
var _caravan_node: Node3D = null
var _caravan_name := ""
var _rival_node: Node3D = null
var _sign_node: Node3D = null
var _chief_weapon_shown := "?"
var _blood_decals: Array = []
var _corpses: Array = []
var _festival_name := ""
var _firework_timer := 0.0
var _mob_nodes: Dictionary = {}  # mob id -> node
var _zombie_overlay: StandardMaterial3D
var _raider_overlay: StandardMaterial3D
var _soldier_overlay: StandardMaterial3D
var _tile_nodes: Dictionary = {}  # wild tile -> trees/rocks standing on it, so they can be felled or mined away
var building_nodes: Dictionary = {}
var lamp_spots: Array = []
var lamp_pool: Array = []
var frontier_nodes: Array = []
var frontier_on := false
var fx: Array = []

var _scenes := {}
var _fits := {}
var _season_drawn := ""
var _focus := Vector3.ZERO
var _claimed_signature := ""
var _lamp_timer := 0.0
var _ground_claimed := StandardMaterial3D.new()
var _ground_wild := StandardMaterial3D.new()
var _water_material := StandardMaterial3D.new()
var _wood := StandardMaterial3D.new()
var _frontier_material := StandardMaterial3D.new()
var _daylight := 1.0


# --- primitives -----------------------------------------------------------------------------------------

func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if material_cache.has(key):
		return material_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	material_cache[key] = m
	return m


func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


func cone(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 14
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 12
	shape.rings = 6
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


func clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# --- models -----------------------------------------------------------------------------------------------

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load("res://assets/kenney/%s.glb" % path)
	return _scenes[path]


func _bounds(node: Node, root: Node) -> AABB:
	var box_ := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != root and cur != null:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			var world := xf * mi.mesh.get_aabb()
			box_ = world if first else box_.merge(world)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box_


## Uniform scale that makes a building fill (but not overflow) one tile.
func fit_scale(path: String) -> float:
	if not _fits.has(path):
		var inst: Node3D = _scene(path).instantiate()
		var b := _bounds(inst, inst)
		inst.free()
		var pack := path.get_slice("/", 0)
		var base: float = PACK_SCALE[pack]
		_fits[path] = {"scale": minf(base, FIT_WIDTH / maxf(0.2, maxf(b.size.x, b.size.z))), "height": b.size.y}
	return float(_fits[path].scale)


func model_height(path: String) -> float:
	fit_scale(path)
	return float(_fits[path].height) * float(_fits[path].scale)


func spawn(path: String, pos: Vector3 = Vector3.ZERO, scale_mult: float = 1.0, parent: Node3D = null, fit: bool = false) -> Node3D:
	var inst: Node3D = _scene(path).instantiate()
	var s: float = fit_scale(path) if fit else float(PACK_SCALE[path.get_slice("/", 0)])
	inst.scale = Vector3.ONE * s * scale_mult
	inst.position = pos
	(parent if parent != null else self).add_child(inst)
	return inst


# --- setup ----------------------------------------------------------------------------------------------------

func generate(sim_: LifeSim) -> void:
	sim = sim_
	for m in [_ground_claimed, _ground_wild]:
		(m as StandardMaterial3D).roughness = 1.0
	_water_material.albedo_color = Color("4d9fd0")
	_water_material.roughness = 0.2
	_water_material.metallic = 0.1
	_wood.albedo_color = Color("b08a5a")
	_wood.roughness = 0.9
	_frontier_material.albedo_color = Color(0.3, 0.85, 0.95, 0.22)
	_frontier_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frontier_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	sky_environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b9d7d1")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e2eedb")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 135.0
	env.fog_light_color = Color("b9d7d1")
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("fff0cd")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.4
	add_child(sun)
	rain = Node3D.new()
	add_child(rain)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(160):
		box(rain, Vector3(rng.randf_range(-26, 26), rng.randf_range(0, 18), rng.randf_range(-26, 26)), Vector3(0.04, 0.9, 0.04), Color("b3d1d8"))
	for i in range(8):
		var light := OmniLight3D.new()
		light.omni_range = 11.0
		light.light_color = Color("ffcf86")
		light.light_energy = 0.0
		light.shadow_enabled = false
		add_child(light)
		lamp_pool.append(light)
	select_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.72
	select_ring.mesh = ring_mesh
	select_ring.scale = Vector3(1, 0.2, 1)
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("f0b64a")
	ring_material.emission_enabled = true
	ring_material.emission = Color("f0b64a")
	ring_material.emission_energy_multiplier = 1.4
	select_ring.material_override = ring_material
	add_child(select_ring)
	hover_zone = MeshInstance3D.new()
	var zone_mesh := BoxMesh.new()
	zone_mesh.size = Vector3(1, 0.08, 1)
	hover_zone.mesh = zone_mesh
	var zone_material := StandardMaterial3D.new()
	zone_material.albedo_color = Color(0.94, 0.71, 0.29, 0.32)
	zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_zone.material_override = zone_material
	hover_zone.visible = false
	add_child(hover_zone)
	chief = build_chief()
	chief.position = CityMap.tile_pos_to_world(sim.chief_pos)
	chief.rotation.y = PI  # start facing away from the default camera
	add_child(chief)
	_apply_season()
	update_world(chief.position, true)
	_sync_buildings(0.0)
	_ensure_actors()


func _apply_season() -> void:
	_season_drawn = sim.season()
	_ground_claimed.albedo_color = GROUND_CLAIMED[_season_drawn]
	_ground_wild.albedo_color = GROUND_WILD[_season_drawn]


# --- characters --------------------------------------------------------------------------------------------------

func build_character(look: String, scale_: float = 0.55) -> Node3D:
	var node: Node3D = _scene("characters/%s" % look).instantiate()
	node.scale = Vector3.ONE * scale_
	var holder := Node3D.new()
	holder.add_child(node)
	for ap in node.find_children("*", "AnimationPlayer", true, false):
		var player := ap as AnimationPlayer
		for name_ in player.get_animation_list():
			var anim := player.get_animation(name_)
			anim.loop_mode = Animation.LOOP_NONE if name_ == "die" else Animation.LOOP_LINEAR
		holder.set_meta("anim", player)
		player.play("idle")
	holder.set_meta("current", "idle")
	return holder


func play(character: Node3D, anim_name: String, speed: float = 1.0) -> void:
	var player: AnimationPlayer = character.get_meta("anim", null)
	if player == null:
		return
	if str(character.get_meta("current", "")) != anim_name and player.has_animation(anim_name):
		character.set_meta("current", anim_name)
		player.play(anim_name, 0.18)
	player.speed_scale = speed


## The village chief: the old man with glasses, plus a long white beard and a walking staff.
func build_chief() -> Node3D:
	var holder := build_character(Catalog.CHIEF_LOOK, 0.62)
	var model: Node3D = holder.get_child(0)
	var head: Node3D = model.find_child("head", true, false)
	var arm: Node3D = model.find_child("arm-right", true, false)
	if head != null:
		# Head-local units: the head mesh is 8 wide, 8 tall, origin at its base, face toward +Z.
		var white := material(Color("f4f4f0"))
		var beard := MeshInstance3D.new()
		var beard_mesh := BoxMesh.new()
		beard_mesh.size = Vector3(7.4, 5.0, 2.0)
		beard.mesh = beard_mesh
		beard.material_override = white
		beard.position = Vector3(0, 1.5, 4.0)
		head.add_child(beard)
		var moustache := MeshInstance3D.new()
		var moustache_mesh := BoxMesh.new()
		moustache_mesh.size = Vector3(5.0, 1.2, 1.4)
		moustache.mesh = moustache_mesh
		moustache.material_override = white
		moustache.position = Vector3(0, 3.5, 4.1)
		head.add_child(moustache)
		for side in [-1.0, 1.0]:
			var brow := MeshInstance3D.new()
			var brow_mesh := BoxMesh.new()
			brow_mesh.size = Vector3(2.4, 0.7, 0.8)
			brow.mesh = brow_mesh
			brow.material_override = white
			brow.position = Vector3(side * 1.8, 5.6, 4.1)
			head.add_child(brow)
	if arm != null:
		# Arm-local units (1 = one model unit): the hand is near the bottom of the arm.
		var staff := Node3D.new()
		staff.position = Vector3(-0.2, -0.75, 0.25)
		staff.name = "staff"
		arm.add_child(staff)
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.05
		pole_mesh.bottom_radius = 0.06
		pole_mesh.height = 2.5
		pole.mesh = pole_mesh
		pole.material_override = material(Color("7a5230"))
		pole.position = Vector3(0, 0.55, 0)
		staff.add_child(pole)
		var orb := MeshInstance3D.new()
		var orb_mesh := SphereMesh.new()
		orb_mesh.radius = 0.15
		orb_mesh.height = 0.3
		orb.mesh = orb_mesh
		var orb_material := StandardMaterial3D.new()
		orb_material.albedo_color = Color("e8c36a")
		orb_material.emission_enabled = true
		orb_material.emission = Color("ffd98a")
		orb_material.emission_energy_multiplier = 0.8
		orb.material_override = orb_material
		orb.position = Vector3(0, 1.85, 0)
		staff.add_child(orb)
	return holder


func _ensure_actors() -> void:
	while actors.size() < sim.residents.size():
		var i := actors.size()
		var r: Dictionary = sim.residents[i]
		var look: String = Catalog.LOOKS[int(r.look) % Catalog.LOOKS.size()]
		var actor := build_character(look)
		actor.position = CityMap.tile_pos_to_world(Vector2(r.pos[0], r.pos[1]))
		add_child(actor)
		actors.append(actor)
		_pop(actor)


func _animate_resident(i: int, dt: float) -> void:
	var r: Dictionary = sim.residents[i]
	var actor := actors[i]
	var inside := sim.is_inside(r)
	actor.visible = not inside
	var target := CityMap.tile_pos_to_world(Vector2(r.pos[0], r.pos[1]))
	var delta := target - actor.position
	var moving: bool = delta.length() > 0.12 or not r.route.is_empty()
	actor.position = actor.position.lerp(target, minf(1.0, dt * 9.0))
	if inside:
		return
	(actor.get_child(0) as Node3D).scale = Vector3.ONE * Lifecycle.body_scale(r)
	if float(r.get("down_until", 0.0)) > sim.minutes:
		play(actor, "die")
		_update_props(actor, r)
		return
	var t := Time.get_ticks_msec() * 0.001 + i * 1.7
	var anim_name := "idle"
	var speed_scale := 1.0
	var foe := _foe_near(actor)
	var face := Vector3.ZERO
	var talk_state: String = str(sim.talking.get(i, ""))
	if talk_state != "":
		# In conversation: stand still, face the other person, gesture while speaking, nod while listening.
		var partner := int(sim.talk_with.get(i, -1))
		var toward: Vector3 = chief.position if partner < 0 or partner >= actors.size() else actors[partner].position
		face = toward - actor.position
		if talk_state.begins_with("speak"):
			anim_name = ["emote-yes", "interact-right", "interact-left"][int(t / 1.7) % 3]
		elif int(t / 3.0) % 2 == 0:
			anim_name = "emote-yes"
	elif foe != Vector3.ZERO:
		anim_name = "attack-melee-right"
		speed_scale = 1.2
		face = foe - actor.position
	elif not (r.get("job", {}) as Dictionary).is_empty() and str(r.job.kind) != "guard" and str(r.job.phase) == "work":
		var res: Array = r.job.res
		face = CityMap.tile_pos_to_world(Vector2(res[0], res[1])) - actor.position
		match str(r.job.kind):
			"chop":
				anim_name = "attack-melee-right"
				speed_scale = 1.15
			"mine":
				anim_name = "attack-melee-right"
				speed_scale = 0.8
			"water":
				anim_name = "pick-up"
	elif moving:
		anim_name = "walk"
		face = delta
	else:
		match str(r.action):
			"socialize":
				anim_name = "emote-yes" if int(t / 2.5) % 2 == 0 else "interact-right"
				var buddy := _nearest_actor(i, 7.0)
				if buddy >= 0:
					face = actors[buddy].position - actor.position
			"play": anim_name = "sprint"
			"exercise": anim_name = "attack-kick-right"
			"farm", "gather": anim_name = "pick-up"
			"repair": anim_name = "interact-right"
	if face.length() > 0.05:
		actor.rotation.y = lerp_angle(actor.rotation.y, atan2(face.x, face.z), minf(1.0, dt * 9.0))
	play(actor, anim_name, speed_scale)
	_update_props(actor, r)


# --- tools, carried loads and world changes from outdoor jobs -------------------------------------------------------------

## Show the right tool in the hand and the right load in the arms for what the resident is doing.
func _update_props(actor: Node3D, r: Dictionary) -> void:
	var job: Dictionary = r.get("job", {})
	var tool_kind := ""
	var carry := str(r.get("carry", ""))
	var weapon := Weapons.weapon_of(r)
	if not job.is_empty() and str(job.kind) == "guard":
		tool_kind = weapon if weapon != "" else "sword"
	elif not job.is_empty():
		var phase := str(job.phase)
		if phase in ["approach", "work", "retreat"] and carry == "":
			tool_kind = {"chop": "axe", "mine": "pickaxe", "water": "bucket"}[str(job.kind)]
	if tool_kind == "" and weapon != "":
		tool_kind = weapon
	if str(actor.get_meta("tool", "")) != tool_kind:
		actor.set_meta("tool", tool_kind)
		var old: Node = actor.get_meta("tool_node", null)
		if old != null and is_instance_valid(old):
			old.queue_free()
		actor.set_meta("tool_node", null)
		if tool_kind != "":
			var model: Node3D = actor.get_child(0)
			var arm: Node3D = model.find_child("arm-right", true, false)
			if arm != null:
				var node := _make_tool(tool_kind)
				arm.add_child(node)
				actor.set_meta("tool_node", node)
	_update_shield(actor, Weapons.has_shield(r))
	if str(actor.get_meta("load", "")) != carry:
		actor.set_meta("load", carry)
		var old_load: Node = actor.get_meta("load_node", null)
		if old_load != null and is_instance_valid(old_load):
			old_load.queue_free()
		actor.set_meta("load_node", null)
		if carry != "":
			var load_node := _make_load(carry)
			actor.add_child(load_node)
			actor.set_meta("load_node", load_node)


func _prim(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material(color)
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


func _cyl(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	return c


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Hand tools, in arm-local units (the hand sits near the bottom of the arm, like the chief's staff).
func _make_tool(kind: String) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(-0.2, -0.75, 0.3)
	holder.rotation = Vector3(deg_to_rad(-70.0), 0.0, 0.0)
	var wood_color := Color("8a5a30")
	match kind:
		"axe":
			_prim(holder, _cyl(0.05, 1.5), wood_color, Vector3(0, 0.55, 0))
			_prim(holder, _box_mesh(Vector3(0.14, 0.38, 0.62)), Color("aeb6bd"), Vector3(0, 1.15, 0.24))
		"pickaxe":
			_prim(holder, _cyl(0.05, 1.5), wood_color, Vector3(0, 0.55, 0))
			_prim(holder, _box_mesh(Vector3(0.12, 0.14, 1.25)), Color("9aa3aa"), Vector3(0, 1.25, 0))
		"sword":
			holder.rotation = Vector3(deg_to_rad(-80.0), 0.0, 0.0)
			_prim(holder, _cyl(0.04, 0.4), wood_color, Vector3(0, 0.2, 0))
			_prim(holder, _box_mesh(Vector3(0.5, 0.08, 0.1)), Color("c9a64a"), Vector3(0, 0.42, 0))
			_prim(holder, _box_mesh(Vector3(0.09, 1.1, 0.04)), Color("d5dade"), Vector3(0, 1.0, 0))
		"club":
			_prim(holder, _cyl(0.07, 1.0), wood_color, Vector3(0, 0.45, 0))
			_prim(holder, _cyl(0.15, 0.55), wood_color.darkened(0.15), Vector3(0, 1.1, 0))
		"spear":
			_prim(holder, _cyl(0.04, 2.6), wood_color, Vector3(0, 0.75, 0))
			_prim(holder, _box_mesh(Vector3(0.06, 0.55, 0.26)), Color("cfd5d9"), Vector3(0, 2.2, 0))
		"bow":
			holder.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)
			_prim(holder, _cyl(0.035, 1.5), wood_color, Vector3(0, 0.55, 0.0), Vector3(deg_to_rad(8.0), 0, 0))
			_prim(holder, _cyl(0.012, 1.45), Color("e8e0c8"), Vector3(0, 0.55, -0.2))
		"shield":
			holder.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
			holder.position = Vector3(0.28, -0.55, 0.15)
			_prim(holder, _cyl(0.46, 0.08), Color("a4272b"), Vector3.ZERO, Vector3(deg_to_rad(90.0), 0, 0))
			_prim(holder, _cyl(0.1, 0.12), Color("d6b45a"), Vector3(0.0, 0.0, 0.0), Vector3(deg_to_rad(90.0), 0, 0))
		"bucket":
			holder.rotation = Vector3.ZERO
			holder.position = Vector3(-0.1, -0.95, 0.35)
			_prim(holder, _cyl(0.24, 0.36), Color("7a5a3a"), Vector3.ZERO)
			_prim(holder, _cyl(0.2, 0.02), Color("5fb4e8"), Vector3(0, 0.17, 0))
	return holder


## A shield strapped to the left arm.
func _update_shield(actor: Node3D, want: bool) -> void:
	var has: bool = actor.get_meta("shield", false)
	if has == want:
		return
	actor.set_meta("shield", want)
	var old: Node = actor.get_meta("shield_node", null)
	if old != null and is_instance_valid(old):
		old.queue_free()
	actor.set_meta("shield_node", null)
	if want:
		var arm: Node3D = (actor.get_child(0) as Node3D).find_child("arm-left", true, false)
		if arm != null:
			var node := _make_tool("shield")
			arm.add_child(node)
			actor.set_meta("shield_node", node)


## The chief holds whatever weapon the armory gave them instead of the staff.
func _sync_chief_weapon() -> void:
	if _chief_weapon_shown == sim.chief_weapon:
		return
	_chief_weapon_shown = sim.chief_weapon
	var arm: Node3D = (chief.get_child(0) as Node3D).find_child("arm-right", true, false)
	if arm == null:
		return
	var staff: Node3D = arm.get_node_or_null("staff")
	if staff != null:
		staff.visible = sim.chief_weapon == ""
	var old: Node = chief.get_meta("weapon_node", null)
	if old != null and is_instance_valid(old):
		old.queue_free()
	chief.set_meta("weapon_node", null)
	if sim.chief_weapon != "":
		var node := _make_tool(sim.chief_weapon)
		arm.add_child(node)
		chief.set_meta("weapon_node", node)


## The rival town is built when the chief gets within sight of it and put away again when far off.
func _sync_rival() -> void:
	var spot := CityMap.tile_pos_to_world(Rival.position(sim))
	var near := Vector2(chief.position.x - spot.x, chief.position.z - spot.z).length()
	if _rival_node == null and near < 650.0:
		_rival_node = RivalArt.build_town(self)
		_rival_node.position = spot
		add_child(_rival_node)
	elif _rival_node != null and near > 1000.0:
		_rival_node.queue_free()
		_rival_node = null
	var centre := Survival.village_centre(sim)
	var post := CityMap.tile_pos_to_world(Vector2(centre.x + Survival.village_radius(sim) + 2.5, centre.y + 3.0))
	if _sign_node == null:
		_sign_node = RivalArt.build_signpost(self, Rival.gap_units(sim))
		add_child(_sign_node)
	_sign_node.position = post
	_sign_node.visible = Rival.known(sim)


## Loads carried in the arms while walking back to the village (world units, in front of the chest).
func _make_load(kind: String) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(0.0, 0.58, 0.34)
	match kind:
		"log":
			_prim(holder, _cyl(0.1, 0.78), Color("8a5a30"), Vector3.ZERO, Vector3(0, 0, deg_to_rad(90.0)))
			_prim(holder, _cyl(0.085, 0.7), Color("9a6a3c"), Vector3(0, 0.17, 0.02), Vector3(0, 0, deg_to_rad(90.0)))
		"stone":
			var rock := SphereMesh.new()
			rock.radius = 0.17
			rock.height = 0.3
			_prim(holder, rock, Color("8b9096"), Vector3(-0.1, 0, 0))
			_prim(holder, rock, Color("a0a5aa"), Vector3(0.12, 0.05, 0.02))
		"bucket":
			_prim(holder, _cyl(0.17, 0.26), Color("7a5a3a"), Vector3.ZERO)
			_prim(holder, _cyl(0.145, 0.02), Color("5fb4e8"), Vector3(0, 0.125, 0))
	return holder


# --- monsters ------------------------------------------------------------------------------------------------------------

func _sync_mobs(dt: float) -> void:
	var alive := {}
	for m in sim.mobs:
		var id := int(m.id)
		alive[id] = true
		var node: Node3D = _mob_nodes.get(id, null)
		if node == null or not is_instance_valid(node):
			node = _build_mob(m)
			_mob_nodes[id] = node
			add_child(node)
			node.position = CityMap.tile_pos_to_world(Vector2(m.pos[0], m.pos[1]))
		var target := CityMap.tile_pos_to_world(Vector2(m.pos[0], m.pos[1]))
		var moved := node.position.distance_to(target) > 0.05
		node.position = node.position.lerp(target, minf(1.0, dt * 8.0))
		node.rotation.y = lerp_angle(node.rotation.y, PI / 2.0 - float(m.get("facing", 0.0)), minf(1.0, dt * 8.0))
		_animate_mob(node, m, moved, dt)
	for id in _mob_nodes.keys():
		if not alive.has(id):
			var gone: Node3D = _mob_nodes[id]
			_mob_nodes.erase(id)
			if is_instance_valid(gone):
				var tw := create_tween()
				tw.tween_property(gone, "scale", Vector3.ONE * 0.02, 0.35)
				tw.tween_callback(gone.queue_free)


func mob_anchor(id: int) -> Vector3:
	var node: Node3D = _mob_nodes.get(id, null)
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	return node.position + Vector3(0, float(node.get_meta("height", 1.6)), 0)


## World position of the nearest monster within striking distance of this actor, or ZERO.
func _foe_near(actor: Node3D) -> Vector3:
	for m in sim.mobs:
		var node: Node3D = _mob_nodes.get(int(m.id), null)
		if node != null and is_instance_valid(node) and node.position.distance_to(actor.position) < 4.6:
			return node.position
	return Vector3.ZERO


func _build_mob(m: Dictionary) -> Node3D:
	var holder: Node3D
	match str(m.kind):
		"zombie":
			var look: String = Catalog.LOOKS[int(m.id) % Catalog.LOOKS.size()]
			holder = build_character(look, 0.6)
			if _zombie_overlay == null:
				_zombie_overlay = StandardMaterial3D.new()
				_zombie_overlay.albedo_color = Color(0.25, 0.65, 0.3, 0.6)
				_zombie_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for mesh in holder.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).material_overlay = _zombie_overlay
			holder.set_meta("height", 2.3)
		"raider", "raider_archer", "raider_captain", "soldier", "soldier_archer", "soldier_knight":
			var rlook: String = Catalog.LOOKS[int(m.id) % Catalog.LOOKS.size()]
			holder = build_character(rlook, 0.8 if str(m.kind) in ["raider_captain", "soldier_knight"] else 0.62)
			var soldier := Survival.is_garrison(str(m.kind))
			if _soldier_overlay == null:
				_soldier_overlay = StandardMaterial3D.new()
				_soldier_overlay.albedo_color = Color(0.32, 0.38, 0.55, 0.5)
				_soldier_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if _raider_overlay == null:
				_raider_overlay = StandardMaterial3D.new()
				_raider_overlay.albedo_color = Color(0.75, 0.12, 0.12, 0.38)
				_raider_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for mesh2 in holder.find_children("*", "MeshInstance3D", true, false):
				(mesh2 as MeshInstance3D).material_overlay = _soldier_overlay if soldier else _raider_overlay
			var rarm: Node3D = (holder.get_child(0) as Node3D).find_child("arm-right", true, false)
			if rarm != null:
				rarm.add_child(_make_tool("bow" if str(m.kind) in ["raider_archer", "soldier_archer"] else ("sword" if int(m.id) % 3 != 0 else "spear")))
			var larm: Node3D = (holder.get_child(0) as Node3D).find_child("arm-left", true, false)
			if larm != null and str(m.kind) not in ["raider_archer", "soldier_archer"]:
				larm.add_child(_make_tool("shield"))
			holder.set_meta("height", 3.0 if str(m.kind) in ["raider_captain", "soldier_knight"] else 2.4)
		"slime":
			holder = Node3D.new()
			var body := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.55
			sphere.height = 0.95
			body.mesh = sphere
			var jelly := material(Color(0.35, 0.85, 0.4))
			jelly.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			jelly.albedo_color = Color(0.35, 0.85, 0.4, 0.82)
			body.material_override = jelly
			body.position = Vector3(0, 0.48, 0)
			body.name = "body"
			holder.add_child(body)
			for side in [-1.0, 1.0]:
				_prim(body, _box_mesh(Vector3(0.12, 0.16, 0.06)), Color("1c2a1e"), Vector3(side * 0.2, 0.1, 0.5))
			holder.set_meta("height", 1.5)
		_:
			holder = Node3D.new()
			var fur := Color("5d6068")
			var body2 := _prim(holder, _box_mesh(Vector3(0.55, 0.42, 1.1)), fur, Vector3(0, 0.62, 0))
			body2.name = "body"
			_prim(holder, _box_mesh(Vector3(0.42, 0.38, 0.46)), fur.lightened(0.08), Vector3(0, 0.82, 0.7))
			_prim(holder, _box_mesh(Vector3(0.24, 0.2, 0.3)), fur.darkened(0.15), Vector3(0, 0.74, 1.02))
			for side in [-1.0, 1.0]:
				_prim(holder, _box_mesh(Vector3(0.1, 0.18, 0.08)), fur, Vector3(side * 0.14, 1.06, 0.62))
				_prim(holder, _box_mesh(Vector3(0.08, 0.06, 0.05)), Color("e03a2a"), Vector3(side * 0.12, 0.88, 0.94))
			_prim(holder, _box_mesh(Vector3(0.1, 0.1, 0.55)), fur.darkened(0.1), Vector3(0, 0.74, -0.78), Vector3(deg_to_rad(-25.0), 0, 0))
			for k in range(4):
				var leg := Node3D.new()
				leg.name = "leg%d" % k
				leg.position = Vector3(-0.2 if k % 2 == 0 else 0.2, 0.45, 0.38 if k < 2 else -0.38)
				_prim(leg, _box_mesh(Vector3(0.12, 0.45, 0.12)), fur.darkened(0.12), Vector3(0, -0.22, 0))
				holder.add_child(leg)
			holder.set_meta("height", 1.5)
	return holder


func _animate_mob(node: Node3D, m: Dictionary, moved: bool, _dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + float(int(m.id)) * 0.9
	match str(m.kind):
		"zombie", "raider", "raider_archer", "raider_captain", "soldier", "soldier_archer", "soldier_knight":
			var foe_at := chief.position if int(m.target) == -2 else _resident_world(int(m.target))
			var reach_units := (Survival.KINDS[str(m.kind)].get("range", 0.0) as float) * CityMap.TILE
			var biting := ((int(m.target) >= 0 or int(m.target) == -2) and node.position.distance_to(foe_at) < maxf(4.4, reach_units)) or int(m.get("siege", -1)) >= 0
			var shooting := str(m.kind) in ["raider_archer", "soldier_archer"] and biting
			play(node, "holding-right-shoot" if shooting else ("attack-melee-right" if biting else ("walk" if moved else "idle")), 0.7)
			_set_alert(node, bool(m.get("winding", false)))
		"slime":
			var body: Node3D = node.get_node_or_null("body")
			if body != null:
				var squash := 1.0 + 0.16 * sin(t * 6.0)
				body.scale = Vector3(1.0 / squash, squash, 1.0 / squash)
				node.position.y = absf(sin(t * 3.0)) * 0.22 if moved else 0.0
		_:
			var swing := 0.7 if moved else 0.0
			for k in range(4):
				var leg: Node3D = node.get_node_or_null("leg%d" % k)
				if leg != null:
					leg.rotation.x = sin(t * 13.0 + float(k % 2) * PI) * swing


func _resident_world(index: int) -> Vector3:
	if index >= 0 and index < actors.size():
		return actors[index].position
	return Vector3(1.0e6, 0, 1.0e6)


func _combat_event(e: Dictionary) -> void:
	match str(e.type):
		"wall_breach":
			var wall := sim.building_by_id(int(e.id))
			if not wall.is_empty():
				var we := Walls.edge(wall)
				_burst(CityMap.tile_pos_to_world(Walls.mid(we.d, we.side)) + Vector3(0, 1.2, 0), Color("b9b2a3"), 30)
		"arrow":
			var from := CityMap.tile_pos_to_world(Vector2(e.from[0], e.from[1])) + Vector3(0, 4.5, 0)
			var to := CityMap.tile_pos_to_world(Vector2(e.to[0], e.to[1])) + Vector3(0, 1.0, 0)
			var shaft := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.04
			mesh.bottom_radius = 0.04
			mesh.height = from.distance_to(to)
			shaft.mesh = mesh
			shaft.material_override = material(Color("f2e3b0"))
			add_child(shaft)
			shaft.position = (from + to) * 0.5
			shaft.look_at_from_position(shaft.position, to, Vector3.UP)
			shaft.rotate_object_local(Vector3.RIGHT, PI / 2.0)
			var tw := create_tween()
			tw.tween_interval(0.12)
			tw.tween_callback(shaft.queue_free)
		"hit":
			var who := int(e.who)
			if who >= 0 and who < actors.size():
				var wp := actors[who].position
				_bleed(wp + Vector3(0, 1.0, 0), Color("b3201f"), 12, 0.3)
		"strike":
			var at := CityMap.tile_pos_to_world(Vector2(e.pos[0], e.pos[1]))
			var amount := float(e.amount)
			var crit := bool(e.crit)
			var kind_color := _blood_color(str(e.kind))
			if amount > 0.5 and int(e.who) < 0:
				_floating_text(at + Vector3(0, 2.4, 0), "%d%s" % [int(round(amount)), "!" if crit else ""], Color("ffd34a") if crit else Color("ffffff"), 84 if crit else 56)
			_bleed(at + Vector3(0, 1.1, 0), kind_color, 10 + int(amount * 0.35) + (12 if bool(e.heavy) else 0) + (10 if crit else 0), 0.25 + amount * 0.01)
			var node: Node3D = _mob_nodes.get(int(e.mob), null)
			if node != null and is_instance_valid(node):
				var pop := create_tween()
				node.scale = Vector3.ONE * 1.18
				pop.tween_property(node, "scale", Vector3.ONE, 0.16)
		"chief_hit":
			var cpos := chief.position
			if bool(e.dodged):
				_floating_text(cpos + Vector3(0, 3.0, 0), "Dodge!", Color("7fe0ff"), 64)
			elif bool(e.blocked):
				_floating_text(cpos + Vector3(0, 3.0, 0), "Blocked", Color("c9d2d8"), 56)
				_burst(cpos + Vector3(0, 1.4, 0), Color("ffe9a8"), 10)
			else:
				_floating_text(cpos + Vector3(0, 3.0, 0), ("Guard broken! " if bool(e.get("broken", false)) else "") + "-%d" % int(round(float(e.amount))), Color("ff5a4a"), 72)
				_bleed(cpos + Vector3(0, 1.2, 0), Color("b3201f"), 16 + int(float(e.amount)), 0.4)
		"chief_drip":
			_blood_decal(chief.position + Vector3(0, 0, 0), Color("b3201f"), 0.16)
		"swing":
			_slash_fx(bool(e.heavy), int(e.combo), str(e.weapon))
		"mob_gone":
			var pos := CityMap.tile_pos_to_world(Vector2(e.pos[0], e.pos[1])) + Vector3(0, 0.8, 0)
			if bool(e.killed):
				var gore := _blood_color(str(e.kind))
				_bleed(pos, gore, 26, 1.0)
				_blood_decal(pos, gore, 1.1)
				_blood_decal(pos + Vector3(0.7, 0, -0.5), gore, 0.55)
				_blood_decal(pos + Vector3(-0.6, 0, 0.6), gore, 0.4)
				_spawn_corpse(str(e.kind), pos - Vector3(0, 0.8, 0))
			else:
				_burst(pos, Color("8c8f94"), 14)
		"downed":
			var who2 := int(e.who)
			if who2 >= 0 and who2 < actors.size():
				_burst(actors[who2].position + Vector3(0, 1.2, 0), Color("f0c93a"), 12)


## Someone has left the village for good.
func remove_actor(index: int) -> void:
	if index < 0 or index >= actors.size():
		return
	var gone: Node3D = actors[index]
	actors.remove_at(index)
	if is_instance_valid(gone):
		var tw := create_tween()
		tw.tween_property(gone, "scale", Vector3.ONE * 0.02, 0.6)
		tw.tween_callback(gone.queue_free)


## The merchant's camp just beyond the village's northern edge while a caravan is in town.
func _sync_caravan() -> void:
	var here := Caravans.present(sim)
	if here and (_caravan_node == null or not is_instance_valid(_caravan_node) or _caravan_name != str(sim.caravan.name)):
		if _caravan_node != null and is_instance_valid(_caravan_node):
			_caravan_node.queue_free()
		_caravan_name = str(sim.caravan.name)
		_caravan_node = _make_caravan()
		add_child(_caravan_node)
	elif not here and _caravan_node != null:
		if is_instance_valid(_caravan_node):
			var tw := create_tween()
			tw.tween_property(_caravan_node, "scale", Vector3.ONE * 0.01, 0.8)
			tw.tween_callback(_caravan_node.queue_free)
		_caravan_node = null
		_caravan_name = ""


func _make_caravan() -> Node3D:
	var root := Node3D.new()
	var centre := Survival.village_centre(sim)
	var radius := Survival.village_radius(sim)
	root.position = CityMap.tile_pos_to_world(centre + Vector2(3.0, -(radius + 3.5)))
	var wood := Color("8a5a30")
	# The wagon: bed, canopy on hoops, wheels.
	_prim(root, _box_mesh(Vector3(3.0, 0.7, 1.6)), wood, Vector3(0, 1.0, 0))
	for k in range(4):
		_prim(root, _cyl(0.05, 1.3), wood.darkened(0.2), Vector3(-1.2 + 0.8 * float(k), 1.9, 0.0))
	_prim(root, _box_mesh(Vector3(3.2, 0.12, 1.9)), Color("efe3c2"), Vector3(0, 2.6, 0), Vector3(0, 0, deg_to_rad(2.0)))
	_prim(root, _box_mesh(Vector3(3.2, 1.2, 0.1)), Color("efe3c2"), Vector3(0, 1.95, -0.85))
	for wx in [-1.0, 1.0]:
		for wz in [-1.0, 1.0]:
			_prim(root, _cyl(0.5, 0.14), Color("5a3b20"), Vector3(wx * 1.0, 0.5, wz * 0.9), Vector3(0, 0, deg_to_rad(90.0)))
	# Goods piled behind and beside.
	for c in range(3):
		_prim(root, _box_mesh(Vector3(0.6, 0.6, 0.6)), Color("c9a46a"), Vector3(2.4 + 0.1 * float(c), 0.3 + 0.62 * float(c % 2), -0.6 + 0.7 * float(c)))
	for b in range(2):
		_prim(root, _cyl(0.32, 0.8), Color("7a4f2a"), Vector3(-2.3, 0.4, -0.5 + 0.9 * float(b)))
	# The horse.
	var coat := Color("7a4e2e")
	var horse := Node3D.new()
	horse.position = Vector3(-4.2, 0, 0.2)
	root.add_child(horse)
	_prim(horse, _box_mesh(Vector3(1.6, 0.8, 0.7)), coat, Vector3(0, 1.3, 0))
	_prim(horse, _box_mesh(Vector3(0.5, 0.9, 0.45)), coat, Vector3(-0.95, 1.8, 0), Vector3(0, 0, deg_to_rad(-25.0)))
	_prim(horse, _box_mesh(Vector3(0.7, 0.4, 0.4)), coat.lightened(0.05), Vector3(-1.35, 2.2, 0))
	_prim(horse, _box_mesh(Vector3(0.12, 0.7, 0.12)), Color("2c1c10"), Vector3(0.9, 1.1, 0), Vector3(0, 0, deg_to_rad(25.0)))
	for lx in [-0.6, 0.6]:
		for lz in [-0.22, 0.22]:
			_prim(horse, _box_mesh(Vector3(0.16, 0.95, 0.16)), coat.darkened(0.15), Vector3(lx, 0.5, lz))
	# The merchant standing by the wagon.
	var merchant := build_character("character-q", 0.5)
	merchant.position = Vector3(1.0, 0, 1.7)
	merchant.rotation.y = PI * 0.8
	root.add_child(merchant)
	play(merchant, "emote-yes", 0.6)
	var lantern := OmniLight3D.new()
	lantern.position = Vector3(0, 2.4, 1.0)
	lantern.omni_range = 9.0
	lantern.light_energy = 1.0
	lantern.light_color = Color("ffcf8a")
	root.add_child(lantern)
	return root


## Decorations at the plaza while a festival is on, and fireworks after dark.
func _sync_festival(dt: float) -> void:
	var active := Festivals.is_active(sim)
	if active and (_festival_node == null or not is_instance_valid(_festival_node) or _festival_name != str(sim.festival.name)):
		if _festival_node != null and is_instance_valid(_festival_node):
			_festival_node.queue_free()
		_festival_name = str(sim.festival.name)
		_festival_node = _make_festival(_festival_name)
		add_child(_festival_node)
	elif not active and _festival_node != null:
		if is_instance_valid(_festival_node):
			var tw := create_tween()
			tw.tween_property(_festival_node, "scale", Vector3.ONE * 0.01, 0.8)
			tw.tween_callback(_festival_node.queue_free)
		_festival_node = null
		_festival_name = ""
	if active:
		var hour := fmod(sim.minutes / 60.0, 24.0)
		if hour >= 19.0 or hour < 5.0:
			_firework_timer -= dt
			if _firework_timer <= 0.0:
				_firework_timer = randf_range(0.9, 2.2)
				_firework()


func _plaza_world() -> Vector3:
	var spot := Festivals.plaza_spot(sim)
	return CityMap.tile_pos_to_world(spot)


func _firework() -> void:
	var centre := _plaza_world() + Vector3(randf_range(-8.0, 8.0), randf_range(9.0, 14.0), randf_range(-8.0, 8.0))
	var palette := [Color("ff5a4d"), Color("ffd84a"), Color("5ad1ff"), Color("9cff6a"), Color("ff7ad9"), Color("ffffff")]
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 70
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -3.2, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	var color: Color = palette[randi() % palette.size()]
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	p.position = centre
	add_child(p)
	get_tree().create_timer(2.4).timeout.connect(p.queue_free)


func _make_festival(festival_name: String) -> Node3D:
	var root := Node3D.new()
	root.position = _plaza_world()
	var flag_colors := [Color("e8553f"), Color("f0b64a"), Color("4fa3d9"), Color("7ccf8e"), Color("e98aa8")]
	# Bunting: four poles round the square with strings of little flags between them.
	var corners := [Vector3(-6.2, 0, -6.2), Vector3(6.2, 0, -6.2), Vector3(6.2, 0, 6.2), Vector3(-6.2, 0, 6.2)]
	for c in corners:
		_prim(root, _cyl(0.1, 3.6), Color("7a5230"), c + Vector3(0, 1.8, 0))
	for k in range(4):
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		for f in range(11):
			var t := float(f) / 10.0
			var p := a.lerp(b, t) + Vector3(0, 3.3 - 0.45 * sin(t * PI), 0)
			var flag := _prim(root, _box_mesh(Vector3(0.34, 0.34, 0.04)), flag_colors[(f + k) % flag_colors.size()], p - Vector3(0, 0.2, 0))
			flag.rotation.y = atan2(b.x - a.x, b.z - a.z) + PI / 2.0
	# Stalls with striped awnings.
	for s in range(3):
		var angle := PI * (0.25 + 0.5 * float(s))
		var base := Vector3(cos(angle) * 5.0 + 0.0, 0, -sin(angle) * 5.0 - 0.3)
		_prim(root, _box_mesh(Vector3(1.9, 0.9, 1.1)), Color("9a6a3c"), base + Vector3(0, 0.45, 0))
		var awning := _prim(root, _box_mesh(Vector3(2.2, 0.12, 1.5)), flag_colors[s % flag_colors.size()], base + Vector3(0, 1.9, 0.1), Vector3(deg_to_rad(10.0), 0, 0))
		_prim(root, _cyl(0.05, 1.9), Color("7a5230"), base + Vector3(-0.95, 0.95, 0.6))
		_prim(root, _cyl(0.05, 1.9), Color("7a5230"), base + Vector3(0.95, 0.95, 0.6))
		var goods := Color("d9a441") if festival_name == "Harvest Fair" else (Color("e98aa8") if festival_name == "Bloom Fair" else Color("c85a4a"))
		for g in range(4):
			var item := SphereMesh.new()
			item.radius = 0.2
			item.height = 0.4
			_prim(root, item, goods if g % 2 == 0 else goods.lightened(0.15), base + Vector3(-0.6 + 0.4 * float(g), 1.05, 0.0))
	# Something for each festival at the centre.
	match festival_name:
		"Midsummer Night", "Winter Feast", "Village Feast":
			for l in range(3):
				var ang := TAU * float(l) / 3.0
				_prim(root, _cyl(0.14, 1.1), Color("5a3b20"), Vector3(cos(ang) * 0.35, 0.25, sin(ang) * 0.35), Vector3(deg_to_rad(65.0), ang, 0))
			var flame := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.45
			cone.height = 1.2
			flame.mesh = cone
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color("ff9a2e")
			fm.emission_enabled = true
			fm.emission = Color("ff7a1a")
			fm.emission_energy_multiplier = 2.4
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flame.material_override = fm
			flame.position = Vector3(0, 0.8, 0)
			root.add_child(flame)
			var glow := OmniLight3D.new()
			glow.position = Vector3(0, 1.4, 0)
			glow.omni_range = 14.0
			glow.light_energy = 1.6
			glow.light_color = Color("ffb36a")
			root.add_child(glow)
		"Harvest Fair":
			for h in range(9):
				var pump := SphereMesh.new()
				pump.radius = 0.38
				pump.height = 0.62
				_prim(root, pump, Color("e8892a"), Vector3(cos(float(h) * 0.7) * (0.6 + 0.12 * float(h)), 0.32, sin(float(h) * 0.7) * (0.6 + 0.12 * float(h))))
			for hb in range(3):
				_prim(root, _box_mesh(Vector3(1.0, 0.6, 0.7)), Color("d9b95b"), Vector3(-2.6 + 2.6 * float(hb), 0.3, 2.8))
		"Bloom Fair":
			for side in [-1.0, 1.0]:
				_prim(root, _cyl(0.1, 3.0), Color("7a5230"), Vector3(side * 1.6, 1.5, 0))
			_prim(root, _box_mesh(Vector3(3.4, 0.14, 0.14)), Color("7a5230"), Vector3(0, 3.0, 0))
			for fl in range(14):
				var blossom := SphereMesh.new()
				blossom.radius = 0.16
				blossom.height = 0.3
				_prim(root, blossom, flag_colors[fl % flag_colors.size()], Vector3(-1.6 + 0.25 * float(fl), 2.95 + 0.1 * sin(float(fl)), 0.1))
	return root


func _stump(parent: Node3D, pos: Vector3) -> void:
	_prim(parent, _cyl(0.22, 0.24), Color("7a5230"), pos + Vector3(0, 0.12, 0))
	_prim(parent, _cyl(0.19, 0.02), Color("c9a36f"), pos + Vector3(0, 0.25, 0))


func _burst(pos: Vector3, color: Color, amount: int = 14, piece: float = 0.12, speed: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0 * speed
	p.initial_velocity_max = 4.0 * speed
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(piece, piece, piece)
	p.mesh = mesh
	p.material_override = material(color)
	p.position = pos
	add_child(p)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# --- blood, numbers, corpses -----------------------------------------------------------------------------------------------

func _blood_on() -> bool:
	return bool(GameSettings.value("blood"))


func _blood_color(kind: String) -> Color:
	if kind == "slime":
		return Color("48c957")
	if kind == "zombie":
		return Color("6e1d1b")
	return Color("b3201f")


## Spray from a wound: a burst of droplets and a splash on the ground. Without blood it is a spark of dust.
func _bleed(pos: Vector3, color: Color, amount: int, size: float) -> void:
	if not _blood_on():
		_burst(pos, Color("f5efc4"), 6)
		return
	_burst(pos, color, amount + 8, 0.2, 1.5)
	_blood_decal(Vector3(pos.x, 0.0, pos.z), color, clampf(size, 0.15, 1.3))
	# Droplets land around the wound a moment later.
	var drops := clampi(amount / 5, 2, 9)
	for k in range(drops):
		var offset := Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU) * randf_range(0.5, 1.2 + size * 1.5)
		var landing := Vector3(pos.x + offset.x, 0.0, pos.z + offset.z)
		var radius := randf_range(0.08, 0.2 + size * 0.2)
		get_tree().create_timer(0.12 + 0.03 * float(k)).timeout.connect(func() -> void: _blood_decal(landing, color, radius))


## A flat stain on the ground that dries and fades.
func _blood_decal(world: Vector3, color: Color, radius: float) -> void:
	if not _blood_on():
		return
	var disc := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = 0.02
	shape.radial_segments = 10
	disc.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.35
	disc.material_override = mat
	disc.position = Vector3(world.x + randf_range(-0.25, 0.25), 0.03 + 0.003 * float(_blood_decals.size() % 6), world.z + randf_range(-0.25, 0.25))
	disc.scale = Vector3(randf_range(0.7, 1.4), 1.0, randf_range(0.7, 1.4))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_blood_decals.append(disc)
	while _blood_decals.size() > 110:
		var old: Node = _blood_decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := create_tween()
	tw.tween_interval(45.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 20.0)
	tw.tween_callback(disc.queue_free)


## Rising damage numbers and call-outs.
func _floating_text(pos: Vector3, text: String, color: Color, size: int = 64) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 16
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", pos.y + 1.7, 0.95)
	tw.tween_property(label, "modulate:a", 0.0, 0.95).set_delay(0.35)
	tw.chain().tween_callback(label.queue_free)


## The defeated lie where they fell for a while.
func _spawn_corpse(kind: String, world: Vector3) -> void:
	if kind == "slime":
		return
	var body := _build_mob({"kind": kind, "id": randi() % 1000})
	add_child(body)
	body.position = world
	body.rotation.y = randf() * TAU
	if kind == "wolf":
		body.rotation.z = deg_to_rad(88.0)
		body.position.y = 0.35
	else:
		play(body, "die", 1.0)
	_corpses.append(body)
	while _corpses.size() > 14:
		var old: Node = _corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := create_tween()
	tw.tween_interval(22.0)
	tw.tween_property(body, "scale", Vector3.ONE * 0.02, 1.5)
	tw.tween_callback(body.queue_free)


## A red "!" over a monster that is about to strike the chief: time to dodge.
func _set_alert(node: Node3D, on: bool) -> void:
	var mark: Label3D = node.get_node_or_null("alert")
	if on and mark == null:
		mark = Label3D.new()
		mark.name = "alert"
		mark.text = "!"
		mark.font_size = 120
		mark.pixel_size = 0.014
		mark.modulate = Color("ff3b2f")
		mark.outline_size = 20
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.no_depth_test = true
		mark.position = Vector3(0, float(node.get_meta("height", 2.0)) + 0.8, 0)
		node.add_child(mark)
	if mark != null:
		mark.visible = on
		if on:
			mark.scale = Vector3.ONE * (1.0 + 0.2 * sin(Time.get_ticks_msec() * 0.03))


## A pale arc in front of the chief for each swing.
func _slash_fx(heavy: bool, combo: int, weapon: String) -> void:
	if weapon == "bow":
		return
	var holder := Node3D.new()
	holder.position = chief.position + Vector3(0, 1.3, 0)
	holder.rotation.y = chief.rotation.y
	add_child(holder)
	var reach := 3.4 if weapon == "spear" else (2.6 if not heavy else 3.4)
	var sweep := deg_to_rad(80.0 if weapon == "spear" else (150.0 if heavy else 110.0))
	var dir := -1.0 if combo == 2 else 1.0
	var pieces := 8
	var color := Color("ffe9b0") if not heavy else Color("ffb061")
	for k in range(pieces):
		var t := float(k) / float(pieces - 1)
		var ang := dir * (-sweep * 0.5 + sweep * t)
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.05, 0.9 if weapon != "spear" else 0.5)
		piece.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = mat
		piece.position = Vector3(sin(ang), 0.0, cos(ang)) * reach
		piece.rotation.y = ang
		holder.add_child(piece)
		var tw := create_tween()
		tw.tween_interval(0.02 * float(k))
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	get_tree().create_timer(0.5).timeout.connect(holder.queue_free)


## Presentation of sim events that change the landscape: a tree crashes down, a rock crumbles.
func world_event(e: Dictionary) -> void:
	if str(e.type) in ["hit", "strike", "mob_gone", "downed", "arrow", "wall_breach", "chief_hit", "chief_drip", "swing"]:
		_combat_event(e)
		return
	var t := Vector2i(int(e.tile[0]), int(e.tile[1]))
	var wp := CityMap.tile_to_world(t)
	var nodes: Array = _tile_nodes.get(t, [])
	_tile_nodes.erase(t)
	match str(e.type):
		"felled":
			_burst(wp + Vector3(0, 1.0, 0), Color("a9783e"))
			var away := Vector3(0, 0, 1)
			if int(e.who) >= 0 and int(e.who) < actors.size():
				away = (wp - actors[int(e.who)].position).normalized()
			for n in nodes:
				if is_instance_valid(n):
					var node := n as Node3D
					var tw := create_tween()
					tw.tween_property(node, "rotation:x", node.rotation.x + away.z * 1.45, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					tw.parallel().tween_property(node, "rotation:z", node.rotation.z - away.x * 1.45, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					tw.tween_property(node, "scale", Vector3.ONE * 0.01, 0.5)
					tw.tween_callback(node.queue_free)
			_stump_in_chunk(t, wp)
		"rock_chipped":
			_burst(wp + Vector3(0, 0.6, 0), Color("b5babf"), 10)
			for n in nodes:
				if is_instance_valid(n):
					var node2 := n as Node3D
					var tw2 := create_tween()
					tw2.tween_property(node2, "scale", node2.scale * 0.8, 0.25)
			_tile_nodes[t] = nodes
			return
		"rock_gone":
			_burst(wp + Vector3(0, 0.6, 0), Color("a3a8ad"), 22)
			for n in nodes:
				if is_instance_valid(n):
					var node3 := n as Node3D
					var tw3 := create_tween()
					tw3.tween_property(node3, "scale", Vector3.ONE * 0.01, 0.4)
					tw3.tween_callback(node3.queue_free)
	var d := CityMap.district_of(t)
	if chunks.has(d):
		chunks[d].sig = _signature(d)


func _stump_in_chunk(t: Vector2i, wp: Vector3) -> void:
	var d := CityMap.district_of(t)
	if chunks.has(d):
		_stump(chunks[d].node, wp + Vector3(0.1, 0, 0.1))


func _nearest_actor(i: int, radius: float) -> int:
	var best := -1
	var best_d := radius
	for j in range(actors.size()):
		if j == i or not actors[j].visible:
			continue
		var d := actors[i].position.distance_to(actors[j].position)
		if d < best_d:
			best_d = d
			best = j
	return best


func animate_chief(face: Vector3, moving: bool, running: bool, mode: String, dt: float) -> void:
	var anim_name := "idle"
	if moving:
		anim_name = "sprint" if running else "walk"
	elif mode != "":
		anim_name = mode
	play(chief, anim_name, 1.0)
	if face.length() > 0.05:
		chief.rotation.y = lerp_angle(chief.rotation.y, atan2(face.x, face.z), minf(1.0, dt * 10.0))


# --- terrain chunks --------------------------------------------------------------------------------------------------

func _signature(d: Vector2i) -> String:
	var s := ""
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			s += "1" if sim.map.claimed.has(d + Vector2i(dx, dy)) else "0"
	var spent := 0
	for t in sim.depleted:
		if CityMap.district_of(t) == d:
			spent += 1
	return s + _season_drawn + str(spent)


## Builds or refreshes terrain around `focus`. `immediate` builds everything now (used at start-up).
func update_world(focus: Vector3, immediate: bool = false) -> void:
	_focus = focus
	var centre := CityMap.district_of(CityMap.world_to_tile(focus))
	var wanted := {}
	for dx in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
		for dy in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			wanted[centre + Vector2i(dx, dy)] = true
	for d in chunks.keys():
		if not wanted.has(d):
			chunks[d].node.queue_free()
			chunks.erase(d)
	var budget := 9999 if immediate else 3
	var order: Array = wanted.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - centre).length_squared() < (b - centre).length_squared())
	for d in order:
		if budget <= 0:
			break
		if not chunks.has(d) or chunks[d].sig != _signature(d):
			_build_chunk(d)
			budget -= 1


func _build_chunk(d: Vector2i) -> void:
	var map := sim.map
	if chunks.has(d):
		chunks[d].node.queue_free()
	var root := Node3D.new()
	add_child(root)
	var claimed := map.claimed.has(d)
	var origin := Vector3(d.x * DISTRICT_UNITS, 0.0, d.y * DISTRICT_UNITS)
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(DISTRICT_UNITS, 0.6, DISTRICT_UNITS)
	slab.mesh = slab_mesh
	slab.material_override = _ground_claimed if claimed else _ground_wild
	slab.position = origin + Vector3(6.0, -0.3, 6.0)
	root.add_child(slab)
	var autumn := _season_drawn == "Autumn"
	for lx in range(CityMap.DISTRICT):
		for ly in range(CityMap.DISTRICT):
			var t: Vector2i = d * CityMap.DISTRICT + Vector2i(lx, ly)
			var wp := CityMap.tile_to_world(t)
			if map.is_water(t):
				var water := box(root, wp + Vector3(0, 0.02, 0), Vector3(4.0, 0.1, 4.0), Color("4d9fd0"))
				water.material_override = _water_material
				continue
			if map.is_road(t):
				_place_road(root, t, wp)
				continue
			if claimed:
				_decorate_claimed(root, t, wp, autumn)
			else:
				_decorate_wild(root, t, wp, autumn)
	chunks[d] = {"node": root, "sig": _signature(d)}


func _tree_name(h: int, autumn: bool) -> String:
	if h % 7 == 0:
		return PINES[(h / 7) % PINES.size()]
	var name_: String = TREES[h % TREES.size()]
	if autumn and name_ in FALL_OK:
		name_ += "_fall"
	return name_


func _decorate_wild(root: Node3D, t: Vector2i, wp: Vector3, autumn: bool) -> void:
	var map := sim.map
	var h := map.tile_hash(t, 11)
	var jitter := Vector3((h % 21 - 10) * 0.1, 0.0, ((h / 21) % 21 - 10) * 0.1)
	if map.has_trees(t):
		if sim.is_depleted(t):
			_stump(root, wp + jitter)
			return
		var tree := spawn("nature/" + _tree_name(h, autumn), wp + jitter, 0.8 + (h % 5) * 0.12, root)
		tree.rotation.y = (h % 360) * 0.01745
		_tile_nodes[t] = [tree]
		if h % 3 == 0:
			var second := spawn("nature/" + _tree_name(h / 3, autumn), wp - jitter * 1.3, 0.7 + (h % 4) * 0.1, root)
			second.rotation.y = (h % 97) * 0.06
			_tile_nodes[t].append(second)
	elif map.has_rock(t):
		if sim.is_depleted(t):
			return
		var rock := spawn("nature/" + ROCKS[h % ROCKS.size()], wp + jitter, 1.2 * (1.0 - 0.2 * float(sim._rock_hits.get(t, 0))), root)
		rock.rotation.y = (h % 360) * 0.01745
		_tile_nodes[t] = [rock]
	elif h % 100 < 22:
		spawn("nature/" + FLOWERS[h % FLOWERS.size()], wp + jitter, 1.4, root)
	elif h % 100 < 40:
		spawn("nature/grass_large" if h % 2 == 0 else "nature/grass", wp + jitter, 1.3, root)


func _decorate_claimed(root: Node3D, t: Vector2i, wp: Vector3, autumn: bool) -> void:
	var map := sim.map
	var h := map.tile_hash(t, 17)
	if sim.map.occupied.has(t):
		return
	if CityMap.is_green(t):
		var tree := spawn("nature/" + _tree_name(h, autumn), wp + Vector3(0.6, 0, -0.4), 1.0, root)
		tree.rotation.y = h * 0.1
		for k in range(4):
			var p := Vector3(((h >> (k * 3)) % 7 - 3) * 0.45, 0.0, ((h >> (k * 3 + 1)) % 7 - 3) * 0.45)
			spawn("nature/" + FLOWERS[(h + k) % FLOWERS.size()], wp + p + Vector3(-0.6, 0, 0.5), 1.5, root)
		return
	if h % 100 < 55:
		var p := Vector3((h % 15 - 7) * 0.2, 0.0, ((h / 15) % 15 - 7) * 0.2)
		spawn("nature/" + FLOWERS[h % FLOWERS.size()] if h % 3 != 0 else "nature/grass_large", wp + p, 1.5, root)
	if h % 100 < 12:
		spawn("nature/plant_bushSmall", wp + Vector3(1.1, 0, -1.1), 1.4, root)


func _place_road(root: Node3D, t: Vector2i, wp: Vector3) -> void:
	var open: Array[int] = []
	for i in range(4):
		if sim.map.is_road(t + DIRS[i]):
			open.append(i)
	var piece := "road-straight"
	var k := 0
	match open.size():
		0, 1:
			piece = "road-end" if open.size() == 1 else "road-straight"
			k = open[0] if open.size() == 1 else 0
		2:
			if (open[0] + 2) % 4 == open[1]:
				piece = "road-straight"
				k = open[0] % 2
			else:
				piece = "road-bend"
				for rot in range(4):
					var a := (2 + rot) % 4
					var b := (3 + rot) % 4
					if (open.has(a) and open.has(b)):
						k = rot
		3:
			piece = "road-intersection"
			var missing := 0
			for i in range(4):
				if not open.has(i):
					missing = i
			k = posmod(missing - 1, 4)
		_:
			piece = "road-crossroad"
	var road := spawn("roads/" + piece, wp + Vector3(0, 0.03, 0), 1.0, root)
	road.rotation_degrees.y = k * 90.0
	var h := sim.map.tile_hash(t, 29)
	if piece == "road-straight" and h % 4 == 0:
		var side := 1.0 if h % 2 == 0 else -1.0
		var offset := Vector3(0.0, 0.0, 1.55 * side) if k % 2 == 0 else Vector3(1.55 * side, 0.0, 0.0)
		var lamp := spawn("roads/light-square", wp + offset, 1.0, root)
		lamp.rotation.y = (PI if side > 0.0 else 0.0) + (0.0 if k % 2 == 0 else PI * 0.5)
		lamp_spots.append(wp + offset + Vector3(0, 2.4, 0))


# --- buildings --------------------------------------------------------------------------------------------------------

func _sync_buildings(dt: float) -> void:
	if building_nodes.size() > sim.buildings.size():
		var live := {}
		for b in sim.buildings:
			live[int(b.id)] = true
		for id in building_nodes.keys():
			if not live.has(id):
				var gone: Dictionary = building_nodes[id]
				building_nodes.erase(id)
				if is_instance_valid(gone.root):
					gone.root.queue_free()
	for b in sim.buildings:
		var id := int(b.id)
		if not building_nodes.has(id):
			var root := Node3D.new()
			root.position = CityMap.tile_to_world(sim.tile_of(b))
			if Walls.is_wall(b) and b.has("edge"):
				root.position = CityMap.tile_to_world(Vector2i(int(b.edge[0]) * 4, int(b.edge[1]) * 4))
			add_child(root)
			building_nodes[id] = {"root": root, "key": "", "model": null, "height": 4.0, "growth": -1.0, "first": true}
		var entry: Dictionary = building_nodes[id]
		var key := "%d:%d:%s" % [int(b.level), int(b.target), "x" if bool(b.get("breached", false)) else str(b.kind)]
		if str(b.kind) == "farm":
			key += ":%s:%s" % [Farming.crop_of(b), "pen" if not Farming.animals_of(b).is_empty() else "open"]
		if entry.key != key:
			var upgraded: bool = not entry.first and entry.key != "" and int(b.level) > 0
			_build_building(entry, b)
			entry.key = key
			if upgraded:
				_pop(entry.root)
				_dust(entry.root.position)
			entry.first = false
		_update_building(entry, b)


func _build_building(entry: Dictionary, b: Dictionary) -> void:
	var root: Node3D = entry.root
	clear_children(root)
	var kind: String = b.kind
	var show_level := int(b.level) if int(b.level) >= 1 else int(b.target)
	var model: Node3D
	var height := 3.0
	match kind:
		"farm": model = _make_farm(root, show_level, int(b.variant), b)
		"park": model = _make_park(root, show_level, int(b.variant))
		"plaza": model = _make_plaza(root, show_level)
		"wall", "gate":
			model = _make_wall(root, b, show_level)
			height = 3.0
		"watchtower":
			model = _make_tower(root, show_level)
			height = 3.0 + float(show_level) * 1.2
		_:
			var path := Catalog.model(kind, show_level, int(b.variant))
			model = spawn(path, Vector3.ZERO, 1.0, root, true)
			var d := Vector2(int(b.door[0]) - int(b.tile[0]), int(b.door[1]) - int(b.tile[1]))
			model.rotation.y = atan2(d.x, d.y)
			height = model_height(path)
	entry.model = model
	entry.height = height
	entry.base_scale = model.scale
	var working := int(b.target) > int(b.level)
	if working and not Walls.is_wall(b):
		_scaffold(root, height + 0.6)


func _update_building(entry: Dictionary, b: Dictionary) -> void:
	var model: Node3D = entry.model
	if model == null:
		return
	var working := int(b.target) > int(b.level)
	if working and int(b.level) == 0:
		# A new building rises as work progresses.
		var rise := lerpf(0.18, 1.0, float(b.progress) / 100.0)
		model.scale = Vector3(entry.base_scale.x, entry.base_scale.y * rise, entry.base_scale.z)
	elif model.scale != entry.base_scale and not working:
		model.scale = entry.base_scale
	if b.kind == "farm":
		_update_crops(model, float(b.get("growth", 0.0)))
	if b.kind == "farm":
		_sync_animals(entry, b)
	if b.kind == "gate" and b.has("edge"):
		var swing := [1.0, -1.0, -1.0, 1.0][int(b.edge[2])] as float
		var angle := 1.5 if bool(b.get("open", true)) else 0.0
		var door_l: Node3D = model.get_node_or_null("door_l")
		var door_r: Node3D = model.get_node_or_null("door_r")
		if door_l != null:
			door_l.rotation.y = lerp_angle(door_l.rotation.y, angle * swing, 0.12)
		if door_r != null:
			door_r.rotation.y = lerp_angle(door_r.rotation.y, -angle * swing, 0.12)


func _scaffold(root: Node3D, height: float) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for cx in [-1.9, 1.9]:
		for cz in [-1.9, 1.9]:
			var pole := MeshInstance3D.new()
			var pole_mesh := BoxMesh.new()
			pole_mesh.size = Vector3(0.14, height, 0.14)
			pole.mesh = pole_mesh
			pole.material_override = _wood
			pole.position = Vector3(cx, height * 0.5, cz)
			holder.add_child(pole)
	for y in [height * 0.33, height * 0.66, height]:
		for side in [-1.9, 1.9]:
			var beam_x := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(3.9, 0.1, 0.1)
			beam_x.mesh = bx
			beam_x.material_override = _wood
			beam_x.position = Vector3(0, y, side)
			holder.add_child(beam_x)
			var beam_z := MeshInstance3D.new()
			var bz := BoxMesh.new()
			bz.size = Vector3(0.1, 0.1, 3.9)
			beam_z.mesh = bz
			beam_z.material_override = _wood
			beam_z.position = Vector3(side, y, 0)
			holder.add_child(beam_z)
	spawn("roads/construction-cone", Vector3(2.4, 0, 2.4), 1.4, holder)
	spawn("roads/construction-cone", Vector3(-2.4, 0, 2.4), 1.4, holder)
	spawn("roads/construction-barrier", Vector3(0, 0, 2.5), 1.3, holder)


## Animals on a farm: kept in step with the herd, they wander about the pen.
func _sync_animals(entry: Dictionary, b: Dictionary) -> void:
	var model: Node3D = entry.model
	if model == null:
		return
	var nodes: Dictionary = entry.get("animals", {})
	var herd := Farming.animals_of(b)
	var alive := {}
	var dt := get_process_delta_time()
	var day := sim.day()
	for a in herd:
		var id := int(a.id)
		alive[id] = true
		var node: Node3D = nodes.get(id, null)
		if node == null or not is_instance_valid(node):
			node = _make_animal(str(a.kind))
			var seed_ := float(id)
			node.position = Vector3(sin(seed_ * 1.7) * 1.2, 0.12, cos(seed_ * 2.3) * 1.0)
			node.set_meta("goal", node.position)
			node.set_meta("wait", randf() * 2.0)
			model.add_child(node)
			nodes[id] = node
		var spec: Dictionary = Farming.ANIMALS[str(a.kind)]
		var growth := clampf(float(day - int(a.born)) / float(spec.adult_days), 0.0, 1.0)
		var size_ := lerpf(0.5, 1.0, growth)
		node.scale = Vector3.ONE * size_ * {"chicken": 0.9, "sheep": 1.0, "cow": 1.05, "pig": 1.0}[str(a.kind)]
		var wait := float(node.get_meta("wait")) - dt
		var goal: Vector3 = node.get_meta("goal")
		if wait <= 0.0:
			goal = Vector3(randf_range(-1.45, 1.45), 0.12, randf_range(-1.45, 1.2))
			node.set_meta("goal", goal)
			wait = randf_range(1.5, 5.0)
		node.set_meta("wait", wait)
		var to_goal := goal - node.position
		to_goal.y = 0.0
		if to_goal.length() > 0.06:
			var speed_ := 0.55 if str(a.kind) == "chicken" else 0.35
			node.position += to_goal.normalized() * minf(to_goal.length(), speed_ * dt)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(to_goal.x, to_goal.z), minf(1.0, dt * 6.0))
			node.position.y = 0.12 + absf(sin(Time.get_ticks_msec() * 0.012 + float(id))) * (0.05 if str(a.kind) == "chicken" else 0.02)
		else:
			node.position.y = 0.12
	for id in nodes.keys():
		if not alive.has(id):
			var gone: Node3D = nodes[id]
			nodes.erase(id)
			if is_instance_valid(gone):
				gone.queue_free()
	entry.animals = nodes


## Little blocky farm animals built from primitives.
func _make_animal(kind: String) -> Node3D:
	var holder := Node3D.new()
	match kind:
		"chicken":
			var white := Color("f4f1ea")
			_prim(holder, _box_mesh(Vector3(0.26, 0.22, 0.34)), white, Vector3(0, 0.22, 0))
			_prim(holder, _box_mesh(Vector3(0.16, 0.18, 0.16)), white, Vector3(0, 0.38, 0.16))
			_prim(holder, _box_mesh(Vector3(0.04, 0.08, 0.1)), Color("d8392b"), Vector3(0, 0.5, 0.16))
			_prim(holder, _box_mesh(Vector3(0.06, 0.04, 0.08)), Color("f0b64a"), Vector3(0, 0.37, 0.27))
			_prim(holder, _box_mesh(Vector3(0.18, 0.18, 0.06)), white.darkened(0.08), Vector3(0, 0.3, -0.2), Vector3(deg_to_rad(30.0), 0, 0))
			for side in [-1.0, 1.0]:
				_prim(holder, _box_mesh(Vector3(0.03, 0.1, 0.03)), Color("f0b64a"), Vector3(side * 0.06, 0.05, 0.02))
		"sheep":
			var wool := Color("efece4")
			_prim(holder, _box_mesh(Vector3(0.5, 0.42, 0.7)), wool, Vector3(0, 0.45, 0))
			_prim(holder, _box_mesh(Vector3(0.44, 0.1, 0.6)), wool.lightened(0.05), Vector3(0, 0.7, 0))
			_prim(holder, _box_mesh(Vector3(0.22, 0.24, 0.24)), Color("3b3430"), Vector3(0, 0.55, 0.42))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_prim(holder, _box_mesh(Vector3(0.08, 0.26, 0.08)), Color("3b3430"), Vector3(sx * 0.17, 0.13, sz * 0.25))
		"cow":
			var hide := Color("f1eee6")
			_prim(holder, _box_mesh(Vector3(0.62, 0.55, 1.1)), hide, Vector3(0, 0.65, 0))
			_prim(holder, _box_mesh(Vector3(0.3, 0.1, 0.4)), Color("2c2724"), Vector3(0.12, 0.94, 0.12))
			_prim(holder, _box_mesh(Vector3(0.3, 0.3, 0.1)), Color("2c2724"), Vector3(-0.2, 0.7, -0.56))
			_prim(holder, _box_mesh(Vector3(0.38, 0.38, 0.4)), hide, Vector3(0, 0.82, 0.68))
			_prim(holder, _box_mesh(Vector3(0.24, 0.16, 0.16)), Color("e8a9a0"), Vector3(0, 0.74, 0.92))
			for sx in [-1.0, 1.0]:
				_prim(holder, _box_mesh(Vector3(0.06, 0.14, 0.06)), Color("e9d9b0"), Vector3(sx * 0.17, 1.05, 0.62))
				for sz in [-1.0, 1.0]:
					_prim(holder, _box_mesh(Vector3(0.12, 0.38, 0.12)), hide.darkened(0.12), Vector3(sx * 0.2, 0.19, sz * 0.38))
		_:
			var pink := Color("eaa5a0")
			_prim(holder, _box_mesh(Vector3(0.46, 0.4, 0.75)), pink, Vector3(0, 0.38, 0))
			_prim(holder, _box_mesh(Vector3(0.34, 0.32, 0.3)), pink.lightened(0.04), Vector3(0, 0.42, 0.46))
			_prim(holder, _box_mesh(Vector3(0.2, 0.14, 0.1)), pink.darkened(0.12), Vector3(0, 0.38, 0.64))
			_prim(holder, _box_mesh(Vector3(0.1, 0.1, 0.04)), pink.darkened(0.2), Vector3(-0.1, 0.62, 0.42))
			_prim(holder, _box_mesh(Vector3(0.1, 0.1, 0.04)), pink.darkened(0.2), Vector3(0.1, 0.62, 0.42))
			_prim(holder, _box_mesh(Vector3(0.04, 0.04, 0.16)), pink.darkened(0.15), Vector3(0, 0.5, -0.44))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_prim(holder, _box_mesh(Vector3(0.1, 0.2, 0.1)), pink.darkened(0.1), Vector3(sx * 0.15, 0.1, sz * 0.26))
	return holder


func _make_farm(root: Node3D, level: int, variant: int, b: Dictionary = {}) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	box(holder, Vector3(0, 0.05, 0), Vector3(3.7, 0.12, 3.7), Color("6b4a2e"))
	var crop_model: String = str(Farming.CROPS[Farming.crop_of(b)].model)
	var crop_names: Array = [crop_model, crop_model, crop_model]
	if not Farming.animals_of(b).is_empty():
		# A rail fence around the pen, with a gap in the front.
		var rail := Color("8a5a30")
		for k in range(9):
			var u := -1.8 + float(k) * 0.45
			for side_pos in [Vector3(u, 0.4, -1.85), Vector3(u, 0.4, 1.85), Vector3(-1.85, 0.4, u), Vector3(1.85, 0.4, u)]:
				if side_pos.z > 1.0 and absf(side_pos.x) < 0.5:
					continue
				_prim(holder, _box_mesh(Vector3(0.1, 0.8, 0.1)), rail, side_pos)
		for rail_y in [0.3, 0.62]:
			_prim(holder, _box_mesh(Vector3(3.8, 0.07, 0.06)), rail.lightened(0.1), Vector3(0, rail_y, -1.85))
			_prim(holder, _box_mesh(Vector3(0.06, 0.07, 3.8)), rail.lightened(0.1), Vector3(-1.85, rail_y, 0))
			_prim(holder, _box_mesh(Vector3(0.06, 0.07, 3.8)), rail.lightened(0.1), Vector3(1.85, rail_y, 0))
			_prim(holder, _box_mesh(Vector3(1.55, 0.07, 0.06)), rail.lightened(0.1), Vector3(-1.05, rail_y, 1.85))
			_prim(holder, _box_mesh(Vector3(1.55, 0.07, 0.06)), rail.lightened(0.1), Vector3(1.05, rail_y, 1.85))
	var plants := Node3D.new()
	plants.name = "Plants"
	holder.add_child(plants)
	for row in range(3):
		for k in range(4):
			var p := spawn("nature/" + crop_names[row], Vector3(-1.35 + k * 0.9, 0.12, -1.2 + row * 1.2), 1.5, plants)
			p.rotation.y = (variant + row * 5 + k * 3) * 0.7
	if level >= 3:
		var barn := spawn("industrial/building-s", Vector3(1.3, 0, -1.3), 0.7, holder)
		barn.rotation.y = PI
	return holder


func _update_crops(model: Node3D, growth: float) -> void:
	var plants: Node3D = model.get_node_or_null("Plants")
	if plants == null:
		return
	var g := lerpf(0.25, 1.0, clampf(growth / 100.0, 0.0, 1.0))
	for p in plants.get_children():
		(p as Node3D).scale = Vector3.ONE * 1.5 * g


func _make_park(root: Node3D, level: int, variant: int) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	box(holder, Vector3(0, 0.04, 0), Vector3(3.8, 0.1, 3.8), Color("8fc86a"))
	var spots := [Vector3(-1.1, 0, -1.0), Vector3(1.2, 0, -0.8), Vector3(-0.5, 0, 1.3), Vector3(1.3, 0, 1.2), Vector3(0.0, 0, 0.1)]
	for i in range(mini(2 + level, spots.size())):
		var tree := spawn("nature/" + TREES[(variant + i) % TREES.size()], spots[i], 0.9 + (i % 3) * 0.15, holder)
		tree.rotation.y = i * 1.3
	for i in range(6 + level * 3):
		var p := Vector3(((variant * (i + 3)) % 17 - 8) * 0.2, 0.0, ((variant * (i + 5)) % 15 - 7) * 0.22)
		spawn("nature/" + FLOWERS[(variant + i) % FLOWERS.size()], p, 1.5, holder)
	if level >= 2:
		for side in [-1.0, 1.0]:
			_bench(holder, Vector3(side * 1.3, 0, 0.0), PI * 0.5 * side)
	if level >= 3:
		_fountain(holder, 1, 0.55)
	return holder


func _bench(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var b := Node3D.new()
	b.position = pos
	b.rotation.y = yaw
	parent.add_child(b)
	box(b, Vector3(0, 0.42, 0), Vector3(1.3, 0.1, 0.42), Color("b89467"))
	box(b, Vector3(0, 0.72, -0.2), Vector3(1.3, 0.4, 0.07), Color("b89467"))
	for x in [-0.5, 0.5]:
		box(b, Vector3(x, 0.2, 0), Vector3(0.08, 0.4, 0.34), Color("58605a"))


## One stretch of border wall (or gate), drawn along the edge of its district. Local frame: the district's first
## tile is the origin; the boundary lies 2 units outside it and the edge runs 16 units.
func _make_wall(root: Node3D, b: Dictionary, level: int) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	var e := Walls.edge(b)
	var side: int = e.side
	var gate := str(b.kind) == "gate"
	var broken := bool(b.get("breached", false))
	var lvl := maxi(1, level)
	var v := -2.0 if side in [0, 2] else 18.0
	var along_z := side < 2
	var spans: Array = [[-2.0, 18.0]]
	if gate:
		spans = [[-2.0, 5.6], [10.4, 18.0]]
	var h := {1: 2.6, 2: 3.0, 3: 3.7}[mini(lvl, 3)] as float
	var wood_color := Color("8a5a30")
	var stone_color := Color("a6a39a")
	for span in spans:
		var u0: float = span[0]
		var u1: float = span[1]
		if lvl == 1:
			var u := u0 + 0.4
			var k := 0
			while u < u1:
				var post_h := h * (0.25 + 0.3 * float((k * 7) % 3) / 2.0) if broken else h
				var p := Vector3(v, post_h * 0.5, u) if along_z else Vector3(u, post_h * 0.5, v)
				_prim(holder, _cyl(0.22, post_h), wood_color, p)
				if not broken:
					var tip := MeshInstance3D.new()
					var cone_mesh := CylinderMesh.new()
					cone_mesh.top_radius = 0.0
					cone_mesh.bottom_radius = 0.22
					cone_mesh.height = 0.5
					tip.mesh = cone_mesh
					tip.material_override = material(wood_color.lightened(0.1))
					tip.position = p + Vector3(0, post_h * 0.5 + 0.25, 0)
					holder.add_child(tip)
				u += 0.8
				k += 1
			if not broken:
				for ry in [0.8, 1.8]:
					var mid_u := (u0 + u1) * 0.5
					var size := Vector3(0.12, 0.14, u1 - u0) if along_z else Vector3(u1 - u0, 0.14, 0.12)
					var pos := Vector3(v + (0.22 if along_z else 0.0), ry, mid_u) if along_z else Vector3(mid_u, ry, v + 0.22)
					_prim(holder, _box_mesh(size), wood_color.darkened(0.2), pos)
		else:
			var span_len := u1 - u0
			var mid_u2 := (u0 + u1) * 0.5
			if broken:
				for k2 in range(int(span_len / 2.0)):
					var ru := u0 + 1.0 + float(k2) * 2.0
					var rh := 0.4 + 0.5 * float((k2 * 5) % 3) / 2.0
					var rp := Vector3(v, rh * 0.5, ru) if along_z else Vector3(ru, rh * 0.5, v)
					_prim(holder, _box_mesh(Vector3(0.9, rh, 1.6) if along_z else Vector3(1.6, rh, 0.9)), stone_color.darkened(0.15), rp)
			else:
				var body_size := Vector3(0.9, h, span_len) if along_z else Vector3(span_len, h, 0.9)
				var body_pos := Vector3(v, h * 0.5, mid_u2) if along_z else Vector3(mid_u2, h * 0.5, v)
				_prim(holder, _box_mesh(body_size), stone_color, body_pos)
				var m := u0 + 0.5
				while m < u1:
					var merlon_pos := Vector3(v, h + 0.25, m) if along_z else Vector3(m, h + 0.25, v)
					_prim(holder, _box_mesh(Vector3(1.0, 0.5, 0.7) if along_z else Vector3(0.7, 0.5, 1.0)), stone_color.lightened(0.08), merlon_pos)
					m += 1.6
				if lvl >= 3:
					var t := u0 + 2.0
					while t < u1:
						var torch_pos := Vector3(v + (0.5 if side == 1 else -0.5 if side == 0 else 0.0), h * 0.7, t) if along_z else Vector3(t, h * 0.7, v + (0.5 if side == 3 else -0.5))
						var flame := _prim(holder, _box_mesh(Vector3(0.18, 0.28, 0.18)), Color("ffb347"), torch_pos)
						var fm := flame.material_override as StandardMaterial3D
						fm.emission_enabled = true
						fm.emission = Color("ff9a2e")
						fm.emission_energy_multiplier = 1.4
						t += 4.0
	if gate:
		var pillar_h := h + 0.9
		for u_edge in [5.6, 10.4]:
			var pp := Vector3(v, pillar_h * 0.5, u_edge) if along_z else Vector3(u_edge, pillar_h * 0.5, v)
			if broken:
				pp.y = 0.3
				_prim(holder, _box_mesh(Vector3(1.2, 0.6, 1.2)), stone_color.darkened(0.2), pp)
			else:
				_prim(holder, _box_mesh(Vector3(1.2, pillar_h, 1.2)), stone_color.darkened(0.08), pp)
		if not broken:
			var lintel_pos := Vector3(v, pillar_h - 0.2, 8.0) if along_z else Vector3(8.0, pillar_h - 0.2, v)
			_prim(holder, _box_mesh(Vector3(1.2, 0.6, 6.0) if along_z else Vector3(6.0, 0.6, 1.2)), wood_color.darkened(0.15), lintel_pos)
			for door_name in ["door_l", "door_r"]:
				var is_left: bool = door_name == "door_l"
				var pivot := Node3D.new()
				pivot.name = door_name
				var pu := 5.6 if is_left else 10.4
				pivot.position = Vector3(v, 0.0, pu) if along_z else Vector3(pu, 0.0, v)
				holder.add_child(pivot)
				var dir_u := 1.0 if is_left else -1.0
				var leaf_pos := Vector3(0, 1.3, dir_u * 1.2) if along_z else Vector3(dir_u * 1.2, 1.3, 0)
				_prim(pivot, _box_mesh(Vector3(0.22, 2.6, 2.3) if along_z else Vector3(2.3, 2.6, 0.22)), wood_color.darkened(0.1), leaf_pos)
				var brace_pos := leaf_pos + (Vector3(0.14, 0, 0) if along_z else Vector3(0, 0, 0.14))
				_prim(pivot, _box_mesh(Vector3(0.1, 0.18, 2.2) if along_z else Vector3(2.2, 0.18, 0.1)), Color("4a3320"), brace_pos + Vector3(0, 0.5, 0))
	return holder


func _make_tower(root: Node3D, level: int) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	var stone := Color("a8a49a")
	var h := 2.6 + float(level) * 1.1
	box(holder, Vector3(0, h * 0.5, 0), Vector3(1.7, h, 1.7), stone)
	box(holder, Vector3(0, 0.15, 0), Vector3(2.0, 0.3, 2.0), stone.darkened(0.15))
	# Lookout platform with posts and a pointed roof.
	box(holder, Vector3(0, h + 0.12, 0), Vector3(2.5, 0.24, 2.5), Color("8a5a30"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(holder, Vector3(sx * 1.05, h + 0.85, sz * 1.05), Vector3(0.14, 1.3, 0.14), Color("7a5230"))
	var roof := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 1.9
	cone_mesh.height = 1.2
	cone_mesh.radial_segments = 4
	roof.mesh = cone_mesh
	roof.material_override = material(Color("b5473a"))
	roof.position = Vector3(0, h + 2.1, 0)
	roof.rotation.y = PI / 4.0
	holder.add_child(roof)
	box(holder, Vector3(0, h + 3.0, 0), Vector3(0.06, 0.9, 0.06), Color("5a3b20"))
	box(holder, Vector3(0.28, h + 3.25, 0), Vector3(0.5, 0.3, 0.04), Color("e8c36a"))
	return holder


func _make_plaza(root: Node3D, level: int) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	cone(holder, Vector3(0, 0.05, 0), 3.2, 0.1, Color("cbbf9f"), 3.2)
	_fountain(holder, level, 1.0)
	return holder


func _fountain(parent: Node3D, level: int, scale_: float) -> void:
	var f := Node3D.new()
	f.scale = Vector3.ONE * scale_
	parent.add_child(f)
	var stone := Color("8a9b94")
	cone(f, Vector3(0, 0.25, 0), 1.7, 0.5, stone, 1.7)
	cone(f, Vector3(0, 0.52, 0), 1.45, 0.06, Color("79bfca"), 1.45)
	cone(f, Vector3(0, 1.1, 0), 0.26, 1.2, Color("c6ccc2"), 0.26)
	sphere(f, Vector3(0, 1.8, 0), 0.42, Color("9dd4d4"))
	if level >= 2:
		cone(f, Vector3(0, 1.4, 0), 0.9, 0.16, stone, 0.9)
	if level >= 3:
		sphere(f, Vector3(0, 2.3, 0), 0.24, Color("e8c36a"))
		for k in range(4):
			var a := k * PI * 0.5 + PI * 0.25
			var jet := cone(f, Vector3(cos(a) * 1.0, 0.95, sin(a) * 1.0), 0.04, 1.0, Color("a8dde6"), 0.1)
			jet.rotation = Vector3(sin(a) * 0.45, 0, -cos(a) * 0.45)


# --- effects -------------------------------------------------------------------------------------------------------------

func _pop(node: Node3D) -> void:
	var target := node.scale
	node.scale = Vector3(target.x, target.y * 0.05, target.z)
	var tw := create_tween()
	tw.tween_property(node, "scale", target, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dust(at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	for i in range(14):
		var puff := sphere(self, at + Vector3(rng.randf_range(-2, 2), 0.5, rng.randf_range(-2, 2)), rng.randf_range(0.2, 0.4), Color("e8dcc4"))
		fx.append({"node": puff, "vel": Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(1.2, 2.4), rng.randf_range(-0.7, 0.7)), "life": 1.1})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f.life -= dt
		var node: Node3D = f.node
		node.position += f.vel * dt
		node.scale = Vector3.ONE * maxf(0.01, f.life / 1.1)
		if f.life <= 0:
			node.queue_free()
			fx.remove_at(i)


# --- frontier (claimable land) -----------------------------------------------------------------------------------------

func set_frontier_visible(on: bool) -> void:
	frontier_on = on
	_refresh_frontier()


func _refresh_frontier() -> void:
	for n in frontier_nodes:
		(n as Node).queue_free()
	frontier_nodes.clear()
	if not frontier_on:
		return
	for d in sim.map.frontier():
		var slab := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(DISTRICT_UNITS - 0.6, 0.12, DISTRICT_UNITS - 0.6)
		slab.mesh = mesh
		slab.material_override = _frontier_material
		slab.position = Vector3(d.x * DISTRICT_UNITS + 6.0, 0.08, d.y * DISTRICT_UNITS + 6.0)
		add_child(slab)
		frontier_nodes.append(slab)


# --- anchors and highlights for the 2D overlay --------------------------------------------------------------------------

func head_anchor(i: int) -> Vector3:
	return actors[i].position + Vector3(0, 1.95, 0)


func chief_anchor() -> Vector3:
	return chief.position + Vector3(0, 2.1, 0)


func building_anchor(b: Dictionary) -> Vector3:
	var entry: Dictionary = building_nodes.get(int(b.id), {})
	var h: float = float(entry.get("height", 3.5))
	return CityMap.tile_to_world(sim.tile_of(b)) + Vector3(0, h + 0.6, 0)


func set_hover_rect(center: Vector3, size_x: float, size_z: float) -> void:
	hover_zone.position = Vector3(center.x, 0.1, center.z)
	hover_zone.scale = Vector3(size_x, 1.0, size_z)
	hover_zone.visible = true


func clear_hover_zone() -> void:
	hover_zone.visible = false


# --- per-frame sync -----------------------------------------------------------------------------------------------------------

func sync(selected: int, dt: float) -> void:
	_ensure_actors()
	if sim.season() != _season_drawn:
		_apply_season()
		for d in chunks.keys():
			chunks[d].sig = ""
	_sync_buildings(dt)
	_sync_mobs(dt)
	_sync_festival(dt)
	_sync_caravan()
	_sync_chief_weapon()
	_sync_rival()
	var signature := str(sim.map.claimed.size())
	if signature != _claimed_signature:
		_claimed_signature = signature
		_refresh_frontier()
	for i in range(actors.size()):
		_animate_resident(i, dt)
	var ring_target: Node3D = actors[selected] if selected >= 0 and selected < actors.size() else null
	select_ring.visible = ring_target != null and ring_target.visible
	if select_ring.visible:
		select_ring.position = Vector3(ring_target.position.x, 0.08, ring_target.position.z)
		select_ring.rotation.y += dt * 1.5
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.05
		select_ring.scale = Vector3(pulse, 0.2, pulse)
	var h := fmod(sim.minutes / 60.0, 24.0)
	_daylight = clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0)
	sun.light_energy = lerpf(0.08, 0.9, _daylight) * (0.7 if sim.weather == "Rain" else 1.0)
	sun.light_color = Color("9eb5e0").lerp(Color("fff0cd"), _daylight)
	var sky := Color("4b6073").lerp(Color("b9d7d1"), _daylight)
	sky_environment.background_color = sky
	sky_environment.fog_light_color = sky
	sky_environment.ambient_light_energy = lerpf(0.18, 0.42, _daylight)
	rain.visible = sim.weather == "Rain"
	if rain.visible:
		rain.position = Vector3(_focus.x, 0, _focus.z)
		for drop in rain.get_children():
			drop.position.y = fposmod(drop.position.y - dt * 16.0, 18.0)
	_lamp_timer -= dt
	if _lamp_timer <= 0.0:
		_lamp_timer = 0.5
		_assign_lamps()
	_update_fx(dt)


## Street lamps glow after dark; a small pool of real lights follows whichever lamps are near the focus.
func _assign_lamps() -> void:
	var dark := 1.0 - _daylight
	var nearest: Array = lamp_spots.filter(func(p: Vector3) -> bool: return p.distance_to(_focus) < 60.0)
	nearest.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(_focus) < b.distance_squared_to(_focus))
	for i in range(lamp_pool.size()):
		var light: OmniLight3D = lamp_pool[i]
		if i < nearest.size():
			light.position = nearest[i]
			light.light_energy = lerpf(0.0, 2.2, dark)
		else:
			light.light_energy = 0.0
