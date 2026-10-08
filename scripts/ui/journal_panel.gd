class_name JournalPanel
extends PanelContainer
## The village journal: the story of each year (written offline, or by the AI when asked) and a timeline of
## everything worth remembering, filterable by kind.

signal closed
signal story_requested(year: int)

var sim: LifeSim
var year := 1
var kind := ""
var ai_available := true
var _year_row: HBoxContainer
var _kind_box: OptionButton
var _story: Label
var _story_button: Button
var _timeline: RichTextLabel
var _count: Label
var _sig := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 14, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.45)))
	visible = false
	custom_minimum_size = Vector2(560, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiKit.label(head, "Village Journal  [J]", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := UiKit.button(head, "", func() -> void: close())
	close_button.custom_minimum_size = Vector2(30, 30)
	var close_icon := Icon.new("close", UiKit.MUTED, 14)
	close_icon.position = Vector2(8, 8)
	close_button.add_child(close_icon)
	_year_row = HBoxContainer.new()
	_year_row.add_theme_constant_override("separation", 6)
	col.add_child(_year_row)
	UiKit.caps(col, "The story of the year")
	_story = UiKit.label(col, "", 14)
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.custom_minimum_size.x = 530
	_story_button = UiKit.button(col, "Ask the storyteller (AI) to retell it", func() -> void: story_requested.emit(year))
	_story_button.add_theme_font_size_override("font_size", 12)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	col.add_child(filter_row)
	UiKit.caps(filter_row, "Timeline")
	_kind_box = OptionButton.new()
	_kind_box.focus_mode = Control.FOCUS_NONE
	_kind_box.add_item("Everything")
	for k in Chronicle.KINDS:
		_kind_box.add_item(str(Chronicle.KINDS[k]))
	_kind_box.item_selected.connect(func(i: int) -> void:
		kind = "" if i == 0 else str(Chronicle.KINDS.keys()[i - 1])
		_sig = ""
		refresh())
	filter_row.add_child(_kind_box)
	_count = UiKit.label(filter_row, "", 12, UiKit.MUTED)
	_timeline = RichTextLabel.new()
	_timeline.bbcode_enabled = true
	_timeline.fit_content = false
	_timeline.scroll_active = true
	_timeline.custom_minimum_size = Vector2(530, 240)
	_timeline.add_theme_font_size_override("normal_font_size", 13)
	col.add_child(_timeline)


func refresh() -> void:
	if sim == null:
		return
	var sig := "%d|%d|%s|%d|%s|%s" % [sim.chronicle.size(), year, kind, sim.day(), str(sim.stories.get(str(year), "")).hash(), str(ai_available)]
	if sig == _sig:
		return
	_sig = sig
	var all_years := Chronicle.years(sim)
	if not all_years.has(year):
		year = int(all_years.back())
	for c in _year_row.get_children():
		c.queue_free()
	UiKit.caps(_year_row, "Year")
	for y in all_years:
		var value: int = y
		var b := UiKit.button(_year_row, str(value), func() -> void:
			year = value
			_sig = ""
			refresh())
		b.toggle_mode = true
		b.set_pressed_no_signal(value == year)
	_story.text = story_for(year)
	_story_button.visible = ai_available
	var list := Chronicle.entries(sim, kind, year)
	_count.text = "%d entries in year %d" % [list.size(), year]
	_timeline.clear()
	if list.is_empty():
		_timeline.append_text("[color=#94a29b]Nothing has been written down yet.[/color]")
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		_timeline.append_text("[color=#94a29b]Day %d · %s[/color]  [color=%s]%s[/color]\n" % [int(e.day), Chronicle.season_of(int(e.day)), Chronicle.KIND_COLOR.get(str(e.kind), "#eef2ee"), str(e.text)])


## The saved story for a year, or the offline account of the year so far.
func story_for(y: int) -> String:
	var saved := str(sim.stories.get(str(y), ""))
	return saved if saved != "" else Chronicle.story_offline(sim, y) + (" (the year is not over yet)" if y == Chronicle.year_of(sim.day()) else "")


func show_ai_story(y: int, text: String) -> void:
	sim.stories[str(y)] = text
	_sig = ""
	refresh()


func close() -> void:
	if visible:
		visible = false
		closed.emit()
