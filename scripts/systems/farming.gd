class_name Farming
extends RefCounted
## Crops and livestock on the farms. Each farm grows one crop (wheat, carrots, corn or pumpkins) with its own
## growing speed, yield and winter hardiness, and keeps animals in a pen: chickens lay eggs, sheep give wool,
## cows give milk, pigs are raised for meat. Animals are born small, grow up, breed when there is room and
## food, go hungry when the larder is empty, and attract wolves. Residents tending the farm feed the animals
## (a hand-fed day costs the larder nothing) and collect what they produced.

const CROPS := {
	"wheat": {"label": "Wheat", "grow": 1.0, "yield": 1.0, "winter": 0.35, "model": "crops_wheatStageB"},
	"carrot": {"label": "Carrots", "grow": 1.3, "yield": 0.8, "winter": 0.8, "model": "crop_carrot"},
	"corn": {"label": "Corn", "grow": 0.85, "yield": 1.3, "winter": 0.1, "model": "crops_cornStageD"},
	"pumpkin": {"label": "Pumpkins", "grow": 0.7, "yield": 1.7, "winter": 0.0, "model": "crop_pumpkin"},
	"melon": {"label": "Melons", "grow": 0.75, "yield": 1.9, "winter": 0.0, "model": "crop_melon"},
}
const ANIMALS := {
	"chicken": {"label": "Chicken", "plural": "chickens", "cost": 12, "slots": 1, "adult_days": 3, "product": "eggs", "rate": 1.0, "meat": 3},
	"sheep": {"label": "Sheep", "plural": "sheep", "cost": 30, "slots": 2, "adult_days": 5, "product": "wool", "rate": 0.34, "meat": 6},
	"cow": {"label": "Cow", "plural": "cows", "cost": 60, "slots": 3, "adult_days": 6, "product": "milk", "rate": 0.8, "meat": 12},
	"pig": {"label": "Pig", "plural": "pigs", "cost": 25, "slots": 2, "adult_days": 5, "product": "", "rate": 0.0, "meat": 8},
}
const PRODUCT_VALUE := {"eggs": 1, "milk": 2}
const WOOL_COINS := 4
const SLOTS_BY_LEVEL := [5, 9, 14]
const STARVE_DAYS := 3
const PRODUCE_CAP := 12
const BREED_CHANCE := 0.16
const FEED_PER_SLOT := 0.2


static func crop_of(b: Dictionary) -> String:
	var c := str(b.get("crop", "wheat"))
	return c if CROPS.has(c) else "wheat"


static func animals_of(b: Dictionary) -> Array:
	return b.get("animals", []) if b.get("animals", []) is Array else []


static func produce_of(b: Dictionary) -> Dictionary:
	var p: Variant = b.get("produce", {})
	return p if p is Dictionary else {}


static func slots_total(b: Dictionary) -> int:
	return SLOTS_BY_LEVEL[clampi(int(b.level) - 1, 0, SLOTS_BY_LEVEL.size() - 1)]


static func slots_used(b: Dictionary) -> int:
	var n := 0
	for a in animals_of(b):
		n += int(ANIMALS[str(a.kind)].slots)
	return n


static func is_adult(a: Dictionary, day: int) -> bool:
	return day - int(a.born) >= int(ANIMALS[str(a.kind)].adult_days)


static func count(b: Dictionary, kind: String = "", adults_only: bool = false, day: int = 0) -> int:
	var n := 0
	for a in animals_of(b):
		if (kind == "" or str(a.kind) == kind) and (not adults_only or is_adult(a, day)):
			n += 1
	return n


## Crop growth per minute of game time on this farm.
static func rate(b: Dictionary, season: String, weather: String) -> float:
	var spec: Dictionary = CROPS[crop_of(b)]
	var r := 0.09 * float(spec.grow)
	if season == "Winter":
		r *= float(spec.winter)
	if weather == "Rain":
		r *= 1.5
	if bool(b.get("pests", false)):
		r *= 0.5
	return r


