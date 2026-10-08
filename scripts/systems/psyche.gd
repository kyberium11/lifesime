class_name Psyche
extends RefCounted
## Inner life: Five-Factor personality, values and beliefs, chronic stress and mental breaks, trauma and core
## memories. Everything lives in extra keys on the resident dictionary (see extend()) so older saves still load.

const FACTORS := ["o", "c", "e", "a", "n"]
const FACTOR_NAMES := {"o": "Openness", "c": "Conscientiousness", "e": "Extraversion", "a": "Agreeableness", "n": "Neuroticism"}
const VALUES := ["Family", "Ambition", "Tradition", "Freedom", "Peace", "Honesty", "Community", "Knowledge", "Nature"]
## What each value objects to being ordered to do (forcing it is stressful and often refused).
const CONFLICTS := {"guard": ["Peace"], "chop": ["Nature"], "mine": ["Nature"], "work": ["Freedom"], "study": ["Tradition"], "socialize": []}
## Starting leanings by temperament: o c e a n deltas around 0.5.
const TRAIT_BIAS := {
	"Curious gardener": [0.15, 0.1, -0.05, 0.1, -0.1], "Outgoing cook": [0.0, 0.0, 0.3, 0.2, -0.05],
	"Ambitious maker": [0.05, 0.3, 0.1, -0.15, 0.0], "Creative bookworm": [0.3, 0.0, -0.2, 0.05, 0.1],
	"Quiet dreamer": [0.25, -0.1, -0.3, 0.1, 0.2], "Cheerful helper": [0.0, 0.05, 0.25, 0.3, -0.2],
	"Practical builder": [-0.1, 0.25, 0.0, 0.0, -0.1], "Gentle healer": [0.1, 0.1, -0.05, 0.3, 0.05],
	"Restless explorer": [0.3, -0.15, 0.15, 0.0, 0.0], "Thoughtful planner": [0.05, 0.3, -0.1, 0.05, 0.1],
	"Playful joker": [0.1, -0.2, 0.3, 0.0, -0.05], "Careful saver": [-0.1, 0.25, -0.1, 0.0, 0.15],
}
const TRAIT_VALUES := {
	"Curious gardener": ["Nature", "Knowledge"], "Outgoing cook": ["Community", "Family"], "Ambitious maker": ["Ambition", "Honesty"],
	"Creative bookworm": ["Knowledge", "Freedom"], "Quiet dreamer": ["Peace", "Freedom"], "Cheerful helper": ["Community", "Peace"],
	"Practical builder": ["Tradition", "Ambition"], "Gentle healer": ["Peace", "Family"], "Restless explorer": ["Freedom", "Nature"],
	"Thoughtful planner": ["Honesty", "Tradition"], "Playful joker": ["Freedom", "Community"], "Careful saver": ["Tradition", "Family"],
}
const SKILLS := ["craft", "cooking", "gardening", "knowledge", "fitness"]
const BREAK_STRESS := 85.0


static func _h(name_: String, salt: int) -> float:
	return float(absi(hash("%s:%d" % [name_, salt])) % 1000) / 1000.0


