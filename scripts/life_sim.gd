class_name LifeSim
extends RefCounted
## Authoritative simulation: residents, the city they build, and every effect. The AI (and the player)
## only propose; this class validates and applies. Space lives in `map` (a CityMap, 1 tile = 4 world
## units). Resident positions are in tile units.

const NEEDS := ["hunger", "energy", "hygiene", "social", "fun", "health"]
const ACTIONS := ["eat", "sleep", "wash", "socialize", "play", "work", "study", "farm", "gather", "cook", "exercise", "rest", "chop", "mine", "water", "guard", "repair", "treat"]
## Outdoor jobs: the resident walks to a real tree, rock or shore, works with a tool, and carries the result home.
const JOB_ACTIONS := ["chop", "mine", "water"]
const JOB_WORK := {"chop": 40.0, "mine": 50.0, "water": 22.0}
const REGROW_DAYS := {"chop": 9, "mine": 14}
const ROCK_HITS := 3
const SITE_RADIUS := 26
## Which building kinds serve each action, best first. Residents use the nearest one.
const ACTION_KINDS := {
	"eat": ["market", "home"], "sleep": ["home"], "wash": ["bathhouse", "home"], "socialize": ["plaza", "park"],
	"play": ["park", "plaza"], "work": ["workshop", "office", "market"], "study": ["library"], "farm": ["farm"],
	"gather": ["farm", "park", "plaza"], "cook": ["home"], "exercise": ["park", "plaza"], "rest": ["home"], "treat": ["clinic"],
}
## Actions that use the resident's own home.
const OWN_HOME_ACTIONS := ["sleep", "rest", "cook"]
## What can be done at each kind of building (used by the click-a-building menu).
const KIND_ACTIONS := {
	"home": ["sleep", "cook", "rest"], "market": ["eat"], "workshop": ["work"], "office": ["work"], "library": ["study"],
	"bathhouse": ["wash"], "farm": ["farm", "gather"], "park": ["play", "exercise", "gather"], "plaza": ["socialize"], "clinic": ["treat"], "watchtower": ["guard"],
}
const DURATIONS := {"treat": 45.0, "repair": 40.0, "chop": 40.0, "mine": 50.0, "water": 22.0, "sleep": 180.0, "work": 90.0, "study": 50.0, "farm": 45.0, "gather": 35.0, "cook": 30.0}
## Actions that happen inside a building: the resident goes in and a progress ring shows on the roof.
const INDOOR_ACTIONS := ["eat", "sleep", "wash", "work", "study", "cook", "rest", "treat"]
const MAX_QUEUE := 4
const ACTION_VERBS := {"eat": "Eat", "sleep": "Sleep", "wash": "Wash up", "socialize": "Socialize", "play": "Play", "work": "Work", "study": "Study", "farm": "Farm", "gather": "Gather", "cook": "Cook", "exercise": "Exercise", "rest": "Rest", "chop": "Chop wood", "mine": "Mine stone", "water": "Fetch water", "guard": "Stand guard", "repair": "Repair", "treat": "See the doctor"}
const TRAIT_PREFERENCE := {
	"Curious gardener": "farm", "Outgoing cook": "cook", "Ambitious maker": "work", "Creative bookworm": "study",
	"Quiet dreamer": "rest", "Cheerful helper": "socialize", "Practical builder": "work", "Gentle healer": "rest",
	"Restless explorer": "exercise", "Thoughtful planner": "study", "Playful joker": "play", "Careful saver": "gather",
}
const SAVE_VERSION := 3
const TRAVEL_PER_MINUTE := 0.1
const POINT_LIMIT := 5000.0

var map := CityMap.new()
var buildings: Array = []
var next_building_id := 1
var residents: Array = []
var minutes := 420.0
var money := 400
var food := 16
var wood := 14  # building materials (timber)
var stone := 4  # building materials (quarried)
## Trees felled and rocks mined out, by tile: {day, hits}. They grow back after a while.
var depleted: Dictionary = {}
var reserved: Dictionary = {}  # resource tile -> resident index working it. Not saved.
var _site_cache: Dictionary = {}
var _site_sig := ""
## Monsters (see Survival). Transient: not saved.
var mobs: Array = []
var mob_serial := 0
var threat := 0
var spawn_clock := 0.0
var last_wave_day := 0
var kills := 0
var animal_serial := 0
var item_serial := 0
## A travelling merchant in town ({} otherwise), the level of the village's trade routes, crops the village has seeds
## for, and whether it owns steel tools.
var caravan: Dictionary = {}
## The village's written history ({day, kind, text}), kept in the save.
var chronicle: Array = []
## Weapons waiting in the armory (kind -> count), the weapon the chief holds, and the rival town's state ({} until day 1).
var armory: Dictionary = {}
var chief_weapon := ""
## The chief's fighting state (health, stamina, timers); see Combat.
var fighter: Dictionary = {}
var rival: Dictionary = {}
## The story of each finished year ("1" -> text), and the year whose story still wants telling (0 if none).
var stories: Dictionary = {}
var story_due := 0
var routes := 0
var crops_unlocked: Array = ["wheat", "carrot", "corn", "pumpkin"]
var tools := false
## Today's festival ({} on ordinary days): name, kind, active, contest... Not saved.
var festival: Dictionary = {}
var medicine := 0
## Crops harvested and not yet eaten or sold, by crop (what the village can bring to market), and daily price history.
var harvested: Dictionary = {}
var price_history: Dictionary = {}
var downs := 0
var gates_override := ""
var gates_override_until := 0.0
var gates_state := ""
## Society (see scripts/systems): rumours in circulation, market prices, running world events, winter heating.
var rumors: Array = []
var rumor_serial := 0
var prices: Dictionary = Economy.init_prices()
var events: Array = []
var cold_homes := false
var epidemic := false
var meals := 4
var journal: Array = []
var weather := "Clear"
var goals: Dictionary = {"harvest": false, "friend": false, "skilled": false, "builder": false}
var last_day := 1
var rng := RandomNumberGenerator.new()
var stage_reached := 0
var last_arrival_day := 0
var auto_plan := true
var stage_floor := 0  # debug/testing: never report a stage below this
var decisions: Array = []  # recent planning decisions: {day, by, text, reason}
var chief_pos := Vector2(2.0, 4.0)  # where the village chief stands, in tile units
## Residents in the middle of a conversation stand still: resident index -> "speak" | "listen" | "speak_chief". Not saved.
var talking: Dictionary = {}
## Who each talking resident is facing (another resident index, or -1 for the chief). Not saved.
var talk_with: Dictionary = {}
## Residents trailing the chief (index -> true) and residents told to stay put (index -> true). Not saved.
var following: Dictionary = {}
var holding: Dictionary = {}
## When true, resident-to-resident interactions emit a "conversation" event for the director to stage,
## instead of the short canned bubbles.
var scripted_dialogue := false
## When true, residents bring decisions to the chief instead of the council acting alone.
var ask_chief := false
## The advice request in progress ({} when none): kind, topic, resident, question, options, state, asked_at. Not saved.
var advice: Dictionary = {}
const ADVICE_INTERVAL := 420.0
var _last_advice_end := -1000.0
var _advice_hour := -1
var _advice_serial := 0
var fx: Array = []  # transient presentation events (speech, emotes), drained by the UI
var notices: Array = []  # short messages for the UI to toast


func _init() -> void:
	rng.seed = 713
	map.set_seed(1337)
	_setup_village()
	var starters := [["Pip", "Curious gardener", 0, 22], ["Mira", "Outgoing cook", 1, 25], ["Theo", "Ambitious maker", 2, 28], ["June", "Creative bookworm", 3, 31]]
	var homes := buildings_of("home")
	for i in range(starters.size()):
		var s: Array = starters[i]
		var home: Dictionary = homes[mini(i / 2, homes.size() - 1)]
		residents.append(_new_resident(str(s[0]), str(s[1]), int(s[2]), int(s[3]), int(home.id), Vector2(map.door_for(tile_of(home)))))
	for r in residents:
		_refresh_wants(r)
	log_event("Welcome to Willowbrook. Four lives, one little neighborhood.")


## The starting hamlet: two claimed districts, a plaza at the centre and eight buildings around it.
func _setup_village() -> void:
	map.claim_district(Vector2i(0, 0))
	map.claim_district(Vector2i(1, 0))
	var layout := [
		[Vector2i(1, 1), "home"], [Vector2i(2, 1), "market"], [Vector2i(3, 1), "home"],
		[Vector2i(1, 2), "library"], [Vector2i(3, 2), "bathhouse"],
		[Vector2i(1, 3), "home"], [Vector2i(2, 3), "workshop"], [Vector2i(3, 3), "farm"],
	]
	_add_building("plaza", Vector2i(2, 2), 1, true)
	for e in layout:
		_add_building(str(e[1]), e[0], 1, true)


func _new_resident(name_: String, trait_: String, look: int, age: int, home_id: int, pos: Vector2) -> Dictionary:
	var r := _new_resident_core(name_, trait_, look, age, home_id, pos)
	Psyche.extend(r, rng)
	return r


func _new_resident_core(name_: String, trait_: String, look: int, age: int, home_id: int, pos: Vector2) -> Dictionary:
	var needs := {}
	for n in NEEDS:
		needs[n] = float(rng.randi_range(65, 95))
	return {"name": name_, "trait": trait_, "age": age, "look": look, "needs": needs, "skills": {"craft": 0.0, "cooking": 0.0, "gardening": 0.0, "knowledge": 0.0, "fitness": 0.0}, "relations": {}, "pos": [pos.x, pos.y], "route": [], "action": "rest", "remaining": 0.0, "target": "Home", "target_id": -1, "home": home_id, "thought": "A new day in Willowbrook.", "say": "", "memory": [], "career": 1, "earned": 0, "completed": 0, "queue": [], "bond": 0.0, "points": 0, "wants": [], "cooldowns": {}, "counts": {}, "commanded": false, "job": {}, "carry": ""}


func day() -> int:
	return int(minutes / 1440.0) + 1


func season() -> String:
	return ["Spring", "Summer", "Autumn", "Winter"][int((day() - 1) / 7) % 4]


func clock_text() -> String:
	return "%02d:%02d" % [int(minutes) % 1440 / 60, int(minutes) % 60]


func mood(r: Dictionary) -> float:
	var total := 0.0
	for n in NEEDS:
		total += float(r.needs[n])
	return total / NEEDS.size()


func average_mood() -> float:
	if residents.is_empty():
		return 0.0
	var total := 0.0
	for r in residents:
		total += mood(r)
	return total / residents.size()


# --- time ---------------------------------------------------------------------------------------

