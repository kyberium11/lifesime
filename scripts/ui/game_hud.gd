class_name GameHud
extends CanvasLayer
## The screen-space interface: top bar, scrolling household list, resident dock with the microphone,
## a tabbed drawer (People, Skills, Mind, City, Build, Log), notification feed and the chat window.
## Panels are built once and updated in place; lists rebuild only when their contents change.

signal resident_picked(index: int)
signal speed_picked(value: float)
signal save_requested
signal menu_requested
signal ai_toggled
signal voice_replies_toggled
signal microphone_cycled
signal interact_requested(index: int)
signal chat_requested(index: int)
signal mic_pressed
signal queue_cancelled(index: int, slot: int)
signal plan_approved(option: Dictionary)
signal autoplan_toggled
signal build_picked(kind: String)
signal chat_sent(index: int, text: String)
signal overview_toggled

const TAB_NAMES := ["People", "Skills", "Mind", "City", "Build", "Log", "Society"]
const TAB_ICONS := ["social", "skills", "mind", "town", "build", "log", "heart"]

var sim: LifeSim
var studio: PortraitStudio
var root: Control
var chat: ChatPanel
var tab := 0

var _top_stage_label: Label
var _top_stage_bar: ProgressBar
var _pop_label: Label
var _date_label: Label
var _season_label: Label
var _weather_icon: Icon
var _res_labels := {}
var _speed_buttons: Array = []
var _menu_popup: PanelContainer
var _voice_toggle: Button
var _mic_device: Button
var _list_box: VBoxContainer
var _cards: Array = []
var _dock_frame: PortraitFrame
var _dock_name: Label
var _dock_trait: Label
var _dock_emotion_icon: Icon
var _dock_emotion: Label
var _dock_asp: Label
var _need_bars := {}
var _need_values := {}
var _now_icon: Icon
var _now_label: Label
var _now_bar: ProgressBar
var _queue_buttons: Array = []
var _queue_hint: Label
var _want_labels: Array = []
var _want_bars: Array = []
var _dock_mic: MicButton
var _dock_voice: Label
var _tab_buttons: Array = []
var _pages: Array = []
var _people_rows: Array = []
var _skill_rows := {}
var _skills_extra: Label
var _mind_text: RichTextLabel
var _mind_cache := ""
var _city_stage: Label
var _city_bar: ProgressBar
var _city_stats: Label
var _city_buildings: Label
var _city_auto: Button
var _city_plans: VBoxContainer
var _city_plan_sig := ""
var _city_decisions: RichTextLabel
var _city_cache := ""
var _build_buttons := {}
var _build_hint: Label
var _log_text: RichTextLabel
var _society_text: RichTextLabel
var _society_cache := ""
var _log_cache := ""
var _feed: VBoxContainer
var _hint: Label
var _hint_panel: PanelContainer
var _selected_index := 0
var _drawer: PanelContainer
var _drawer_handle: Button
var drawer_open := true


