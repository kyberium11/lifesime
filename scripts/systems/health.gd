class_name Health
extends RefCounted
## Illness that spreads between people standing close together, injuries from fights, and the cold:
## winter nights outside and unheated homes. Hygiene, rest and a hardy constitution all help.

const ILLNESSES := {
	"cold": {"days": 3.0, "spread": 0.0007, "drain": 0.012},
	"flu": {"days": 5.0, "spread": 0.0012, "drain": 0.022},
}
const CONTACT := 1.7


static func is_ill(sim: LifeSim, r: Dictionary) -> bool:
	return float(r.ill_until) > sim.minutes


static func speed(r: Dictionary) -> float:
	var s := 1.0
	if bool(r.get("injured", false)):
		s *= 0.6
	if float(r.get("ill_until", 0.0)) > 0.0:
		s *= 0.85
	return s


static func infect(sim: LifeSim, index: int, kind: String) -> void:
	var r: Dictionary = sim.residents[index]
	if is_ill(sim, r) or sim.minutes < float(r.get("immune_until", 0.0)):
		return
	var spec: Dictionary = ILLNESSES[kind]
	r.ill_kind = kind
	r.ill_until = sim.minutes + float(spec.days) * 1440.0 * (1.0 / float(r.genes.hardy))
	sim.log_event("%s came down with %s." % [r.name, kind])
	sim.emote(index, "sick", 0.0)
	if sim.rng.randf() < 0.5:
		sim.say(index, "Achoo... I don't feel well.")
	if kind == "flu":
		Rumors.create(sim, str(r.name), "", "illness", "%s is sick with the flu" % r.name, -0.1, [index])


static func tick(sim: LifeSim, dm: float) -> void:
	var winter := sim.season() == "Winter"
	var night := Survival.is_night(sim)
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		var n: Dictionary = r.needs
		var inside := sim.is_inside(r)
		# Warmth: dropping outside in cold weather, restored by a roof (less so without firewood).
		if inside:
			r.warmth = minf(100.0, float(r.warmth) + (0.5 if not sim.cold_homes else 0.12) * dm)
		else:
			var chill := 0.0
			if winter:
				chill = 0.07 if night else 0.035
			elif sim.weather == "Rain":
				chill = 0.012
			r.warmth = clampf(float(r.warmth) - chill * dm + (0.05 if chill == 0.0 else 0.0) * dm, 0.0, 100.0)
		if winter and float(r.warmth) < 12.0 and not is_ill(sim, r) and sim.minutes >= float(r.get("immune_until", 0.0)) and sim.rng.randf() < 0.0005 * dm:
			infect(sim, i, "cold")
		if is_ill(sim, r):
			var spec: Dictionary = ILLNESSES[str(r.ill_kind)]
			n.energy = maxf(0.0, float(n.energy) - float(spec.drain) * dm)
			n.health = maxf(5.0, float(n.health) - float(spec.drain) * 0.5 * dm)
			var resting := str(r.action) in ["sleep", "rest"]
			if resting:
				r.ill_until = float(r.ill_until) - dm * 2.0
			if sim.minutes >= float(r.ill_until):
				r.ill_until = 0.0
				r.ill_kind = ""
				r.immune_until = sim.minutes + 4.0 * 1440.0
				sim.log_event("%s recovered." % r.name)
				sim.say(i, "I'm feeling better at last.")
			else:
				_spread(sim, i, dm)
		if bool(r.injured) and (float(n.health) >= 75.0 or str(r.action) in ["sleep", "rest"] and float(n.health) >= 60.0):
			r.injured = false
			sim.log_event("%s's injuries have healed." % r.name)
		elif not bool(r.injured) and float(n.health) < 45.0 and float(r.get("fight_cd", 0.0)) >= 0.0 and sim.threat > 0:
			r.injured = true
			sim.log_event("%s is hurt and moving slowly." % r.name)
		# Hygiene matters: filth makes sickness likelier.
		if float(n.hygiene) < 12.0 and not is_ill(sim, r) and sim.minutes >= float(r.get("immune_until", 0.0)) and sim.rng.randf() < 0.0002 * dm:
			infect(sim, i, "cold")
		# Sleep and food mend a little.
		if str(r.action) in ["sleep", "rest"] and float(n.hunger) > 30.0:
			n.health = minf(100.0, float(n.health) + 0.03 * dm)


static func _spread(sim: LifeSim, source: int, dm: float) -> void:
	var s: Dictionary = sim.residents[source]
	var here := Vector2(float(s.pos[0]), float(s.pos[1]))
	var spec: Dictionary = ILLNESSES[str(s.ill_kind)]
	for j in range(sim.residents.size()):
		if j == source:
			continue
		var o: Dictionary = sim.residents[j]
		if is_ill(sim, o):
			continue
		var close := here.distance_to(Vector2(float(o.pos[0]), float(o.pos[1]))) < CONTACT
		if close and sim.is_inside(s) == sim.is_inside(o):
			var chance := float(spec.spread) * dm * (1.2 - float(o.needs.hygiene) / 150.0) * (2.0 - float(o.genes.hardy)) * (1.6 if sim.season() == "Winter" else 1.0)
			if sim.rng.randf() < chance:
				infect(sim, j, str(s.ill_kind))


static func daily(sim: LifeSim) -> void:
	# Heating: homes burn firewood in winter.
	sim.cold_homes = false
	if sim.season() == "Winter":
		var homes := sim.buildings_of("home").size()
		var need := maxi(1, int(ceil(float(homes) * 0.5)))
		if sim.wood >= need:
			sim.wood -= need
		else:
			sim.wood = 0
			sim.cold_homes = true
			sim.notice("The village ran out of firewood. Homes are cold. Send someone to chop wood!")
	var ill := 0
	for r in sim.residents:
		if is_ill(sim, r):
			ill += 1
	if ill >= 4 and not sim.epidemic:
		sim.epidemic = true
		sim.notice("An illness is spreading through the village (%d sick). Keep people apart and rested." % ill)
	elif ill <= 1:
		sim.epidemic = false
