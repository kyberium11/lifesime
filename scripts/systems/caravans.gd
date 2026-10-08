class_name Caravans
extends RefCounted
## Travelling merchants and trade routes. A caravan camps outside the village for a few days with rare wares that
## no local market has (spices for a feast, exotic melon seeds, a prize cow, steel tools, rare books, medicine),
## and pays better for what the village sells. The chief can pay to open trade routes: each level brings
## caravans more often, and every sale to the market earns a little more.

const WARES := {
	"c_spice": {"label": "Spices", "base": 28, "qty": 3, "blurb": "Feast spices: lifts everyone's spirits when bought."},
	"c_seeds": {"label": "Melon seeds", "base": 70, "qty": 1, "blurb": "Exotic seeds: unlocks melons, a rich new crop."},
	"c_cow": {"label": "Prize cow", "base": 150, "qty": 1, "blurb": "A champion milker: twice the milk of an ordinary cow."},
	"c_tools": {"label": "Steel tools", "base": 160, "qty": 1, "blurb": "Better axes and picks: every haul brings one more, and repairs cost less."},
	"c_books": {"label": "Rare books", "base": 70, "qty": 2, "blurb": "Teaches everyone something: knowledge for the whole village."},
	"c_medicine": {"label": "Medicine", "base": 7, "qty": 6, "blurb": "Apothecary's remedies, cheaper than the market's."},
}
const STAY_DAYS := 3
const BASE_CHANCE := 0.09
const ROUTE_COST := 250
const MAX_ROUTE := 3


static func present(sim: LifeSim) -> bool:
	return not sim.caravan.is_empty() and sim.day() <= int(sim.caravan.until)


static func arrival_chance(sim: LifeSim) -> float:
	if sim.day() < 5 or present(sim):
		return 0.0
	return BASE_CHANCE + 0.05 * float(sim.routes)


static func route_bonus(sim: LifeSim) -> float:
	return 1.0 + 0.05 * float(sim.routes)


static func price_of(sim: LifeSim, key: String) -> int:
	return int(sim.caravan.get("prices", {}).get(key, WARES[key].base)) if not sim.caravan.is_empty() else int(WARES[key].base)


## A caravan arrives with a random selection of wares.
static func arrive(sim: LifeSim) -> void:
	if present(sim):
		return
	var keys: Array = WARES.keys()
	keys.shuffle()
	var chosen: Array = keys.slice(0, 3 + (1 if sim.routes >= 2 else 0))
	if "c_medicine" not in chosen:
		chosen[chosen.size() - 1] = "c_medicine"
	var stock := {}
	var prices := {}
	for k in chosen:
		stock[k] = int(WARES[k].qty) + (1 if sim.routes >= 3 else 0)
		prices[k] = int(round(float(WARES[k].base) * sim.rng.randf_range(0.9, 1.2)))
	var names := ["Marlow's caravan", "The Silver Wheel company", "Old Tamsin's wagons", "The Wandering Fair", "Corvin & Daughters"]
	sim.caravan = {"name": names[sim.rng.randi() % names.size()], "until": sim.day() + STAY_DAYS - 1 + (1 if sim.routes >= 3 else 0), "stock": stock, "prices": prices, "arrived": sim.day()}
	sim.notice("%s has set up camp outside the village for a few days." % sim.caravan.name)
	sim.log_event("%s arrived with %s." % [sim.caravan.name, ", ".join(chosen.map(func(k: String) -> String: return str(WARES[k].label).to_lower()))])
	sim.push_fx({"type": "caravan_arrive"})


static func daily(sim: LifeSim) -> void:
	if not sim.caravan.is_empty() and sim.day() > int(sim.caravan.until):
		sim.notice("%s has moved on." % sim.caravan.name)
		sim.log_event("%s left." % sim.caravan.name)
		sim.caravan = {}
		sim.push_fx({"type": "caravan_leave"})
	if arrival_chance(sim) > 0.0 and sim.rng.randf() < arrival_chance(sim):
		arrive(sim)


static func stock_of(sim: LifeSim, key: String) -> int:
	return int(sim.caravan.get("stock", {}).get(key, 0)) if present(sim) else 0


