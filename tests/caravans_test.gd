extends SceneTree
## Travelling merchants, their wares, trade routes, melons, steel tools, prize cows, and the camp.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	call_deferred("run")


func _sim(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 3000
	sim.food = 200
	sim.wood = 200
	sim.minutes = 6.0 * 1440.0
	sim.last_day = sim.day()
	for r in sim.residents:
		r.values = ["Community"]
	return sim


func run() -> void:
	var sim := _sim()
	check(not Caravans.present(sim) and Caravans.stock_of(sim, "c_spice") == 0, "no merchant to begin with")
	check(not Caravans.buy(sim, "c_spice", 1).ok, "you cannot buy from nobody")
	Caravans.arrive(sim)
	check(Caravans.present(sim) and sim.caravan.stock.size() >= 3, "a caravan arrives with wares (%s)" % str(sim.caravan.stock.keys()))
	check(sim.caravan.stock.has("c_medicine"), "it always carries medicine")
	var days := int(sim.caravan.until) - sim.day()
	check(days == Caravans.STAY_DAYS - 1, "it stays a few days")
	Caravans.arrive(sim)
	check(sim.caravan.stock.size() >= 3, "a second arrival does nothing while one is camped")
	# spending effects
	var fun := {}
	for r in sim.residents:
		r.needs.fun = 40.0
	sim.caravan.stock.c_spice = 3
	sim.caravan.prices.c_spice = 20
	var coins := sim.money
	var spice := Caravans.buy(sim, "c_spice", 2)
	check(spice.ok and sim.money == coins - 40 and sim.caravan.stock.c_spice == 1, "buying spices costs coins and uses stock: " + str(spice.message))
	check(float(sim.residents[0].needs.fun) > 40.0, "spices cheer the village")
	sim.caravan.stock.c_seeds = 1
	sim.caravan.prices.c_seeds = 70
	check(not Farming.set_crop(sim, "melon").ok, "melons can't be planted without seeds")
	check(Caravans.buy(sim, "c_seeds", 1).ok and "melon" in sim.crops_unlocked, "seeds unlock melons")
	check(Farming.set_crop(sim, "melon").ok and Farming.crop_of(sim.buildings_of("farm")[0]) == "melon", "and then they can be planted")
	check(Farming.rate({"crop": "melon"}, "Spring", "Clear") > 0.0 and Farming.rate({"crop": "melon"}, "Winter", "Clear") == 0.0, "melons grow in warm weather only")
	sim.caravan.stock.c_seeds = 1
	check(not Caravans.buy(sim, "c_seeds", 1).ok, "seeds are only worth buying once")
	sim.caravan.stock.c_tools = 1
	sim.caravan.prices.c_tools = 160
	check(not sim.tools and Caravans.buy(sim, "c_tools", 1).ok and sim.tools, "steel tools are bought for good")
	sim.caravan.stock.c_cow = 1
	sim.caravan.prices.c_cow = 150
	var farm: Dictionary = sim.buildings_of("farm")[0]
	check(Caravans.buy(sim, "c_cow", 1).ok and Farming.count(farm, "cow") == 1, "a prize cow joins the farm")
	var cow: Dictionary = Farming.animals_of(farm)[0]
	check(str(cow.breed) == "prize", "it is marked as a prize breed")
	var plain := _sim(2)
	var plain_farm: Dictionary = plain.buildings_of("farm")[0]
	Farming.add_animal(plain, plain_farm, "cow", -20)
	var prize := _sim(2)
	var prize_farm: Dictionary = prize.buildings_of("farm")[0]
	var pc := Farming.add_animal(prize, prize_farm, "cow", -20)
	pc.breed = "prize"
	var plain_milk := 0
	var prize_milk := 0
	for i in range(5):
		plain.minutes += 1440.0
		prize.minutes += 1440.0
		plain.food = 300
		prize.food = 300
		Farming.daily(plain)
		Farming.daily(prize)
	plain_milk = int(Farming.produce_of(plain_farm).milk)
	prize_milk = int(Farming.produce_of(prize_farm).milk)
	check(prize_milk > plain_milk, "a prize cow gives more milk (%d vs %d)" % [prize_milk, plain_milk])
	sim.caravan.stock.c_books = 2
	sim.caravan.prices.c_books = 70
	var knowledge := float(sim.residents[0].skills.knowledge)
	check(Caravans.buy(sim, "c_books", 1).ok and float(sim.residents[0].skills.knowledge) > knowledge, "rare books teach everyone")
	sim.caravan.stock.c_medicine = 4
	sim.caravan.prices.c_medicine = 7
	var meds := sim.medicine
	check(Caravans.buy(sim, "c_medicine", 2).ok and sim.medicine == meds + 6, "medicine fills the shelves")
	var poor := _sim(3)
	Caravans.arrive(poor)
	poor.money = 1
	var any_key: String = poor.caravan.stock.keys()[0]
	check(not Caravans.buy(poor, any_key, 1).ok, "you need coins to buy")
	# steel tools help the haulers and the menders
	var smith := _sim(4)
	smith.tools = true
	var wood_before := smith.wood
	smith.command(0, "chop")
	smith.last_day = smith.day()
	for i in range(1500):
		smith.tick(2.0)
		if (smith.residents[0].job as Dictionary).is_empty() and i > 20:
			break
	check(smith.wood >= wood_before + 4, "with steel tools a haul of timber is bigger (%d -> %d)" % [wood_before, smith.wood])
	# leaving
	var leave := _sim(5)
	Caravans.arrive(leave)
	leave.minutes += 5.0 * 1440.0
	leave.last_day = leave.day()
	Caravans.daily(leave)
	check(not Caravans.present(leave) or leave.caravan.is_empty(), "the caravan moves on after its stay")
	# the market is kinder while a merchant is in town, and along routes
	var kind := _sim(6)
	var spread := Economy.spread(kind)
	Caravans.arrive(kind)
	check(Economy.spread(kind) < spread, "the market's cut narrows while a caravan is in town")
	kind.stone = 40
	var no_route := kind.money
	Economy.trade(kind, "sell", "stone", 20)
	var gain_plain := kind.money - no_route
	kind.routes = 3
	kind.stone = 40
	var with_route := kind.money
	Economy.trade(kind, "sell", "stone", 20)
	var gain_route := kind.money - with_route
	check(gain_route > gain_plain, "trade routes raise what sales earn (%d vs %d)" % [gain_route, gain_plain])
	# routes cost more each time and stop at the top
	var routes := _sim(7)
	var paid := routes.money
	check(Caravans.open_route(routes).ok and routes.routes == 1 and routes.money == paid - Caravans.ROUTE_COST, "the first route costs the base price")
	paid = routes.money
	check(Caravans.open_route(routes).ok and routes.money == paid - Caravans.ROUTE_COST * 2, "the next costs double")
	Caravans.open_route(routes)
	check(not Caravans.open_route(routes).ok and routes.routes == Caravans.MAX_ROUTE, "there is a limit to routes")
	var rare_a := _sim(8)
	var rare_b := _sim(8)
	rare_b.routes = 3
	var chance_a := Caravans.arrival_chance(rare_a)
	check(Caravans.arrival_chance(rare_b) > chance_a, "caravans come more often along routes")
	var early := _sim(9)
	early.minutes = 2.0 * 1440.0
	check(Caravans.arrival_chance(early) == 0.0, "no caravans in the first days")
	# orders
	var o := _sim(10)
	check(Orders.parse("open a trade route", o).intent == "route", "route order parses")
	check(Orders.execute(o, Orders.parse("open a trade route", o), 0).ok and o.routes == 1, "route order is carried out")
	check(Orders.parse("what is the merchant selling", o).intent == "caravan_report", "merchant report parses")
	check(not Orders.execute(o, Orders.parse("what is the merchant selling", o), 0).message.is_empty(), "the report reads out")
	Caravans.arrive(o)
	o.caravan.stock.c_spice = 3
	o.caravan.prices.c_spice = 20
	var parsed := Orders.parse("buy 2 spices", o)
	check(parsed.intent == "caravan_buy" and parsed.ware == "c_spice" and int(parsed.amount) == 2, "buying from the caravan parses")
	check(Orders.execute(o, parsed, 0).ok and o.caravan.stock.c_spice == 1, "and is carried out")
	var o2 := _sim(11)
	check(Orders.parse("buy 2 spices", o2).intent != "caravan_buy", "with no merchant it is not a caravan order")
	# the panel shows the wares
	var panel := MarketPanel.new()
	panel.sim = o
	root.add_child(panel)
	await process_frame
	panel.visible = true
	panel.refresh()
	await process_frame
	check(panel._caravan_box.get_child_count() >= 3, "the market panel lists the merchant's wares (%d rows)" % panel._caravan_box.get_child_count())
	var seen: Array = []
	panel.traded.connect(func(action: String, item: String, amount: int) -> void: seen.append([action, item, amount]))
	panel._route_button.pressed.emit()
	check(seen.size() == 1 and seen[0][0] == "route", "the route button sends a route request")
	# the camp appears in the scene
	var s := _sim(12)
	var art := CityArt.new()
	root.add_child(art)
	art.generate(s)
	Caravans.arrive(s)
	for i in range(4):
		await process_frame
		art.sync(0, 0.016)
	check(art._caravan_node != null and art._caravan_node.get_child_count() > 15, "the camp is drawn outside the village")
	s.caravan = {}
	for i in range(4):
		await process_frame
		art.sync(0, 0.016)
	check(art._caravan_node == null, "and packed up when they leave")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with a caravan loads")
	check(back.tools and "melon" in back.crops_unlocked and back.routes == sim.routes and Caravans.present(back) == Caravans.present(sim), "merchant state survives saving")
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	old.erase("caravan")
	old.erase("routes")
	old.erase("crops_unlocked")
	old.erase("tools")
	var legacy := LifeSim.new()
	check(legacy.load_data(old) and "wheat" in legacy.crops_unlocked and not legacy.tools, "an older save loads with the defaults")
	print("CARAVAN TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
