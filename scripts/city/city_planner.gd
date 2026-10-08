class_name CityPlanner
extends RefCounted
## The village council. It reads what the town lacks and proposes concrete plans:
## build something on a free lot, upgrade a busy building, or claim more land.
## The chief's advice, the council and (optionally) the Claude "mayor" all choose from these same options,
## and LifeSim.apply_option() validates and executes whichever is chosen.

## Coins the council keeps back so a single plan never bankrupts the town.
const RESERVE := 60
## The council only acts on plans that answer a real need.
const MIN_SCORE := 2.5


## How urgently each kind of building (and land) is needed, 0 (fine) to ~2.5 (pressing).
static func needs(sim: LifeSim) -> Dictionary:
	var pop := sim.residents.size()
	var cap := sim.housing()
	var food_stock := sim.food + sim.meals * 2
	var out := {}
	# The council plans ahead: it wants spare beds so newcomers keep arriving, and a richer town wants more of everything.
	var ambition := 1.0 + clampf(log(maxf(1.0, float(sim.money)) / 2000.0) / 1.5, 0.0, 1.5) * 0.6
	out["home"] = clampf((float(pop) * 1.2 + 4.0 - cap) / 3.0, 0.0, 2.5)
	var demand := {"market": pop / 6.0 * ambition, "workshop": pop / 5.0 * ambition, "library": pop / 10.0 * ambition, "bathhouse": pop / 8.0 * ambition, "park": pop / 8.0 * ambition}
	for kind in demand:
		var supply: float = sim._levels(kind)
		var need := clampf((float(demand[kind]) - supply) / 2.0, 0.0, 2.0)
		if sim._count(kind) == 0 and pop >= 3 and Catalog.stage_needed(kind, 1) <= sim.stage():
			need = maxf(need, 1.2)
		out[kind] = need
	# Farms are judged on how much food is actually in the larder per resident.
	out["farm"] = clampf((pop * 8.0 - food_stock) / maxf(1.0, pop * 4.0), 0.0, 2.0)
	if sim._count("farm") == 0 and pop >= 3:
		out["farm"] = maxf(float(out["farm"]), 1.2)
	out["office"] = 0.0
	if sim.stage() >= 2:
		out["office"] = clampf((pop / 14.0 - sim._levels("office")) / 2.0, 0.0, 1.5)
	var ill := 0
	for r in sim.residents:
		if Health.is_ill(sim, r):
			ill += 1
	var clinic_need := clampf((float(ill) + (2.0 if sim.epidemic else 0.0) - sim._levels("clinic") * 2.0) / 3.0, 0.0, 2.0)
	if sim._count("clinic") == 0 and pop >= 12 and Catalog.stage_needed("clinic", 1) <= sim.stage():
		clinic_need = maxf(clinic_need, 0.9)
	out["clinic"] = clinic_need
	var tower_need := 0.0
	if sim.day() >= Survival.GRACE_DAYS:
		tower_need = clampf((float(pop) / 9.0 - float(sim._levels("watchtower"))) / 2.0, 0.0, 1.6)
		if sim._count("watchtower") == 0 and (sim.kills > 0 or sim.downs > 0):
			tower_need = maxf(tower_need, 1.3)
	out["watchtower"] = tower_need
	var wall_need := 0.0
	var gap := Walls.missing(sim).size()
	# Walls come down whenever the village grows past them, so the council only fortifies a settled, wealthy town.
	if sim.stage() >= 2 and gap > 0 and sim.day() >= Survival.GRACE_DAYS and sim.money > 600 and sim.map.free_lots().size() >= 4:
		wall_need = clampf(float(sim.kills + sim.downs * 2) / 20.0, 0.0, 1.0)
		var wall_status := Walls.status(sim)
		if int(wall_status.segments) >= 3 and int(wall_status.gates) == 0:
			wall_need = maxf(wall_need, 1.7)
	out["wall"] = wall_need
	var free_lots := sim.map.free_lots().size()
	out["land"] = clampf((3.0 - free_lots) / 2.0, 0.0, 2.0) + (1.0 if free_lots == 0 else 0.0)
	if sim.money > 6000 and float(free_lots) < maxf(8.0, float(pop) * 0.5):
		out["land"] = maxf(float(out["land"]), 1.4)
	return out


static func _reason(kind: String, sim: LifeSim) -> String:
	var pop := sim.residents.size()
	match kind:
		"home": return "Homes are nearly full: %d residents for %d beds." % [pop, sim.housing()]
		"farm": return "Food is tight: %d produce and meals for %d residents." % [sim.food + sim.meals, pop]
		"market": return "%d residents share %d market level%s." % [pop, sim._levels("market"), "" if sim._levels("market") == 1 else "s"]
		"workshop": return "More workshops mean more work shifts to build the town."
		"library": return "Residents want to learn: knowledge only grows at a library."
		"bathhouse": return "Hygiene is slipping with %d people sharing %d bathhouse level%s." % [pop, sim._levels("bathhouse"), "" if sim._levels("bathhouse") == 1 else "s"]
		"park": return "Residents need green space for play and calm."
		"wall": return "Monsters keep reaching the homes. A wall with gates would keep them out."
		"clinic": return "Illness is going round and the sick have nowhere to be treated."
		"watchtower": return "Monsters keep coming at night. Lookouts would keep people safe."
		"office": return "The town is big enough for offices and city wages."
		"land": return "Only %d free lot%s left, so the town cannot grow without more land." % [sim.map.free_lots().size(), "" if sim.map.free_lots().size() == 1 else "s"]
	return "The town would benefit."


