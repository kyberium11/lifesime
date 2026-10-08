class_name Lifecycle
extends RefCounted
## Ages and stages, romance and marriage, children with inherited genes, family ties, old age and its estate.
## A year lasts 28 days; children grow up twice as fast so a family can be seen to grow.

const YEAR_DAYS := 28
const CHILD_GROWTH_DAYS := 14
const STAGES := [[3, "Infant"], [13, "Child"], [18, "Teen"], [60, "Adult"], [1000, "Senior"]]
const CHILD_ACTIONS := ["eat", "sleep", "wash", "socialize", "play", "study", "rest"]
const TEEN_BLOCKED := ["guard", "mine"]
const MIN_ROMANCE_AGE := 18
const COUPLE_ROMANCE := 62.0
const COUPLE_FRIENDSHIP := 50.0
const WED_ROMANCE := 85.0
const BIRTH_CHANCE := 0.1
const SENIOR_AGE := 62


static func stage_name(age: int) -> String:
	for s in STAGES:
		if age < int(s[0]):
			return str(s[1])
	return "Senior"


static func is_child(r: Dictionary) -> bool:
	return int(r.age) < 13


static func is_adult(r: Dictionary) -> bool:
	return int(r.age) >= MIN_ROMANCE_AGE


## Can this resident be given this activity? Returns "" or a reason.
static func blocked(r: Dictionary, action: String) -> String:
	var age := int(r.age)
	if age < 13 and action not in CHILD_ACTIONS:
		return "is too young for that"
	if age < 18 and action in TEEN_BLOCKED:
		return "is too young for that"
	if age >= SENIOR_AGE + 8 and action in ["guard", "mine", "chop"]:
		return "is too old for such hard work"
	return ""


## Body size on screen: children are small, genes add a little variety.
static func body_scale(r: Dictionary) -> float:
	var age := float(r.age)
	var grown := clampf(0.55 + (age - 18.0) * 0.0, 0.55, 0.55)
	if age < 18.0:
		grown = lerpf(0.34, 0.55, clampf(age / 17.0, 0.0, 1.0))
	elif age >= 70.0:
		grown = 0.52
	return grown * float((r.get("genes", {}) as Dictionary).get("height", 1.0))


static func related(a: Dictionary, b: Dictionary) -> bool:
	if str(b.name) in a.parents or str(a.name) in b.parents:
		return true
	for p in a.parents:
		if p in b.parents:
			return true
	return false


## Chemistry between two residents that is fixed by who they are, 0..1.
static func attraction(a: Dictionary, b: Dictionary) -> float:
	var first := str(a.name) if str(a.name) < str(b.name) else str(b.name)
	var second := str(b.name) if str(a.name) < str(b.name) else str(a.name)
	var h := float(absi(hash("%s+%s" % [first, second])) % 1000) / 1000.0
	return clampf(h * 0.7 + Psyche.compat(a, b) * 0.5, 0.0, 1.0)


static func eligible(a: Dictionary, b: Dictionary) -> bool:
	return is_adult(a) and is_adult(b) and not related(a, b) and (str(a.partner) == "" or str(a.partner) == str(b.name)) and (str(b.partner) == "" or str(b.partner) == str(a.name))


## Called after two residents interact. Romance grows between compatible single adults; rivalry from quarrels.
static func on_interact(sim: LifeSim, a_index: int, b_index: int, kind: String, success: bool) -> void:
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	a.last_contact[b.name] = sim.day()
	b.last_contact[a.name] = sim.day()
	if kind == "argue":
		a.rivalry[b.name] = minf(100.0, float(a.rivalry.get(b.name, 0.0)) + 9.0)
		b.rivalry[a.name] = minf(100.0, float(b.rivalry.get(a.name, 0.0)) + 9.0)
		return
	if not success:
		return
	if kind in ["chat", "joke", "compliment", "hug"]:
		a.rivalry[b.name] = maxf(0.0, float(a.rivalry.get(b.name, 0.0)) - 3.0)
		b.rivalry[a.name] = maxf(0.0, float(b.rivalry.get(a.name, 0.0)) - 3.0)
	if not eligible(a, b) or sim.relation(a, str(b.name)) < 30.0:
		return
	var chem := attraction(a, b)
	if chem < 0.5:
		return
	var gain := (2.5 + chem * 4.0) * (3.0 if kind in ["compliment", "hug"] else 1.0)
	gain *= 1.0 - minf(0.5, (float(a.trauma) + float(b.trauma)) * 0.25)
	var romance := minf(100.0, float(a.romance.get(b.name, 0.0)) + gain)
	a.romance[b.name] = romance
	b.romance[a.name] = romance
	if str(a.partner) == "" and str(b.partner) == "" and romance >= COUPLE_ROMANCE and sim.relation(a, str(b.name)) >= COUPLE_FRIENDSHIP:
		_couple(sim, a_index, b_index)


