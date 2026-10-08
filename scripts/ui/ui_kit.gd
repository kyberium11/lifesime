class_name UiKit
extends RefCounted
## Design tokens and small widget factories shared by every panel, so the HUD reads as one system.

const INK := Color("eef2ee")
const MUTED := Color("94a29b")
const DIM := Color("5f6d67")
const ACCENT := Color("f0b64a")
const GOOD := Color("7ccf8e")
const WARN := Color("eaa45c")
const BAD := Color("e2645a")
const SOCIAL := Color("e98aa8")
const GLASS := Color(0.065, 0.085, 0.11, 0.90)
const GLASS_HI := Color(0.12, 0.15, 0.19, 0.95)
const EDGE := Color(1, 1, 1, 0.10)

const NEED_ICON := {"hunger": "hunger", "energy": "energy", "hygiene": "hygiene", "social": "social", "fun": "fun", "health": "health"}
const NEED_COLOR := {"hunger": Color("e8955a"), "energy": Color("f0cf5a"), "hygiene": Color("6cc3e6"), "social": Color("e98aa8"), "fun": Color("b793f0"), "health": Color("e2645a")}
const EMOTION_COLOR := {"happy": Color("7ccf8e"), "content": Color("a8d08d"), "gloomy": Color("8aa0b8"), "hungry": Color("e8955a"), "tired": Color("8aa0d8"), "dirty": Color("b09870"), "lonely": Color("e98aa8"), "bored": Color("a0a0a0"), "sick": Color("c8d86a")}


static func box(bg: Color = GLASS, radius: int = 14, margin: int = 12, border: Color = EDGE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.border_color = border
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	return s


static func flat(bg: Color, radius: int = 8, margin: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


static func need_tint(value: float) -> Color:
	if value < 25.0:
		return BAD
	if value < 50.0:
		return WARN
	return GOOD


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", INK)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := Color(1, 1, 1, 0.07)
		match state:
			"hover": bg = Color(1, 1, 1, 0.14)
			"pressed": bg = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
			"disabled": bg = Color(1, 1, 1, 0.03)
			"focus": bg = Color(1, 1, 1, 0.0)
		var sb := flat(bg, 9, 8)
		if state == "focus":
			sb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7)
			sb.set_border_width_all(1)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	var line := flat(Color(0, 0, 0, 0.30), 9, 9)
	line.border_color = EDGE
	line.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", line)
	var focus_line := line.duplicate() as StyleBoxFlat
	focus_line.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", focus_line)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("panel", "PanelContainer", box())
	var tip := box(Color(0.05, 0.06, 0.08, 0.96), 8, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	var grab := flat(Color(1, 1, 1, 0.25), 4, 0)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0), 4, 0))
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	return t


static func label(parent: Node, text: String, size: int = 14, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if parent:
		parent.add_child(l)
	return l


static func caps(parent: Node, text: String) -> Label:
	var l := label(parent, text.to_upper(), 11, MUTED)
	return l


static func button(parent: Node, text: String, callback: Callable, icon_kind: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	if icon_kind != "":
		var ic := Icon.new(icon_kind, INK, 16)
		ic.position = Vector2(8, 8)
		b.add_child(ic)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "      " + text
	if parent:
		parent.add_child(b)
	return b


## A slim progress bar. Returns the bar; set `.value` (0-100) and tint with set_fill().
static func bar(width: float = 100.0, height: float = 7.0, fill: Color = GOOD) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(width, height)
	p.show_percentage = false
	p.max_value = 100.0
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("background", flat(Color(1, 1, 1, 0.10), 4, 0))
	p.add_theme_stylebox_override("fill", flat(fill, 4, 0))
	return p


static func set_fill(p: ProgressBar, color: Color) -> void:
	(p.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color
