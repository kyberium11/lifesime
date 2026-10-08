class_name Dialogue
extends RefCounted
## Offline conversation writer: multi-turn exchanges built from what is actually happening in the town
## (weather, work, food, moods, wishes, projects, the chief). Used whenever the AI is unavailable or slow.

const GREETINGS := {"morning": ["Good morning", "Morning", "Rise and shine"], "afternoon": ["Good afternoon", "Afternoon", "Hello there"], "evening": ["Good evening", "Evening", "Hey, good to see you"], "night": ["Out late", "Still up", "Quiet night"]}
const MOOD_LINES := {
	"happy": ["I'm feeling wonderful today.", "Honestly, I couldn't be happier.", "Everything seems to be going my way."],
	"content": ["Can't complain, really.", "Steady as ever.", "It's been a pleasant day."],
	"hungry": ["My stomach's been growling all morning.", "I could eat just about anything right now.", "I really need a proper meal."],
	"tired": ["I'm worn out, to be honest.", "I could sleep for a week.", "My legs feel like lead today."],
	"dirty": ["I badly need a wash.", "I've been up to my elbows in work all day.", "I smell like the workshop, sorry."],
	"lonely": ["It's nice to have someone to talk to.", "I've been a bit on my own lately.", "I was hoping I'd run into someone."],
	"bored": ["I've been bored out of my mind.", "Nothing exciting going on, is there?", "I need something fun to do."],
	"sick": ["I haven't been feeling well.", "I think I'm coming down with something.", "I'm not at my best, I'm afraid."],
	"gloomy": ["It's been a rough few days.", "My head's not in the right place.", "I've had better days."],
}


static func _name(sim: LifeSim, i: int) -> String:
	return str(sim.residents[i].name)


static func _weather(sim: LifeSim) -> String:
	match sim.weather:
		"Rain": return "This rain just won't let up, will it?"
		"Cloudy": return "Bit gray out today, isn't it?"
	match sim.season():
		"Spring": return "Lovely spring weather we're having."
		"Summer": return "It's a hot one today."
		"Autumn": return "The leaves are turning. Autumn suits this place."
	return "It's a crisp, cold day."


static func _period(sim: LifeSim) -> String:
	var h := int(sim.minutes) % 1440 / 60
	if h < 5 or h >= 21:
		return "night"
	if h < 12:
		return "morning"
	if h < 17:
		return "afternoon"
	return "evening"


