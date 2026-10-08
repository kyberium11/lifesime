class_name Rival
extends RefCounted
## The rival town. Redmarch is a big walled town a short flight east of the village (about 200 world units beyond its eastern border). Word of it reaches the
## village after a week or so. Its mood towards the village drifts hostile; when it turns bad enough it sends a warband
## that marches for a day or two and then arrives at the village's eastern edge as raiders. The chief can prepare (arm the
## guards), hold them off, buy peace with envoys and tribute, or take the fight to them with armed residents.

const NAME := "Redmarch"
## The town's gate wall stands this many tiles beyond the village's eastern edge (50 tiles = 200 world units), and its
## centre is TOWN_HALF_TILES further on.
const GAP_TILES := 50.0
const TOWN_HALF_TILES := 8.5
const DISCOVER_DAY := 8
const FIRST_RAID_DAY := 14
const HOSTILE_BELOW := -35.0
const MARCH_MINUTES := 1.5 * 1440.0
const ENVOY_COST := 80
const TRIBUTE_COST := 300
const ATTACK_MIN_FIGHTERS := 3
const ATTACK_COOLDOWN_DAYS := 5
const LOOT_WAIT := 90.0
const TRIBUTE_INCOME := 40
## Soldiers stand guard when the chief comes within GARRISON_RADIUS tiles of the town, chase them no further than
## GARRISON_LEASH from home, and go back to barracks when the chief is more than GARRISON_DESPAWN away.
const GARRISON_RADIUS := 30.0
const GARRISON_LEASH := 42.0
const GARRISON_DESPAWN := 80.0


## Where the town stands: due east of the village's current eastern edge.
static func _spot(sim: LifeSim) -> Vector2:
	var rect := sim.map.bounds()
	var edge := float((rect.position.x + rect.size.x) * CityMap.DISTRICT)
	return Vector2(edge + GAP_TILES + TOWN_HALF_TILES, Survival.village_centre(sim).y)


static func ensure(sim: LifeSim) -> void:
	if not sim.rival.is_empty():
		# Saves from when the town was five kilometres away: bring it in to a short flight.
		if float(sim.rival.pos[0]) - Survival.village_centre(sim).x > 400.0:
			var spot := _spot(sim)
			sim.rival.pos = [spot.x, spot.y]
		return
	var spot := _spot(sim)
	sim.rival = {"name": NAME, "pos": [spot.x, spot.y], "known": false, "pop": 140, "soldiers": 18, "wealth": 4000.0, "attitude": -12.0, "grudge": -45.0,
		"truce_until": 0.0, "march": {}, "raid": {}, "raids": 0, "repelled": 0, "looted": 0, "last_raid_day": 0, "last_attack_day": -99, "defeated": false, "attacks_won": 0, "attacks_lost": 0}


## How many raiders of any kind are alive.
static func raiders(sim: LifeSim) -> int:
	var n := 0
	for m in sim.mobs:
		if Survival.is_raider(str(m.kind)):
			n += 1
	return n


static func known(sim: LifeSim) -> bool:
	return not sim.rival.is_empty() and bool(sim.rival.known)


static func at_peace(sim: LifeSim) -> bool:
	return not sim.rival.is_empty() and (bool(sim.rival.defeated) or sim.minutes < float(sim.rival.truce_until))


static func position(sim: LifeSim) -> Vector2:
	ensure(sim)
	return Vector2(float(sim.rival.pos[0]), float(sim.rival.pos[1]))


## Open ground between the village's eastern edge and the town's gate wall, in world units.
static func gap_units(sim: LifeSim) -> float:
	var rect := sim.map.bounds()
	var edge := float((rect.position.x + rect.size.x) * CityMap.DISTRICT)
	return (position(sim).x - TOWN_HALF_TILES - edge) * CityMap.TILE


