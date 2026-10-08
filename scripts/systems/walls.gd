class_name Walls
extends RefCounted
## Walls and gates along the village border. A wall is a building whose "edge" is one side of a claimed
## district that faces unclaimed land; gates are walls with an opening in the middle. Walls stop monsters
## (they claw at them until they breach), gates let residents and open-gate traffic through, and all of it
## wears down and needs repair like any other building. Tile units throughout: tile centres are integers,
## so a district boundary lies half a tile outside its first tile.

const SIDES := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const SIDE_NAMES := ["west", "east", "north", "south"]
const GATE_HALF := 1.0
const OVERRIDE_MINUTES := 480.0
const SIEGE_RATE := {"zombie": 2.2, "slime": 0.8, "wolf": 1.0}


static func is_wall(b: Dictionary) -> bool:
	return str(b.get("kind", "")) in Catalog.WALL_KINDS


static func edge(b: Dictionary) -> Dictionary:
	var e: Array = b.edge
	return {"d": Vector2i(int(e[0]), int(e[1])), "side": int(e[2])}


static func intact(b: Dictionary) -> bool:
	return int(b.level) >= 1 and not bool(b.get("breached", false))


static func find(sim: LifeSim, d: Vector2i, side: int) -> Dictionary:
	for b in sim.buildings:
		if is_wall(b) and b.has("edge") and int(b.edge[0]) == d.x and int(b.edge[1]) == d.y and int(b.edge[2]) == side:
			return b
	return {}


## Where the wall line lies, in tile units. The roads along a district's east and south sides are tiles of the
## neighbouring district, so those walls stand one tile further out than the district boundary.
static func line(d: Vector2i, side: int) -> float:
	match side:
		0: return d.x * 4 - 0.5
		1: return (d.x + 1) * 4 + 0.5
		2: return d.y * 4 - 0.5
	return (d.y + 1) * 4 + 0.5


## Middle of the edge, on the wall line.
static func mid(d: Vector2i, side: int) -> Vector2:
	if side < 2:
		return Vector2(line(d, side), d.y * 4 + 2.0)
	return Vector2(d.x * 4 + 2.0, line(d, side))


static func outward(side: int) -> Vector2:
	return Vector2(SIDES[side])


static func gate_points(w: Dictionary) -> Dictionary:
	var e := edge(w)
	var m := mid(e.d, e.side)
	var out := outward(e.side)
	return {"inner": m - out * 0.9, "outer": m + out * 1.3, "mid": m}


## Edges of claimed districts that face unclaimed land.
static func perimeter(sim: LifeSim) -> Array:
	var out: Array = []
	for d in sim.map.claimed:
		for i in range(4):
			if not sim.map.claimed.has(d + SIDES[i]):
				out.append({"d": d, "side": i})
	return out


# --- collision -----------------------------------------------------------------------------------------------

## The wall (if any) that the straight step from `a` to `b` would have to pass through.
static func blocks(sim: LifeSim, a: Vector2, b: Vector2) -> Dictionary:
	for w in sim.buildings:
		if not is_wall(w) or not w.has("edge") or not intact(w):
			continue
		var e := edge(w)
		var l := line(e.d, e.side)
		var m := mid(e.d, e.side)
		var along_y: bool = e.side < 2
		var pa: float = a.x if along_y else a.y
		var pb: float = b.x if along_y else b.y
		if (pa - l) * (pb - l) >= 0.0:
			continue
		var t := (l - pa) / (pb - pa)
		var cross: float = (a.y + t * (b.y - a.y)) if along_y else (a.x + t * (b.x - a.x))
		var centre: float = m.y if along_y else m.x
		if absf(cross - centre) > 2.5:
			continue
		if str(w.kind) == "gate" and bool(w.get("open", true)) and absf(cross - centre) <= GATE_HALF:
			continue
		return w
	return {}


## First wall on the straight line between two points.
static func crossing(sim: LifeSim, a: Vector2, b: Vector2) -> Dictionary:
	return blocks(sim, a, b)


static func gates(sim: LifeSim, open_only: bool = false) -> Array:
	var out: Array = []
	for b in sim.buildings:
		if str(b.kind) == "gate" and intact(b) and (not open_only or bool(b.get("open", true))):
			out.append(b)
	return out