static func _couple(sim: LifeSim, a_index: int, b_index: int) -> void:
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	a.partner = str(b.name)
	b.partner = str(a.name)
	a.partner_since = sim.day()
	b.partner_since = sim.day()
	sim.log_event("%s and %s are now a couple!" % [a.name, b.name])
	sim.notice("%s and %s fell in love." % [a.name, b.name])
	sim.emote(a_index, "heart", 0.2)
	sim.emote(b_index, "heart", 0.8)
	Psyche.add_core(sim, a, "Day %d: %s and I became a couple." % [sim.day(), b.name], 0.6, 0.8)
	Psyche.add_core(sim, b, "Day %d: %s and I became a couple." % [sim.day(), a.name], 0.6, 0.8)
	Rumors.create(sim, str(a.name), str(b.name), "romance", "%s and %s are seeing each other" % [a.name, b.name], 0.3, [a_index, b_index])


static func _marry(sim: LifeSim, a_index: int, b_index: int) -> void:
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	sim.log_event("%s and %s got married!" % [a.name, b.name])
	sim.notice("Wedding! %s and %s are now married." % [a.name, b.name])
	sim.emote(a_index, "heart", 0.1)
	sim.emote(b_index, "heart", 0.5)
	for r in [a, b]:
		r.needs.fun = 100.0
		r.needs.social = 100.0
	a.married = true
	b.married = true
	Psyche.add_core(sim, a, "Day %d: I married %s." % [sim.day(), b.name], 0.9, 0.9)
	Psyche.add_core(sim, b, "Day %d: I married %s." % [sim.day(), a.name], 0.9, 0.9)
	Rumors.create(sim, str(a.name), str(b.name), "marriage", "%s and %s got married" % [a.name, b.name], 0.5, [a_index, b_index])
	# They share a home when there is room.
	var home := sim.building_by_id(int(a.home))
	if not home.is_empty() and sim.occupants_of(int(a.home)) < Catalog.capacity(str(home.kind), int(home.level)):
		b.home = a.home
		Ownership.refresh(sim, home)


static func daily(sim: LifeSim) -> void:
	var day := sim.day()
	# Growing up and growing old.
	for r in sim.residents:
		if int(r.age) < 18:
			if day % CHILD_GROWTH_DAYS == 0:
				r.age += 1
		elif day % YEAR_DAYS == 0:
			r.age += 1
	# Slow decay of ties that are not kept up.
	for r in sim.residents:
		for name_ in r.relations.keys():
			var last := int(r.last_contact.get(name_, day))
			if day - last > 6 and float(r.relations[name_]) > 25.0:
				r.relations[name_] = maxf(25.0, float(r.relations[name_]) - 0.25)
		for name_ in r.romance.keys():
			if str(r.partner) != name_:
				r.romance[name_] = maxf(0.0, float(r.romance[name_]) - 0.4)
		for name_ in r.rivalry.keys():
			r.rivalry[name_] = maxf(0.0, float(r.rivalry[name_]) - 0.6)
	_courtship(sim)
	# Couples: weddings, children.
	var done := {}
	for i in range(sim.residents.size()):
		var a: Dictionary = sim.residents[i]
		if str(a.partner) == "" or done.has(str(a.name)):
			continue
		var j := sim.index_of(str(a.partner))
		if j < 0:
			a.partner = ""
			continue
		var b: Dictionary = sim.residents[j]
		done[str(a.name)] = true
		done[str(b.name)] = true
		if not bool(a.get("married", false)) and day - int(a.partner_since) >= 4 and float(a.romance.get(b.name, 0.0)) >= WED_ROMANCE:
			_marry(sim, i, j)
		if bool(a.get("married", false)) and int(a.age) <= 46 and int(b.age) <= 46 and sim.residents.size() < Catalog.MAX_POPULATION:
			if sim.rng.randf() < BIRTH_CHANCE * (3.0 if sim.day() < int(a.get("family_blessing_until", 0)) or sim.day() < int(b.get("family_blessing_until", 0)) else 1.0) and sim.housing() > sim.residents.size() and sim.food + sim.meals * 2 >= sim.residents.size() * 2:
				birth(sim, i, j)
	# Old age.
	for i in range(sim.residents.size() - 1, -1, -1):
		var r: Dictionary = sim.residents[i]
		if int(r.age) >= SENIOR_AGE and sim.residents.size() > 3:
			var odds := float(int(r.age) - SENIOR_AGE + 1) * 0.0035 / float((r.genes as Dictionary).hardy)
			if sim.rng.randf() < odds:
				pass_away(sim, i, "old age")