func tick(dm: float) -> void:
	if dm <= 0:
		return
	minutes += dm
	if day() != last_day:
		last_day = day()
		_new_day()
	for b in buildings:
		if b.kind == "farm" and int(b.level) >= 1:
			b.growth = minf(100.0, float(b.get("growth", 0.0)) + dm * Farming.rate(b, season(), weather))
	var park_levels := _levels("park")
	for r in residents:
		var n: Dictionary = r.needs
		for key in ["hunger", "energy", "hygiene", "social", "fun"]:
			var rate: float = {"hunger": 0.045, "energy": 0.035, "hygiene": 0.025, "social": 0.020, "fun": 0.022}[key]
			if key == "fun": rate *= maxf(0.6, 1.0 - park_levels * 0.03)
			n[key] = clampf(float(n[key]) - rate * Psyche.decay_mult(r, key) * dm, 0, 100)
		n.health = clampf(float(n.health) + (-0.12 if n.hunger < 8 or n.energy < 5 else 0.015) * dm, 0, 100)
		var index := residents.find(r)
		Psyche.tick(self, r, index, dm)
		if float(r.get("down_until", 0.0)) > minutes:
			r.route = []
			continue
		Survival.resident_fight(self, index, dm)
		if talking.has(index):
			continue
		if holding.has(index):
			r.route = []
			continue
		if not (r.get("job", {}) as Dictionary).is_empty():
			_job_step(r, index, dm)
			continue
		if following.has(index):
			_follow_step(r, index, dm)
		elif float(r.remaining) <= 0:
			_begin_next(index)
		var pos := Vector2(float(r.pos[0]), float(r.pos[1]))
		var travel := dm * TRAVEL_PER_MINUTE * Health.speed(r)
		while not r.route.is_empty() and travel > 0:
			var waypoint := Vector2(r.route[0][0], r.route[0][1])
			var distance := pos.distance_to(waypoint)
			pos = pos.move_toward(waypoint, travel)
			travel -= distance
			if pos.distance_to(waypoint) < 0.01:
				r.route.pop_front()
		r.pos = [pos.x, pos.y]
		if r.route.is_empty():
			r.remaining = maxf(0, float(r.remaining) - dm)
			if r.action == "sleep":
				var home := building_by_id(int(r.target_id))
				n.energy = minf(100, n.energy + dm * (0.38 + (int(home.level) if not home.is_empty() else 0) * 0.04) * Ownership.rest_mult(self, r))
			if float(r.remaining) <= 0:
				finish_action(r)
	Health.tick(self, dm)
	Festivals.tick(self, dm)
	Walls.policy(self)
	Survival.tick(self, dm)
	_tick_advice(dm)
	_check_goals()


func _new_day() -> void:
	_regrow()
	weather = ["Clear", "Cloudy", "Rain"][rng.randi_range(0, 2)]
	var upkeep := buildings.size() * 3 + map.claimed.size() * 14 + residents.size() * 2
	var taxes := 0
	for r in residents:
		var home := building_by_id(int(r.home))
		taxes += 1 + (int(home.level) if not home.is_empty() else 0)
	for b in buildings:
		if b.kind == "market" and int(b.level) >= 1:
			taxes += 2 * int(b.level)
	money += taxes
	var paid := mini(money, upkeep)
	money -= paid
	log_event("Day %d: %s skies. Taxes %d, upkeep %d coins%s." % [day(), weather, taxes, paid, " (shortfall affects morale)" if paid < upkeep else ""])
	for r in residents:
		if paid < upkeep:
			r.needs.fun = maxf(0, r.needs.fun - 15)
	Lifecycle.daily(self)
	Rumors.daily(self)
	Health.daily(self)
	Economy.daily(self)
	Farming.daily(self)
	Ownership.daily(self)
	Jobs.daily(self)
	Festivals.daily(self)
	Quests.daily(self)
	Caravans.daily(self)
	Chronicle.daily(self)
	Rival.daily(self)
	_maybe_immigrate()
	if auto_plan:
		CityPlanner.meeting(self)
		Farming.council(self)
	_check_stage()


# --- choosing and starting actions -----------------------------------------------------------------

func has_target(action: String) -> bool:
	if action == "guard":
		return true
	if action == "repair":
		return materials() >= Economy.REPAIR_COST and not Economy.worst_building(self, 85.0).is_empty()
	if action in JOB_ACTIONS:
		var probed := 0
		for t in _sites(action):
			if depleted.has(t):
				continue
			probed += 1
			if probed > 40:
				break
			if Walls.accessible(self, Vector2(_work_spot(t)), Vector2(t)):
				return true
		return false
	for kind in ACTION_KINDS.get(action, []):
		if _count(kind) > 0:
			return true
	return false


func choose_action(r: Dictionary) -> String:
	var n: Dictionary = r.needs
	if float(r.get("break_until", 0.0)) > minutes:
		return "rest"
	if Health.is_ill(self, r):
		if has_target("treat") and rng.randf() < 0.9:
			return "treat"
		if rng.randf() < 0.75:
			return "rest"
	if n.energy < 25 or (int(minutes) % 1440 > 1320 and n.energy < 80):
		return "sleep"
	if n.hunger < 45:
		return "eat" if food > 0 or meals > 0 else "gather"
	if n.hygiene < 40:
		return "wash"
	if n.social < 40:
		return "socialize"
	if n.fun < 35:
		return "play"
	if n.health < 45:
		return "rest"
	var job_action := Jobs.preferred_action(self, r)
	if job_action != "" and rng.randf() < 0.85 and has_target(job_action):
		return job_action
	if _farm_ready() and rng.randf() < 0.6:
		return "farm"
	if food + meals < maxi(6, residents.size()) and has_target("gather") and rng.randf() < 0.5:
		return "gather"
	if Lifecycle.is_child(r):
		var play: Array = ["play", "study", "socialize", "play"]
		return play[rng.randi_range(0, play.size() - 1)]
	if threat > 0 and Lifecycle.blocked(r, "guard") == "" and rng.randf() < 0.2 + float(r.skills.fitness) / 400.0:
		return "guard"
	if has_target("repair") and not Economy.worst_building(self, 55.0).is_empty() and rng.randf() < 0.35:
		return "repair"
	if materials() < 12 and rng.randf() < 0.5:
		var haul: Array = []
		for job in ["chop", "mine"]:
			if has_target(job) and Lifecycle.blocked(r, job) == "":
				haul.append(job)
		if not haul.is_empty():
			return haul[rng.randi_range(0, haul.size() - 1)]
	if has_target("water") and _thirsty_farm() and rng.randf() < 0.35:
		return "water"
	# Residents pitch in on construction when there is a project underway.
	if not active_project().is_empty() and rng.randf() < 0.45 and has_target("work"):
		return "work"
	var options: Array = []
	for a in ["work", "study", "farm", "cook", "exercise", "socialize", "play"]:
		if has_target(a) and not (a == "cook" and food < 3):
			options.append(a)
	var preference: String = TRAIT_PREFERENCE.get(r.trait, "play")
	if preference == "farm" and not _farm_ready():
		preference = "play"
	if rng.randf() < 0.3 and has_target(preference):
		return preference
	return options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else "rest"


## Total building materials: timber and quarried stone.
func materials() -> int:
	return wood + stone


## Pay for construction: timber first, then stone.
func spend_materials(amount: int) -> void:
	var from_wood := mini(wood, amount)
	wood -= from_wood
	stone = maxi(0, stone - (amount - from_wood))


func _thirsty_farm() -> bool:
	for b in buildings:
		if b.kind == "farm" and int(b.level) >= 1 and float(b.get("growth", 0.0)) < 60.0:
			return true
	return false


## True when any farm has a crop ready to harvest.
func _farm_ready() -> bool:
	if Farming.any_needs_tending(self):
		return true
	for b in buildings:
		if b.kind == "farm" and int(b.level) >= 1 and float(b.get("growth", 0.0)) >= 100.0:
			return true
	return false


## Where an action happens: {id, kind, tile, label}. Falls back to the plaza (or the town centre).
func _target_for(r: Dictionary, action: String) -> Dictionary:
	var here := Vector2i(roundi(r.pos[0]), roundi(r.pos[1]))
	if action == "repair":
		var worn := Economy.worst_building(self, 90.0)
		if not worn.is_empty():
			return _target_dict(worn)
	if action in OWN_HOME_ACTIONS:
		var own := building_by_id(int(r.home))
		if not own.is_empty() and int(own.level) >= 1:
			return _target_dict(own)
	var best := {}
	var best_d := 1 << 30
	var kinds: Array = ACTION_KINDS.get(action, ["plaza"])
	if action == "work" and Jobs.workplace_kind(r) != "":
		kinds = [Jobs.workplace_kind(r)] + kinds
	for rank in range(kinds.size()):
		for b in buildings:
			if int(b.level) < 1 or b.kind != kinds[rank]:
				continue
			var t := tile_of(b)
			var d := (absi(t.x - here.x) + absi(t.y - here.y)) + rank * 12
			if action == "farm" and float(b.get("growth", 0.0)) < 100.0 and not Farming.needs_tending(self, b):
				d += 30  # prefer a farm with a crop ready or animals to tend
			if d < best_d:
				best_d = d
				best = b
		if not best.is_empty() and rank == 0:
			break
	if best.is_empty():
		var plazas := buildings_of("plaza")
		if not plazas.is_empty():
			best = plazas[0]
	if best.is_empty():
		return {"id": -1, "kind": "plaza", "tile": map.nearest_walkable(Vector2i(2, 2)), "label": "Square"}
	return _target_dict(best)


func _target_dict(b: Dictionary) -> Dictionary:
	var t := tile_of(b)
	var destination := t if not Catalog.solid(str(b.kind)) else Vector2i(b.door[0], b.door[1])
	return {"id": int(b.id), "kind": str(b.kind), "tile": destination, "label": Catalog.label(str(b.kind))}


func start_action(index: int, action: String) -> bool:
	if index < 0 or index >= residents.size() or action not in ACTIONS:
		return false
	var r: Dictionary = residents[index]
	# Avoid interrupting sleep for nonessential AI suggestions.
	if r.action == "sleep" and r.needs.energy < 60 and r.remaining > 0:
		return false
	if action == "guard":
		return start_guard(index)
	if action in JOB_ACTIONS:
		return _start_job(index, action)
	var job_cancel: Dictionary = r.get("job", {})
	if not job_cancel.is_empty():
		_drop_job(r)
	var target := _target_for(r, action)
	r.action = action
	r.target = target.label
	r.target_id = int(target.id)
	r.remaining = float(DURATIONS.get(action, 25.0))
	_set_route(r, target.tile)
	return true


func _set_route(r: Dictionary, goal: Vector2i, allow_teleport: bool = true) -> void:
	var start := Vector2i(roundi(r.pos[0]), roundi(r.pos[1]))
	r.route = []
	if start == goal:
		return
	var path := map.find_path(start, goal)
	if path.is_empty():
		# Boxed in (for example a building went up beneath them): step to the goal.
		if allow_teleport:
			r.pos = [float(goal.x), float(goal.y)]
		return
	for waypoint in path:
		r.route.append([waypoint.x, waypoint.y])


