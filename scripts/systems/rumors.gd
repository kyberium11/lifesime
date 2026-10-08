class_name Rumors
extends RefCounted
## Information is not global. A rumor starts with the people who saw it, travels only when residents talk,
## and drifts as it goes: it can be exaggerated and its truth fades. What residents hear shapes their opinion of
## the people involved, and the average of those opinions is a person's reputation.

const MAX_AGE_DAYS := 14
const MAX_RUMORS := 40


static func find(sim: LifeSim, id: int) -> Dictionary:
	for ru in sim.rumors:
		if int(ru.id) == id:
			return ru
	return {}


## `witnesses` are resident indices who saw it happen. valence runs from -1 (scandalous) to +1 (admirable).
static func create(sim: LifeSim, subject: String, about: String, kind: String, text: String, valence: float, witnesses: Array) -> void:
	sim.rumor_serial += 1
	var ru := {"id": sim.rumor_serial, "subject": subject, "about": about, "kind": kind, "text": text, "valence": valence, "truth": 1.0, "day": sim.day(), "hops": 0}
	sim.rumors.append(ru)
	if sim.rumors.size() > MAX_RUMORS:
		sim.rumors.pop_front()
	# Anyone who happened to be close by also saw it.
	var seen := {}
	for w in witnesses:
		seen[int(w)] = true
	if not witnesses.is_empty():
		var at := Vector2(float(sim.residents[int(witnesses[0])].pos[0]), float(sim.residents[int(witnesses[0])].pos[1]))
		for i in range(sim.residents.size()):
			if not seen.has(i) and at.distance_to(Vector2(float(sim.residents[i].pos[0]), float(sim.residents[i].pos[1]))) < 6.0 and not sim.is_inside(sim.residents[i]):
				seen[i] = true
	for i in seen.keys():
		_learn(sim, int(i), ru, 1.0)


static func _learn(sim: LifeSim, index: int, ru: Dictionary, trust: float) -> void:
	var r: Dictionary = sim.residents[index]
	if int(ru.id) in r.heard:
		return
	r.heard.append(int(ru.id))
	if r.heard.size() > 12:
		r.heard.pop_front()
	var subject := str(ru.subject)
	if subject == str(r.name):
		return
	# The listener's opinion of the person it is about shifts, weighed by how much they trust the teller.
	var current := float(r.opinion.get(subject, sim.relation(r, subject)))
	var shift := float(ru.valence) * float(ru.truth) * 12.0 * trust * (0.8 + Psyche.f(r, "a") * 0.4 if float(ru.valence) < 0.0 else 1.0)
	r.opinion[subject] = clampf(current + shift, 0.0, 100.0)
	if float(ru.valence) < -0.4 and float(r.opinion[subject]) < 35.0:
		r.stress = minf(100.0, float(r.stress) + 2.0)


## A and B are talking: A passes on something they know.
static func on_interact(sim: LifeSim, a_index: int, b_index: int, kind: String) -> void:
	if kind not in ["chat", "gossip", "joke"]:
		return
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	if a.heard.is_empty():
		return
	if kind != "gossip" and sim.rng.randf() > 0.45:
		return
	var options: Array = []
	for id in a.heard:
		var ru := find(sim, int(id))
		if not ru.is_empty() and not (int(id) in b.heard) and str(ru.subject) != str(b.name):
			options.append(ru)
	if options.is_empty():
		return
	var ru2: Dictionary = options[sim.rng.randi() % options.size()]
	# The story changes in the telling.
	var copy := ru2.duplicate()
	copy.hops = int(ru2.hops) + 1
	if sim.rng.randf() < 0.35 and float(ru2.valence) != 0.0:
		copy.valence = clampf(float(ru2.valence) * 1.3, -1.0, 1.0)
		copy.truth = maxf(0.2, float(ru2.truth) * 0.8)
		copy.text = "%s (and people say it was worse than that)" % str(ru2.text).replace(" (and people say it was worse than that)", "") if float(ru2.valence) < 0.0 else str(ru2.text)
		sim.rumors.append(copy)
		if sim.rumors.size() > MAX_RUMORS:
			sim.rumors.pop_front()
		copy.id = sim.rumor_serial + 1
		sim.rumor_serial += 1
		_learn(sim, b_index, copy, clampf(sim.relation(b, str(a.name)) / 100.0 + 0.3, 0.2, 1.0))
		if int(copy.id) not in a.heard:
			a.heard.append(int(copy.id))
	else:
		_learn(sim, b_index, ru2, clampf(sim.relation(b, str(a.name)) / 100.0 + 0.3, 0.2, 1.0))
	if sim.rng.randf() < 0.25:
		sim.log_event("%s told %s: \"%s\"." % [a.name, b.name, str(ru2.text)])


static func daily(sim: LifeSim) -> void:
	var keep: Array = []
	for ru in sim.rumors:
		if sim.day() - int(ru.day) <= MAX_AGE_DAYS:
			keep.append(ru)
	sim.rumors = keep
	# Opinions drift back toward what people truly feel about each other.
	for r in sim.residents:
		for name_ in r.opinion.keys():
			var base := sim.relation(r, str(name_))
			r.opinion[name_] = lerpf(float(r.opinion[name_]), base, 0.04)


## How the village sees one person, 0..100: the average opinion across everyone else.
static func reputation(sim: LifeSim, name_: String) -> float:
	var total := 0.0
	var count := 0
	for r in sim.residents:
		if str(r.name) == name_:
			continue
		total += float(r.opinion.get(name_, sim.relation(r, name_) + 10.0))
		count += 1
	return total / float(count) if count > 0 else 50.0


static func reputation_label(value: float) -> String:
	if value >= 75.0:
		return "beloved"
	if value >= 55.0:
		return "well liked"
	if value >= 38.0:
		return "neutral"
	if value >= 22.0:
		return "distrusted"
	return "scorned"
