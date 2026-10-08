extends Node2D
## Wires the world, pet, player, camera, HUD and save/load together.
## Debug flags (after `--`): --fresh (ignore save) --nosave --speed=8 --shot=path.png --shot-after=10

const SAVE_PATH := "user://save.json"

var world: World
var pet: Pet
var player: Player
var brain: Brain
var hud: Hud
var camera: Camera2D
var tint: CanvasModulate
var follow_pet := true

var _fresh := false
var _nosave := false
var _verbose := false
var _shot_path := ""
var _shot_after := 8.0
var _autosave := 30.0


func _ready() -> void:
	_parse_args()
	tint = CanvasModulate.new()
	add_child(tint)

	world = World.new()
	add_child(world)

	brain = Brain.new()
	add_child(brain)
	player = Player.new()
	player.world = world
	pet = Pet.new()
	add_child(player)
	add_child(pet)
	pet.setup(world, brain, player)

	var saved := {}
	if not _fresh:
		saved = _read_save()
	if saved.is_empty():
		world.generate_new(randi())
		pet.place(world.center + Vector2i(1, 3))
		player.position = world.cell_to_pos(world.center + Vector2i(-2, 3))
	else:
		GameClock.minutes = float(saved.clock)
		world.from_dict(saved.world)
		pet.from_dict(saved.pet)
		player.position = Vector2(float(saved.player[0]), float(saved.player[1]))

	camera = Camera2D.new()
	camera.zoom = Vector2(3, 3)
	camera.position_smoothing_enabled = true
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = World.W * World.T
	camera.limit_bottom = World.H * World.T
	add_child(camera)
	camera.position = pet.position

	hud = Hud.new()
	add_child(hud)
	hud.pet = pet
	pet.logged.connect(hud.add_log)
	pet.spoke.connect(hud.show_bubble)
	hud.said.connect(pet.hear)
	hud.gift_berry.connect(func() -> void: pet.receive_gift("berry", 1))
	hud.gift_wood.connect(func() -> void: pet.receive_gift("wood", 2))
	if _verbose:
		pet.logged.connect(func(kind: String, text: String) -> void: print("[%s] %s" % [kind, text]))
	if saved.is_empty():
		hud.add_log("event", "Pip woke up in an empty meadow. Say hello!")


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--fresh":
			_fresh = true
		elif a == "--nosave":
			_nosave = true
		elif a == "--verbose":
			_verbose = true
		elif a.begins_with("--speed="):
			GameClock.speed = float(a.substr(8))
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
			_nosave = true
		elif a.begins_with("--shot-after="):
			_shot_after = float(a.substr(13))


func _process(dt: float) -> void:
	var frozen: bool = Data.config.get("pause_while_thinking", true) and (pet.state == Pet.State.THINKING or not brain.ready_to_think)
	var dm := 0.0 if frozen else dt * GameClock.PER_SEC * GameClock.speed
	GameClock.minutes += dm
	world.tick()
	pet.step(dm, 0.0 if frozen else dt * GameClock.speed)
	tint.color = GameClock.daylight()
	camera.position = pet.position if follow_pet else player.position
	_autosave -= dt
	if _autosave <= 0.0:
		_autosave = 30.0
		_save()
	if _shot_path != "":
		_shot_after -= dt
		if _shot_after <= 0.0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_TAB:
			follow_pet = not follow_pet
			hud.camera_label.text = "Camera: %s (TAB to switch)  |  WASD walk  |  1/2/3 speed" % ("Pip" if follow_pet else "You")
		KEY_1:
			GameClock.speed = 1.0
		KEY_2:
			GameClock.speed = 3.0
		KEY_3:
			GameClock.speed = 8.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom + Vector2(0.5, 0.5)).clamp(Vector2(1.5, 1.5), Vector2(6, 6))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom - Vector2(0.5, 0.5)).clamp(Vector2(1.5, 1.5), Vector2(6, 6))


# --- save / load -----------------------------------------------------------

func _save() -> void:
	if _nosave:
		return
	var data := {
		"clock": GameClock.minutes,
		"world": world.to_dict(),
		"pet": pet.to_dict(),
		"player": [player.position.x, player.position.y],
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("world") and parsed.has("pet"):
		return parsed
	return {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