## Concrete, currently possible plans sorted best first. Each: {id, type, kind, tile|building, label, coins, mats, score, reason}.
static func options(sim: LifeSim, limit: int = 9, keep_reserve: bool = true) -> Array:
	var need := needs(sim)
	var out: Array = []
	var lots := sim.map.free_lots()
	# A wealthy council keeps investing: coins pile up otherwise.
	var wealth := clampf(log(maxf(1.0, sim.money) / 1500.0) / 1.6, 0.0, 2.0)
	var reserve := RESERVE if keep_reserve else 0
	# Build on the best lots.
	for kind in Catalog.BUILDABLE:
		var n: float = float(need.get(kind, 0.0)) + (wealth * 0.12 if kind in ["park", "office", "library", "bathhouse"] else 0.0)
		if n <= 0.15 or Catalog.stage_needed(kind, 1) > sim.stage():
			continue
		var c := Catalog.cost(kind, 1)
		if sim.money - int(c.coins) < reserve or sim.materials() < int(c.mats):
			continue
		var tried := 0
		for t in lots:
			if sim.build_blocker(kind, t) != "":
				continue
			var dist: float = Vector2(t - Vector2i(2, 2)).length()
			out.append({"type": "build", "kind": kind, "tile": [t.x, t.y], "label": "Build a %s at (%d, %d)" % [Catalog.label(kind).to_lower(), t.x, t.y], "coins": int(c.coins), "mats": int(c.mats), "score": n * 10.0 + 3.0 / (1.0 + dist / 5.0) - float(c.coins) / 900.0, "reason": _reason(kind, sim)})
			tried += 1
			if tried >= 2:
				break
	# Walls and gates around the border.
	if float(need.get("wall", 0.0)) > 0.15:
		var shown := 0
		for e in Walls.missing(sim):
			var wkind := "gate" if bool(e.gate) else "wall"
			var wc := Catalog.cost(wkind, 1)
			if Catalog.stage_needed(wkind, 1) > sim.stage() or sim.money - int(wc.coins) < reserve or sim.materials() < int(wc.mats):
				continue
			out.append({"type": "wall", "kind": wkind, "d": [e.d.x, e.d.y], "side": e.side, "gate": bool(e.gate), "tile": [e.d.x * 4, e.d.y * 4], "label": "Build a %s on the %s" % [wkind, Walls.label_for(e.d, int(e.side))], "coins": int(wc.coins), "mats": int(wc.mats), "score": float(need.wall) * 6.0 + 1.0 - float(wc.coins) / 900.0, "reason": _reason("wall", sim)})
			shown += 1
			if shown >= 2:
				break
	# Upgrade buildings that have earned it.
	for b in sim.buildings:
		if Walls.is_wall(b):
			continue
		if str(b.kind) == "plaza" and sim.stage() < 1:
			continue
		if sim.upgrade_blocker(int(b.id)) != "":
			continue
		var next := int(b.level) + 1
		var c2 := Catalog.cost(str(b.kind), next)
		if sim.money - int(c2.coins) < reserve:
			continue
		var kind: String = b.kind
		var n2: float = float(need.get(kind, 0.0)) * 5.0 + (3.0 if kind == "home" and float(need.get("home", 0.0)) > 0.3 else 0.0)
		var ratio := float(b.visits) / float(maxi(1, Catalog.UPGRADE_VISITS[int(b.level)]))
		out.append({"type": "upgrade", "kind": kind, "building": int(b.id), "tile": b.tile, "label": "Upgrade the %s to level %d" % [Catalog.label(kind).to_lower(), next], "coins": int(c2.coins), "mats": int(c2.mats), "score": n2 + minf(ratio, 3.0) + 1.0 + wealth * 1.6 - float(c2.coins) / 1200.0, "reason": "It is busy (%d visits) and ready to grow. %s" % [int(b.visits), _reason(kind, sim) if n2 > 1.0 else "Better buildings serve more people."]})
	# Claim more land.
	var land: float = float(need.get("land", 0.0))
	var frontier := sim.map.frontier()
	var claimed_options := 0
	for d in frontier:
		if sim.claim_blocker(d) != "" or sim.money - sim.claim_cost(d) < reserve:
			continue
		out.append({"type": "expand", "kind": "land", "tile": [d.x, d.y], "label": "Claim the district at (%d, %d)" % [d.x, d.y], "coins": sim.claim_cost(d), "mats": 0, "score": (land + (wealth * 0.35 if lots.size() < 10 else 0.0)) * 10.0 + 0.5 - float(sim.claim_cost(d)) / 2000.0, "reason": _reason("land", sim)})
		claimed_options += 1
		if claimed_options >= 2:
			break
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var trimmed: Array = []
	for i in range(mini(limit, out.size())):
		var o: Dictionary = out[i]
		o["id"] = i
		trimmed.append(o)
	return trimmed


## One council meeting: act on the best plans, as many as the town has crews for.
static func meeting(sim: LifeSim) -> void:
	if not sim.auto_plan:
		return
	var max_projects := 2 + sim.residents.size() / 8
	# While the chief is being asked about things, the council still gets on with the routine work on its own.
	for i in range(1 if sim.ask_chief else 2):
		if sim.projects().size() >= max_projects:
			return
		var opts := options(sim)
		if opts.is_empty() or float(opts[0].score) < MIN_SCORE:
			return
		sim.apply_option(opts[0], "The council")
