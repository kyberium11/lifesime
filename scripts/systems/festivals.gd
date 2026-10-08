class_name Festivals
extends RefCounted
## Seasonal festivals in the plaza: Bloom Fair (spring), Midsummer Night (summer), Harvest Fair (autumn) and
## Winter Feast (winter), each on the fourth day of its season. People gather from the afternoon, the plaza is
## decorated, a contest is held (the winner gets a prize and the village's admiration), the market stirs, and the
## night ends with fireworks. The chief can also call an impromptu feast.

const FESTIVALS := {
	"Spring": {"name": "Bloom Fair", "contest": "craft", "contest_name": "garland-making", "market": {"wool": 1.15}},
	"Summer": {"name": "Midsummer Night", "contest": "fitness", "contest_name": "footrace", "market": {"food": 0.92}},
	"Autumn": {"name": "Harvest Fair", "contest": "gardening", "contest_name": "biggest pumpkin", "market": {"food": 1.12, "wool": 1.15}},
	"Winter": {"name": "Winter Feast", "contest": "cooking", "contest_name": "feast cooking", "market": {"wood": 1.1}},
}
const FESTIVAL_DAY_IN_SEASON := 4
const GATHER_HOUR := 13.5
const CONTEST_HOUR := 18.0
const END_HOUR := 23.0
const PRIZE := 30


static func day_in_season(sim: LifeSim) -> int:
	return ((sim.day() - 1) % 7) + 1


static func hour(sim: LifeSim) -> float:
	return fmod(sim.minutes / 60.0, 24.0)


static func is_active(sim: LifeSim) -> bool:
	return not sim.festival.is_empty() and bool(sim.festival.get("active", false))


static func plaza_spot(sim: LifeSim) -> Vector2:
	var plazas := sim.buildings_of("plaza")
	if plazas.is_empty():
		return Vector2(2.0, 2.0)
	var t := sim.tile_of(plazas[0])
	return Vector2(float(t.x), float(t.y))


## Called at the start of each day: is today a festival day?
static func daily(sim: LifeSim) -> void:
	if not sim.festival.is_empty() and sim.day() != int(sim.festival.get("day", -1)):
		sim.festival = {}
	if day_in_season(sim) == FESTIVAL_DAY_IN_SEASON and sim.residents.size() >= 4 and sim.festival.is_empty():
		var spec: Dictionary = FESTIVALS[sim.season()]
		sim.festival = {"name": spec.name, "kind": "season", "day": sim.day(), "active": false, "contest_done": false, "contest": spec.contest, "contest_name": spec.contest_name, "market": spec.market}
		sim.notice("Tonight is the %s! Everyone gathers at the plaza this afternoon." % spec.name)
		sim.log_event("The %s is today." % spec.name)


## An impromptu feast called by the chief.
static func call_feast(sim: LifeSim) -> bool:
	if not sim.festival.is_empty():
		return false
	sim.festival = {"name": "Village Feast", "kind": "feast", "day": sim.day(), "active": false, "contest_done": true, "contest": "", "contest_name": "", "market": {}}
	_start(sim)
	return true


static func tick(sim: LifeSim, dm: float) -> void:
	if sim.festival.is_empty():
		return
	var f: Dictionary = sim.festival
	var h := hour(sim)
	if not bool(f.active):
		if f.kind == "season" and h >= GATHER_HOUR and h < END_HOUR:
			_start(sim)
		return
	if h >= END_HOUR or h < 6.0:
		_end(sim)
		return
	# Everyone present enjoys themselves.
	for r in sim.residents:
		r.needs.fun = minf(100.0, float(r.needs.fun) + 0.12 * dm)
		r.needs.social = minf(100.0, float(r.needs.social) + 0.09 * dm)
		r.stress = maxf(0.0, float(r.stress) - 0.03 * dm)
	if not bool(f.contest_done) and h >= CONTEST_HOUR:
		_contest(sim)


static func _start(sim: LifeSim) -> void:
	var f: Dictionary = sim.festival
	f.active = true
	var everyone: Array = []
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if float(r.get("down_until", 0.0)) <= sim.minutes and not Health.is_ill(sim, r):
			everyone.append(i)
	sim.gather_at(everyone, plaza_spot(sim), "the festival")
	var mult: Dictionary = f.get("market", {})
	if not mult.is_empty():
		sim.events.append({"kind": "festival_market", "text": "The %s fills the market with eager buyers." % f.name, "until": sim.day() + 1, "mult": mult})
	sim.notice("The %s has begun at the plaza!" % f.name)
	sim.log_event("The %s begins." % f.name)
	sim.push_fx({"type": "festival_start", "name": f.name})
	if sim.residents.size() > 0:
		sim.say(0, "Let the %s begin!" % str(f.name).to_lower())


static func _contest(sim: LifeSim) -> void:
	var f: Dictionary = sim.festival
	f.contest_done = true
	var skill := str(f.contest)
	var best := -1
	var best_score := -1.0
	var field: Array = []
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		if int(r.age) < 12 or float(r.get("down_until", 0.0)) > sim.minutes:
			continue
		var score := float(r.skills.get(skill, 0.0)) + sim.rng.randf() * 35.0 + (10.0 if str(r.get("genes", {}).get("talent", "")) == skill else 0.0)
		field.append(i)
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return
	var winner: Dictionary = sim.residents[best]
	sim.money = maxi(0, sim.money - PRIZE)
	winner.savings = int(winner.get("savings", 0)) + PRIZE
	winner.needs.fun = 100.0
	winner.points = int(winner.points) + 15
	for i in field:
		var other: Dictionary = sim.residents[i]
		if i != best:
			other.opinion[str(winner.name)] = minf(100.0, float(other.opinion.get(str(winner.name), sim.relation(other, str(winner.name)))) + 4.0)
	sim.notice("%s wins the %s contest at the %s!" % [winner.name, f.contest_name, f.name])
	sim.log_event("%s won the %s at the %s (prize %d coins)." % [winner.name, f.contest_name, f.name, PRIZE])
	sim.say(best, Social.pick(["I won! I can hardly believe it!", "Thank you all! What a night!", "The %s is mine!" % f.contest_name], sim.rng))
	sim.emote(best, "star", 0.1)
	Psyche.add_core(sim, winner, "Day %d: I won the %s at the %s." % [sim.day(), f.contest_name, f.name], 0.6, 0.8)
	Rumors.create(sim, str(winner.name), "", "heroic", "%s won the %s at the %s" % [winner.name, f.contest_name, f.name], 0.6, [best])
	f.winner = str(winner.name)
	sim.push_fx({"type": "contest_won", "who": best})


static func _end(sim: LifeSim) -> void:
	var f: Dictionary = sim.festival
	f.active = false
	f.ended = true
	for i in range(sim.residents.size()):
		sim.release(i)
		var r: Dictionary = sim.residents[i]
		if str(r.action) == "socialize" and str(r.target) == "the festival":
			r.remaining = 0.0
			r.commanded = false
	sim.notice("The %s is over. What a night." % f.name)
	sim.log_event("The %s ends." % f.name)
	sim.push_fx({"type": "festival_end"})