func finish_action(r: Dictionary) -> void:
	var n: Dictionary = r.needs
	var result := ""
	var place := building_by_id(int(r.target_id))
	var lvl := int(round(float(place.level) * Economy.efficiency(place))) if not place.is_empty() else 0
	if not place.is_empty():
		place.visits = int(place.visits) + 1
		if str(r.action) in ["work", "study"] and Interiors.enterable(place):
			Ownership.claim_station(self, place, str(r.name))
	match str(r.action):
		"eat":
			if meals > 0:
				meals -= 1
				n.hunger = minf(100, n.hunger + 65 + (lvl * 4 if place.get("kind") == "market" else 0))
				n.fun = minf(100, n.fun + 8)
			elif food > 0:
				food -= 1
				n.hunger = minf(100, n.hunger + 38)
			else:
				result = "The pantry is empty. Time to gather food."
		"wash":
			n.hygiene = 100.0
			n.health = minf(100, n.health + (lvl * 3 if place.get("kind") == "bathhouse" else 0))
		"sleep": n.energy = minf(100, n.energy + 15 + lvl * 3)
		"rest":
			n.health = minf(100, n.health + 18)
			n.energy = minf(100, n.energy + 15)
		"play": n.fun = minf(100, n.fun + 40 + (lvl * 3 if place.get("kind") == "park" else 0))
		"exercise":
			n.health = minf(100, n.health + 12)
			n.fun = minf(100, n.fun + 15)
			r.skills.fitness += 8
		"study":
			r.skills.knowledge += float(12 + (lvl * 3 if place.get("kind") == "library" else 0)) * Psyche.skill_mult(r, "knowledge")
			n.fun = minf(100, n.fun + 18)
		"work":
			var wage := int(round(float(5 + int(r.career) * 2 + lvl * 2 + (6 if place.get("kind") == "office" else 0)) * Psyche.work_mult(r)))
			money += wage
			r.earned += wage
			r.skills.craft += 10.0 * Psyche.skill_mult(r, "craft")
			var rank := mini(5, 1 + int(r.skills.craft / 60))
			if rank > int(r.career):
				r.career = rank
				log_event("%s earned a promotion to level %d!" % [r.name, rank])
			if place.get("kind") == "workshop":
				wood += 1
			var profession := Jobs.title_of(r)
			if profession == "doctor" and place.get("kind") == "clinic":
				medicine += 1 + lvl
				result = "Prepared medicine. "
			elif profession == "shopkeeper" and place.get("kind") == "market":
				money += 3 + lvl * 2
				result = "Served the shop. "
			elif profession == "librarian" and place.get("kind") == "library":
				r.skills.knowledge += 6.0
				place.visits = int(place.visits) + 2
			elif profession == "builder" and place.get("kind") == "workshop":
				add_progress(8.0)
			result += "Earned %d coins." % wage
			var worked_on := add_progress(20.0 + float(r.skills.craft) / 12.0)
			if worked_on != "":
				result += " " + worked_on
		"gather":
			food += 2
			wood += 2
			r.skills.gardening += 3
			result = "Gathered 2 produce and 2 materials."
		"farm":
			r.skills.gardening += 8.0 * Psyche.skill_mult(r, "gardening")
			if not place.is_empty() and place.kind == "farm" and bool(place.get("pests", false)):
				place.pests = false
				result = "Cleared the pests from the field."
			if not place.is_empty() and place.kind == "farm" and float(place.get("growth", 0.0)) >= 100.0:
				var quantity := int(round(float(6 + int(r.skills.gardening / 30) + lvl * 5) * Economy.yield_factor(place) * float(Farming.CROPS[Farming.crop_of(place)].yield) * (1.25 if Jobs.title_of(r) == "farmer" else 1.0)))
				food += quantity
				harvested[Farming.crop_of(place)] = int(harvested.get(Farming.crop_of(place), 0)) + quantity
				place.soil = maxf(25.0, float(place.get("soil", 100.0)) - 15.0)
				place.growth = 0.0
				goals.harvest = true
				result = "Harvested %d %s." % [quantity, str(Farming.CROPS[Farming.crop_of(place)].label).to_lower()]
			if not place.is_empty() and place.kind == "farm":
				var tended := Farming.tend(self, place)
				if tended != "":
					result = (result + " " + tended).strip_edges()
		"treat":
			if Health.is_ill(self, r) or bool(r.injured) or float(n.health) < 90.0:
				var attended := false
				for other in residents:
					if Jobs.title_of(other) == "doctor" and int(other.get("employer", -1)) == int(place.get("id", -2)) and not Health.is_ill(self, other):
						attended = true
				var drug := medicine > 0
				if drug:
					medicine -= 1
				if Health.is_ill(self, r):
					if drug or attended:
						r.ill_until = 0.0
						r.ill_kind = ""
						r.immune_until = minutes + 4.0 * 1440.0
					else:
						r.ill_until = minutes + (float(r.ill_until) - minutes) * 0.5
				if drug or attended:
					r.injured = false
				n.health = minf(100.0, float(n.health) + (12.0 if not (drug or attended) else 25.0) + lvl * 8.0 + (10.0 if drug else 0.0))
				r.stress = maxf(0.0, float(r.stress) - 6.0)
				result = "Was treated at the clinic%s." % (" with medicine and a doctor's care" if drug and attended else (" with medicine" if drug else (" by the doctor" if attended else " (no doctor or medicine, so only rest)")))
			else:
				n.health = minf(100.0, float(n.health) + 6.0)
		"repair":
			if not place.is_empty():
				result = Economy.repair(self, place, float(r.skills.craft))
				r.skills.craft += 4.0 * Psyche.skill_mult(r, "craft")
		"cook":
			if food >= 3:
				food -= 3
				meals += 2
				r.skills.cooking += 10
				result = "Prepared 2 nourishing meals."
			else:
				result = "Cooking needs 3 produce."
		"socialize":
			var me := residents.find(r)
			var other := _nearest_resident(me, 1.6)
			if other >= 0:
				var kind := _pick_social_kind(r, residents[other])
				if kind == "":
					n.social = minf(100, n.social + 6)
					result = "Enjoyed a quiet moment with %s." % residents[other].name
				else:
					result = str(resident_interact(me, other, kind).summary)
			elif residents.size() > 1:
				var invitee := (me + 1 + rng.randi() % (residents.size() - 1)) % residents.size()
				start_action(invitee, "socialize")
				n.social = minf(100, n.social + 8)
				result = "Invited %s to the square." % residents[invitee].name
	r.completed += 1
	r.counts[r.action] = int(r.counts.get(r.action, 0)) + 1
	_check_wants(r)
	if result != "":
		remember(r, result)
		log_event("%s: %s" % [r.name, result])


# --- outdoor jobs: chop, mine, fetch water --------------------------------------------------------------

func is_depleted(t: Vector2i) -> bool:
	return depleted.has(t)


## Nearby resource tiles for a job, nearest to the village first: [{tile: Vector2i}]. Cached until land or season changes.
func _sites(action: String) -> Array:
	var sig := "%d:%d" % [map.claimed.size(), day() / 3]
	if sig != _site_sig:
		_site_sig = sig
		_site_cache.clear()
	if _site_cache.has(action):
		return _site_cache[action]
	var rect := map.bounds()
	var centre := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2) * CityMap.DISTRICT
	var found: Array = []
	for dx in range(-SITE_RADIUS - 8, SITE_RADIUS + 9):
		for dy in range(-SITE_RADIUS - 8, SITE_RADIUS + 9):
			var t := centre + Vector2i(dx, dy)
			if map.is_claimed_tile(t) or map.is_road(t):
				continue
			var ok := false
			match action:
				"chop": ok = map.has_trees(t)
				"mine": ok = map.has_rock(t)
				"water": ok = map.is_water(t)
			if ok:
				found.append(t)
	var edge := _village_edge_tiles()
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _edge_distance(a, edge) < _edge_distance(b, edge))
	var out: Array = found.slice(0, 160)
	_site_cache[action] = out
	return out


func _village_edge_tiles() -> Array:
	var out: Array = []
	for d in map.claimed:
		out.append(Vector2i(d.x * CityMap.DISTRICT + 2, d.y * CityMap.DISTRICT + 2))
	return out


func _edge_distance(t: Vector2i, edge: Array) -> int:
	var best := 1 << 30
	for e in edge:
		var d := absi(t.x - e.x) + absi(t.y - e.y)
		if d < best:
			best = d
	return best


func _find_site(r: Dictionary, action: String) -> Dictionary:
	var here := Vector2(float(r.pos[0]), float(r.pos[1]))
	var best := {}
	var best_d := 1.0e9
	var tried := 0
	for t in _sites(action):
		if depleted.has(t) or reserved.has(t):
			continue
		tried += 1
		if tried > 60:
			break
		if not Walls.accessible(self, Vector2(_work_spot(t)), Vector2(t)):
			continue
		var d := here.distance_to(Vector2(t))
		if d < best_d:
			best_d = d
			best = {"tile": t}
	return best


## The village tile nearest to a resource outside it: where the worker leaves the streets.
func _work_spot(t: Vector2i) -> Vector2i:
	for ring in range(1, 14):
		var best := Vector2i.ZERO
		var best_d := 1 << 30
		var found := false
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := t + Vector2i(dx, dy)
				if map.walkable(c) and map.nav_rect.has_point(c) and not map.nav.is_point_solid(c):
					var d := dx * dx + dy * dy
					if d < best_d:
						best_d = d
						best = c
						found = true
		if found:
			return best
	return map.nearest_walkable(t)


func _depot_for(r: Dictionary, action: String) -> Vector2i:
	var here := Vector2i(roundi(r.pos[0]), roundi(r.pos[1]))
	var kinds: Array = ["farm", "plaza"] if action == "water" else ["workshop", "market", "plaza"]
	for kind in kinds:
		var best := {}
		var best_d := 1 << 30
		for b in buildings:
			if str(b.kind) != kind or int(b.level) < 1:
				continue
			var t := tile_of(b)
			var d := absi(t.x - here.x) + absi(t.y - here.y)
			if d < best_d:
				best_d = d
				best = b
		if not best.is_empty():
			return _target_dict(best).tile
	return map.nearest_walkable(Vector2i(2, 2))


func _start_job(index: int, action: String) -> bool:
	var r: Dictionary = residents[index]
	var site := _find_site(r, action)
	if site.is_empty():
		return false
	_drop_job(r)
	var res: Vector2i = site.tile
	# Walk to the closest walkable village tile, then cross the last stretch of open ground on foot.
	var spot := _work_spot(res)
	var toward := Vector2(res - spot)
	var stand := Vector2(res) - (toward.normalized() * 1.05 if toward.length() > 1.05 else Vector2.ZERO)
	var pts: Array = []
	if not Walls.crossing(self, Vector2(spot), stand).is_empty():
		var gate := Walls.nearest_gate(self, Vector2(spot))
		if gate.is_empty():
			return false
		var gp := Walls.gate_points(gate)
		spot = map.nearest_walkable(Vector2i(roundi(gp.inner.x), roundi(gp.inner.y)))
		pts = [[gp.inner.x, gp.inner.y], [gp.outer.x, gp.outer.y]]
	pts.append([stand.x, stand.y])
	reserved[res] = index
	r.action = action
	r.target = {"chop": "the forest", "mine": "the rocks", "water": "the shore"}[action]
	r.target_id = -1
	r.remaining = float(JOB_WORK[action])
	r.carry = ""
	r.job = {"kind": action, "res": [res.x, res.y], "spot": [spot.x, spot.y], "stand": [stand.x, stand.y], "pts": pts, "i": 0, "phase": "to_spot", "left": float(JOB_WORK[action]), "depot": []}
	_set_route(r, spot)
	return true


## Give up an unfinished job: free the resource and drop whatever is carried.
func _drop_job(r: Dictionary) -> void:
	var job: Dictionary = r.get("job", {})
	if job.is_empty():
		return
	r.job = {}
	r.carry = ""
	if str(job.kind) == "guard":
		var here := Vector2i(roundi(r.pos[0]), roundi(r.pos[1]))
		if not map.walkable(here):
			var back := map.nearest_walkable(here)
			r.pos = [float(back.x), float(back.y)]
		return
	var res := Vector2i(int(job.res[0]), int(job.res[1]))
	reserved.erase(res)
	var spot := Vector2i(int(job.spot[0]), int(job.spot[1]))
	if map.walkable(Vector2i(roundi(r.pos[0]), roundi(r.pos[1]))) == false:
		r.pos = [float(spot.x), float(spot.y)]


## Stand watch at the plaza; charge any monster that comes within reach of the village.
func start_guard(index: int) -> bool:
	var r: Dictionary = residents[index]
	_drop_job(r)
	r.action = "guard"
	r.target = "the village"
	r.target_id = -1
	r.carry = ""
	r.remaining = Survival.GUARD_SHIFT
	r.job = {"kind": "guard", "phase": "post", "left": Survival.GUARD_SHIFT, "prey": -1}
	_set_route(r, _guard_post(r))
	return true


func _guard_post(r: Dictionary = {}) -> Vector2i:
	# A gatekeeper stands just inside their own gate.
	if not r.is_empty() and Jobs.title_of(r) == "gatekeeper":
		var gate := building_by_id(int(r.get("employer", -1)))
		if not gate.is_empty() and Walls.is_wall(gate) and gate.has("edge"):
			var gp := Walls.gate_points(gate)
			return map.nearest_walkable(Vector2i(roundi(gp.inner.x), roundi(gp.inner.y)))
	var plazas := buildings_of("plaza")
	if not plazas.is_empty():
		return map.nearest_walkable(tile_of(plazas[0]))
	return map.nearest_walkable(Vector2i(2, 2))


func _mob_by_id(id: int) -> Dictionary:
	for m in mobs:
		if int(m.id) == id:
			return m
	return {}


