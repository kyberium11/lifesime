class_name Combat
extends RefCounted
## Hands-on fighting for the chief. A light attack chains into a three-hit combo, a heavy attack is slow and knocks foes
## back, a dodge roll gives a moment of invulnerability, and holding block soaks most of a blow from the front. Every move
## costs stamina. The chief has health too: monsters and raiders go for them, wounds bleed, and a beating leaves them
## knocked out until they come round back at the plaza. All timers here are real seconds; the chief's state lives in
## LifeSim.fighter so it is saved with the village.

const MAX_HP := 100.0
const MAX_STAMINA := 100.0
const COMBO_WINDOW := 1.1
const COMBO_MULT := [1.0, 1.0, 1.6]
const HEAVY_MULT := 2.4
const HEAVY_STAMINA := 3.2
const HEAVY_SWING := 2.6
const DODGE_COST := 22.0
const DODGE_TIME := 0.5
const DODGE_COOLDOWN := 0.8
const DODGE_DASH := 0.32
const BLOCK_FRONT := 0.3
const SHIELD_ABSORB := 0.75
const PARRY_ABSORB := 0.45
const KNOCKED_OUT_SECONDS := 12.0
const BLEED_SECONDS := 20.0
const BLEED_PER_SECOND := 1.2
const CRIT_CHANCE := 0.12
const HEAVY_CRIT_CHANCE := 0.22
const DEFAULTS := {
	"hp": 100.0, "max_hp": 100.0, "stamina": 100.0, "max_stamina": 100.0, "cd": 0.0, "combo": 0, "combo_t": 0.0, "block": false, "shield": false,
	"dodge_t": 0.0, "dodge_cd": 0.0, "down_t": 0.0, "bleed_t": 0.0, "bleed_drip": 0.0, "hurt_t": 0.0, "since_hit": 99.0, "rest_t": 0.0, "facing": [0.0, 1.0],
	"air": false, "safe": false, "respawn": false, "kills": 0, "last_swing": "",
}


static func fighter(sim: LifeSim) -> Dictionary:
	var f: Dictionary = sim.fighter
	for k in DEFAULTS:
		if not f.has(k):
			f[k] = DEFAULTS[k].duplicate() if DEFAULTS[k] is Array else DEFAULTS[k]
	return f


static func is_down(sim: LifeSim) -> bool:
	return float(fighter(sim).down_t) > 0.0


static func is_bleeding(sim: LifeSim) -> bool:
	return float(fighter(sim).bleed_t) > 0.0


static func facing(sim: LifeSim) -> Vector2:
	var a: Array = fighter(sim).facing
	return Vector2(float(a[0]), float(a[1])).normalized()


static func set_facing(sim: LifeSim, dir: Vector2) -> void:
	if dir.length() > 0.01:
		fighter(sim).facing = [dir.normalized().x, dir.normalized().y]


static func stamina_fraction(sim: LifeSim) -> float:
	return clampf(float(fighter(sim).stamina) / float(fighter(sim).max_stamina), 0.0, 1.0)


## True while the chief is in a fight worth showing the bars for.
static func engaged(sim: LifeSim) -> bool:
	var f := fighter(sim)
	return float(f.since_hit) < 8.0 or float(f.hurt_t) > 0.0 or float(f.hp) < float(f.max_hp) - 0.5 or float(f.stamina) < float(f.max_stamina) - 1.0 or bool(f.block) or float(f.down_t) > 0.0


# --- real-time upkeep ----------------------------------------------------------------------------------------------------

static func tick(sim: LifeSim, dt: float) -> void:
	var f := fighter(sim)
	f.cd = maxf(0.0, float(f.cd) - dt)
	f.combo_t = maxf(0.0, float(f.combo_t) - dt)
	if float(f.combo_t) <= 0.0:
		f.combo = 0
	f.dodge_t = maxf(0.0, float(f.dodge_t) - dt)
	f.dodge_cd = maxf(0.0, float(f.dodge_cd) - dt)
	f.hurt_t = maxf(0.0, float(f.hurt_t) - dt)
	f.since_hit = float(f.since_hit) + dt
	f.rest_t = maxf(0.0, float(f.rest_t) - dt)
	if float(f.down_t) > 0.0:
		f.down_t = float(f.down_t) - dt
		f.block = false
		if float(f.down_t) <= 0.0:
			f.down_t = 0.0
			f.hp = float(f.max_hp) * 0.4
			f.stamina = float(f.max_stamina) * 0.5
			f.bleed_t = 0.0
			f.respawn = true
			var fee := mini(300, int(float(sim.money) * 0.03))
			sim.money -= fee
			sim.notice("You come round at the plaza. The healer's bill was %d coins." % fee)
			sim.log_event("The chief was knocked out and carried to safety.")
		return
	if bool(f.block):
		if float(f.stamina) <= 0.0:
			f.block = false
		f.stamina = minf(float(f.max_stamina), float(f.stamina) + 4.0 * dt)
	elif float(f.rest_t) <= 0.0:
		f.stamina = minf(float(f.max_stamina), float(f.stamina) + 17.0 * dt)
	if float(f.bleed_t) > 0.0:
		f.bleed_t = float(f.bleed_t) - dt
		f.hp = maxf(1.0, float(f.hp) - BLEED_PER_SECOND * dt)
		f.bleed_drip = float(f.bleed_drip) + dt
		if float(f.bleed_drip) >= 0.9:
			f.bleed_drip = 0.0
			sim.push_fx({"type": "chief_drip"})
	elif float(f.since_hit) > 8.0 and float(f.hp) < float(f.max_hp):
		f.hp = minf(float(f.max_hp), float(f.hp) + 1.5 * dt)