## Fill in every inner-life key that is missing. Safe to call on new residents and on loaded saves.
static func extend(r: Dictionary, rng: RandomNumberGenerator = null) -> void:
	var name_ := str(r.get("name", "x"))
	var bias: Array = TRAIT_BIAS.get(str(r.get("trait", "")), [0.0, 0.0, 0.0, 0.0, 0.0])
	if not r.has("ocean") or not r.ocean is Dictionary:
		var o := {}
		for i in range(FACTORS.size()):
			o[FACTORS[i]] = clampf(0.5 + float(bias[i]) + (_h(name_, i) - 0.5) * 0.4, 0.05, 0.95)
		r.ocean = o
	if not r.has("values") or not r.values is Array or r.values.is_empty():
		var picks: Array = (TRAIT_VALUES.get(str(r.get("trait", "")), ["Community"]) as Array).duplicate()
		var extra: String = VALUES[int(_h(name_, 9) * VALUES.size()) % VALUES.size()]
		if extra not in picks:
			picks.append(extra)
		r.values = picks
	var defaults := {"stress": 12.0, "break_until": 0.0, "break_kind": "", "trauma": 0.0, "warmth": 100.0, "ill_until": 0.0, "ill_kind": "", "immune_until": 0.0, "injured": false,
		"partner": "", "partner_since": 0, "married": false, "profession": "", "employer": -1, "savings": 0, "aspiration": {}, "family_blessing_until": 0, "reputation_note": "", "birth_day": 0, "down_until": 0.0, "fleeing_until": 0.0, "fight_cd": 0.0}
	for key in defaults:
		if not r.has(key):
			r[key] = defaults[key]
	for key in ["romance", "rivalry", "opinion", "last_contact"]:
		if not r.has(key) or not r[key] is Dictionary:
			r[key] = {}
	for key in ["parents", "children", "core", "heard"]:
		if not r.has(key) or not r[key] is Array:
			r[key] = []
	if not r.has("genes") or not r.genes is Dictionary:
		r.genes = {"talent": SKILLS[int(_h(name_, 21) * SKILLS.size()) % SKILLS.size()], "hardy": 0.85 + _h(name_, 22) * 0.3, "height": 0.94 + _h(name_, 23) * 0.12}


