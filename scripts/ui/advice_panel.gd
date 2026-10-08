class_name AdvicePanel
extends PanelContainer
## A resident asks the chief for advice. Shows the question, the real options, and lets you answer by
## clicking, typing a number, or speaking (the microphone matches your words to an option).

signal chosen(option_id: int)
signal mic_pressed
signal closed

var request: Dictionary = {}
var _frame: PortraitFrame
var _title: Label
var _sub: Label
var _question: Label
var _options: VBoxContainer
var _mic: MicButton
var _voice_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 14, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.55)))
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_frame = PortraitFrame.new(52)
	head.add_child(_frame)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	_title = UiKit.label(names, "", 18)
	_sub = UiKit.label(names, "asks for your advice", 12, UiKit.ACCENT)
	var close_button := UiKit.button(head, "", func() -> void: close())
	close_button.custom_minimum_size = Vector2(30, 30)
	var close_icon := Icon.new("close", UiKit.MUTED, 14)
	close_icon.position = Vector2(8, 8)
	close_button.add_child(close_icon)
	_question = UiKit.label(col, "", 15)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.custom_minimum_size = Vector2(340, 0)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	col.add_child(_options)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_mic = MicButton.new(42)
	_mic.pressed.connect(func() -> void: mic_pressed.emit())
	row.add_child(_mic)
	_voice_label = UiKit.label(row, "Or answer out loud: click the mic and say it (\"the first one\", \"build the farm\", \"not now\").", 12, UiKit.MUTED)
	_voice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func open_for(req: Dictionary, name_: String, texture: Texture2D) -> void:
	request = req
	_title.text = name_
	_frame.set_texture(texture)
	_frame.set_state(UiKit.ACCENT, false)
	_question.text = str(req.question)
	for c in _options.get_children():
		c.queue_free()
	var n := 0
	for o in req.options:
		var option: Dictionary = o
		var id := int(option.id)
		var label := str(option.text) if id < 0 else "%d.  %s" % [n + 1, str(option.text)]
		if id >= 0:
			n += 1
		var b := Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(340, 40)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if id < 0:
			b.add_theme_color_override("font_color", UiKit.MUTED)
		b.pressed.connect(func() -> void: chosen.emit(id))
		_options.add_child(b)
	visible = true


func set_voice_state(text: String, listening: bool, working: bool, level: float) -> void:
	_mic.set_state(listening, working, level)
	_voice_label.text = text if listening or working else "Or answer out loud: click the mic and say it (\"the first one\", \"build the farm\", \"not now\")."


func close() -> void:
	if visible:
		visible = false
		request = {}
		closed.emit()
