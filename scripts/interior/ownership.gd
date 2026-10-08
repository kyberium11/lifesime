class_name Ownership
extends RefCounted
## Who owns what. Every resident has their own bed and a few personal things in the house they live in
## (armchair, bedside table, lamp, desk...), and a workstation in the place they work. Owners use their own
## things, take pride in them (a comfortable home helps sleep and calms stress), and mind when others use them.
## Possessions pass to the family when someone dies, and the chief can furnish a home or give a gift.

const TRESPASS_STRESS := 3.0


## Residents who live in this home, eldest first.
static func occupants(sim: LifeSim, b: Dictionary) -> Array:
	var names: Array = []
	for r in sim.residents:
		if int(r.home) == int(b.id):
			names.append(r)
	names.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.age) > int(y.age))
	return names.map(func(r: Dictionary) -> String: return str(r.name))


static func resident_exists(sim: LifeSim, name_: String) -> bool:
	return sim.index_of(name_) >= 0


## May this person use this item without it being a trespass? Owners, their partner and family, and close friends may.
static func may_use(sim: LifeSim, who: String, it: Dictionary) -> bool:
	var owners: Array = it.owners
	if owners.is_empty() or who == "" or who in owners:
		return true
	var user := sim.index_of(who)
	if user < 0:
		return true
	var me: Dictionary = sim.residents[user]
	for o in owners:
		var oi := sim.index_of(str(o))
		if oi < 0:
			continue
		var owner: Dictionary = sim.residents[oi]
		if str(me.partner) == str(o) or str(o) in me.parents or str(o) in me.children or str(me.name) in owner.parents:
			return true
		if sim.relation(owner, who) >= 60.0:
			return true
	return false


## Hand out the personal things of a home to the people who live there, and drop owners who no longer do.
static func refresh(sim: LifeSim, b: Dictionary) -> void:
	var items := Interiors.furniture_of(b)
	if items.is_empty():
		return
	if str(b.kind) == "home":
		var live := occupants(sim, b)
		for it in items:
			var kept: Array = []
			for o in it.owners:
				if o in live:
					kept.append(o)
			it.owners = kept
		# Beds first: a bed per person, couples share a double bed or bunk.
		for name_ in live:
			if _owns_role(items, name_, "bed"):
				continue
			var r: Dictionary = sim.residents[sim.index_of(name_)]
			var spot := {}
			var partner := str(r.partner)
			for it in items:
				if str(it.role) != "bed":
					continue
				var slots := int(FurnitureDb.spec(str(it.model)).get("slots", 1))
				if it.owners.size() >= slots:
					continue
				if not it.owners.is_empty() and partner != "" and partner in it.owners:
					spot = it
					break
				if it.owners.is_empty() and spot.is_empty():
					spot = it
			if not spot.is_empty():
				spot.owners.append(name_)
		# Then the other personal belongings, spread round the household.
		var turn := 0
		for it in items:
			if str(it.role) == "bed" or not FurnitureDb.is_personal(str(it.model)) or not it.owners.is_empty() or live.is_empty():
				continue
			it.owners = [live[turn % live.size()]]
			turn += 1
	else:
		var live_names := {}
		for r in sim.residents:
			live_names[str(r.name)] = true
		for it in items:
			var kept2: Array = []
			for o in it.owners:
				if live_names.has(o):
					kept2.append(o)
			it.owners = kept2


static func _owns_role(items: Array, name_: String, role: String) -> bool:
	for it in items:
		if str(it.role) == role and name_ in it.owners:
			return true
	return false


## A worker takes the station they use as their own, if one is free.
static func claim_station(sim: LifeSim, b: Dictionary, who: String) -> Dictionary:
	if str(b.kind) == "home" or who == "":
		return {}
	Interiors.ensure(sim, b)
	var items := Interiors.furniture_of(b)
	for it in items:
		if who in it.owners and str(it.role) in ["desk", "bench_work", "counter", "computer"]:
			return it
	for it in items:
		if str(it.role) in ["desk", "bench_work", "counter"] and it.owners.is_empty():
			it.owners = [who]
			return it
	return {}