func build(sim_: LifeSim, studio_: PortraitStudio) -> void:
	sim = sim_
	studio = studio_
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.make_theme()
	add_child(root)
	_build_top_bar()
	_build_household()
	_build_dock()
	_build_drawer()
	_build_feed()
	chat = ChatPanel.new()
	_anchor(chat, 0, 1, 0, 1, 78, -430, 450, -190)
	chat.sent.connect(func(i: int, text: String) -> void: chat_sent.emit(i, text))
	chat.mic_pressed.connect(func() -> void: mic_pressed.emit())
	root.add_child(chat)
	_hint_panel = PanelContainer.new()
	_anchor(_hint_panel, 0.5, 1, 0.5, 1, -240, -222, 240, -190)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.07, 0.10, 0.85), 10, 6))
	_hint = UiKit.label(_hint_panel, "", 13, UiKit.ACCENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_panel.visible = false
	root.add_child(_hint_panel)
	_show_tab(0)


func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _icon_button(parent: Node, kind: String, tip: String, callback: Callable, size_: Vector2 = Vector2(38, 34)) -> Button:
	var b := UiKit.button(parent, "", callback)
	b.custom_minimum_size = size_
	b.tooltip_text = tip
	var ic := Icon.new(kind, UiKit.INK, 18)
	ic.position = (size_ - Vector2(18, 18)) * 0.5
	b.add_child(ic)
	return b


func _look_texture(r: Dictionary) -> Texture2D:
	if studio == null:
		return null
	return studio.texture_for(Catalog.LOOKS[int(r.look) % Catalog.LOOKS.size()])


# --- top bar ---------------------------------------------------------------------------------------

func _build_top_bar() -> void:
	var top := PanelContainer.new()
	_anchor(top, 0, 0, 1, 0, 12, 10, -12, 64)
	top.add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS, 14, 8))
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	row.add_child(brand)
	UiKit.label(brand, "WILLOWBROOK", 18, UiKit.INK)
	var stage_row := HBoxContainer.new()
	stage_row.add_theme_constant_override("separation", 6)
	brand.add_child(stage_row)
	stage_row.add_child(Icon.new("town", UiKit.ACCENT, 14))
	_top_stage_label = UiKit.label(stage_row, "Hamlet", 12, UiKit.ACCENT)
	_top_stage_bar = UiKit.bar(70, 5, UiKit.ACCENT)
	stage_row.add_child(_top_stage_bar)
	_pop_label = UiKit.label(stage_row, "", 12, UiKit.MUTED)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_weather_icon = Icon.new("sun", UiKit.ACCENT, 26)
	row.add_child(_weather_icon)
	var when := VBoxContainer.new()
	when.add_theme_constant_override("separation", 0)
	row.add_child(when)
	_date_label = UiKit.label(when, "", 16)
	_season_label = UiKit.label(when, "", 12, UiKit.MUTED)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)
	for key in [["coins", "coin", UiKit.ACCENT], ["materials", "wood", Color("c89b6a")], ["produce", "produce", UiKit.GOOD], ["meals", "meal", Color("e8955a")]]:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 5)
		row.add_child(chip)
		chip.add_child(Icon.new(key[1], key[2], 18))
		_res_labels[key[0]] = UiKit.label(chip, "0", 15)
		(chip.get_child(1) as Label).custom_minimum_size.x = 44
		chip.tooltip_text = String(key[0]).capitalize()
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	row.add_child(speeds)
	var speed_defs := [[0.0, "pause", "Pause (Space)"], [1.0, "play_arrow", "Normal speed (1)"], [3.0, "fast", "Fast (2)"], [8.0, "faster", "Very fast (3)"]]
	for def in speed_defs:
		var value: float = def[0]
		var btn := _icon_button(speeds, def[1], def[2], func() -> void: speed_picked.emit(value))
		_speed_buttons.append({"value": value, "button": btn})
	_icon_button(row, "menu", "Menu", func() -> void: _menu_popup.visible = not _menu_popup.visible)
	_menu_popup = PanelContainer.new()
	_anchor(_menu_popup, 1, 0, 1, 0, -270, 70, -12, 70)
	_menu_popup.add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 12, 10))
	_menu_popup.visible = false
	root.add_child(_menu_popup)
	var menu_col := VBoxContainer.new()
	_menu_popup.add_child(menu_col)
	UiKit.button(menu_col, "Game menu: villages, settings  [Esc]", func() -> void:
		_menu_popup.visible = false
		menu_requested.emit())
	UiKit.button(menu_col, "Save village", func() -> void:
		_menu_popup.visible = false
		save_requested.emit())
	UiKit.button(menu_col, "Toggle Claude AI / local only", func() -> void:
		_menu_popup.visible = false
		ai_toggled.emit())
	_voice_toggle = UiKit.button(menu_col, "Voice replies: on", func() -> void: voice_replies_toggled.emit())
	_mic_device = UiKit.button(menu_col, "Microphone: default", func() -> void: microphone_cycled.emit())
	UiKit.button(menu_col, "Hide interface  [H]", func() -> void:
		_menu_popup.visible = false
		root.visible = false)


func set_voice_menu(replies_on: bool, mic_name: String) -> void:
	_voice_toggle.text = "Voice replies: %s" % ("on" if replies_on else "off")
	_mic_device.text = "Microphone: %s" % mic_name.left(28)


# --- household list ----------------------------------------------------------------------------------

func _build_household() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_anchor(scroll, 0, 0, 0, 1, 12, 74, 70, -12)
	root.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	_list_box.custom_minimum_size.x = 56
	scroll.add_child(_list_box)