## Genes and temperament for a child, blended from two parents with some mutation.
static func inherit(child: Dictionary, a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var o := {}
	for f in FACTORS:
		o[f] = clampf((float(a.ocean[f]) + float(b.ocean[f])) * 0.5 + rng.randf_range(-0.14, 0.14), 0.05, 0.95)
	child.ocean = o
	var pool: Array = []
	pool.append_array(a.values)
	pool.append_array(b.values)
	pool.shuffle()
	var vals: Array = []
	for v in pool:
		if v not in vals and vals.size() < 3:
			vals.append(v)
	child.values = vals
	var parent: Dictionary = a if rng.randf() < 0.5 else b
	child.genes = {
		"talent": str(parent.genes.talent) if rng.randf() < 0.8 else SKILLS[rng.randi() % SKILLS.size()],
		"hardy": clampf((float(a.genes.hardy) + float(b.genes.hardy)) * 0.5 + rng.randf_range(-0.06, 0.06), 0.7, 1.3),
		"height": clampf((float(a.genes.height) + float(b.genes.height)) * 0.5 + rng.randf_range(-0.04, 0.04), 0.88, 1.12),
	}


# --- effects of personality ------------------------------------------------------------------------------

static func f(r: Dictionary, factor: String) -> float:
	return float((r.get("ocean", {}) as Dictionary).get(factor, 0.5))


## Extroverts burn through company faster; the anxious tire and get bored a little sooner.
static func decay_mult(r: Dictionary, need: String) -> float:
	match need:
		"social": return 0.7 + f(r, "e") * 0.8
		"fun": return 1.15 - f(r, "o") * 0.3
		"energy": return 0.92 + f(r, "n") * 0.18
	return 1.0


static func social_gain(r: Dictionary) -> float:
	return (0.7 + f(r, "e") * 0.7) * (1.0 - float(r.get("trauma", 0.0)) * 0.4)


static func work_mult(r: Dictionary) -> float:
	return 0.85 + f(r, "c") * 0.3


static func skill_mult(r: Dictionary, skill: String) -> float:
	var m := 1.0
	if skill == "knowledge":
		m *= 0.8 + f(r, "o") * 0.5
	if str((r.get("genes", {}) as Dictionary).get("talent", "")) == skill:
		m *= 1.3
	return m


## How well two residents click, 0..1: similar temperaments and shared values.
static func compat(a: Dictionary, b: Dictionary) -> float:
	var diff := 0.0
	for k in ["o", "c", "e", "n"]:
		diff += absf(f(a, k) - f(b, k))
	var shared := 0
	for v in a.get("values", []):
		if v in b.get("values", []):
			shared += 1
	var kind := (f(a, "a") + f(b, "a")) * 0.5
	return clampf(1.0 - diff / 2.4 + shared * 0.12 + (kind - 0.5) * 0.3, 0.0, 1.0)


# --- stress and breaks -------------------------------------------------------------------------------------

static func tick(sim: LifeSim, r: Dictionary, index: int, dm: float) -> void:
	var n: Dictionary = r.needs
	var rise := 0.0
	for key in LifeSim.NEEDS:
		if float(n[key]) < 20.0:
			rise += 0.035
	if sim.mood(r) < 40.0:
		rise += 0.012
	if float(r.ill_until) > sim.minutes:
		rise += 0.015
	rise += float(r.trauma) * 0.01
	rise *= 0.6 + f(r, "n") * 0.9
	var action := str(r.action)
	var calm := 0.0
	if action in ["sleep", "rest"]:
		calm = 0.07
	elif action in ["play", "socialize", "exercise", "wash"]:
		calm = 0.045
	elif sim.mood(r) > 72.0:
		calm = 0.018
	calm *= 0.8 + (1.0 - f(r, "n")) * 0.4
	r.stress = clampf(float(r.stress) + (rise - calm) * dm, 0.0, 100.0)
	r.trauma = maxf(0.0, float(r.trauma) - 0.0008 * dm)
	if float(r.break_until) > 0.0 and sim.minutes >= float(r.break_until):
		r.break_until = 0.0
		r.break_kind = ""
		r.stress = minf(float(r.stress), 52.0)
		sim.say(index, "I... I think I'm all right now. Sorry about that.")
	elif float(r.break_until) <= 0.0 and float(r.stress) >= BREAK_STRESS + f(r, "c") * 8.0:
		_break(sim, r, index)


static func _break(sim: LifeSim, r: Dictionary, index: int) -> void:
	var kind := "withdraw"
	if f(r, "a") < 0.4 and f(r, "n") > 0.45:
		kind = "outburst"
	elif f(r, "e") > 0.55 and f(r, "c") < 0.5:
		kind = "binge"
	elif f(r, "n") < 0.35:
		kind = "withdraw"
	r.break_kind = kind
	r.break_until = sim.minutes + sim.rng.randf_range(100.0, 180.0)
	sim.release(index)
	r.queue.clear()
	sim.log_event("%s is having a breakdown (%s)." % [r.name, {"withdraw": "withdrawing from everyone", "outburst": "lashing out", "binge": "comfort eating"}[kind]])
	sim.notice("%s is overwhelmed." % r.name)
	sim.emote(index, "sweat", 0.0)
	add_core(sim, r, "Day %d: I broke down. Everything felt like too much." % sim.day(), 0.6, -0.5)
	Rumors.create(sim, str(r.name), "", "breakdown", "%s had a breakdown" % r.name, -0.5, [index])
	match kind:
		"withdraw":
			if sim.start_action(index, "rest"):
				r.commanded = true
				r.remaining = 150.0
			sim.say(index, "Please... I just need to be alone.")
		"binge":
			var eaten := mini(sim.food, 3)
			sim.food -= eaten
			r.needs.hunger = 100.0
			sim.money = maxi(0, sim.money - 8)
			r.needs.fun = minf(100.0, float(r.needs.fun) + 25.0)
			sim.say(index, "I deserve this. Just let me eat.")
		"outburst":
			var other := sim._nearest_resident(index, 6.0)
			if other >= 0:
				sim.resident_interact(index, other, "argue")
				Rumors.create(sim, str(r.name), str(sim.residents[other].name), "argue", "%s screamed at %s" % [r.name, sim.residents[other].name], -0.6, [index, other])
			sim.say(index, "I can't take this anymore!")


## Is this order against the resident's values? Returns a refusal line, or "" if fine.
static func dissonance(sim: LifeSim, index: int, action: String) -> String:
	var r: Dictionary = sim.residents[index]
	for v in CONFLICTS.get(action, []):
		if v in r.values:
			r.stress = minf(100.0, float(r.stress) + 5.0)
			if sim.rng.randf() < 0.5:
				return "I can't, Chief. It goes against what I believe in (%s)." % str(v).to_lower()
	return ""


static func add_core(sim: LifeSim, r: Dictionary, text: String, weight: float, valence: float) -> void:
	for existing in r.core:
		if str(existing.text).get_slice(": ", 1) == text.get_slice(": ", 1):
			return
	r.core.append({"text": text, "weight": weight, "valence": valence, "day": sim.day()})
	if r.core.size() > 6:
		r.core.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.weight) > float(b.weight))
		r.core.resize(6)
	if valence < 0.0:
		r.trauma = minf(1.0, float(r.trauma) + weight * 0.35)
		r.stress = minf(100.0, float(r.stress) + weight * 18.0)
	else:
		r.stress = maxf(0.0, float(r.stress) - weight * 8.0)


