class_name Jobs
extends RefCounted
## Professions. Residents hold a named job (farmer, shopkeeper, doctor, guard...) with working hours, a wage
## from the village treasury and a share of what they produce. Employed residents spend their shift at their
## trade, save part of their pay, and spend savings on furnishing their own homes. Shopkeepers own the shop.
## Resident keys: profession (title or ""), employer (building id or -1), savings (coins).

const JOBS := {
	"farmer": {"label": "Farmer", "action": "farm", "kind": "farm", "shift": [6.5, 16.0], "wage": 6, "skill": "gardening", "traits": ["Curious gardener", "Careful saver"], "slots_per": 2},
	"lumberjack": {"label": "Lumberjack", "action": "chop", "kind": "", "shift": [7.0, 15.0], "wage": 6, "skill": "fitness", "traits": ["Practical builder", "Restless explorer"], "slots_per": 1},
	"miner": {"label": "Miner", "action": "mine", "kind": "", "shift": [7.0, 15.0], "wage": 7, "skill": "craft", "traits": ["Practical builder", "Ambitious maker"], "slots_per": 1},
	"builder": {"label": "Builder", "action": "work", "kind": "workshop", "shift": [7.0, 17.0], "wage": 8, "skill": "craft", "traits": ["Ambitious maker", "Practical builder"], "slots_per": 2},
	"shopkeeper": {"label": "Shopkeeper", "action": "work", "kind": "market", "shift": [8.0, 18.0], "wage": 8, "skill": "cooking", "traits": ["Outgoing cook", "Cheerful helper", "Careful saver"], "slots_per": 1},
	"doctor": {"label": "Doctor", "action": "work", "kind": "clinic", "shift": [8.0, 18.0], "wage": 12, "skill": "knowledge", "traits": ["Gentle healer", "Thoughtful planner"], "slots_per": 1},
	"librarian": {"label": "Librarian", "action": "work", "kind": "library", "shift": [9.0, 17.0], "wage": 7, "skill": "knowledge", "traits": ["Creative bookworm", "Quiet dreamer"], "slots_per": 1},
	"guard": {"label": "Guard", "action": "guard", "kind": "watchtower", "shift": [18.0, 30.0], "wage": 9, "skill": "fitness", "traits": ["Practical builder", "Restless explorer"], "slots_per": 2},
	"gatekeeper": {"label": "Gatekeeper", "action": "guard", "kind": "gate", "shift": [6.0, 20.0], "wage": 8, "skill": "fitness", "traits": ["Careful saver", "Thoughtful planner"], "slots_per": 1},
}
const SAVE_SHARE := 0.45
const PAYROLL_RESERVE := 80
const HOME_WISHES := ["bedSingle", "loungeChair", "lampRoundFloor", "rugRectangle", "pottedPlant", "table", "bookcaseClosed", "loungeSofa", "televisionModern", "bedDouble"]


static func title_of(r: Dictionary) -> String:
	return str(r.get("profession", ""))


static func label_of(r: Dictionary) -> String:
	var t := title_of(r)
	return str(JOBS[t].label) if JOBS.has(t) else ""


## True if the job's hours include this hour (shifts may run past midnight: 18 to 30 is 18:00-06:00).
static func in_shift(title: String, hour: float) -> bool:
	if not JOBS.has(title):
		return false
	var s: Array = JOBS[title].shift
	var h := hour
	if float(s[1]) > 24.0 and h < float(s[0]):
		h += 24.0
	return h >= float(s[0]) and h < float(s[1])


static func hour_of(sim: LifeSim) -> float:
	return fmod(sim.minutes / 60.0, 24.0)


static func on_shift(sim: LifeSim, r: Dictionary) -> bool:
	return in_shift(title_of(r), hour_of(sim))


## The activity this resident should be doing for their job right now ("" if none applies).
static func preferred_action(sim: LifeSim, r: Dictionary) -> String:
	var t := title_of(r)
	if t == "" or not on_shift(sim, r):
		return ""
	if Lifecycle.blocked(r, str(JOBS[t].action)) != "":
		return ""
	return str(JOBS[t].action)


## Buildings a worker uses for the generic "work" action.
static func workplace_kind(r: Dictionary) -> String:
	var t := title_of(r)
	if t != "" and JOBS[t].action == "work":
		return str(JOBS[t].kind)
	return ""


static func holders(sim: LifeSim, title: String) -> Array:
	var out: Array = []
	for i in range(sim.residents.size()):
		if title_of(sim.residents[i]) == title:
			out.append(i)
	return out