static func nearest_gate(sim: LifeSim, from: Vector2, open_only: bool = false) -> Dictionary:
	var best := {}
	var best_d := 1.0e9
	for g in gates(sim, open_only):
		var d := from.distance_to(gate_points(g).mid)
		if d < best_d:
			best_d = d
			best = g
	return best


## Can a resident walk between these points, using a gate if a wall is in the way?
static func accessible(sim: LifeSim, a: Vector2, b: Vector2) -> bool:
	if crossing(sim, a, b).is_empty():
		return true
	return not nearest_gate(sim, a).is_empty()


# --- building ------------------------------------------------------------------------------------------------------

static func label_for(d: Vector2i, side: int) -> String:
	return "%s edge of district (%d, %d)" % [SIDE_NAMES[side], d.x, d.y]


## Edges that should hold gates: one on each side that has none yet, the edge nearest the village's middle line.
static func designated_gates(sim: LifeSim) -> Dictionary:
	var centre := Survival.village_centre(sim)
	var have := {}
	for g in gates(sim):
		have[int(g.edge[2])] = true
	var out := {}
	for side in range(4):
		if have.has(side):
			continue
		var best := {}
		var best_d := 1.0e9
		for e in perimeter(sim):
			if int(e.side) != side:
				continue
			var m := mid(e.d, side)
			var d: float = absf(m.y - centre.y) if side < 2 else absf(m.x - centre.x)
			if d < best_d:
				best_d = d
				best = e
		if not best.is_empty():
			out["%d,%d,%d" % [best.d.x, best.d.y, side]] = true
	return out


## Edges that still need a wall, with whether each should be a gate. Nearest the middle first.
static func missing(sim: LifeSim) -> Array:
	var wants := designated_gates(sim)
	var out: Array = []
	for e in perimeter(sim):
		var existing := find(sim, e.d, int(e.side))
		var gate: bool = wants.has("%d,%d,%d" % [e.d.x, e.d.y, e.side])
		if existing.is_empty() or (gate and str(existing.kind) == "wall" and not _has_gate_on(sim, int(e.side))):
			out.append({"d": e.d, "side": e.side, "gate": gate, "converts": not existing.is_empty()})
	var centre := Survival.village_centre(sim)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x.gate != y.gate:
			return bool(x.gate)
		return mid(x.d, int(x.side)).distance_to(centre) < mid(y.d, int(y.side)).distance_to(centre))
	return out


static func _has_gate_on(sim: LifeSim, side: int) -> bool:
	for g in gates(sim):
		if int(g.edge[2]) == side:
			return true
	return false


static func walkable_near(sim: LifeSim, d: Vector2i, side: int) -> Vector2i:
	var guess := Vector2i(d.x * 4 + 1, d.y * 4 + 1)
	match side:
		0: guess = Vector2i(d.x * 4, d.y * 4 + 1)
		1: guess = Vector2i(d.x * 4 + 3, d.y * 4 + 1)
		2: guess = Vector2i(d.x * 4 + 1, d.y * 4)
		3: guess = Vector2i(d.x * 4 + 1, d.y * 4 + 3)
	return sim.map.nearest_walkable(guess)


## Why a wall cannot be started here right now ("" if it can).
static func place_blocker(sim: LifeSim, d: Vector2i, side: int) -> String:
	if side < 0 or side > 3 or not sim.map.claimed.has(d):
		return "Walls go along the village border."
	if sim.map.claimed.has(d + SIDES[side]):
		return "That edge is inside the village."
	if not find(sim, d, side).is_empty():
		return "There is already a wall here."
	if Catalog.stage_needed("wall", 1) > sim.stage():
		return "Needs the village to reach %s." % Catalog.STAGES[Catalog.stage_needed("wall", 1)]
	var c := Catalog.cost("wall", 1)
	if sim.money < int(c.coins) or sim.materials() < int(c.mats):
		return "Needs %d coins and %d materials." % [c.coins, c.mats]
	return ""


