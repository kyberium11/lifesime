class_name PhotoMode
extends CanvasLayer
## Photo mode: the interface hides, the camera flies freely, a filter can be chosen, and a photo is saved as a PNG
## in user://photos. The host scene moves the camera; this node owns the filter, the little toolbar and the capture.

signal exited
signal captured(path: String)
signal filter_changed(name: String)

const FILTERS := ["Natural", "Warm", "Cool", "Noir", "Vivid", "Vintage"]
const DIR := "user://photos"
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	if (mode == 1) { c = c * vec3(1.08, 1.0, 0.88) + vec3(0.03, 0.01, -0.02); }
	else if (mode == 2) { c = c * vec3(0.88, 1.0, 1.12); }
	else if (mode == 3) { c = vec3(l); c = (c - 0.5) * 1.15 + 0.5; }
	else if (mode == 4) { c = mix(vec3(l), c, 1.45); c = (c - 0.5) * 1.1 + 0.5; }
	else if (mode == 5) { c = mix(c, vec3(l * 1.1, l * 0.95, l * 0.78), 0.8); }
	vec2 q = SCREEN_UV - 0.5;
	float v = smoothstep(0.9, 0.2, length(q) * 1.2);
	if (mode == 3 || mode == 5) { c *= mix(0.6, 1.0, v); }
	COLOR = vec4(c, 1.0);
}
"""

var active := false
var filter := 0
var photo_dir := DIR
var shots := 0
var _rect: ColorRect
var _bar: PanelContainer
var _filter_label: Label
var _material: ShaderMaterial


func _ready() -> void:
	layer = 20
	visible = false
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material
	add_child(_rect)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme = UiKit.make_theme()
	add_child(holder)
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UiKit.box(UiKit.GLASS, 14, 10))
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -330
	_bar.offset_right = 330
	_bar.offset_top = -92
	_bar.offset_bottom = -16
	holder.add_child(_bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_bar.add_child(col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	UiKit.button(row, "<", func() -> void: cycle_filter(-1))
	_filter_label = UiKit.label(row, "", 14, UiKit.ACCENT)
	_filter_label.custom_minimum_size.x = 100
	_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.button(row, ">", func() -> void: cycle_filter(1))
	UiKit.button(row, "Take photo  [Enter]", func() -> void: take_photo())
	UiKit.button(row, "Done  [P]", func() -> void: exit())
	UiKit.label(col, "WASD fly · Q/E down/up · Shift faster · right-drag look · wheel forward/back · left/right arrows change filter", 11, UiKit.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_filter()


func enter() -> void:
	active = true
	visible = true
	_apply_filter()


func exit() -> void:
	if not active:
		return
	active = false
	visible = false
	exited.emit()


func cycle_filter(d: int) -> void:
	filter = (filter + d + FILTERS.size()) % FILTERS.size()
	_apply_filter()
	filter_changed.emit(FILTERS[filter])


func _apply_filter() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("mode", filter)
	_rect.visible = filter != 0
	_filter_label.text = FILTERS[filter]


## Save what the screen shows (filter included, toolbar hidden). Returns the file path, or "" on failure.
func take_photo() -> String:
	_bar.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	_bar.visible = true
	if image == null:
		return ""
	DirAccess.make_dir_recursive_absolute(photo_dir)
	shots += 1
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var path := "%s/willowbrook_%s_%d.png" % [photo_dir, stamp, shots]
	if image.save_png(path) != OK:
		return ""
	captured.emit(path)
	return path
