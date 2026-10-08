class_name Weapons
extends RefCounted
## Arms for the village. A workshop turns timber, stone and coins into clubs, spears, swords, bows and shields; they wait
## in the armory until someone is handed one. Guards are armed first. A weapon multiplies what a swing does (and decides
## how far away it lands), a shield soaks up part of every blow.

const ITEMS := {
	"club": {"label": "Club", "kind": "melee", "wood": 8, "stone": 0, "coins": 0, "power": 1.5, "reach": 1.15, "arc": 140.0, "swing": 0.5, "stamina": 9.0, "blurb": "Crude but sturdy: a wide, slow swing."},
	"spear": {"label": "Spear", "kind": "melee", "wood": 10, "stone": 8, "coins": 12, "power": 2.1, "reach": 1.7, "arc": 50.0, "swing": 0.55, "stamina": 10.0, "blurb": "Keeps foes at arm's length: a narrow thrust."},
	"sword": {"label": "Sword", "kind": "melee", "wood": 4, "stone": 18, "coins": 70, "power": 3.0, "reach": 1.2, "arc": 110.0, "swing": 0.38, "stamina": 8.0, "blurb": "The best close-range arm the village can forge."},
	"bow": {"label": "Bow", "kind": "ranged", "wood": 14, "stone": 0, "coins": 40, "power": 2.2, "reach": 5.5, "arc": 40.0, "swing": 0.8, "stamina": 6.0, "blurb": "Strikes from a distance. Needs arrows."},
	"arrow": {"label": "Arrows", "kind": "ammo", "wood": 5, "stone": 0, "coins": 0, "power": 1.0, "reach": 0.0, "bundle": 10, "blurb": "Ten to a bundle."},
	"shield": {"label": "Shield", "kind": "shield", "wood": 12, "stone": 4, "coins": 25, "power": 1.0, "reach": 0.0, "guard": 0.35, "blurb": "Absorbs a third of every blow."},
}
const FISTS_POWER := 1.0
const FISTS_ARC := 90.0
const FISTS_SWING := 0.35
const FISTS_STAMINA := 6.0
## Best weapon first, for handing them out.
const RANK := ["sword", "spear", "bow", "club"]
const CHIEF_BASE_DAMAGE := 20.0


static func is_item(kind: String) -> bool:
	return ITEMS.has(kind)


static func label(kind: String) -> String:
	return str(ITEMS[kind].label).to_lower() if ITEMS.has(kind) else "bare hands"


static func in_armory(sim: LifeSim, kind: String) -> int:
	return int(sim.armory.get(kind, 0))


static func has_workshop(sim: LifeSim) -> bool:
	for b in sim.buildings_of("workshop"):
		if int(b.level) >= 1:
			return true
	return false


## What forging n of these would cost: {wood, stone, coins}.
static func cost_of(kind: String, n: int) -> Dictionary:
	var spec: Dictionary = ITEMS[kind]
	return {"wood": int(spec.wood) * n, "stone": int(spec.stone) * n, "coins": int(spec.coins) * n}


## Forge weapons at the workshop. Returns {ok, message}.
static func craft(sim: LifeSim, kind: String, n: int = 1) -> Dictionary:
	if not ITEMS.has(kind):
		return {"ok": false, "message": "The smith doesn't know how to make that."}
	n = clampi(n, 1, 20)
	if not has_workshop(sim):
		return {"ok": false, "message": "Weapons are made at a workshop, and there isn't a finished one yet."}
	var c := cost_of(kind, n)
	if sim.wood < int(c.wood) or sim.stone < int(c.stone) or sim.money < int(c.coins):
		return {"ok": false, "message": "%d %s%s needs %d timber, %d stone and %d coins." % [n, label(kind), "" if n == 1 else "s", int(c.wood), int(c.stone), int(c.coins)]}
	sim.wood -= int(c.wood)
	sim.stone -= int(c.stone)
	sim.money -= int(c.coins)
	var made := n * int(ITEMS[kind].get("bundle", 1))
	sim.armory[kind] = in_armory(sim, kind) + made
	sim.log_event("The workshop made %d %s%s." % [made, label(kind), "" if made == 1 else "s"])
	return {"ok": true, "message": "Forged %d %s%s (%d timber, %d stone, %d coins). %d in the armory." % [made, label(kind), "" if made == 1 else "s", int(c.wood), int(c.stone), int(c.coins), in_armory(sim, kind)]}


