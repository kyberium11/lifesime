extends SceneTree
## Aspirations: dreams chosen to fit people, asking the chief, backing/delaying/refusing, completion.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _sim(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 3000
	sim.food = 200
	sim.wood = 200
	sim.stage_floor = 2
	sim.minutes = 5.0 * 1440.0
	sim.last_day = sim.day()
	for r in sim.residents:
		r.values = ["Community"]
	return sim


func _give(sim: LifeSim, index: int, aspiration: Dictionary) -> void:
	sim.residents[index].aspiration = aspiration


func _init() -> void:
	var sim := _sim()
	Quests.daily(sim)
	var with_dream := 0
	for r in sim.residents:
		if not Quests.get_of(r).is_empty():
			with_dream += 1
	check(with_dream >= 3, "most adults get a dream (%d of %d)" % [with_dream, sim.residents.size()])
	var kinds := {}
	for seed_ in range(1, 12):
		var s := _sim(seed_)
		Quests.daily(s)
		for r in s.residents:
			var a := Quests.get_of(r)
			if not a.is_empty():
				kinds[str(a.kind)] = true
	check(kinds.size() >= 3, "different people dream of different things (%s)" % str(kinds.keys()))
	var child := _sim(2)
	child.residents[0].age = 8
	Quests.daily(child)
	check(Quests.get_of(child.residents[0]).is_empty(), "children have no dreams to ask about")
	# nobody asks straight away
	var wait := _sim(3)
	Quests.daily(wait)
	check(Quests.request(wait).is_empty(), "nobody comes to ask on the day they think of it")
	wait.minutes += 3.0 * 1440.0
	wait.last_day = wait.day()
	var req := Quests.request(wait)
	check(not req.is_empty() and req.kind == "quest" and req.options.size() == 3, "a few days later someone asks: " + str(req.get("question", "")).left(60))
	check(req.options[req.options.size() - 1].id == Advice.NOT_NOW, "the last answer is always the refusal")
	# it goes through the real advice lifecycle
	wait.start_advice(req)
	var asker := int(req.resident)
	check(int(Quests.get_of(wait.residents[asker]).stage) == 1, "the dream is marked as asked")
	var msg := wait.resolve_advice(0)
	check(msg != "" and wait.advice.is_empty(), "the chief's answer is carried out: " + msg)
	# each kind of dream
	var career := _sim(4)
	var cr: Dictionary = career.residents[0]
	cr.profession = ""
	_give(career, 0, {"kind": "career", "text": "Become the village farmer", "stage": 1, "goal": 1.0, "base": 0.0, "since": 1, "ask_after": 0, "title": "farmer"})
	check(Quests.resolve(career, 0, "approve").contains("farmer") and Jobs.title_of(cr) == "farmer", "backing a career gives the job")
	check(int(Quests.get_of(cr).stage) == 3, "and the dream is fulfilled at once")
	var home_sim := _sim(5)
	var hr: Dictionary = home_sim.residents[0]
	var home := home_sim.building_by_id(int(hr.home))
	_give(home_sim, 0, {"kind": "home", "text": "Live in a bigger, finer home", "stage": 1, "goal": float(home.level) + 1.0, "base": float(home.level), "since": 1, "ask_after": 0})
	var money_before := home_sim.money
	var home_msg := Quests.resolve(home_sim, 0, "approve")
	check(int(home.target) > int(home.level) and home_sim.money < money_before, "backing a bigger home starts the upgrade: " + home_msg)
	home.level = int(home.target)
	home.target = 0
	Quests.daily(home_sim)
	check(int(Quests.get_of(hr).stage) == 3, "and it is celebrated when finished")
	var love := _sim(6)
	_give(love, 0, {"kind": "marry", "text": "Find someone to marry", "stage": 1, "goal": 1.0, "base": 0.0, "since": 1, "ask_after": 0})
	love.residents[0].romance["Mira"] = 40.0
	var love_msg := Quests.resolve(love, 0, "approve")
	check(float(love.residents[0].romance["Mira"]) > 50.0 and Festivals.is_active(love) == false or not love.festival.is_empty(), "blessing a courtship helps it and calls a feast: " + love_msg)
	var skill := _sim(7)
	_give(skill, 0, {"kind": "skill", "text": "Become a master of cooking", "stage": 1, "goal": 70.0, "base": 0.0, "since": 1, "ask_after": 0, "skill": "cooking", "text_skill": "cooking"})
	var before := float(skill.residents[0].skills.cooking)
	Quests.resolve(skill, 0, "approve")
	check(float(skill.residents[0].skills.cooking) == before + 15.0, "books raise the skill")
	skill.residents[0].skills.cooking = 75.0
	Quests.daily(skill)
	check(int(Quests.get_of(skill.residents[0]).stage) == 3, "mastery completes the dream")
	var fam := _sim(8)
	fam.residents[0].married = true
	_give(fam, 0, {"kind": "family", "text": "Have a child", "stage": 1, "goal": 1.0, "base": 0.0, "since": 1, "ask_after": 0})
	Quests.resolve(fam, 0, "approve")
	check(int(fam.residents[0].family_blessing_until) > fam.day(), "a blessing raises the chance of a child")
	fam.residents[0].children = ["Baby"]
	Quests.daily(fam)
	check(int(Quests.get_of(fam.residents[0]).stage) == 3, "a child fulfils the family dream")
	# delay and refuse
	var delay := _sim(9)
	_give(delay, 0, {"kind": "skill", "text": "Become a master of cooking", "stage": 1, "goal": 70.0, "base": 0.0, "since": 1, "ask_after": 0, "skill": "cooking"})
	Quests.resolve(delay, 0, "delay")
	check(int(Quests.get_of(delay.residents[0]).stage) == 0 and int(Quests.get_of(delay.residents[0]).ask_after) > delay.day(), "asking them to wait postpones the question")
	var stress := float(delay.residents[0].stress)
	Quests.resolve(delay, 0, "refuse")
	check(Quests.get_of(delay.residents[0]).is_empty() and float(delay.residents[0].stress) > stress, "a refusal ends the dream and hurts")
	# too poor
	var poor := _sim(10)
	poor.money = 5
	_give(poor, 0, {"kind": "skill", "text": "Become a master of cooking", "stage": 1, "goal": 70.0, "base": 0.0, "since": 1, "ask_after": 0, "skill": "cooking"})
	check(Quests.resolve(poor, 0, "approve").contains("afford"), "a dream that costs coins waits for coins")
	# no opening, no job
	var none := _sim(11)
	_give(none, 0, {"kind": "career", "text": "Become the village doctor", "stage": 1, "goal": 1.0, "base": 0.0, "since": 1, "ask_after": 0, "title": "doctor"})
	check(not Quests.resolve(none, 0, "approve").contains("is now"), "no clinic, no doctor job")
	# ignoring someone lets the dream wait
	var ignore := _sim(12)
	_give(ignore, 0, {"kind": "skill", "text": "Become a master of cooking", "stage": 0, "goal": 70.0, "base": 0.0, "since": 1, "ask_after": 0, "skill": "cooking"})
	var ask := Quests.request(ignore)
	if not ask.is_empty():
		ignore.start_advice(ask)
		ignore.advice.state = "waiting"
		ignore.minutes += Advice.TIMEOUT_MINUTES + 10.0
		ignore.tick(1.0)
		check(ignore.advice.is_empty(), "an unanswered dream request lapses")
		var ia := Quests.get_of(ignore.residents[int(ask.resident)])
		check(ia.is_empty() or int(ia.stage) == 0, "and the dream goes back to waiting")
	# orders and display
	var o := _sim(13)
	Quests.daily(o)
	check(Orders.parse("what are their dreams", o).intent == "dreams", "dreams order parses")
	check(Orders.execute(o, Orders.parse("what are everyone's dreams", o), 0).ok, "the dreams report works")
	check(Psyche.describe(o, o.residents[0]).has("dream"), "dreams reach the AI's view of a resident")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with dreams loads")
	check(Quests.text_of(back.residents[0]) == Quests.text_of(sim.residents[0]), "dreams survive saving")
	print("QUEST TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
