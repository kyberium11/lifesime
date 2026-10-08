class_name Economy
extends RefCounted
## A living market and a changing world: prices follow supply, demand, season and events; random events
## (storms, drought, pests, trader caravans, festivals) shake things up; buildings wear out and need repair;
## farm soil tires with every harvest and recovers with rest and rain.

const BASE_PRICE := {"food": 3.0, "wood": 2.0, "stone": 3.0, "wheat": 3.0, "carrot": 3.4, "corn": 4.0, "pumpkin": 5.0, "melon": 6.0, "wool": 4.0, "medicine": 8.0}
const GOODS := ["food", "wood", "stone", "medicine"]
const CROP_ITEMS := ["wheat", "carrot", "corn", "pumpkin", "melon"]
const CROP_SEASON := {
	"wheat": {"Spring": 1.1, "Summer": 1.0, "Autumn": 0.8, "Winter": 1.3},
	"carrot": {"Spring": 1.1, "Summer": 1.0, "Autumn": 0.95, "Winter": 1.3},
	"corn": {"Spring": 1.15, "Summer": 1.0, "Autumn": 0.85, "Winter": 1.4},
	"pumpkin": {"Spring": 1.3, "Summer": 1.2, "Autumn": 0.7, "Winter": 1.6},
	"melon": {"Spring": 1.2, "Summer": 0.8, "Autumn": 1.0, "Winter": 1.7},
}
const SPREAD := 0.2
const HISTORY_DAYS := 21
const REPAIR_COST := 2
const EVENT_GRACE_DAYS := 4
const DECAY_PER_DAY := 0.55


static func animal_key(kind: String) -> String:
	return "a_" + kind


static func is_animal_key(item: String) -> bool:
	return item.begins_with("a_")


static func base_of(item: String) -> float:
	if is_animal_key(item):
		return float(Farming.ANIMALS[item.substr(2)].cost)
	return float(BASE_PRICE.get(item, 1.0))


static func init_prices() -> Dictionary:
	var out := {}
	for item in BASE_PRICE:
		out[item] = float(BASE_PRICE[item])
	for kind in Farming.ANIMALS:
		out[animal_key(kind)] = float(Farming.ANIMALS[kind].cost)
	return out


static func price(sim: LifeSim, item: String) -> float:
	return float(sim.prices.get(item, base_of(item)))


## The market's cut: wider when the village has no market building, narrower with each level.
static func spread(sim: LifeSim) -> float:
	return clampf(0.26 - 0.04 * float(sim._levels("market")) - (0.05 if Caravans.present(sim) else 0.0), 0.05, 0.26)


static func buy_price(sim: LifeSim, item: String) -> float:
	return price(sim, item) * (1.0 + spread(sim))


static func sell_price(sim: LifeSim, item: String) -> float:
	return price(sim, item) * (1.0 - spread(sim))


static func _stock_ratio(sim: LifeSim, item: String) -> float:
	var pop := float(maxi(1, sim.residents.size()))
	match item:
		"food": return float(sim.food + sim.meals * 2) / (pop * 4.0)
		"wood": return float(sim.wood) / (pop * 1.5 + 8.0)
		"stone": return float(sim.stone) / (pop * 1.0 + 6.0)
		"medicine": return float(sim.medicine) / (pop * 0.4 + 2.0)
	if item in CROP_ITEMS:
		return float(sim.harvested.get(item, 0)) / (pop * 0.8 + 4.0)
	return 1.0


static func herd_size(sim: LifeSim, kind: String) -> int:
	var n := 0
	for b in sim.buildings:
		if str(b.kind) == "farm":
			n += Farming.count(b, kind)
	return n


static func _event_multiplier(sim: LifeSim, item: String) -> float:
	var m := 1.0
	var key := item
	if item in CROP_ITEMS:
		key = "food"
	for e in sim.events:
		if sim.day() <= int(e.until):
			m *= float((e.get("mult", {}) as Dictionary).get(key, 1.0))
	return m


