class_name Survival
extends RefCounted
## Monsters and danger. Zombies and slimes wander in from the wilds at night, wolves stalk anyone working
## outside the village. Residents flee indoors, guards and the chief fight back, and anyone who is beaten down
## collapses until dawn. All state lives in LifeSim.mobs / the residents.

const GRACE_DAYS := 3
const KINDS := {
	"zombie": {"hp": 34.0, "speed": 0.055, "aggro": 9.0, "damage": 9.0, "cooldown": 10.0, "label": "Zombie", "burns": true},
	"slime": {"hp": 20.0, "speed": 0.07, "aggro": 7.0, "damage": 5.0, "cooldown": 8.0, "label": "Slime", "burns": true},
	"raider": {"hp": 55.0, "speed": 0.11, "aggro": 15.0, "damage": 12.0, "cooldown": 7.0, "label": "Redmarch raider", "burns": false},
	"raider_archer": {"hp": 38.0, "speed": 0.1, "aggro": 17.0, "damage": 7.0, "cooldown": 12.0, "label": "Redmarch archer", "burns": false, "range": 5.5, "ranged": true},
	"raider_captain": {"hp": 130.0, "speed": 0.09, "aggro": 15.0, "damage": 20.0, "cooldown": 9.0, "label": "Redmarch captain", "burns": false},
	"soldier": {"hp": 60.0, "speed": 0.115, "aggro": 14.0, "damage": 13.0, "cooldown": 7.0, "label": "Redmarch soldier", "burns": false},
	"soldier_archer": {"hp": 40.0, "speed": 0.1, "aggro": 16.0, "damage": 8.0, "cooldown": 11.0, "label": "Redmarch bowman", "burns": false, "range": 5.5, "ranged": true},
	"soldier_knight": {"hp": 160.0, "speed": 0.09, "aggro": 14.0, "damage": 22.0, "cooldown": 9.0, "label": "Redmarch knight", "burns": false},
	"wolf": {"hp": 26.0, "speed": 0.15, "aggro": 11.0, "damage": 8.0, "cooldown": 7.0, "label": "Dire wolf", "burns": false},
}
const ATTACK_RANGE := 0.9
const FLEE_RANGE := 6.0
const GUARD_SHIFT := 150.0


static func is_raider(kind: String) -> bool:
	return kind.begins_with("raider")


## Redmarch's own soldiers, standing guard at home rather than marching on the village.
static func is_garrison(kind: String) -> bool:
	return kind.begins_with("soldier")


static func hour(sim: LifeSim) -> float:
	return fmod(sim.minutes / 60.0, 24.0)


static func is_night(sim: LifeSim) -> bool:
	var h := hour(sim)
	return h >= 20.0 or h < 6.0


static func cap_for(sim: LifeSim) -> int:
	var base := clampi(1 + sim.day() / 5 + sim.stage(), 1, 9)
	var factor := GameSettings.monster_factor()
	return 0 if factor <= 0.0 else maxi(1, int(round(float(base) * factor)))


static func village_centre(sim: LifeSim) -> Vector2:
	var rect := sim.map.bounds()
	return (Vector2(rect.position) + Vector2(rect.size) * 0.5) * float(CityMap.DISTRICT)


static func village_radius(sim: LifeSim) -> float:
	var rect := sim.map.bounds()
	return maxf(float(rect.size.x), float(rect.size.y)) * float(CityMap.DISTRICT) * 0.5


static func count(sim: LifeSim, kind: String = "") -> int:
	var n := 0
	for m in sim.mobs:
		if kind == "" and bool(m.get("garrison", false)):
			continue
		if kind == "" or str(m.kind) == kind:
			n += 1
	return n


static func spawn(sim: LifeSim, kind: String, pos: Vector2) -> Dictionary:
	var spec: Dictionary = KINDS[kind]
	sim.mob_serial += 1
	var mob := {"id": sim.mob_serial, "kind": kind, "pos": [pos.x, pos.y], "hp": float(spec.hp), "max_hp": float(spec.hp), "cd": 3.0, "target": -1, "born": sim.minutes, "heading": 0.0}
	sim.mobs.append(mob)
	sim.push_fx({"type": "mob_spawn", "id": mob.id})
	return mob


static func _random_outside(sim: LifeSim, around: Vector2, min_d: float, max_d: float) -> Vector2:
	for attempt in range(12):
		var angle := sim.rng.randf() * TAU
		var p := around + Vector2(cos(angle), sin(angle)) * sim.rng.randf_range(min_d, max_d)
		var t := Vector2i(roundi(p.x), roundi(p.y))
		if not sim.map.is_water(t) and not sim.map.is_claimed_tile(t):
			return p
	return around + Vector2(max_d, 0)


