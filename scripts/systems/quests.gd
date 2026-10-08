class_name Quests
extends RefCounted
## Aspirations. Each adult has a personal dream that fits their life: to run the shop, to have a bigger home,
## to find love, to master a skill, to take up a trade, or to start a family. When a dream needs the chief's help
## the resident comes to ask (through the advice system); the chief can back it, ask them to wait, or refuse.
## Dreams that come true are celebrated, remembered, and talked about.
## Resident key: aspiration = {kind, text, stage, goal, base, since, ask_after, title?, skill?, other?}
## stage: 0 = not yet asked, 1 = asked and waiting, 2 = backed (working towards it), 3 = finished (cooldown).

const KINDS := ["shop", "home", "marry", "skill", "career", "family"]
const ASK_DELAY_DAYS := 2
const RETRY_DAYS := 5
const COOLDOWN_DAYS := 9
const SKILL_GOAL := 70.0
const SKILL_NAMES := {"craft": "building", "cooking": "cooking", "gardening": "gardening", "knowledge": "learning", "fitness": "fitness"}
const TITLE_FOR_TRAIT := {"Curious gardener": "farmer", "Outgoing cook": "shopkeeper", "Ambitious maker": "builder", "Creative bookworm": "librarian", "Gentle healer": "doctor", "Practical builder": "builder", "Restless explorer": "guard", "Careful saver": "shopkeeper"}


static func get_of(r: Dictionary) -> Dictionary:
	var a: Variant = r.get("aspiration", {})
	return a if a is Dictionary else {}


static func text_of(r: Dictionary) -> String:
	var a := get_of(r)
	return str(a.get("text", ""))


static func _asp(kind: String, text: String, sim: LifeSim, extra: Dictionary = {}) -> Dictionary:
	var a := {"kind": kind, "text": text, "stage": 0, "goal": 1.0, "base": 0.0, "since": sim.day(), "ask_after": sim.day() + ASK_DELAY_DAYS}
	for k in extra:
		a[k] = extra[k]
	return a


## Choose a dream that suits someone right now ({} if nothing fits).
static func pick(sim: LifeSim, r: Dictionary) -> Dictionary:
	if int(r.age) < 18 or int(r.age) >= Lifecycle.SENIOR_AGE + 4:
		return {}
	var options: Array = []
	var name_ := str(r.name)
	# Career: a trade that suits them and has an opening.
	var title: String = TITLE_FOR_TRAIT.get(str(r.trait), "farmer")
	if Jobs.title_of(r) == "" and Jobs.vacancies(sim, title) > 0:
		options.append(["career", 3.0, {"title": title}])
	elif Jobs.title_of(r) == "":
		for t in Jobs.JOBS:
			if Jobs.vacancies(sim, t) > 0 and Jobs.suitability(r, t) > 10.0:
				options.append(["career", 2.0, {"title": t}])
				break
	# The shop, if it has no keeper.
	if Jobs.title_of(r) != "shopkeeper" and Jobs.vacancies(sim, "shopkeeper") > 0 and Psyche.f(r, "e") > 0.45:
		options.append(["shop", 2.5, {"title": "shopkeeper"}])
	# A bigger home.
	var home := sim.building_by_id(int(r.home))
	if not home.is_empty() and int(home.level) < Catalog.max_level("home") and int(home.level) >= 1 and sim.stage() >= Catalog.stage_needed("home", int(home.level) + 1):
		options.append(["home", 1.5 + (1.0 if "Family" in r.values else 0.0), {"base": float(home.level), "goal": float(home.level) + 1.0}])
	# Love.
	if str(r.partner) == "" and Lifecycle.is_adult(r) and Psyche.f(r, "e") + Psyche.f(r, "a") > 0.7:
		options.append(["marry", 2.0 if "Family" in r.values else 1.2, {}])
	# Family.
	if bool(r.get("married", false)) and int(r.age) <= 45 and sim.residents.size() < Catalog.MAX_POPULATION:
		options.append(["family", 2.5 if "Family" in r.values else 1.0, {"base": float(r.children.size())}])
	# Mastery: their talent or favourite skill.
	var best_skill := str(r.genes.talent)
	if float(r.skills.get(best_skill, 0.0)) < SKILL_GOAL - 10.0:
		options.append(["skill", 1.4, {"skill": best_skill, "goal": SKILL_GOAL}])
	if options.is_empty():
		return {}
	var total := 0.0
	for o in options:
		total += float(o[1])
	var roll := sim.rng.randf() * total
	for o in options:
		roll -= float(o[1])
		if roll <= 0.0:
			return _build(sim, r, str(o[0]), o[2])
	return _build(sim, r, str(options[0][0]), options[0][2])


static func _build(sim: LifeSim, r: Dictionary, kind: String, extra: Dictionary) -> Dictionary:
	match kind:
		"career":
			return _asp("career", "Become the village %s" % str(Jobs.JOBS[extra.title].label).to_lower(), sim, extra)
		"shop":
			return _asp("shop", "Run the village shop", sim, extra)
		"home":
			return _asp("home", "Live in a bigger, finer home", sim, extra)
		"marry":
			return _asp("marry", "Find someone to marry", sim, extra)
		"family":
			return _asp("family", "Have a child", sim, extra)
		"skill":
			extra.text_skill = str(SKILL_NAMES.get(str(extra.skill), str(extra.skill)))
			return _asp("skill", "Become a master of %s" % str(extra.text_skill), sim, extra)
	return {}


