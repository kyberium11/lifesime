extends SceneTree
## Renders one building's interior for visual checks (windowed).
## godot --path . --script tests/interior_shot.gd -- <kind> <out.png> [level] [mode: high|low|door]

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var kind: String = args[0]
	var out: String = args[1]
	var level := int(args[2]) if args.size() > 2 else 1
	var mode: String = args[3] if args.size() > 3 else "high"
	var sim := LifeSim.new()
	sim.rng.seed = 3
	sim.money = 5000
	var art := CityArt.new()
	root.add_child(art)
	art.generate(sim)
	var b: Dictionary = {}
	for x in sim.buildings:
		if str(x.kind) == kind:
			b = x
			break
	b.level = level
	b.target = 0
	Interiors.ensure(sim, b)
	if kind == "farm":
		for k in ["chicken", "chicken", "sheep", "cow", "pig"]:
			Farming.add_animal(sim, b, k, -10)
	# Put a few residents inside doing things.
	var view := InteriorView.new()
	root.add_child(view)
	view.setup(sim, art, b)
	var actions: Array = {"home": ["sleep", "cook", "eat", "rest"], "market": ["eat", "work"], "workshop": ["work", "work"], "library": ["study", "study"], "bathhouse": ["wash", "wash"], "office": ["work", "work"], "clinic": ["treat", "treat"], "farm": ["farm", "farm"]}[kind]
	for i in range(mini(sim.residents.size(), actions.size())):
		var r: Dictionary = sim.residents[i]
		r.home = int(b.id)
		r.action = actions[i]
		r.target_id = int(b.id)
		r.route = []
		r.remaining = 500.0
	Ownership.refresh(sim, b)
	var cam := Camera3D.new()
	cam.fov = 58.0
	root.add_child(cam)
	cam.current = true
	var size := view.size
	var centre := view.to_world(Vector2(size.x * 0.5, size.y * 0.5))
	var dist := maxf(size.x, size.y) * 1.05
	var pitch := deg_to_rad(52.0)
	var yaw := 0.0
	if mode == "low":
		pitch = deg_to_rad(24.0)
		dist = maxf(size.x, size.y) * 0.8
	elif mode == "door":
		pitch = deg_to_rad(30.0)
		yaw = PI
		dist = maxf(size.x, size.y) * 0.9
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = centre + dir * dist
	cam.look_at(centre, Vector3.UP)
	for i in range(40):
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(out)
	quit()