## How many people the village can employ in each trade right now.
static func openings(sim: LifeSim, title: String) -> int:
	var spec: Dictionary = JOBS[title]
	var n := 0
	match title:
		"farmer": n = sim._count("farm") * int(spec.slots_per)
		"lumberjack": n = 1 + sim.residents.size() / 12
		"miner": n = 1 + sim.residents.size() / 16
		"builder": n = sim._count("workshop") * int(spec.slots_per)
		"shopkeeper": n = sim._count("market")
		"doctor": n = sim._count("clinic")
		"librarian": n = sim._count("library")
		"guard": n = mini(6, sim._count("watchtower") * int(spec.slots_per) + (1 if sim.threat > 0 or sim.kills > 2 else 0))
		"gatekeeper": n = Walls.gates(sim).size()
	return n


static func vacancies(sim: LifeSim, title: String) -> int:
	return maxi(0, openings(sim, title) - holders(sim, title).size())


static func eligible(r: Dictionary) -> bool:
	return int(r.age) >= 18 and int(r.age) < Lifecycle.SENIOR_AGE + 6


## Who suits a trade best: their skill, their temperament, and whether they are free.
static func suitability(r: Dictionary, title: String) -> float:
	var spec: Dictionary = JOBS[title]
	var score := float(r.skills.get(str(spec.skill), 0.0)) * 0.6
	if str(r.trait) in spec.traits:
		score += 25.0
	if title_of(r) != "":
		score -= 40.0
	if Lifecycle.blocked(r, str(spec.action)) != "":
		score -= 200.0
	if title == "guard" and "Peace" in r.values:
		score -= 60.0
	if title in ["lumberjack", "miner"] and "Nature" in r.values:
		score -= 60.0
	return score


static func employer_for(sim: LifeSim, title: String, r: Dictionary) -> int:
	var kind: String = JOBS[title].kind
	if kind == "":
		return -1
	var here := Vector2(float(r.pos[0]), float(r.pos[1]))
	var best := -1
	var best_d := 1.0e9
	for b in sim.buildings:
		if str(b.kind) != kind or int(b.level) < 1:
			continue
		var staffed := 0
		for other in sim.residents:
			if int(other.get("employer", -1)) == int(b.id) and title_of(other) == title:
				staffed += 1
		if staffed >= maxi(1, int(JOBS[title].slots_per)) and title not in ["farmer", "builder", "guard"]:
			continue
		var d := here.distance_to(Vector2(float(b.tile[0]), float(b.tile[1]))) + float(staffed) * 6.0
		if d < best_d:
			best_d = d
			best = int(b.id)
	return best


## Give someone a job. Returns {ok, message}.
static func assign(sim: LifeSim, index: int, title: String, announce: bool = true) -> Dictionary:
	if not JOBS.has(title) or index < 0 or index >= sim.residents.size():
		return {"ok": false, "message": "Choose a job: farmer, lumberjack, miner, builder, shopkeeper, doctor, librarian, guard or gatekeeper."}
	var r: Dictionary = sim.residents[index]
	if not eligible(r):
		return {"ok": false, "message": "%s is too %s to hold a job." % [r.name, "young" if int(r.age) < 18 else "old"]}
	if title_of(r) != title and vacancies(sim, title) <= 0 and openings(sim, title) > 0:
		return {"ok": false, "message": "Every %s post is already filled." % str(JOBS[title].label).to_lower()}
	if openings(sim, title) <= 0:
		var need: String = {"farmer": "a farm", "builder": "a workshop", "shopkeeper": "a market", "doctor": "a clinic", "librarian": "a library", "guard": "a watchtower", "gatekeeper": "a gate"}.get(title, "work")
		return {"ok": false, "message": "There is no opening for a %s (the village needs %s first)." % [JOBS[title].label.to_lower(), need]}
	if title_of(r) == title:
		return {"ok": false, "message": "%s already works as a %s." % [r.name, str(JOBS[title].label).to_lower()]}
	var spec: Dictionary = JOBS[title]
	r.profession = title
	r.employer = employer_for(sim, title, r)
	if title == "shopkeeper" and int(r.employer) >= 0:
		var shop := sim.building_by_id(int(r.employer))
		if not shop.is_empty() and str(shop.get("owner", "")) == "":
			shop.owner = str(r.name)
	if int(r.employer) >= 0:
		var site := sim.building_by_id(int(r.employer))
		if not site.is_empty() and Interiors.enterable(site):
			Ownership.claim_station(sim, site, str(r.name))
	if announce:
		sim.log_event("%s now works as a %s." % [r.name, str(spec.label).to_lower()])
		sim.notice("%s is now a %s" % [r.name, str(spec.label).to_lower()])
		sim.say(index, "A %s! I won't let you down, Chief." % str(spec.label).to_lower())
		sim.emote(index, "star", 0.2)
	Psyche.add_core(sim, r, "Day %d: I became the village %s." % [sim.day(), str(spec.label).to_lower()], 0.5, 0.6)
	return {"ok": true, "message": "%s is now a %s." % [r.name, str(spec.label).to_lower()]}