static func mood_word(sim: LifeSim) -> String:
	if sim.rival.is_empty():
		return "unknown"
	if bool(sim.rival.defeated):
		return "beaten and paying tribute"
	var a := float(sim.rival.attitude)
	if a < -60.0:
		return "furious"
	if a < HOSTILE_BELOW:
		return "hostile"
	if a < -10.0:
		return "wary"
	if a < 25.0:
		return "cool"
	return "friendly"


# --- each day ------------------------------------------------------------------------------------------------------------

static func daily(sim: LifeSim) -> void:
	ensure(sim)
	var rv: Dictionary = sim.rival
	if not bool(rv.known) and sim.day() >= DISCOVER_DAY:
		rv.known = true
		sim.notice("A traveller tells of %s, a large walled town a short flight to the east." % NAME)
		sim.log_event("Word reached the village of %s, a big walled town a short flight east." % NAME)
	rv.pop = mini(400, int(rv.pop) + (1 if sim.rng.randf() < 0.6 else 0))
	rv.wealth = float(rv.wealth) + float(rv.pop) * 1.6 * sim.rng.randf_range(0.8, 1.2)
	var hostility := clampf((-float(rv.attitude)) / 100.0, 0.0, 1.0)
	var want := int(float(rv.pop) * (0.1 + 0.14 * hostility))
	if int(rv.soldiers) < want:
		rv.soldiers = int(rv.soldiers) + 1
	if bool(rv.defeated):
		sim.money += TRIBUTE_INCOME
		return
	# Mood drifts back towards its grudge, with envy pushing it down if the village is doing well.
	var drift := 1.0 if float(rv.attitude) < float(rv.grudge) else -1.0
	rv.attitude = clampf(float(rv.attitude) + drift * 0.8 + sim.rng.randf_range(-0.6, 0.4), -100.0, 100.0)
	if float(sim.money) > float(rv.wealth) * 3.0:
		rv.attitude = clampf(float(rv.attitude) - 0.8, -100.0, 100.0)
	if bool(rv.known) and sim.auto_plan:
		council_prepare(sim)
	if not bool(rv.known) or not (rv.march as Dictionary).is_empty() or not (rv.raid as Dictionary).is_empty():
		return
	if sim.day() < FIRST_RAID_DAY or sim.minutes < float(rv.truce_until) or GameSettings.monster_factor() <= 0.0:
		return
	var gap := 4 if float(rv.attitude) < -70.0 else 6
	if float(rv.attitude) < HOSTILE_BELOW and sim.day() - int(rv.last_raid_day) >= gap and sim.rng.randf() < 0.55:
		plan_raid(sim)


## The council does not wait to be told: with an unfriendly neighbour it has weapons forged and the guards armed.
static func council_prepare(sim: LifeSim) -> void:
	if float(sim.rival.attitude) > -5.0 and int(sim.rival.raids) == 0:
		return
	var want := mini(Weapons.fighters(sim).size(), 4 + int(sim.rival.soldiers) / 4)
	var forged := 0
	while Weapons.armed_count(sim) + _stock(sim) < want and forged < 3 and sim.money > 300:
		var made := false
		for kind in ["sword", "spear", "club"]:
			if Weapons.craft(sim, kind, 1).ok:
				made = true
				break
		if not made:
			break
		forged += 1
	if Weapons.in_armory(sim, "shield") < 2 and sim.money > 600:
		Weapons.craft(sim, "shield", 1)
	var given := Weapons.arm_guards(sim)
	if int(given.armed) > 0:
		sim.log_event("The council armed %d guard%s." % [int(given.armed), "" if int(given.armed) == 1 else "s"])


static func _stock(sim: LifeSim) -> int:
	var n := 0
	for kind in Weapons.RANK:
		n += Weapons.in_armory(sim, kind)
	return n