static func update_prices(sim: LifeSim) -> void:
	var pop := maxi(1, sim.residents.size())
	for item in BASE_PRICE:
		var scarcity := clampf(1.9 - _stock_ratio(sim, item), 0.55, 2.8)
		var season_mult := 1.0
		if item == "food":
			season_mult = {"Spring": 1.1, "Summer": 0.9, "Autumn": 0.8, "Winter": 1.35}[sim.season()]
		elif item == "wood" and sim.season() == "Winter":
			season_mult = 1.4
		elif item in CROP_ITEMS:
			season_mult = float(CROP_SEASON[item][sim.season()])
		elif item == "wool":
			scarcity = clampf(1.7 - float(herd_size(sim, "sheep")) / (float(pop) / 6.0 + 1.0), 0.6, 2.2)
			season_mult = 1.4 if sim.season() == "Winter" else 1.0
		var target := base_of(item) * scarcity * season_mult * _event_multiplier(sim, item)
		sim.prices[item] = snappedf(lerpf(price(sim, item), target, 0.35), 0.05)
	for kind in Farming.ANIMALS:
		var want := float({"chicken": maxi(2, pop / 3), "sheep": maxi(1, pop / 7), "cow": maxi(1, pop / 9), "pig": maxi(1, pop / 12)}[kind])
		var ratio := float(herd_size(sim, kind)) / want
		var item := animal_key(kind)
		var scarcity2 := clampf(1.75 - ratio * 0.75, 0.6, 2.2)
		var target2 := base_of(item) * scarcity2 * _event_multiplier(sim, item)
		sim.prices[item] = snappedf(lerpf(price(sim, item), target2, 0.3), 0.05)
	for item in sim.prices:
		if not sim.price_history.has(item) or not sim.price_history[item] is Array:
			sim.price_history[item] = []
		sim.price_history[item].append(float(sim.prices[item]))
		while sim.price_history[item].size() > HISTORY_DAYS:
			sim.price_history[item].pop_front()


## How many of an item the village has to sell.
static func stock_of(sim: LifeSim, item: String) -> int:
	match item:
		"food": return sim.food
		"wood": return sim.wood
		"stone": return sim.stone
		"medicine": return sim.medicine
	if item in CROP_ITEMS:
		return mini(int(sim.harvested.get(item, 0)), sim.food)
	if is_animal_key(item):
		return herd_size(sim, item.substr(2))
	return 0


static func label_of(item: String) -> String:
	if is_animal_key(item):
		return str(Farming.ANIMALS[item.substr(2)].plural).capitalize()
	if item in CROP_ITEMS:
		return str(Farming.CROPS[item if item != "carrot" else "carrot"].label)
	return item.capitalize()


## Buy or sell goods and crops. Returns {ok, message}. Crops can only be sold from what has been harvested.
static func trade(sim: LifeSim, action: String, item: String, amount: int) -> Dictionary:
	if item in CROP_ITEMS:
		return _trade_crop(sim, action, item, amount)
	if item not in GOODS or amount <= 0:
		return {"ok": false, "message": "Trade food, wood, stone, a crop, or livestock."}
	var unit := price(sim, item)
	var cut := spread(sim)
	if action == "sell":
		var n := mini(amount, stock_of(sim, item))
		if n <= 0:
			return {"ok": false, "message": "There is no %s to sell." % item}
		var earned := int(round(float(n) * unit * (1.0 - cut) * Caravans.route_bonus(sim)))
		match item:
			"food": sim.food -= n
			"wood": sim.wood -= n
			"stone": sim.stone -= n
			"medicine": sim.medicine -= n
		sim.money += earned
		return {"ok": true, "message": "Sold %d %s for %d coins (%.2f each)." % [n, item, earned, unit * (1.0 - cut)]}
	var cost_each := unit * (1.0 + cut)
	var affordable := mini(amount, int(floor(float(sim.money) / cost_each)))
	if affordable <= 0:
		return {"ok": false, "message": "Not enough coins: %s costs %.2f each." % [item, cost_each]}
	var cost := int(ceil(float(affordable) * cost_each))
	sim.money -= cost
	match item:
		"food": sim.food += affordable
		"wood": sim.wood += affordable
		"stone": sim.stone += affordable
		"medicine": sim.medicine += affordable
	return {"ok": true, "message": "Bought %d %s for %d coins (%.2f each)." % [affordable, item, cost, cost_each]}