## Buy from the caravan. Returns {ok, message}.
static func buy(sim: LifeSim, key: String, amount: int) -> Dictionary:
	if not WARES.has(key):
		return {"ok": false, "message": "The merchant doesn't sell that."}
	if not present(sim):
		return {"ok": false, "message": "No merchant is in town."}
	var have := stock_of(sim, key)
	if have <= 0:
		return {"ok": false, "message": "The merchant has no more %s." % str(WARES[key].label).to_lower()}
	var n := mini(maxi(1, amount), have)
	var unit := price_of(sim, key)
	var affordable := mini(n, int(floor(float(sim.money) / float(unit))))
	if affordable <= 0:
		return {"ok": false, "message": "%s costs %d coins each." % [WARES[key].label, unit]}
	var effect := _apply(sim, key, affordable)
	if not bool(effect.ok):
		return effect
	sim.money -= unit * int(effect.used)
	sim.caravan.stock[key] = have - int(effect.used)
	return {"ok": true, "message": "Bought %d %s for %d coins. %s" % [int(effect.used), str(WARES[key].label).to_lower(), unit * int(effect.used), str(effect.note)]}


static func _apply(sim: LifeSim, key: String, n: int) -> Dictionary:
	match key:
		"c_spice":
			for r in sim.residents:
				r.needs.fun = minf(100.0, float(r.needs.fun) + 6.0 * float(n))
				r.needs.social = minf(100.0, float(r.needs.social) + 4.0 * float(n))
				r.stress = maxf(0.0, float(r.stress) - 2.0 * float(n))
			return {"ok": true, "used": n, "note": "The whole village smells wonderful tonight."}
		"c_seeds":
			if "melon" in sim.crops_unlocked:
				return {"ok": false, "message": "Melons are already planted in the village."}
			sim.crops_unlocked.append("melon")
			return {"ok": true, "used": 1, "note": "Melons can now be planted: say \"plant melons\"."}
		"c_cow":
			var farm := Farming.farm_with_room(sim, "cow")
			if farm.is_empty():
				return {"ok": false, "message": "No farm has room for the prize cow."}
			var a := Farming.add_animal(sim, farm, "cow", sim.day() - int(Farming.ANIMALS.cow.adult_days))
			a.breed = "prize"
			sim.push_fx({"type": "livestock"})
			return {"ok": true, "used": 1, "note": "She is settled in at the farm."}
		"c_tools":
			if sim.tools:
				return {"ok": false, "message": "The village already has steel tools."}
			sim.tools = true
			return {"ok": true, "used": 1, "note": "Woodcutters and miners will bring back more."}
		"c_books":
			for r in sim.residents:
				r.skills.knowledge = float(r.skills.knowledge) + 8.0 * float(n)
			return {"ok": true, "used": n, "note": "Everyone learns a little."}
		"c_medicine":
			sim.medicine += 3 * n
			return {"ok": true, "used": n, "note": "%d doses added to the clinic's shelves." % (3 * n)}
	return {"ok": false, "message": "Unknown ware."}


## Pay to open or widen a trade route. Returns {ok, message}.
static func open_route(sim: LifeSim) -> Dictionary:
	if sim.routes >= MAX_ROUTE:
		return {"ok": false, "message": "The village already trades along every road it can."}
	var cost := ROUTE_COST * (sim.routes + 1)
	if sim.money < cost:
		return {"ok": false, "message": "A new trade route costs %d coins." % cost}
	sim.money -= cost
	sim.routes += 1
	sim.log_event("The village opened trade route %d." % sim.routes)
	return {"ok": true, "message": "Trade route %d opened (%d coins). Caravans will visit more often and sales earn %d%% more." % [sim.routes, cost, 5 * sim.routes]}


static func report(sim: LifeSim) -> String:
	if not present(sim):
		return "No merchant is in town. Trade route level %d; caravans come about every %d days." % [sim.routes, int(round(1.0 / maxf(0.02, BASE_CHANCE + 0.05 * float(sim.routes))))]
	var parts: Array = []
	for k in sim.caravan.stock:
		if int(sim.caravan.stock[k]) > 0:
			parts.append("%s %d (%d coins)" % [str(WARES[k].label).to_lower(), int(sim.caravan.stock[k]), price_of(sim, k)])
	return "%s sells: %s." % [sim.caravan.name, ", ".join(parts) if not parts.is_empty() else "nothing more"]