## The chief has been carried back: stand them up and clear the flag.
static func consume_respawn(sim: LifeSim) -> bool:
	var f := fighter(sim)
	if bool(f.respawn):
		f.respawn = false
		return true
	return false


# --- the chief's moves ---------------------------------------------------------------------------------------------------

static func set_block(sim: LifeSim, on: bool) -> void:
	var f := fighter(sim)
	f.block = on and float(f.stamina) > 3.0 and float(f.down_t) <= 0.0 and float(f.dodge_t) <= 0.0


## Swing (or loose an arrow). Returns {swung, hits, kills, heavy, combo, message}.
static func attack(sim: LifeSim, heavy: bool = false) -> Dictionary:
	var f := fighter(sim)
	var out := {"swung": false, "hits": 0, "kills": 0, "heavy": heavy, "combo": 0, "message": ""}
	if float(f.down_t) > 0.0 or float(f.cd) > 0.0 or bool(f.block):
		return out
	var weapon := sim.chief_weapon
	var ranged := weapon == "bow"
	var cost := Weapons.stamina_of_weapon(weapon) * (HEAVY_STAMINA if heavy else 1.0)
	if float(f.stamina) < cost * 0.5:
		out.message = "Out of breath."
		return out
	if ranged and Weapons.in_armory(sim, "arrow") <= 0:
		out.message = "No arrows. Forge some at the workshop."
		return out
	f.stamina = maxf(0.0, float(f.stamina) - cost)
	f.rest_t = 0.7
	f.cd = Weapons.swing_of_weapon(weapon) * (HEAVY_SWING if heavy else 1.0)
	var combo := 0
	if not heavy:
		combo = int(f.combo) + 1 if float(f.combo_t) > 0.0 else 1
		if combo > 3:
			combo = 1
		f.combo = combo
		f.combo_t = COMBO_WINDOW
	else:
		f.combo = 0
		f.combo_t = 0.0
	out.swung = true
	out.combo = combo
	var mult: float = HEAVY_MULT if heavy else float(COMBO_MULT[combo - 1])
	var base := Weapons.chief_damage(sim) * mult
	var here := sim.chief_pos
	var dir := facing(sim)
	var arc := deg_to_rad(Weapons.arc_of_weapon(weapon)) * (1.25 if heavy else 1.0)
	var reach := Weapons.chief_reach(sim)
	var finisher := heavy or combo == 3
	f.last_swing = "heavy" if heavy else ("combo%d" % combo)
	sim.push_fx({"type": "swing", "heavy": heavy, "combo": combo, "weapon": weapon, "ranged": ranged})
	if ranged:
		sim.armory["arrow"] = Weapons.in_armory(sim, "arrow") - 1
		var shot := _best_in_cone(sim, here, dir, reach, arc)
		if shot.is_empty():
			sim.push_fx({"type": "arrow", "from": [here.x, here.y], "to": [here.x + dir.x * reach, here.y + dir.y * reach]})
			return out
		sim.push_fx({"type": "arrow", "from": [here.x, here.y], "to": [shot.pos[0], shot.pos[1]]})
		_strike(sim, shot, base, heavy, here, finisher, out)
		return out
	if bool(f.air):
		return out
	for mob in sim.mobs.duplicate():
		var v := Vector2(float(mob.pos[0]), float(mob.pos[1])) - here
		var d := v.length()
		if d > reach + 0.35:
			continue
		if d > 0.45 and absf(dir.angle_to(v)) > arc * 0.5:
			continue
		if not Walls.crossing(sim, here, Vector2(float(mob.pos[0]), float(mob.pos[1]))).is_empty():
			continue
		_strike(sim, mob, base, heavy, here, finisher, out)
	return out


