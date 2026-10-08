extends SceneTree
## Renders the city with CityArt only (no UI) for visual checks.
## godot --path . --script tests/city_view.gd -- <out.png> [days] [mode: chief|overview|close] [yaw_deg]

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var days := int(args[1]) if args.size() > 1 else 0
	var mode: String = args[2] if args.size() > 2 else "chief"
	var yaw := deg_to_rad(float(args[3])) if args.size() > 3 else 0.6
	var sim := LifeSim.new()
	for i in range(days * 1440):
		sim.tick(1.0)
	var art := CityArt.new()
	root.add_child(art)
	art.generate(sim)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	var target := art.chief.position + Vector3(0, 1.4, 0)
	var dist := 7.0
	var pitch := deg_to_rad(18.0)
	if mode == "overview":
		target = Vector3(10, 0, 8)
		dist = 70.0
		pitch = deg_to_rad(52.0)
	elif mode == "chiefclose":
		target = art.chief.position + Vector3(0, 1.1, 0)
		dist = 3.2
		pitch = deg_to_rad(8.0)
	elif mode == "residents":
		target = art.actors[0].position + Vector3(0, 1.0, 0)
		dist = 6.0
		pitch = deg_to_rad(16.0)
	elif mode == "close":
		target = CityMap.tile_to_world(Vector2i(2, 3)) + Vector3(0, 2.0, 0)
		dist = 9.0
		pitch = deg_to_rad(22.0)
	var offset := Vector3(0, sin(pitch), cos(pitch)) * dist
	cam.position = target + offset.rotated(Vector3.UP, yaw)
	cam.look_at(target)
	art.update_world(target, true)
	for i in range(8):
		art.sync(0, 0.016)
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " residents=", sim.residents.size(), " buildings=", sim.buildings.size(), " chunks=", art.chunks.size())
	quit()
