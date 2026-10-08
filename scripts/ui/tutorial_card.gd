class_name TutorialCard
extends PanelContainer
## The first-steps checklist in the corner of the screen.

var _list: VBoxContainer
var _title: Label
var _sig := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS, 12, 10))
	mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UiKit.label(head, "", 13, UiKit.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hide_b := UiKit.button(head, "Hide", func() -> void:
		GameSettings.set_value("tutorial_hidden", true)
		refresh())
	hide_b.add_theme_font_size_override("font_size", 11)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	col.add_child(_list)
	refresh()


func refresh() -> void:
	var left := Tutorial.remaining()
	var shown := not bool(GameSettings.value("tutorial_hidden")) and left > 0
	visible = shown
	var sig := str(GameSettings.value("tutorial_done")) + str(shown)
	if sig == _sig:
		return
	_sig = sig
	_title.text = "First steps  (%d left)" % left
	for c in _list.get_children():
		c.queue_free()
	for s in Tutorial.STEPS:
		var done := Tutorial.is_done(str(s.id))
		var l := UiKit.label(_list, ("[x] " if done else "[ ] ") + str(s.text), 12, UiKit.GOOD if done else UiKit.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 300