## A warband sets out; it reaches the village after a day or two.
static func plan_raid(sim: LifeSim) -> void:
	var rv: Dictionary = sim.rival
	var size := clampi(int(round(float(rv.soldiers) * 0.28 * sim.rng.randf_range(0.8, 1.25) * GameSettings.monster_factor())), 2, 14)
	rv.march = {"arrive": sim.minutes + MARCH_MINUTES, "size": size}
	rv.last_raid_day = sim.day()
	sim.notice("Scouts report a %s warband marching on the village: about %d fighters, arriving in a day or two." % [NAME, size])
	sim.log_event("%s sent a warband of %d against the village." % [NAME, size])
	sim.push_fx({"type": "warband_sighted"})


static func _launch(sim: LifeSim) -> void:
	var rv: Dictionary = sim.rival
	var size := int((rv.march as Dictionary).size)
	rv.march = {}
	var centre := Survival.village_centre(sim)
	var radius := Survival.village_radius(sim) + 9.0
	for i in range(size):
		var a := sim.rng.randf_range(-0.6, 0.6)
		var p := centre + Vector2(cos(a), sin(a)) * (radius + sim.rng.randf_range(0.0, 4.0))
		# A captain leads bigger warbands; every fourth fighter is an archer.
		var kind := "raider"
		if i == 0 and size >= 6:
			kind = "raider_captain"
		elif i % 4 == 3:
			kind = "raider_archer"
		Survival.spawn(sim, kind, p)
	rv.raid = {"size": size, "started": sim.minutes, "loot": 0}
	rv.raids = int(rv.raids) + 1
	sim.notice("%s raiders are at the eastern edge of the village! Arm up and hold them off." % NAME)
	sim.log_event("%d %s raiders attacked the village from the east." % [size, NAME])


## Called every simulation step: warbands arrive, raids end.
static func tick(sim: LifeSim, _dm: float) -> void:
	if sim.rival.is_empty():
		return
	var rv: Dictionary = sim.rival
	garrison_tick(sim)
	var march: Dictionary = rv.march
	if not march.is_empty() and sim.minutes >= float(march.arrive):
		_launch(sim)
		return
	var raid: Dictionary = rv.raid
	if raid.is_empty():
		return
	if raiders(sim) == 0:
		_end_raid(sim)


## Redmarch's soldiers currently on their feet.
static func garrison(sim: LifeSim) -> Array:
	var out: Array = []
	for m in sim.mobs:
		if bool(m.get("garrison", false)):
			out.append(m)
	return out


## Soldiers appear at the gate when the chief comes near, and stand down when they go away.
static func garrison_tick(sim: LifeSim) -> void:
	var rv: Dictionary = sim.rival
	var spot := position(sim)
	var dist := sim.chief_pos.distance_to(spot)
	var alive := garrison(sim)
	if dist > GARRISON_DESPAWN:
		for m in alive:
			Survival._remove(sim, m, false)
		return
	if dist > GARRISON_RADIUS or not alive.is_empty() or bool(rv.defeated) or int(rv.soldiers) <= 2 or int(rv.get("garrison_day", -1)) == sim.day():
		return
	rv.garrison_day = sim.day()
	var n := clampi(int(rv.soldiers) / 3, 4, 12)
	var gate := Vector2(spot.x - TOWN_HALF_TILES - 2.5, spot.y)
	for i in range(n):
		var kind := "soldier"
		if i == 0 and n >= 8:
			kind = "soldier_knight"
		elif i % 4 == 3:
			kind = "soldier_archer"
		var at := gate + Vector2(sim.rng.randf_range(-4.0, 2.5), sim.rng.randf_range(-4.5, 4.5))
		var m := Survival.spawn(sim, kind, at)
		m.garrison = true
		m.home = [at.x, at.y]
		m.provoked = false
	if at_peace(sim):
		sim.notice("%s's guards watch you carefully. Don't provoke them." % NAME)
	else:
		sim.notice("%s's soldiers have seen you! They are coming for you." % NAME)


