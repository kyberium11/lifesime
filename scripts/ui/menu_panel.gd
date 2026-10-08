class_name MenuPanel
extends PanelContainer
## The pause menu: save slots (save, load, delete, new village), settings, and the controls list.

signal resumed
signal slot_saved(slot: int)
signal slot_loaded(slot: int)
signal slot_deleted(slot: int)
signal new_village
signal setting_changed(key: String, value: Variant)
signal tutorial_reset
signal quit_game

const CONTROLS := [
	["W A S D / Shift", "Walk / run the chief"], ["Right-drag, wheel", "Look around, zoom"], ["Click", "Select or open the circle menu on a person, building or lot"],
	["E", "Use the door, gate, ladder or tower in front of you"], ["T / V", "Talk by keyboard / by microphone"], ["Z", "Fly: toggle (E climbs, Q descends; walls and roofs stop you below their height)"], ["O", "Orders: type or speak what the village should do"],
	["K", "Market (and the travelling merchant)"], ["G", "Furnish the room you are in"], ["J", "Village journal"], ["P", "Photo mode"],
	["F", "Attack: tap for a three-hit combo (or fire from a tower)"], ["R", "Heavy attack: slow, knocks foes back"], ["Ctrl", "Dodge roll: a moment of invulnerability"], ["Hold Y", "Block: a shield soaks most of a blow from the front"], ["X", "Switch weapon: bare hands or what the armory holds"], ["Space, 1 2 3", "Pause, normal, fast, very fast"], ["Tab", "Overview camera"],
	["[ ]", "Previous / next resident"], ["B, C", "Build and City tabs"], ["Backslash", "Collapse the side panel"], ["H", "Hide the interface"], ["M", "Voice replies on/off"], ["Esc", "Close things; open this menu"],
]

var slot_dir := SaveSlots.DIR
var _tabs: Array = []
var _pages: Array = []
var _slot_box: VBoxContainer
var _confirm := ""
var _status: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 16, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.45)))
	visible = false
	custom_minimum_size = Vector2(620, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var title := UiKit.label(head, "Willowbrook", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(3):
		var index: int = i
		var b := UiKit.button(head, ["Villages", "Settings", "Controls"][i], func() -> void: show_page(index))
		b.toggle_mode = true
		_tabs.append(b)
	UiKit.button(head, "Resume", func() -> void: close())
	_status = UiKit.label(col, "", 12, UiKit.MUTED)
	_pages.append(_build_slots(col))
	_pages.append(_build_settings(col))
	_pages.append(_build_controls(col))
	show_page(0)


func _build_slots(col: VBoxContainer) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	col.add_child(page)
	UiKit.label(page, "Save to a slot to keep several villages, or load one to go back. The current village also saves itself when you quit.", 12, UiKit.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 6)
	page.add_child(_slot_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	UiKit.button(row, "Start a new village", func() -> void: _confirmed("new", func() -> void: new_village.emit()))
	UiKit.button(row, "Quit game", func() -> void: quit_game.emit())
	return page


func _build_settings(col: VBoxContainer) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	col.add_child(page)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	page.add_child(vol_row)
	var vol_label := UiKit.label(vol_row, "Voice volume", 14)
	vol_label.custom_minimum_size.x = 150
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 150
	slider.step = 5
	slider.value = float(GameSettings.value("voice_volume"))
	slider.custom_minimum_size.x = 260
	slider.value_changed.connect(func(v: float) -> void: _apply_setting("voice_volume", int(v)))
	vol_row.add_child(slider)
	_check(page, "Residents speak their replies aloud", "voice_replies")
	_check(page, "Blood and gore in fights", "blood")
	_check(page, "AI (local model) writes conversations, advice and the year's story", "ai")
	_choice(page, "Graphics quality", "quality", GameSettings.QUALITY)
	_choice(page, "Monsters at night", "difficulty", GameSettings.DIFFICULTY.keys())
	UiKit.label(page, "Peaceful turns monsters off completely; harsh brings bigger and more frequent waves. Changes apply at once.", 12, UiKit.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_check(page, "Show the first-steps checklist", "tutorial_hidden", true)
	UiKit.button(page, "Restart the tutorial", func() -> void:
		tutorial_reset.emit()
		_say("Tutorial restarted."))
	return page


func _check(page: VBoxContainer, text: String, key: String, inverted: bool = false) -> void:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(GameSettings.value(key)) != inverted
	c.toggled.connect(func(on: bool) -> void: _apply_setting(key, on != inverted))
	page.add_child(c)


func _choice(page: VBoxContainer, text: String, key: String, options: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	page.add_child(row)
	var l := UiKit.label(row, text, 14)
	l.custom_minimum_size.x = 150
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	for o in options:
		ob.add_item(str(o).capitalize())
	ob.select(maxi(0, options.find(GameSettings.value(key))))
	ob.item_selected.connect(func(i: int) -> void: _apply_setting(key, str(options[i])))
	row.add_child(ob)


func _apply_setting(key: String, v: Variant) -> void:
	GameSettings.set_value(key, v)
	setting_changed.emit(key, v)


func _build_controls(col: VBoxContainer) -> Control:
	var page := GridContainer.new()
	page.columns = 2
	page.add_theme_constant_override("h_separation", 18)
	page.add_theme_constant_override("v_separation", 3)
	col.add_child(page)
	for c in CONTROLS:
		var k := UiKit.label(page, str(c[0]), 13, UiKit.ACCENT)
		k.custom_minimum_size.x = 150
		UiKit.label(page, str(c[1]), 13)
	return page


func show_page(i: int) -> void:
	for n in range(_pages.size()):
		(_pages[n] as Control).visible = n == i
		(_tabs[n] as Button).set_pressed_no_signal(n == i)
	if i == 0:
		refresh_slots()


func refresh_slots() -> void:
	for c in _slot_box.get_children():
		c.queue_free()
	for entry in SaveSlots.list(slot_dir):
		var slot: int = entry.slot
		var exists: bool = entry.exists
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_slot_box.add_child(row)
		UiKit.label(row, "Slot %d" % (slot + 1), 14, UiKit.ACCENT).custom_minimum_size.x = 52
		var info := UiKit.label(row, SaveSlots.describe(entry), 12, UiKit.INK if exists else UiKit.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 300
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := "save%d" % slot
		UiKit.button(row, "Overwrite?" if _confirm == key else "Save", func() -> void:
			if exists:
				_confirmed(key, func() -> void: slot_saved.emit(slot))
			else:
				slot_saved.emit(slot))
		var load_b := UiKit.button(row, "Sure?" if _confirm == "load%d" % slot else "Load", func() -> void: _confirmed("load%d" % slot, func() -> void: slot_loaded.emit(slot)))
		load_b.disabled = not exists
		var del := UiKit.button(row, "Delete?" if _confirm == "del%d" % slot else "Delete", func() -> void: _confirmed("del%d" % slot, func() -> void: slot_deleted.emit(slot)))
		del.disabled = not exists


## Dangerous buttons need two clicks.
func _confirmed(key: String, action: Callable) -> void:
	if _confirm == key:
		_confirm = ""
		action.call()
	else:
		_confirm = key
		_say("Click again to confirm.")
	refresh_slots()


func _say(text: String) -> void:
	_status.text = text


func status(text: String) -> void:
	_say(text)
	refresh_slots()


func open() -> void:
	_confirm = ""
	_status.text = ""
	visible = true
	show_page(0)


func close() -> void:
	if visible:
		visible = false
		resumed.emit()