func _rebuild_cards() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_cards.clear()
	for i in range(sim.residents.size()):
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(56, 56)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				resident_picked.emit(idx))
		_list_box.add_child(card)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 9)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)
		var frame := PortraitFrame.new(40)
		hb.add_child(frame)
		var info := VBoxContainer.new()
		info.visible = false
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(info)
		var name_row := HBoxContainer.new()
		info.add_child(name_row)
		var name_label := UiKit.label(name_row, str(sim.residents[i].name), 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var emo_icon := Icon.new("content", UiKit.GOOD, 15)
		name_row.add_child(emo_icon)
		var act_row := HBoxContainer.new()
		act_row.add_theme_constant_override("separation", 5)
		info.add_child(act_row)
		var act_icon := Icon.new("rest", UiKit.MUTED, 12)
		act_row.add_child(act_icon)
		var act_label := UiKit.label(act_row, "", 12, UiKit.MUTED)
		act_label.clip_text = true
		act_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mood := UiKit.bar(100, 3, UiKit.GOOD)
		info.add_child(mood)
		_cards.append({"card": card, "frame": frame, "emo": emo_icon, "act_icon": act_icon, "act": act_label, "mood": mood, "tex_set": false})


# --- resident dock -------------------------------------------------------------------------------------

func _build_dock() -> void:
	var dock := PanelContainer.new()
	_anchor(dock, 0, 1, 1, 1, 270, -182, -372, -12)
	dock.add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 12))
	root.add_child(dock)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	dock.add_child(hb)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	hb.add_child(left)
	_dock_frame = PortraitFrame.new(96)
	left.add_child(_dock_frame)
	_dock_asp = UiKit.label(left, "", 11, UiKit.ACCENT)
	_dock_asp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(mid)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	mid.add_child(title)
	_dock_name = UiKit.label(title, "", 22)
	_dock_trait = UiKit.label(title, "", 12, UiKit.MUTED)
	_dock_trait.size_flags_vertical = Control.SIZE_SHRINK_END
	var emo_row := HBoxContainer.new()
	emo_row.add_theme_constant_override("separation", 6)
	mid.add_child(emo_row)
	_dock_emotion_icon = Icon.new("content", UiKit.GOOD, 16)
	emo_row.add_child(_dock_emotion_icon)
	_dock_emotion = UiKit.label(emo_row, "", 13, UiKit.GOOD)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	mid.add_child(grid)
	for n in LifeSim.NEEDS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 5)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.tooltip_text = String(n).capitalize()
		grid.add_child(cell)
		cell.add_child(Icon.new(UiKit.NEED_ICON[n], UiKit.NEED_COLOR[n], 16))
		var bar := UiKit.bar(60, 8, UiKit.NEED_COLOR[n])
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(bar)
		var value := UiKit.label(cell, "", 11, UiKit.MUTED)
		value.custom_minimum_size.x = 22
		_need_bars[n] = bar
		_need_values[n] = value
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	mid.add_child(actions)
	UiKit.button(actions, "Interact", func() -> void: interact_requested.emit(_selected_index), "socialize").custom_minimum_size = Vector2(112, 34)
	UiKit.button(actions, "Talk", func() -> void: chat_requested.emit(_selected_index), "talk").custom_minimum_size = Vector2(84, 34)
	_dock_mic = MicButton.new(46)
	_dock_mic.pressed.connect(func() -> void: mic_pressed.emit())
	actions.add_child(_dock_mic)
	_dock_voice = UiKit.label(actions, "", 12, UiKit.MUTED)
	_dock_voice.clip_text = true
	_dock_voice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_voice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	right.custom_minimum_size.x = 236
	hb.add_child(right)
	var now_row := HBoxContainer.new()
	now_row.add_theme_constant_override("separation", 6)
	right.add_child(now_row)
	_now_icon = Icon.new("rest", UiKit.INK, 18)
	now_row.add_child(_now_icon)
	_now_label = UiKit.label(now_row, "", 14)
	_now_label.clip_text = true
	_now_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_bar = UiKit.bar(100, 5, UiKit.ACCENT)
	right.add_child(_now_bar)
	UiKit.caps(right, "Up next")
	var queue_row := HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 5)
	right.add_child(queue_row)
	for slot in range(LifeSim.MAX_QUEUE):
		var s := slot
		var chip := _icon_button(queue_row, "rest", "", func() -> void: queue_cancelled.emit(_selected_index, s), Vector2(34, 30))
		chip.visible = false
		_queue_buttons.append(chip)
	_queue_hint = UiKit.label(queue_row, "Nothing queued", 12, UiKit.DIM)
	UiKit.caps(right, "Wishes")
	for k in range(2):
		var want_label := UiKit.label(right, "", 12, UiKit.INK)
		want_label.clip_text = true
		var want_bar := UiKit.bar(100, 4, UiKit.ACCENT)
		right.add_child(want_bar)
		_want_labels.append(want_label)
		_want_bars.append(want_bar)


func set_voice_state(text: String, listening: bool, working: bool, level: float) -> void:
	_dock_voice.text = text
	_dock_mic.set_state(listening, working, level)
	if chat != null:
		chat.set_voice_state(text, listening, working, level)


# --- drawer (tabs) ---------------------------------------------------------------------------------------

func _build_drawer() -> void:
	var drawer := PanelContainer.new()
	_drawer = drawer
	_anchor(drawer, 1, 0, 1, 1, -360, 74, -12, -12)
	drawer.add_theme_stylebox_override("panel", UiKit.box(Color(0.065, 0.085, 0.11, 0.97), 16, 10))
	root.add_child(drawer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	drawer.add_child(col)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 3)
	col.add_child(tab_row)
	for i in range(TAB_NAMES.size()):
		var idx := i
		var b := UiKit.button(tab_row, "", func() -> void: _show_tab(idx))
		b.custom_minimum_size = Vector2(38, 44)
		b.tooltip_text = TAB_NAMES[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ic := Icon.new(TAB_ICONS[i], UiKit.MUTED, 18)
		ic.position = Vector2(10, 5)
		b.add_child(ic)
		var cap := UiKit.label(b, TAB_NAMES[i], 9, UiKit.MUTED)
		cap.position = Vector2(0, 26)
		cap.size = Vector2(38, 14)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tab_buttons.append({"button": b, "icon": ic, "cap": cap})
	var hide_button := UiKit.button(tab_row, "››", toggle_drawer)
	hide_button.custom_minimum_size = Vector2(34, 44)
	hide_button.add_theme_font_size_override("font_size", 12)
	hide_button.tooltip_text = "Collapse this panel"
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)
	_drawer_handle = UiKit.button(root, "›", toggle_drawer)
	_drawer_handle.tooltip_text = "Collapse or expand the side panel (backslash key)"
	_drawer_handle.add_theme_font_size_override("font_size", 20)
	_anchor(_drawer_handle, 1, 0.5, 1, 0.5, -388, -36, -362, 36)
	get_viewport().size_changed.connect(_fit_drawer)
	_fit_drawer.call_deferred()
	_pages = [_build_people_page(), _build_skills_page(), _build_mind_page(), _build_city_page(), _build_build_page(), _build_log_page(), _build_society_page()]
	for page in _pages:
		(page as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)


func _scroll_page() -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	return [sc, vb]