static func weapon_of(r: Dictionary) -> String:
	return str(r.get("weapon", ""))


static func has_shield(r: Dictionary) -> bool:
	return bool(r.get("shield", false))


## Damage multiplier of whatever this resident holds.
static func power_of(r: Dictionary) -> float:
	var w := weapon_of(r)
	return float(ITEMS[w].power) if ITEMS.has(w) else FISTS_POWER


## How far (in tiles) their swing reaches.
static func reach_of(r: Dictionary) -> float:
	var w := weapon_of(r)
	return float(ITEMS[w].reach) if ITEMS.has(w) else 1.15


## Fraction of an incoming blow the shield soaks up.
static func guard_of(r: Dictionary) -> float:
	return float(ITEMS.shield.guard) if has_shield(r) else 0.0


## Give a resident a weapon (or shield) from the armory, taking back whatever they held.
static func equip(sim: LifeSim, index: int, kind: String) -> Dictionary:
	if index < 0 or index >= sim.residents.size() or not ITEMS.has(kind) or str(ITEMS[kind].kind) == "ammo":
		return {"ok": false, "message": "Nobody to arm."}
	var r: Dictionary = sim.residents[index]
	if in_armory(sim, kind) <= 0:
		return {"ok": false, "message": "There is no %s in the armory." % label(kind)}
	sim.armory[kind] = in_armory(sim, kind) - 1
	if kind == "shield":
		if has_shield(r):
			sim.armory.shield = in_armory(sim, "shield") + 1
		r.shield = true
	else:
		var old := weapon_of(r)
		if old != "":
			sim.armory[old] = in_armory(sim, old) + 1
		r.weapon = kind
	return {"ok": true, "message": "%s now carries a %s." % [r.name, label(kind)]}


## Hand a resident's arms back to the armory.
static func disarm(sim: LifeSim, index: int) -> void:
	var r: Dictionary = sim.residents[index]
	var old := weapon_of(r)
	if old != "":
		sim.armory[old] = in_armory(sim, old) + 1
	if has_shield(r):
		sim.armory.shield = in_armory(sim, "shield") + 1
	r.weapon = ""
	r.shield = false


static func is_guard(r: Dictionary) -> bool:
	var job: Dictionary = r.get("job", {})
	var title := Jobs.title_of(r)
	return title == "guard" or title == "gatekeeper" or (not job.is_empty() and str(job.kind) == "guard")


## Everyone fit to fight (adults standing on their feet).
static func fighters(sim: LifeSim) -> Array:
	var out: Array = []
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if int(r.age) >= 16 and float(r.get("down_until", 0.0)) <= sim.minutes:
			out.append(i)
	return out


static func armed_count(sim: LifeSim) -> int:
	var n := 0
	for r in sim.residents:
		if weapon_of(r) != "":
			n += 1
	return n


## Arm the guards first (best weapons), then others if `everyone`. Returns {armed, shields}.
static func arm_guards(sim: LifeSim, everyone: bool = false) -> Dictionary:
	var armed := 0
	var shields := 0
	var order: Array = []
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if int(r.age) < 16:
			continue
		if is_guard(r):
			order.push_front(i)
		elif everyone:
			order.append(i)
	for i in order:
		var r: Dictionary = sim.residents[i]
		if weapon_of(r) == "":
			for kind in RANK:
				if in_armory(sim, kind) > 0:
					equip(sim, i, kind)
					armed += 1
					break
		if not has_shield(r) and in_armory(sim, "shield") > 0:
			equip(sim, i, "shield")
			shields += 1
	return {"armed": armed, "shields": shields}