static func _best_in_cone(sim: LifeSim, here: Vector2, dir: Vector2, reach: float, arc: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for mob in sim.mobs:
		var v := Vector2(float(mob.pos[0]), float(mob.pos[1])) - here
		var d := v.length()
		if d < best_d and (d < 0.6 or absf(dir.angle_to(v)) <= arc * 0.5) and Walls.crossing(sim, here, Vector2(float(mob.pos[0]), float(mob.pos[1]))).is_empty():
			best_d = d
			best = mob
	return best


static func _strike(sim: LifeSim, mob: Dictionary, base: float, heavy: bool, from: Vector2, finisher: bool, out: Dictionary) -> void:
	var crit := sim.rng.randf() < (HEAVY_CRIT_CHANCE if heavy else CRIT_CHANCE)
	var amount := base * (2.0 if crit else 1.0) * sim.rng.randf_range(0.9, 1.1)
	var opts := {"crit": crit, "heavy": heavy, "from": from, "knock": 0.9 if heavy else (0.45 if finisher else 0.15), "stagger": 2.0 if heavy else (1.0 if finisher else 0.0)}
	out.hits = int(out.hits) + 1
	if Survival.damage_mob(sim, mob, amount, -1, opts):
		out.kills = int(out.kills) + 1
		fighter(sim).kills = int(fighter(sim).kills) + 1


## Roll away from danger. Returns true if the roll started.
static func dodge(sim: LifeSim) -> bool:
	var f := fighter(sim)
	if float(f.down_t) > 0.0 or float(f.dodge_cd) > 0.0 or float(f.stamina) < DODGE_COST * 0.6:
		return false
	f.stamina = maxf(0.0, float(f.stamina) - DODGE_COST)
	f.rest_t = 0.6
	f.dodge_t = DODGE_TIME
	f.dodge_cd = DODGE_COOLDOWN
	f.block = false
	sim.push_fx({"type": "dodge"})
	return true


# --- being hit -----------------------------------------------------------------------------------------------------------

## A blow lands (or doesn't) on the chief. Returns {dodged, blocked, damage}.
static func hit_chief(sim: LifeSim, from: Vector2, damage: float) -> Dictionary:
	var f := fighter(sim)
	if bool(f.safe) or float(f.down_t) > 0.0:
		return {"dodged": false, "blocked": false, "damage": 0.0}
	if float(f.dodge_t) > 0.0:
		sim.push_fx({"type": "chief_hit", "dodged": true, "blocked": false, "amount": 0.0, "from": [from.x, from.y]})
		return {"dodged": true, "blocked": false, "damage": 0.0}
	var dir := (from - sim.chief_pos).normalized()
	var blocked := false
	var broken := false
	if bool(f.block) and facing(sim).dot(dir) > BLOCK_FRONT:
		blocked = true
		f.stamina = float(f.stamina) - damage * 0.9
		if float(f.stamina) <= 0.0:
			f.stamina = 0.0
			f.block = false
			f.cd = 0.9
			broken = true
			blocked = false
		else:
			damage *= 1.0 - (SHIELD_ABSORB if bool(f.shield) else PARRY_ABSORB)
	f.rest_t = 1.0
	f.hp = maxf(0.0, float(f.hp) - damage)
	f.hurt_t = 1.2
	f.since_hit = 0.0
	f.combo = 0
	f.combo_t = 0.0
	if not blocked and damage >= 7.0 and sim.rng.randf() < 0.45 and float(f.bleed_t) <= 0.0:
		f.bleed_t = BLEED_SECONDS
		sim.notice("You are bleeding. Rest, or reach the healer.")
	if float(f.hp) <= 0.0:
		f.down_t = KNOCKED_OUT_SECONDS
		f.bleed_t = 0.0
		f.block = false
		sim.notice("You collapse! Hold on until help comes.")
		sim.log_event("The chief was beaten down.")
	sim.push_fx({"type": "chief_hit", "dodged": false, "blocked": blocked, "broken": broken, "amount": damage, "from": [from.x, from.y]})
	return {"dodged": false, "blocked": blocked, "damage": damage}


static func status_line(sim: LifeSim) -> String:
	var f := fighter(sim)
	return "Health %d/%d, stamina %d%s%s." % [int(float(f.hp)), int(float(f.max_hp)), int(float(f.stamina)), ", bleeding" if is_bleeding(sim) else "", ", knocked out" if is_down(sim) else ""]
