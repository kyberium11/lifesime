class_name Advice
extends RefCounted
## Residents come to the chief for advice. Two kinds of request:
##  - "city": a resident has noticed what the village needs and brings the council's real options to the chief.
##  - "personal": a resident is struggling (lonely, exhausted, bored, low) and asks what to do.
## A request is {kind, resident, question, options: [{id, text, plan?|effect?}], topic}. The last option is always
## "Not now". The chief answers by choosing, by speaking, or by ignoring (the council then decides after a while).

const TIMEOUT_MINUTES := 360.0
const NOT_NOW := -1
const SKILL_FOR_KIND := {"farm": "gardening", "market": "cooking", "workshop": "craft", "library": "knowledge", "park": "fitness", "office": "craft", "land": "craft", "home": "craft", "bathhouse": "cooking"}


static func _pick_resident(sim: LifeSim, kind: String) -> int:
	var skill: String = SKILL_FOR_KIND.get(kind, "craft")
	var best := -1
	var best_score := -1.0
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if sim.talking.has(i) or sim.is_inside(r) or str(r.action) == "sleep":
			continue
		var score := float(r.skills.get(skill, 0.0)) + sim.rng.randf() * 30.0 + float(r.bond) * 0.3
		if score > best_score:
			best_score = score
			best = i
	return best


## A plain-language label for one of the council's plans.
static func plain(option: Dictionary) -> String:
	var cost := "%d coins" % int(option.coins)
	match str(option.type):
		"build": return "Build a %s (%s)" % [Catalog.label(str(option.kind)).to_lower(), cost]
		"upgrade": return "Upgrade the %s (%s)" % [Catalog.label(str(option.kind)).to_lower(), cost]
		"expand": return "Claim new land for the village (%s)" % cost
		"wall": return "%s (%s)" % [str(option.label), cost]
	return str(option.label)


static func city_request(sim: LifeSim) -> Dictionary:
	var options := CityPlanner.options(sim, 4, true)
	if options.is_empty() or float(options[0].score) < CityPlanner.MIN_SCORE:
		return {}
	var picks: Array = options.slice(0, 3)
	var resident := _pick_resident(sim, str(picks[0].kind))
	if resident < 0:
		return {}
	var opts: Array = []
	for i in range(picks.size()):
		opts.append({"id": i, "text": plain(picks[i]), "plan": picks[i]})
	opts.append({"id": NOT_NOW, "text": "Not now. Let's wait.", "plan": {}})
	var first: Dictionary = picks[0]
	var question := "Chief, may I have a word? %s I think we should %s. What do you say?" % [str(first.reason), plain(first).to_lower()]
	return {"kind": "city", "topic": str(first.kind), "resident": resident, "question": question, "options": opts}


static func personal_request(sim: LifeSim) -> Dictionary:
	var order: Array = range(sim.residents.size())
	order.shuffle()
	for i in order:
		var r: Dictionary = sim.residents[i]
		if sim.talking.has(i) or sim.is_inside(r) or str(r.action) == "sleep":
			continue
		var n: Dictionary = r.needs
		if float(n.social) < 36.0:
			return _personal(i, "lonely", "Chief, I've been feeling lonely lately. Everyone's so busy. What would you do in my place?", [
				["Hold a gathering in the plaza tonight.", "gathering"], ["I'll sit with you for a while.", "sit"], ["Join the others at the park.", "park"]])
		if float(n.energy) < 32.0:
			return _personal(i, "tired", "Chief, I'm completely worn out. I can barely keep my eyes open. Should I keep going?", [
				["Take the rest of the day off.", "rest"], ["Push through, the village needs you.", "push"], ["Ask a friend to share your work.", "share"]])
		if float(n.fun) < 32.0:
			return _personal(i, "bored", "Chief, honestly, I'm bored. There's nothing to look forward to. Any ideas?", [
				["Let's organize a village festival (40 coins).", "festival"], ["Spend time at the library.", "library"], ["Take a long walk.", "walk"]])
		if sim.mood(r) < 42.0:
			return _personal(i, "gloomy", "Chief, I've been down lately and I'm not sure why. Could I talk to you?", [
				["Tell me what's weighing on you.", "listen"], ["Do something you love today.", "joy"], ["Think how far the village has come.", "hope"]])
	return {}