static func dismiss(sim: LifeSim, index: int) -> Dictionary:
	if index < 0 or index >= sim.residents.size():
		return {"ok": false, "message": "Who?"}
	var r: Dictionary = sim.residents[index]
	if title_of(r) == "":
		return {"ok": false, "message": "%s has no job." % r.name}
	var old := label_of(r).to_lower()
	for b in sim.buildings:
		if str(b.get("owner", "")) == str(r.name):
			b.owner = ""
	r.profession = ""
	r.employer = -1
	r.stress = minf(100.0, float(r.stress) + 4.0)
	return {"ok": true, "message": "%s is no longer the %s." % [r.name, old]}


## Fill empty posts with the best free people.
static func fill_vacancies(sim: LifeSim) -> int:
	var filled := 0
	for title in JOBS:
		while vacancies(sim, title) > 0:
			var best := -1
			var best_score := 15.0
			for i in range(sim.residents.size()):
				var r: Dictionary = sim.residents[i]
				if not eligible(r) or title_of(r) != "":
					continue
				var score := suitability(r, title)
				if score > best_score:
					best_score = score
					best = i
			if best < 0:
				break
			if bool(assign(sim, best, title).ok):
				filled += 1
			else:
				break
	return filled


## Close posts that no longer exist (a clinic collapsed, the last gate was torn down).
static func prune(sim: LifeSim) -> void:
	for title in JOBS:
		var holders_now := holders(sim, title)
		var allowed := openings(sim, title)
		while holders_now.size() > allowed:
			var last: int = holders_now.pop_back()
			dismiss(sim, last)
			sim.log_event("%s lost their post as the %s." % [sim.residents[last].name, str(JOBS[title].label).to_lower()])


static func daily(sim: LifeSim) -> void:
	prune(sim)
	fill_vacancies(sim)
	payroll(sim)
	for r in sim.residents:
		_spend_savings(sim, r)
	# A shop's owner takes a quarter of its takings home.
	for b in sim.buildings:
		var owner_name := str(b.get("owner", ""))
		if owner_name != "" and str(b.kind) == "market" and int(b.level) >= 1:
			var i := sim.index_of(owner_name)
			if i >= 0:
				var cut := 2 * int(b.level)
				sim.residents[i].savings = int(sim.residents[i].savings) + cut


## Daily pay from the treasury; part of it is saved. An empty treasury means unpaid, grumbling workers.
static func payroll(sim: LifeSim) -> void:
	for r in sim.residents:
		var t := title_of(r)
		if t == "":
			continue
		var wage := int(JOBS[t].wage) + int(r.career)
		if sim.money - wage >= PAYROLL_RESERVE:
			sim.money -= wage
			var kept := int(round(float(wage) * SAVE_SHARE))
			r.savings = int(r.savings) + kept
			r.earned = int(r.earned) + wage
		else:
			r.stress = minf(100.0, float(r.stress) + 3.0)
			if sim.rng.randf() < 0.25:
				sim.log_event("%s was not paid this week." % r.name)


## Residents use their own savings to furnish their homes with things they like.
static func _spend_savings(sim: LifeSim, r: Dictionary) -> void:
	if int(r.savings) < 20 or sim.rng.randf() > 0.35:
		return
	var home := sim.building_by_id(int(r.home))
	if home.is_empty() or not Interiors.enterable(home):
		return
	Interiors.ensure(sim, home)
	var owned: Dictionary = {}
	for it in Interiors.furniture_of(home):
		if str(r.name) in it.owners:
			owned[str(it.model)] = true
	for model in HOME_WISHES:
		if owned.has(model) and model != "pottedPlant":
			continue
		var price := FurnitureDb.price_of(model)
		if price > int(r.savings):
			continue
		var placed := Interiors.place_auto(sim, home, model, [str(r.name)] if FurnitureDb.is_personal(model) else [], false)
		if placed.is_empty():
			continue
		r.savings = int(r.savings) - price
		sim.log_event("%s bought a %s for their home." % [r.name, FurnitureDb.label_of(model).to_lower()])
		r.needs.fun = minf(100.0, float(r.needs.fun) + 5.0)
		sim.push_fx({"type": "furnished", "building": int(home.id)})
		return


static func summary(sim: LifeSim) -> Array:
	var out: Array = []
	for title in JOBS:
		var names: Array = []
		for i in holders(sim, title):
			names.append(str(sim.residents[i].name))
		var open := vacancies(sim, title)
		if names.is_empty() and openings(sim, title) == 0:
			continue
		out.append({"title": title, "label": JOBS[title].label, "names": names, "open": open})
	return out