func _guard_step(r: Dictionary, index: int, dm: float) -> void:
	var job: Dictionary = r.job
	var pos := Vector2(float(r.pos[0]), float(r.pos[1]))
	job.left = float(job.left) - dm
	r.remaining = maxf(1.0, float(job.left))
	if float(job.left) <= 0.0 and mobs.is_empty():
		r.job = {}
		r.remaining = 0.0
		r.commanded = false
		say(index, "My shift is over. All quiet.")
		return
	var prey := _mob_by_id(int(job.prey))
	if prey.is_empty():
		job.prey = -1
		var best_d := 16.0
		for m in mobs:
			var mp := Vector2(float(m.pos[0]), float(m.pos[1]))
			var d := pos.distance_to(mp)
			if d < best_d and Walls.crossing(self, pos, mp).is_empty():
				best_d = d
				prey = m
		if not prey.is_empty():
			job.prey = int(prey.id)
			job.phase = "hunt"
			if rng.randf() < 0.5:
				say(index, Social.pick(["Monster! I'll deal with it.", "Stay behind me!", "Here they come."], rng))
	if prey.is_empty():
		job.phase = "post"
		var tile := Vector2i(roundi(pos.x), roundi(pos.y))
		if not map.walkable(tile):
			_walk_straight(r, Vector2(map.nearest_walkable(tile)), dm)
		elif r.route.is_empty():
			var post := _guard_post(r)
			if pos.distance_to(Vector2(post)) > (1.2 if Jobs.title_of(r) == "gatekeeper" else 2.0):
				_set_route(r, post)
		else:
			_walk_route(r, dm)
		return
	var goal := Vector2(float(prey.pos[0]), float(prey.pos[1]))
	if pos.distance_to(goal) > maxf(0.95, Weapons.reach_of(r) - 0.2):
		r.route = []
		_walk_straight(r, goal, dm * 1.4)


func flee(index: int, long_stay: bool = false) -> void:
	var r: Dictionary = residents[index]
	release(index)
	r.queue.clear()
	if start_action(index, "rest"):
		r.commanded = true
		r.remaining = 120.0 if long_stay else 60.0
		r.fleeing_until = minutes + (150.0 if long_stay else 80.0)
		if rng.randf() < 0.6:
			say(index, Social.pick(["Run! Monsters!", "Everyone inside!", "Get to safety!"], rng))


func _walk_route(r: Dictionary, dm: float) -> bool:
	var pos := Vector2(float(r.pos[0]), float(r.pos[1]))
	var travel := dm * TRAVEL_PER_MINUTE * Health.speed(r)
	while not r.route.is_empty() and travel > 0:
		var waypoint := Vector2(r.route[0][0], r.route[0][1])
		var distance := pos.distance_to(waypoint)
		var moved := pos.move_toward(waypoint, travel)
		if not Walls.blocks(self, pos, moved).is_empty():
			break
		pos = moved
		travel -= distance
		if pos.distance_to(waypoint) < 0.01:
			r.route.pop_front()
	r.pos = [pos.x, pos.y]
	return r.route.is_empty()


func _walk_straight(r: Dictionary, goal: Vector2, dm: float) -> bool:
	var pos := Vector2(float(r.pos[0]), float(r.pos[1]))
	var moved := pos.move_toward(goal, dm * TRAVEL_PER_MINUTE * Health.speed(r))
	if Walls.blocks(self, pos, moved).is_empty():
		pos = moved
	r.pos = [pos.x, pos.y]
	return pos.distance_to(goal) < 0.02


func _job_step(r: Dictionary, index: int, dm: float) -> void:
	var job: Dictionary = r.job
	var kind: String = job.kind
	var n: Dictionary = r.needs
	if kind == "guard":
		_guard_step(r, index, dm)
		return
	# Starving or exhausted workers drop what they are doing.
	if float(n.hunger) < 6.0 or float(n.energy) < 4.0:
		_drop_job(r)
		r.remaining = 0.0
		r.commanded = false
		return
	match str(job.phase):
		"to_spot":
			r.remaining = float(JOB_WORK[kind])
			if _walk_route(r, dm):
				job.phase = "approach"
		"approach":
			var pts: Array = job.pts
			var step := mini(int(job.i), pts.size() - 1)
			if _walk_straight(r, Vector2(pts[step][0], pts[step][1]), dm):
				job.i = int(job.i) + 1
				if int(job.i) >= pts.size():
					job.phase = "work"
					job.i = 0
		"work":
			job.left = float(job.left) - dm
			r.remaining = maxf(1.0, float(job.left))
			if float(job.left) <= 0.0:
				_job_harvest(r, index)
				job.phase = "retreat"
		"retreat":
			var back: Array = job.pts.duplicate()
			back.reverse()
			var goals: Array = back.slice(1)
			goals.append([job.spot[0], job.spot[1]])
			var leg := mini(int(job.i), goals.size() - 1)
			if _walk_straight(r, Vector2(goals[leg][0], goals[leg][1]), dm):
				job.i = int(job.i) + 1
			if int(job.i) >= goals.size():
				job.i = 0
				var depot := _depot_for(r, kind)
				job.depot = [depot.x, depot.y]
				_set_route(r, depot)
				job.phase = "haul"
		"haul":
			r.remaining = 5.0
			if _walk_route(r, dm):
				_job_deliver(r, index)


func _job_harvest(r: Dictionary, index: int) -> void:
	var job: Dictionary = r.job
	var res := Vector2i(int(job.res[0]), int(job.res[1]))
	match str(job.kind):
		"chop":
			depleted[res] = {"day": day(), "hits": 1}
			push_fx({"type": "felled", "tile": [res.x, res.y], "who": index})
			r.carry = "log"
		"mine":
			var hits := int(_rock_hits.get(res, 0)) + 1
			if hits >= ROCK_HITS:
				depleted[res] = {"day": day(), "hits": hits}
				_rock_hits.erase(res)
				push_fx({"type": "rock_gone", "tile": [res.x, res.y], "who": index})
			else:
				_rock_hits[res] = hits
				push_fx({"type": "rock_chipped", "tile": [res.x, res.y], "who": index, "hits": hits})
			r.carry = "stone"
		"water":
			r.carry = "bucket"
	reserved.erase(res)


var _rock_hits: Dictionary = {}


func _job_deliver(r: Dictionary, index: int) -> void:
	var job: Dictionary = r.job
	var kind: String = job.kind
	var result := ""
	var strong := 1.0 + float(r.skills.fitness) / 200.0
	match kind:
		"chop":
			var amount := int(round(3.0 * strong)) + (1 if Jobs.title_of(r) == "lumberjack" else 0) + (1 if tools else 0)
			wood += amount
			r.skills.fitness += 4
			result = "Chopped and hauled %d timber." % amount
		"mine":
			var amount2 := int(round(3.0 * strong)) + (1 if Jobs.title_of(r) == "miner" else 0) + (1 if tools else 0)
			stone += amount2
			r.skills.craft += 4
			result = "Quarried and hauled %d stone." % amount2
		"water":
			var watered := false
			var depot := Vector2i(int(job.depot[0]), int(job.depot[1]))
			for b in buildings:
				if b.kind == "farm" and int(b.level) >= 1 and tile_of(b).distance_to(Vector2(depot)) < 5.0:
					b.growth = minf(100.0, float(b.get("growth", 0.0)) + 30.0)
					watered = true
					break
			r.skills.gardening += 3
			result = "Watered the crops." if watered else "Fetched a bucket of water."
			if not watered:
				r.needs.fun = minf(100.0, float(r.needs.fun) + 4.0)
	r.job = {}
	r.carry = ""
	r.remaining = 0.0
	r.completed += 1
	r.counts[kind] = int(r.counts.get(kind, 0)) + 1
	push_fx({"type": "delivered", "who": index, "kind": kind})
	_check_wants(r)
	remember(r, result)
	log_event("%s: %s" % [r.name, result])


func _regrow() -> void:
	var back: Array = []
	for t in depleted:
		var entry: Dictionary = depleted[t]
		var limit := int(REGROW_DAYS["mine" if map.has_rock(t) else "chop"])
		if day() - int(entry.day) >= limit:
			back.append(t)
	for t in back:
		depleted.erase(t)
		_rock_hits.erase(t)
		push_fx({"type": "regrown", "tile": [t.x, t.y]})


func _depleted_list() -> Array:
	var out: Array = []
	for t in depleted:
		out.append([t.x, t.y, int(depleted[t].day), int(depleted[t].hits)])
	return out


func _load_depleted(list: Variant) -> void:
	depleted.clear()
	if list is Array:
		for e in list:
			if e is Array and e.size() >= 4:
				depleted[Vector2i(int(e[0]), int(e[1]))] = {"day": int(e[2]), "hits": int(e[3])}


# --- people come and go -------------------------------------------------------------------------------------

func index_of(name_: String) -> int:
	for i in range(residents.size()):
		if str(residents[i].name) == name_:
			return i
	return -1


## Remove a resident and re-number everything that refers to residents by index.
func remove_resident(index: int) -> void:
	if index < 0 or index >= residents.size():
		return
	var name_ := str(residents[index].name)
	residents.remove_at(index)
	var fix := func(old: Dictionary) -> Dictionary:
		var out := {}
		for k in old:
			var ik := int(k)
			if ik == index:
				continue
			out[ik - 1 if ik > index else ik] = old[k]
		return out
	talking = fix.call(talking)
	talk_with = fix.call(talk_with)
	following = fix.call(following)
	holding = fix.call(holding)
	for k in talk_with.keys():
		var partner := int(talk_with[k])
		if partner == index:
			talk_with[k] = -1
		elif partner > index:
			talk_with[k] = partner - 1
	for t in reserved.keys():
		var who := int(reserved[t])
		if who == index:
			reserved.erase(t)
		elif who > index:
			reserved[t] = who - 1
	if not advice.is_empty():
		var ar := int(advice.resident)
		if ar == index:
			advice = {}
		elif ar > index:
			advice.resident = ar - 1
	for m in mobs:
		m.target = -1
	push_fx({"type": "resident_removed", "index": index, "name": name_})


# --- buildings -------------------------------------------------------------------------------------

func tile_of(b: Dictionary) -> Vector2i:
	return Vector2i(int(b.tile[0]), int(b.tile[1]))


func building_by_id(id: int) -> Dictionary:
	for b in buildings:
		if int(b.id) == id:
			return b
	return {}


## Complete buildings of a kind (level >= 1).
func buildings_of(kind: String) -> Array:
	var out: Array = []
	for b in buildings:
		if b.kind == kind and int(b.level) >= 1:
			out.append(b)
	return out


func building_at_tile(t: Vector2i) -> Dictionary:
	var id := int(map.occupied.get(t, -1))
	return building_by_id(id) if id >= 0 else {}


func _count(kind: String) -> int:
	var c := 0
	for b in buildings:
		if b.kind == kind and int(b.level) >= 1:
			c += 1
	return c


func _levels(kind: String) -> int:
	var c := 0
	for b in buildings:
		if b.kind == kind:
			c += int(b.level)
	return c


func _add_building(kind: String, tile: Vector2i, level: int, complete: bool) -> Dictionary:
	var door := map.door_for(tile)
	var b := {"id": next_building_id, "kind": kind, "tile": [tile.x, tile.y], "level": level if complete else 0, "target": 0 if complete else level, "progress": 100.0 if complete else 0.0, "visits": 0, "variant": rng.randi() % 997, "door": [door.x, door.y], "growth": 0.0, "condition": 100.0, "soil": 100.0, "pests": false, "crop": "wheat", "animals": [], "produce": {"eggs": 0, "milk": 0, "wool": 0}, "hay": 0.0, "hungry": 0}
	next_building_id += 1
	buildings.append(b)
	map.set_building_tile(int(b.id), tile, Catalog.solid(kind))
	return b