static func total_animals(sim: LifeSim) -> int:
	var n := 0
	for b in sim.buildings:
		if str(b.kind) == "farm":
			n += animals_of(b).size()
	return n


## Does this farm have livestock work waiting?
static func needs_tending(sim: LifeSim, b: Dictionary) -> bool:
	if int(b.level) < 1 or str(b.kind) != "farm":
		return false
	var p := produce_of(b)
	var ready := int(p.get("eggs", 0)) + int(p.get("milk", 0)) + int(p.get("wool", 0))
	if ready >= 3:
		return true
	return not animals_of(b).is_empty() and (int(b.get("hungry", 0)) > 0 or float(b.get("hay", 0.0)) <= 0.0 and ready >= 1)


static func any_needs_tending(sim: LifeSim) -> bool:
	for b in sim.buildings:
		if needs_tending(sim, b):
			return true
	return false


# --- buying, breeding, selling ---------------------------------------------------------------------------------------

static func farm_with_room(sim: LifeSim, kind: String) -> Dictionary:
	var need := int(ANIMALS[kind].slots)
	var best := {}
	var best_free := -1
	for b in sim.buildings:
		if str(b.kind) != "farm" or int(b.level) < 1:
			continue
		var free := slots_total(b) - slots_used(b)
		if free >= need and free > best_free:
			best_free = free
			best = b
	return best


static func add_animal(sim: LifeSim, b: Dictionary, kind: String, born_day: int) -> Dictionary:
	if not b.get("animals", []) is Array:
		b.animals = []
	sim.animal_serial += 1
	var a := {"id": sim.animal_serial, "kind": kind, "born": born_day, "hungry": 0}
	b.animals.append(a)
	return a


## Buy up to `n` animals of a kind and house them. Returns {ok, message}.
static func buy(sim: LifeSim, kind: String, n: int) -> Dictionary:
	if not ANIMALS.has(kind):
		return {"ok": false, "message": "Raise chickens, sheep, cows or pigs."}
	var bought := 0
	var spent := 0
	var why := ""
	var cost := int(ceil(Economy.buy_price(sim, Economy.animal_key(kind))))
	for i in range(maxi(1, n)):
		if sim.money < cost:
			why = "Not enough coins (%d each)." % cost
			break
		var farm := farm_with_room(sim, kind)
		if farm.is_empty():
			why = "No farm has room for another %s. Upgrade a farm or build one." % str(ANIMALS[kind].label).to_lower()
			break
		sim.money -= cost
		spent += cost
		add_animal(sim, farm, kind, sim.day() - int(ANIMALS[kind].adult_days))
		bought += 1
	if bought == 0:
		return {"ok": false, "message": why if why != "" else "No farms yet."}
	sim.log_event("Bought %d %s for %d coins." % [bought, ANIMALS[kind].plural if bought != 1 else str(ANIMALS[kind].label).to_lower(), spent])
	sim.push_fx({"type": "livestock"})
	return {"ok": true, "message": "Bought %d %s for %d coins%s." % [bought, ANIMALS[kind].plural if bought != 1 else str(ANIMALS[kind].label).to_lower(), spent, "" if bought == n or why == "" else " (" + why + ")"]}


## Butcher adult animals of a kind. Returns {ok, message}.
static func slaughter(sim: LifeSim, kind: String, n: int) -> Dictionary:
	if not ANIMALS.has(kind):
		return {"ok": false, "message": "Say which animal: chickens, sheep, cows or pigs."}
	var done := 0
	var meat := 0
	for b in sim.buildings:
		if str(b.kind) != "farm":
			continue
		for a in animals_of(b).duplicate():
			if done >= maxi(1, n):
				break
			if str(a.kind) == kind and is_adult(a, sim.day()):
				b.animals.erase(a)
				done += 1
				meat += int(ANIMALS[kind].meat)
	if done == 0:
		return {"ok": false, "message": "There are no grown %s to butcher." % ANIMALS[kind].plural}
	sim.food += meat
	sim.push_fx({"type": "livestock"})
	return {"ok": true, "message": "Butchered %d %s for %d food." % [done, ANIMALS[kind].plural, meat]}


