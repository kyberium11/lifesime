extends SceneTree
## Festivals: calendar, gathering, contests, prizes, market, impromptu feasts, decorations.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	call_deferred("run")


func _day_at(sim: LifeSim, season: String, day_in_season: int, hour: float) -> void:
	var offset: int = {"Spring": 0, "Summer": 7, "Autumn": 14, "Winter": 21}[season]
	var day: int = 28 + offset + day_in_season
	sim.minutes = float(day - 1) * 1440.0 + hour * 60.0
	sim.last_day = sim.day()


func _sim(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 2000
	for r in sim.residents:
		r.values = ["Community"]
	return sim


func run() -> void:
	# the calendar
	for season in ["Spring", "Summer", "Autumn", "Winter"]:
		var sim := _sim()
		_day_at(sim, season, 4, 8.0)
		check(sim.season() == season, "the test calendar lands in %s" % season)
		Festivals.daily(sim)
		check(not sim.festival.is_empty() and str(sim.festival.name) == Festivals.FESTIVALS[season].name, "%s has its festival (%s)" % [season, str(sim.festival.get("name", ""))])
		var other := _sim()
		_day_at(other, season, 2, 8.0)
		Festivals.daily(other)
		check(other.festival.is_empty(), "no festival on an ordinary day")
	# the day unfolds
	var f := _sim(2)
	_day_at(f, "Autumn", 4, 8.0)
	Festivals.daily(f)
	check(not Festivals.is_active(f), "it hasn't started in the morning")
	f.minutes = float(f.day() - 1) * 1440.0 + 14.0 * 60.0
	Festivals.tick(f, 1.0)
	check(Festivals.is_active(f), "it starts in the afternoon")
	var gathering := 0
	for r in f.residents:
		if str(r.target) == "the festival":
			gathering += 1
	check(gathering == f.residents.size(), "everyone sets off for the plaza")
	var market_event := false
	for e in f.events:
		if str(e.kind) == "festival_market":
			market_event = true
	check(market_event, "the festival stirs the market")
	var fun_before := float(f.residents[0].needs.fun)
	f.residents[0].needs.fun = 40.0
	Festivals.tick(f, 10.0)
	check(float(f.residents[0].needs.fun) > 40.0, "people enjoy themselves")
	# contest
	f.residents[2].skills.gardening = 500.0
	var money := f.money
	f.minutes = float(f.day() - 1) * 1440.0 + 18.5 * 60.0
	Festivals.tick(f, 1.0)
	check(bool(f.festival.contest_done) and str(f.festival.get("winner", "")) == str(f.residents[2].name), "the best gardener wins the pumpkin contest: " + str(f.festival.get("winner", "")))
	check(f.money == money - Festivals.PRIZE and int(f.residents[2].savings) >= Festivals.PRIZE, "the prize is paid")
	check(not f.residents[2].core.is_empty(), "the winner remembers it")
	check(f.rumors.size() > 0, "the village talks about it")
	# the end
	f.minutes = float(f.day() - 1) * 1440.0 + 23.2 * 60.0
	Festivals.tick(f, 1.0)
	check(not Festivals.is_active(f), "it ends at night")
	Festivals.daily(f)
	var again := Festivals.is_active(f)
	check(not again, "and does not restart that night")
	# a new day clears it
	f.minutes += 1440.0
	f.last_day = f.day()
	Festivals.daily(f)
	check(f.festival.is_empty() or int(f.festival.day) == f.day(), "the next day starts fresh")
	# an impromptu feast
	var feast := _sim(3)
	check(Festivals.call_feast(feast) and Festivals.is_active(feast), "the chief can call a feast")
	check(not Festivals.call_feast(feast), "not twice at once")
	var o := _sim(4)
	var order := Orders.parse("hold a festival", o)
	check(order.intent == "festival", "the festival order parses")
	check(Orders.execute(o, order, 0).ok and Festivals.is_active(o), "ordering a festival starts a feast")
	check(not Orders.execute(o, order, 0).ok, "a second festival is refused while one is on")
	var poor := _sim(5)
	poor.money = 5
	check(not Orders.execute(poor, Orders.parse("hold a festival", poor), 0).ok, "a feast needs coins")
	# small towns have none
	var tiny := _sim(6)
	tiny.residents.resize(3)
	_day_at(tiny, "Spring", 4, 8.0)
	Festivals.daily(tiny)
	check(tiny.festival.is_empty(), "a hamlet of three has no fair")
	# decorations appear in the scene
	var s := _sim(7)
	var art := CityArt.new()
	root.add_child(art)
	art.generate(s)
	_day_at(s, "Winter", 4, 15.0)
	Festivals.daily(s)
	s.minutes = float(s.day() - 1) * 1440.0 + 15.0 * 60.0
	Festivals.tick(s, 1.0)
	for i in range(5):
		await process_frame
		art.sync(0, 0.016)
	check(art._festival_node != null and is_instance_valid(art._festival_node), "the plaza is decorated while the festival runs")
	check(art._festival_node.get_child_count() > 40, "with bunting, stalls and a bonfire (%d pieces)" % art._festival_node.get_child_count())
	s.minutes = float(s.day() - 1) * 1440.0 + 23.5 * 60.0
	Festivals.tick(s, 1.0)
	for i in range(5):
		await process_frame
		art.sync(0, 0.016)
	check(art._festival_node == null, "the decorations come down afterwards")
	print("FESTIVAL TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