func housing() -> int:
	var c := 0
	for b in buildings:
		if b.kind == "home":
			c += Catalog.capacity("home", int(b.level))
	return c


func population() -> int:
	return residents.size()


func occupants_of(id: int) -> int:
	var c := 0
	for r in residents:
		if int(r.home) == id:
			c += 1
	return c


func stage() -> int:
	return maxi(stage_floor, Catalog.stage_for_pop(residents.size()))


func stage_name() -> String:
	return Catalog.STAGES[stage()]


func stage_progress() -> float:
	var s := stage()
	if s >= Catalog.STAGES.size() - 1:
		return 1.0
	var low: int = Catalog.STAGE_POP[s]
	var high: int = Catalog.STAGE_POP[s + 1]
	return clampf(float(residents.size() - low) / float(high - low), 0.0, 1.0)


func _check_stage() -> void:
	var s := stage()
	if s > stage_reached:
		stage_reached = s
		log_event("Willowbrook has grown into a %s!" % Catalog.STAGES[s])
		notice("Willowbrook is now a %s!" % Catalog.STAGES[s])


## Why `kind` cannot be built on `tile` ("" means it can).
func build_blocker(kind: String, tile: Vector2i, level: int = 1) -> String:
	if not Catalog.KINDS.has(kind) or kind not in Catalog.BUILDABLE:
		return "Unknown building."
	if not map.is_claimed_tile(tile):
		return "That land is not part of the village yet."
	if not CityMap.is_lot(tile):
		return "Build on a lot, not on the road or green."
	if map.is_water(tile):
		return "That spot is underwater."
	if map.occupied.has(tile):
		return "That lot is taken."
	if Catalog.stage_needed(kind, level) > stage():
		return "Needs the village to reach %s." % Catalog.STAGES[Catalog.stage_needed(kind, level)]
	var c := Catalog.cost(kind, level)
	if money < int(c.coins) or materials() < int(c.mats):
		return "Needs %d coins and %d materials." % [c.coins, c.mats]
	for r in residents:
		if Vector2(r.pos[0], r.pos[1]).distance_to(Vector2(tile)) < 0.8:
			return "A resident is standing there."
	if chief_pos.distance_to(Vector2(tile)) < 1.4:
		return "You are standing there. Step aside first."
	return ""


func place_building(kind: String, tile: Vector2i) -> String:
	var why := build_blocker(kind, tile)
	if why != "":
		return why
	var c := Catalog.cost(kind, 1)
	money -= int(c.coins)
	spend_materials(int(c.mats))
	var b := _add_building(kind, tile, 1, false)
	goals.builder = true
	log_event("Construction started: %s at (%d, %d). Residents will build it on work shifts." % [Catalog.label(kind), tile.x, tile.y])
	notice("Building a %s" % Catalog.label(kind))
	return "Started the %s." % Catalog.label(kind)


func upgrade_blocker(id: int) -> String:
	var b := building_by_id(id)
	if b.is_empty():
		return "No such building."
	if int(b.target) > int(b.level) or int(b.level) < 1:
		return "Already under construction."
	var next := int(b.level) + 1
	if next > Catalog.max_level(str(b.kind)):
		return "Fully upgraded."
	if Catalog.stage_needed(str(b.kind), next) > stage():
		return "Needs the village to reach %s." % Catalog.STAGES[Catalog.stage_needed(str(b.kind), next)]
	if int(b.visits) < Catalog.UPGRADE_VISITS[int(b.level)] and not Walls.is_wall(b):
		return "Needs %d visits (has %d)." % [Catalog.UPGRADE_VISITS[int(b.level)], int(b.visits)]
	if bool(b.get("breached", false)):
		return "Repair the breach first."
	var c := Catalog.cost(str(b.kind), next)
	if money < int(c.coins) or materials() < int(c.mats):
		return "Needs %d coins and %d materials." % [c.coins, c.mats]
	return ""


func upgrade_building(id: int) -> String:
	var why := upgrade_blocker(id)
	if why != "":
		return why
	var b := building_by_id(id)
	var next := int(b.level) + 1
	var c := Catalog.cost(str(b.kind), next)
	money -= int(c.coins)
	spend_materials(int(c.mats))
	b.target = next
	b.progress = 0.0
	log_event("Upgrade started: %s to level %d." % [Catalog.label(str(b.kind)), next])
	notice("Upgrading the %s" % Catalog.label(str(b.kind)))
	return "Upgrade started."


func claim_cost(d: Vector2i) -> int:
	return 100 + 45 * map.claimed.size() + map.district_water(d) * 6


func claim_blocker(d: Vector2i) -> String:
	if map.claimed.has(d):
		return "Already part of the village."
	if not map.frontier().has(d):
		return "Only land next to the village can be claimed."
	if money < claim_cost(d):
		return "Needs %d coins." % claim_cost(d)
	return ""


## Claim a district: roads appear, its trees are felled for materials.
func claim_district(d: Vector2i) -> String:
	var why := claim_blocker(d)
	if why != "":
		return why
	money -= claim_cost(d)
	var trees := map.district_trees(d)
	wood += trees
	map.claim_district(d)
	Walls.remove_interior(self)
	log_event("The village expanded: a new district opened%s." % (" (%d materials from cleared trees)" % trees if trees > 0 else ""))
	notice("New land claimed")
	return "District claimed."


func apply_option(option: Dictionary, by: String = "Council") -> String:
	var result := ""
	match str(option.get("type", "")):
		"build":
			result = place_building(str(option.kind), Vector2i(option.tile[0], option.tile[1]))
			if result.begins_with("Started"):
				record_decision(by, str(option.label), str(option.get("reason", "")))
		"upgrade":
			result = upgrade_building(int(option.building))
			if result == "Upgrade started.":
				record_decision(by, str(option.label), str(option.get("reason", "")))
		"wall":
			result = Walls.place(self, Vector2i(int(option.d[0]), int(option.d[1])), int(option.side), bool(option.get("gate", false)))
			if result.begins_with("Started"):
				record_decision(by, str(option.label), str(option.get("reason", "")))
		"expand":
			result = claim_district(Vector2i(option.tile[0], option.tile[1]))
			if result == "District claimed.":
				record_decision(by, str(option.label), str(option.get("reason", "")))
		_:
			result = "Unknown plan."
	return result


func record_decision(by: String, text: String, reason: String) -> void:
	decisions.append({"day": day(), "by": by, "text": text, "reason": reason})
	if decisions.size() > 14:
		decisions.pop_front()
	log_event("%s decided: %s" % [by, text])


# --- construction work ------------------------------------------------------------------------------

## The project residents are currently labouring on: the oldest building under construction or upgrade.
func active_project() -> Dictionary:
	for b in buildings:
		if int(b.target) > int(b.level):
			return {"type": "build" if int(b.level) == 0 else "upgrade", "ref": b, "label": "%s%s" % [Catalog.label(str(b.kind)), "" if int(b.level) == 0 else " to level %d" % int(b.target)], "progress": float(b.progress)}
	return {}


func projects() -> Array:
	var out: Array = []
	for b in buildings:
		if int(b.target) > int(b.level):
			out.append(b)
	return out


## Adds a work shift to the active project. Returns a short result string ("" if nothing to build).
func add_progress(amount: float) -> String:
	var project := active_project()
	if project.is_empty():
		return ""
	var b: Dictionary = project.ref
	var work: float = Catalog.WORK[clampi(int(b.target) - 1, 0, Catalog.WORK.size() - 1)] * (0.45 if Walls.is_wall(b) else 1.0)
	b.progress = minf(100.0, float(b.progress) + amount * 100.0 / work * 1.15)
	if float(b.progress) >= 100.0:
		var first := int(b.level) == 0
		b.level = int(b.target)
		b.target = 0
		b.visits = 0 if first else int(b.visits)
		_assign_homeless()
		var what := Catalog.label(str(b.kind))
		log_event("%s %s!" % [what, "is finished" if first else "upgraded to level %d" % int(b.level)])
		notice("%s %s" % [what, "completed" if first else "upgraded to level %d" % int(b.level)])
		_check_stage()
		return "The %s is %s!" % [what.to_lower(), "finished" if first else "upgraded"]
	return "Construction %d%% done." % int(b.progress)


# --- population -------------------------------------------------------------------------------------

func _assign_homeless() -> void:
	for r in residents:
		var home := building_by_id(int(r.home))
		if home.is_empty() or int(home.level) < 1:
			r.home = _free_home()


func _free_home() -> int:
	var best := -1
	var best_free := 0
	for b in buildings:
		if b.kind == "home" and int(b.level) >= 1:
			var free := Catalog.capacity("home", int(b.level)) - occupants_of(int(b.id))
			if free > best_free:
				best_free = free
				best = int(b.id)
	return best


func _maybe_immigrate() -> void:
	var free_beds := housing() - residents.size()
	if free_beds <= 0 or residents.size() >= Catalog.MAX_POPULATION or average_mood() < 60.0:
		return
	var arrivals := clampi(1 + free_beds / 8, 1, 2)
	for i in range(arrivals):
		if not _spawn_resident():
			return


## One newcomer moves into a free bed. False if the town cannot take anyone right now.
func _spawn_resident() -> bool:
	if residents.size() >= Catalog.MAX_POPULATION or _free_home() < 0:
		return false
	if food + meals * 2 < residents.size() * 2:
		return false
	var home_id := _free_home()
	var used := {}
	for r in residents:
		used[r.name] = true
	var name_ := ""
	for candidate in Catalog.RESIDENT_NAMES:
		if not used.has(candidate):
			name_ = candidate
			break
	if name_ == "":
		name_ = "Newcomer %d" % (residents.size() + 1)
	var home := building_by_id(home_id)
	var arrival := Vector2(map.door_for(tile_of(home)))
	var look := residents.size() % Catalog.LOOKS.size()
	var trait_: String = Catalog.RESIDENT_TRAITS[rng.randi() % Catalog.RESIDENT_TRAITS.size()]
	var r := _new_resident(name_, trait_, look, rng.randi_range(18, 62), home_id, arrival)
	for key in r.skills:
		r.skills[key] = float(rng.randi_range(0, 30))
	residents.append(r)
	_refresh_wants(r)
	last_arrival_day = day()
	log_event("%s, a %s, moved to Willowbrook." % [name_, trait_.to_lower()])
	notice("%s has moved in!" % name_)
	say(residents.size() - 1, "Hello, Willowbrook!")
	emote(residents.size() - 1, "happy", 0.3)
	_check_stage()
	return true


# --- interaction: commands, social, wants ------------------------------------------------------------

func push_fx(event: Dictionary) -> void:
	fx.append(event)
	if fx.size() > 60:
		fx.pop_front()


func drain_fx() -> Array:
	var out := fx
	fx = []
	return out


func say(index: int, text: String, delay: float = 0.0) -> void:
	push_fx({"type": "say", "who": index, "text": text, "delay": delay})


func emote(index: int, kind: String, delay: float = 0.0) -> void:
	push_fx({"type": "emote", "who": index, "kind": kind, "delay": delay})


func emotion(r: Dictionary) -> String:
	return Social.emotion(r.needs, mood(r))


func relation(r: Dictionary, other_name: String) -> float:
	return float(r.relations.get(other_name, 0))


## True while the resident is inside a building doing an indoor activity.
func is_inside(r: Dictionary) -> bool:
	return r.route.is_empty() and str(r.action) in INDOOR_ACTIONS and float(r.remaining) > 0.0 and int(r.target_id) >= 0


## 0..1 progress of the current activity.
func activity_progress(r: Dictionary) -> float:
	var total := float(DURATIONS.get(r.action, 25.0))
	return clampf(1.0 - float(r.remaining) / total, 0.0, 1.0)


func _begin_next(index: int) -> void:
	var r: Dictionary = residents[index]
	while not r.queue.is_empty():
		var queued: String = r.queue.pop_front()
		if has_target(queued) and start_action(index, queued):
			r.commanded = true
			_bark(index, queued)
			return
	r.commanded = false
	var chosen := choose_action(r)
	if start_action(index, chosen):
		_bark(index, chosen)