static func _topic(sim: LifeSim, a: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = []
	var project := sim.active_project()
	if not project.is_empty():
		options.append({"open": "Did you see they're working on the %s?" % str(project.label).to_lower(), "react": ["It'll be good for the village.", "About time, honestly.", "I hope they finish before winter."], "follow": "I'm hoping to put in a shift on it myself."})
	if sim.food + sim.meals < sim.residents.size():
		options.append({"open": "Have you seen how empty the larder is getting?", "react": ["I noticed. We should plant more.", "It worries me a little.", "Somebody should talk to the chief about farms."], "follow": "More farms would solve it."})
	else:
		options.append({"open": "The market's well stocked this week.", "react": ["That's a relief.", "Good. Nobody likes an empty plate.", "Mira's cooking has a lot to do with it."], "follow": "I could eat there every day."})
	if sim.residents.size() > 6:
		options.append({"open": "Have you noticed how many new faces there are?", "react": ["The village is really growing.", "I keep meeting people I've never seen.", "It's exciting, and a little overwhelming."], "follow": "I wonder what it will look like in a year."})
	if not a.wants.is_empty():
		var want := str(a.wants[0].text).to_lower()
		options.append({"open": "I've set myself a goal: %s." % want, "react": ["That's a good one. You'll manage it.", "Ambitious! I like that.", "Let me know if I can help."], "follow": "One step at a time, right?"})
	options.append({"open": _weather(sim), "react": ["It does make you notice the sky.", "I never get tired of this view.", "The weather's all anyone talks about."], "follow": "At least the work keeps us busy."})
	options.append({"open": "The chief walked by earlier. Seemed deep in thought.", "react": ["That old man sees more than he says.", "I'd love his advice on something.", "He's been good for this village."], "follow": "I should ask him about the new homes."})
	return options[rng.randi() % options.size()]


static func _own_line(sim: LifeSim, i: int, rng: RandomNumberGenerator) -> String:
	var r: Dictionary = sim.residents[i]
	var lines: Array = Social.TRAIT_LINES.get(r.name, Social.GENERIC_LINES)
	return str(lines[rng.randi() % lines.size()])


## Returns {lines: [{speaker: 0|1, text}], summary}. speaker 0 is `a`, 1 is `b`.
static func build(sim: LifeSim, a_index: int, b_index: int, kind: String, success: bool) -> Dictionary:
	var rng := sim.rng
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	var an := str(a.name)
	var bn := str(b.name)
	var lines: Array = []
	var summary := ""
	var topic := _topic(sim, a, rng)
	var greeting: String = Social.pick(GREETINGS[_period(sim)], rng)
	var a_mood: String = Social.pick(MOOD_LINES[sim.emotion(a)], rng)
	var b_mood: String = Social.pick(MOOD_LINES[sim.emotion(b)], rng)
	match kind:
		"chat":
			lines = [
				[0, "%s, %s! How is your day going?" % [greeting, bn]],
				[1, "%s %s" % [Social.pick(["Pretty well, thanks for asking.", "Not bad at all.", "Better now that you've stopped by."], rng), b_mood] if success else "Oh, hi. Sorry, my mind's somewhere else."],
				[0, str(topic.open)],
				[1, str(Social.pick(topic.react, rng)) if success else "Mm. Maybe. I really should get going."],
			]
			if success:
				lines.append([0, "%s %s" % [a_mood, str(topic.follow)]])
				lines.append([1, _own_line(sim, b_index, rng)])
			summary = "%s and %s chatted about the day." % [an, bn]
		"joke":
			lines = [
				[0, "%s, you have to hear this one. %s" % [bn, Social.line("joke", "start", rng)]],
				[1, Social.line("joke", "good" if success else "meh", rng)],
				[0, Social.pick(["I've got a whole barn full of those.", "Wait, there's a second half.", "I've been saving that all week."], rng) if success else "Tough crowd. I'll workshop it."],
				[1, Social.pick(["Please, no more. My sides hurt.", "Tell Theo that one, he'd love it.", "Okay, that actually made my day."], rng) if success else "Maybe stick to your day job."],
			]
			summary = "%s tried a joke on %s." % [an, bn]
		"compliment":
			lines = [
				[0, "%s, I just wanted to say: %s" % [bn, Social.line("compliment", "start", rng, bn).to_lower()]],
				[1, Social.line("compliment", "good" if success else "meh", rng)],
				[0, Social.pick(["The village is lucky to have you.", "I mean it. You make this place feel like home.", "Not everyone works as hard as you do."], rng)],
				[1, Social.pick(["Coming from you, that really means something.", "Well, now you've made me blush.", "You're not so bad yourself, %s." % an], rng) if success else "Right. Thanks. I should get back to it."],
			]
			summary = "%s paid %s a compliment." % [an, bn]
		"gossip":
			lines = [
				[0, "%s, keep this between us, but %s" % [bn, Social.line("gossip", "start", rng).to_lower()]],
				[1, Social.line("gossip", "good" if success else "meh", rng)],
				[0, str(topic.open)],
				[1, str(Social.pick(topic.react, rng)) if success else "I really wouldn't know about any of that."],
			]
			summary = "%s and %s traded village gossip." % [an, bn]
		"hug":
			lines = [
				[0, "%s, you look like you could use a hug. Come here." % bn],
				[1, Social.line("hug", "good" if success else "meh", rng)],
				[0, "Rough few days?" if success else "Sorry, I didn't mean to be pushy."],
				[1, "%s Thanks for noticing." % b_mood if success else "It's fine. I'm just not much of a hugger."],
			]
			summary = "%s offered %s a hug." % [an, bn]
		"argue":
			lines = [
				[0, Social.line("argue", "start", rng)],
				[1, "%s %s" % [Social.line("argue", "good", rng), Social.pick(["You always do this.", "Don't put this on me.", "Maybe if you listened for once."], rng)]],
				[0, Social.pick(["Some of us actually pull our weight around here.", "I'm tired of cleaning up after everyone.", "You never think about anybody but yourself."], rng)],
				[1, Social.pick(["Fine. Let's talk when we've both cooled off.", "I don't have time for this.", "You know what? Forget it."], rng)],
			]
			summary = "%s and %s had an argument." % [an, bn]
		_:
			lines = [[0, "%s, %s." % [greeting, bn]], [1, "%s, %s." % [greeting, an]]]
			summary = "%s and %s greeted each other." % [an, bn]
	var out: Array = []
	for e in lines:
		out.append({"speaker": int(e[0]), "text": str(e[1]).strip_edges()})
	return {"lines": out, "summary": summary}


## The payload the bridge's /talk endpoint expects.
static func payload(sim: LifeSim, a_index: int, b_index: int, kind: String, success: bool) -> Dictionary:
	var speakers: Array = []
	for i in [a_index, b_index]:
		var r: Dictionary = sim.residents[i]
		speakers.append({
			"name": r.name, "trait": r.trait, "age": r.age, "emotion": sim.emotion(r),
			"wants": r.wants.map(func(w: Dictionary) -> String: return str(w.text)),
			"memories": r.memory.slice(-4),
		})
	var a: Dictionary = sim.residents[a_index]
	var b: Dictionary = sim.residents[b_index]
	var score := sim.relation(a, str(b.name))
	var outcome := "It goes well." if success else "It falls flat; one of them is distracted or unreceptive."
	if kind == "argue":
		outcome = "They genuinely disagree; the mood turns tense."
	return {
		"speakers": speakers,
		"relationship": {"level": Social.bond_label(score), "score": int(score)},
		"interaction": {"kind": kind, "outcome": outcome},
		"context": {"day": sim.day(), "time": sim.clock_text(), "season": sim.season(), "weather": sim.weather, "stage": sim.stage_name(), "population": sim.residents.size(), "recent_events": sim.journal.slice(-5), "building_project": "" if sim.active_project().is_empty() else str(sim.active_project().label)},
	}