func _build_people_page() -> ScrollContainer:
	var made := _scroll_page()
	var vb: VBoxContainer = made[1]
	UiKit.caps(vb, "Closest relationships")
	for k in range(6):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.05), 12, 10, Color(1, 1, 1, 0.06)))
		vb.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		card.add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		var name_label := UiKit.label(top, "", 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var level := UiKit.label(top, "", 12, UiKit.SOCIAL)
		var bar := UiKit.bar(100, 7, UiKit.SOCIAL)
		col.add_child(bar)
		_people_rows.append({"card": card, "name": name_label, "level": level, "bar": bar})
	return made[0]


func _build_skills_page() -> ScrollContainer:
	var made := _scroll_page()
	var vb: VBoxContainer = made[1]
	UiKit.caps(vb, "Skills")
	for k in ["craft", "cooking", "gardening", "knowledge", "fitness"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		vb.add_child(row)
		var top := HBoxContainer.new()
		row.add_child(top)
		var title := UiKit.label(top, String(k).capitalize(), 14)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var level := UiKit.label(top, "", 12, UiKit.ACCENT)
		var bar := UiKit.bar(100, 7, UiKit.ACCENT)
		row.add_child(bar)
		_skill_rows[k] = {"level": level, "bar": bar}
	UiKit.caps(vb, "Career")
	_skills_extra = UiKit.label(vb, "", 13)
	_skills_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return made[0]


func _rich_page() -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", UiKit.INK)
	sc.add_child(rt)
	return [sc, rt]


func _build_mind_page() -> ScrollContainer:
	var made := _rich_page()
	_mind_text = made[1]
	return made[0]


func _build_society_page() -> ScrollContainer:
	var made := _rich_page()
	_society_text = made[1]
	return made[0]


func _build_log_page() -> ScrollContainer:
	var made := _rich_page()
	_log_text = made[1]
	return made[0]


func _build_city_page() -> ScrollContainer:
	var made := _scroll_page()
	var vb: VBoxContainer = made[1]
	UiKit.caps(vb, "Willowbrook")
	_city_stage = UiKit.label(vb, "", 20, UiKit.ACCENT)
	_city_bar = UiKit.bar(100, 7, UiKit.ACCENT)
	vb.add_child(_city_bar)
	_city_stats = UiKit.label(vb, "", 13)
	_city_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_city_buildings = UiKit.label(vb, "", 12, UiKit.MUTED)
	_city_buildings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.button(vb, "Overview map  [Tab]", func() -> void: overview_toggled.emit(), "town").custom_minimum_size.y = 34
	UiKit.caps(vb, "The council's plans")
	_city_auto = UiKit.button(vb, "", func() -> void: autoplan_toggled.emit())
	_city_auto.custom_minimum_size.y = 34
	var note := UiKit.label(vb, "You decide, or let the council act on its own.", 12, UiKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_city_plans = VBoxContainer.new()
	_city_plans.add_theme_constant_override("separation", 6)
	vb.add_child(_city_plans)
	UiKit.caps(vb, "Decisions")
	_city_decisions = RichTextLabel.new()
	_city_decisions.bbcode_enabled = true
	_city_decisions.fit_content = true
	_city_decisions.scroll_active = false
	_city_decisions.add_theme_font_size_override("normal_font_size", 12)
	_city_decisions.add_theme_color_override("default_color", UiKit.INK)
	vb.add_child(_city_decisions)
	return made[0]


func _build_build_page() -> ScrollContainer:
	var made := _scroll_page()
	var vb: VBoxContainer = made[1]
	UiKit.caps(vb, "Build mode")
	for kind in Catalog.BUILDABLE:
		var k: String = kind
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 58)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void: build_picked.emit(k))
		vb.add_child(b)
		var ic := Icon.new(Catalog.spec(k).icon, UiKit.ACCENT, 26)
		ic.position = Vector2(12, 16)
		b.add_child(ic)
		var title := UiKit.label(b, "", 15)
		title.position = Vector2(50, 7)
		var desc := UiKit.label(b, str(Catalog.spec(k).desc), 11, UiKit.MUTED)
		desc.position = Vector2(50, 30)
		desc.size = Vector2(250, 18)
		desc.clip_text = true
		_build_buttons[k] = {"button": b, "title": title}
	_build_hint = UiKit.label(vb, "Pick a building, then click a free lot on claimed land (the green squares in overview). Residents finish it during work shifts.", 12, UiKit.MUTED)
	_build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return made[0]


func _show_tab(i: int) -> void:
	tab = i
	for k in range(_pages.size()):
		(_pages[k] as Control).visible = k == i
		var t: Dictionary = _tab_buttons[k]
		var on := k == i
		(t.icon as Icon).set_icon(TAB_ICONS[k], UiKit.ACCENT if on else UiKit.MUTED)
		(t.cap as Label).add_theme_color_override("font_color", UiKit.ACCENT if on else UiKit.MUTED)
		var b: Button = t.button
		var bg := Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.16) if on else Color(1, 1, 1, 0.0)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, UiKit.flat(bg if state == "normal" else Color(1, 1, 1, 0.1), 10, 0))


func show_tab(i: int) -> void:
	set_drawer(true)
	_show_tab(i)


## On a narrow window the side panel would cover the game, so start with it folded away.
func _fit_drawer() -> void:
	if get_viewport().get_visible_rect().size.x < 1000.0 and drawer_open:
		set_drawer(false)


func toggle_drawer() -> void:
	set_drawer(not drawer_open)


func set_drawer(open: bool) -> void:
	drawer_open = open
	_drawer.visible = open
	_drawer_handle.text = "›" if open else "‹ Panel"
	if open:
		_anchor(_drawer_handle, 1, 0.5, 1, 0.5, -388, -36, -362, 36)
	else:
		_anchor(_drawer_handle, 1, 0, 1, 0, -92, 76, -8, 112)