## Per-day upkeep: give dreams to people without one, track progress, notice when they come true.
static func daily(sim: LifeSim) -> void:
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		var a := get_of(r)
		if a.is_empty():
			var fresh := pick(sim, r)
			if not fresh.is_empty():
				r.aspiration = fresh
			continue
		if int(a.stage) == 3:
			if sim.day() >= int(a.get("ask_after", 0)):
				r.aspiration = {}
			continue
		if _done(sim, r, a):
			_complete(sim, i, a)
		elif int(a.stage) in [0, 1, 2] and not _still_possible(sim, r, a):
			r.aspiration = {}


static func progress(sim: LifeSim, r: Dictionary, a: Dictionary) -> float:
	match str(a.kind):
		"skill":
			return clampf(float(r.skills.get(str(a.skill), 0.0)) / float(a.goal), 0.0, 1.0)
		"marry":
			var best := 0.0
			for name_ in r.romance:
				best = maxf(best, float(r.romance[name_]))
			return clampf(best / 85.0, 0.0, 1.0)
		"home":
			var home := sim.building_by_id(int(r.home))
			return 0.5 if not home.is_empty() and int(home.target) > int(home.level) else 0.0
	return 0.0


static func _done(sim: LifeSim, r: Dictionary, a: Dictionary) -> bool:
	match str(a.kind):
		"career", "shop":
			return Jobs.title_of(r) == str(a.title)
		"home":
			var home := sim.building_by_id(int(r.home))
			return not home.is_empty() and int(home.level) >= int(a.goal)
		"marry":
			return bool(r.get("married", false))
		"family":
			return r.children.size() > int(a.base)
		"skill":
			return float(r.skills.get(str(a.skill), 0.0)) >= float(a.goal)
	return false


static func _still_possible(sim: LifeSim, r: Dictionary, a: Dictionary) -> bool:
	match str(a.kind):
		"career", "shop":
			return Jobs.vacancies(sim, str(a.title)) > 0 or int(a.stage) == 2
		"marry":
			return str(r.partner) == "" or bool(r.get("married", false))
		"family":
			return bool(r.get("married", false))
		"home":
			var home := sim.building_by_id(int(r.home))
			return not home.is_empty() and int(home.level) < Catalog.max_level("home")
	return true


static func _complete(sim: LifeSim, index: int, a: Dictionary) -> void:
	var r: Dictionary = sim.residents[index]
	r.aspiration["stage"] = 3
	r.aspiration["ask_after"] = sim.day() + COOLDOWN_DAYS
	r.points = int(r.points) + 25
	r.needs.fun = 100.0
	r.stress = maxf(0.0, float(r.stress) - 20.0)
	r.bond = minf(100.0, float(r.bond) + 3.0)
	sim.notice("%s's dream came true: %s." % [r.name, str(a.text).to_lower()])
	sim.log_event("%s achieved a dream: %s." % [r.name, str(a.text).to_lower()])
	sim.say(index, Social.pick(["I did it! I really did it!", "It's real. After all this time!", "Thank you, everyone. I'm so happy."], sim.rng))
	sim.emote(index, "star", 0.1)
	Psyche.add_core(sim, r, "Day %d: My dream came true: %s." % [sim.day(), str(a.text).to_lower()], 0.8, 0.9)
	Rumors.create(sim, str(r.name), "", "heroic", "%s achieved their dream: %s" % [r.name, str(a.text).to_lower()], 0.5, [index])
	sim.push_fx({"type": "dream_done", "who": index})


# --- asking the chief -----------------------------------------------------------------------------------------------------------

static func cost_of(sim: LifeSim, r: Dictionary, a: Dictionary) -> int:
	match str(a.kind):
		"home":
			var home := sim.building_by_id(int(r.home))
			return int(Catalog.cost("home", int(home.level) + 1).coins) if not home.is_empty() else 0
		"marry":
			return 40
		"skill":
			return 30
		"family":
			return 0
	return 0


