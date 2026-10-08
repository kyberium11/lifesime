class_name OrdersPanel
extends PanelContainer
## Every order the chief can give, as buttons. The same orders can be spoken or typed ("everyone follow me").
## Pick who it applies to (the selected resident, people nearby, or everyone), then click an order.

signal ordered(order: Dictionary)
signal closed

const MOVES := [["Follow me", "follow"], ["Come here", "come"], ["Stay here", "stay"], ["Go home", "home"], ["Carry on", "stop"], ["Stop following", "unfollow"], ["Take cover", "shelter"]]
const ACTIONS := [["Work", "work"], ["Farm", "farm"], ["Gather food", "gather"], ["Chop wood", "chop"], ["Mine stone", "mine"], ["Fetch water", "water"], ["Defend", "guard"], ["Repair", "repair"], ["See doctor", "treat"], ["Cook", "cook"], ["Study", "study"], ["Exercise", "exercise"], ["Play", "play"], ["Socialize", "socialize"], ["Eat", "eat"], ["Sleep", "sleep"], ["Rest", "rest"], ["Wash up", "wash"]]
const BUILDS := [["House", "home"], ["Farm", "farm"], ["Market", "market"], ["Workshop", "workshop"], ["Library", "library"], ["Bathhouse", "bathhouse"], ["Park", "park"], ["Office", "office"]]
const VILLAGE := [["Build something", "build", ""], ["Upgrade", "upgrade", ""], ["Claim land", "expand", ""], ["Approve plan", "approve", ""], ["Festival", "festival", ""], ["Report", "report", ""], ["Council: auto", "council_auto", ""], ["Council: ask me", "council_ask", ""]]
const QUIET := [["Stop talking", "hush"], ["Let them talk", "chatter"], ["Pause", "pause"], ["Resume", "resume"]]

var scope := "default"
var _scope_buttons: Dictionary = {}
var _selected_name := ""
var _scope_note: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS_HI, 16, 14, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.45)))
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiKit.label(head, "Orders", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := UiKit.button(head, "", func() -> void: close())
	close_button.custom_minimum_size = Vector2(30, 30)
	var close_icon := Icon.new("close", UiKit.MUTED, 14)
	close_icon.position = Vector2(8, 8)
	close_button.add_child(close_icon)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 6)
	col.add_child(who)
	UiKit.label(who, "Give orders to:", 12, UiKit.MUTED)
	for entry in [["default", "Selected"], ["near", "Nearby"], ["all", "Everyone"]]:
		var key: String = entry[0]
		var b := UiKit.button(who, str(entry[1]), func() -> void: _set_scope(key))
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		_scope_buttons[key] = b
	_scope_note = UiKit.label(col, "", 12, UiKit.MUTED)
	_section(col, "Move", MOVES, func(v: String) -> Dictionary: return {"intent": v})
	_section(col, "Activities", ACTIONS, func(v: String) -> Dictionary: return {"intent": "action", "action": v})
	_section(col, "Build here", BUILDS, func(v: String) -> Dictionary: return {"intent": "build", "kind": v, "count": 1})
	var village_row := _row(col, "Village")
	for entry in VILLAGE:
		var intent: String = entry[1]
		_button(village_row, str(entry[0]), {"intent": intent, "kind": ""})
	var farm_row := _row(col, "Farm")
	for crop in [["Plant wheat", "wheat"], ["Carrots", "carrot"], ["Corn", "corn"], ["Pumpkins", "pumpkin"]]:
		_button(farm_row, str(crop[0]), {"intent": "crop", "crop": str(crop[1])})
	for beast in [["Buy chicken", "chicken"], ["Buy sheep", "sheep"], ["Buy cow", "cow"], ["Buy pig", "pig"]]:
		_button(farm_row, str(beast[0]), {"intent": "buy_animal", "animal": str(beast[1]), "amount": 1})
	_button(farm_row, "Farm report", {"intent": "farm_report"})
	var wall_row := _row(col, "Walls and gates")
	_button(wall_row, "Wall the village", {"intent": "build", "kind": "wall", "count": 99})
	_button(wall_row, "Add a gate", {"intent": "build", "kind": "gate", "count": 1})
	_button(wall_row, "Open gates", {"intent": "gates_open"})
	_button(wall_row, "Close gates", {"intent": "gates_close"})
	_button(wall_row, "Gates: auto", {"intent": "gates_auto"})
	var trade_row := _row(col, "Trade")
	_button(trade_row, "Market prices", {"intent": "market"})
	_button(trade_row, "Sell surplus", {"intent": "trade", "trade_action": "sell", "item": "surplus", "amount": 0})
	_button(trade_row, "Sell 10 stone", {"intent": "trade", "trade_action": "sell", "item": "stone", "amount": 10})
	_button(trade_row, "Buy 10 food", {"intent": "trade", "trade_action": "buy", "item": "food", "amount": 10})
	_button(trade_row, "Buy 10 wood", {"intent": "trade", "trade_action": "buy", "item": "wood", "amount": 10})
	var quiet_row := _row(col, "Quiet and time")
	for entry in QUIET:
		_button(quiet_row, str(entry[0]), {"intent": str(entry[1])})
	UiKit.label(col, "You can also say these out loud: \"everyone follow me\", \"build two farms\", \"Mira, stop talking\".", 11, UiKit.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_scope("default")


func _row(col: VBoxContainer, title: String) -> HFlowContainer:
	UiKit.label(col, title.to_upper(), 11, UiKit.MUTED)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.custom_minimum_size = Vector2(520, 0)
	col.add_child(flow)
	return flow


func _section(col: VBoxContainer, title: String, entries: Array, make: Callable) -> void:
	var flow := _row(col, title)
	for entry in entries:
		var value: String = entry[1]
		_button(flow, str(entry[0]), make.call(value))


func _button(parent: Control, text: String, order: Dictionary) -> void:
	var b := UiKit.button(parent, text, func() -> void:
		var o := order.duplicate()
		o.scope = scope
		o.names = []
		o.text = text
		ordered.emit(o))
	b.add_theme_font_size_override("font_size", 12)


func _set_scope(key: String) -> void:
	scope = key
	for k in _scope_buttons:
		(_scope_buttons[k] as Button).set_pressed_no_signal(k == key)
	_refresh_note()


func set_selected_name(name_: String) -> void:
	_selected_name = name_
	_refresh_note()


func _refresh_note() -> void:
	if _scope_note == null:
		return
	match scope:
		"all":
			_scope_note.text = "Orders apply to the whole village."
		"near":
			_scope_note.text = "Orders apply to everyone close to you."
		_:
			_scope_note.text = "Orders apply to %s." % (_selected_name if _selected_name != "" else "the selected resident")


func close() -> void:
	if visible:
		visible = false
		closed.emit()