# --- notification feed --------------------------------------------------------------------------------------

func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 6)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_feed, 0.5, 0, 0.5, 0, -150, 118, 150, 400)
	root.add_child(_feed)


func toast(text: String, icon: String = "star", color: Color = UiKit.ACCENT) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiKit.box(Color(0.07, 0.09, 0.12, 0.94), 12, 9, Color(color.r, color.g, color.b, 0.5)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	var ic := Icon.new(icon, color, 18)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(ic)
	var label := UiKit.label(hb, text, 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 215
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(card)
	while _feed.get_child_count() > 5:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tw := create_tween()
	card.modulate.a = 0.0
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.tween_interval(6.0)
	tw.tween_property(card, "modulate:a", 0.0, 0.8)
	tw.tween_callback(card.queue_free)


func set_hint(text: String) -> void:
	_hint_panel.visible = text != ""
	_hint.text = text


func chat_reply(index: int, name_: String, text: String) -> void:
	chat.add_message(index, false, name_, text)
	if chat.chatting and chat.index == index:
		chat.set_typing(false)


# --- refresh ---------------------------------------------------------------------------------------------------

func refresh(selected: int, speed: float, build_kind: String, plans: Array) -> void:
	_selected_index = selected
	var r: Dictionary = sim.residents[selected]
	if _cards.size() != sim.residents.size():
		_rebuild_cards()
	# Top bar.
	_top_stage_label.text = sim.stage_name()
	_top_stage_bar.value = sim.stage_progress() * 100.0
	_pop_label.text = "%d / %d beds" % [sim.residents.size(), sim.housing()]
	_date_label.text = "Day %d  ·  %s" % [sim.day(), sim.clock_text()]
	_season_label.text = "%s  ·  %s%s" % [sim.season(), sim.weather, "  ·  Paused" if speed == 0.0 else ""]
	var weather_kind: String = "snow" if sim.season() == "Winter" and sim.weather != "Clear" else {"Clear": "sun", "Cloudy": "cloud", "Rain": "rain"}[sim.weather]
	_weather_icon.set_icon(weather_kind, UiKit.ACCENT if sim.weather == "Clear" else Color("a9c4d6"))
	(_res_labels.coins as Label).text = str(sim.money)
	(_res_labels.materials as Label).text = str(sim.materials())
	(_res_labels.produce as Label).text = str(sim.food)
	(_res_labels.meals as Label).text = str(sim.meals)
	for entry in _speed_buttons:
		var b: Button = entry.button
		var on: bool = is_equal_approx(float(entry.value), speed)
		var bg := Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.30) if on else Color(1, 1, 1, 0.07)
		b.add_theme_stylebox_override("normal", UiKit.flat(bg, 9, 8))
	# Household list.
	for i in range(_cards.size()):
		var c: Dictionary = _cards[i]
		var ri: Dictionary = sim.residents[i]
		var emo := sim.emotion(ri)
		var emo_color: Color = UiKit.EMOTION_COLOR.get(emo, UiKit.INK)
		if not c.tex_set and _look_texture(ri) != null:
			(c.frame as PortraitFrame).set_texture(_look_texture(ri))
			c.tex_set = true
		(c.frame as PortraitFrame).set_state(emo_color, i == selected)
		(c.emo as Icon).set_icon(emo, emo_color)
		(c.act_icon as Icon).set_icon(str(ri.action), UiKit.MUTED)
		var talking := sim.talking.has(i)
		(c.act as Label).text = "Talking" if talking else "%s%s" % [LifeSim.ACTION_VERBS[ri.action], "  ·  inside" if sim.is_inside(ri) else ""]
		var highlight := Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.7) if i == selected else UiKit.EDGE
		(c.card as PanelContainer).add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI if i == selected else UiKit.GLASS, 12, 7, highlight))
		(c.card as PanelContainer).tooltip_text = "%s: %s" % [ri.name, (c.act as Label).text]
		(c.mood as ProgressBar).value = sim.mood(ri)
		UiKit.set_fill(c.mood, UiKit.need_tint(sim.mood(ri)))
	# Dock.
	var emotion_ := sim.emotion(r)
	var emotion_color: Color = UiKit.EMOTION_COLOR.get(emotion_, UiKit.INK)
	if _look_texture(r) != null:
		_dock_frame.set_texture(_look_texture(r))
	_dock_frame.set_state(emotion_color, false)
	_dock_name.text = str(r.name)
	_dock_trait.text = "%s  ·  age %d" % [r.trait, r.age]
	_dock_emotion_icon.set_icon(emotion_, emotion_color)
	_dock_emotion.text = emotion_.capitalize()
	_dock_emotion.add_theme_color_override("font_color", emotion_color)
	_dock_asp.text = "Aspiration Lv %d  ·  %d pts" % [sim.aspiration_level(r), int(r.points)]
	for n in LifeSim.NEEDS:
		var v := float(r.needs[n])
		(_need_bars[n] as ProgressBar).value = v
		UiKit.set_fill(_need_bars[n], UiKit.need_tint(v))
		(_need_values[n] as Label).text = str(int(v))
	_now_icon.set_icon(str(r.action), UiKit.ACCENT)
	var where := " at the %s" % str(r.target).to_lower() if r.target != "Square" else " in the square"
	_now_label.text = "%s%s%s" % [LifeSim.ACTION_VERBS[r.action], where, "  (you asked)" if r.commanded else ""]
	_now_bar.value = sim.activity_progress(r) * 100.0
	for slot in range(_queue_buttons.size()):
		var qb: Button = _queue_buttons[slot]
		if slot < r.queue.size():
			qb.visible = true
			qb.tooltip_text = "Cancel: %s" % LifeSim.ACTION_VERBS[r.queue[slot]]
			((qb.get_child(0)) as Icon).set_icon(str(r.queue[slot]), UiKit.INK)
		else:
			qb.visible = false
	_queue_hint.visible = r.queue.is_empty()
	for k in range(2):
		if k < r.wants.size():
			var w: Dictionary = r.wants[k]
			(_want_labels[k] as Label).text = "%s  (+%d)" % [w.text, int(w.points)]
			(_want_bars[k] as ProgressBar).value = sim.want_progress(r, w) * 100.0
		else:
			(_want_labels[k] as Label).text = ""
			(_want_bars[k] as ProgressBar).value = 0.0
	match tab:
		0: _refresh_people(selected)
		1: _refresh_skills(r)
		2: _refresh_mind(r)
		3: _refresh_city(plans)
		4: _refresh_build(build_kind)
		5: _refresh_log()
		6: _refresh_society()


