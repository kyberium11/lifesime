extends SceneTree
## Renders a labelled contact sheet of Kenney models for choosing assets.
## godot --path . --script tests/model_sheet.gd -- <pack> <out.png> [columns] [prefix-filter]

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var pack: String = args[0]
	var out: String = args[1]
	var columns := int(args[2]) if args.size() > 2 else 7
	var prefix: String = args[3] if args.size() > 3 else ""
	var top_down: bool = args.size() > 4 and args[4] == "top"
	var dir := DirAccess.open("res://assets/kenney/%s" % pack)
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb") and f.begins_with(prefix):
			names.append(f.get_basename())
	names.sort()
	var world := Node3D.new()
	root.add_child(world)
	var spacing := 2.6
	var rows := int(ceil(names.size() / float(columns)))
	for i in range(names.size()):
		var scene: PackedScene = load("res://assets/kenney/%s/%s.glb" % [pack, names[i]])
		var inst: Node3D = scene.instantiate()
		var x := (i % columns) * spacing
		var z := (i / columns) * spacing
		inst.position = Vector3(x, 0, z)
		world.add_child(inst)
		var label := Label3D.new()
		label.text = String(names[i]).replace("building-", "").replace("type-", "t-")
		if pack == "characters":
			label.position = Vector3(x, 3.1, z)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		else:
			label.position = Vector3(x, 0.02, z + 1.0)
			label.rotation_degrees = Vector3(-90, 0, 0)
		label.pixel_size = 0.006
		label.font_size = 40
		label.modulate = Color.WHITE
		label.outline_size = 12
		world.add_child(label)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("55606a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("dfe6ee")
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var width := columns * spacing
	var height := rows * spacing
	cam.size = maxf(height * 1.15, width * 0.62)
	world.add_child(cam)
	if top_down:
		cam.size = maxf(height, width * 0.62) * 1.12
		cam.position = Vector3(width * 0.5 - 1.3, 30.0, height * 0.5 - 1.3)
		cam.look_at(Vector3(width * 0.5 - 1.3, 0.0, height * 0.5 - 1.3), Vector3(0, 0, -1))
	else:
		cam.position = Vector3(width * 0.5 - 1.3 + 6.0, 14.0, height * 0.5 - 1.3 + 14.0)
		cam.look_at(Vector3(width * 0.5 - 1.3, 0.8, height * 0.5 - 1.3))
	for i in range(6):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " models=", names.size())
	quit()