## One of the town's own soldiers has fallen: the town is weaker and angrier, and the loot is yours.
static func on_soldier_killed(sim: LifeSim, who: int) -> void:
	var rv: Dictionary = sim.rival
	rv.soldiers = maxi(0, int(rv.soldiers) - 1)
	rv.attitude = clampf(float(rv.attitude) - 4.0, -100.0, 100.0)
	rv.grudge = clampf(float(rv.grudge) - 1.0, -100.0, 0.0)
	rv.wealth = maxf(0.0, float(rv.wealth) - 25.0)
	sim.money += 20
	if sim.rng.randf() < 0.2:
		sim.armory["sword"] = Weapons.in_armory(sim, "sword") + 1
		sim.notice("A fallen soldier dropped a sword. It is in the armory.")
	if who >= 0 and who < sim.residents.size():
		Psyche.add_core(sim, sim.residents[who], "Day %d: I fought a %s soldier." % [sim.day(), NAME], 0.4, 0.4)
	if int(rv.soldiers) <= 2 and not bool(rv.defeated):
		_surrender(sim)


static func _surrender(sim: LifeSim) -> void:
	sim.rival.defeated = true
	sim.rival.truce_until = sim.minutes + 99999.0
	sim.rival.march = {}
	sim.notice("%s has surrendered to the village!" % NAME)
	sim.log_event("%s surrendered to the village and will pay tribute." % NAME)
	for m in garrison(sim):
		Survival._remove(sim, m, false)


static func _end_raid(sim: LifeSim) -> void:
	var rv: Dictionary = sim.rival
	var raid: Dictionary = rv.raid
	rv.raid = {}
	var loot := int(raid.loot)
	if loot > 0:
		sim.notice("The raiders made off with %d coins." % loot)
		sim.log_event("%s raiders escaped with %d coins." % [NAME, loot])
		rv.attitude = clampf(float(rv.attitude) + 5.0, -100.0, 100.0)
		rv.grudge = clampf(float(rv.grudge) - 2.0, -100.0, 0.0)
	else:
		rv.repelled = int(rv.repelled) + 1
		rv.soldiers = maxi(3, int(rv.soldiers) - int(raid.size))
		rv.truce_until = sim.minutes + 6.0 * 1440.0
		rv.grudge = clampf(float(rv.grudge) + 3.0, -100.0, 0.0)
		sim.notice("The %s raid is beaten back. They will think twice before coming again." % NAME)
		sim.log_event("The village beat back the %s raiders." % NAME)
		for r in sim.residents:
			r.stress = maxf(0.0, float(r.stress) - 3.0)
			r.needs.fun = minf(100.0, float(r.needs.fun) + 4.0)


## A raider with nobody to fight grabs what it can: called by the monster logic once it has loitered.
static func loot(sim: LifeSim, mob: Dictionary) -> int:
	var take := mini(sim.money, maxi(15, int(float(sim.money) * 0.02)))
	take = mini(take, 400)
	sim.money -= take
	if not sim.rival.is_empty():
		sim.rival.wealth = float(sim.rival.wealth) + float(take)
		sim.rival.looted = int(sim.rival.looted) + take
		if not (sim.rival.raid as Dictionary).is_empty():
			sim.rival.raid.loot = int(sim.rival.raid.loot) + take
	return take


## A raider has been cut down: their blade may be worth keeping.
static func on_raider_killed(sim: LifeSim, who: int) -> void:
	sim.money += 10
	if sim.rng.randf() < 0.25:
		sim.armory["sword"] = Weapons.in_armory(sim, "sword") + 1
		sim.notice("A fallen raider dropped a sword. It is in the armory.")
	elif sim.rng.randf() < 0.3:
		sim.armory["shield"] = Weapons.in_armory(sim, "shield") + 1
		sim.notice("A fallen raider dropped a shield. It is in the armory.")
	if who >= 0 and who < sim.residents.size():
		Psyche.add_core(sim, sim.residents[who], "Day %d: I fought off a %s raider." % [sim.day(), NAME], 0.5, 0.6)


# --- the chief's choices ------------------------------------------------------------------------------------------------

