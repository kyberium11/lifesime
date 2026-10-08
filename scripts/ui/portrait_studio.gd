class_name PortraitStudio
extends Node
## Renders a head-and-shoulders portrait of every villager model once, so the interface can show faces
## for any number of residents without keeping a live 3D view per person.

signal ready_all

var textures: Dictionary = {}  # model name -> ImageTexture
var is_ready := false

var _art: CityArt
var _viewport: SubViewport
var _holder: Node3D


func setup(art: CityArt) -> void:
	_art = art
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(160, 160)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e6edf2")
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 20, 0)
	key.light_energy = 0.9
	_viewport.add_child(key)
	_holder = Node3D.new()
	_viewport.add_child(_holder)
	var cam := Camera3D.new()
	cam.fov = 24.0
	cam.position = Vector3(0, 2.38, 2.9)
	_viewport.add_child(cam)
	cam.look_at(Vector3(0, 2.26, 0), Vector3.UP)
	call_deferred("_render_all")


func texture_for(model_name: String) -> Texture2D:
	return textures.get(model_name)


func _render_all() -> void:
	var names: Array = Catalog.LOOKS.duplicate()
	names.append(Catalog.CHIEF_LOOK)
	for look in names:
		var model: Node3D
		if look == Catalog.CHIEF_LOOK:
			model = _art.build_chief()
			model.scale = Vector3.ONE / 0.62
		else:
			model = _art.build_character(look, 1.0)
		_holder.add_child(model)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			textures[look] = ImageTexture.create_from_image(image)
		model.queue_free()
	is_ready = true
	ready_all.emit()
