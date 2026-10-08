class_name MarketPanel
extends PanelContainer
## The village market: every good, crop and animal with its price today, a sparkline of recent prices,
## how many the village has, and buy/sell buttons. Prices come from supply, season, events and the village's
## market buildings (they narrow the market's cut). Pick an amount, then click.

signal traded(action: String, item: String, amount: int)
signal closed

const GOODS_ROWS := ["food", "wood", "stone", "wheat", "carrot", "corn", "pumpkin"]
const ANIMAL_ROWS := ["a_chicken", "a_sheep", "a_cow", "a_pig"]

var sim: LifeSim
var amount := 1
var _rows: Dictionary = {}
var _amount_buttons: Dictionary = {}
var _cut_label: Label
var _coins_label: Label
var _timer := 0.0
var _caravan_box: VBoxContainer
var _caravan_title: Label
var _caravan_sig := "x"
var _route_label: Label
var _route_button: Button


class Sparkline:
	extends Control
	var values: Array = []
	var base := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(84, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.05))
		if values.size() < 2:
			return
		var lo: float = float(values.min())
		var hi: float = float(values.max())
		var span := maxf(hi - lo, 0.01)
		var pts := PackedVector2Array()
		for i in range(values.size()):
			var x := 3.0 + (size.x - 6.0) * float(i) / float(values.size() - 1)
			var y := size.y - 3.0 - (size.y - 6.0) * (float(values[i]) - lo) / span
			pts.append(Vector2(x, y))
		var rising: bool = float(values[values.size() - 1]) >= float(values[0])
		var color := Color("e8955a") if rising else Color("7ccf8e")
		draw_polyline(pts, color, 1.8, true)
		draw_circle(pts[pts.size() - 1], 2.4, color)


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 14, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.45)))
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiKit.label(head, "Market", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coins_label = UiKit.label(head, "", 14, UiKit.ACCENT)
	var close_button := UiKit.button(head, "", func() -> void: close())
	close_button.custom_minimum_size = Vector2(30, 30)
	var close_icon := Icon.new("close", UiKit.MUTED, 14)
	close_icon.position = Vector2(8, 8)
	close_button.add_child(close_icon)
	var amounts := HBoxContainer.new()
	amounts.add_theme_constant_override("separation", 6)
	col.add_child(amounts)
	UiKit.label(amounts, "Amount per click:", 12, UiKit.MUTED)
	for n in [1, 5, 10, 25]:
		var value: int = n
		var b := UiKit.button(amounts, str(n), func() -> void: _set_amount(value))
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		_amount_buttons[n] = b
	_cut_label = UiKit.label(col, "", 11, UiKit.MUTED)
	_section(col, "Goods and crops", GOODS_ROWS)
	_section(col, "Livestock", ANIMAL_ROWS)
	_caravan_title = UiKit.label(col, "TRAVELLING MERCHANT", 11, UiKit.MUTED)
	_caravan_box = VBoxContainer.new()
	_caravan_box.add_theme_constant_override("separation", 4)
	col.add_child(_caravan_box)
	var route_row := HBoxContainer.new()
	route_row.add_theme_constant_override("separation", 8)
	col.add_child(route_row)
	_route_label = UiKit.label(route_row, "", 12, UiKit.MUTED)
	_route_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_button = UiKit.button(route_row, "Open trade route", func() -> void: traded.emit("route", "route", 1))
	_route_button.add_theme_font_size_override("font_size", 12)
	_set_amount(1)


func _section(col: VBoxContainer, title: String, items: Array) -> void:
	UiKit.label(col, title.to_upper(), 11, UiKit.MUTED)
	for item in items:
		var id: String = item
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var name_label := UiKit.label(row, "", 14)
		name_label.custom_minimum_size.x = 92
		var price_label := UiKit.label(row, "", 14)
		price_label.custom_minimum_size.x = 92
		var spark := Sparkline.new()
		row.add_child(spark)
		var have_label := UiKit.label(row, "", 12, UiKit.MUTED)
		have_label.custom_minimum_size.x = 70
		var buy := UiKit.button(row, "Buy", func() -> void: traded.emit("buy", id, amount))
		buy.add_theme_font_size_override("font_size", 12)
		var sell := UiKit.button(row, "Sell", func() -> void: traded.emit("sell", id, amount))
		sell.add_theme_font_size_override("font_size", 12)
		_rows[id] = {"name": name_label, "price": price_label, "spark": spark, "have": have_label, "buy": buy, "sell": sell}


func _set_amount(n: int) -> void:
	amount = n
	for k in _amount_buttons:
		(_amount_buttons[k] as Button).set_pressed_no_signal(k == n)


## Redraw prices, history and stock from the simulation.
func refresh() -> void:
	if sim == null:
		return
	_coins_label.text = "%d coins" % sim.money
	_cut_label.text = "The market keeps %d%% of each trade (more market buildings lower it). Crops can only be sold from the harvest." % int(round(Economy.spread(sim) * 100.0))
	var sig := str(sim.caravan) + str(sim.money / 10)
	if sig != _caravan_sig:
		_caravan_sig = sig
		_rebuild_caravan()
	_route_label.text = "Trade route level %d of %d: caravans visit more often and sales earn %d%% more." % [sim.routes, Caravans.MAX_ROUTE, 5 * sim.routes]
	_route_button.disabled = sim.routes >= Caravans.MAX_ROUTE or sim.money < Caravans.ROUTE_COST * (sim.routes + 1)
	_route_button.text = "Open route (%d)" % (Caravans.ROUTE_COST * (sim.routes + 1)) if sim.routes < Caravans.MAX_ROUTE else "Fully open"
	for id in _rows:
		var row: Dictionary = _rows[id]
		var now := Economy.price(sim, id)
		var base := Economy.base_of(id)
		(row.name as Label).text = Economy.label_of(id)
		var mood_color := UiKit.BAD if now > base * 1.25 else (UiKit.GOOD if now < base * 0.8 else UiKit.INK)
		(row.price as Label).text = "%.2f" % now
		(row.price as Label).add_theme_color_override("font_color", mood_color)
		var spark: Sparkline = row.spark
		spark.values = sim.price_history.get(id, [])
		spark.base = base
		spark.queue_redraw()
		(row.have as Label).text = "have %d" % Economy.stock_of(sim, id)
		(row.sell as Button).disabled = Economy.stock_of(sim, id) <= 0
		(row.buy as Button).disabled = sim.money < int(ceil(Economy.buy_price(sim, id)))


func _rebuild_caravan() -> void:
	for c in _caravan_box.get_children():
		c.queue_free()
	if not Caravans.present(sim):
		UiKit.label(_caravan_box, "No merchant is in town. Caravans visit more often along trade routes.", 12, UiKit.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	UiKit.label(_caravan_box, "%s is camped outside until day %d." % [sim.caravan.name, int(sim.caravan.until)], 12, UiKit.ACCENT)
	for key in sim.caravan.stock:
		var id: String = key
		var ware: Dictionary = Caravans.WARES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_caravan_box.add_child(row)
		var name_label := UiKit.label(row, str(ware.label), 14)
		name_label.custom_minimum_size.x = 112
		name_label.tooltip_text = str(ware.blurb)
		var price_label := UiKit.label(row, "%d coins" % Caravans.price_of(sim, id), 14)
		price_label.custom_minimum_size.x = 92
		var have := UiKit.label(row, "%d left" % Caravans.stock_of(sim, id), 12, UiKit.MUTED)
		have.custom_minimum_size.x = 70
		var buy := UiKit.button(row, "Buy", func() -> void: traded.emit("buy", id, 1))
		buy.add_theme_font_size_override("font_size", 12)
		buy.disabled = Caravans.stock_of(sim, id) <= 0 or sim.money < Caravans.price_of(sim, id)
		var blurb := UiKit.label(row, str(ware.blurb), 11, UiKit.MUTED)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size.x = 260


func _process(dt: float) -> void:
	if not visible:
		return
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.4
		refresh()


func close() -> void:
	if visible:
		visible = false
		closed.emit()
