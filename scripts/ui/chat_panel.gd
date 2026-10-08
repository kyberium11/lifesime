class_name ChatPanel
extends PanelContainer
## Conversation window: portrait header, scrolling history, quick replies, a microphone for speaking and
## a text box for typing. Replies are spoken aloud by the resident.

signal sent(index: int, text: String)
signal mic_pressed
signal closed

const QUICK := ["Hello!", "How are you?", "What do you want to do?", "You're doing great!", "Need anything?", "Tell me about yourself"]

var index := 0
## True while speaking to the whole village: messages go to everyone and commands apply to all.
var broadcast := false
## True while a conversation with a resident is open. Otherwise the panel shows overheard village talk.
var chatting := false
var _chips: HFlowContainer
var _row: HBoxContainer
var _close_button: Button
var _all_button: Button
var _logs: Dictionary = {}
var _title: Label
var _name := ""
var _sub_text := ""
var _sub: Label
var _frame: PortraitFrame
var _log: RichTextLabel
var _typing: Label
var _input: LineEdit
var _mic: MicButton
var _voice_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 12))
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_frame = PortraitFrame.new(48)
	head.add_child(_frame)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	_title = UiKit.label(names, "", 17)
	_sub = UiKit.label(names, "", 12, UiKit.MUTED)
	_all_button = UiKit.button(head, "Everyone", func() -> void: set_broadcast(not broadcast))
	_all_button.toggle_mode = true
	_all_button.tooltip_text = "Talk to the whole village at once. Commands then apply to everyone."
	_all_button.add_theme_font_size_override("font_size", 12)
	_close_button = UiKit.button(head, "", close)
	_close_button.custom_minimum_size = Vector2(30, 30)
	var close_icon := Icon.new("close", UiKit.MUTED, 14)
	close_icon.position = Vector2(8, 8)
	_close_button.add_child(close_icon)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 110)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", UiKit.INK)
	col.add_child(_log)
	_typing = UiKit.label(col, "", 12, UiKit.MUTED)
	var chips := HFlowContainer.new()
	_chips = chips
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	col.add_child(chips)
	for q in QUICK:
		var text: String = q
		var chip := UiKit.button(chips, text, func() -> void: _send(text))
		chip.add_theme_font_size_override("font_size", 12)
	var row := HBoxContainer.new()
	_row = row
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_mic = MicButton.new(46)
	_mic.pressed.connect(func() -> void: mic_pressed.emit())
	row.add_child(_mic)
	_input = LineEdit.new()
	_input.placeholder_text = "Type, or click the mic and speak…"
	_input.max_length = 400
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_input.custom_minimum_size.y = 34
	_input.text_submitted.connect(func(text: String) -> void: _send(text))
	row.add_child(_input)
	UiKit.button(row, "Send", func() -> void: _send(_input.text))
	_voice_label = UiKit.label(col, "", 12, UiKit.MUTED)
	show_overheard()


func _chat_mode(on: bool) -> void:
	chatting = on
	_chips.visible = on
	_row.visible = on
	_voice_label.visible = on
	_typing.visible = on
	_all_button.visible = on
	_close_button.visible = on
	_frame.visible = on
	anchor_top = 0.0 if on else 1.0
	offset_top = 74.0 if on else -430.0


## The quiet state: a transcript of conversations between residents that the chief overhears.
func show_overheard() -> void:
	_chat_mode(false)
	broadcast = false
	_all_button.set_pressed_no_signal(false)
	_title.text = "Village talk"
	_sub.text = "What you overhear around the village"
	visible = true
	_render()


func add_overheard(speaker: String, listener: String, text: String) -> void:
	add_message(-2, false, "%s → %s" % [speaker, listener], text)


func open_for(i: int, name_: String, subtitle: String, texture: Texture2D, color: Color) -> void:
	_chat_mode(true)
	index = i
	_name = name_
	_sub_text = subtitle
	_title.text = "The whole village" if broadcast else name_
	_sub.text = "Commands apply to everyone" if broadcast else subtitle
	_frame.set_texture(texture)
	_frame.set_state(color, false)
	_typing.text = ""
	_input.placeholder_text = "Speak to everyone: \"everyone follow me\", \"build a farm\"…" if broadcast else "Type to %s, or use the mic…" % name_
	visible = true
	_render()


func set_broadcast(on: bool) -> void:
	if not chatting:
		return
	broadcast = on
	_all_button.set_pressed_no_signal(on)
	_title.text = "The whole village" if on else _name
	_input.placeholder_text = "Speak to everyone: \"everyone follow me\", \"build a farm\"…" if on else "Type to %s, or use the mic…" % _name
	_sub.text = "Commands apply to everyone" if on else _sub_text
	_render()


func _key() -> int:
	if not chatting:
		return -2
	return -1 if broadcast else index


func focus_input() -> void:
	_input.grab_focus()


func close() -> void:
	if chatting:
		_input.release_focus()
		show_overheard()
		closed.emit()


func set_subtitle(text: String, color: Color) -> void:
	_sub_text = text
	if broadcast:
		return
	_sub.text = text
	_frame.set_state(color, false)


func set_voice_state(text: String, listening: bool, working: bool, level: float) -> void:
	_voice_label.text = text
	_mic.set_state(listening, working, level)


func add_message(i: int, from_player: bool, name_: String, text: String) -> void:
	if not _logs.has(i):
		_logs[i] = []
	_logs[i].append({"player": from_player, "name": name_, "text": text})
	if _logs[i].size() > 60:
		_logs[i].pop_front()
	if visible and i == _key():
		_render()


## Recent exchange with a resident, oldest first: [{from: "chief"|"resident", text}].
func history(i: int) -> Array:
	var out: Array = []
	for m in _logs.get(i, []):
		out.append({"from": "chief" if m.player else "resident", "text": str(m.text)})
	return out


func set_typing(on: bool, name_: String = "") -> void:
	_typing.text = "%s is thinking…" % name_ if on else ""


## Submit text as if the chief said it (used for typed text and for transcribed speech).
func submit(text: String) -> void:
	_send(text)


func _send(text: String) -> void:
	text = text.strip_edges()
	_input.clear()
	if text == "":
		return
	add_message(_key(), true, "You", text)
	sent.emit(_key(), text)


func _render() -> void:
	_log.clear()
	var messages: Array = _logs.get(_key(), [])
	if messages.is_empty() and not chatting:
		_log.append_text("[color=#94a29b][i]When villagers chat near you, their conversation appears here as they speak.[/i][/color]
")
	elif messages.is_empty():
		_log.append_text("[color=#94a29b][i]Say hello! Pick a quick reply, type, or click the microphone and just talk.[/i][/color]\n")
	for m in messages:
		var who := "[color=#f0b64a][b]%s[/b][/color]" % m.name if m.player else "[color=#8ed0e8][b]%s[/b][/color]" % m.name
		_log.append_text("%s  %s\n" % [who, str(m.text).replace("[", "[lb]")])
