class_name Player
extends Node2D
## The human caretaker. WASD / arrow keys to walk around the village.

const SPEED := 56.0

var world: World


func _ready() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	var s := Sprite2D.new()
	s.texture = Art.player_texture()
	s.name = "Sprite"
	add_child(s)


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		return
	var step := dir * SPEED * delta
	var nx := position + Vector2(step.x, 0)
	if world.walkable(world.pos_to_cell(nx)):
		position = nx
	var ny := position + Vector2(0, step.y)
	if world.walkable(world.pos_to_cell(ny)):
		position = ny
	if dir.x != 0.0:
		$Sprite.flip_h = dir.x < 0.0