static func items_owned_by(sim: LifeSim, name_: String) -> Array:
	var out: Array = []
	for b in sim.buildings:
		for it in Interiors.furniture_of(b):
			if name_ in it.owners:
				out.append({"building": int(b.id), "kind": str(b.kind), "item": it})
	return out


## "a bed, an armchair and 3 more things": for Mind tab and prompts.
static func summary(sim: LifeSim, name_: String) -> String:
	var owned := items_owned_by(sim, name_)
	if owned.is_empty():
		return ""
	var names: Array = []
	var seen := {}
	for o in owned:
		var label := FurnitureDb.label_of(str(o.item.model)).to_lower()
		if not seen.has(label):
			seen[label] = 0
		seen[label] = int(seen[label]) + 1
	for label in seen:
		names.append(label if int(seen[label]) == 1 else "%d %s" % [seen[label], label])
	return ", ".join(names.slice(0, 6)) + (" and more" if names.size() > 6 else "")


## How comfortable a building is, from everything in it.
static func comfort(b: Dictionary) -> int:
	var total := 0
	for it in Interiors.furniture_of(b):
		total += FurnitureDb.comfort_of(str(it.model))
	return total


## Sleeping and resting are better in a comfortable home, and best in your own bed.
static func rest_mult(sim: LifeSim, r: Dictionary) -> float:
	var home := sim.building_by_id(int(r.home))
	if home.is_empty():
		return 1.0
	var bonus := minf(0.35, float(comfort(home)) / 120.0)
	if _owns_role(Interiors.furniture_of(home), str(r.name), "bed"):
		bonus += 0.08
	return 1.0 + bonus


static func value_owned(sim: LifeSim, name_: String) -> int:
	var total := 0
	for o in items_owned_by(sim, name_):
		total += FurnitureDb.comfort_of(str(o.item.model)) + 1
	return total


static func daily(sim: LifeSim) -> void:
	for b in sim.buildings:
		if Interiors.enterable(b):
			Interiors.ensure(sim, b)
			refresh(sim, b)
	# Pride in your own things: a few possessions calm the mind a little each day.
	for r in sim.residents:
		var pride := minf(3.5, float(value_owned(sim, str(r.name))) / 12.0)
		r.stress = maxf(0.0, float(r.stress) - pride)


## When someone dies their things go to their partner or children (or become shared).
static func on_death(sim: LifeSim, name_: String) -> void:
	var r_index := sim.index_of(name_)
	var heirs: Array = []
	if r_index >= 0:
		var r: Dictionary = sim.residents[r_index]
		if str(r.partner) != "":
			heirs.append(str(r.partner))
		for c in r.children:
			heirs.append(str(c))
	var passed := 0
	for b in sim.buildings:
		for it in Interiors.furniture_of(b):
			if name_ in it.owners:
				it.owners.erase(name_)
				for h in heirs:
					if resident_exists(sim, h) and it.owners.is_empty() and int(sim.residents[sim.index_of(h)].home) == int(b.id):
						it.owners.append(h)
						passed += 1
						break
	if passed > 0:
		sim.log_event("%d of %s's belongings passed to the family." % [passed, name_])


## Buy furniture for a building and place it. Personal items go to `owner_name` (if given). Returns {ok, message, item}.
static func furnish(sim: LifeSim, b: Dictionary, model: String, owner_name: String = "") -> Dictionary:
	if not FurnitureDb.ITEMS.has(model) or b.is_empty() or not Interiors.enterable(b):
		return {"ok": false, "message": "Nothing to furnish."}
	Interiors.ensure(sim, b)
	var price := FurnitureDb.price_of(model)
	if sim.money < price:
		return {"ok": false, "message": "%s costs %d coins." % [FurnitureDb.label_of(model), price]}
	var owners: Array = [owner_name] if (owner_name != "" and FurnitureDb.is_personal(model)) else []
	var placed := Interiors.place_auto(sim, b, model, owners, false)
	if placed.is_empty():
		return {"ok": false, "message": "There is no room left for a %s." % FurnitureDb.label_of(model).to_lower()}
	sim.money -= price
	sim.push_fx({"type": "furnished", "building": int(b.id)})
	return {"ok": true, "message": "Bought a %s (%d coins)%s." % [FurnitureDb.label_of(model).to_lower(), price, " for " + owner_name if not owners.is_empty() else ""], "item": placed}


