class_name Icon
extends Control
## Vector icons drawn in code (no font or image assets). Use Icon.paint() from any CanvasItem
## or drop an Icon control into a container.

const PANEL_BG := Color(0.07, 0.09, 0.12, 1.0)

@export var kind := "star"
@export var tint := Color("e9eeea")


func _init(kind_: String = "star", tint_: Color = Color("e9eeea"), size_: float = 20.0) -> void:
	kind = kind_
	tint = tint_
	custom_minimum_size = Vector2(size_, size_)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(kind_: String, tint_: Color = Color(0, 0, 0, 0)) -> void:
	kind = kind_
	if tint_.a > 0.0:
		tint = tint_
	queue_redraw()


func _draw() -> void:
	paint(self, kind, Rect2(Vector2.ZERO, size), tint)


# --- drawing helpers (unit square coordinates) -----------------------------------

static func _v(o: Vector2, s: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * s


static func _poly(ci: CanvasItem, o: Vector2, s: float, col: Color, pts: Array) -> void:
	var points := PackedVector2Array()
	for i in range(0, pts.size(), 2):
		points.append(_v(o, s, pts[i], pts[i + 1]))
	ci.draw_colored_polygon(points, col)


static func _line(ci: CanvasItem, o: Vector2, s: float, col: Color, x1: float, y1: float, x2: float, y2: float, w: float = 0.08) -> void:
	ci.draw_line(_v(o, s, x1, y1), _v(o, s, x2, y2), col, maxf(1.0, w * s), true)


static func _disc(ci: CanvasItem, o: Vector2, s: float, col: Color, x: float, y: float, rad: float) -> void:
	ci.draw_circle(_v(o, s, x, y), rad * s, col)


static func _ring(ci: CanvasItem, o: Vector2, s: float, col: Color, x: float, y: float, rad: float, w: float = 0.07, from: float = 0.0, to: float = TAU) -> void:
	ci.draw_arc(_v(o, s, x, y), rad * s, from, to, 28, col, maxf(1.0, w * s), true)


static func _rect(ci: CanvasItem, o: Vector2, s: float, col: Color, x: float, y: float, w: float, h: float) -> void:
	ci.draw_rect(Rect2(_v(o, s, x, y), Vector2(w, h) * s), col)


static func _arc_poly(ci: CanvasItem, o: Vector2, s: float, col: Color, cx: float, cy: float, rad: float, a0: float, a1: float) -> void:
	if rad * s < 1.0 or absf(a1 - a0) < 0.05:
		return
	var points := PackedVector2Array()
	points.append(_v(o, s, cx, cy))
	for k in range(17):
		var a := lerpf(a0, a1, k / 16.0)
		points.append(_v(o, s, cx + cos(a) * rad, cy + sin(a) * rad))
	ci.draw_colored_polygon(points, col)


static func _star(ci: CanvasItem, o: Vector2, s: float, col: Color, cx: float, cy: float, outer: float, inner: float) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var a := -PI / 2.0 + i * PI / 5.0
		var rad := outer if i % 2 == 0 else inner
		points.append(_v(o, s, cx + cos(a) * rad, cy + sin(a) * rad))
	ci.draw_colored_polygon(points, col)


static func _cloud(ci: CanvasItem, o: Vector2, s: float, col: Color, dy: float = 0.0) -> void:
	_disc(ci, o, s, col, 0.32, 0.5 + dy, 0.2)
	_disc(ci, o, s, col, 0.55, 0.4 + dy, 0.26)
	_disc(ci, o, s, col, 0.74, 0.55 + dy, 0.17)
	_rect(ci, o, s, col, 0.32, 0.5 + dy, 0.42, 0.22)


static func paint(ci: CanvasItem, kind_: String, r: Rect2, col: Color) -> void:
	if not is_finite(r.position.x) or not is_finite(r.position.y) or not is_finite(r.size.x) or r.size.x < 2.0 or r.size.y < 2.0:
		return
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var dark := col.darkened(0.45)
	match kind_:
		"hunger", "hungry", "produce_apple":
			_disc(ci, o, s, col, 0.5, 0.6, 0.3)
			_line(ci, o, s, col, 0.5, 0.3, 0.56, 0.1, 0.07)
			_poly(ci, o, s, col.lightened(0.15), [0.56, 0.2, 0.82, 0.08, 0.72, 0.32])
		"energy":
			_poly(ci, o, s, col, [0.6, 0.04, 0.2, 0.56, 0.46, 0.56, 0.38, 0.96, 0.8, 0.4, 0.54, 0.4])
		"hygiene", "sweat":
			_disc(ci, o, s, col, 0.5, 0.62, 0.27)
			_poly(ci, o, s, col, [0.5, 0.05, 0.26, 0.5, 0.74, 0.5])
			_disc(ci, o, s, Color(1, 1, 1, 0.35), 0.4, 0.58, 0.07)
		"social", "people":
			_disc(ci, o, s, col, 0.32, 0.32, 0.16)
			_disc(ci, o, s, col.lightened(0.15), 0.68, 0.34, 0.15)
			_poly(ci, o, s, col, [0.08, 0.92, 0.12, 0.66, 0.24, 0.55, 0.42, 0.55, 0.54, 0.66, 0.58, 0.92])
			_poly(ci, o, s, col.lightened(0.15), [0.5, 0.92, 0.55, 0.68, 0.64, 0.58, 0.8, 0.58, 0.92, 0.68, 0.94, 0.92])
		"fun", "star":
			_star(ci, o, s, col, 0.5, 0.54, 0.46, 0.2)
		"health", "heart":
			_disc(ci, o, s, col, 0.33, 0.36, 0.21)
			_disc(ci, o, s, col, 0.67, 0.36, 0.21)
			_poly(ci, o, s, col, [0.14, 0.46, 0.86, 0.46, 0.5, 0.88])
		"coin":
			_disc(ci, o, s, col, 0.5, 0.5, 0.42)
			_ring(ci, o, s, dark, 0.5, 0.5, 0.29, 0.06)
			_line(ci, o, s, dark, 0.5, 0.32, 0.5, 0.68, 0.07)
		"treat":
			_rect(ci, o, s, col, 0.38, 0.1, 0.24, 0.8)
			_rect(ci, o, s, col, 0.1, 0.38, 0.8, 0.24)
		"guard":
			_poly(ci, o, s, col, [0.5, 0.06, 0.88, 0.2, 0.84, 0.58, 0.5, 0.94, 0.16, 0.58, 0.12, 0.2])
			_line(ci, o, s, dark, 0.5, 0.24, 0.5, 0.7, 0.07)
		"chop":
			_line(ci, o, s, col.darkened(0.25), 0.24, 0.9, 0.7, 0.22, 0.09)
			_poly(ci, o, s, col, [0.5, 0.14, 0.86, 0.1, 0.88, 0.46, 0.62, 0.4])
		"mine":
			_line(ci, o, s, col.darkened(0.25), 0.22, 0.92, 0.66, 0.34, 0.09)
			_ring(ci, o, s, col, 0.5, 0.64, 0.42, 0.09, PI * 1.05, PI * 1.95)
		"water":
			_poly(ci, o, s, col, [0.5, 0.06, 0.78, 0.55, 0.22, 0.55])
			_disc(ci, o, s, col, 0.5, 0.62, 0.28)
		"wood":
			_rect(ci, o, s, col.darkened(0.2), 0.12, 0.3, 0.7, 0.4)
			_disc(ci, o, s, col, 0.2, 0.5, 0.2)
			_ring(ci, o, s, dark, 0.2, 0.5, 0.11, 0.05)
		"produce", "gather":
			_disc(ci, o, s, col.lightened(0.2), 0.38, 0.42, 0.14)
			_disc(ci, o, s, col.lightened(0.1), 0.62, 0.4, 0.14)
			_ring(ci, o, s, col, 0.5, 0.52, 0.32, 0.06, PI, TAU)
			_poly(ci, o, s, col, [0.12, 0.5, 0.88, 0.5, 0.76, 0.92, 0.24, 0.92])
		"meal", "cook":
			_arc_poly(ci, o, s, col, 0.5, 0.45, 0.42, 0.0, PI)
			_line(ci, o, s, col, 0.38, 0.12, 0.42, 0.3, 0.06)
			_line(ci, o, s, col, 0.56, 0.08, 0.6, 0.3, 0.06)
			if kind_ == "cook":
				_line(ci, o, s, col, 0.04, 0.45, 0.14, 0.45, 0.07)
				_line(ci, o, s, col, 0.86, 0.45, 0.96, 0.45, 0.07)
		"anger":
			_ring(ci, o, s, col, 0.5, 0.5, 0.42, 0.07)
			_line(ci, o, s, col, 0.24, 0.3, 0.44, 0.42, 0.09)
			_line(ci, o, s, col, 0.76, 0.3, 0.56, 0.42, 0.09)
			_disc(ci, o, s, col, 0.36, 0.5, 0.055)
			_disc(ci, o, s, col, 0.64, 0.5, 0.055)
			_ring(ci, o, s, col, 0.5, 0.82, 0.17, 0.07, 1.15 * PI, 1.85 * PI)
		"laugh", "happy", "smile":
			_ring(ci, o, s, col, 0.5, 0.5, 0.42, 0.07)
			_disc(ci, o, s, col, 0.36, 0.4, 0.06)
			_disc(ci, o, s, col, 0.64, 0.4, 0.06)
			_arc_poly(ci, o, s, col, 0.5, 0.52, 0.24, 0.1 * PI, 0.9 * PI)
		"speech", "talk":
			_poly(ci, o, s, col, [0.1, 0.12, 0.9, 0.12, 0.9, 0.66, 0.1, 0.66])
			_poly(ci, o, s, col, [0.26, 0.64, 0.2, 0.92, 0.52, 0.64])
			for x in [0.3, 0.5, 0.7]:
				_disc(ci, o, s, Color(0, 0, 0, 0.4), x, 0.39, 0.055)
		"zzz", "tired", "sleep_z":
			_line(ci, o, s, col, 0.1, 0.12, 0.5, 0.12, 0.09)
			_line(ci, o, s, col, 0.5, 0.12, 0.1, 0.5, 0.09)
			_line(ci, o, s, col, 0.1, 0.5, 0.5, 0.5, 0.09)
			_line(ci, o, s, col, 0.58, 0.5, 0.9, 0.5, 0.08)
			_line(ci, o, s, col, 0.9, 0.5, 0.58, 0.82, 0.08)
			_line(ci, o, s, col, 0.58, 0.82, 0.9, 0.82, 0.08)
		"lonely":
			_disc(ci, o, s, col, 0.5, 0.3, 0.17)
			_poly(ci, o, s, col, [0.2, 0.92, 0.26, 0.6, 0.4, 0.5, 0.6, 0.5, 0.74, 0.6, 0.8, 0.92])
		"dirty":
			_disc(ci, o, s, col, 0.3, 0.6, 0.2)
			_disc(ci, o, s, col, 0.6, 0.5, 0.25)
			_disc(ci, o, s, col, 0.74, 0.7, 0.15)
		"bored":
			for x in [0.2, 0.5, 0.8]:
				_disc(ci, o, s, col, x, 0.5, 0.1)
		"sick", "plus":
			_poly(ci, o, s, col, [0.38, 0.1, 0.62, 0.1, 0.62, 0.38, 0.9, 0.38, 0.9, 0.62, 0.62, 0.62, 0.62, 0.9, 0.38, 0.9, 0.38, 0.62, 0.1, 0.62, 0.1, 0.38, 0.38, 0.38])
		"gloomy":
			_ring(ci, o, s, col, 0.5, 0.5, 0.42, 0.07)
			_disc(ci, o, s, col, 0.36, 0.4, 0.06)
			_disc(ci, o, s, col, 0.64, 0.4, 0.06)
			_ring(ci, o, s, col, 0.5, 0.78, 0.2, 0.07, 1.15 * PI, 1.85 * PI)
		"content":
			_ring(ci, o, s, col, 0.5, 0.5, 0.42, 0.07)
			_disc(ci, o, s, col, 0.36, 0.4, 0.06)
			_disc(ci, o, s, col, 0.64, 0.4, 0.06)
			_line(ci, o, s, col, 0.34, 0.66, 0.66, 0.66, 0.07)
		"pause":
			_rect(ci, o, s, col, 0.24, 0.16, 0.18, 0.68)
			_rect(ci, o, s, col, 0.58, 0.16, 0.18, 0.68)
		"play_arrow":
			_poly(ci, o, s, col, [0.26, 0.14, 0.88, 0.5, 0.26, 0.86])
		"fast":
			_poly(ci, o, s, col, [0.12, 0.2, 0.52, 0.5, 0.12, 0.8])
			_poly(ci, o, s, col, [0.5, 0.2, 0.9, 0.5, 0.5, 0.8])
		"faster":
			_poly(ci, o, s, col, [0.02, 0.24, 0.34, 0.5, 0.02, 0.76])
			_poly(ci, o, s, col, [0.34, 0.24, 0.66, 0.5, 0.34, 0.76])
			_poly(ci, o, s, col, [0.66, 0.24, 0.98, 0.5, 0.66, 0.76])
		"menu":
			for y in [0.24, 0.5, 0.76]:
				_line(ci, o, s, col, 0.14, y, 0.86, y, 0.09)
		"close", "x":
			_line(ci, o, s, col, 0.2, 0.2, 0.8, 0.8, 0.1)
			_line(ci, o, s, col, 0.8, 0.2, 0.2, 0.8, 0.1)
		"check":
			_line(ci, o, s, col, 0.14, 0.54, 0.4, 0.78, 0.11)
			_line(ci, o, s, col, 0.4, 0.78, 0.88, 0.24, 0.11)
		"chevron_right":
			_line(ci, o, s, col, 0.34, 0.16, 0.7, 0.5, 0.1)
			_line(ci, o, s, col, 0.7, 0.5, 0.34, 0.84, 0.1)
		"chevron_left":
			_line(ci, o, s, col, 0.66, 0.16, 0.3, 0.5, 0.1)
			_line(ci, o, s, col, 0.3, 0.5, 0.66, 0.84, 0.1)
		"arrow_up", "upgrade":
			_poly(ci, o, s, col, [0.5, 0.08, 0.88, 0.48, 0.62, 0.48, 0.62, 0.92, 0.38, 0.92, 0.38, 0.48, 0.12, 0.48])
		"clock":
			_ring(ci, o, s, col, 0.5, 0.5, 0.4, 0.07)
			_line(ci, o, s, col, 0.5, 0.5, 0.5, 0.26, 0.07)
			_line(ci, o, s, col, 0.5, 0.5, 0.68, 0.58, 0.07)
		"sun":
			_disc(ci, o, s, col, 0.5, 0.5, 0.22)
			for k in range(8):
				var a := k * PI / 4.0
				_line(ci, o, s, col, 0.5 + cos(a) * 0.32, 0.5 + sin(a) * 0.32, 0.5 + cos(a) * 0.46, 0.5 + sin(a) * 0.46, 0.07)
		"cloud":
			_cloud(ci, o, s, col)
		"rain":
			_cloud(ci, o, s, col, -0.12)
			for x in [0.3, 0.5, 0.7]:
				_line(ci, o, s, col.lightened(0.2), x, 0.72, x - 0.06, 0.92, 0.06)
		"snow":
			for k in range(3):
				var a := k * PI / 3.0
				_line(ci, o, s, col, 0.5 + cos(a) * 0.42, 0.5 + sin(a) * 0.42, 0.5 - cos(a) * 0.42, 0.5 - sin(a) * 0.42, 0.07)
		"work", "build", "hammer":
			_line(ci, o, s, col.darkened(0.2), 0.22, 0.86, 0.62, 0.44, 0.11)
			_poly(ci, o, s, col, [0.5, 0.12, 0.88, 0.32, 0.78, 0.5, 0.4, 0.3])
		"eat":
			_line(ci, o, s, col, 0.3, 0.1, 0.3, 0.92, 0.08)
			for x in [0.16, 0.3, 0.44]:
				_line(ci, o, s, col, x, 0.1, x, 0.4, 0.06)
			_line(ci, o, s, col, 0.7, 0.1, 0.7, 0.92, 0.08)
			_poly(ci, o, s, col, [0.62, 0.1, 0.82, 0.1, 0.82, 0.5, 0.62, 0.5])
		"sleep", "moon":
			_disc(ci, o, s, col, 0.5, 0.5, 0.4)
			_disc(ci, o, s, PANEL_BG, 0.66, 0.4, 0.34)
		"wash":
			_disc(ci, o, s, col, 0.5, 0.62, 0.27)
			_poly(ci, o, s, col, [0.5, 0.05, 0.26, 0.5, 0.74, 0.5])
		"socialize":
			paint(ci, "social", r, col)
		"play":
			_ring(ci, o, s, col, 0.5, 0.5, 0.4, 0.07)
			_ring(ci, o, s, col, 0.1, 0.5, 0.4, 0.06, -0.4, 0.4)
			_ring(ci, o, s, col, 0.9, 0.5, 0.4, 0.06, PI - 0.4, PI + 0.4)
			_line(ci, o, s, col, 0.1, 0.5, 0.9, 0.5, 0.05)
		"study", "book":
			_poly(ci, o, s, col, [0.1, 0.2, 0.46, 0.28, 0.46, 0.86, 0.1, 0.78])
			_poly(ci, o, s, col.lightened(0.15), [0.9, 0.2, 0.54, 0.28, 0.54, 0.86, 0.9, 0.78])
		"farm", "sprout":
			_line(ci, o, s, col, 0.5, 0.92, 0.5, 0.4, 0.08)
			_poly(ci, o, s, col, [0.5, 0.5, 0.12, 0.42, 0.2, 0.18, 0.5, 0.36])
			_poly(ci, o, s, col.lightened(0.15), [0.5, 0.4, 0.88, 0.28, 0.8, 0.06, 0.5, 0.24])
		"exercise", "dumbbell":
			_line(ci, o, s, col, 0.25, 0.5, 0.75, 0.5, 0.1)
			_rect(ci, o, s, col, 0.1, 0.28, 0.14, 0.44)
			_rect(ci, o, s, col, 0.76, 0.28, 0.14, 0.44)
			_rect(ci, o, s, col, 0.0, 0.38, 0.1, 0.24)
			_rect(ci, o, s, col, 0.9, 0.38, 0.1, 0.24)
		"rest", "sofa":
			_rect(ci, o, s, col, 0.2, 0.3, 0.6, 0.3)
			_rect(ci, o, s, col, 0.06, 0.44, 0.18, 0.34)
			_rect(ci, o, s, col, 0.76, 0.44, 0.18, 0.34)
			_rect(ci, o, s, col, 0.16, 0.56, 0.68, 0.22)
		"home", "town":
			_poly(ci, o, s, col, [0.5, 0.1, 0.92, 0.48, 0.8, 0.48, 0.8, 0.88, 0.2, 0.88, 0.2, 0.48, 0.08, 0.48])
			_rect(ci, o, s, PANEL_BG, 0.43, 0.6, 0.14, 0.28)
		"skills", "bars":
			_rect(ci, o, s, col, 0.14, 0.52, 0.18, 0.4)
			_rect(ci, o, s, col, 0.41, 0.3, 0.18, 0.62)
			_rect(ci, o, s, col, 0.68, 0.1, 0.18, 0.82)
		"mind", "bulb":
			_disc(ci, o, s, col, 0.5, 0.38, 0.28)
			_rect(ci, o, s, col, 0.38, 0.62, 0.24, 0.2)
			_line(ci, o, s, col, 0.4, 0.9, 0.6, 0.9, 0.07)
		"log", "list":
			for y in [0.24, 0.5, 0.76]:
				_disc(ci, o, s, col, 0.16, y, 0.06)
				_line(ci, o, s, col, 0.3, y, 0.9, y, 0.07)
		"lock":
			_rect(ci, o, s, col, 0.2, 0.46, 0.6, 0.42)
			_ring(ci, o, s, col, 0.5, 0.46, 0.22, 0.08, PI, TAU)
		"gift":
			_rect(ci, o, s, col, 0.14, 0.4, 0.72, 0.5)
			_rect(ci, o, s, col.lightened(0.25), 0.44, 0.4, 0.12, 0.5)
			_rect(ci, o, s, col.darkened(0.1), 0.1, 0.28, 0.8, 0.16)
			_ring(ci, o, s, col, 0.36, 0.2, 0.12, 0.06)
			_ring(ci, o, s, col, 0.64, 0.2, 0.12, 0.06)
		"follow", "eye":
			var lens: Array = []
			for k in range(13):
				var u := k / 12.0
				lens.append_array([0.05 + 0.9 * u, 0.5 - 0.3 * sin(PI * u)])
			for k in range(12, -1, -1):
				var u := k / 12.0
				lens.append_array([0.05 + 0.9 * u, 0.5 + 0.3 * sin(PI * u)])
			_poly(ci, o, s, col, lens)
			_disc(ci, o, s, PANEL_BG, 0.5, 0.5, 0.18)
			_disc(ci, o, s, col, 0.5, 0.5, 0.09)
		"plumbob":
			_poly(ci, o, s, col, [0.5, 0.02, 0.84, 0.4, 0.5, 0.98, 0.16, 0.4])
		"mic":
			_rect(ci, o, s, col, 0.38, 0.16, 0.24, 0.36)
			_disc(ci, o, s, col, 0.5, 0.16, 0.12)
			_disc(ci, o, s, col, 0.5, 0.52, 0.12)
			_ring(ci, o, s, col, 0.5, 0.48, 0.27, 0.07, 0.0, PI)
			_line(ci, o, s, col, 0.5, 0.75, 0.5, 0.9, 0.07)
			_line(ci, o, s, col, 0.34, 0.9, 0.66, 0.9, 0.07)
		"speaker":
			_poly(ci, o, s, col, [0.08, 0.4, 0.28, 0.4, 0.5, 0.2, 0.5, 0.8, 0.28, 0.6, 0.08, 0.6])
			_ring(ci, o, s, col, 0.5, 0.5, 0.22, 0.07, -0.8, 0.8)
			_ring(ci, o, s, col, 0.5, 0.5, 0.38, 0.07, -0.8, 0.8)
		"mute":
			_poly(ci, o, s, col, [0.08, 0.4, 0.28, 0.4, 0.5, 0.2, 0.5, 0.8, 0.28, 0.6, 0.08, 0.6])
			_line(ci, o, s, col, 0.62, 0.36, 0.9, 0.64, 0.08)
			_line(ci, o, s, col, 0.9, 0.36, 0.62, 0.64, 0.08)
		_:
			_disc(ci, o, s, col, 0.5, 0.5, 0.3)
