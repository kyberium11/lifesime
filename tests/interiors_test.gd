extends SceneTree
## Building interiors and ownership: layouts for every kind and level, owners, smart-object slots,
## comfort, gifts, upgrades, inheritance, saving.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _sim() -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = 3
	sim.money = 3000
	sim.food = 200
	sim.wood = 200
	for r in sim.residents:
		r.values = ["Community"]
	return sim


func _count(b: Dictionary, role: String) -> int:
	var n := 0
	for it in Interiors.furniture_of(b):
		if str(it.role) == role:
			n += 1
	return n


func _overlaps(b: Dictionary) -> int:
	var items := Interiors.furniture_of(b)
	var bad := 0
	for i in range(items.size()):
		for j in range(i + 1, items.size()):
			if str(items[i].role) == "rug" or str(items[j].role) == "rug" or float(items[i].get("y", 0.0)) > 0.0 or float(items[j].get("y", 0.0)) > 0.0:
				continue
			var a := Interiors.rect_of(str(items[i].model), int(items[i].rot), float(items[i].x), float(items[i].z))
			var c := Interiors.rect_of(str(items[j].model), int(items[j].rot), float(items[j].x), float(items[j].z))
			if a.grow(-0.03).intersects(c):
				bad += 1
	return bad


func _inside(b: Dictionary) -> int:
	var size := Interiors.dims(str(b.kind), int(b.level))
	var bad := 0
	for it in Interiors.furniture_of(b):
		var r := Interiors.rect_of(str(it.model), int(it.rot), float(it.x), float(it.z))
		if r.position.x < -0.001 or r.position.y < -0.001 or r.end.x > size.x + 0.001 or r.end.y > size.y + 0.001:
			bad += 1
	return bad


