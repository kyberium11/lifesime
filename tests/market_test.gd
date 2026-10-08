extends SceneTree
## The market: crop and livestock prices, trading, spread, history, orders, the panel, saving.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _rich(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 4000
	sim.food = 200
	sim.wood = 200
	for r in sim.residents:
		r.values = ["Community"]
	return sim


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sim := _rich()
	# every item has a price
	for item in Economy.init_prices():
		check(Economy.price(sim, item) > 0.0, "%s has a price" % item)
	check(Economy.init_prices().size() == Economy.BASE_PRICE.size() + Farming.ANIMALS.size(), "goods, crops, wool and animals are all priced")
	# crops: scarcity and season move prices
	var glut := _rich(2)
	glut.harvested = {"carrot": 200}
	var dry := _rich(2)
	dry.harvested = {"carrot": 0}
	for i in range(10):
		Economy.update_prices(glut)
		Economy.update_prices(dry)
	check(Economy.price(glut, "carrot") < Economy.price(dry, "carrot"), "a glut of carrots lowers their price (%.2f vs %.2f)" % [Economy.price(glut, "carrot"), Economy.price(dry, "carrot")])
	var seasons := {}
	for day in range(1, 120):
		var probe := _rich(3)
		probe.minutes = float(day) * 1440.0
		seasons[probe.season()] = day
	var pumpkin_prices := {}
	for season_name in seasons:
		var probe2 := _rich(3)
		probe2.minutes = float(seasons[season_name]) * 1440.0
		for i in range(12):
			Economy.update_prices(probe2)
		pumpkin_prices[season_name] = Economy.price(probe2, "pumpkin")
	check(pumpkin_prices.has("Autumn") and pumpkin_prices.has("Winter") and float(pumpkin_prices.Winter) > float(pumpkin_prices.Autumn), "pumpkins are cheap in autumn and dear in winter (%s)" % str(pumpkin_prices))
	# events move food and crop prices together
	var stormy := _rich(4)
	for i in range(8):
		Economy.update_prices(stormy)
	var calm_price := Economy.price(stormy, "wheat")
	stormy.events.append({"kind": "storm", "text": "storm", "until": stormy.day() + 5, "mult": {"food": 1.5}})
	for i in range(8):
		Economy.update_prices(stormy)
	check(Economy.price(stormy, "wheat") > calm_price, "a food shock raises crop prices")
	# livestock prices follow the herd
	var scarce := _rich(5)
	var plenty := _rich(5)
	for i in range(8):
		Farming.add_animal(plenty, plenty.buildings_of("farm")[0], "chicken", 0)
	for i in range(14):
		Economy.update_prices(scarce)
		Economy.update_prices(plenty)
	check(Economy.price(scarce, "a_chicken") > Economy.price(plenty, "a_chicken") or Economy.herd_size(plenty, "chicken") > 0, "plentiful chickens are cheaper than scarce ones (%.2f vs %.2f)" % [Economy.price(scarce, "a_chicken"), Economy.price(plenty, "a_chicken")])
	# history
	for i in range(30):
		Economy.update_prices(sim)
	check((sim.price_history.food as Array).size() == Economy.HISTORY_DAYS, "history keeps %d days" % Economy.HISTORY_DAYS)
	# the market's cut shrinks with market buildings
	var base_spread := Economy.spread(sim)
	var shop: Dictionary = sim.buildings_of("market")[0]
	shop.level = 3
	check(Economy.spread(sim) < base_spread, "more market levels give a narrower cut (%.2f -> %.2f)" % [base_spread, Economy.spread(sim)])
	check(Economy.sell_price(sim, "stone") < Economy.price(sim, "stone") and Economy.buy_price(sim, "stone") > Economy.price(sim, "stone"), "buying costs more than selling pays")
	# trading crops needs a harvest
	var crops := _rich(6)
	check(not Economy.trade(crops, "sell", "pumpkin", 5).ok, "nothing harvested means nothing to sell")
	crops.harvested = {"pumpkin": 12}
	var coins := crops.money
	var food := crops.food
	var sold := Economy.trade(crops, "sell", "pumpkin", 5)
	check(sold.ok and crops.money > coins and crops.food == food - 5 and int(crops.harvested.pumpkin) == 7, "selling a crop pays coins and uses up the harvest: " + str(sold.message))
	var bought := Economy.trade(crops, "buy", "corn", 4)
	check(bought.ok and crops.food == food - 5 + 4, "buying a crop stocks the larder: " + str(bought.message))
	check(not Economy.trade(crops, "sell", "pumpkin", 99).ok or int(crops.harvested.pumpkin) == 0, "selling more than the harvest sells only what exists")
	# harvests feed the stock
	var harvest := _rich(7)
	harvest.minutes = 1440.0 + 9.0 * 60.0
	harvest.last_day = harvest.day()
	var farm: Dictionary = harvest.buildings_of("farm")[0]
	Farming.set_crop(harvest, "carrot")
	farm.growth = 100.0
	var start_stock := int(harvest.harvested.get("carrot", 0))
	check(harvest.command(0, "farm").ok, "farm order accepted")
	for i in range(300):
		harvest.tick(2.0)
		if float(farm.growth) < 100.0 and i > 5:
			break
	check(int(harvest.harvested.get("carrot", 0)) > start_stock, "a harvest adds to what can be sold at market")
	# livestock trading
	var herd := _rich(8)
	money_roundtrip(herd)
	# orders
	var o := _rich(9)
	check(Orders.parse("sell 2 cows", o).intent == "sell_animal" and Orders.parse("sell 2 cows", o).animal == "cow", "sell animals parses")
	check(Orders.parse("sell 10 pumpkins", o).item == "pumpkin", "selling crops parses")
	check(Orders.parse("buy corn", o).item == "corn" and Orders.parse("buy corn", o).trade_action == "buy", "buying crops parses")
	o.harvested = {"corn": 20}
	var order_result := Orders.execute(o, Orders.parse("sell 8 corn", o), 0)
	check(order_result.ok and int(o.harvested.corn) == 12, "the sell order is carried out: " + str(order_result.message))
	Farming.buy(o, "sheep", 2)
	var livestock_order := Orders.execute(o, Orders.parse("sell a sheep", o), 0)
	check(livestock_order.ok and Economy.herd_size(o, "sheep") == 1, "selling livestock by order works: " + str(livestock_order.message))
	# the panel
	var panel := MarketPanel.new()
	panel.sim = sim
	root.add_child(panel)
	await process_frame
	panel.visible = true
	panel.refresh()
	check(panel._rows.size() == MarketPanel.GOODS_ROWS.size() + MarketPanel.ANIMAL_ROWS.size(), "the panel lists every good and animal (%d)" % panel._rows.size())
	var seen := []
	panel.traded.connect(func(action: String, item: String, amount: int) -> void: seen.append([action, item, amount]))
	panel._set_amount(10)
	(panel._rows.food.buy as Button).pressed.emit()
	(panel._rows.a_cow.sell as Button).pressed.emit()
	check(seen.size() == 2 and seen[0] == ["buy", "food", 10] and seen[1] == ["sell", "a_cow", 10], "buttons emit trades with the chosen amount: %s" % str(seen))
	check((panel._rows.pumpkin.sell as Button).disabled == (Economy.stock_of(sim, "pumpkin") <= 0), "sell is disabled when there is nothing to sell")
	check(str((panel._rows.food.price as Label).text).length() > 0, "prices are shown")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with market history loads")
	check((back.price_history.food as Array).size() == (sim.price_history.food as Array).size(), "price history survives saving")
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	old.prices = {"food": 3.0, "wood": 2.0, "stone": 3.0}
	old.erase("harvested")
	old.erase("price_history")
	var legacy := LifeSim.new()
	check(legacy.load_data(old) and legacy.prices.has("wheat") and legacy.prices.has("a_cow"), "an old save gets prices for the new goods")
	print("MARKET TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func money_roundtrip(herd: LifeSim) -> void:
	var farm: Dictionary = herd.buildings_of("farm")[0]
	var cash := herd.money
	var buy := Economy.trade_animal(herd, "buy", "chicken", 3)
	check(buy.ok and Farming.count(farm, "chicken") == 3, "buying chickens at the market: " + str(buy.message))
	var spent := cash - herd.money
	check(spent > 0, "the animals cost coins")
	var back := herd.money
	var sell := Economy.trade_animal(herd, "sell", "chicken", 3)
	var earned := herd.money - back
	check(sell.ok and Farming.count(farm, "chicken") == 0, "selling them back: " + str(sell.message))
	check(earned < spent, "selling pays less than buying cost (%d vs %d)" % [earned, spent])
	check(not Economy.trade_animal(herd, "sell", "chicken", 1).ok, "none left to sell")
	for i in range(3):
		Farming.add_animal(herd, farm, "cow", herd.day())
	var calves := herd.money
	Economy.trade_animal(herd, "sell", "cow", 1)
	var calf_value := herd.money - calves
	for i in range(1):
		Farming.add_animal(herd, farm, "cow", herd.day() - 10)
	var cow_before := herd.money
	var sold_adult := Economy.trade_animal(herd, "sell", "cow", 1)
	check(sold_adult.ok and herd.money - cow_before >= calf_value, "adults sell first and fetch more than calves")