# --- the chief's own weapon ------------------------------------------------------------------------------------------------

static func chief_power(sim: LifeSim) -> float:
	return float(ITEMS[sim.chief_weapon].power) if ITEMS.has(sim.chief_weapon) else FISTS_POWER


## Swing arc in degrees, seconds between swings, and stamina per swing of the chief's weapon.
static func arc_of_weapon(kind: String) -> float:
	return float(ITEMS[kind].arc) if ITEMS.has(kind) and ITEMS[kind].has("arc") else FISTS_ARC


static func swing_of_weapon(kind: String) -> float:
	return float(ITEMS[kind].swing) if ITEMS.has(kind) and ITEMS[kind].has("swing") else FISTS_SWING


static func stamina_of_weapon(kind: String) -> float:
	return float(ITEMS[kind].stamina) if ITEMS.has(kind) and ITEMS[kind].has("stamina") else FISTS_STAMINA


static func chief_reach(sim: LifeSim) -> float:
	return float(ITEMS[sim.chief_weapon].reach) if ITEMS.has(sim.chief_weapon) else 1.8


## Damage of one swing of the chief's weapon.
static func chief_damage(sim: LifeSim) -> float:
	return CHIEF_BASE_DAMAGE * chief_power(sim)


## Take a weapon from the armory into the chief's hand ("" for bare hands). Returns {ok, message}.
static func chief_equip(sim: LifeSim, kind: String) -> Dictionary:
	if kind == "":
		if ITEMS.has(sim.chief_weapon):
			sim.armory[sim.chief_weapon] = in_armory(sim, sim.chief_weapon) + 1
		sim.chief_weapon = ""
		return {"ok": true, "message": "You put your weapon away."}
	if kind == "shield":
		if sim.fighter.get("shield", false):
			return {"ok": true, "message": "You already carry a shield."}
		if in_armory(sim, "shield") <= 0:
			return {"ok": false, "message": "There is no shield in the armory."}
		sim.armory["shield"] = in_armory(sim, "shield") - 1
		sim.fighter["shield"] = true
		return {"ok": true, "message": "You strap on a shield: hold Y to block, it soaks three quarters of a blow."}
	if not ITEMS.has(kind) or str(ITEMS[kind].kind) in ["ammo", "shield"]:
		return {"ok": false, "message": "You can't wield that."}
	if sim.chief_weapon == kind:
		return {"ok": true, "message": "You already hold the %s." % label(kind)}
	if in_armory(sim, kind) <= 0:
		return {"ok": false, "message": "There is no %s in the armory." % label(kind)}
	sim.armory[kind] = in_armory(sim, kind) - 1
	if ITEMS.has(sim.chief_weapon):
		sim.armory[sim.chief_weapon] = in_armory(sim, sim.chief_weapon) + 1
	sim.chief_weapon = kind
	return {"ok": true, "message": "You take up the %s (hits %.1fx as hard)." % [label(kind), float(ITEMS[kind].power)]}


## Cycle the chief through bare hands and what the armory holds.
static func chief_cycle(sim: LifeSim) -> Dictionary:
	var options: Array = [""]
	for kind in RANK:
		if in_armory(sim, kind) > 0 or sim.chief_weapon == kind:
			options.append(kind)
	var at := options.find(sim.chief_weapon)
	return chief_equip(sim, str(options[(at + 1) % options.size()]))


static func report(sim: LifeSim) -> String:
	var parts: Array = []
	for kind in ITEMS:
		if in_armory(sim, kind) > 0:
			parts.append("%d %s%s" % [in_armory(sim, kind), label(kind), "" if in_armory(sim, kind) == 1 else "s"])
	var stock := ", ".join(parts) if not parts.is_empty() else "nothing"
	var held := ("You carry the %s." % label(sim.chief_weapon) if sim.chief_weapon != "" else "You are unarmed.") + (" You have a shield." if sim.fighter.get("shield", false) else "")
	return "Armory: %s. %d resident%s armed. %s" % [stock, armed_count(sim), "" if armed_count(sim) == 1 else "s", held]