# --- descriptions (for the UI and for the AI that voices residents) ---------------------------------------------

static func level_word(v: float, low: String, mid: String, high: String) -> String:
	return low if v < 0.38 else (mid if v < 0.64 else high)


static func personality_text(r: Dictionary) -> String:
	var bits: Array = [
		level_word(f(r, "e"), "reserved and happier alone", "friendly in small doses", "outgoing and always seeking company"),
		level_word(f(r, "o"), "set in their ways", "open to some new ideas", "endlessly curious and imaginative"),
		level_word(f(r, "c"), "easygoing and a little messy", "reasonably dependable", "careful, tidy and driven"),
		level_word(f(r, "a"), "blunt and competitive", "fair-minded", "warm and eager to help"),
		level_word(f(r, "n"), "calm under pressure", "occasionally anxious", "anxious and quick to worry"),
	]
	return ", ".join(bits)


static func stress_word(r: Dictionary) -> String:
	var s := float(r.stress)
	if float(r.break_until) > 0.0:
		return "in the middle of a breakdown"
	if s >= 70.0:
		return "close to breaking"
	if s >= 45.0:
		return "stressed"
	if s >= 25.0:
		return "a bit tense"
	return "relaxed"


static func health_text(sim: LifeSim, r: Dictionary) -> String:
	var parts: Array = []
	if float(r.down_until) > sim.minutes:
		parts.append("knocked out")
	if float(r.ill_until) > sim.minutes:
		parts.append("down with %s" % str(r.ill_kind))
	if bool(r.injured):
		parts.append("injured")
	if float(r.warmth) < 35.0:
		parts.append("freezing")
	return ", ".join(parts) if not parts.is_empty() else "healthy"


## Plain-language inner life for prompts and the Mind tab: {personality, values, stress, health, partner, family, gossip, core}.
static func describe(sim: LifeSim, r: Dictionary) -> Dictionary:
	var family: Array = []
	if not r.parents.is_empty():
		family.append("child of %s" % " and ".join(r.parents))
	if not r.children.is_empty():
		family.append("parent of %s" % ", ".join(r.children))
	var gossip: Array = []
	for id in (r.heard as Array).slice(-3):
		var ru := Rumors.find(sim, int(id))
		if not ru.is_empty():
			gossip.append(str(ru.text))
	var core: Array = []
	for c in r.core:
		core.append(str(c.text))
	return {
		"personality": personality_text(r).left(1).to_upper() + personality_text(r).substr(1), "values": ", ".join(r.values), "stress": stress_word(r), "health": health_text(sim, r),
		"partner": str(r.partner), "family": "; ".join(family), "gossip": gossip, "core": core.slice(0, 2),
		"stage": Lifecycle.stage_name(int(r.age)), "reputation": int(Rumors.reputation(sim, str(r.name))), "belongings": Ownership.summary(sim, str(r.name)), "job": Jobs.label_of(r), "dream": Quests.text_of(r), "savings": int(r.get("savings", 0)),
	}