static func _trade_crop(sim: LifeSim, action: String, crop: String, amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "message": "How many?"}
	var unit := price(sim, crop)
	var cut := spread(sim)
	var name_ := str(Farming.CROPS[crop].label).to_lower()
	if action == "sell":
		var n := mini(amount, stock_of(sim, crop))
		if n <= 0:
			return {"ok": false, "message": "No %s have been harvested to sell." % name_}
		var earned := int(round(float(n) * unit * (1.0 - cut) * Caravans.route_bonus(sim)))
		sim.food -= n
		sim.harvested[crop] = maxi(0, int(sim.harvested.get(crop, 0)) - n)
		sim.money += earned
		return {"ok": true, "message": "Sold %d %s for %d coins (%.2f each)." % [n, name_, earned, unit * (1.0 - cut)]}
	var cost_each := unit * (1.0 + cut)
	var affordable := mini(amount, int(floor(float(sim.money) / cost_each)))
	if affordable <= 0:
		return {"ok": false, "message": "Not enough coins: %s cost %.2f each." % [name_, cost_each]}
	var cost := int(ceil(float(affordable) * cost_each))
	sim.money -= cost
	sim.food += affordable
	return {"ok": true, "message": "Bought %d %s for %d coins (%.2f each). They go into the larder." % [affordable, name_, cost, cost_each]}


## Sell livestock back to the market (adults fetch full price, young ones half). Buying goes through Farming.buy.
static func trade_animal(sim: LifeSim, action: String, kind: String, amount: int) -> Dictionary:
	if not Farming.ANIMALS.has(kind) or amount <= 0:
		return {"ok": false, "message": "Trade chickens, sheep, cows or pigs."}
	if action == "buy":
		return Farming.buy(sim, kind, amount)
	var sold := 0
	var earned := 0.0
	var unit := sell_price(sim, animal_key(kind))
	for pass_adults in [true, false]:
		for b in sim.buildings:
			if str(b.kind) != "farm":
				continue
			for a in Farming.animals_of(b).duplicate():
				if sold >= amount:
					break
				if str(a.kind) != kind or Farming.is_adult(a, sim.day()) != pass_adults:
					continue
				b.animals.erase(a)
				sold += 1
				earned += unit * (1.0 if pass_adults else 0.5)
	if sold == 0:
		return {"ok": false, "message": "There are no %s to sell." % Farming.ANIMALS[kind].plural}
	sim.money += int(round(earned))
	sim.push_fx({"type": "livestock"})
	return {"ok": true, "message": "Sold %d %s for %d coins." % [sold, Farming.ANIMALS[kind].plural if sold != 1 else str(Farming.ANIMALS[kind].label).to_lower(), int(round(earned))]}


# --- events -------------------------------------------------------------------------------------------------

static func _announce(sim: LifeSim, kind: String, text: String, days: int, mult: Dictionary = {}) -> void:
	sim.events.append({"kind": kind, "text": text, "until": sim.day() + days, "mult": mult})
	if sim.events.size() > 8:
		sim.events.pop_front()
	sim.notice(text)
	sim.log_event(text)


static func daily(sim: LifeSim) -> void:
	for crop in sim.harvested.keys():
		sim.harvested[crop] = int(float(sim.harvested[crop]) * 0.92)
	_wear(sim)
	_soil(sim)
	var keep: Array = []
	for e in sim.events:
		if sim.day() <= int(e.until):
			keep.append(e)
	sim.events = keep
	if sim.day() >= EVENT_GRACE_DAYS and sim.rng.randf() < 0.14:
		_random_event(sim)
	update_prices(sim)