func _refresh_people(selected: int) -> void:
	var r: Dictionary = sim.residents[selected]
	var rows: Array = [{"name": "You (the chief)", "score": float(r.bond)}]
	var others: Array = []
	for i in range(sim.residents.size()):
		if i != selected and sim.relation(r, sim.residents[i].name) > 0.0:
			others.append({"name": str(sim.residents[i].name), "score": sim.relation(r, sim.residents[i].name)})
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	rows.append_array(others.slice(0, _people_rows.size() - 1))
	for k in range(_people_rows.size()):
		var row: Dictionary = _people_rows[k]
		(row.card as Control).visible = k < rows.size()
		if k < rows.size():
			var d: Dictionary = rows[k]
			(row.name as Label).text = d.name
			(row.level as Label).text = "%s  ·  %d" % [Social.bond_label(d.score), int(d.score)]
			(row.bar as ProgressBar).value = d.score


func _refresh_skills(r: Dictionary) -> void:
	for k in _skill_rows:
		var xp := float(r.skills[k])
		(_skill_rows[k].level as Label).text = "Level %d" % (1 + int(xp / 60.0))
		(_skill_rows[k].bar as ProgressBar).value = fmod(xp, 60.0) / 60.0 * 100.0
	_skills_extra.text = "Career level %d  ·  earned %d coins\nCompleted %d activities\nAspiration level %d (%d pts)" % [r.career, r.earned, r.completed, sim.aspiration_level(r), int(r.points)]


func _heading(title: String) -> String:
	return "[color=#f0b64a][b]%s[/b][/color]\n" % title


func _refresh_mind(r: Dictionary) -> void:
	var inner := Psyche.describe(sim, r)
	var o: Dictionary = r.ocean
	var text := _heading("INTENTION") + "%s\n\n" % str(r.thought).replace("[", "[lb]")
	text += _heading("INNER LIFE")
	text += "%s, age %d. %s.\n" % [inner.stage, int(r.age), str(inner.personality).capitalize()]
	text += "[color=#94a29b]Openness %d · Conscientiousness %d · Extraversion %d · Agreeableness %d · Neuroticism %d[/color]\n" % [int(float(o.o) * 100), int(float(o.c) * 100), int(float(o.e) * 100), int(float(o.a) * 100), int(float(o.n) * 100)]
	text += "Values: %s\n" % inner["values"]
	text += "Stress: %s (%d)   ·   Health: %s\n" % [inner.stress, int(r.stress), inner.health]
	text += "Talent: %s   ·   Hardiness %d%%\n\n" % [str(r.genes.talent), int(float(r.genes.hardy) * 100)]
	if str(inner.get("job", "")) != "":
		text += "Job: %s - savings %d coins\n\n" % [inner.job, int(inner.savings)]
	var dream := Quests.get_of(r)
	if not dream.is_empty():
		var stage_note: String = ["has not yet told you", "is waiting for your answer", "is working towards it", "achieved it!"][clampi(int(dream.stage), 0, 3)]
		text += "Dream: %s (%s)

" % [dream.text, stage_note]
	var belongings := str(inner.get("belongings", ""))
	text += _heading("HOME AND BELONGINGS")
	var own_home := sim.building_by_id(int(r.home))
	if not own_home.is_empty():
		text += "Lives in a level %d %s (comfort %d)
" % [int(own_home.level), Catalog.label(str(own_home.kind)).to_lower(), Ownership.comfort(own_home)]
	text += (("Owns: " + belongings) if belongings != "" else "[color=#94a29b]Owns nothing yet.[/color]") + "