## Start a wall (or gate) on this edge. Returns a message beginning "Started" on success.
static func place(sim: LifeSim, d: Vector2i, side: int, gate: bool = false) -> String:
	if side < 0 or side > 3 or not sim.map.claimed.has(d):
		return "Walls go along the village border."
	if sim.map.claimed.has(d + SIDES[side]):
		return "That edge is inside the village."
	var kind := "gate" if gate else "wall"
	var existing := find(sim, d, side)
	if not existing.is_empty():
		if str(existing.kind) == kind:
			return "There is already a %s here." % kind
		if not gate:
			return "There is a gate here already."
		var upgrade_cost := Catalog.cost("gate", 1)
		if sim.money < int(upgrade_cost.coins) or sim.materials() < int(upgrade_cost.mats):
			return "Needs %d coins and %d materials." % [upgrade_cost.coins, upgrade_cost.mats]
		sim.money -= int(upgrade_cost.coins)
		sim.spend_materials(int(upgrade_cost.mats))
		existing.kind = "gate"
		existing.open = true
		existing.target = int(existing.level) if int(existing.level) >= 1 else 1
		sim.log_event("A gate is being fitted to the %s." % label_for(d, side))
		sim.notice("Fitting a gate")
		return "Started the Gate."
	if Catalog.stage_needed(kind, 1) > sim.stage():
		return "Needs the village to reach %s." % Catalog.STAGES[Catalog.stage_needed(kind, 1)]
	var c := Catalog.cost(kind, 1)
	if sim.money < int(c.coins) or sim.materials() < int(c.mats):
		return "Needs %d coins and %d materials." % [c.coins, c.mats]
	sim.money -= int(c.coins)
	sim.spend_materials(int(c.mats))
	var stand := walkable_near(sim, d, side)
	var b := {"id": sim.next_building_id, "kind": kind, "tile": [stand.x, stand.y], "level": 0, "target": 1, "progress": 0.0, "visits": 0, "variant": sim.rng.randi() % 997, "door": [stand.x, stand.y], "growth": 0.0, "condition": 100.0, "soil": 100.0, "pests": false, "edge": [d.x, d.y, side], "open": true, "breached": false}
	sim.next_building_id += 1
	sim.buildings.append(b)
	sim.goals.builder = true
	sim.log_event("Construction started: a %s on the %s." % [kind, label_for(d, side)])
	sim.notice("Building a %s" % kind)
	return "Started the %s." % Catalog.label(kind)


## Wall off as much of the border as can be paid for. Returns {placed, message}.
static func build(sim: LifeSim, limit: int, force_gate: bool = false) -> Dictionary:
	var placed := 0
	var last := ""
	for e in missing(sim):
		if placed >= limit:
			break
		var gate: bool = bool(e.gate) or (force_gate and placed == 0)
		last = place(sim, e.d, int(e.side), gate)
		if last.begins_with("Started"):
			placed += 1
		else:
			break
	if placed == 0:
		if missing(sim).is_empty():
			return {"placed": 0, "message": "The whole border is already walled."}
		return {"placed": 0, "message": last}
	var remaining := missing(sim).size()
	return {"placed": placed, "message": "Started %d wall segment%s%s." % [placed, "" if placed == 1 else "s", ", %d still to go" % remaining if remaining > 0 else ", closing the whole border"]}


## When the village grows past a wall, that stretch comes down (new edges need new walls).
static func remove_interior(sim: LifeSim) -> void:
	var removed := 0
	for b in sim.buildings.duplicate():
		if not is_wall(b) or not b.has("edge"):
			continue
		var e := edge(b)
		if sim.map.claimed.has(e.d + SIDES[e.side]):
			sim.buildings.erase(b)
			sim.push_fx({"type": "wall_removed", "id": int(b.id)})
			removed += 1
	if removed > 0:
		sim.notice("The new land took down %d stretch%s of wall. Build it again further out." % [removed, "" if removed == 1 else "es"])


# --- gates and sieges ---------------------------------------------------------------------------------------------------

