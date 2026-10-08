extends SceneTree
## The chief's fighting: combos, heavy swings, arcs, stamina, dodging, blocking, bleeding, being knocked out; and the
## monsters' side: they go for the chief, archers shoot from range, stagger and knockback.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _sim(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 3000
	sim.minutes = 20.0 * 1440.0 + 12.0 * 60.0
	sim.last_day = sim.day()
	sim.chief_pos = Vector2(10.0, 10.0)
	Combat.set_facing(sim, Vector2(1, 0))
	return sim


func _zombie(sim: LifeSim, at: Vector2, hp: float = 500.0) -> Dictionary:
	var m := Survival.spawn(sim, "zombie", at)
	m.hp = hp
	m.max_hp = hp
	return m


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	# --- light attacks and the combo ---
	var sim := _sim()
	var foe := _zombie(sim, Vector2(11.0, 10.0))
	var r1 := Combat.attack(sim)
	check(bool(r1.swung) and int(r1.hits) == 1 and int(r1.combo) == 1, "a swing in front hits")
	check(not bool(Combat.attack(sim).swung), "you can't swing again at once (cooldown)")
	Combat.tick(sim, 0.6)
	var hp1 := float(foe.hp)
	var r2 := Combat.attack(sim)
	check(int(r2.combo) == 2 and bool(r2.swung), "a quick second swing is combo two")
	Combat.tick(sim, 0.6)
	var before := float(foe.hp)
	var r3 := Combat.attack(sim)
	var third := before - float(foe.hp)
	check(int(r3.combo) == 3, "and a third finishes the combo")
	Combat.tick(sim, 3.0)
	var r4 := Combat.attack(sim)
	check(int(r4.combo) == 1, "after a pause the combo starts over")
	# the finisher hits harder than an opener on average, and shoves the foe back
	var s2 := _sim(2)
	var f2 := _zombie(s2, Vector2(10.8, 10.0))
	var x0 := float(f2.pos[0])
	Combat.attack(s2)
	Combat.tick(s2, 0.6)
	Combat.attack(s2)
	Combat.tick(s2, 0.6)
	var pre := float(f2.hp)
	Combat.attack(s2)
	check(float(f2.pos[0]) > x0 + 0.3, "the finisher knocks the foe back")
	check(sim.minutes < float(f2.get("stun_until", 0.0)), "and staggers it")
	# arcs: behind you is safe, far away is safe
	var s3 := _sim(3)
	var behind := _zombie(s3, Vector2(9.0, 10.0))
	var far := _zombie(s3, Vector2(14.0, 10.0))
	var res := Combat.attack(s3)
	check(int(res.hits) == 0 and float(behind.hp) == 500.0 and float(far.hp) == 500.0, "foes behind or out of reach are missed")
	# a spear thrust is narrow, a club is wide
	var spear := _sim(4)
	spear.armory["spear"] = 1
	Weapons.chief_equip(spear, "spear")
	_zombie(spear, Vector2(11.4, 11.6))
	check(int(Combat.attack(spear).hits) == 0, "a narrow thrust misses off to the side")
	var club := _sim(4)
	club.armory["club"] = 1
	Weapons.chief_equip(club, "club")
	_zombie(club, Vector2(10.6, 11.0))
	check(int(Combat.attack(club).hits) == 1, "a wide club swing catches it")
	# sweeping hits several at once
	var sweep := _sim(5)
	sweep.armory["sword"] = 1
	Weapons.chief_equip(sweep, "sword")
	_zombie(sweep, Vector2(10.9, 10.0))
	_zombie(sweep, Vector2(10.8, 10.5))
	_zombie(sweep, Vector2(10.8, 9.5))
	check(int(Combat.attack(sweep).hits) == 3, "a sword sweeps several foes")
	# walls stop swings
	# heavy attacks
	var h := _sim(6)
	var hf := _zombie(h, Vector2(10.9, 10.0))
	var stamina := float(Combat.fighter(h).stamina)
	var hx := float(hf.pos[0])
	var heavy := Combat.attack(h, true)
	check(bool(heavy.swung) and bool(heavy.heavy) and float(Combat.fighter(h).stamina) < stamina - 10.0, "a heavy swing costs a lot of stamina")
	check(float(hf.pos[0]) > hx + 0.6, "and throws the foe back")
	check(float(Combat.fighter(h).cd) > 0.8, "and is slow to recover from")
	# stamina limits attacks
	var tired := _sim(7)
	Combat.fighter(tired).stamina = 1.0
	check(not bool(Combat.attack(tired, true).swung), "no stamina, no heavy swing")
	Combat.tick(tired, 0.1)
	Combat.tick(tired, 3.0)
	check(float(Combat.fighter(tired).stamina) > 20.0, "stamina comes back with rest")
	# a bow needs arrows
	var archer := _sim(8)
	archer.armory["bow"] = 1
	Weapons.chief_equip(archer, "bow")
	_zombie(archer, Vector2(14.0, 10.0))
	var dry := Combat.attack(archer)
	check(not bool(dry.swung) and str(dry.message).contains("arrows"), "a bow without arrows does nothing")
	check(Weapons.craft(archer, "arrow", 1).ok and Weapons.in_armory(archer, "arrow") == 10, "arrows come in bundles of ten")
	var shot := Combat.attack(archer)
	check(bool(shot.swung) and int(shot.hits) == 1 and Weapons.in_armory(archer, "arrow") == 9, "an arrow flies and is spent")
	# critical hits happen and hit harder
	var crits := 0
	for seed_ in range(40):
		var cs := _sim(100 + seed_)
		var cz := _zombie(cs, Vector2(10.9, 10.0))
		Combat.attack(cs)
		if 500.0 - float(cz.hp) > 30.0:
			crits += 1
	check(crits > 0 and crits < 20, "some swings are critical hits (%d of 40)" % crits)
	# --- dodging ---
	var d := _sim(9)
	check(Combat.dodge(d), "you can roll")
	check(not Combat.dodge(d), "but not twice in a row")
	var mob := _zombie(d, Vector2(11.0, 10.0))
	var hp_before := float(Combat.fighter(d).hp)
	var dodged := Combat.hit_chief(d, Vector2(11.0, 10.0), 20.0)
	check(bool(dodged.dodged) and float(Combat.fighter(d).hp) == hp_before, "a blow during the roll misses")
	Combat.tick(d, 1.0)
	var hit := Combat.hit_chief(d, Vector2(11.0, 10.0), 20.0)
	check(not bool(hit.dodged) and float(Combat.fighter(d).hp) == hp_before - 20.0, "after the roll the next blow lands")
	# --- blocking ---
	var b := _sim(10)
	Combat.set_block(b, true)
	var blocked := Combat.hit_chief(b, Vector2(11.0, 10.0), 20.0)
	check(bool(blocked.blocked) and float(blocked.damage) < 12.0, "blocking a blow from the front softens it (%.1f)" % float(blocked.damage))
	var bs := _sim(10)
	bs.armory["shield"] = 1
	check(Weapons.chief_equip(bs, "shield").ok and bool(Combat.fighter(bs).shield), "the chief can carry a shield")
	Combat.set_block(bs, true)
	var shielded := Combat.hit_chief(bs, Vector2(11.0, 10.0), 20.0)
	check(float(shielded.damage) < float(blocked.damage), "a shield soaks more")
	var flank := _sim(10)
	Combat.set_block(flank, true)
	var side := Combat.hit_chief(flank, Vector2(9.0, 10.0), 20.0)
	check(not bool(side.blocked) and float(side.damage) == 20.0, "a blow from behind ignores the block")
	var broke := _sim(11)
	Combat.set_block(broke, true)
	Combat.fighter(broke).stamina = 5.0
	Combat.hit_chief(broke, Vector2(11.0, 10.0), 40.0)
	check(not bool(Combat.fighter(broke).block), "a heavy blow on a tired guard breaks it")
	var drained := _sim(12)
	Combat.set_block(drained, true)
	var st := float(Combat.fighter(drained).stamina)
	Combat.hit_chief(drained, Vector2(11.0, 10.0), 10.0)
	check(float(Combat.fighter(drained).stamina) < st, "blocking costs stamina")
	# --- wounds, knock-out and recovery ---
	var w := _sim(13)
	var bled := false
	for i in range(20):
		var ws := _sim(200 + i)
		Combat.hit_chief(ws, Vector2(11.0, 10.0), 12.0)
		if Combat.is_bleeding(ws):
			bled = true
			var hp_start := float(Combat.fighter(ws).hp)
			Combat.tick(ws, 5.0)
			check(float(Combat.fighter(ws).hp) < hp_start, "bleeding drains health")
			Combat.tick(ws, 30.0)
			check(not Combat.is_bleeding(ws), "the bleeding stops by itself")
			break
	check(bled, "a deep wound can bleed")
	Combat.hit_chief(w, Vector2(11.0, 10.0), 500.0)
	check(Combat.is_down(w) and float(Combat.fighter(w).hp) == 0.0, "a beating knocks the chief out")
	check(not bool(Combat.attack(w).swung), "you can't fight while down")
	var gold := w.money
	Combat.tick(w, Combat.KNOCKED_OUT_SECONDS + 1.0)
	check(not Combat.is_down(w) and Combat.consume_respawn(w) and not Combat.consume_respawn(w), "they come round and are carried to the plaza once")
	check(float(Combat.fighter(w).hp) > 30.0 and w.money < gold, "with some health back and a bill to pay")
	# safe indoors, out of reach in the air
	var safe := _sim(14)
	Combat.fighter(safe).safe = true
	Combat.hit_chief(safe, Vector2(11.0, 10.0), 50.0)
	check(float(Combat.fighter(safe).hp) == 100.0, "nothing hurts the chief indoors")
	# --- monsters go for the chief ---
	var m := _sim(15)
	for r in m.residents:
		r.pos = [-400.0, -400.0]
	var z := _zombie(m, Vector2(10.5, 10.0), 40.0)
	z.cd = 0.0
	var h0 := float(Combat.fighter(m).hp)
	for i in range(8):
		Survival.tick(m, 1.0)
	check(float(Combat.fighter(m).hp) < h0, "a zombie attacks the chief")
	check(int(z.target) == -2, "it picked the chief as its target")
	var air := _sim(16)
	for r in air.residents:
		r.pos = [-400.0, -400.0]
	Combat.fighter(air).air = true
	var az := _zombie(air, Vector2(10.5, 10.0), 40.0)
	az.cd = 0.0
	for i in range(8):
		Survival.tick(air, 1.0)
	check(float(Combat.fighter(air).hp) == 100.0, "a flying chief is out of a zombie's reach")
	# windup warning
	var wind := _sim(17)
	for r in wind.residents:
		r.pos = [-400.0, -400.0]
	var wz := _zombie(wind, Vector2(10.5, 10.0), 40.0)
	wz.cd = 2.0
	Survival.tick(wind, 0.1)
	check(bool(wz.get("winding", false)), "a monster about to strike shows a warning")
	# stagger stops a monster
	var stun := _sim(18)
	for r in stun.residents:
		r.pos = [-400.0, -400.0]
	var sz := _zombie(stun, Vector2(10.5, 10.0), 40.0)
	sz.cd = 0.0
	sz.stun_until = stun.minutes + 100.0
	var hs := float(Combat.fighter(stun).hp)
	for i in range(5):
		Survival.tick(stun, 1.0)
	check(float(Combat.fighter(stun).hp) == hs, "a staggered monster can't attack")
	# archers shoot from range
	var ar := _sim(19)
	for r in ar.residents:
		r.pos = [-400.0, -400.0]
	var raider := Survival.spawn(ar, "raider_archer", Vector2(14.5, 10.0))
	raider.cd = 0.0
	var ha := float(Combat.fighter(ar).hp)
	for i in range(10):
		Survival.tick(ar, 1.0)
	check(float(Combat.fighter(ar).hp) < ha and float(raider.pos[0]) > 12.0, "archers shoot from a distance without closing in")
	# raid composition
	var raid := _sim(20)
	Rival.daily(raid)
	raid.rival.known = true
	raid.rival.march = {"arrive": raid.minutes, "size": 8}
	Rival.tick(raid, 1.0)
	var kinds := {}
	for mb in raid.mobs:
		kinds[str(mb.kind)] = int(kinds.get(str(mb.kind), 0)) + 1
	check(kinds.has("raider_captain") and kinds.has("raider_archer") and kinds.has("raider") and Rival.raiders(raid) == 8, "a big warband has a captain, archers and footmen (%s)" % str(kinds))
	check(float(Survival.KINDS.raider_captain.hp) > float(Survival.KINDS.raider.hp) * 2.0, "the captain is tough")
	# fx for the art
	var fx := _sim(21)
	var target := _zombie(fx, Vector2(10.9, 10.0))
	fx.drain_fx()
	Combat.attack(fx)
	var types := {}
	for e in fx.drain_fx():
		types[str(e.type)] = e
	check(types.has("swing") and types.has("strike") and float(types.strike.amount) > 5.0 and types.strike.has("pos"), "swings and strikes announce themselves with damage numbers")
	# the art: blood, numbers, corpses, call-outs
	var art_sim := _sim(22)
	var art := CityArt.new()
	root.add_child(art)
	art.generate(art_sim)
	var tgt := _zombie(art_sim, Vector2(10.9, 10.0), 30.0)
	art_sim.drain_fx()
	Combat.attack(art_sim, true)
	for e in art_sim.drain_fx():
		art.world_event(e)
	for i in range(30):
		await process_frame
	check(art._blood_decals.size() >= 3, "a wound leaves blood on the ground (%d stains)" % art._blood_decals.size())
	check(art._corpses.size() == 1 or art_sim.mobs.size() > 0, "a slain foe leaves a body")
	var labels := 0
	for c in art.get_children():
		if c is Label3D:
			labels += 1
	check(labels >= 1, "damage numbers float up")
	art.world_event({"type": "chief_hit", "dodged": true, "blocked": false, "amount": 0.0, "from": [11.0, 10.0]})
	art.world_event({"type": "chief_hit", "dodged": false, "blocked": false, "amount": 14.0, "from": [11.0, 10.0]})
	var stains := art._blood_decals.size()
	check(stains > 3, "a wound on the chief bleeds too")
	GameSettings.set_value("blood", false)
	for e in [{"type": "strike", "mob": 99, "who": -1, "amount": 20.0, "crit": false, "heavy": false, "pos": [10.0, 10.0], "kind": "zombie", "dead": false}]:
		art.world_event(e)
	check(art._blood_decals.size() == stains, "with blood switched off there are no stains")
	GameSettings.set_value("blood", true)
	art.world_event({"type": "swing", "heavy": true, "combo": 0, "weapon": "sword", "ranged": false})
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(h.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with a fighter loads")
	check(LifeSim.new().load_data(JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))), "fresh saves load")
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	print("COMBAT TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