func _bark(index: int, action: String) -> void:
	if rng.randf() < 0.22:
		say(index, Social.bark(action, rng))


## Player orders an action. Interrupts autonomous behaviour; otherwise joins the queue.
## Residents may refuse (exhausted, starving, not sleepy, queue full).
func command(index: int, action: String) -> Dictionary:
	if index < 0 or index >= residents.size() or action not in ACTIONS:
		return {"ok": false, "message": "Unknown request."}
	var r: Dictionary = residents[index]
	var n: Dictionary = r.needs
	var too := Lifecycle.blocked(r, action)
	if too != "":
		return {"ok": false, "message": "%s %s." % [r.name, too]}
	if float(r.get("break_until", 0.0)) > minutes:
		var plea := "Please, Chief... not now. I need some space."
		say(index, plea)
		return {"ok": false, "refused": true, "message": "%s: \"%s\"" % [r.name, plea]}
	var objection := Psyche.dissonance(self, index, action)
	if objection != "":
		say(index, objection)
		return {"ok": false, "refused": true, "message": "%s: \"%s\"" % [r.name, objection]}
	release(index)
	var reason := ""
	if action not in ["sleep", "rest"] and float(n.energy) < 12.0:
		reason = "tired"
	elif action not in ["eat", "gather"] and float(n.hunger) < 10.0:
		reason = "starving"
	elif action == "sleep" and float(n.energy) > 85.0:
		reason = "not_sleepy"
	elif r.queue.size() >= MAX_QUEUE:
		reason = "full_queue"
	if reason != "":
		var text := Social.refusal(reason, rng)
		say(index, text)
		emote(index, "anger" if reason == "starving" else "tired")
		return {"ok": false, "refused": true, "message": "%s: \"%s\"" % [r.name, text]}
	if not has_target(action):
		if action in JOB_ACTIONS:
			return {"ok": false, "message": "There is nothing to %s within reach of the village." % {"chop": "chop", "mine": "mine", "water": "draw water from"}[action]}
		return {"ok": false, "message": "There is nowhere to %s yet. Build something for it first." % ACTION_VERBS[action].to_lower()}
	if action == "eat" and food <= 0 and meals <= 0:
		return {"ok": false, "message": "The pantry is empty. Send someone to gather first."}
	var busy_commanded: bool = bool(r.commanded) and float(r.remaining) > 0.0
	var sleeping: bool = str(r.action) == "sleep" and float(r.remaining) > 0.0
	if busy_commanded or sleeping or not r.queue.is_empty():
		r.queue.append(action)
		return {"ok": true, "queued": true, "message": "%s will %s next." % [r.name, ACTION_VERBS[action].to_lower()]}
	if start_action(index, action):
		r.commanded = true
		say(index, Social.bark(action, rng))
		return {"ok": true, "queued": false, "message": "%s: %s." % [r.name, ACTION_VERBS[action]]}
	return {"ok": false, "message": "%s can't do that right now." % r.name}


## Orders that change what a resident is doing drop any follow/stay order first.
func release(index: int) -> void:
	following.erase(index)
	holding.erase(index)
	if index >= 0 and index < residents.size():
		_drop_job(residents[index])


func _follow_step(r: Dictionary, index: int, dm: float) -> void:
	var n: Dictionary = r.needs
	if float(n.hunger) < 8.0 or float(n.energy) < 6.0:
		following.erase(index)
		say(index, "Sorry Chief, I really need to look after myself.")
		r.remaining = 0.0
		r.commanded = false
		return
	r.commanded = true
	r.action = "socialize"
	r.target = "the chief"
	r.target_id = -1
	r.remaining = 30.0
	var here := Vector2(float(r.pos[0]), float(r.pos[1]))
	var spot := Vector2(chief_pos.x + 0.9 + 0.35 * (index % 5), chief_pos.y + 0.6 + 0.3 * (index % 3))
	if here.distance_to(chief_pos) > 2.4:
		r.repath = float(r.get("repath", 0.0)) - dm
		if r.route.is_empty() or float(r.repath) <= 0.0:
			r.repath = 2.0
			_set_route(r, map.nearest_walkable(Vector2i(roundi(spot.x), roundi(spot.y))), false)
	elif not r.route.is_empty():
		r.route = []


## Tell residents to stay where they are until released.
func hold(index: int) -> void:
	release(index)
	var r: Dictionary = residents[index]
	r.queue.clear()
	r.route = []
	r.commanded = true
	holding[index] = true
	r.target_id = -1
	r.action = "rest" if str(r.action) in INDOOR_ACTIONS else str(r.action)
	r.target = "Waiting for the chief"


func follow(index: int) -> void:
	release(index)
	var r: Dictionary = residents[index]
	r.queue.clear()
	following[index] = true
	r.remaining = 0.0
	say(index, Social.pick(["Right behind you, Chief.", "Lead the way!", "Coming along."], rng))


## Back to normal life: drop every standing order and let the resident decide again.
func free_resident(index: int) -> void:
	release(index)
	talk_with.erase(index)
	talking.erase(index)
	var r: Dictionary = residents[index]
	r.queue.clear()
	r.commanded = false
	r.remaining = 0.0
	r.route = []


## Everyone listed walks to the spot (tile units) and waits there for a while.
func gather_at(indices: Array, spot: Vector2, label: String = "the chief") -> int:
	var count := 0
	for k in range(indices.size()):
		var index: int = indices[k]
		if index < 0 or index >= residents.size():
			continue
		release(index)
		var r: Dictionary = residents[index]
		r.queue.clear()
		r.action = "socialize"
		r.target = label
		r.target_id = -1
		r.commanded = true
		r.remaining = 60.0
		var angle := TAU * float(k) / maxf(1.0, float(indices.size()))
		var radius := 1.2 + 0.25 * float(k / 8)
		var p := spot + Vector2(cos(angle), sin(angle)) * radius
		_set_route(r, map.nearest_walkable(Vector2i(roundi(p.x), roundi(p.y))), false)
		count += 1
	return count


func cancel_queued(index: int, slot: int) -> void:
	var r: Dictionary = residents[index]
	if slot >= 0 and slot < r.queue.size():
		r.queue.remove_at(slot)


## Why a social kind is unavailable between residents (a, b) or with the player (b = -1). "" if available.
func social_blocker(a_index: int, b_index: int, kind: String) -> String:
	var spec: Dictionary = Social.KINDS[kind]
	var a: Dictionary = residents[a_index]
	var bond := float(a.bond) if b_index < 0 else relation(a, residents[b_index].name)
	if bond < float(spec.min):
		return "Needs friendship (%d+)" % int(spec.min)
	var key := "player:%s" % kind if b_index < 0 else "%s:%s" % [kind, residents[b_index].name]
	if minutes < float(a.cooldowns.get(key, 0.0)):
		return "Wait a little"
	return ""


func _success_chance(bond: float, target: Dictionary) -> float:
	return clampf(0.55 + bond / 220.0 + (mood(target) - 50.0) / 250.0, 0.2, 0.95)


## Nearest other resident within `radius` tiles (-1 if none).
func _nearest_resident(index: int, radius: float) -> int:
	var me := Vector2(residents[index].pos[0], residents[index].pos[1])
	var best := -1
	var best_d := radius
	for j in range(residents.size()):
		if j == index:
			continue
		var d := me.distance_to(Vector2(residents[j].pos[0], residents[j].pos[1]))
		if d <= best_d:
			best_d = d
			best = j
	return best


func _pick_social_kind(a: Dictionary, b: Dictionary) -> String:
	var bond := relation(a, b.name)
	if mood(a) < 38.0 and rng.randf() < 0.25 * (1.5 - Psyche.f(a, "a")) and minutes >= float(a.cooldowns.get("argue:%s" % b.name, 0.0)):
		return "argue"
	var options: Array = []
	for kind in Social.KINDS:
		if kind == "argue" or bond < float(Social.KINDS[kind].min):
			continue
		if minutes < float(a.cooldowns.get("%s:%s" % [kind, b.name], 0.0)):
			continue
		options.append(kind)
	if options.is_empty():
		return ""
	return options[rng.randi() % options.size()]


func _apply_social_needs(r: Dictionary, spec: Dictionary, scale_: float) -> void:
	var warmth := Psyche.social_gain(r) if float(spec.social) > 0.0 else 1.0
	r.needs.social = clampf(float(r.needs.social) + float(spec.social) * scale_ * warmth, 0.0, 100.0)
	r.needs.fun = clampf(float(r.needs.fun) + float(spec.fun) * scale_, 0.0, 100.0)


## Two residents interact. Returns {ok, success, summary, delta}.
func resident_interact(a_index: int, b_index: int, kind: String) -> Dictionary:
	var a: Dictionary = residents[a_index]
	var b: Dictionary = residents[b_index]
	var spec: Dictionary = Social.KINDS[kind]
	var before := relation(a, b.name)
	var key := "%s:%s" % [kind, b.name]
	a.cooldowns[key] = minutes + float(spec.cool)
	var liking := float(b.opinion.get(a.name, before))
	var success := kind == "argue" or rng.randf() < _success_chance(before, b) + (Psyche.compat(a, b) - 0.5) * 0.15 + (liking - before) / 300.0
	var delta: float = float(spec.bond) if success else 1.0
	var after := clampf(before + delta, 0.0, 100.0)
	a.relations[b.name] = after
	b.relations[a.name] = after
	_apply_social_needs(a, spec, 1.0 if success else 0.3)
	_apply_social_needs(b, spec, 1.0 if success else 0.3)
	if scripted_dialogue:
		push_fx({"type": "conversation", "a": a_index, "b": b_index, "kind": kind, "success": success, "summary": ""})
	else:
		say(a_index, Social.line(kind, "start", rng, b.name))
		say(b_index, Social.line(kind, "good" if success else "meh", rng, a.name), 1.8)
		emote(a_index, spec.emote, 0.2)
		emote(b_index, spec.emote if success and kind != "argue" else ("anger" if kind == "argue" else "sweat"), 2.0)
	var verb: String = {"chat": "chatted with", "joke": "told a joke to", "compliment": "complimented", "gossip": "gossiped with", "hug": "hugged", "argue": "argued with"}[kind]
	var summary := "%s %s %s%s" % [a.name, verb, b.name, "." if success or kind == "argue" else ". It fell a bit flat."]
	remember(a, summary)
	remember(b, "%s %s you." % [a.name, verb])
	Lifecycle.on_interact(self, a_index, b_index, kind, success)
	Rumors.on_interact(self, a_index, b_index, kind)
	if kind == "argue":
		Rumors.create(self, str(a.name), str(b.name), "argue", "%s and %s had a row" % [a.name, b.name], -0.3, [a_index, b_index])
	_milestone(a_index, b_index, before, after)
	_check_wants(a)
	_check_wants(b)
	return {"ok": true, "success": success, "summary": summary, "delta": delta}


func _milestone(a_index: int, b_index: int, before: float, after: float) -> void:
	var was := Social.bond_label(before)
	var now := Social.bond_label(after)
	if was != now and after > before:
		var names := "%s and %s" % [residents[a_index].name, residents[b_index].name]
		log_event("%s are now %s!" % [names, now.to_lower()])
		notice("%s: %s" % [names, now])
		emote(a_index, "heart", 0.6)
		emote(b_index, "heart", 2.2)


