class_name PortraitFrame
extends Control
## Round portrait with a coloured mood ring (and an optional selection glow).

var ring_color := Color("7ccf8e")
var selected := false
var _clip: Panel
var _tex: TextureRect


func _init(diameter: float = 60.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Panel.new()
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	var sb := UiKit.flat(Color(0.17, 0.22, 0.28), int(diameter), 0)
	_clip.add_theme_stylebox_override("panel", sb)
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(_clip)
	_tex = TextureRect.new()
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.add_child(_tex)


func set_texture(texture: Texture2D) -> void:
	_tex.texture = texture


func set_state(color: Color, is_selected: bool) -> void:
	if color != ring_color or is_selected != selected:
		ring_color = color
		selected = is_selected
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.5
	if selected:
		draw_arc(c, radius + 1.0, 0.0, TAU, 48, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.35), 5.0, true)
	draw_arc(c, radius, 0.0, TAU, 48, ring_color, 3.0, true)