## Gates close for the night or when monsters are about, and open again by day, unless the chief says otherwise.
static func policy(sim: LifeSim) -> void:
	var all := gates(sim)
	if all.is_empty():
		return
	var want_open := true
	if sim.gates_override_until > sim.minutes and sim.gates_override != "":
		want_open = sim.gates_override == "open"
	else:
		sim.gates_override = ""
		var danger := Survival.is_night(sim) and sim.day() >= Survival.GRACE_DAYS
		if not danger:
			var reach := Survival.village_radius(sim) + 14.0
			var centre := Survival.village_centre(sim)
			for m in sim.mobs:
				if centre.distance_to(Vector2(float(m.pos[0]), float(m.pos[1]))) < reach:
					danger = true
					break
		want_open = not danger
	var state := "open" if want_open else "closed"
	for g in all:
		g.open = want_open
	if state != sim.gates_state:
		if sim.gates_state != "":
			sim.notice("The gates are %s." % ("open again" if want_open else "closed"))
		sim.gates_state = state


static func set_override(sim: LifeSim, mode: String) -> String:
	if gates(sim).is_empty():
		return "There are no gates yet."
	if mode == "auto":
		sim.gates_override = ""
		sim.gates_override_until = 0.0
		policy(sim)
		return "The gates follow the usual routine (shut at night or when monsters come)."
	sim.gates_override = mode
	sim.gates_override_until = sim.minutes + OVERRIDE_MINUTES
	policy(sim)
	return "The gates are %s for the next several hours." % ("open" if mode == "open" else "shut and barred")


## A monster claws at a wall in its way. Stronger walls hold much longer.
static func siege(sim: LifeSim, mob: Dictionary, w: Dictionary, dm: float) -> void:
	mob.siege = int(w.id)
	var rate: float = float(SIEGE_RATE.get(str(mob.kind), 1.0)) * defence_factor(sim, w)
	w.condition = maxf(0.0, float(w.get("condition", 100.0)) - rate * dm / float(maxi(1, int(w.level))))
	if float(w.condition) <= 0.0 and not bool(w.get("breached", false)):
		w.breached = true
		var e := edge(w)
		sim.notice("The %s was breached! Monsters can pour through the %s." % [Catalog.label(str(w.kind)).to_lower(), label_for(e.d, e.side)])
		sim.log_event("The %s on the %s was breached." % [str(w.kind), label_for(e.d, e.side)])
		sim.push_fx({"type": "wall_breach", "id": int(w.id)})


## Is a watchtower close enough to cover this stretch of wall?
static func tower_covers(sim: LifeSim, w: Dictionary) -> bool:
	var e := edge(w)
	var m: Vector2 = mid(e.d, e.side)
	for b in sim.buildings:
		if str(b.kind) == "watchtower" and int(b.level) >= 1 and not bool(b.get("breached", false)):
			if Vector2(float(b.tile[0]), float(b.tile[1])).distance_to(m) <= 11.0:
				return true
	return false


## Is someone minding this gate? A gatekeeper standing near it.
static func manned(sim: LifeSim, w: Dictionary) -> bool:
	if str(w.kind) != "gate":
		return false
	var m: Vector2 = gate_points(w).mid
	for r in sim.residents:
		if Jobs.title_of(r) == "gatekeeper" and int(r.get("employer", -1)) == int(w.id) and float(r.get("down_until", 0.0)) <= sim.minutes:
			if Vector2(float(r.pos[0]), float(r.pos[1])).distance_to(m) <= 3.5:
				return true
	return false


## How much damage a siege does here, relative to normal: towers and keepers help, an unmanned gate at night is weak.
static func defence_factor(sim: LifeSim, w: Dictionary) -> float:
	var f := 1.0
	if tower_covers(sim, w):
		f *= 0.7
	if str(w.kind) == "gate":
		if manned(sim, w):
			f *= 0.7
		elif Survival.is_night(sim):
			f *= 1.35
	return f


static func status(sim: LifeSim) -> Dictionary:
	var total := 0
	var up := 0
	var breached := 0
	var gate_count := 0
	var open := 0
	for b in sim.buildings:
		if not is_wall(b):
			continue
		total += 1
		if bool(b.get("breached", false)):
			breached += 1
		elif int(b.level) >= 1:
			up += 1
		if str(b.kind) == "gate" and intact(b):
			gate_count += 1
			if bool(b.get("open", true)):
				open += 1
	return {"segments": total, "intact": up, "breached": breached, "gates": gate_count, "open": open, "border": perimeter(sim).size()}
