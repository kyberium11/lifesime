class_name Hud
extends CanvasLayer
## Needs panel, thought/event log, chat box, speech bubble and speed controls.

signal said(text: String)
signal gift_berry
signal gift_wood

var pet: Pet
var camera_label: Label

var _bars: Dictionary = {}
var _status: Label
var _info: Label
var _time: Label
var _log: RichTextLabel
var _chat: LineEdit
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_t := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status_panel(root)
	_build_log_panel(root)
	_build_bubble(root)


func _build_status_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(250, 0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Pip"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_status = Label.new()
	box.add_child(_status)
	for n in ["Hunger", "Energy", "Mood"]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = n
		l.custom_minimum_size.x = 60
		var b := ProgressBar.new()
		b.max_value = 100
		b.show_percentage = false
		b.custom_minimum_size = Vector2(150, 14)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		row.add_child(b)
		box.add_child(row)
		_bars[n] = b
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_time = Label.new()
	box.add_child(_time)
	var speeds := HBoxContainer.new()
	for s in [1.0, 3.0, 8.0]:
		var btn := Button.new()
		btn.text = "%dx" % int(s)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: GameClock.speed = s)
		speeds.add_child(btn)
	var gift1 := Button.new()
	gift1.text = "Gift berry"
	gift1.focus_mode = Control.FOCUS_NONE
	gift1.pressed.connect(func() -> void: gift_berry.emit())
	var gift2 := Button.new()
	gift2.text = "Gift wood"
	gift2.focus_mode = Control.FOCUS_NONE
	gift2.pressed.connect(func() -> void: gift_wood.emit())
	box.add_child(speeds)
	var gifts := HBoxContainer.new()
	gifts.add_child(gift1)
	gifts.add_child(gift2)
	box.add_child(gifts)
	camera_label = Label.new()
	camera_label.text = "Camera: Pip (TAB to switch)  |  WASD walk  |  1/2/3 speed"
	camera_label.add_theme_font_size_override("font_size", 11)
	box.add_child(camera_label)


func _build_log_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12
	panel.offset_right = 612
	panel.offset_top = -250
	panel.offset_bottom = -12
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)
	_chat = LineEdit.new()
	_chat.placeholder_text = "Talk to Pip... (Enter to send, Esc to leave the box)"
	_chat.text_submitted.connect(_on_submit)
	box.add_child(_chat)


func _build_bubble(root: Control) -> void:
	_bubble = PanelContainer.new()
	_bubble.visible = false
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label = Label.new()
	_bubble_label.custom_minimum_size.x = 200
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	_bubble.add_child(_bubble_label)
	root.add_child(_bubble)


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	_chat.clear()
	if text != "":
		add_log("player", text)
		said.emit(text)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _chat.has_focus():
		_chat.release_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not _chat.has_focus():
		_chat.grab_focus()
		get_viewport().set_input_as_handled()


func show_bubble(text: String) -> void:
	_bubble_label.text = text
	_bubble.visible = true
	_bubble_t = 6.0


func add_log(kind: String, text: String) -> void:
	var t := text.replace("[", "[lb]")
	match kind:
		"thought":
			_log.append_text("[color=#9aa4b2][i]%s[/i][/color]\n" % t)
		"speech":
			_log.append_text("[color=#ffd479]Pip: %s[/color]\n" % t)
		"player":
			_log.append_text("[color=#7dd3fc]You: %s[/color]\n" % t)
		"brain":
			_log.append_text("[color=#6b7280][font_size=10]%s[/font_size][/color]\n" % t)
		_:
			_log.append_text("%s\n" % t)


func _process(delta: float) -> void:
	if pet == null:
		return
	_status.text = "Doing: %s" % pet.status_text
	_bars["Hunger"].value = pet.hunger
	_bars["Energy"].value = pet.energy
	_bars["Mood"].value = pet.mood
	_info.text = "Bond %d | Bag: %s" % [pet.bond, pet._inventory_text()]
	_time.text = "Day %d  %s (%s)   speed %dx" % [GameClock.day(), GameClock.time_string(), GameClock.period(), int(GameClock.speed)]
	if _bubble.visible:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
		else:
			var screen := get_viewport().get_canvas_transform() * pet.global_position
			_bubble.position = screen + Vector2(-_bubble.size.x * 0.5, -50.0 - _bubble.size.y)