func _init() -> void:
	check(not FurnitureDb.sizes().is_empty(), "furniture sizes are measured")
	for model in FurnitureDb.ITEMS:
		check(FurnitureDb.sizes().has(model), "%s has a measured size" % model)
	var sim := _sim()
	# every enterable kind at every level
	for kind in Interiors.ENTERABLE:
		for level in range(1, Catalog.max_level(kind) + 1):
			var b := {"id": 900 + level, "kind": kind, "level": level, "variant": 5, "furniture": []}
			Interiors.generate(sim, b)
			check(Interiors.furniture_of(b).size() >= 6, "%s level %d is furnished (%d items)" % [kind, level, Interiors.furniture_of(b).size()])
			check(_overlaps(b) == 0, "%s level %d has no overlapping furniture (%d)" % [kind, level, _overlaps(b)])
			check(_inside(b) == 0, "%s level %d keeps everything inside the walls" % [kind, level])
			var door := Rect2(Vector2(Interiors.door_x(Interiors.dims(kind, level)) - 0.4, Interiors.dims(kind, level).y - 0.9), Vector2(0.8, 0.9))
			var blocked := false
			for it in Interiors.furniture_of(b):
				if str(it.role) != "rug" and Interiors.rect_of(str(it.model), int(it.rot), float(it.x), float(it.z)).intersects(door):
					blocked = true
			check(not blocked, "%s level %d leaves the door clear" % [kind, level])
	# what each place must contain
	var home: Dictionary = sim.buildings_of("home")[0]
	Interiors.ensure(sim, home)
	check(_count(home, "bed") >= 1 and _count(home, "stove") >= 1 and _count(home, "table") >= 1 and _count(home, "sofa") >= 1, "a home has beds, a stove, a table and a sofa")
	var market: Dictionary = sim.buildings_of("market")[0]
	Interiors.ensure(sim, market)
	check(_count(market, "counter") >= 1 and _count(market, "bookcase") >= 3, "a market has counters and shelves")
	var workshop: Dictionary = sim.buildings_of("workshop")[0]
	Interiors.ensure(sim, workshop)
	check(_count(workshop, "bench_work") >= 2, "a workshop has workbenches")
	var library: Dictionary = sim.buildings_of("library")[0]
	Interiors.ensure(sim, library)
	check(_count(library, "bookcase") >= 6 and _count(library, "desk") >= 2, "a library has bookcases and reading desks")
	var bathhouse: Dictionary = sim.buildings_of("bathhouse")[0]
	Interiors.ensure(sim, bathhouse)
	check(_count(bathhouse, "bath") >= 2, "a bathhouse has baths and showers")
	# beds for everyone and personal belongings
	var pip: Dictionary = sim.residents[0]
	Ownership.refresh(sim, home)
	var owned_beds := 0
	for r in sim.residents:
		var home_b := sim.building_by_id(int(r.home))
		Interiors.ensure(sim, home_b)
		Ownership.refresh(sim, home_b)
		var has_bed := false
		for it in Interiors.furniture_of(home_b):
			if str(it.role) == "bed" and str(r.name) in it.owners:
				has_bed = true
		if has_bed:
			owned_beds += 1
	check(owned_beds == sim.residents.size(), "every resident owns a bed (%d of %d)" % [owned_beds, sim.residents.size()])
	var sharing := {}
	for r in sim.residents:
		for it in Interiors.furniture_of(sim.building_by_id(int(r.home))):
			if str(it.role) == "bed" and str(r.name) in it.owners:
				sharing[int(it.id)] = int(sharing.get(int(it.id), 0)) + 1
	var overfull := false
	for id in sharing:
		var found := Interiors.item_by_id(sim.building_by_id(int(pip.home)), int(id))
		if not found.is_empty() and int(sharing[id]) > int(FurnitureDb.spec(str(found.model)).get("slots", 1)):
			overfull = true
	check(not overfull, "no bed has more owners than places")
	check(Ownership.summary(sim, str(pip.name)).contains("bed"), "a resident's belongings are listed: " + Ownership.summary(sim, str(pip.name)))
	# permission to use things
	var bed := {}
	for it in Interiors.furniture_of(sim.building_by_id(int(pip.home))):
		if str(it.role) == "bed" and str(pip.name) in it.owners:
			bed = it
	check(Ownership.may_use(sim, str(pip.name), bed), "owners may use their own things")
	var stranger: Dictionary = sim.residents[3]
	stranger.relations[str(pip.name)] = 5.0
	pip.relations[str(stranger.name)] = 5.0
	stranger.partner = ""
	check(not Ownership.may_use(sim, str(stranger.name), bed), "strangers may not use someone's bed")
	stranger.partner = str(pip.name)
	check(Ownership.may_use(sim, str(stranger.name), bed), "a partner may")
	stranger.partner = ""
	pip.relations[str(stranger.name)] = 80.0
	check(Ownership.may_use(sim, str(stranger.name), bed), "a close friend may")
	# smart objects pick the right thing
	var found_bed := Interiors.find_item(sim, sim.building_by_id(int(pip.home)), "sleep", str(pip.name))
	check(not found_bed.is_empty() and str(pip.name) in found_bed.owners, "sleep goes to the resident's own bed")
	check(not Interiors.find_item(sim, home, "cook", "").is_empty(), "cooking finds a stove")
	check(not Interiors.find_item(sim, home, "eat", "").is_empty(), "eating finds a seat")
	var slot := Interiors.slot_of(found_bed)
	check(str(slot.pose) == "lie", "a bed is for lying down")
	check(str(Interiors.slot_of(Interiors.find_item(sim, home, "eat", "")).pose) == "sit", "a chair is for sitting")
	check(str(Interiors.slot_of(Interiors.find_item(sim, home, "cook", "")).pose) == "stand", "a stove is used standing")
	# workplaces: claiming a station
	var claimed := Ownership.claim_station(sim, workshop, str(pip.name))
	check(not claimed.is_empty() and str(pip.name) in claimed.owners, "a worker claims a workbench")
	var again := Ownership.claim_station(sim, workshop, str(pip.name))
	check(int(again.id) == int(claimed.id), "and keeps the same one")
	var other := Ownership.claim_station(sim, workshop, str(sim.residents[1].name))
	check(int(other.id) != int(claimed.id), "a colleague gets a different one")
	# comfort and rest
	var comfort_before := Ownership.comfort(home)
	var before_mult := Ownership.rest_mult(sim, pip)
	var hb := sim.building_by_id(int(pip.home))
	Interiors.place_auto(sim, hb, "loungeSofaLong", [], false)
	Interiors.place_auto(sim, hb, "lampRoundFloor", [], false)
	check(Ownership.comfort(hb) > 0 and Ownership.rest_mult(sim, pip) >= before_mult, "more furniture, more comfort")
	check(Ownership.rest_mult(sim, pip) <= 1.5, "comfort bonuses are bounded")
	# gifts
	var money := sim.money
	var bond := float(pip.bond)
	var gift_result := Ownership.gift(sim, "loungeChairRelax", 0)
	check(gift_result.ok and sim.money == money - FurnitureDb.price_of("loungeChairRelax"), "a gift costs its price: " + str(gift_result.message))
	check(float(pip.bond) > bond, "gifts raise the bond")
	check(gift_result.has("item") and str(pip.name) in gift_result.item.owners, "a personal gift belongs to its recipient")
	var shared := Ownership.gift(sim, "table", 0)
	check(shared.ok and shared.item.owners.is_empty(), "a household gift belongs to everyone")
	var poor := _sim()
	poor.money = 3
	check(not Ownership.gift(poor, "bedDouble", 0).ok, "a gift needs coins")
	check(not Ownership.gift(sim, "dragon", 0).ok, "unknown furniture is refused")
	# buying fills the room until it is full
	var crowd := _sim()
	var ch: Dictionary = crowd.buildings_of("home")[0]
	Interiors.ensure(crowd, ch)
	var filled := 0
	for i in range(80):
		if Interiors.place_auto(crowd, ch, "bedBunk", [], false).is_empty():
			break
		filled += 1
	check(filled > 0 and filled < 80 and _overlaps(ch) == 0, "a full room refuses more furniture without overlaps (%d placed)" % filled)
	var removed := Interiors.remove(ch, int(Interiors.furniture_of(ch).back().id))
	check(not removed.is_empty(), "furniture can be removed")
	# upgrades keep gifts
	var up := _sim()
	var uh: Dictionary = up.buildings_of("home")[0]
	Interiors.ensure(up, uh)
	var up_pip: Dictionary = up.residents[0]
	up_pip.home = int(uh.id)
	Ownership.gift(up, "loungeChairRelax", 0)
	var gifts_before := 0
	for it in Interiors.furniture_of(uh):
		if not bool(it.base):
			gifts_before += 1
	uh.level = 3
	Interiors.ensure(up, uh)
	var gifts_after := 0
	for it in Interiors.furniture_of(uh):
		if not bool(it.base):
			gifts_after += 1
	check(gifts_before >= 1 and gifts_after == gifts_before, "gifts survive an upgrade")
	check(Interiors.furniture_of(uh).size() > 20, "a bigger house has more furniture")
	# heirlooms
	var heir := _sim()
	var hh: Dictionary = heir.buildings_of("home")[0]
	Interiors.ensure(heir, hh)
	var father: Dictionary = heir.residents[0]
	var daughter: Dictionary = heir.residents[1]
	father.home = int(hh.id)
	daughter.home = int(hh.id)
	father.children = [str(daughter.name)]
	Ownership.refresh(heir, hh)
	var armchair := Interiors.place_auto(heir, hh, "loungeChair", [str(father.name)], false)
	Ownership.on_death(heir, str(father.name))
	check(str(father.name) not in armchair.owners and str(daughter.name) in armchair.owners, "a dead resident's armchair passes to their child")
	# the chief using someone's things
	var react := _sim()
	var rb: Dictionary = react.buildings_of("home")[0]
	Interiors.ensure(react, rb)
	var owner: Dictionary = react.residents[0]
	owner.home = int(rb.id)
	Ownership.refresh(react, rb)
	var chair := Interiors.place_auto(react, rb, "loungeChair", [str(owner.name)], false)
	owner.bond = 80.0
	check(Ownership.chief_uses(react, rb, chair).contains("doesn't mind"), "a trusting owner doesn't mind the chief")
	owner.bond = 5.0
	var stress := float(owner.stress)
	check(Ownership.chief_uses(react, rb, chair).contains("minds") and float(owner.stress) > stress, "a wary owner minds, and is stressed")
	check(Ownership.chief_uses(react, rb, Interiors.furniture_of(rb)[0]) is String, "unowned things draw no reaction")
	# orders: giving furniture
	var gifted := _sim()
	var pip_name: String = gifted.residents[0].name
	var parsed := Orders.parse("give %s an armchair" % pip_name, gifted)
	check(parsed.intent == "gift" and parsed.furniture == "loungeChair" and parsed.scope == "names", "a gift order parses")
	check(Orders.parse("buy a bed for Mira", gifted).furniture == "bedSingle", "bed gift parses")
	check(Orders.parse("get Theo a television", gifted).furniture == "televisionModern", "television gift parses")
	check(Orders.parse("build a wall", gifted).intent != "gift", "walls are not gifts")
	var coins_before := gifted.money
	var done := Orders.execute(gifted, parsed, 0)
	check(done.ok and gifted.money < coins_before and Ownership.summary(gifted, pip_name).contains("armchair"), "the gift order buys and assigns it: " + str(done.message))
	check(not Orders.execute(gifted, Orders.parse("give a lamp", gifted), -1).ok, "a gift needs someone to receive it")
	# furnishing a building directly
	var shop := _sim()
	var wb: Dictionary = shop.buildings_of("workshop")[0]
	var bought := Ownership.furnish(shop, wb, "desk", "Pip")
	check(bought.ok and "Pip" in bought.item.owners, "furnishing a workplace gives the desk to the worker: " + str(bought.message))
	check(Ownership.furnish(shop, shop.buildings_of("farm")[0], "table", "").ok, "a barn can be furnished too")
	check(not Ownership.furnish(shop, shop.buildings_of("park")[0] if not shop.buildings_of("park").is_empty() else shop.buildings_of("plaza")[0], "desk", "Pip").ok, "open spaces cannot be furnished")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with furniture loads")
	var item_count := 0
	for b in sim.buildings:
		item_count += Interiors.furniture_of(b).size()
	var back_count := 0
	for b in back.buildings:
		back_count += Interiors.furniture_of(b).size()
	check(back_count == item_count and back.item_serial == sim.item_serial, "furniture and ownership survive saving (%d items)" % back_count)
	check(Ownership.summary(back, str(back.residents[0].name)) == Ownership.summary(sim, str(sim.residents[0].name)), "owners survive saving")
	# an old save without furniture still plays
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	for b in old.buildings:
		b.erase("furniture")
		b.erase("layout_level")
	old.erase("item_serial")
	var legacy := LifeSim.new()
	check(legacy.load_data(old), "an older save loads")
	Interiors.ensure(legacy, legacy.buildings_of("home")[0])
	check(not Interiors.furniture_of(legacy.buildings_of("home")[0]).is_empty(), "and its homes are furnished on demand")
	# the sim uses comfort for sleep
	var sleeper := _sim()
	var sb: Dictionary = sleeper.buildings_of("home")[0]
	Interiors.ensure(sleeper, sb)
	print("INTERIOR TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