static func _personal(resident: int, topic: String, question: String, rows: Array) -> Dictionary:
	var opts: Array = []
	for i in range(rows.size()):
		opts.append({"id": i, "text": str(rows[i][0]), "effect": str(rows[i][1])})
	opts.append({"id": NOT_NOW, "text": "Not now. Let's talk later.", "effect": ""})
	return {"kind": "personal", "topic": topic, "resident": resident, "question": question, "options": opts}


## What the AI sees when it polishes a request: the resident, the village, and the real options.
static func payload(sim: LifeSim, request: Dictionary) -> Dictionary:
	var r: Dictionary = sim.residents[int(request.resident)]
	var opts: Array = []
	for o in request.options:
		if int(o.id) >= 0:
			opts.append({"id": int(o.id), "text": str(o.text)})
	return {"resident": {"name": r.name, "trait": r.get("trait", ""), "mood": sim.mood(r)}, "kind": request.kind, "topic": request.topic, "draft_question": request.question, "options": opts, "village": sim.city_summary()}


## Apply the chief's answer. Returns a short message for the log.
static func apply(sim: LifeSim, request: Dictionary, option_id: int) -> String:
	var r: Dictionary = sim.residents[int(request.resident)]
	var index := int(request.resident)
	var choice := {}
	for o in request.options:
		if int(o.id) == option_id:
			choice = o
	if str(request.kind) == "quest":
		var effect := "refuse" if (choice.is_empty() or option_id == NOT_NOW) else str(choice.get("effect", "delay"))
		return Quests.resolve(sim, index, effect)
	if choice.is_empty() or option_id == NOT_NOW:
		r.bond = maxf(0.0, float(r.bond) - 1.0)
		sim.say(index, Social.pick(["Understood, Chief. I'll manage.", "Of course. Another time, then.", "All right. Thank you for hearing me."], sim.rng))
		sim.remember(r, "Day %d: I asked the chief for advice, but it wasn't the right moment." % sim.day())
		return "%s will wait." % r.name
	var message := ""
	if str(request.kind) == "city":
		var plan: Dictionary = choice.plan
		message = sim.apply_option(plan, "The chief")
		var ok := message.begins_with("Started") or message == "Upgrade started." or message == "District claimed."
		if ok:
			message = "You decided: %s." % str(choice.text)
		else:
			sim.say(index, "Hmm, it seems we can't afford that right now.")
			return message
		sim.record_decision("The chief", plain(plan), "Advised by %s" % r.name)
		r.bond = minf(100.0, float(r.bond) + 4.0)
		sim.say(index, Social.pick(["Wise choice, Chief. I'll tell everyone.", "Thank you. That will help us all.", "Right away, Chief!"], sim.rng))
		sim.emote(index, "heart", 0.4)
		sim.remember(r, "Day %d: The chief listened to me: %s." % [sim.day(), str(choice.text)])
	else:
		message = _apply_personal(sim, index, str(choice.effect))
		r.bond = minf(100.0, float(r.bond) + 5.0)
		sim.say(index, Social.pick(["That actually helps. Thank you, Chief.", "You always know what to say.", "I feel better already."], sim.rng))
		sim.emote(index, "heart", 0.4)
		sim.remember(r, "Day %d: The chief advised me: %s" % [sim.day(), str(choice.text)])
	sim._check_wants(r)
	return message