static func _random_event(sim: LifeSim) -> void:
	var season := sim.season()
	var pool: Array = ["trader", "trader", "festival", "traveler", "inspiration"]
	if sim.day() >= Survival.GRACE_DAYS + 2:
		pool.append("wolf_pack")
	if sim.buildings.size() >= 8:
		pool.append("fire")
	if season in ["Summer", "Autumn"]:
		pool.append("blight")
	if season in ["Spring", "Autumn", "Winter"]:
		pool.append("storm")
	if season == "Summer":
		pool.append_array(["drought", "pests"])
	if season == "Winter":
		pool.append("sickness")
	if season in ["Spring", "Summer"]:
		pool.append("bumper")
	var kind: String = pool[sim.rng.randi() % pool.size()]
	match kind:
		"storm":
			_announce(sim, "storm", "A fierce storm has hit! Crops are flattened and roofs are damaged.", 6, {"food": 1.45, "wood": 1.2})
			for b in sim.buildings:
				b.condition = maxf(0.0, float(b.get("condition", 100.0)) - sim.rng.randf_range(8.0, 20.0))
				if b.kind == "farm":
					b.growth = minf(float(b.get("growth", 0.0)), 20.0)
		"drought":
			_announce(sim, "drought", "A dry spell is withering the fields. Food will get dearer.", 8, {"food": 1.35})
			for b in sim.buildings:
				if b.kind == "farm":
					b.growth = float(b.get("growth", 0.0)) * 0.5
		"pests":
			_announce(sim, "pests", "Pests are in the crops! Farmers should tend the fields.", 6, {"food": 1.2})
			for b in sim.buildings:
				if b.kind == "farm" and int(b.level) >= 1:
					b.pests = true
		"bumper":
			_announce(sim, "bumper", "A bumper season! The fields are heavy with produce and prices fall.", 6, {"food": 0.7})
			for b in sim.buildings:
				if b.kind == "farm" and int(b.level) >= 1:
					b.growth = minf(100.0, float(b.get("growth", 0.0)) + 40.0)
		"festival":
			_announce(sim, "festival", "The villagers hold an impromptu feast. Spirits are high.", 2)
			for r in sim.residents:
				r.needs.fun = minf(100.0, float(r.needs.fun) + 20.0)
				r.needs.social = minf(100.0, float(r.needs.social) + 10.0)
				r.stress = maxf(0.0, float(r.stress) - 10.0)
		"sickness":
			_announce(sim, "sickness", "A travelling cough has reached the village.", 5)
			var sick := mini(2, sim.residents.size())
			for k in range(sick):
				Health.infect(sim, sim.rng.randi() % sim.residents.size(), "flu" if sim.rng.randf() < 0.4 else "cold")
		"wolf_pack":
			_announce(sim, "wolf_pack", "A pack of dire wolves has been seen near the village. Keep watch.", 3)
			var centre := Survival.village_centre(sim)
			var radius := Survival.village_radius(sim)
			for k in range(2 + sim.stage() / 2):
				Survival.spawn(sim, "wolf", Survival._random_outside(sim, centre, radius + 5.0, radius + 9.0))
		"fire":
			var target: Dictionary = sim.buildings[sim.rng.randi() % sim.buildings.size()]
			if str(target.kind) != "plaza" and int(target.level) >= 1:
				target.condition = maxf(0.0, float(target.get("condition", 100.0)) - 40.0)
				_announce(sim, "fire", "A fire broke out at the %s! It is badly scorched." % Catalog.label(str(target.kind)).to_lower(), 2)
				for r in sim.residents:
					r.stress = minf(100.0, float(r.stress) + 4.0)
		"blight":
			_announce(sim, "blight", "A blight has spoiled part of the stores. Food prices rise.", 5, {"food": 1.25})
			sim.food = int(float(sim.food) * 0.8)
		"traveler":
			if sim.housing() > sim.residents.size() and sim._spawn_resident():
				sim.log_event("A weary traveller decided to stay.")
			else:
				_announce(sim, "traveler", "A traveller passed through but found no room to stay.", 1)
		"inspiration":
			_announce(sim, "inspiration", "A wave of inspiration sweeps the village. Everyone feels capable.", 2)
			for r in sim.residents:
				r.stress = maxf(0.0, float(r.stress) - 12.0)
				r.skills[Psyche.SKILLS[sim.rng.randi() % Psyche.SKILLS.size()]] += 6.0
		"trader":
			Caravans.arrive(sim)
			_announce(sim, "trader", "A trader's caravan is camped nearby: they pay well for timber and stone.", 3, {"wood": 1.25, "stone": 1.25})
			var sold := 0
			if sim.wood > 40:
				var surplus := sim.wood - 40
				sim.money += int(round(float(surplus) * price(sim, "wood") * 1.2))
				sim.wood -= surplus
				sold += surplus
			if sim.stone > 30:
				var extra := sim.stone - 30
				sim.money += int(round(float(extra) * price(sim, "stone") * 1.2))
				sim.stone -= extra
				sold += extra
			if sold > 0:
				sim.log_event("The trader bought %d surplus materials." % sold)