## A resident with a dream that needs the chief's help, as an advice request ({} if nobody is ready to ask).
static func request(sim: LifeSim) -> Dictionary:
	var order: Array = range(sim.residents.size())
	order.shuffle()
	for i in order:
		var r: Dictionary = sim.residents[i]
		var a := get_of(r)
		if a.is_empty() or int(a.stage) != 0 or sim.day() < int(a.get("ask_after", 0)):
			continue
		if sim.talking.has(i) or sim.is_inside(r) or str(r.action) == "sleep" or bool(Health.is_ill(sim, r)):
			continue
		var cost := cost_of(sim, r, a)
		var opts: Array = []
		var help := "Yes, you have my blessing%s." % (" (%d coins)" % cost if cost > 0 else "")
		match str(a.kind):
			"career", "shop":
				help = "Yes. Take the job, and good luck."
			"home":
				help = "Yes. We'll pay for the bigger home (%d coins)." % cost
			"marry":
				help = "Yes. I'll pay for the wedding feast (%d coins)." % cost
			"skill":
				help = "Yes. Here are some books and time off (%d coins)." % cost
			"family":
				help = "Yes. May your household grow."
		opts.append({"id": 0, "text": help, "effect": "approve"})
		opts.append({"id": 1, "text": "Not yet. Show me you're ready first.", "effect": "delay"})
		opts.append({"id": Advice.NOT_NOW, "text": "I can't help with that.", "effect": "refuse"})
		var question := "Chief, may I tell you what I dream of? %s. I'd be so grateful for your support." % str(a.text)
		match str(a.kind):
			"career", "shop":
				question = "Chief, I'd love to %s. There's an opening, and I think I'd be good at it. Will you let me?" % str(a.text).to_lower()
			"marry":
				question = "Chief, my heart is set on finding someone to marry. Would you bless the idea, and help us celebrate when the day comes?"
			"home":
				question = "Chief, my home is getting small for our dreams. Could the village help me build a bigger one?"
			"skill":
				question = "Chief, I want to become a real master of %s. Could you give me the books and the time?" % str(a.get("text_skill", "my craft"))
			"family":
				question = "Chief, we would love to have a child. Would you wish us well?"
		return {"kind": "quest", "topic": str(a.kind), "resident": i, "question": question, "options": opts}
	return {}


static func mark_asked(sim: LifeSim, index: int) -> void:
	var a := get_of(sim.residents[index])
	if not a.is_empty():
		a["stage"] = 1


## Wait and ask again later.
static func delay(sim: LifeSim, index: int, days: int = RETRY_DAYS) -> void:
	if index < 0 or index >= sim.residents.size():
		return
	var r: Dictionary = sim.residents[index]
	var a := get_of(r)
	if a.is_empty():
		return
	a["stage"] = 0
	a["ask_after"] = sim.day() + days


## The chief's answer. Returns a short message for the log.
static func resolve(sim: LifeSim, index: int, effect: String) -> String:
	var r: Dictionary = sim.residents[index]
	var a := get_of(r)
	if a.is_empty():
		return "%s has no dream just now." % r.name
	match effect:
		"delay":
			delay(sim, index)
			sim.say(index, "Of course, Chief. I'll show you.")
			return "%s will try to prove themselves." % r.name
		"refuse":
			r.aspiration = {}
			r.stress = minf(100.0, float(r.stress) + 6.0)
			r.bond = maxf(0.0, float(r.bond) - 2.0)
			sim.say(index, "I... understand, Chief.")
			Psyche.add_core(sim, r, "Day %d: The chief turned down my dream." % sim.day(), 0.3, -0.4)
			return "%s's hopes are dashed." % r.name
	var cost := cost_of(sim, r, a)
	if sim.money < cost:
		delay(sim, index, 3)
		sim.say(index, "We can't afford it yet. I'll wait.")
		return "The village can't afford it yet (%d coins)." % cost
	var message := ""
	match str(a.kind):
		"career", "shop":
			var res := Jobs.assign(sim, index, str(a.title))
			if not bool(res.ok):
				delay(sim, index, 3)
				return str(res.message)
			message = str(res.message)
		"home":
			var home := sim.building_by_id(int(r.home))
			if home.is_empty():
				delay(sim, index, 3)
				return "%s has no home to upgrade." % r.name
			# The chief's backing stands in for the visits a building normally needs.
			home.visits = maxi(int(home.visits), int(Catalog.UPGRADE_VISITS[clampi(int(home.level), 0, Catalog.UPGRADE_VISITS.size() - 1)]))
			var up := sim.upgrade_building(int(home.id))
			if up != "Upgrade started.":
				delay(sim, index, 3)
				return up
			message = "The %s is being enlarged for %s." % [Catalog.label(str(home.kind)).to_lower(), r.name]
		"marry":
			sim.money -= cost
			for name_ in r.romance.keys():
				r.romance[name_] = minf(100.0, float(r.romance[name_]) + 12.0)
			if sim.festival.is_empty():
				Festivals.call_feast(sim)
			message = "%s has your blessing, and the village feasts to celebrate." % r.name
		"skill":
			sim.money -= cost
			var sk := str(a.skill)
			r.skills[sk] = float(r.skills.get(sk, 0.0)) + 15.0
			message = "%s gets books and time to study." % r.name
		"family":
			message = "%s is wished well." % r.name
			r.family_blessing_until = sim.day() + 12
	a["stage"] = 2
	r.bond = minf(100.0, float(r.bond) + 3.5)
	sim.say(index, Social.pick(["Thank you, Chief. You won't regret it.", "You've made my year, Chief.", "I'll make you proud."], sim.rng))
	sim.emote(index, "heart", 0.3)
	Psyche.add_core(sim, r, "Day %d: The chief backed my dream: %s." % [sim.day(), str(a.text).to_lower()], 0.6, 0.8)
	if _done(sim, r, a):
		_complete(sim, index, a)
	return message
