class_name WorldOverlay
extends Control
## Everything that floats over the 3D world: speech bubbles, emotes, name tags and the plumbob,
## building and construction labels, and progress rings for residents who are inside buildings.

const LABEL_DISTANCE := 62.0
const NAME_DISTANCE := 48.0

var camera: Camera3D
var sim: LifeSim
var art: CityArt
## The room the chief is standing in (null outdoors).
var interior: InteriorView = null
## True while the chief is up a watchtower: monsters are tagged from much further away.
var lookout := false
var selected := 0
var hover_text := ""
var hover_pos := Vector2.ZERO
var show_labels := true

var _font: Font
var _time := 0.0
var _pending: Array = []
var _bubbles: Array = []
var _emotes: Array = []
var _pings: Array = []
var _pill: StyleBoxFlat
var _bubble_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_pill = UiKit.flat(Color(0.05, 0.07, 0.10, 0.84), 10, 0)
	_pill.border_color = Color(1, 1, 1, 0.10)
	_pill.set_border_width_all(1)
	_bubble_style = UiKit.flat(Color(0.97, 0.97, 0.95, 0.98), 12, 0)
	_bubble_style.shadow_color = Color(0, 0, 0, 0.3)
	_bubble_style.shadow_size = 6


## Sim presentation events: {type: say|emote, who, text|kind, delay}.
## Name tags for the people inside and owner tags on the furniture near the chief.
func _draw_interior_tags() -> void:
	var chief_room := interior.to_room(art.chief.position)
	for it in Interiors.furniture_of(interior.building):
		var owners: Array = it.owners
		if owners.is_empty() or str(it.role) in ["rug", "decor", "lamp"]:
			continue
		var anchor := interior.item_anchor(it)
		if not _visible(anchor) or Vector2(float(it.x), float(it.z)).distance_to(chief_room) > 4.2:
			continue
		var label := "%s's %s" % [" & ".join(owners), FurnitureDb.label_of(str(it.model)).to_lower()]
		var p := _proj(anchor)
		var w := _text_width(label, 11) + 14.0
		draw_style_box(_pill, Rect2(p + Vector2(-w * 0.5, -10), Vector2(w, 20)))
		draw_string(_font, p + Vector2(-w * 0.5 + 7, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.ACCENT)
	for i in interior.actor_indices():
		var a := interior.actor_anchor(int(i))
		if a == Vector3.ZERO or not _visible(a):
			continue
		var p2 := _proj(a)
		var name_text := str(sim.residents[int(i)].name)
		var w2 := _text_width(name_text, 13) + 16.0
		draw_style_box(_pill, Rect2(p2 + Vector2(-w2 * 0.5, -16), Vector2(w2, 22)))
		draw_string(_font, p2 + Vector2(-w2 * 0.5 + 8, 0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK)
	var chief_anchor_inside := art.chief_anchor()
	if _visible(chief_anchor_inside):
		var cp := _proj(chief_anchor_inside) + Vector2(0, -2)
		var cw := _text_width("Chief", 12) + 14.0
		draw_style_box(_pill, Rect2(cp + Vector2(-cw * 0.5, -14), Vector2(cw, 20)))
		draw_string(_font, cp + Vector2(-cw * 0.5 + 7, 1), "Chief", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.ACCENT)


func clear_bubbles() -> void:
	_bubbles.clear()


func feed(events: Array) -> void:
	for e in events:
		if e.type == "say" or e.type == "emote":
			_pending.append({"at": _time + float(e.get("delay", 0.0)), "e": e})


## The chief's own words (who = -1), for example a transcription of what you just said.
func chief_say(text: String) -> void:
	_add_bubble(-1, text)


## A bubble that stays up until `release(id)` (used while a voice line is playing).
func say_hold(who: int, text: String, id: int) -> void:
	_add_bubble(who, text, id)


func release(id: int) -> void:
	for b in _bubbles:
		if int(b.hold) == id:
			b.hold = -1
			b.life = (_time - float(b.start)) + 0.9


func ping(world_pos: Vector3) -> void:
	_pings.append({"pos": world_pos, "start": _time})


func _process(dt: float) -> void:
	_time += dt
	for i in range(_pending.size() - 1, -1, -1):
		if _pending[i].at <= _time:
			var e: Dictionary = _pending[i].e
			_pending.remove_at(i)
			if e.type == "say":
				_add_bubble(int(e.who), str(e.text))
			elif e.type == "emote":
				_emotes = _emotes.filter(func(o: Dictionary) -> bool: return o.who != int(e.who))
				_emotes.append({"who": int(e.who), "kind": str(e.kind), "start": _time, "life": 2.6})
	_bubbles = _bubbles.filter(func(b: Dictionary) -> bool: return _time - b.start < b.life)
	_emotes = _emotes.filter(func(o: Dictionary) -> bool: return _time - o.start < o.life)
	_pings = _pings.filter(func(p: Dictionary) -> bool: return _time - p.start < 0.7)
	queue_redraw()


func _add_bubble(who: int, text: String, hold: int = -1) -> void:
	_bubbles = _bubbles.filter(func(b: Dictionary) -> bool: return b.who != who)
	_bubbles.append({"who": who, "text": text, "start": _time, "life": 999.0 if hold >= 0 else 3.2 + minf(4.0, text.length() * 0.045), "hold": hold})


# --- projection helpers ------------------------------------------------------------------------

func _proj(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func _visible(p: Vector3) -> bool:
	return not camera.is_position_behind(p)


func _near(p: Vector3, distance: float) -> bool:
	return camera.global_position.distance_to(p) <= distance


func _anchor_for(who: int) -> Vector3:
	if who < 0:
		return art.chief_anchor()
	if interior != null:
		var inside_anchor := interior.actor_anchor(who)
		if inside_anchor != Vector3.ZERO:
			return inside_anchor
	if who >= sim.residents.size() or who >= art.actors.size():
		return Vector3.ZERO
	var r: Dictionary = sim.residents[who]
	if sim.is_inside(r):
		var place := sim.building_by_id(int(r.target_id))
		if not place.is_empty():
			return art.building_anchor(place)
	return art.head_anchor(who)


func _text_width(text: String, size: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _shadow_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(_font, pos + Vector2(1, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.75))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _pill_at(center: Vector2, text: String, icon: String, tint: Color, size: int = 12, progress: float = -1.0) -> Rect2:
	var tw := _text_width(text, size)
	var icon_w := 20.0 if icon != "" else 0.0
	var w := tw + icon_w + 16.0
	var h := float(size) + 12.0
	var rect := Rect2(center - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_style_box(_pill, rect)
	if progress >= 0.0:
		draw_rect(Rect2(rect.position + Vector2(5, h - 4.5), Vector2((w - 10.0) * clampf(progress, 0.0, 1.0), 2.5)), tint)
	if icon != "":
		Icon.paint(self, icon, Rect2(rect.position + Vector2(6, h * 0.5 - 7), Vector2(14, 14)), tint)
	draw_string(_font, rect.position + Vector2(8.0 + icon_w, h * 0.5 + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiKit.INK)
	return rect


# --- drawing ------------------------------------------------------------------------------------------

func _draw() -> void:
	if camera == null or sim == null or art == null:
		return
	if interior != null:
		_draw_interior_tags()
		_draw_bubbles_and_emotes()
		if hover_text != "":
			var ts_inside := _text_width(hover_text, 13)
			draw_style_box(_pill, Rect2(hover_pos + Vector2(16, 20), Vector2(ts_inside + 18, 26)))
			draw_string(_font, hover_pos + Vector2(25, 38), hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK)
		return
	for ping in _pings:
		var age: float = (_time - ping.start) / 0.7
		if _visible(ping.pos):
			draw_arc(_proj(ping.pos), 8.0 + age * 26.0, 0.0, TAU, 32, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 1.0 - age), 2.5, true)
	if show_labels:
		_draw_building_labels()
	_draw_indoor_markers()
	_draw_name_tags()
	_draw_mobs()
	_draw_bubbles_and_emotes()
	if hover_text != "":
		var ts := _text_width(hover_text, 13)
		var rect := Rect2(hover_pos + Vector2(16, 20), Vector2(ts + 18, 26))
		draw_style_box(_pill, rect)
		draw_string(_font, rect.position + Vector2(9, 18), hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK)


func _draw_building_labels() -> void:
	for b in sim.buildings:
		if Walls.is_wall(b):
			continue
		var anchor := art.building_anchor(b)
		if not _visible(anchor) or not _near(anchor, LABEL_DISTANCE):
			continue
		var p := _proj(anchor)
		var kind: String = b.kind
		var working := int(b.target) > int(b.level)
		if working:
			var verb := "Building" if int(b.level) == 0 else "Upgrading"
			_pill_at(p, "%s  %d%%" % [verb, int(float(b.progress))], "build", UiKit.ACCENT, 12, float(b.progress) / 100.0)
			continue
		var rect := _pill_at(p, Catalog.label(kind), "", UiKit.INK, 12)
		var max_level := Catalog.max_level(kind)
		if max_level > 1:
			var pips := mini(max_level, 5)
			var start_x := p.x - (pips - 1) * 6.0
			for k in range(pips):
				var col := UiKit.ACCENT if k < int(b.level) else Color(1, 1, 1, 0.22)
				draw_circle(Vector2(start_x + k * 12.0, rect.end.y + 7.0), 3.2, col)


func _draw_indoor_markers() -> void:
	var groups := {}
	for i in range(mini(sim.residents.size(), art.actors.size())):
		var r: Dictionary = sim.residents[i]
		if sim.is_inside(r):
			var id := int(r.target_id)
			if not groups.has(id):
				groups[id] = []
			groups[id].append(i)
	for id in groups:
		var place := sim.building_by_id(int(id))
		if place.is_empty():
			continue
		var anchor := art.building_anchor(place)
		if not _visible(anchor) or not _near(anchor, LABEL_DISTANCE):
			continue
		var base := _proj(anchor) + Vector2(0, -34)
		var members: Array = groups[id]
		for k in range(mini(members.size(), 4)):
			var i: int = members[k]
			var r: Dictionary = sim.residents[i]
			var c := base + Vector2((k - (mini(members.size(), 4) - 1) * 0.5) * 42.0, 0)
			var hot := i == selected
			draw_circle(c + Vector2(0, 2), 17.0, Color(0, 0, 0, 0.35))
			draw_circle(c, 16.0, Color(0.06, 0.08, 0.11, 0.94))
			draw_arc(c, 16.0, -PI / 2.0, -PI / 2.0 + TAU * sim.activity_progress(r), 32, UiKit.ACCENT if hot else UiKit.GOOD, 3.0, true)
			Icon.paint(self, str(r.action), Rect2(c - Vector2(8, 8), Vector2(16, 16)), UiKit.INK)
			if hot or members.size() == 1:
				var name_w := _text_width(r.name, 11)
				_shadow_text(c + Vector2(-name_w * 0.5, 29), str(r.name), 11, UiKit.ACCENT if hot else UiKit.INK)
		if members.size() > 4:
			_shadow_text(base + Vector2(84, 4), "+%d" % (members.size() - 4), 12, UiKit.INK)


func _draw_name_tags() -> void:
	for i in range(mini(sim.residents.size(), art.actors.size())):
		var r: Dictionary = sim.residents[i]
		if sim.is_inside(r):
			continue
		var hot := i == selected
		var anchor := art.head_anchor(i)
		if not _visible(anchor) or (not hot and not _near(anchor, NAME_DISTANCE)):
			continue
		var p := _proj(anchor) + Vector2(0, -4)
		var name_w := _text_width(r.name, 13 if hot else 12)
		var emo := sim.emotion(r)
		var col: Color = UiKit.EMOTION_COLOR.get(emo, UiKit.INK)
		var total := name_w + 18.0
		var x := p.x - total * 0.5
		Icon.paint(self, emo, Rect2(Vector2(x, p.y - 12), Vector2(14, 14)), col)
		_shadow_text(Vector2(x + 18, p.y), str(r.name), 13 if hot else 12, UiKit.ACCENT if hot else UiKit.INK)
		if hot:
			var bob := sin(_time * 3.0) * 3.0
			var d := Vector2(p.x, p.y - 30.0 + bob)
			draw_colored_polygon(PackedVector2Array([d + Vector2(0, -11), d + Vector2(7, 0), d + Vector2(0, 11), d + Vector2(-7, 0)]), UiKit.ACCENT)
			draw_polyline(PackedVector2Array([d + Vector2(0, -11), d + Vector2(7, 0), d + Vector2(0, 11), d + Vector2(-7, 0), d + Vector2(0, -11)]), Color(1, 1, 1, 0.55), 1.5, true)
		if float(r.get("down_until", 0.0)) > sim.minutes:
			_pill_at(Vector2(p.x, p.y - 30.0), "Knocked out", "", UiKit.BAD, 11)
		if not sim.advice.is_empty() and int(sim.advice.resident) == i and str(sim.advice.state) == "waiting":
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			var bp := Vector2(p.x, p.y - 46.0 - pulse * 4.0)
			draw_circle(bp, 13.0 + pulse * 2.0, Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.35))
			draw_circle(bp, 11.0, UiKit.ACCENT)
			draw_string(_font, bp + Vector2(-3.5, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.1, 0.08, 0.04))
	var chief_anchor := art.chief_anchor()
	if _visible(chief_anchor):
		var ap := _proj(chief_anchor) + Vector2(0, -2)
		var tag_w := _text_width("Chief", 12) + 14.0
		draw_style_box(_pill, Rect2(ap + Vector2(-tag_w * 0.5, -14), Vector2(tag_w, 20)))
		draw_string(_font, ap + Vector2(-tag_w * 0.5 + 7, 1), "Chief", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.ACCENT)


func _draw_mobs() -> void:
	for m in sim.mobs:
		var anchor := art.mob_anchor(int(m.id))
		if anchor == Vector3.ZERO or not _visible(anchor) or not _near(anchor, 190.0 if lookout else 70.0):
			continue
		var p := _proj(anchor)
		var label: String = str(Survival.KINDS[str(m.kind)].label)
		var w := _text_width(label, 12) + 16.0
		draw_style_box(_pill, Rect2(p + Vector2(-w * 0.5, -22), Vector2(w, 20)))
		draw_string(_font, p + Vector2(-w * 0.5 + 8, -7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.BAD)
		var frac := clampf(float(m.hp) / float(m.max_hp), 0.0, 1.0)
		draw_rect(Rect2(p + Vector2(-24, 2), Vector2(48, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-23, 3), Vector2(46.0 * frac, 3)), UiKit.BAD.lerp(UiKit.GOOD, frac))


func _draw_bubbles_and_emotes() -> void:
	var bubble_tops := {}
	for b in _bubbles:
		var world := _anchor_for(int(b.who))
		if world == Vector3.ZERO or not _visible(world):
			continue
		var age: float = _time - b.start
		var appear := clampf(age * 7.0, 0.0, 1.0)
		var fade := clampf((b.life - age) * 3.0, 0.0, 1.0)
		var anchor := _proj(world) + Vector2(0, -34)
		var max_w := 230.0
		var wrapped := _font.get_multiline_string_size(str(b.text), HORIZONTAL_ALIGNMENT_LEFT, max_w, 14)
		var box_size := wrapped + Vector2(22, 16)
		var top_left := anchor + Vector2(-box_size.x * 0.5, -box_size.y - 10.0 * appear)
		var rect := Rect2(top_left, box_size)
		bubble_tops[b.who] = rect.position.y
		var modulate_a := appear * fade
		draw_set_transform(rect.get_center(), 0.0, Vector2.ONE * (0.85 + 0.15 * appear))
		var local := Rect2(-box_size * 0.5, box_size)
		var style := _bubble_style.duplicate() as StyleBoxFlat
		style.bg_color.a *= modulate_a
		style.shadow_color.a *= modulate_a
		draw_style_box(style, local)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, box_size.y * 0.5 - 1), Vector2(7, box_size.y * 0.5 - 1), Vector2(0, box_size.y * 0.5 + 9)]), Color(0.97, 0.97, 0.95, 0.98 * modulate_a))
		draw_multiline_string(_font, local.position + Vector2(11, 8 + _font.get_ascent(14)), str(b.text), HORIZONTAL_ALIGNMENT_LEFT, max_w, 14, -1, Color(0.12, 0.14, 0.17, modulate_a))
		if int(b.hold) >= 0:
			# A little speaker mark while the voice line is playing.
			var wave := 1.0 + sin(_time * 12.0) * 0.25
			draw_arc(local.position + Vector2(box_size.x - 12, 12), 4.0 * wave, -0.9, 0.9, 8, Color(0.2, 0.5, 0.75, modulate_a), 1.6, true)
			draw_arc(local.position + Vector2(box_size.x - 12, 12), 8.0 * wave, -0.9, 0.9, 8, Color(0.2, 0.5, 0.75, modulate_a * 0.7), 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for e in _emotes:
		var world := _anchor_for(int(e.who))
		if world == Vector3.ZERO or not _visible(world):
			continue
		var age: float = _time - e.start
		var pop := clampf(age * 6.0, 0.0, 1.0)
		var scale_ := 1.0 + sin(pop * PI) * 0.35 if age < 0.2 else 1.0
		var fade := clampf((e.life - age) * 2.5, 0.0, 1.0)
		var anchor := _proj(world)
		var rise := age * 6.0
		var c := Vector2(anchor.x, anchor.y - 40.0 - rise)
		if bubble_tops.has(e.who):
			c = Vector2(anchor.x + 34.0, float(bubble_tops[e.who]) - 4.0 - rise)
		var tint := _emote_color(str(e.kind))
		draw_circle(c, 17.0 * scale_, Color(0.05, 0.07, 0.10, 0.92 * fade))
		draw_arc(c, 17.0 * scale_, 0.0, TAU, 28, Color(tint.r, tint.g, tint.b, fade), 2.0, true)
		Icon.paint(self, str(e.kind), Rect2(c - Vector2(10, 10) * scale_, Vector2(20, 20) * scale_), Color(tint.r, tint.g, tint.b, fade))


func _emote_color(kind: String) -> Color:
	match kind:
		"heart": return UiKit.SOCIAL
		"anger": return UiKit.BAD
		"laugh": return UiKit.ACCENT
		"star": return Color("ffd45e")
		"speech": return Color("bfe3f2")
		"tired", "zzz": return Color("8aa0e8")
		"sweat": return Color("7bd0e8")
		"happy": return UiKit.GOOD
	return UiKit.INK
