extends SceneTree
## Headless tests for the chief's orders: parsing, targeting and effects on the simulation.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run(sim: LifeSim, text: String, default_index: int = 0) -> Dictionary:
	return Orders.execute(sim, Orders.parse(text, sim), default_index)


func _init() -> void:
	var sim := LifeSim.new()
	for resident in sim.residents:
		resident.values = ["Community"]
	sim.money = 5000
	sim.wood = 500
	sim.chief_pos = Vector2(2.0, 4.0)
	var n := sim.residents.size()
	var name0: String = sim.residents[0].name
	# parsing
	check(Orders.parse("everyone follow me", sim).intent == "follow", "follow intent")
	check(Orders.parse("everyone follow me", sim).scope == "all", "everyone scope")
	check(Orders.parse("%s, build a farm" % name0, sim).scope == "names", "named scope")
	check(Orders.parse("How are you today?", sim).intent == "chat", "plain chat stays chat")
	check(Orders.parse("I love farming", sim).intent == "chat", "opinion stays chat")
	check(Orders.parse("stop talking", sim).intent == "hush", "hush")
	check(Orders.parse("build two farms", sim).count == 2, "count")
	# follow / stay / free
	var r := _run(sim, "everyone follow me")
	check(r.ok and sim.following.size() == n, "everyone follows")
	for i in range(30):
		sim.tick(10.0)
	check(sim.following.size() == n, "followers keep following")
	r = _run(sim, "everyone stay here")
	check(sim.holding.size() == n and sim.following.is_empty(), "stay replaces follow")
	var before := Vector2(sim.residents[0].pos[0], sim.residents[0].pos[1])
	sim.tick(60.0)
	check(Vector2(sim.residents[0].pos[0], sim.residents[0].pos[1]) == before, "held resident does not move")
	r = _run(sim, "everyone carry on")
	check(sim.holding.is_empty() and sim.following.is_empty(), "carry on frees everyone")
	# gather round
	sim.chief_pos = Vector2(2.0, 4.0)
	r = _run(sim, "everyone gather round")
	check(r.ok, "gather round ok")
	var close := 0
	for i in range(60):
		sim.tick(5.0)
		var here := 0
		for res in sim.residents:
			if Vector2(res.pos[0], res.pos[1]).distance_to(sim.chief_pos) < 4.0:
				here += 1
		close = maxi(close, here)
	check(close >= n - 1, "residents reach the chief (%d of %d)" % [close, n])
	# activities
	r = _run(sim, "everyone work")
	check(r.ok, "work order ok: " + str(r.message))
	r = _run(sim, "%s go farm" % name0, 1)
	check(Orders.parse("%s go farm" % name0, sim).intent == "action", "named action parsed")
	# village
	var buildings := sim.buildings.size()
	r = _run(sim, "build a market")
	check(r.ok and sim.buildings.size() == buildings + 1, "build a market: " + str(r.message))
	buildings = sim.buildings.size()
	r = _run(sim, "build two houses")
	check(sim.buildings.size() >= buildings + 1, "build houses: " + str(r.message))
	var claimed := sim.map.claimed.size()
	r = _run(sim, "claim more land")
	check(r.ok and sim.map.claimed.size() == claimed + 1, "expand: " + str(r.message))
	r = _run(sim, "how is everyone doing?")
	check(r.ok and str(r.message).length() > 10, "report")
	check(_run(sim, "let the council decide").ok and sim.auto_plan, "council auto")
	check(_run(sim, "ask me first").ok and not sim.auto_plan, "council ask")
	check(str(_run(sim, "stop talking").ui) == "hush", "hush ui")
	check(str(_run(sim, "pause the game").ui) == "pause", "pause ui")
	r = _run(sim, "hold a festival")
	check(r.ok, "festival: " + str(r.message))
	r = _run(sim, "follow me", -1)
	check(not r.ok, "no target is reported")
	# outdoor jobs
	var sim2 := LifeSim.new()
	sim2.rng.seed = 7
	for resident in sim2.residents:
		resident.values = ["Community"]
	for job in ["chop", "mine", "water"]:
		check(sim2.has_target(job), "world offers a site to %s" % job)
	var timber := sim2.wood
	var stone0 := sim2.stone
	var res := sim2.command(0, "chop")
	check(res.ok and not (sim2.residents[0].job as Dictionary).is_empty(), "chop order starts a job: " + str(res.message))
	var phases := {}
	var felled := false
	for i in range(900):
		sim2.tick(2.0)
		var job: Dictionary = sim2.residents[0].job
		if not job.is_empty():
			phases[job.phase] = true
		for e in sim2.drain_fx():
			if e.type == "felled":
				felled = true
		if job.is_empty() and phases.has("haul"):
			break
	check(felled and not sim2.depleted.is_empty(), "a tree was felled")
	check(sim2.wood > timber, "timber delivered (%d -> %d)" % [timber, sim2.wood])
	check(phases.has("approach") and phases.has("work") and phases.has("haul"), "job went through approach, work and haul: %s" % [phases.keys()])
	check((sim2.residents[0].carry as String) == "", "load handed over")
	res = sim2.command(1, "mine")
	check(res.ok, "mine order ok: " + str(res.message))
	for i in range(900):
		sim2.tick(2.0)
		if (sim2.residents[1].job as Dictionary).is_empty():
			break
	check(sim2.stone > stone0, "stone delivered (%d -> %d)" % [stone0, sim2.stone])
	check(sim2.materials() == sim2.wood + sim2.stone, "materials combine timber and stone")
	res = sim2.command(2, "water")
	check(res.ok, "water order ok: " + str(res.message))
	var loaded := LifeSim.new()
	check(loaded.load_data(sim2.to_dict()), "state with depleted trees loads")
	check(loaded.depleted.size() == sim2.depleted.size() and loaded.stone == sim2.stone, "depleted tiles and stone survive saving")
	var wood_before := sim2.wood
	var tile: Vector2i = sim2.depleted.keys()[0]
	sim2.depleted[tile].day = 1
	sim2.minutes += 24.0 * 60.0 * 12
	sim2._regrow()
	check(not sim2.depleted.has(tile), "felled trees grow back")
	check(Orders.parse("gather some wood", sim2).action == "chop", "gather wood means chop")
	check(Orders.parse("everyone mine stone", sim2).action == "mine", "mine stone order")
	check(Orders.parse("fetch water", sim2).action == "water", "fetch water order")
	print("ORDERS TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