static func envoy(sim: LifeSim) -> Dictionary:
	if not known(sim):
		return {"ok": false, "message": "The village has not heard of any other town yet."}
	if bool(sim.rival.defeated):
		return {"ok": false, "message": "%s already answers to you." % NAME}
	if sim.money < ENVOY_COST:
		return {"ok": false, "message": "An envoy costs %d coins for the journey and gifts." % ENVOY_COST}
	sim.money -= ENVOY_COST
	var gain := 12.0 + sim.rng.randf_range(0.0, 6.0)
	sim.rival.attitude = clampf(float(sim.rival.attitude) + gain, -100.0, 100.0)
	sim.rival.grudge = clampf(float(sim.rival.grudge) + 2.0, -100.0, 0.0)
	sim.log_event("An envoy was sent to %s." % NAME)
	return {"ok": true, "message": "Your envoy was received coolly but politely. %s is now %s towards you (%d coins)." % [NAME, mood_word(sim), ENVOY_COST]}


static func tribute(sim: LifeSim) -> Dictionary:
	if not known(sim):
		return {"ok": false, "message": "The village has not heard of any other town yet."}
	if bool(sim.rival.defeated):
		return {"ok": false, "message": "%s pays tribute to you now, not the other way round." % NAME}
	if sim.money < TRIBUTE_COST:
		return {"ok": false, "message": "Tribute costs %d coins." % TRIBUTE_COST}
	sim.money -= TRIBUTE_COST
	sim.rival.wealth = float(sim.rival.wealth) + float(TRIBUTE_COST)
	sim.rival.attitude = clampf(float(sim.rival.attitude) + 25.0, -100.0, 100.0)
	sim.rival.truce_until = maxf(float(sim.rival.truce_until), sim.minutes + 7.0 * 1440.0)
	sim.rival.march = {}
	sim.log_event("The village paid %d coins in tribute to %s." % [TRIBUTE_COST, NAME])
	return {"ok": true, "message": "Tribute delivered (%d coins). %s promises a week of peace." % [TRIBUTE_COST, NAME]}


static func peace(sim: LifeSim) -> Dictionary:
	if not known(sim):
		return {"ok": false, "message": "The village has not heard of any other town yet."}
	if bool(sim.rival.defeated):
		return {"ok": false, "message": "%s has already surrendered." % NAME}
	if float(sim.rival.attitude) < -55.0 and sim.minutes >= float(sim.rival.truce_until):
		return {"ok": false, "message": "%s will not listen to words right now. Send an envoy or pay tribute first." % NAME}
	sim.rival.truce_until = maxf(float(sim.rival.truce_until), sim.minutes + 8.0 * 1440.0)
	sim.rival.march = {}
	sim.log_event("A truce was agreed with %s." % NAME)
	return {"ok": true, "message": "%s agrees to a truce of about a week." % NAME}


## Fighters who could march on the rival: armed adults on their feet.
static func strike_force(sim: LifeSim) -> Array:
	var out: Array = []
	for i in Weapons.fighters(sim):
		if Weapons.weapon_of(sim.residents[i]) != "":
			out.append(i)
	return out


static func our_strength(sim: LifeSim, force: Array) -> float:
	var s := 0.0
	for i in force:
		var r: Dictionary = sim.residents[i]
		s += Weapons.power_of(r) * (1.0 + float(r.skills.fitness) / 100.0) * (1.15 if Weapons.has_shield(r) else 1.0) * (1.25 if Weapons.is_guard(r) else 1.0)
	return s * 10.0


static func their_strength(sim: LifeSim) -> float:
	return float(sim.rival.soldiers) * 2.6 * 1.25


