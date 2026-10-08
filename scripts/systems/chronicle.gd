class_name Chronicle
extends RefCounted
## The village's written history. Notable events are recorded as they happen ({day, kind, text}) and kept in the
## save. The journal shows them as a timeline and tells the story of each year, offline from the facts or, when the
## local model is running, as a short narrative.

const MAX_ENTRIES := 500
const KINDS := {
	"birth": "Births", "wedding": "Weddings", "love": "Romance", "death": "Farewells", "monsters": "Danger", "festival": "Festivals",
	"dream": "Dreams", "job": "Work", "trade": "Trade", "growth": "Growth", "weather": "Weather and omens",
}
const KIND_COLOR := {
	"birth": "#e98aa8", "wedding": "#e98aa8", "love": "#e98aa8", "death": "#8aa0b8", "monsters": "#e8553f", "festival": "#f0b64a",
	"dream": "#7ccf8e", "job": "#8ed0e8", "trade": "#f0b64a", "growth": "#7ccf8e", "weather": "#a9c4d6",
}
const DAYS_PER_YEAR := 28


static func year_of(day: int) -> int:
	return (day - 1) / DAYS_PER_YEAR + 1


static func season_of(day: int) -> String:
	return ["Spring", "Summer", "Autumn", "Winter"][int((day - 1) / 7) % 4]


## Called each new day: when a year ends its story is written down and flagged so the game can ask the AI for a better one.
static func daily(sim: LifeSim) -> void:
	var today := sim.day()
	if today > 1 and year_of(today) > year_of(today - 1):
		var finished := year_of(today - 1)
		sim.stories[str(finished)] = story_offline(sim, finished)
		sim.story_due = finished
		sim.notice("Year %d is over. Its story is written in the journal (J)." % finished)


## Which kind of history an event-log line is, or "" when it is not worth remembering.
static func classify(message: String) -> String:
	var m := message.to_lower()
	if "was born" in m or "baby" in m:
		return "birth"
	if "married" in m:
		return "wedding"
	if "passed away" in m:
		return "death"
	if "monsters are approaching" in m or "breached" in m or "siege" in m:
		return "monsters"
	if "achieved a dream" in m:
		return "dream"
	if "has grown into" in m:
		return "growth"
	if "festival" in m or "fair begins" in m or " won the " in m or "feast" in m or "midsummer" in m:
		return "festival"
	if "trade route" in m or "arrived with" in m:
		return "trade"
	if " is now the village" in m or "hired" in m:
		return "job"
	return ""


## Record something worth remembering.
static func add(sim: LifeSim, kind: String, text: String) -> void:
	if not KINDS.has(kind):
		kind = "growth"
	sim.chronicle.append({"day": sim.day(), "kind": kind, "text": text})
	while sim.chronicle.size() > MAX_ENTRIES:
		sim.chronicle.pop_front()


static func entries(sim: LifeSim, kind: String = "", year: int = 0) -> Array:
	var out: Array = []
	for e in sim.chronicle:
		if (kind == "" or str(e.kind) == kind) and (year <= 0 or year_of(int(e.day)) == year):
			out.append(e)
	return out


static func years(sim: LifeSim) -> Array:
	var seen := {}
	for e in sim.chronicle:
		seen[year_of(int(e.day))] = true
	seen[year_of(sim.day())] = true
	var out: Array = seen.keys()
	out.sort()
	return out


static func count_of(sim: LifeSim, kind: String, year: int) -> int:
	return entries(sim, kind, year).size()


## Facts about one year, for the summary and for the AI that writes the story.
static func facts(sim: LifeSim, year: int) -> Dictionary:
	var list: Array = []
	for e in entries(sim, "", year):
		list.append("Day %d (%s): %s" % [int(e.day), season_of(int(e.day)), str(e.text)])
	return {
		"year": year, "village": {"stage": sim.stage_name(), "population": sim.residents.size(), "coins": sim.money, "buildings": sim.buildings.size()},
		"counts": {"births": count_of(sim, "birth", year), "weddings": count_of(sim, "wedding", year), "farewells": count_of(sim, "death", year), "dreams": count_of(sim, "dream", year), "festivals": count_of(sim, "festival", year), "dangers": count_of(sim, "monsters", year)},
		"events": list.slice(0, 40),
	}


## A plain-language account of a year from the facts alone.
static func story_offline(sim: LifeSim, year: int) -> String:
	var f := facts(sim, year)
	var counts: Dictionary = f.counts
	var parts: Array = []
	parts.append("Year %d in Willowbrook: a %s of %d people." % [year, str(f.village.stage).to_lower(), int(f.village.population)])
	var happy: Array = []
	if int(counts.births) > 0:
		happy.append("%d child%s born" % [int(counts.births), "" if int(counts.births) == 1 else "ren were"])
	if int(counts.weddings) > 0:
		happy.append("%d wedding%s" % [int(counts.weddings), "" if int(counts.weddings) == 1 else "s"])
	if int(counts.dreams) > 0:
		happy.append("%d dream%s come true" % [int(counts.dreams), "" if int(counts.dreams) == 1 else "s"])
	if int(counts.festivals) > 0:
		happy.append("%d festival%s" % [int(counts.festivals), "" if int(counts.festivals) == 1 else "s"])
	if not happy.is_empty():
		parts.append("There was much to celebrate: " + ", ".join(happy) + ".")
	var hard: Array = []
	if int(counts.dangers) > 0:
		hard.append("monsters threatened the village %d time%s" % [int(counts.dangers), "" if int(counts.dangers) == 1 else "s"])
	if int(counts.farewells) > 0:
		hard.append("%d beloved neighbour%s passed away" % [int(counts.farewells), "" if int(counts.farewells) == 1 else "s"])
	if not hard.is_empty():
		parts.append("It was not all easy: " + " and ".join(hard) + ".")
	var growth := entries(sim, "growth", year)
	if not growth.is_empty():
		parts.append("The village grew: " + str(growth.back().text))
	var highlights := entries(sim, "", year)
	highlights = highlights.filter(func(e: Dictionary) -> bool: return str(e.kind) in ["wedding", "birth", "dream", "death", "festival"])
	for e in highlights.slice(0, 3):
		parts.append("On day %d: %s." % [int(e.day), str(e.text).trim_suffix(".")])
	if parts.size() <= 1:
		parts.append("It was a quiet year of ordinary days: planting, building and getting to know one another.")
	return " ".join(parts)
