extends SceneTree
## The rival town, its raids, weapons, diplomacy and the strike on Redmarch.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _sim(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 4000
	sim.food = 300
	sim.wood = 300
	sim.stone = 300
	sim.stage_floor = 2
	sim.minutes = 20.0 * 1440.0
	sim.last_day = sim.day()
	for r in sim.residents:
		r.values = ["Community"]
	return sim


func _initialize() -> void:
	call_deferred("run")


func _arm(sim: LifeSim, n: int) -> void:
	sim.armory["sword"] = n
	for i in range(n):
		Weapons.equip(sim, i, "sword")


func run() -> void:
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	# --- weapons ---
	var sim := _sim()
	var workshop: Array = sim.buildings_of("workshop")
	check(not workshop.is_empty(), "the village starts with a workshop")
	for b in workshop:
		b.level = 0
	check(not Weapons.craft(sim, "sword", 1).ok, "an unfinished workshop can't forge")
	var shop := workshop
	shop[0].level = 1
	var wood := sim.wood
	var coins := sim.money
	check(Weapons.craft(sim, "sword", 2).ok and Weapons.in_armory(sim, "sword") == 2 and sim.money == coins - 140 and sim.wood == wood - 8, "forging spends timber, stone and coins")
	sim.money = 5
	check(not Weapons.craft(sim, "sword", 1).ok, "can't forge without coins")
	check(not Weapons.craft(sim, "lance", 1).ok, "unknown weapon")
	var r0: Dictionary = sim.residents[0]
	check(Weapons.power_of(r0) == 1.0, "bare hands hit for 1x")
	check(Weapons.equip(sim, 0, "sword").ok and Weapons.power_of(r0) == 3.0 and Weapons.in_armory(sim, "sword") == 1, "a sword triples a swing and leaves the armory")
	sim.armory["club"] = 1
	Weapons.equip(sim, 0, "club")
	check(Weapons.weapon_of(r0) == "club" and Weapons.in_armory(sim, "sword") == 2, "swapping returns the old weapon")
	check(not Weapons.equip(sim, 1, "bow").ok, "can't equip what the armory lacks")
	sim.armory["shield"] = 1
	Weapons.equip(sim, 0, "shield")
	check(Weapons.has_shield(r0) and Weapons.guard_of(r0) > 0.3, "a shield guards")
	Weapons.disarm(sim, 0)
	check(Weapons.weapon_of(r0) == "" and not Weapons.has_shield(r0) and Weapons.in_armory(sim, "shield") == 1, "disarming returns everything")
	sim.residents[1].age = 30
	sim.residents[1].profession = "guard"
	sim.armory["sword"] = 1
	var given := Weapons.arm_guards(sim)
	check(int(given.armed) >= 1 and Weapons.weapon_of(sim.residents[1]) == "sword", "guards are armed first")
	# chief
	var cs := _sim(2)
	check(Weapons.chief_damage(cs) == 20.0 and Weapons.chief_reach(cs) > 1.5, "unarmed chief")
	cs.armory["sword"] = 1
	cs.armory["bow"] = 1
	check(Weapons.chief_equip(cs, "sword").ok and Weapons.chief_damage(cs) == 60.0, "the chief wields a sword")
	check(Weapons.chief_equip(cs, "bow").ok and Weapons.in_armory(cs, "sword") == 1 and Weapons.chief_reach(cs) > 4.0, "switching returns the sword and bows reach far")
	Weapons.chief_cycle(cs)
	Weapons.chief_cycle(cs)
	check(cs.chief_weapon in ["", "sword", "bow"], "cycling works")
	check(Weapons.chief_equip(cs, "shield").ok == false, "a shield can't be wielded")
	check(Weapons.report(cs).contains("Armory"), "report reads")
	# fighting: armed residents kill faster
	var plain := _sim(3)
	var armed := _sim(3)
	armed.armory["sword"] = 1
	Weapons.equip(armed, 0, "sword")
	for s in [plain, armed]:
		s.residents[0].pos = [10.0, 10.0]
		s.residents[0].action = "rest"
		s.residents[0].fight_cd = 0.0
		var m := Survival.spawn(s, "zombie", Vector2(10.5, 10.0))
		m.hp = 200.0
	Survival.resident_fight(plain, 0, 1.0)
	Survival.resident_fight(armed, 0, 1.0)
	check(float(armed.mobs[0].hp) < float(plain.mobs[0].hp), "a sword hurts a zombie more than bare hands (%.0f vs %.0f)" % [float(armed.mobs[0].hp), float(plain.mobs[0].hp)])
	var shielded := _sim(4)
	shielded.armory["shield"] = 1
	Weapons.equip(shielded, 0, "shield")
	var unshielded := _sim(4)
	var z1 := Survival.spawn(shielded, "zombie", Vector2(1, 1))
	var z2 := Survival.spawn(unshielded, "zombie", Vector2(1, 1))
	shielded.residents[0].needs.health = 100.0
	unshielded.residents[0].needs.health = 100.0
	Survival._hit_resident(shielded, 0, z1, 10.0)
	Survival._hit_resident(unshielded, 0, z2, 10.0)
	check(float(shielded.residents[0].needs.health) > float(unshielded.residents[0].needs.health), "a shield soaks damage")
	# --- the rival ---
	var w := _sim(5)
	w.minutes = 2.0 * 1440.0
	Rival.daily(w)
	check(not Rival.known(w) and not w.rival.is_empty(), "the rival exists before anyone knows of it")
	check(absf(Rival.gap_units(w) - 200.0) < 20.0, "it lies about 200 units beyond the border (%.0f)" % Rival.gap_units(w))
	var legacy := _sim(55)
	legacy.rival = {"pos": [Survival.village_centre(legacy).x + 1250.0, 0.0]}
	Rival.ensure(legacy)
	check(absf(Rival.gap_units(legacy) - 200.0) < 20.0, "an old save with the far-off town is brought in close")
	check(Rival.position(w).x > Survival.village_centre(w).x + 40.0, "and to the east")
	w.minutes = 9.0 * 1440.0
	Rival.daily(w)
	check(Rival.known(w) and Rival.report(w).contains("Redmarch"), "word arrives by day eight")
	# a raid
	var raid := _sim(6)
	Rival.daily(raid)
	raid.rival.known = true
	raid.rival.attitude = -80.0
	raid.rival.soldiers = 40
	raid.rival.last_raid_day = 0
	var planned := false
	for i in range(30):
		raid.minutes += 1440.0
		raid.last_day = raid.day()
		Rival.daily(raid)
		if not (raid.rival.march as Dictionary).is_empty():
			planned = true
			break
	check(planned, "a hostile rival sends a warband")
	var size := int(raid.rival.march.size)
	check(size >= 2 and size <= 14, "of a sensible size (%d)" % size)
	check(Rival.raiders(raid) == 0, "who have not arrived yet")
	check(Rival.report(raid).contains("marching"), "the report warns of the march")
	raid.minutes = float(raid.rival.march.arrive) + 1.0
	Rival.tick(raid, 1.0)
	check(Rival.raiders(raid) == size and not (raid.rival.raid as Dictionary).is_empty(), "the raiders arrive at the village")
	var east := Survival.village_centre(raid).x
	var all_east := true
	for m in raid.mobs:
		if float(m.pos[0]) < east:
			all_east = false
	check(all_east, "from the east")
	# beat them
	var coins_before := raid.money
	var swords := Weapons.in_armory(raid, "sword")
	for m in raid.mobs.duplicate():
		Survival.damage_mob(raid, m, 999.0, 0)
	check(Rival.raiders(raid) == 0 and raid.money > coins_before, "killing raiders pays a bounty")
	Rival.tick(raid, 1.0)
	check(int(raid.rival.repelled) == 1 and raid.minutes < float(raid.rival.truce_until), "beating a raid brings a truce")
	check(Rival.at_peace(raid), "and peace for now")
	# loot
	var looty := _sim(7)
	Rival.daily(looty)
	looty.rival.known = true
	Rival.plan_raid(looty)
	looty.minutes = float(looty.rival.march.arrive) + 1.0
	Rival.tick(looty, 1.0)
	var purse := looty.money
	for m in looty.mobs:
		m.pos = [Survival.village_centre(looty).x, Survival.village_centre(looty).y]
	for i in range(80):
		for r in looty.residents:
			r.pos = [-500.0, -500.0]
		Survival.tick(looty, 5.0)
		if Rival.raiders(looty) == 0:
			break
	check(looty.money < purse and int(looty.rival.looted) > 0, "unopposed raiders loot coins (%d -> %d)" % [purse, looty.money])
	check(Rival.raiders(looty) == 0 and (looty.rival.raid as Dictionary).is_empty(), "and then leave, ending the raid")
	# peaceful setting
	GameSettings.set_value("difficulty", "peaceful")
	var calm := _sim(8)
	Rival.daily(calm)
	calm.rival.known = true
	calm.rival.attitude = -90.0
	calm.rival.soldiers = 50
	for i in range(40):
		calm.minutes += 1440.0
		calm.last_day = calm.day()
		Rival.daily(calm)
	check((calm.rival.march as Dictionary).is_empty() and calm.rival.raids == 0, "peaceful mode means no raids")
	GameSettings.set_value("difficulty", "normal")
	# diplomacy
	var d := _sim(9)
	check(not Rival.envoy(d).ok, "no envoy to a town nobody knows")
	Rival.daily(d)
	d.rival.known = true
	var mood := float(d.rival.attitude)
	var purse2 := d.money
	check(Rival.envoy(d).ok and float(d.rival.attitude) > mood and d.money == purse2 - Rival.ENVOY_COST, "an envoy warms them")
	check(Rival.tribute(d).ok and Rival.at_peace(d), "tribute buys a truce")
	d.rival.truce_until = 0.0
	d.rival.attitude = -80.0
	check(not Rival.peace(d).ok, "a furious rival won't talk")
	d.rival.attitude = -20.0
	check(Rival.peace(d).ok and Rival.at_peace(d), "a wary one will")
	d.money = 10
	check(not Rival.tribute(d).ok and not Rival.envoy(d).ok, "diplomacy costs coins")
	# the council prepares by itself
	var c := _sim(10)
	for b in c.buildings_of("workshop"):
		b.level = 1
	Rival.daily(c)
	c.rival.known = true
	c.rival.attitude = -50.0
	c.rival.soldiers = 30
	Rival.council_prepare(c)
	check(Weapons.armed_count(c) + Weapons.in_armory(c, "sword") + Weapons.in_armory(c, "spear") + Weapons.in_armory(c, "club") > 0, "the council forges weapons against a hostile neighbour")
	# attacking
	var a := _sim(11)
	Rival.daily(a)
	a.rival.known = true
	check(not Rival.attack(a).ok, "can't attack with no army")
	a.armory["sword"] = 12
	for i in range(mini(12, a.residents.size())):
		a.residents[i].age = 30
		Weapons.equip(a, i, "sword")
	check(Rival.strike_force(a).size() >= 3, "armed residents form a strike force")
	a.rival.soldiers = 3
	var loot_before := a.money
	var res := Rival.attack(a)
	check(bool(res.ok) and a.money > loot_before and bool(a.rival.defeated), "a strong army beats a weak town: " + str(res.message).left(80))
	check(Rival.at_peace(a) and not Rival.envoy(a).ok, "a beaten rival is at peace")
	var coin := a.money
	Rival.daily(a)
	check(a.money == coin + Rival.TRIBUTE_INCOME, "a defeated rival pays tribute")
	var f := _sim(12)
	Rival.daily(f)
	f.rival.known = true
	f.rival.soldiers = 200
	f.armory["club"] = 3
	for i in range(3):
		f.residents[i].age = 30
		Weapons.equip(f, i, "club")
	var lost := Rival.attack(f)
	check(not bool(lost.ok) and not bool(f.rival.defeated), "a small band loses to a big army")
	check(not Rival.attack(f).ok, "and must recover before marching again")
	# --- Redmarch's soldiers fight back in person ---
	var g := _sim(30)
	Rival.daily(g)
	g.rival.known = true
	g.rival.attitude = -60.0
	g.rival.soldiers = 30
	for r in g.residents:
		r.pos = [-900.0, -900.0]
	var town := Rival.position(g)
	g.chief_pos = town + Vector2(-60.0, 0.0)
	Rival.tick(g, 1.0)
	check(Rival.garrison(g).is_empty(), "far from the town nobody is on guard")
	g.chief_pos = town + Vector2(-Rival.TOWN_HALF_TILES - 14.0, 0.0)
	Rival.tick(g, 1.0)
	var guards := Rival.garrison(g)
	check(guards.size() >= 4 and guards.size() <= 12, "soldiers turn out when the chief comes near (%d)" % guards.size())
	check(Survival.count(g) == 0, "and they are not counted as the village's monsters")
	var gk := {}
	for m in guards:
		gk[str(m.kind)] = true
	check(gk.has("soldier") and gk.has("soldier_archer"), "footmen and bowmen")
	var hp0 := float(Combat.fighter(g).hp)
	for i in range(40):
		Survival.tick(g, 1.0)
	check(float(Combat.fighter(g).hp) < hp0, "hostile soldiers attack the chief in person")
	var closest := 1.0e9
	for m in Rival.garrison(g):
		closest = minf(closest, Vector2(float(m.pos[0]), float(m.pos[1])).distance_to(g.chief_pos))
	check(closest < 8.0, "they close in on the chief (%.1f tiles)" % closest)
	# leash: run away and they go home rather than following to the village
	g.chief_pos = town + Vector2(-Rival.GARRISON_LEASH - 12.0, 0.0)
	var home_ok := true
	for i in range(60):
		Survival.tick(g, 2.0)
	for m in Rival.garrison(g):
		if Vector2(float(m.pos[0]), float(m.pos[1])).distance_to(Vector2(float(m.home[0]), float(m.home[1]))) > Rival.GARRISON_LEASH + 6.0:
			home_ok = false
	check(home_ok, "they won't chase far from their town")
	g.chief_pos = town + Vector2(-Rival.GARRISON_DESPAWN - 20.0, 0.0)
	Rival.tick(g, 1.0)
	check(Rival.garrison(g).is_empty(), "when the chief leaves, the soldiers return to barracks")
	# killing them weakens the town and ends in surrender
	var k := _sim(31)
	Rival.daily(k)
	k.rival.known = true
	k.rival.soldiers = 6
	for r in k.residents:
		r.pos = [-900.0, -900.0]
	k.chief_pos = Rival.position(k) + Vector2(-Rival.TOWN_HALF_TILES - 12.0, 0.0)
	Rival.tick(k, 1.0)
	var strength := int(k.rival.soldiers)
	var purse3 := k.money
	for m in Rival.garrison(k).duplicate():
		Survival.damage_mob(k, m, 9999.0, -1)
	check(int(k.rival.soldiers) < strength and k.money > purse3, "every soldier slain weakens the town and pays a little loot")
	check(bool(k.rival.defeated), "when the garrison is gone the town surrenders")
	# at peace the guards stay calm until struck
	var calm2 := _sim(32)
	Rival.daily(calm2)
	calm2.rival.known = true
	calm2.rival.soldiers = 30
	calm2.rival.truce_until = calm2.minutes + 5.0 * 1440.0
	for r in calm2.residents:
		r.pos = [-900.0, -900.0]
	calm2.chief_pos = Rival.position(calm2) + Vector2(-Rival.TOWN_HALF_TILES - 8.0, 0.0)
	Rival.tick(calm2, 1.0)
	var hp_calm := float(Combat.fighter(calm2).hp)
	for i in range(40):
		Survival.tick(calm2, 1.0)
	check(Rival.garrison(calm2).size() > 0 and float(Combat.fighter(calm2).hp) == hp_calm, "during a truce the guards leave the chief alone")
	Survival.damage_mob(calm2, Rival.garrison(calm2)[0], 1.0, -1)
	for i in range(60):
		Survival.tick(calm2, 1.0)
	check(float(Combat.fighter(calm2).hp) < hp_calm, "but strike one and they all turn on you")
	# orders
	var o := _sim(13)
	Rival.daily(o)
	o.rival.known = true
	for b in o.buildings_of("workshop"):
		b.level = 1
	check(Orders.parse("forge 3 swords", o).intent == "craft" and int(Orders.parse("forge 3 swords", o).amount) == 3, "forge order parses")
	var had := Weapons.in_armory(o, "sword")
	var forge_res := Orders.execute(o, Orders.parse("forge 2 swords", o), 0)
	check(forge_res.ok and Weapons.in_armory(o, "sword") == had + 2, "and works")
	check(Orders.parse("arm the guards", o).intent == "arm", "arm order parses")
	check(Orders.parse("what is in the armory", o).intent == "weapons_report", "armory report parses")
	check(Orders.parse("equip the sword", o).intent == "chief_equip", "equip parses")
	check(Orders.execute(o, Orders.parse("equip the sword", o), 0).ok and o.chief_weapon == "sword", "chief takes the sword")
	check(Orders.parse("how is redmarch", o).intent == "rival_report", "rival report parses")
	check(Orders.parse("send an envoy to redmarch", o).intent == "envoy", "envoy parses")
	check(Orders.parse("pay tribute to redmarch", o).intent == "tribute", "tribute parses")
	check(Orders.parse("ask redmarch for peace", o).intent == "peace", "peace parses")
	check(Orders.parse("attack redmarch", o).intent == "attack_rival", "attack parses")
	check(not Orders.execute(o, Orders.parse("how is redmarch", o), 0).message.is_empty(), "rival report reads out")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(a.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data) and bool(back.rival.defeated) and Weapons.in_armory(back, "sword") == Weapons.in_armory(a, "sword"), "rival and armory survive saving")
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	old.erase("rival")
	old.erase("armory")
	old.erase("chief_weapon")
	check(LifeSim.new().load_data(old), "older saves load")
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	print("RIVAL TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