## Send every armed resident against the rival. They march, fight and come home hurt. Returns {ok, message}.
static func attack(sim: LifeSim) -> Dictionary:
	if not known(sim):
		return {"ok": false, "message": "There is nobody to attack: the village has not heard of another town."}
	if bool(sim.rival.defeated):
		return {"ok": false, "message": "%s has already surrendered." % NAME}
	var force := strike_force(sim)
	if force.size() < ATTACK_MIN_FIGHTERS:
		return {"ok": false, "message": "You need at least %d armed fighters to march on %s (you have %d). Forge weapons and arm people." % [ATTACK_MIN_FIGHTERS, NAME, force.size()]}
	if sim.day() - int(sim.rival.last_attack_day) < ATTACK_COOLDOWN_DAYS:
		return {"ok": false, "message": "The fighters are still recovering from the last march."}
	var ours := our_strength(sim, force)
	var theirs := their_strength(sim)
	var chance := ours / (ours + theirs)
	var won := sim.rng.randf() < chance
	sim.rival.last_attack_day = sim.day()
	for i in force:
		sim.residents[i].down_until = sim.minutes + 2.0 * 1440.0
		sim.release(i)
	var head := "%d armed residents marched on %s (strength %d against about %d)." % [force.size(), NAME, int(ours), int(theirs)]
	if won:
		var loot := mini(int(float(sim.rival.wealth) * 0.25), 2500)
		sim.money += loot
		sim.rival.wealth = float(sim.rival.wealth) - float(loot)
		var killed := mini(int(sim.rival.soldiers), maxi(2, int(ceil(float(force.size()) * 1.6))))
		sim.rival.soldiers = int(sim.rival.soldiers) - killed
		sim.rival.attitude = clampf(float(sim.rival.attitude) - 20.0, -100.0, 100.0)
		sim.rival.attacks_won = int(sim.rival.attacks_won) + 1
		sim.rival.march = {}
		var msg := "%s Victory! %d of their soldiers fell and the village took %d coins in plunder. Your fighters need two days to recover." % [head, killed, loot]
		if int(sim.rival.soldiers) <= 2:
			_surrender(sim)
			msg += " %s surrenders and will pay tribute every day." % NAME
		sim.log_event("The village's fighters defeated %s's defenders and took %d coins." % [NAME, loot])
		return {"ok": true, "message": msg}
	for i in force:
		if sim.rng.randf() < 0.5:
			sim.residents[i].weapon = ""
		sim.residents[i].needs.health = minf(float(sim.residents[i].needs.health), 20.0)
	sim.rival.attitude = clampf(float(sim.rival.attitude) - 8.0, -100.0, 100.0)
	sim.rival.grudge = clampf(float(sim.rival.grudge) - 4.0, -100.0, 0.0)
	sim.rival.attacks_lost = int(sim.rival.attacks_lost) + 1
	sim.log_event("The village's fighters were driven back from %s." % NAME)
	return {"ok": false, "message": "%s Defeat. Your fighters were driven back, some lost their arms, and %s is angrier than ever." % [head, NAME]}


static func report(sim: LifeSim) -> String:
	if not known(sim):
		return "Nobody has told us of any other town yet."
	var rv: Dictionary = sim.rival
	var parts: Array = ["%s: a walled town of about %d people, some %d metres east of our border. They are %s towards us." % [NAME, int(round(float(rv.pop) / 10.0)) * 10, int(round(gap_units(sim) / 10.0)) * 10, mood_word(sim)]]
	if not bool(rv.defeated):
		parts.append("Their army is roughly %d." % (int(round(float(rv.soldiers) / 3.0)) * 3))
	if not (rv.march as Dictionary).is_empty():
		var hours := int(ceil((float(rv.march.arrive) - sim.minutes) / 60.0))
		parts.append("A warband of about %d is marching on us, arriving in about %d hours." % [int(rv.march.size), maxi(1, hours)])
	elif not (rv.raid as Dictionary).is_empty():
		parts.append("Their raiders are in the village now: %d still standing." % raiders(sim))
	elif sim.minutes < float(rv.truce_until) and not bool(rv.defeated):
		parts.append("A truce holds for about %d more days." % int(ceil((float(rv.truce_until) - sim.minutes) / 1440.0)))
	parts.append("Raids so far: %d (%d beaten back, %d coins lost). Our strike force: %d armed fighters." % [int(rv.raids), int(rv.repelled), int(rv.looted), strike_force(sim).size()])
	return " ".join(parts)
