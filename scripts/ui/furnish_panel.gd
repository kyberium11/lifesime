class_name FurnishPanel
extends PanelContainer
## The furniture shop, opened inside a building. Each button buys that piece and puts it somewhere sensible in the
## room. Personal things (a bed, an armchair, a desk) are given to the selected resident when they live or work here.

signal bought(model: String)
signal closed

var _note: Label
var _buttons: Dictionary = {}
var money := 0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 14, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.45)))
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiKit.label(head, "Furnish", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := UiKit.button(head, "", func() -> void: close())
	close_button.custom_minimum_size = Vector2(30, 30)
	var close_icon := Icon.new("close", UiKit.MUTED, 14)
	close_icon.position = Vector2(8, 8)
	close_button.add_child(close_icon)
	_note = UiKit.label(col, "", 12, UiKit.MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(430, 0)
	for category in FurnitureDb.SHOP:
		UiKit.label(col, str(category).to_upper(), 11, UiKit.MUTED)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		col.add_child(flow)
		for model in FurnitureDb.SHOP[category]:
			var id: String = model
			var b := UiKit.button(flow, "%s  %d" % [FurnitureDb.label_of(id), FurnitureDb.price_of(id)], func() -> void: bought.emit(id))
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = "%s%s. Comfort +%d" % [FurnitureDb.label_of(id), " (personal)" if FurnitureDb.is_personal(id) else "", FurnitureDb.comfort_of(id)]
			_buttons[id] = b


func set_context(note: String, coins: int) -> void:
	_note.text = note
	money = coins
	for id in _buttons:
		(_buttons[id] as Button).disabled = coins < FurnitureDb.price_of(id)


func close() -> void:
	if visible:
		visible = false
		closed.emit()
