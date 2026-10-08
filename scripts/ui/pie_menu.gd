class_name PieMenu
extends Control
## Sims-style radial interaction menu with sub-menus.
## Item: {label, icon, color?, enabled?, hint?, action: Callable, children?: Array}

signal closed

const RADIUS := 96.0
const SLOT := 31.0

var _stack: Array = []
var _items: Array = []
var _title := ""
var _subtitle := ""
var _center := Vector2.ZERO
var _hover := -1  # -1 nothing, -2 centre
var _t := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open(at: Vector2, title: String, subtitle: String, items: Array) -> void:
	_stack.clear()
	_items = items
	_title = title
	_subtitle = subtitle
	_t = 0.0
	_hover = -1
	var vp := get_viewport_rect().size
	var pad := RADIUS + SLOT + 34.0
	_center = Vector2(clampf(at.x, pad, vp.x - pad), clampf(at.y, pad, vp.y - pad - 20.0))
	position = Vector2.ZERO
	size = vp
	visible = true


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _slot_pos(i: int, n: int) -> Vector2:
	var eased := 1.0 - pow(1.0 - clampf(_t, 0.0, 1.0), 3.0)
	var a := -PI / 2.0 + float(i) * TAU / float(maxi(n, 1))
	return _center + Vector2(cos(a), sin(a)) * RADIUS * eased


func _process(dt: float) -> void:
	if visible:
		# A Control directly under a CanvasLayer has no parent to size against, so cover the viewport by hand.
		var view := get_viewport_rect().size
		if size != view:
			position = Vector2.ZERO
			size = view
		_t = minf(1.0, _t + dt * 6.5)
		queue_redraw()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _hit(p: Vector2) -> int:
	if p.distance_to(_center) < 36.0:
		return -2
	for i in range(_items.size()):
		if p.distance_to(_slot_pos(i, _items.size())) <= SLOT + 5.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _hit(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			close()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var h := _hit(event.position)
			if h == -2:
				if _stack.is_empty():
					close()
				else:
					var prev: Dictionary = _stack.pop_back()
					_items = prev.items
					_title = prev.title
					_t = 0.5
			elif h >= 0:
				_activate(_items[h])
			else:
				close()
		accept_event()


func _activate(item: Dictionary) -> void:
	if not item.get("enabled", true):
		return
	var children: Array = item.get("children", [])
	if not children.is_empty():
		_stack.append({"items": _items, "title": _title})
		_items = children
		_title = str(item.label)
		_t = 0.35
		_hover = -1
		return
	close()
	var action: Callable = item.get("action", Callable())
	if action.is_valid():
		action.call()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.30 * clampf(_t * 1.5, 0.0, 1.0)))
	var n := _items.size()
	var fade := clampf(_t * 1.6, 0.0, 1.0)
	draw_arc(_center, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.10 * fade), 2.0, true)
	for i in range(n):
		var item: Dictionary = _items[i]
		var enabled: bool = item.get("enabled", true)
		var p := _slot_pos(i, n)
		var hot := i == _hover and enabled
		var rad := SLOT + (4.0 if hot else 0.0)
		var tint: Color = item.get("color", UiKit.ACCENT)
		var bg := Color(0.09, 0.11, 0.15, 0.96 * fade)
		draw_circle(p + Vector2(0, 3), rad + 1.0, Color(0, 0, 0, 0.35 * fade))
		draw_circle(p, rad, bg)
		draw_arc(p, rad, 0.0, TAU, 40, Color(tint.r, tint.g, tint.b, (0.95 if enabled else 0.25) * fade), 2.5 if hot else 1.8, true)
		if hot:
			draw_circle(p, rad - 2.0, Color(tint.r, tint.g, tint.b, 0.22))
		var icon_col := tint if enabled else UiKit.DIM
		Icon.paint(self, str(item.get("icon", "star")), Rect2(p - Vector2(13, 13), Vector2(26, 26)), icon_col)
		if not item.get("children", []).is_empty():
			draw_circle(p + Vector2(rad - 6, -rad + 6), 4.0, tint)
		var label := str(item.label)
		var ls := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var lp := p + Vector2(-ls.x * 0.5, rad + 14.0)
		draw_rect(Rect2(lp + Vector2(-5, -12), ls + Vector2(10, 5)), Color(0.04, 0.05, 0.07, 0.8 * fade), true)
		draw_string(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.INK if enabled else UiKit.DIM)
	# Centre: title, or hint of the hovered item.
	draw_circle(_center, 36.0, Color(0.05, 0.06, 0.09, 0.95 * fade))
	draw_arc(_center, 36.0, 0.0, TAU, 40, Color(1, 1, 1, 0.18 * fade), 1.5, true)
	var top := _title
	var bottom := _subtitle
	if _hover >= 0 and _hover < n:
		var hovered: Dictionary = _items[_hover]
		top = str(hovered.label)
		bottom = str(hovered.get("hint", ""))
	if _hover == -2 and not _stack.is_empty():
		top = "Back"
		bottom = ""
	var title_size := 14
	while title_size > 9 and _font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 66.0:
		title_size -= 1
	var ts := _font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size)
	draw_string(_font, _center + Vector2(-ts.x * 0.5, -2), top, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, UiKit.INK)
	if bottom != "":
		draw_multiline_string(_font, _center + Vector2(-33, 13), bottom, HORIZONTAL_ALIGNMENT_CENTER, 66, 10, 2, UiKit.MUTED)
	if not _stack.is_empty() and _hover != -2:
		Icon.paint(self, "chevron_left", Rect2(_center + Vector2(-9, 16), Vector2(18, 18)), UiKit.MUTED)
	# Hint shown outside when an item is disabled for a reason.
	if _hover >= 0 and _hover < n and not _items[_hover].get("enabled", true):
		var why := str(_items[_hover].get("hint", ""))
		if why != "":
			var ws := _font.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var wp := _center + Vector2(-ws.x * 0.5, RADIUS + SLOT + 40.0)
			draw_rect(Rect2(wp + Vector2(-8, -14), ws + Vector2(16, 8)), Color(0.45, 0.12, 0.1, 0.9), true)
			draw_string(_font, wp, why, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
