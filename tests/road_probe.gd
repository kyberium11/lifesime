extends SceneTree
## Renders road pieces at four rotations (top-down) to learn which directions each one connects.
## godot --path . --script tests/road_probe.gd -- <out.png>

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var pieces := ["road-straight", "road-bend", "road-intersection", "road-crossroad", "road-end"]
	var world := Node3D.new()
	root.add_child(world)
	for row in range(pieces.size()):
		for k in range(4):
			var scene: PackedScene = load("res://assets/kenney/roads/%s.glb" % pieces[row])
			var inst: Node3D = scene.instantiate()
			inst.position = Vector3(k * 1.6, 0, row * 1.6)
			inst.rotation_degrees.y = k * 90.0
			world.add_child(inst)
			var label := Label3D.new()
			label.text = "%s r%d" % [pieces[row].replace("road-", ""), k * 90]
			label.position = Vector3(k * 1.6, 0.02, row * 1.6 + 0.72)
			label.rotation_degrees = Vector3(-90, 0, 0)
			label.pixel_size = 0.0035
			label.font_size = 40
			label.outline_size = 10
			world.add_child(label)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("55606a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.4
	world.add_child(cam)
	cam.position = Vector3(2.4, 20, 3.2)
	cam.look_at(Vector3(2.4, 0, 3.2), Vector3(0, 0, -1))
	for i in range(6):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