## Switch every farm to another crop. Fields that were growing start over.
static func set_crop(sim: LifeSim, crop: String) -> Dictionary:
	if not CROPS.has(crop):
		return {"ok": false, "message": "Plant wheat, carrots, corn or pumpkins."}
	if crop not in sim.crops_unlocked:
		return {"ok": false, "message": "The village has no melon seeds yet. A travelling merchant may sell some."}
	var changed := 0
	var total := 0
	for b in sim.buildings:
		if str(b.kind) == "farm" and int(b.level) >= 1:
			total += 1
			if crop_of(b) != crop:
				b.crop = crop
				b.growth = 0.0
				changed += 1
	if total == 0:
		return {"ok": false, "message": "There are no farms yet."}
	if changed == 0:
		return {"ok": false, "message": "The fields already grow %s." % str(CROPS[crop].label).to_lower()}
	sim.log_event("The fields are replanted with %s." % str(CROPS[crop].label).to_lower())
	return {"ok": true, "message": "%d field%s replanted with %s." % [changed, "" if changed == 1 else "s", str(CROPS[crop].label).to_lower()]}


# --- the day's work ----------------------------------------------------------------------------------------------------

## A resident tends a farm: feeds the animals by hand and gathers what they made. Returns a short message.
static func tend(sim: LifeSim, b: Dictionary) -> String:
	var notes: Array = []
	if not animals_of(b).is_empty():
		b.hay = 1.0
		b.hungry = 0
		for a in animals_of(b):
			a.hungry = 0
		notes.append("fed the animals")
	var p := produce_of(b)
	var eggs := int(p.get("eggs", 0))
	var milk := int(p.get("milk", 0))
	var wool := int(p.get("wool", 0))
	if eggs + milk + wool > 0:
		sim.food += eggs * int(PRODUCT_VALUE.eggs) + milk * int(PRODUCT_VALUE.milk)
		sim.money += int(round(float(wool) * Economy.price(sim, "wool")))
		var got: Array = []
		if eggs > 0:
			got.append("%d egg%s" % [eggs, "" if eggs == 1 else "s"])
		if milk > 0:
			got.append("%d milk" % milk)
		if wool > 0:
			got.append("%d wool" % wool)
		notes.append("collected " + ", ".join(got))
		b.produce = {"eggs": 0, "milk": 0, "wool": 0}
	return ("Tended the farm: " + ", ".join(notes) + ".") if not notes.is_empty() else ""