static func tick(sim: LifeSim, dm: float) -> void:
	_recover(sim)
	_towers(sim, dm)
	_spawn(sim, dm)
	for mob in sim.mobs.duplicate():
		_step_mob(sim, mob, dm)
	_react(sim)
	Rival.tick(sim, dm)
	sim.threat = count(sim)


## Waves at night; wolves near workers.
static func _spawn(sim: LifeSim, dm: float) -> void:
	if sim.day() < GRACE_DAYS or sim.residents.is_empty():
		return
	sim.spawn_clock -= dm
	if sim.spawn_clock > 0.0:
		return
	sim.spawn_clock = 45.0
	var night := is_night(sim)
	if night and count(sim) < cap_for(sim):
		var centre := village_centre(sim)
		var radius := village_radius(sim)
		var wave := mini(cap_for(sim) - count(sim), 1 + sim.rng.randi_range(0, 1 + sim.stage() / 2))
		var announce := sim.last_wave_day != sim.day()
		for k in range(wave):
			var kind := "zombie" if sim.rng.randf() < 0.65 else "slime"
			spawn(sim, kind, _random_outside(sim, centre, radius + 6.0, radius + 11.0))
		if announce:
			sim.last_wave_day = sim.day()
			sim.notice("Monsters are stirring in the dark. Get everyone safe, or send the guards.")
			sim.log_event("Night %d: monsters are approaching the village." % sim.day())
	if GameSettings.monster_factor() > 0.0 and count(sim, "wolf") < 2 and sim.rng.randf() < 0.3:
		for i in range(sim.residents.size()):
			var r: Dictionary = sim.residents[i]
			var job: Dictionary = r.get("job", {})
			if not job.is_empty() and str(job.kind) != "guard" and str(job.phase) in ["approach", "work"]:
				spawn(sim, "wolf", _random_outside(sim, Vector2(float(r.pos[0]), float(r.pos[1])), 7.0, 10.0))
				sim.notice("A wolf is prowling near %s!" % r.name)
				break