static func _apply_personal(sim: LifeSim, index: int, effect: String) -> String:
	var r: Dictionary = sim.residents[index]
	var n: Dictionary = r.needs
	match effect:
		"gathering":
			for other in sim.residents:
				other.needs.social = minf(100.0, float(other.needs.social) + 8.0)
			n.social = minf(100.0, float(n.social) + 35.0)
			return "The village gathers in the plaza for the evening."
		"sit":
			n.social = minf(100.0, float(n.social) + 30.0)
			return "You keep %s company." % r.name
		"park":
			n.social = minf(100.0, float(n.social) + 20.0)
			n.fun = minf(100.0, float(n.fun) + 15.0)
			if r.queue.size() < LifeSim.MAX_QUEUE and sim.has_target("play"):
				r.queue.append("play")
			return "%s heads to the park." % r.name
		"rest":
			n.energy = minf(100.0, float(n.energy) + 40.0)
			return "%s takes the day off." % r.name
		"push":
			sim.money += 20
			n.fun = maxf(0.0, float(n.fun) - 8.0)
			return "%s pushes on, earning a little extra." % r.name
		"share":
			n.energy = minf(100.0, float(n.energy) + 15.0)
			var friend := _best_friend(sim, index)
			if friend >= 0:
				sim.residents[friend].relations[r.name] = minf(100.0, sim.relation(sim.residents[friend], str(r.name)) + 6.0)
				r.relations[sim.residents[friend].name] = minf(100.0, sim.relation(r, str(sim.residents[friend].name)) + 6.0)
			return "A friend steps in to help %s." % r.name
		"festival":
			if sim.money < 40:
				n.fun = minf(100.0, float(n.fun) + 10.0)
				return "There isn't enough money for a festival, but %s cheers up a little." % r.name
			sim.money -= 40
			for other in sim.residents:
				other.needs.fun = minf(100.0, float(other.needs.fun) + 25.0)
				other.needs.social = minf(100.0, float(other.needs.social) + 10.0)
			return "The village holds a festival!"
		"library":
			r.skills.knowledge = float(r.skills.knowledge) + 8.0
			n.fun = minf(100.0, float(n.fun) + 18.0)
			return "%s loses an afternoon in the library." % r.name
		"walk":
			n.fun = minf(100.0, float(n.fun) + 20.0)
			n.health = minf(100.0, float(n.health) + 6.0)
			return "%s goes for a long walk." % r.name
		"listen":
			for key in ["hunger", "energy", "hygiene", "social", "fun", "health"]:
				n[key] = minf(100.0, float(n[key]) + 8.0)
			return "%s feels heard." % r.name
		"joy":
			n.fun = minf(100.0, float(n.fun) + 25.0)
			n.energy = minf(100.0, float(n.energy) + 10.0)
			return "%s spends the day doing what they love." % r.name
		"hope":
			n.social = minf(100.0, float(n.social) + 10.0)
			n.fun = minf(100.0, float(n.fun) + 10.0)
			return "%s smiles remembering the early days." % r.name
	return ""


static func _best_friend(sim: LifeSim, index: int) -> int:
	var r: Dictionary = sim.residents[index]
	var best := -1
	var best_score := 0.0
	for j in range(sim.residents.size()):
		if j == index:
			continue
		var score := sim.relation(r, str(sim.residents[j].name))
		if score > best_score:
			best_score = score
			best = j
	return best


## Which option did the chief mean by these spoken or typed words? Returns an option id, or -2 if unclear.
static func interpret(text: String, options: Array) -> int:
	var t := text.to_lower().strip_edges()
	for phrase in ["not now", "wait", "later", "no thanks", "never mind", "nevermind", "don't", "do not", "not yet"]:
		if t.contains(phrase):
			return NOT_NOW
	var real: Array = options.filter(func(o: Dictionary) -> bool: return int(o.id) >= 0)
	var ordinals := [["first", "one", "1"], ["second", "two", "2"], ["third", "three", "3"]]
	for i in range(mini(ordinals.size(), real.size())):
		for word in ordinals[i]:
			if (" " + t + " ").contains(" " + word + " ") or (" " + t + " ").contains(" option " + word):
				return int(real[i].id)
	var best := -2
	var best_score := 0
	var tie := false
	for o in real:
		var words: PackedStringArray = str(o.text).to_lower().replace("(", " ").replace(")", " ").replace(",", " ").replace(".", " ").split(" ", false)
		var score := 0
		for w in words:
			if w.length() >= 4 and w not in ["the", "that", "with", "this", "coins", "village", "have", "your"] and t.contains(w):
				score += 1
		if score > best_score:
			best_score = score
			best = int(o.id)
			tie = false
		elif score == best_score and score > 0:
			tie = true
	if best_score > 0 and not tie:
		return best
	for phrase in ["yes", "okay", "ok ", "sure", "do it", "approve", "go ahead", "agreed", "sounds good", "let's do", "let us do", "your idea", "your suggestion"]:
		if (t + " ").contains(phrase):
			return int(real[0].id) if not real.is_empty() else -2
	return -2