"
	text += _heading("TIES")
	if str(r.partner) != "":
		text += "%s: %s (romance %d)\n" % ["Spouse" if bool(r.get("married", false)) else "Partner", r.partner, int(float(r.romance.get(r.partner, 0.0)))]
	if str(inner.family) != "":
		text += "%s\n" % inner.family
	var friends: Array = []
	var rivals: Array = []
	for name_ in r.relations:
		friends.append([name_, float(r.relations[name_])])
	friends.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	for name_ in r.rivalry:
		if float(r.rivalry[name_]) >= 20.0:
			rivals.append("%s (%d)" % [name_, int(float(r.rivalry[name_]))])
	if not friends.is_empty():
		text += "Closest: %s\n" % ", ".join(friends.slice(0, 3).map(func(x: Array) -> String: return "%s %d" % [x[0], int(x[1])]))
	if not rivals.is_empty():
		text += "Rivals: %s\n" % ", ".join(rivals)
	var rep := Rumors.reputation(sim, str(r.name))
	text += "Reputation: %s (%d)   ·   Trusts the chief: %s\n\n" % [Rumors.reputation_label(rep), int(rep), Social.bond_label(float(r.bond)).to_lower()]
	if not r.core.is_empty():
		text += _heading("CORE MEMORIES")
		for c in r.core:
			text += "• %s\n" % str(c.text).replace("[", "[lb]")
		text += "\n"
	if not r.heard.is_empty():
		text += _heading("GOSSIP THEY'VE HEARD")
		for id in (r.heard as Array).slice(-4):
			var ru := Rumors.find(sim, int(id))
			if not ru.is_empty():
				text += "• %s\n" % str(ru.text).replace("[", "[lb]")
		text += "\n"
	text += _heading("MEMORIES")
	if r.memory.is_empty():
		text += "[color=#94a29b]A new life, waiting to be written.[/color]"
	else:
		var recent: Array = r.memory.slice(-8)
		recent.reverse()
		for m in recent:
			text += "• %s\n\n" % str(m).replace("[", "[lb]")
	if text != _mind_cache:
		_mind_cache = text
		_mind_text.text = text


func _refresh_society() -> void:
	var text := _heading("MARKET")
	for item in ["food", "wood", "stone"]:
		var now := Economy.price(sim, item)
		var base := float(Economy.BASE_PRICE[item])
		var trend := "dear" if now > base * 1.25 else ("cheap" if now < base * 0.8 else "fair")
		text += "%s  %.2f coins   [color=#94a29b](%s)[/color]\n" % [item.capitalize(), now, trend]
	text += "\n" + _heading("WORLD EVENTS")
	if sim.events.is_empty():
		text += "[color=#94a29b]Quiet for now.[/color]\n"
	for e in sim.events:
		text += "• %s\n" % str(e.text)
	var ill := 0
	for r in sim.residents:
		if Health.is_ill(sim, r):
			ill += 1
	text += "\n" + _heading("HEALTH AND SAFETY")
	text += "Sick: %d%s   ·   Homes %s   ·   Monsters: %d   ·   Slain: %d\n" % [ill, " (epidemic!)" if sim.epidemic else "", "cold: out of firewood" if sim.cold_homes else "warm", sim.threat, sim.kills]
	text += "\n" + _heading("REPUTATION")
	var ranked: Array = []
	for r in sim.residents:
		ranked.append([str(r.name), Rumors.reputation(sim, str(r.name))])
	ranked.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	for entry in ranked.slice(0, 3):
		text += "%s  %s (%d)\n" % [entry[0], Rumors.reputation_label(entry[1]), int(entry[1])]
	if ranked.size() > 4:
		text += "[color=#94a29b]…[/color]\n"
		for entry in ranked.slice(ranked.size() - 2):
			text += "%s  %s (%d)\n" % [entry[0], Rumors.reputation_label(entry[1]), int(entry[1])]
	text += "\n" + _heading("RUMOURS IN CIRCULATION")
	if sim.rumors.is_empty():
		text += "[color=#94a29b]Nothing is being whispered.[/color]\n"
	else:
		for ru in sim.rumors.slice(-6):
			var mark := "" if int(ru.hops) == 0 else "  [color=#94a29b](passed on %d×)[/color]" % int(ru.hops)
			text += "• %s%s\n" % [str(ru.text).replace("[", "[lb]"), mark]
	text += "\n" + _heading("FAMILIES")
	var any := false
	var seen := {}
	for r in sim.residents:
		if str(r.partner) != "" and not seen.has(str(r.name)):
			seen[str(r.name)] = true
			seen[str(r.partner)] = true
			any = true
			var kids: Array = r.children
			text += "%s & %s%s\n" % [r.name, r.partner, "  ·  children: %s" % ", ".join(kids) if not kids.is_empty() else ""]
	if not any:
		text += "[color=#94a29b]No couples yet.[/color]\n"
	text += "\n" + _heading("JOBS")
	var any_job := false
	for entry in Jobs.summary(sim):
		any_job = true
		text += "%s: %s%s\n" % [entry.label, ", ".join(entry.names) if not entry.names.is_empty() else "nobody", "  [color=#e8955a](%d open)[/color]" % int(entry.open) if int(entry.open) > 0 else ""]
	if not any_job:
		text += "[color=#94a29b]No trades yet. Build farms, markets and a clinic.[/color]\n"
	text += "\n" + _heading("FARMS")
	var farm_lines := 0
	for fb in sim.buildings:
		if str(fb.kind) != "farm" or int(fb.level) < 1:
			continue
		farm_lines += 1
		var herd: Array = []
		for kind in Farming.ANIMALS:
			var n := Farming.count(fb, kind)
			if n > 0:
				herd.append("%d %s" % [n, Farming.ANIMALS[kind].plural if n != 1 else str(Farming.ANIMALS[kind].label).to_lower()])
		var made := Farming.produce_of(fb)
		var shelf := ""
		if int(made.get("eggs", 0)) + int(made.get("milk", 0)) + int(made.get("wool", 0)) > 0:
			shelf = "  [color=#94a29b](waiting: %d eggs, %d milk, %d wool)[/color]" % [int(made.get("eggs", 0)), int(made.get("milk", 0)), int(made.get("wool", 0))]
		text += "%s %d%%  ·  %s  ·  %d/%d pen%s%s\n" % [str(Farming.CROPS[Farming.crop_of(fb)].label), int(float(fb.get("growth", 0.0))), ", ".join(herd) if not herd.is_empty() else "no animals", Farming.slots_used(fb), Farming.slots_total(fb), shelf, "  [color=#e8955a]hungry![/color]" if int(fb.get("hungry", 0)) > 0 else ""]
	if farm_lines == 0:
		text += "[color=#94a29b]No farms yet.[/color]\n"
	var wall_state := Walls.status(sim)
	text += "\n" + _heading("DEFENCES")
	if int(wall_state.segments) == 0:
		text += "[color=#94a29b]No walls yet. Open the Orders panel to wall the village.[/color]\n"
	else:
		text += "Walls: %d of %d border edges (%d breached)\n" % [int(wall_state.intact), int(wall_state.border), int(wall_state.breached)]
		text += "Gates: %d (%s)\n" % [int(wall_state.gates), "open" if sim.gates_state == "open" else "shut"]
	var worn := Economy.worst_building(sim, 70.0)
	text += "\n" + _heading("UPKEEP")
	if worn.is_empty():
		text += "Every building is in good repair.\n"
	else:
		text += "Worst: the %s at %d%% condition. Order a repair.\n" % [Catalog.label(str(worn.kind)).to_lower(), int(float(worn.get("condition", 100.0)))]
	if text != _society_cache:
		_society_cache = text
		_society_text.text = text