## The nearest monster to a point within `reach` tiles ({} if none).
static func nearest_mob(sim: LifeSim, from: Vector2, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for m in sim.mobs:
		var d := from.distance_to(Vector2(float(m.pos[0]), float(m.pos[1])))
		if d < best_d:
			best_d = d
			best = m
	return best


## A shot from a watchtower, aimed by hand (the chief up on the lookout). Returns true if it killed.
static func tower_fire(sim: LifeSim, tower: Dictionary, mob: Dictionary) -> bool:
	var at := Vector2(float(tower.tile[0]), float(tower.tile[1]))
	sim.push_fx({"type": "arrow", "from": [at.x, at.y], "to": [mob.pos[0], mob.pos[1]]})
	return damage_mob(sim, mob, (14.0 + 6.0 * float(int(tower.level))) * Economy.efficiency(tower), -1)


## Watchtowers shoot at monsters in range: reach and damage grow with level.
static func _towers(sim: LifeSim, dm: float) -> void:
	if sim.mobs.is_empty():
		return
	for b in sim.buildings:
		if str(b.kind) != "watchtower" or int(b.level) < 1:
			continue
		b.cd = float(b.get("cd", 0.0)) - dm
		if float(b.cd) > 0.0:
			continue
		var level := int(b.level)
		var at := Vector2(float(b.tile[0]), float(b.tile[1]))
		var best := {}
		var best_d := 8.0 + float(level) * 2.0
		var best_sieging := false
		for m in sim.mobs:
			var d := at.distance_to(Vector2(float(m.pos[0]), float(m.pos[1])))
			# Monsters clawing at a wall are shot first, then whatever is nearest.
			var sieging := int(m.get("siege", -1)) >= 0
			if d < 8.0 + float(level) * 2.0 and ((sieging and not best_sieging) or (sieging == best_sieging and d < best_d)):
				best_d = d
				best = m
				best_sieging = sieging
		if best.is_empty():
			continue
		b.cd = maxf(2.5, 7.0 - float(level))
		sim.push_fx({"type": "arrow", "from": [at.x, at.y], "to": [best.pos[0], best.pos[1]]})
		damage_mob(sim, best, (6.0 + 5.0 * float(level)) * Economy.efficiency(b), -1)


static func _burns_at_dawn(mob: Dictionary) -> bool:
	return bool(KINDS[str(mob.kind)].burns)


static func _step_mob(sim: LifeSim, mob: Dictionary, dm: float) -> void:
	var spec: Dictionary = KINDS[str(mob.kind)]
	var pos := Vector2(float(mob.pos[0]), float(mob.pos[1]))
	if sim.minutes < float(mob.get("stun_until", 0.0)):
		mob.winding = false
		return
	# Sunlight burns zombies and slimes away; wolves drift off after a while.
	var h := hour(sim)
	if _burns_at_dawn(mob) and h >= 6.5 and h < 20.0:
		mob.hp = float(mob.hp) - 6.0 * dm
		if float(mob.hp) <= 0.0:
			_remove(sim, mob, false)
			return
	if str(mob.kind) == "wolf" and sim.minutes - float(mob.born) > 400.0:
		_remove(sim, mob, false)
		return
	# Choose the closest resident who is outside and standing.
	var best := -1
	var best_d := float(spec.aggro)
	var garrison := is_garrison(str(mob.kind))
	var home := Vector2(float(mob.home[0]), float(mob.home[1])) if garrison and mob.has("home") else pos
	# Redmarch's soldiers only ever fight the chief, and only while at odds with the village or after being struck.
	var hostile := not garrison or bool(mob.get("provoked", false)) or not Rival.at_peace(sim)
	for i in range(0 if garrison else sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if sim.is_inside(r) or float(r.get("down_until", 0.0)) > sim.minutes:
			continue
		var d := pos.distance_to(Vector2(float(r.pos[0]), float(r.pos[1])))
		if d < best_d:
			best_d = d
			best = i
	# The chief is fair game too (unless indoors, up a tower, or flying beyond reach of anything but arrows).
	var fighter := Combat.fighter(sim)
	if not bool(fighter.safe) and float(fighter.down_t) <= 0.0:
		var chief_d := pos.distance_to(sim.chief_pos)
		var leashed := garrison and sim.chief_pos.distance_to(home) > Rival.GARRISON_LEASH
		if hostile and not leashed and chief_d < best_d and (not bool(fighter.air) or bool(spec.get("ranged", false))):
			best_d = chief_d
			best = -2
	mob.target = best
	var raider := is_raider(str(mob.kind))
	if raider:
		# A raider with nobody to fight loots the village once it has loitered inside it.
		if best == -1 and pos.distance_to(village_centre(sim)) < village_radius(sim) + 2.0:
			mob.idle = float(mob.get("idle", 0.0)) + dm
			if float(mob.idle) >= Rival.LOOT_WAIT:
				Rival.loot(sim, mob)
				_remove(sim, mob, false)
				return
		else:
			mob.idle = maxf(0.0, float(mob.get("idle", 0.0)) - dm)
	var goal := pos
	var attacking := false
	var reach := float(spec.get("range", ATTACK_RANGE))
	if best != -1:
		goal = sim.chief_pos if best == -2 else Vector2(float(sim.residents[best].pos[0]), float(sim.residents[best].pos[1]))
		if best_d <= reach and Walls.crossing(sim, pos, goal).is_empty():
			attacking = true
		elif not Walls.crossing(sim, pos, goal).is_empty():
			# A wall is in the way: head for an open gate, else pound on the wall.
			var gate := Walls.nearest_gate(sim, pos, true)
			if not gate.is_empty():
				var gp := Walls.gate_points(gate)
				if pos.distance_to(gp.outer) > 0.7 and not bool(mob.get("passing", false)):
					goal = gp.outer
				else:
					mob.passing = true
					goal = gp.inner
		else:
			mob.passing = false
	elif garrison:
		goal = home
	elif str(mob.kind) == "wolf" and best == -1:
		var prey_farm := Farming.nearest_prey_farm(sim, pos, 16.0)
		if prey_farm.x < 1.0e8:
			goal = prey_farm
			if Farming.raid(sim, mob, dm):
				return
		else:
			goal = pos + Vector2(cos(float(mob.heading)), sin(float(mob.heading))) * 3.0
			if sim.rng.randf() < 0.05 * dm:
				mob.heading = sim.rng.randf() * TAU
	else:
		goal = village_centre(sim)
	if attacking:
		mob.cd = float(mob.cd) - dm
		mob.winding = float(mob.cd) <= 2.6 and best == -2
		if float(mob.cd) <= 0.0:
			mob.cd = float(spec.cooldown) * sim.rng.randf_range(0.85, 1.15)
			mob.winding = false
			if bool(spec.get("ranged", false)):
				sim.push_fx({"type": "arrow", "from": [pos.x, pos.y], "to": [goal.x, goal.y]})
			if best == -2:
				Combat.hit_chief(sim, pos, float(spec.damage))
			else:
				_hit_resident(sim, best, mob, float(spec.damage))
		mob.facing = (goal - pos).angle()
		return
	mob.winding = false
	var dir := (goal - pos)
	if dir.length() < 0.05 or (garrison and best == -1 and dir.length() < 1.5):
		return
	dir = dir.normalized()
	var step := float(spec.speed) * dm
	var wall_hit := {}
	mob.siege = -1
	for turn in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var cand := pos + dir.rotated(turn) * step
		var t := Vector2i(roundi(cand.x), roundi(cand.y))
		var blocking := Walls.blocks(sim, pos, cand)
		if not blocking.is_empty():
			if turn == 0.0 and (best >= 0 or raider):
				mob.facing = dir.angle()
				Walls.siege(sim, mob, blocking, dm)
				return
			if wall_hit.is_empty():
				wall_hit = blocking
			continue
		if not sim.map.solid_tiles.has(t) and not sim.map.is_water(t):
			mob.pos = [cand.x, cand.y]
			mob.facing = dir.rotated(turn).angle()
			return
	if not wall_hit.is_empty() and (best >= 0 or raider):
		mob.facing = dir.angle()
		Walls.siege(sim, mob, wall_hit, dm)


static func _hit_resident(sim: LifeSim, index: int, mob: Dictionary, damage: float) -> void:
	var r: Dictionary = sim.residents[index]
	var n: Dictionary = r.needs
	damage *= 1.0 - Weapons.guard_of(r)
	n.health = maxf(0.0, float(n.health) - damage)
	n.fun = maxf(0.0, float(n.fun) - 3.0)
	r.stress = minf(100.0, float(r.stress) + 5.0)
	sim.push_fx({"type": "hit", "who": index, "mob": mob.id})
	sim.emote(index, "anger" if sim.rng.randf() < 0.4 else "sweat", 0.0)
	if sim.rng.randf() < 0.5:
		sim.say(index, Social.pick(["Ow! Get away!", "Help!", "Monster!", "Not today, you brute!"], sim.rng))
	if float(n.health) <= 0.0:
		_down(sim, index, mob)


static func _down(sim: LifeSim, index: int, mob: Dictionary) -> void:
	var r: Dictionary = sim.residents[index]
	sim.release(index)
	r.queue.clear()
	r.job = {}
	r.route = []
	r.commanded = false
	r.remaining = 5.0
	var morning := floorf(sim.minutes / 1440.0) * 1440.0 + 1440.0 + 6.0 * 60.0 if hour(sim) >= 6.0 else floorf(sim.minutes / 1440.0) * 1440.0 + 6.0 * 60.0
	r.down_until = morning
	sim.downs += 1
	if Jobs.title_of(r) == "gatekeeper":
		var post := sim.building_by_id(int(r.get("employer", -1)))
		if not post.is_empty() and Walls.is_wall(post):
			post.condition = maxf(0.0, float(post.get("condition", 100.0)) - 35.0)
			sim.notice("The gatekeeper fell! The gate is left weak.")
	sim.log_event("%s was knocked out by a %s." % [r.name, KINDS[str(mob.kind)].label.to_lower()])
	sim.notice("%s collapsed! Protect them until morning." % r.name)
	sim.remember(r, "Day %d: A %s knocked me down. I will not forget it." % [sim.day(), KINDS[str(mob.kind)].label.to_lower()])
	Psyche.add_core(sim, r, "Day %d: A %s knocked me senseless." % [sim.day(), KINDS[str(mob.kind)].label.to_lower()], 0.7, -0.7)
	Rumors.create(sim, str(r.name), "", "downed", "%s was knocked out by a %s" % [r.name, KINDS[str(mob.kind)].label.to_lower()], -0.1, [index])
	sim.push_fx({"type": "downed", "who": index})


static func _recover(sim: LifeSim) -> void:
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		var until := float(r.get("down_until", 0.0))
		if until > 0.0 and sim.minutes >= until:
			r.down_until = 0.0
			r.needs.health = 35.0
			r.remaining = 0.0
			sim.say(i, "Ugh... is it morning already?")
			sim.log_event("%s got back on their feet." % r.name)


## Residents who are not guards run for home when a monster gets close.
static func _react(sim: LifeSim) -> void:
	if sim.mobs.is_empty():
		return
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if float(r.get("down_until", 0.0)) > sim.minutes or sim.is_inside(r):
			continue
		var job: Dictionary = r.get("job", {})
		if not job.is_empty() and str(job.kind) == "guard":
			continue
		if float(r.get("fleeing_until", 0.0)) > sim.minutes:
			continue
		var pos := Vector2(float(r.pos[0]), float(r.pos[1]))
		for mob in sim.mobs:
			if pos.distance_to(Vector2(float(mob.pos[0]), float(mob.pos[1]))) < FLEE_RANGE:
				sim.flee(i)
				break


## A swing at a monster. Returns true if it died.
static func damage_mob(sim: LifeSim, mob: Dictionary, amount: float, who: int = -1, opts: Dictionary = {}) -> bool:
	mob.hp = float(mob.hp) - amount
	var at := Vector2(float(mob.pos[0]), float(mob.pos[1]))
	if bool(mob.get("garrison", false)):
		for g in sim.mobs:
			if bool(g.get("garrison", false)):
				g.provoked = true
	var knock := float(opts.get("knock", 0.0))
	if knock > 0.0 and float(mob.hp) > 0.0:
		var from: Vector2 = opts.get("from", at - Vector2(1, 0))
		var away := (at - from).normalized()
		var cand := at + away * knock
		var tile := Vector2i(roundi(cand.x), roundi(cand.y))
		if Walls.blocks(sim, at, cand).is_empty() and not sim.map.solid_tiles.has(tile) and not sim.map.is_water(tile):
			mob.pos = [cand.x, cand.y]
	var stagger := float(opts.get("stagger", 0.0))
	if stagger > 0.0:
		mob.stun_until = sim.minutes + stagger * 4.0
	sim.push_fx({"type": "strike", "mob": mob.id, "who": who, "amount": amount, "crit": bool(opts.get("crit", false)), "heavy": bool(opts.get("heavy", false)), "pos": [at.x, at.y], "kind": mob.kind, "dead": float(mob.hp) <= 0.0})
	if float(mob.hp) > 0.0:
		return false
	_remove(sim, mob, true)
	if who >= 0 and who < sim.residents.size():
		var r: Dictionary = sim.residents[who]
		r.skills.fitness += 6
		r.points = int(r.points) + 5
		r.bond = minf(100.0, float(r.bond) + 1.0)
		sim.say(who, Social.pick(["Got it!", "That'll teach you!", "Back to the dark with you!"], sim.rng))
		sim.emote(who, "laugh", 0.0)
		sim.remember(r, "Day %d: I fought off a %s." % [sim.day(), KINDS[str(mob.kind)].label.to_lower()])
		Psyche.add_core(sim, r, "Day %d: I stood my ground against a %s." % [sim.day(), KINDS[str(mob.kind)].label.to_lower()], 0.4, 0.6)
		Rumors.create(sim, str(r.name), "", "heroic", "%s fought off a %s" % [r.name, KINDS[str(mob.kind)].label.to_lower()], 0.7, [who])
	if str(mob.kind) == "wolf":
		sim.food += 2
	elif is_raider(str(mob.kind)):
		Rival.on_raider_killed(sim, who)
	elif is_garrison(str(mob.kind)):
		Rival.on_soldier_killed(sim, who)
	else:
		sim.money += 3
	sim.kills += 1
	return true


static func _remove(sim: LifeSim, mob: Dictionary, killed: bool) -> void:
	sim.mobs.erase(mob)
	sim.push_fx({"type": "mob_gone", "id": mob.id, "killed": killed, "pos": mob.pos, "kind": mob.kind})


## Combat for residents: anyone beside a monster hits back, guards hit harder.
static func resident_fight(sim: LifeSim, index: int, dm: float) -> void:
	var r: Dictionary = sim.residents[index]
	if sim.mobs.is_empty() or float(r.get("down_until", 0.0)) > sim.minutes or sim.is_inside(r):
		return
	r.fight_cd = float(r.get("fight_cd", 0.0)) - dm
	if float(r.fight_cd) > 0.0:
		return
	var pos := Vector2(float(r.pos[0]), float(r.pos[1]))
	var job: Dictionary = r.get("job", {})
	var guard := not job.is_empty() and str(job.kind) == "guard"
	for mob in sim.mobs:
		var foe := Vector2(float(mob.pos[0]), float(mob.pos[1]))
		if pos.distance_to(foe) <= Weapons.reach_of(r) and Walls.crossing(sim, pos, foe).is_empty():
			r.fight_cd = 5.0
			var amount := (5.0 + float(r.skills.fitness) / 14.0 + float(r.skills.craft) / 40.0 + (9.0 if guard else 0.0) + (4.0 if Jobs.title_of(r) == "guard" else 0.0)) * Weapons.power_of(r)
			if Weapons.weapon_of(r) == "bow":
				sim.push_fx({"type": "arrow", "from": [pos.x, pos.y], "to": [foe.x, foe.y]})
			damage_mob(sim, mob, amount, index)
			return