## The chief interacts with a resident. kind: a Social kind, or "share_meal".
func player_interact(index: int, kind: String) -> Dictionary:
	var r: Dictionary = residents[index]
	if kind == "share_meal":
		if meals <= 0:
			return {"ok": false, "message": "There are no meals to share."}
		if minutes < float(r.cooldowns.get("player:share_meal", 0.0)):
			return {"ok": false, "message": "%s isn't hungry for another while." % r.name}
		r.cooldowns["player:share_meal"] = minutes + 120.0
		meals -= 1
		var hungry := float(r.needs.hunger) < 55.0
		r.needs.hunger = minf(100.0, float(r.needs.hunger) + 35.0)
		var before_meal := float(r.bond)
		r.bond = minf(100.0, before_meal + 6.0)
		say(index, "Thank you, I was starving!" if hungry else "That's kind of you!", 0.5)
		emote(index, "heart", 0.6)
		remember(r, "Day %d: The chief shared a meal with me." % day())
		_check_wants(r)
		return {"ok": true, "success": true, "message": "You shared a meal with %s." % r.name}
	var spec: Dictionary = Social.KINDS[kind]
	var why := social_blocker(index, -1, kind)
	if why != "":
		if why.begins_with("Needs"):
			say(index, Social.pick(Social.REFUSE_BOND, rng), 0.4)
			emote(index, "sweat", 0.4)
		return {"ok": false, "message": "%s: %s." % [r.name, why]}
	r.cooldowns["player:%s" % kind] = minutes + float(spec.cool)
	var before := float(r.bond)
	var success := kind == "argue" or rng.randf() < _success_chance(before, r)
	var delta: float = float(spec.bond) if success else 1.0
	r.bond = clampf(before + delta, 0.0, 100.0)
	_apply_social_needs(r, spec, 1.0 if success else 0.3)
	say(index, Social.line(kind, "good" if success else "meh", rng, "you"), 0.6)
	emote(index, spec.emote if success and kind != "argue" else ("anger" if kind == "argue" else "sweat"), 0.5)
	remember(r, "Day %d: The chief wanted to %s with me." % [day(), str(spec.label).to_lower()])
	var was := Social.bond_label(before)
	var now := Social.bond_label(float(r.bond))
	if was != now and float(r.bond) > before:
		log_event("%s now respects you as a %s." % [r.name, now.to_lower()])
		notice("%s: you are now %s" % [r.name, now.to_lower()])
		emote(index, "heart", 1.2)
	_check_wants(r)
	return {"ok": true, "success": success, "delta": delta, "message": "%s %s." % [r.name, "enjoyed that" if success else "wasn't into it"]}


# --- advice: residents ask the chief what to do ------------------------------------------------------------

func _tick_advice(dm: float) -> void:
	if advice.is_empty():
		var hour := int(minutes / 60.0)
		if ask_chief and hour != _advice_hour:
			_advice_hour = hour
			_maybe_request_advice()
		return
	var index := int(advice.resident)
	if index >= residents.size():
		advice = {}
		return
	var r: Dictionary = residents[index]
	if minutes - float(advice.asked_at) > Advice.TIMEOUT_MINUTES:
		_expire_advice()
		return
	if advice.state == "approaching":
		if Vector2(r.pos[0], r.pos[1]).distance_to(chief_pos) <= 1.8:
			advice.state = "waiting"
			r.route = []
			push_fx({"type": "advice_ready", "who": index})
			say(index, "Chief! May I ask for your advice?")
			emote(index, "speech", 0.3)
		else:
			advice.repath = float(advice.get("repath", 0.0)) - dm
			if float(advice.repath) <= 0.0:
				advice.repath = 1.5
				_set_route(r, map.nearest_walkable(Vector2i(roundi(chief_pos.x), roundi(chief_pos.y))), false)


func _maybe_request_advice() -> void:
	if minutes - _last_advice_end < ADVICE_INTERVAL or residents.size() < 2:
		return
	var request := {}
	if rng.randf() < 0.5:
		request = Quests.request(self)
	if request.is_empty() and rng.randf() < 0.35:
		request = Advice.personal_request(self)
	if request.is_empty():
		request = Advice.city_request(self)
	if request.is_empty():
		request = Advice.personal_request(self)
	if not request.is_empty():
		start_advice(request)


## A resident sets off to find the chief with this request.
func start_advice(request: Dictionary) -> void:
	_advice_serial += 1
	request.id = _advice_serial
	request.state = "approaching"
	request.asked_at = minutes
	request.opened = false
	advice = request
	if str(request.kind) == "quest":
		Quests.mark_asked(self, int(request.resident))
	var r: Dictionary = residents[int(request.resident)]
	r.commanded = true
	r.action = "socialize"
	r.remaining = 99999.0
	r.target = "the chief"
	r.target_id = -1
	r.queue.clear()
	notice("%s wants your advice" % r.name)
	log_event("%s is looking for the chief to ask for advice." % r.name)


## The chief answers (an option id from the request, or Advice.NOT_NOW). Returns a short message.
func resolve_advice(option_id: int) -> String:
	if advice.is_empty():
		return ""
	var message := Advice.apply(self, advice, option_id)
	_end_advice()
	return message


func _end_advice() -> void:
	if not advice.is_empty() and int(advice.resident) < residents.size():
		var r: Dictionary = residents[int(advice.resident)]
		r.remaining = 0.0
		r.commanded = false
	advice = {}
	_last_advice_end = minutes


## Nobody answered: the council decides, and the resident feels ignored.
func _expire_advice() -> void:
	var r: Dictionary = residents[int(advice.resident)]
	if str(advice.kind) == "quest":
		Quests.delay(self, int(advice.resident), 3)
		say(int(advice.resident), "Never mind, Chief. Perhaps another time.")
		r.bond = maxf(0.0, float(r.bond) - 1.0)
		log_event("%s gave up waiting to tell the chief their dream." % r.name)
		_end_advice()
		return
	if str(advice.kind) == "city":
		for o in advice.options:
			if int(o.id) >= 0 and not (o.plan as Dictionary).is_empty():
				apply_option(o.plan, "The council")
				break
		say(int(advice.resident), "The council went ahead without you, Chief.")
	else:
		say(int(advice.resident), "I will manage on my own.")
	r.bond = maxf(0.0, float(r.bond) - 2.0)
	emote(int(advice.resident), "sweat", 0.3)
	log_event("%s gave up waiting for the chief." % r.name)
	_end_advice()


## Replace the template wording with the AI's (only while the chief has not opened the request yet).
func refine_advice(question: String, option_texts: Dictionary) -> void:
	if advice.is_empty() or bool(advice.get("opened", false)):
		return
	if question.strip_edges() != "":
		advice.question = question.strip_edges()
	for o in advice.options:
		if option_texts.has(int(o.id)) and str(option_texts[int(o.id)]).strip_edges() != "" and int(o.id) >= 0:
			o.text = str(option_texts[int(o.id)]).strip_edges()


# --- wants (aspirations) ------------------------------------------------------------------------------

func aspiration_level(r: Dictionary) -> int:
	return int(float(r.points) / 60.0) + 1


func _refresh_wants(r: Dictionary) -> void:
	var guard := 0
	while r.wants.size() < 2 and guard < 16:
		guard += 1
		var w := _make_want(r)
		var duplicate := false
		for e in r.wants:
			if e.kind == w.kind and e.get("who", "") == w.get("who", "") and e.get("skill", "") == w.get("skill", "") and e.get("action", "") == w.get("action", ""):
				duplicate = true
		if not duplicate:
			r.wants.append(w)


func _make_want(r: Dictionary) -> Dictionary:
	match rng.randi() % 4:
		0:
			var others: Array = residents.filter(func(o: Dictionary) -> bool: return o.name != r.name and relation(r, o.name) < 55.0)
			if not others.is_empty():
				var o: Dictionary = others[rng.randi() % others.size()]
				return {"kind": "friend", "who": o.name, "goal": minf(100.0, relation(r, o.name) + 25.0), "points": 25, "text": "Grow closer to %s" % o.name}
		1:
			var keys: Array = r.skills.keys()
			var k: String = keys[rng.randi() % keys.size()]
			var level := int(float(r.skills[k]) / 60.0) + 1
			return {"kind": "skill", "skill": k, "goal": float(level * 60), "points": 20, "text": "Reach %s level %d" % [k.capitalize(), level + 1]}
		2:
			if float(r.bond) < 70.0:
				return {"kind": "bond", "goal": minf(100.0, float(r.bond) + 20.0), "points": 20, "text": "Win the chief's trust"}
	var action: String = ACTIONS[rng.randi() % ACTIONS.size()]
	var times := 2 if action == "sleep" else 3
	return {"kind": "do", "action": action, "goal": times, "base": int(r.counts.get(action, 0)), "points": 15, "text": "%s %d times" % [ACTION_VERBS[action], times]}


func want_progress(r: Dictionary, w: Dictionary) -> float:
	match str(w.kind):
		"friend": return clampf(relation(r, str(w.who)) / float(w.goal), 0.0, 1.0)
		"skill": return clampf(float(r.skills.get(w.skill, 0.0)) / float(w.goal), 0.0, 1.0)
		"bond": return clampf(float(r.bond) / float(w.goal), 0.0, 1.0)
		"do": return clampf(float(int(r.counts.get(w.action, 0)) - int(w.base)) / float(w.goal), 0.0, 1.0)
	return 0.0


func _check_wants(r: Dictionary) -> void:
	for w in r.wants.duplicate():
		if want_progress(r, w) >= 1.0:
			r.wants.erase(w)
			r.points = int(r.points) + int(w.points)
			var index := residents.find(r)
			log_event("%s's wish came true: %s (+%d)" % [r.name, str(w.text).to_lower(), int(w.points)])
			notice("%s: wish fulfilled! +%d" % [r.name, int(w.points)])
			emote(index, "star", 0.3)
			_refresh_wants(r)


func remember(r: Dictionary, message: String) -> void:
	r.memory.append("Day %d: %s" % [day(), message.left(300)])
	if r.memory.size() > 12:
		r.memory.pop_front()


func log_has(fragment: String) -> bool:
	for e in journal:
		if str(e).contains(fragment):
			return true
	return false


func log_event(message: String) -> void:
	journal.append("%s  %s" % [clock_text(), message])
	if journal.size() > 60:
		journal.pop_front()
	var kind := Chronicle.classify(message)
	if kind != "":
		Chronicle.add(self, kind, message)


func notice(message: String) -> void:
	notices.append(message)
	if notices.size() > 8:
		notices.pop_front()


func _check_goals() -> void:
	for r in residents:
		for score in r.relations.values():
			if float(score) >= 48:
				goals.friend = true
		for xp in r.skills.values():
			if float(xp) >= 60:
				goals.skilled = true


# --- observation for the AI -----------------------------------------------------------------------------

func city_summary() -> Dictionary:
	var kinds := {}
	var danger := "%d monsters nearby" % threat if threat > 0 else "calm"
	for b in buildings:
		if int(b.level) >= 1:
			kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
	var project := active_project()
	return {"stage": stage_name(), "population": residents.size(), "housing": housing(), "buildings": kinds, "danger": danger, "livestock": Farming.total_animals(self), "districts": map.claimed.size(), "free_lots": map.free_lots().size(), "active_project": "" if project.is_empty() else "%s (%d%% done) - 'work' builds it" % [project.label, int(project.progress)]}


func observation(index: int, message: String, history: Array = []) -> Dictionary:
	var r: Dictionary = residents[index]
	var slim := {"name": r.name, "inner": Psyche.describe(self, r), "gender": "woman" if Catalog.LOOKS[int(r.look) % Catalog.LOOKS.size()] in Catalog.FEMALE_LOOKS else "man", "trait": r.trait, "age": r.age, "needs": r.needs, "skills": r.skills, "action": r.action, "target": r.target, "thought": r.thought, "memory": r.memory.slice(-6), "wants": r.wants.map(func(w: Dictionary) -> String: return str(w.text)), "bond_with_chief": r.bond}
	return {"resident": slim, "day": day(), "time": clock_text(), "season": season(), "weather": weather, "threat": threat, "household": {"coins": money, "produce": food, "meals": meals, "materials": materials()}, "neighbors": residents.slice(0, 12).map(func(o: Dictionary) -> Dictionary: return {"name": o.name, "action": o.action}), "recent_events": journal.slice(-6), "market": prices, "world_events": events.map(func(e: Dictionary) -> String: return str(e.text)), "player_message": message, "chat_history": history.slice(-8), "allowed_actions": ACTIONS.filter(func(a: String) -> bool: return has_target(a)), "city": city_summary()}


