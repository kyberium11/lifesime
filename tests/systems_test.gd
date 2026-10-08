extends SceneTree
## Inner life, families, rumours, health, the market and upkeep.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _init() -> void:
	var sim := LifeSim.new()
	sim.rng.seed = 21
	var a: Dictionary = sim.residents[0]
	var b: Dictionary = sim.residents[1]
	# personality, values, genes exist and are sane
	for r in sim.residents:
		check(r.ocean.size() == 5 and float(r.ocean.e) >= 0.0 and float(r.ocean.e) <= 1.0, "%s has a five-factor personality" % r.name)
		check(not r.values.is_empty() and r.genes.has("talent"), "%s has values and genes" % r.name)
	check(Psyche.compat(a, b) >= 0.0 and Psyche.compat(a, b) <= 1.0, "compatibility is 0..1")
	check(Psyche.decay_mult({"ocean": {"e": 0.9}}, "social") > Psyche.decay_mult({"ocean": {"e": 0.1}}, "social"), "extroverts burn through company faster")
	# beliefs
	a.values = ["Nature"]
	var refused := 0
	for i in range(40):
		if Psyche.dissonance(sim, 0, "chop") != "":
			refused += 1
	check(refused > 5 and refused < 40, "a resident who values nature sometimes refuses to chop (%d/40)" % refused)
	# stress -> breakdown
	a.values = ["Community"]
	a.stress = 99.0
	sim.tick(1.0)
	check(float(a.break_until) > sim.minutes, "extreme stress causes a breakdown")
	check(not sim.command(0, "work").ok, "someone on a break refuses orders")
	sim.minutes += 400.0
	sim.tick(1.0)
	check(float(a.break_until) == 0.0 and float(a.stress) <= 55.0, "the breakdown passes and stress eases")
	# core memories and trauma
	var before := float(b.trauma)
	Psyche.add_core(sim, b, "Something terrible happened.", 0.9, -0.9)
	check(float(b.trauma) > before and not b.core.is_empty(), "painful memories leave trauma")
	# romance, marriage, children
	var s := LifeSim.new()
	s.rng.seed = 5
	s.money = 5000
	s.food = 200
	var p: Dictionary = s.residents[0]
	var q: Dictionary = s.residents[1]
	p.age = 28
	q.age = 27
	p.relations[q.name] = 80.0
	q.relations[p.name] = 80.0
	p.ocean = {"o": 0.5, "c": 0.5, "e": 0.5, "a": 0.7, "n": 0.4}
	q.ocean = p.ocean.duplicate()
	p.values = ["Family"]
	q.values = ["Family"]
	check(Lifecycle.attraction(p, q) >= 0.5, "the pair is compatible")
	for i in range(80):
		s.resident_interact(0, 1, "compliment")
		s.resident_interact(1, 0, "hug")
		if str(p.partner) != "":
			break
	check(str(p.partner) == str(q.name) and str(q.partner) == str(p.name), "romance grows into a couple")
	p.partner_since = -10
	p.romance[q.name] = 95.0
	q.romance[p.name] = 95.0
	Lifecycle.daily(s)
	check(bool(p.married) and bool(q.married), "the couple marries")
	var pop := s.residents.size()
	for i in range(160):
		s.minutes += 1440.0
		s.food = 300
		s.last_day = s.day()
		Lifecycle.daily(s)
		if s.residents.size() > pop:
			break
	check(s.residents.size() > pop, "the couple has a child")
	if s.residents.size() > pop:
		var kid: Dictionary = s.residents[s.residents.size() - 1]
		check(int(kid.age) == 0 and kid.parents.size() == 2 and p.children.has(kid.name), "the baby is recorded in the family tree")
		check(Lifecycle.stage_name(int(kid.age)) == "Infant" and Lifecycle.blocked(kid, "work") != "", "infants cannot work")
		check(Lifecycle.body_scale(kid) < Lifecycle.body_scale(p), "children are drawn smaller")
		check(float(kid.ocean.e) >= 0.0 and str(kid.genes.talent) != "", "the child inherits a temperament and genes")
	# death and estate
	var d := LifeSim.new()
	var elder: Dictionary = d.residents[2]
	elder.earned = 500
	var count := d.residents.size()
	var elder_name: String = elder.name
	Lifecycle.pass_away(d, 2, "old age")
	check(d.residents.size() == count - 1 and d.index_of(elder_name) < 0, "a death removes the resident")
	check(d.money > 400, "their estate is passed on")
	var removed := false
	for e in d.drain_fx():
		if e.type == "resident_removed":
			removed = true
	check(removed, "the world is told someone has gone")
	# rumours spread, distort, and move reputations
	var g := LifeSim.new()
	g.rng.seed = 3
	for r in g.residents:
		r.pos = [100.0, 100.0]
	g.residents[0].pos = [2.0, 2.0]
	g.residents[1].pos = [2.5, 2.0]
	Rumors.create(g, "Pip", "", "heroic", "Pip fought off a zombie", 0.7, [0, 1])
	check(g.residents[0].heard.size() == 1 and g.residents[1].heard.size() == 1, "witnesses hear it first")
	check(g.residents[3].heard.is_empty(), "people far away have not heard")
	var told := false
	for i in range(120):
		g.resident_interact(1, 3, "chat")
		if g.residents[3].heard.size() > 0:
			told = true
			break
	check(told, "it spreads when residents talk")
	Rumors.create(g, "Mira", "", "argue", "Mira screamed at Theo", -0.8, [2])
	check(Rumors.reputation(g, "Mira") < 60.0, "bad news lowers reputation")
	check(Rumors.reputation_label(80.0) == "beloved" and Rumors.reputation_label(10.0) == "scorned", "reputation labels")
	# illness
	var h := LifeSim.new()
	h.rng.seed = 8
	Health.infect(h, 0, "flu")
	check(h.log_has("came down with"), "illness is logged")
	check(float(h.residents[0].ill_until) > h.minutes, "the sick resident is ill for a while")
	check(Health.speed({"injured": true, "ill_until": 0.0}) < 1.0, "injury slows people down")
	for r in h.residents:
		r.pos = [3.0, 3.0]
		r.needs.hygiene = 5.0
	var spread := false
	for i in range(600):
		for r in h.residents:
			r.pos = [3.0, 3.0]
			r.needs.hunger = 90.0
			r.needs.energy = 90.0
			r.needs.hygiene = 5.0
			r.route = []
			r.action = "play"
			r.remaining = 9999.0
			r.target_id = -1
		h.tick(1.0)
		for k in range(1, h.residents.size()):
			if float(h.residents[k].ill_until) > 0.0:
				spread = true
		if spread:
			break
	check(spread, "illness spreads between people standing close together")
	# the market
	var m := LifeSim.new()
	m.food = 2
	for i in range(3):
		Economy.update_prices(m)
	var scarce := Economy.price(m, "food")
	m.food = 400
	for i in range(8):
		Economy.update_prices(m)
	check(Economy.price(m, "food") < scarce, "plentiful food is cheaper than scarce food (%.2f vs %.2f)" % [Economy.price(m, "food"), scarce])
	m.stone = 50
	var coins := m.money
	var sold := Economy.trade(m, "sell", "stone", 20)
	check(sold.ok and m.stone == 30 and m.money > coins, "selling stone pays coins")
	var bought := Economy.trade(m, "buy", "wood", 5)
	check(bought.ok and m.wood >= 19, "buying wood costs coins")
	check(not Economy.trade(m, "sell", "gold", 1).ok, "unknown goods are refused")
	# events
	var ev := LifeSim.new()
	ev.rng.seed = 2
	ev.minutes = 20.0 * 1440.0
	var fired := false
	for i in range(80):
		ev.minutes += 1440.0
		ev.last_day = ev.day()
		Economy.daily(ev)
		if not ev.events.is_empty():
			fired = true
			break
	check(fired, "random world events happen")
	# maintenance
	var mt := LifeSim.new()
	mt.money = 500
	mt.wood = 50
	for resident in mt.residents:
		resident.values = ["Community"]
	var shop: Dictionary = mt.buildings_of("market")[0]
	shop.condition = 20.0
	check(Economy.efficiency(shop) < 1.0, "a run-down building works worse")
	check(mt.has_target("repair"), "worn buildings can be repaired")
	var done := mt.command(0, "repair")
	check(done.ok, "repair order accepted: " + str(done.message))
	for i in range(300):
		mt.tick(2.0)
		if float(shop.condition) > 40.0:
			break
	check(float(shop.condition) > 40.0, "the repair raises the building's condition")
	var farm: Dictionary = mt.buildings_of("farm")[0]
	farm.soil = 30.0
	check(Economy.yield_factor(farm) < 0.75, "tired soil yields less")
	# saving keeps the new systems
	var save := LifeSim.new()
	save.residents[0].partner = "Mira"
	save.residents[0].stress = 44.0
	Rumors.create(save, "Pip", "", "heroic", "Pip did something brave", 0.7, [0])
	save.prices.food = 4.5
	var data: Variant = JSON.parse_string(JSON.stringify(save.to_dict()))
	var restored := LifeSim.new()
	check(restored.load_data(data), "a save with the new systems loads")
	check(str(restored.residents[0].partner) == "Mira" and absf(float(restored.residents[0].stress) - 44.0) < 0.01, "inner life survives saving")
	check(restored.rumors.size() == 1 and absf(float(restored.prices.food) - 4.5) < 0.01, "rumours and prices survive saving")
	# an old save without any of it still loads
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	for r in old.residents:
		for key in ["ocean", "values", "stress", "genes", "partner", "core", "heard", "romance", "rivalry", "opinion", "warmth"]:
			r.erase(key)
	old.erase("rumors")
	old.erase("prices")
	var legacy := LifeSim.new()
	check(legacy.load_data(old) and not legacy.residents[0].ocean.is_empty(), "an older save is given an inner life on load")
	# orders for the new systems
	var o := LifeSim.new()
	check(Orders.parse("repair the market", o).action == "repair", "repair order parses")
	var trade := Orders.parse("sell 20 stone", o)
	check(trade.intent == "trade" and trade.item == "stone" and int(trade.amount) == 20 and trade.trade_action == "sell", "sell order parses")
	check(Orders.parse("buy some food", o).trade_action == "buy", "buy order parses")
	check(Orders.parse("what are the prices today", o).intent == "market", "price question parses")
	check(Orders.execute(o, Orders.parse("market prices", o), 0).ok, "market report works")
	o.stone = 40
	check(Orders.execute(o, {"intent": "trade", "trade_action": "sell", "item": "surplus", "amount": 0, "scope": "default", "names": []}, 0).ok, "selling surplus works")
	# clinic and watchtower
	var c := LifeSim.new()
	c.money = 3000
	c.wood = 80
	c.stage_floor = 1
	for resident in c.residents:
		resident.values = ["Community"]
	var spot := Orders._spot_near_chief(c, "clinic")
	check(spot.x > -9000, "there is a lot for a clinic")
	var placed := c.place_building("clinic", spot)
	check(placed.begins_with("Started"), "a clinic can be built: " + placed)
	var clinic: Dictionary = c.buildings[c.buildings.size() - 1]
	clinic.level = 1
	clinic.target = 0
	clinic.progress = 100.0
	Health.infect(c, 0, "flu")
	check(c.has_target("treat"), "a clinic offers treatment")
	var patient: Dictionary = c.residents[0]
	c.medicine = 2
	check(c.command(0, "treat").ok, "treat order accepted")
	for i in range(300):
		c.tick(2.0)
		if float(patient.ill_until) == 0.0:
			break
	check(float(patient.ill_until) == 0.0, "the clinic cures the patient")
	var needs := CityPlanner.needs(c)
	check(needs.has("clinic") and needs.has("watchtower"), "the council weighs clinics and watchtowers")
	var t := LifeSim.new()
	t.money = 3000
	t.wood = 80
	t.stage_floor = 1
	var tower_spot := Orders._spot_near_chief(t, "watchtower")
	check(t.place_building("watchtower", tower_spot).begins_with("Started"), "a watchtower can be built")
	var tower: Dictionary = t.buildings[t.buildings.size() - 1]
	tower.level = 1
	tower.target = 0
	tower.progress = 100.0
	t.minutes = 5.0 * 1440.0 + 23.0 * 60.0
	var prey := Survival.spawn(t, "zombie", Vector2(float(tower.tile[0]) + 4.0, float(tower.tile[1])))
	for i in range(60):
		t.tick(1.0)
		if not t.mobs.has(prey):
			break
	check(not t.mobs.has(prey) and t.kills >= 1, "the watchtower shoots down a monster in range")
	check(Orders.parse("go see a doctor", t).action == "treat", "treat order parses")
	var wolves := LifeSim.new()
	wolves.minutes = 20.0 * 1440.0
	Economy._random_event(wolves)
	check(true, "random events run without error")
	print("SYSTEMS TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