func _refresh_city(plans: Array) -> void:
	_city_stage.text = sim.stage_name()
	_city_bar.value = sim.stage_progress() * 100.0
	var next_pop := "" if sim.stage() >= Catalog.STAGES.size() - 1 else "  ·  next stage at %d residents" % Catalog.STAGE_POP[sim.stage() + 1]
	_city_stats.text = "%d residents  ·  %d beds  ·  %d districts  ·  %d free lots%s" % [sim.residents.size(), sim.housing(), sim.map.claimed.size(), sim.map.free_lots().size(), next_pop]
	var counts := {}
	for b in sim.buildings:
		if int(b.level) >= 1 and b.kind != "plaza":
			counts[b.kind] = int(counts.get(b.kind, 0)) + 1
	var parts: Array = []
	for kind in Catalog.BUILDABLE:
		if counts.has(kind):
			parts.append("%s ×%d" % [Catalog.label(kind), counts[kind]])
	_city_buildings.text = ", ".join(parts) if not parts.is_empty() else "No buildings yet."
	_city_auto.text = "Council acts on its own: %s" % ("ON" if sim.auto_plan else "OFF (you decide)")
	# Plan cards rebuild only when the plans change.
	var sig := ""
	for o in plans:
		sig += "%s|" % str(o.label)
	if sig != _city_plan_sig:
		_city_plan_sig = sig
		for c in _city_plans.get_children():
			c.queue_free()
		if plans.is_empty():
			var none := UiKit.label(_city_plans, "Nothing pressing right now. The council is saving up.", 12, UiKit.MUTED)
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for o in plans.slice(0, 5):
			_add_plan_card(o)
	var decisions := ""
	for d in sim.decisions.slice(-6):
		decisions += "[color=#5f6d67]Day %d[/color]  [b]%s[/b]: %s\n" % [int(d.day), str(d.by), str(d.text)]
	if decisions != _city_cache:
		_city_cache = decisions
		_city_decisions.text = decisions if decisions != "" else "[color=#94a29b]No decisions yet.[/color]"


func _add_plan_card(option: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.05), 12, 10, Color(1, 1, 1, 0.07)))
	_city_plans.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var title := UiKit.label(col, str(option.label), 14)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var why := UiKit.label(col, str(option.reason), 12, UiKit.MUTED)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	col.add_child(row)
	var cost := UiKit.label(row, "%d coins%s" % [int(option.coins), "" if int(option.mats) == 0 else "  ·  %d materials" % int(option.mats)], 12, UiKit.ACCENT)
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var opt := option
	UiKit.button(row, "Approve", func() -> void: plan_approved.emit(opt)).custom_minimum_size = Vector2(90, 30)


func _refresh_build(build_kind: String) -> void:
	for k in _build_buttons:
		var entry: Dictionary = _build_buttons[k]
		var b: Button = entry.button
		var on: bool = k == build_kind
		var cost := Catalog.cost(k, 1)
		var locked := Catalog.stage_needed(k, 1) > sim.stage()
		(entry.title as Label).text = "%s  ·  %d coins%s" % [Catalog.label(k), cost.coins, "  ·  needs %s" % Catalog.STAGES[Catalog.stage_needed(k, 1)] if locked else ""]
		var bg := Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.25) if on else Color(1, 1, 1, 0.06)
		b.add_theme_stylebox_override("normal", UiKit.flat(bg, 12, 8))
		b.disabled = locked or sim.money < int(cost.coins) or sim.materials() < int(cost.mats)


func _refresh_log() -> void:
	var lines: Array = sim.journal.slice(-30)
	lines.reverse()
	var text := ""
	for line in lines:
		var s := str(line)
		text += "[color=#5f6d67]%s[/color]  %s\n\n" % [s.substr(0, 5), s.substr(7).replace("[", "[lb]")]
	if text != _log_cache:
		_log_cache = text
		_log_text.text = text
