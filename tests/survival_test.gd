extends SceneTree
## Monsters: night waves, chasing, fleeing, fighting, guards, being knocked out, dawn.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _outside(sim: LifeSim, index: int) -> void:
	var r: Dictionary = sim.residents[index]
	r.action = "play"
	r.route = []
	r.remaining = 500.0
	r.commanded = true


func _init() -> void:
	var sim := LifeSim.new()
	sim.rng.seed = 11
	sim.minutes = 6.0 * 1440.0 + 21.0 * 60.0  # day 7, 21:00
	# waves
	for i in range(80):
		sim.tick(10.0)
		if not sim.mobs.is_empty():
			break
	check(not sim.mobs.is_empty(), "monsters arrive at night")
	check(sim.mobs.size() <= Survival.cap_for(sim), "wave size respects the cap")
	# a quiet daytime start has none
	var day_sim := LifeSim.new()
	day_sim.minutes = 6.0 * 1440.0 + 12.0 * 60.0
	for i in range(10):
		day_sim.tick(10.0)
	check(Survival.count(day_sim, "zombie") + Survival.count(day_sim, "slime") == 0, "no zombies or slimes at midday")
	var early := LifeSim.new()
	early.minutes = 1.0 * 1440.0 + 22.0 * 60.0
	for i in range(10):
		early.tick(10.0)
	check(early.mobs.is_empty(), "grace period: no monsters in the first days")
	# a zombie hunts a resident standing outside
	var s := LifeSim.new()
	s.rng.seed = 5
	s.minutes = 6.0 * 1440.0 + 23.0 * 60.0
	var victim: Dictionary = s.residents[0]
	for r in s.residents:
		r.route = []
	var here := Vector2(float(victim.pos[0]), float(victim.pos[1]))
	var zombie := Survival.spawn(s, "zombie", here + Vector2(0.6, 0.0))
	_outside(s, 0)
	var health := float(victim.needs.health)
	for i in range(8):
		s.tick(3.0)
	check(float(victim.needs.health) < health or s.mobs.is_empty() or float(victim.get("fleeing_until", 0.0)) > 0.0, "zombie harms or scares a nearby resident")
	# fleeing
	var fled := false
	for r in s.residents:
		if float(r.get("fleeing_until", 0.0)) > 0.0:
			fled = true
	check(fled, "residents run for cover")
	# the chief strikes
	var z2 := Survival.spawn(s, "zombie", Vector2(float(s.chief_pos.x) + 0.5, float(s.chief_pos.y)))
	check(not Survival.damage_mob(s, z2, 10.0), "a light blow does not kill")
	check(Survival.damage_mob(s, z2, 100.0) and not s.mobs.has(z2), "a heavy blow kills and removes the monster")
	check(s.kills >= 1, "kills are counted")
	# guards fight
	var g := LifeSim.new()
	g.rng.seed = 9
	for resident in g.residents:
		resident.values = ["Community"]
	g.minutes = 6.0 * 1440.0 + 23.0 * 60.0
	check(g.command(1, "guard").ok, "guard order accepted")
	check(str((g.residents[1].job as Dictionary).kind) == "guard", "guard job started")
	var gpos := Vector2(float(g.residents[1].pos[0]), float(g.residents[1].pos[1]))
	var beast := Survival.spawn(g, "slime", gpos + Vector2(6.0, 0.0))
	var killed := false
	for i in range(300):
		g.tick(2.0)
		if not g.mobs.has(beast):
			killed = true
			break
	check(killed, "the guard hunts down the monster")
	# knocked out and back on their feet
	var k := LifeSim.new()
	k.minutes = 6.0 * 1440.0 + 23.0 * 60.0
	var down: Dictionary = k.residents[0]
	down.needs.health = 4.0
	var kpos := Vector2(float(down.pos[0]), float(down.pos[1]))
	_outside(k, 0)
	Survival.spawn(k, "zombie", kpos + Vector2(0.4, 0.0))
	for i in range(10):
		k.tick(4.0)
		if float(down.get("down_until", 0.0)) > 0.0:
			break
	check(float(down.get("down_until", 0.0)) > k.minutes, "a beaten resident collapses")
	k.mobs.clear()
	k.minutes = floorf(k.minutes / 1440.0) * 1440.0 + 1440.0 + 7.0 * 60.0
	k.tick(1.0)
	check(float(down.get("down_until", 0.0)) == 0.0 and float(down.needs.health) >= 30.0, "they recover at dawn")
	# sunlight
	var d := LifeSim.new()
	d.minutes = 6.0 * 1440.0 + 7.0 * 60.0
	Survival.spawn(d, "zombie", Vector2(30, 30))
	for i in range(30):
		d.tick(5.0)
	check(Survival.count(d, "zombie") == 0, "sunlight burns zombies away")
	# shelter order
	var sh := LifeSim.new()
	var order := Orders.parse("everyone take cover", sh)
	check(order.intent == "shelter" and order.scope == "all", "take cover parses")
	check(Orders.execute(sh, order, 0).ok, "take cover executes")
	check(Orders.parse("defend the village", sh).action == "guard", "defend means guard")
	check(Orders.parse("go home", sh).intent == "home", "go home still works")
	# saving ignores monsters
	var saved := LifeSim.new()
	Survival.spawn(saved, "wolf", Vector2(20, 20))
	var fresh := LifeSim.new()
	check(fresh.load_data(saved.to_dict()) and fresh.mobs.is_empty(), "monsters are not saved")
	# a watchtower can be fired by hand
	var lk := LifeSim.new()
	lk.money = 3000
	lk.wood = 100
	lk.stage_floor = 1
	var lspot := Orders._spot_near_chief(lk, "watchtower")
	lk.place_building("watchtower", lspot)
	var lt: Dictionary = lk.buildings[lk.buildings.size() - 1]
	lt.level = 2
	lt.target = 0
	lt.progress = 100.0
	var foe := Survival.spawn(lk, "zombie", Vector2(float(lt.tile[0]) + 6.0, float(lt.tile[1])))
	var far := Survival.spawn(lk, "zombie", Vector2(float(lt.tile[0]) + 30.0, float(lt.tile[1])))
	check(Survival.nearest_mob(lk, Vector2(float(lt.tile[0]), float(lt.tile[1])), 20.0) == foe, "the nearest monster in reach is found")
	check(Survival.nearest_mob(lk, Vector2(float(lt.tile[0]), float(lt.tile[1])), 3.0).is_empty(), "none in a short reach")
	var hp := float(foe.hp)
	Survival.tower_fire(lk, lt, foe)
	check(float(foe.hp) < hp, "a shot from the lookout hurts the monster")
	var shots := 0
	while lk.mobs.has(foe) and shots < 10:
		Survival.tower_fire(lk, lt, foe)
		shots += 1
	check(not lk.mobs.has(foe) and lk.kills >= 1 and lk.mobs.has(far), "a few shots kill it, and only it")
	print("SURVIVAL TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