## Buy a piece of furniture for a resident's home. Returns {ok, message}.
static func gift(sim: LifeSim, model: String, index: int) -> Dictionary:
	if not FurnitureDb.ITEMS.has(model) or index < 0 or index >= sim.residents.size():
		return {"ok": false, "message": "Choose a piece of furniture and a resident."}
	var r: Dictionary = sim.residents[index]
	var home := sim.building_by_id(int(r.home))
	if home.is_empty() or int(home.level) < 1:
		return {"ok": false, "message": "%s has no home to put it in." % r.name}
	Interiors.ensure(sim, home)
	var price := FurnitureDb.price_of(model)
	if sim.money < price:
		return {"ok": false, "message": "%s costs %d coins." % [FurnitureDb.label_of(model), price]}
	var owners: Array = [str(r.name)] if FurnitureDb.is_personal(model) else []
	var placed := Interiors.place_auto(sim, home, model, owners, false)
	if placed.is_empty():
		return {"ok": false, "message": "There is no room for it in %s's home." % r.name}
	sim.money -= price
	r.bond = minf(100.0, float(r.bond) + 2.0 + float(price) / 25.0)
	r.needs.fun = minf(100.0, float(r.needs.fun) + 6.0 + float(price) / 15.0)
	r.stress = maxf(0.0, float(r.stress) - 3.0)
	var line := Social.pick(["Oh! A %s, just for me? Thank you, Chief." % FurnitureDb.label_of(model).to_lower(), "I love it. It's going right here.", "You shouldn't have, Chief. It's perfect."], sim.rng)
	sim.say(index, line)
	sim.emote(index, "heart", 0.2)
	sim.remember(r, "Day %d: The chief gave me a %s for my home." % [sim.day(), FurnitureDb.label_of(model).to_lower()])
	sim.log_event("The chief gave %s a %s." % [r.name, FurnitureDb.label_of(model).to_lower()])
	sim.push_fx({"type": "furnished", "building": int(home.id)})
	return {"ok": true, "message": "Gave %s a %s (%d coins)." % [r.name, FurnitureDb.label_of(model).to_lower(), price], "item": placed}


## The chief uses a resident's belongings. Returns the reaction text ("" if nobody minds).
static func chief_uses(sim: LifeSim, b: Dictionary, it: Dictionary) -> String:
	var owners: Array = it.owners
	if owners.is_empty():
		return ""
	var owner_name := str(owners[0])
	var oi := sim.index_of(owner_name)
	if oi < 0:
		return ""
	var owner: Dictionary = sim.residents[oi]
	# Residents who are inside and awake notice; trusting ones joke about it, others mind.
	var trust := float(owner.bond)
	if trust >= 40.0:
		sim.say(oi, Social.pick(["Make yourself at home, Chief. That's my %s, but you are welcome." % FurnitureDb.label_of(str(it.model)).to_lower(), "Ha, comfortable, Chief? It's my %s." % FurnitureDb.label_of(str(it.model)).to_lower()], sim.rng))
		owner.bond = minf(100.0, float(owner.bond) + 0.6)
		return "%s doesn't mind." % owner_name
	sim.say(oi, Social.pick(["Chief, that's my %s..." % FurnitureDb.label_of(str(it.model)).to_lower(), "Er, that's mine, Chief."], sim.rng))
	owner.stress = minf(100.0, float(owner.stress) + TRESPASS_STRESS)
	owner.bond = maxf(0.0, float(owner.bond) - 0.8)
	return "%s minds that you used their %s." % [owner_name, FurnitureDb.label_of(str(it.model)).to_lower()]