## Time spent together out of sight: single adults drift toward the person they click with.
static func _courtship(sim: LifeSim) -> void:
	for i in range(sim.residents.size()):
		var a: Dictionary = sim.residents[i]
		if not is_adult(a) or str(a.partner) != "" or sim.rng.randf() > 0.2:
			continue
		var best := -1
		var best_score := 0.0
		for j in range(sim.residents.size()):
			if j == i:
				continue
			var b: Dictionary = sim.residents[j]
			if not eligible(a, b) or str(b.partner) != "":
				continue
			var score := attraction(a, b) + sim.relation(a, str(b.name)) / 200.0
			if score > best_score:
				best_score = score
				best = j
		if best >= 0 and best_score > 0.7:
			var b2: Dictionary = sim.residents[best]
			var romance := minf(100.0, float(a.romance.get(b2.name, 0.0)) + 5.0)
			a.romance[b2.name] = romance
			b2.romance[a.name] = romance
			a.relations[b2.name] = minf(100.0, sim.relation(a, str(b2.name)) + 2.5)
			b2.relations[a.name] = a.relations[b2.name]
			a.last_contact[b2.name] = sim.day()
			b2.last_contact[a.name] = sim.day()
			if romance >= COUPLE_ROMANCE and sim.relation(a, str(b2.name)) >= COUPLE_FRIENDSHIP and str(b2.partner) == "":
				_couple(sim, i, best)


static func birth(sim: LifeSim, a_index: int, b_index: int) -> void:
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	var used := {}
	for r in sim.residents:
		used[r.name] = true
	var name_ := ""
	for candidate in Catalog.RESIDENT_NAMES:
		if not used.has(candidate):
			name_ = candidate
			break
	if name_ == "":
		name_ = "Baby %d" % (sim.residents.size() + 1)
	var girl := sim.rng.randf() < 0.5
	var pool: Array = []
	for look in range(Catalog.LOOKS.size()):
		if (Catalog.LOOKS[look] in Catalog.FEMALE_LOOKS) == girl:
			pool.append(look)
	var look_index: int = pool[sim.rng.randi() % pool.size()]
	var trait_: String = Catalog.RESIDENT_TRAITS[sim.rng.randi() % Catalog.RESIDENT_TRAITS.size()]
	var door := Vector2(sim.map.door_for(sim.tile_of(sim.building_by_id(int(a.home))))) if not sim.building_by_id(int(a.home)).is_empty() else Vector2(a.pos[0], a.pos[1])
	var child := sim._new_resident(name_, trait_, look_index, 0, int(a.home), door)
	Psyche.extend(child, sim.rng)
	Psyche.inherit(child, a, b, sim.rng)
	child.parents = [str(a.name), str(b.name)]
	child.birth_day = sim.day()
	for key in child.skills:
		child.skills[key] = 0.0
	a.children.append(name_)
	b.children.append(name_)
	child.relations[str(a.name)] = 60.0
	child.relations[str(b.name)] = 60.0
	a.relations[name_] = 75.0
	b.relations[name_] = 75.0
	sim.residents.append(child)
	sim._refresh_wants(child)
	var family_home := sim.building_by_id(int(a.home))
	if not family_home.is_empty():
		Ownership.refresh(sim, family_home)
	sim.log_event("%s and %s welcomed a baby: %s!" % [a.name, b.name, name_])
	sim.notice("A baby is born: %s, child of %s and %s." % [name_, a.name, b.name])
	sim.log_event("%s was born to %s and %s." % [name_, a.name, b.name])
	Psyche.add_core(sim, a, "Day %d: %s was born." % [sim.day(), name_], 1.0, 1.0)
	Psyche.add_core(sim, b, "Day %d: %s was born." % [sim.day(), name_], 1.0, 1.0)
	sim.emote(a_index, "heart", 0.2)
	sim.say(sim.residents.size() - 1, "...")
	sim.push_fx({"type": "birth", "who": sim.residents.size() - 1})


## A resident dies. Their estate passes to the surviving family (or the village treasury), and those who loved them grieve.
static func pass_away(sim: LifeSim, index: int, cause: String) -> void:
	var r: Dictionary = sim.residents[index]
	var name_ := str(r.name)
	Ownership.on_death(sim, name_)
	var estate := int(r.earned * 0.4)
	var heirs: Array = []
	if str(r.partner) != "":
		heirs.append(str(r.partner))
	for c in r.children:
		heirs.append(str(c))
	var living: Array = []
	for h in heirs:
		var k := sim.index_of(h)
		if k >= 0 and k != index:
			living.append(k)
	sim.log_event("%s passed away (%s). Their estate of %d coins goes to %s." % [name_, cause, estate, "family" if not living.is_empty() else "the village"])
	sim.notice("%s has passed away." % name_)
	sim.money += estate if living.is_empty() else estate / 2
	for k in living:
		var heir: Dictionary = sim.residents[k]
		sim.money += (estate / 2) / living.size() if living.size() > 0 else 0
		heir.needs.fun = maxf(0.0, float(heir.needs.fun) - 25.0)
		Psyche.add_core(sim, heir, "Day %d: I lost %s." % [sim.day(), name_], 0.9, -0.9)
		if str(heir.partner) == name_:
			heir.partner = ""
			heir.married = false
	for other in sim.residents:
		if other == r:
			continue
		if sim.relation(other, name_) >= 55.0:
			other.stress = minf(100.0, float(other.stress) + 14.0)
			Psyche.add_core(sim, other, "Day %d: %s died. The village feels emptier." % [sim.day(), name_], 0.4, -0.4)
		other.relations.erase(name_)
		other.romance.erase(name_)
		other.rivalry.erase(name_)
	sim.remove_resident(index)