# --- persistence --------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "minutes": minutes, "money": money, "food": food, "wood": wood, "stone": stone, "depleted": _depleted_list(), "rumors": rumors, "rumor_serial": rumor_serial, "animal_serial": animal_serial, "item_serial": item_serial, "caravan": caravan, "chronicle": chronicle, "armory": armory, "chief_weapon": chief_weapon, "fighter": {"hp": float(fighter.get("hp", 100.0)), "shield": bool(fighter.get("shield", false)), "kills": int(fighter.get("kills", 0))}, "rival": rival, "stories": stories, "routes": routes, "crops_unlocked": crops_unlocked, "tools": tools, "medicine": medicine, "harvested": harvested, "price_history": price_history, "prices": prices, "events": events, "cold_homes": cold_homes, "meals": meals, "map": map.to_dict(), "buildings": buildings, "next_building_id": next_building_id, "residents": residents, "journal": journal, "weather": weather, "goals": goals, "rng_state": str(rng.state), "stage_reached": stage_reached, "last_arrival_day": last_arrival_day, "auto_plan": auto_plan, "decisions": decisions, "chief": [chief_pos.x, chief_pos.y]}


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _valid_point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _valid_number(value[0]) and _valid_number(value[1]) and absf(value[0]) <= 100000 and absf(value[1]) <= 100000


func load_data(d: Dictionary) -> bool:
	if d.get("version") == 2:
		return _migrate_v2(d)
	if d.get("version") != SAVE_VERSION or not d.get("residents") is Array or d.residents.is_empty():
		return false
	for key in ["minutes", "money", "food", "wood", "meals", "next_building_id"]:
		if not _valid_number(d.get(key)): return false
	if not d.get("buildings") is Array or not d.get("journal") is Array or not d.get("goals") is Dictionary or not d.get("map") is Dictionary:
		return false
	var probe := CityMap.new()
	if not probe.load_dict(d.map):
		return false
	var seen_ids := {}
	for b in d.buildings:
		if not b is Dictionary or not Catalog.KINDS.has(b.get("kind")) or not _valid_point(b.get("tile")) or not _valid_point(b.get("door")): return false
		for key in ["id", "level", "target", "progress", "visits", "variant"]:
			if not _valid_number(b.get(key)): return false
		if int(b.level) < 0 or int(b.level) > Catalog.max_level(b.kind) or int(b.target) < 0 or int(b.target) > Catalog.max_level(b.kind): return false
		if float(b.progress) < 0 or float(b.progress) > 100 or seen_ids.has(int(b.id)): return false
		seen_ids[int(b.id)] = true
	for entry in d.journal:
		if not entry is String: return false
	for key in d.goals:
		if not d.goals[key] is bool: return false
	var fresh := _resident_template()
	for r in d.residents:
		if not _valid_resident(r, fresh):
			return false
	for e in d.get("decisions", []):
		if not e is Dictionary or not e.get("text") is String or not e.get("by") is String: return false
	minutes = maxf(0, float(d.minutes))
	money = maxi(0, int(d.money))
	food = maxi(0, int(d.food))
	wood = maxi(0, int(d.wood))
	stone = maxi(0, int(d.get("stone", 0)))
	rumors = d.get("rumors", []) if d.get("rumors", []) is Array else []
	rumor_serial = int(d.get("rumor_serial", 0))
	animal_serial = int(d.get("animal_serial", 0))
	item_serial = int(d.get("item_serial", 0))
	armory = d.get("armory", {}) if d.get("armory", {}) is Dictionary else {}
	chief_weapon = str(d.get("chief_weapon", ""))
	fighter = d.get("fighter", {}) if d.get("fighter", {}) is Dictionary else {}
	rival = d.get("rival", {}) if d.get("rival", {}) is Dictionary else {}
	stories = d.get("stories", {}) if d.get("stories", {}) is Dictionary else {}
	chronicle = d.get("chronicle", []) if d.get("chronicle", []) is Array else []
	caravan = d.get("caravan", {}) if d.get("caravan", {}) is Dictionary else {}
	routes = clampi(int(d.get("routes", 0)), 0, Caravans.MAX_ROUTE)
	crops_unlocked = d.get("crops_unlocked", ["wheat", "carrot", "corn", "pumpkin"]) if d.get("crops_unlocked", []) is Array and not (d.get("crops_unlocked", []) as Array).is_empty() else ["wheat", "carrot", "corn", "pumpkin"]
	tools = bool(d.get("tools", false))
	medicine = maxi(0, int(d.get("medicine", 0)))
	harvested = d.get("harvested", {}) if d.get("harvested", {}) is Dictionary else {}
	price_history = d.get("price_history", {}) if d.get("price_history", {}) is Dictionary else {}
	prices = d.get("prices", Economy.init_prices()) if d.get("prices", {}) is Dictionary and not (d.get("prices", {}) as Dictionary).is_empty() else Economy.init_prices()
	events = d.get("events", []) if d.get("events", []) is Array else []
	cold_homes = bool(d.get("cold_homes", false))
	for fill in Economy.init_prices():
		if not prices.has(fill):
			prices[fill] = Economy.init_prices()[fill]
	_load_depleted(d.get("depleted", []))
	meals = maxi(0, int(d.meals))
	map = probe
	buildings = d.buildings
	next_building_id = int(d.next_building_id)
	for b in buildings:
		b.id = int(b.id)
		b.level = int(b.level)
		b.target = int(b.target)
		b.visits = int(b.visits)
		b.variant = int(b.variant)
		if not Walls.is_wall(b):
			map.set_building_tile(int(b.id), tile_of(b), Catalog.solid(str(b.kind)))
	residents = d.residents
	for r in residents:
		if float(r.remaining) > 5000.0:
			r.remaining = 0.0  # a saved advice errand: the request itself is not saved
			r.commanded = false
		r.job = {}
		r.carry = ""
		if str(r.action) in JOB_ACTIONS:
			r.remaining = 0.0
		r.bond = float(r.bond)
		r.points = int(r.points)
		r.home = int(r.home)
		r.target_id = int(r.target_id)
		r.look = int(r.look)
		_refresh_wants(r)
	journal = d.journal
	weather = str(d.get("weather", "Clear"))
	goals.merge(d.goals, true)
	last_day = day()
	rng.state = int(d.get("rng_state", str(rng.state)))
	stage_reached = maxi(int(d.get("stage_reached", 0)), stage())
	last_arrival_day = int(d.get("last_arrival_day", 0))
	auto_plan = bool(d.get("auto_plan", true))
	decisions = d.get("decisions", [])
	var chief: Variant = d.get("chief", [2.0, 4.0])
	chief_pos = Vector2(float(chief[0]), float(chief[1])) if _valid_point(chief) else Vector2(2.0, 4.0)
	notices.clear()
	return true


func _resident_template() -> Dictionary:
	return _new_resident("x", "x", 0, 20, -1, Vector2.ZERO)


func _valid_resident(r: Variant, fresh: Dictionary) -> bool:
	if not r is Dictionary or not r.get("needs") is Dictionary or not r.get("skills") is Dictionary or not _valid_point(r.get("pos")):
		return false
	for n in NEEDS:
		if not _valid_number(r.needs.get(n)) or float(r.needs[n]) < 0 or float(r.needs[n]) > 100:
			return false
	r["route"] = r.get("route", [])
	for key in ["queue", "wants", "memory"]:
		if not r.has(key): r[key] = []
	for key in ["cooldowns", "counts", "relations"]:
		if not r.has(key): r[key] = {}
	if not r.has("bond"): r["bond"] = 0.0
	if not r.has("points"): r["points"] = 0
	if not r.has("commanded"): r["commanded"] = false
	if not r.has("look"): r["look"] = 0
	if not r.has("home"): r["home"] = -1
	if not r.has("target_id"): r["target_id"] = -1
	if not r.has("job"): r["job"] = {}
	if not r.has("carry"): r["carry"] = ""
	Psyche.extend(r, rng)
	for key in fresh.keys():
		if not r.has(key):
			return false
	if not r.route is Array or not r.memory is Array or not r.relations is Dictionary or not r.queue is Array or not r.wants is Array or not r.cooldowns is Dictionary or not r.counts is Dictionary or not r.commanded is bool:
		return false
	if not _valid_number(r.bond) or not _valid_number(r.points): return false
	for point in r.route:
		if not _valid_point(point): return false
	for entry in r.memory:
		if not entry is String: return false
	for key in ["name", "trait", "action", "target", "thought", "say"]:
		if not r[key] is String: return false
	if r.action not in ACTIONS: return false
	for queued_action in r.queue:
		if not queued_action is String or queued_action not in ACTIONS: return false
	for w in r.wants:
		if not w is Dictionary or not w.get("kind") is String or not w.get("text") is String or not _valid_number(w.get("goal")) or not _valid_number(w.get("points")): return false
	for key in ["age", "remaining", "career", "earned", "completed", "look", "home", "target_id"]:
		if not _valid_number(r[key]): return false
	for key in ["age", "remaining", "career", "earned", "completed"]:
		if float(r[key]) < 0: return false
	for value in r.cooldowns.values():
		if not _valid_number(value): return false
	for value in r.counts.values():
		if not _valid_number(value): return false
	for key in fresh.skills:
		if not _valid_number(r.skills.get(key)): return false
	for score in r.relations.values():
		if not _valid_number(score): return false
	return true


## Saves from the fixed-layout village keep their people, memories and relationships; the city is rebuilt.
func _migrate_v2(d: Dictionary) -> bool:
	if not d.get("residents") is Array or d.residents.size() != 4:
		return false
	var fresh := LifeSim.new()
	var old_residents: Array = d.residents
	for i in range(4):
		var o: Dictionary = old_residents[i]
		var r: Dictionary = fresh.residents[i]
		if not o.get("needs") is Dictionary or not o.get("skills") is Dictionary:
			return false
		for n in NEEDS:
			if _valid_number(o.needs.get(n)):
				r.needs[n] = clampf(float(o.needs[n]), 0.0, 100.0)
		for k in r.skills:
			if _valid_number(o.skills.get(k)):
				r.skills[k] = float(o.skills[k])
		if o.get("relations") is Dictionary:
			for k in o.relations:
				if _valid_number(o.relations[k]):
					r.relations[str(k)] = float(o.relations[k])
		if o.get("memory") is Array:
			for m in o.memory:
				if m is String:
					r.memory.append(m)
		for key in ["career", "earned", "completed", "points", "age"]:
			if _valid_number(o.get(key)):
				r[key] = int(o[key])
		if _valid_number(o.get("bond")):
			r.bond = float(o.bond)
		if o.get("counts") is Dictionary:
			for k in o.counts:
				if _valid_number(o.counts[k]):
					r.counts[str(k)] = int(o.counts[k])
		r.wants = []
	for r in fresh.residents:
		fresh._refresh_wants(r)
	map = fresh.map
	buildings = fresh.buildings
	next_building_id = fresh.next_building_id
	residents = fresh.residents
	minutes = maxf(0.0, float(d.get("minutes", 420.0)))
	money = maxi(400, int(d.get("money", 400)))
	food = maxi(0, int(d.get("food", 16)))
	wood = maxi(14, int(d.get("wood", 14)))
	meals = maxi(0, int(d.get("meals", 4)))
	journal = ["%s  Willowbrook was rebuilt on the new unlimited map. Everyone kept their memories and friendships." % clock_text()]
	weather = str(d.get("weather", "Clear"))
	last_day = day()
	stage_reached = stage()
	last_arrival_day = day()
	decisions = []
	return true