static func daily(sim: LifeSim) -> void:
	var day := sim.day()
	for b in sim.buildings:
		if str(b.kind) != "farm" or int(b.level) < 1:
			continue
		var herd := animals_of(b)
		if herd.is_empty():
			continue
		# Feeding: a hand-fed day is free, otherwise the animals eat from the larder.
		var need := int(ceil(float(slots_used(b)) * FEED_PER_SLOT))
		var fed := false
		if float(b.get("hay", 0.0)) > 0.0:
			fed = true
			b.hay = 0.0
		elif sim.food >= need:
			sim.food -= need
			fed = true
		for a in herd.duplicate():
			if fed:
				a.hungry = 0
			else:
				a.hungry = int(a.get("hungry", 0)) + 1
				if int(a.hungry) >= STARVE_DAYS:
					b.animals.erase(a)
					sim.notice("A %s starved at the farm. Keep the larder stocked." % str(a.kind))
					sim.log_event("A %s starved at the farm." % str(a.kind))
		b.hungry = 0 if fed else 1
		# Produce.
		if not b.get("produce", {}) is Dictionary or (b.produce as Dictionary).is_empty():
			b.produce = {"eggs": 0, "milk": 0, "wool": 0}
		if fed:
			for a in animals_of(b):
				if not is_adult(a, day):
					continue
				var spec: Dictionary = ANIMALS[str(a.kind)]
				if str(spec.product) == "":
					continue
				var amount := float(spec.rate) * (2.0 if str(a.get("breed", "")) == "prize" else 1.0)
				var whole := int(floor(amount))
				if sim.rng.randf() < amount - float(whole):
					whole += 1
				b.produce[spec.product] = mini(PRODUCE_CAP, int(b.produce.get(spec.product, 0)) + whole)
		# Breeding.
		if fed:
			for kind in ANIMALS:
				var adults := count(b, kind, true, day)
				if adults >= 2 and slots_total(b) - slots_used(b) >= int(ANIMALS[kind].slots) and sim.rng.randf() < BREED_CHANCE:
					add_animal(sim, b, kind, day)
					sim.log_event("A baby %s was born at the farm." % kind)
					sim.push_fx({"type": "livestock"})


## The council restocks the pens when the village is short of food and has coins to spare.
static func council(sim: LifeSim) -> void:
	if sim.money < 220:
		return
	var pop := sim.residents.size()
	var larder := sim.food + sim.meals * 2
	if larder > pop * 14:
		return
	for kind in ["chicken", "sheep", "cow", "pig"]:
		if sim.rng.randf() > 0.35:
			continue
		var herd := 0
		for b in sim.buildings:
			if str(b.kind) == "farm":
				herd += count(b, kind)
		var want := {"chicken": maxi(2, pop / 3), "sheep": maxi(1, pop / 7), "cow": maxi(1, pop / 9), "pig": maxi(0, pop / 12)}[kind] as int
		if herd < want and sim.money >= int(ceil(Economy.buy_price(sim, Economy.animal_key(kind)))) + 120:
			var res := buy(sim, kind, 1)
			if bool(res.ok):
				sim.notice("The council bought a %s for the farm." % kind)
				return


# --- predators -------------------------------------------------------------------------------------------------------------

## A wolf near a farm may take an animal if nobody is around to stop it and no wall is in the way.
static func raid(sim: LifeSim, mob: Dictionary, dm: float) -> bool:
	var pos := Vector2(float(mob.pos[0]), float(mob.pos[1]))
	for b in sim.buildings:
		if str(b.kind) != "farm" or int(b.level) < 1 or animals_of(b).is_empty():
			continue
		var at := Vector2(float(b.tile[0]), float(b.tile[1]))
		if pos.distance_to(at) > 2.4 or not Walls.crossing(sim, pos, at).is_empty():
			continue
		mob.raid_cd = float(mob.get("raid_cd", 0.0)) - dm
		if float(mob.raid_cd) > 0.0:
			return true
		mob.raid_cd = 25.0
		var victim: Dictionary = animals_of(b)[sim.rng.randi() % animals_of(b).size()]
		b.animals.erase(victim)
		sim.notice("A wolf killed a %s at the farm!" % str(victim.kind))
		sim.log_event("A wolf took a %s from the farm." % str(victim.kind))
		sim.push_fx({"type": "livestock"})
		return true
	return false


## Where a hungry wolf heads when nothing else tempts it: the nearest farm with animals.
static func nearest_prey_farm(sim: LifeSim, from: Vector2, within: float) -> Vector2:
	var best := Vector2(1.0e9, 1.0e9)
	var best_d := within
	for b in sim.buildings:
		if str(b.kind) != "farm" or int(b.level) < 1 or animals_of(b).is_empty():
			continue
		var at := Vector2(float(b.tile[0]), float(b.tile[1]))
		var d := from.distance_to(at)
		if d < best_d:
			best_d = d
			best = at
	return best
