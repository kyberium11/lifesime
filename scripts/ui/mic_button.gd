class_name MicButton
extends Control
## A round push-to-talk button. Idle: microphone. Listening: pulsing red ring that follows your voice level.
## Working: a spinner while your words are transcribed.

signal pressed

var listening := false
var working := false
var level := 0.0

var _time := 0.0


func _init(diameter: float = 52.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Click, then speak. It stops when you stop talking. [V]"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func set_state(is_listening: bool, is_working: bool, voice_level: float) -> void:
	listening = is_listening
	working = is_working
	level = voice_level
	queue_redraw()


func _process(dt: float) -> void:
	_time += dt
	if listening or working:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3.0
	var base := Color(0.12, 0.15, 0.2, 0.95)
	var ring := Color(1, 1, 1, 0.22)
	var icon_color := UiKit.INK
	if listening:
		base = Color(0.55, 0.12, 0.12, 0.95)
		ring = UiKit.BAD
		icon_color = Color.WHITE
		var pulse := 1.0 + sin(_time * 7.0) * 0.06 + level * 0.25
		draw_circle(c, radius * pulse + 4.0, Color(UiKit.BAD.r, UiKit.BAD.g, UiKit.BAD.b, 0.22))
	elif working:
		ring = UiKit.ACCENT
		icon_color = UiKit.ACCENT
	draw_circle(c, radius, base)
	draw_arc(c, radius, 0.0, TAU, 48, ring, 2.5, true)
	if working:
		draw_arc(c, radius, _time * 5.0, _time * 5.0 + 1.6, 16, UiKit.ACCENT, 4.0, true)
	var icon_size := radius * 1.05
	Icon.paint(self, "mic", Rect2(c - Vector2(icon_size, icon_size) * 0.5, Vector2(icon_size, icon_size)), icon_color)
	if listening:
		draw_arc(c, radius - 5.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(level, 0.04, 1.0), 40, Color.WHITE, 2.5, true)