# --- maintenance -------------------------------------------------------------------------------------------------

static func efficiency(b: Dictionary) -> float:
	var c := float(b.get("condition", 100.0))
	if c < 15.0:
		return 0.4
	if c < 35.0:
		return 0.7
	return 1.0


static func _wear(sim: LifeSim) -> void:
	for b in sim.buildings:
		if int(b.level) < 1:
			continue
		var decay := DECAY_PER_DAY + (0.35 if sim.weather == "Rain" else 0.0) + (0.25 if sim.season() == "Winter" else 0.0)
		decay *= 0.9 + float(int(b.level)) * 0.05
		b.condition = maxf(0.0, float(b.get("condition", 100.0)) - decay)
		if float(b.condition) < 8.0 and int(b.level) > 1 and sim.rng.randf() < 0.15:
			b.level = int(b.level) - 1
			b.target = int(b.level)
			b.condition = 40.0
			sim.notice("The %s fell into such disrepair that part of it collapsed!" % Catalog.label(str(b.kind)).to_lower())
			sim.log_event("The %s collapsed to level %d from neglect." % [Catalog.label(str(b.kind)).to_lower(), int(b.level)])


static func worst_building(sim: LifeSim, below: float) -> Dictionary:
	var worst := {}
	var low := below
	for b in sim.buildings:
		if int(b.level) < 1 or str(b.kind) == "plaza":
			continue
		var c := float(b.get("condition", 100.0))
		if c < low:
			low = c
			worst = b
	return worst


static func repair(sim: LifeSim, b: Dictionary, skill: float) -> String:
	if sim.materials() < REPAIR_COST:
		return "There aren't enough materials to repair the %s." % Catalog.label(str(b.kind)).to_lower()
	sim.spend_materials(maxi(1, REPAIR_COST - (1 if sim.tools else 0)))
	if bool(b.get("breached", false)):
		b.breached = false
		b.condition = maxf(float(b.get("condition", 0.0)), 35.0)
	b.condition = minf(100.0, float(b.get("condition", 100.0)) + 40.0 + skill / 4.0)
	return "Repaired the %s." % Catalog.label(str(b.kind)).to_lower()


# --- soil ---------------------------------------------------------------------------------------------------------

static func _soil(sim: LifeSim) -> void:
	for b in sim.buildings:
		if b.kind == "farm":
			b.soil = minf(100.0, float(b.get("soil", 100.0)) + (2.5 if sim.weather == "Rain" else 1.2))


static func yield_factor(b: Dictionary) -> float:
	var f := 0.55 + float(b.get("soil", 100.0)) / 220.0
	if bool(b.get("pests", false)):
		f *= 0.6
	return f
