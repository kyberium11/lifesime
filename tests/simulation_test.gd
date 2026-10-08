extends SceneTree
## Headless checks of the city simulation: map, buildings, council, population, interactions and saves.
## Run: godot --headless --path . --script tests/simulation_test.gd

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		print("FAIL: " + message)


func _initialize() -> void:
	test_map()
	test_buildings()
	test_construction()
	test_expansion()
	test_commands()
	test_social()
	test_population_and_council()
	test_saves()
	test_long_run()
	print("SIMULATION TESTS: %d failure(s)" % failures)
	quit(1 if failures else 0)


func test_map() -> void:
	var sim := LifeSim.new()
	var map := sim.map
	check(sim.residents.size() == 4 and sim.buildings.size() == 9, "The village starts with four residents and nine buildings")
	check(map.claimed.size() == 2 and map.claimed.has(Vector2i(0, 0)) and map.claimed.has(Vector2i(1, 0)), "Two districts are claimed at the start")
	check(sim.stage() == 0 and sim.stage_name() == "Hamlet" and sim.housing() == 6, "A hamlet with six beds")
	check(map.is_road(Vector2i(0, 0)) and map.is_road(Vector2i(2, 0)) and map.is_road(Vector2i(4, 2)) and map.is_road(Vector2i(8, 0)), "Roads run along claimed district edges")
	check(map.is_road(Vector2i(0, 4)) and not map.is_road(Vector2i(0, 8)) and not map.is_road(Vector2i(-4, 0)), "Roads close the claimed land and stop there")
	check(CityMap.is_lot(Vector2i(1, 1)) and CityMap.is_green(Vector2i(2, 2)) and not CityMap.is_lot(Vector2i(2, 2)) and not CityMap.is_lot(Vector2i(4, 1)), "Lots, green and roads are distinct")
	check(map.free_lots().size() == 8, "The second district offers eight free lots")
	var home: Dictionary = sim.buildings_of("home")[0]
	var door := Vector2i(home.door[0], home.door[1])
	check(map.is_road(door), "Buildings face a road")
	var market: Dictionary = sim.buildings_of("market")[0]
	var path := map.find_path(door, Vector2i(market.door[0], market.door[1]))
	check(not path.is_empty() or door == Vector2i(market.door[0], market.door[1]), "Roads connect homes to markets")
	check(map.find_path(door, Vector2i(30, 30)).is_empty(), "Unclaimed land is not walkable for residents")
	check(sim.map.frontier().has(Vector2i(0, 1)) and sim.map.frontier().has(Vector2i(-1, 0)) and not sim.map.frontier().has(Vector2i(5, 5)), "The frontier lists land touching the village")
	var twin := CityMap.new(1337)
	check(twin.is_water(Vector2i(300, 300)) == map.is_water(Vector2i(300, 300)) and twin.has_trees(Vector2i(40, 40)) == map.has_trees(Vector2i(40, 40)), "Terrain is deterministic")
	check(not map.is_water(Vector2i(2, 2)) and not map.is_water(Vector2i(6, 6)), "The starting area is dry")


func test_buildings() -> void:
	var sim := LifeSim.new()
	sim.money = 5000
	sim.wood = 200
	check(sim.build_blocker("home", Vector2i(5, 1)) == "", "A free lot in claimed land is buildable")
	check(sim.build_blocker("home", Vector2i(1, 1)) != "", "An occupied lot is rejected")
	check(sim.build_blocker("home", Vector2i(4, 1)) != "", "Roads cannot be built on")
	check(sim.build_blocker("home", Vector2i(2, 2)) != "", "The green cannot be built on")
	check(sim.build_blocker("home", Vector2i(9, 1)) != "", "Unclaimed land cannot be built on")
	check(sim.build_blocker("office", Vector2i(5, 1)) != "", "Offices wait for the town stage")
	check(sim.build_blocker("palace", Vector2i(5, 1)) != "", "Unknown buildings are rejected")
	var coins := sim.money
	var mats := sim.wood
	check(sim.place_building("home", Vector2i(5, 1)).begins_with("Started"), "A house can be started")
	var cost := Catalog.cost("home", 1)
	check(sim.money == coins - cost.coins and sim.wood == mats - cost.mats, "Construction costs are deducted exactly once")
	check(sim.build_blocker("home", Vector2i(5, 1)) != "", "A lot cannot be built on twice")
	var site := sim.building_at_tile(Vector2i(5, 1))
	check(not site.is_empty() and site.level == 0 and site.target == 1 and site.progress == 0.0, "A new building starts as a construction site")
	check(sim.housing() == 6, "A site gives no beds until it is finished")
	sim.money = 5
	check(sim.build_blocker("market", Vector2i(6, 1)).begins_with("Needs"), "Affordability is checked")


func test_construction() -> void:
	var sim := LifeSim.new()
	sim.money = 5000
	sim.wood = 200
	sim.place_building("home", Vector2i(5, 1))
	var worker: Dictionary = sim.residents[1]
	worker.action = "work"
	worker.target_id = int(sim.buildings_of("workshop")[0].id)
	for i in range(8):
		sim.finish_action(worker)
	var done := sim.building_at_tile(Vector2i(5, 1))
	check(done.level == 1 and done.target == 0 and done.progress >= 100.0, "Work shifts finish construction")
	check(sim.housing() == 8, "A finished house adds beds")
	var b: Dictionary = sim.buildings_of("home")[0]
	check(sim.upgrade_blocker(int(b.id)).begins_with("Needs"), "Upgrades must be earned through visits")
	b.visits = 50
	check(sim.upgrade_blocker(int(b.id)) == "", "A busy building can be upgraded")
	var coins := sim.money
	check(sim.upgrade_building(int(b.id)) == "Upgrade started." and sim.money < coins and int(b.target) == 2, "Upgrading charges and starts a project")
	check(sim.upgrade_blocker(int(b.id)) == "Already under construction.", "No double upgrades")
	for i in range(12):
		sim.finish_action(worker)
	check(int(b.level) == 2 and sim.housing() >= 9, "Upgrades raise the level and capacity")
	b.visits = 500
	for lvl in range(3, 6):
		sim.money = 99999
		sim.wood = 999
		sim.stage_floor = 4
		sim.upgrade_building(int(b.id))
		for i in range(30):
			sim.finish_action(worker)
	check(int(b.level) == Catalog.max_level("home"), "Houses can reach the top level")
	check(sim.upgrade_blocker(int(b.id)) == "Fully upgraded.", "Top-level buildings stop upgrading")


func test_expansion() -> void:
	var sim := LifeSim.new()
	sim.money = 5000
	var cost := sim.claim_cost(Vector2i(0, 1))
	var mats := sim.wood
	check(sim.claim_blocker(Vector2i(5, 5)) != "", "Only touching land can be claimed")
	check(sim.claim_blocker(Vector2i(0, 0)) != "", "Claimed land cannot be claimed again")
	check(sim.claim_district(Vector2i(0, 1)) == "District claimed." and sim.money == 5000 - cost, "Claiming a district costs coins")
	check(sim.map.claimed.size() == 3 and sim.wood >= mats, "The village grows and clearing trees yields materials")
	check(sim.map.is_road(Vector2i(0, 8)) and sim.map.is_road(Vector2i(2, 4)), "Claiming adds the new district's roads")
	check(sim.map.free_lots().size() == 16, "New land adds new lots")
	var far := LifeSim.new()
	far.money = 10 ** 7
	for i in range(30):
		far.claim_district(far.map.frontier()[0])
	check(far.map.claimed.size() == 32, "The village can keep expanding (no world edge)")
	var some := far.map.frontier()[0]
	check(far.map.nav_rect.size.x > 20 and far.claim_blocker(some) == "", "Navigation grows with the territory")


func test_commands() -> void:
	var play := LifeSim.new()
	var res: Dictionary = play.command(1, "study")
	check(res.ok and not res.queued and play.residents[1].action == "study" and play.residents[1].commanded, "A command interrupts autonomy")
	res = play.command(1, "work")
	check(res.ok and res.queued and play.residents[1].queue == ["work"], "A second command is queued")
	play.cancel_queued(1, 0)
	check(play.residents[1].queue.is_empty(), "A queued command can be cancelled")
	for i in range(LifeSim.MAX_QUEUE):
		play.command(1, "play")
	res = play.command(1, "play")
	check(res.get("refused", false) and play.residents[1].queue.size() == LifeSim.MAX_QUEUE, "A full queue refuses more")
	play.residents[1].remaining = 0.0
	play.tick(1.0)
	check(play.residents[1].action == "play" and play.residents[1].queue.size() == LifeSim.MAX_QUEUE - 1, "The queue feeds the next action")
	play.residents[2].needs.energy = 5.0
	check(play.command(2, "work").get("refused", false), "An exhausted resident refuses to work")
	check(play.command(2, "sleep").ok, "An exhausted resident accepts sleep")
	play.residents[3].needs.energy = 99.0
	check(play.command(3, "sleep").get("refused", false), "A rested resident will not sleep on command")
	play.residents[0].needs.hunger = 4.0
	check(play.command(0, "play").get("refused", false) and play.command(0, "eat").ok, "A starving resident refuses fun but accepts food")
	play.food = 0
	play.meals = 0
	check(not play.command(1, "eat").ok, "Cannot order a meal from an empty pantry")
	check(play.drain_fx().size() > 0 and play.drain_fx().is_empty(), "Presentation events are produced then drained")
	# Targets: residents use their own home and the nearest suitable building.
	var sim := LifeSim.new()
	var r: Dictionary = sim.residents[0]
	sim.start_action(0, "sleep")
	check(int(r.target_id) == int(r.home) and r.target == "House", "Sleeping happens at the resident's own home")
	sim.start_action(0, "eat")
	check(sim.building_by_id(int(r.target_id)).kind == "market", "Eating happens at a market")
	check(sim.command(0, "play").ok, "Play has a destination")
	var bare := LifeSim.new()
	for b in bare.buildings.duplicate():
		if b.kind == "library":
			bare.buildings.erase(b)
			bare.map.clear_building_tile(bare.tile_of(b))
	check(not bare.has_target("study") and not bare.command(1, "study").ok and "study" not in bare.observation(0, "").allowed_actions, "Actions without a building are unavailable")


func test_social() -> void:
	var social := LifeSim.new()
	check(social.social_blocker(0, 1, "hug") != "" and social.social_blocker(0, 1, "chat") == "", "Hugging needs friendship, chatting does not")
	var before := social.relation(social.residents[0], "Mira")
	var chatted := social.resident_interact(0, 1, "chat")
	check(chatted.ok and social.relation(social.residents[0], "Mira") >= before + 1.0, "Chatting builds friendship")
	check(social.relation(social.residents[0], "Mira") == social.relation(social.residents[1], "Pip"), "Friendship is mutual")
	check(social.social_blocker(0, 1, "chat") == "Wait a little", "Repeating an interaction is on cooldown")
	var said := 0
	var emoted := 0
	for e in social.drain_fx():
		if e.type == "say": said += 1
		if e.type == "emote": emoted += 1
	check(said >= 2 and emoted >= 2, "Both residents speak and emote")
	social.residents[0].relations["Mira"] = 40.0
	social.residents[1].relations["Pip"] = 40.0
	check(social.social_blocker(0, 1, "hug") == "", "Friends can hug")
	social.resident_interact(0, 1, "argue")
	check(social.relation(social.residents[0], "Mira") < 40.0, "Arguing damages friendship")
	check(Social.bond_label(0.0) == "Stranger" and Social.bond_label(35.0) == "Friend" and Social.bond_label(90.0) == "Best friend", "Friendship levels")
	var pip: Dictionary = social.residents[0]
	var bond_before := float(pip.bond)
	var res := social.player_interact(0, "hug")
	check(not res.ok and res.message.contains("friendship"), "A hug is locked until the chief is a friend")
	res = social.player_interact(0, "chat")
	check(res.ok and float(pip.bond) > bond_before, "Chatting with the chief raises the bond")
	res = social.player_interact(0, "chat")
	check(not res.ok and res.message.contains("Wait"), "Chief interactions have cooldowns")
	pip.needs.hunger = 30.0
	var meals_before := social.meals
	res = social.player_interact(0, "share_meal")
	check(res.ok and social.meals == meals_before - 1 and pip.needs.hunger > 60.0, "Sharing a meal feeds the resident")
	pip.needs.hunger = 10.0
	check(social.emotion(pip) == "hungry", "Emotion follows the lowest need")
	check(Social.chat_reply("Zed", "Quiet dreamer", "happy", "tell me more", social.rng).length() > 5, "Residents without personal lines still reply")
	check(social.residents[1].wants.size() == 2, "Residents always have two wishes")
	var wisher: Dictionary = social.residents[1]
	wisher.wants = [{"kind": "do", "action": "play", "goal": 1, "base": 0, "points": 15, "text": "Play 1 times"}]
	wisher.counts["play"] = 1
	social._check_wants(wisher)
	check(wisher.points == 15 and wisher.wants.size() == 2, "Fulfilling a wish grants points and a new wish")


func test_population_and_council() -> void:
	var sim := LifeSim.new()
	sim.money = 3000
	sim.wood = 100
	sim.food = 200
	for r in sim.residents:
		for n in r.needs:
			r.needs[n] = 90.0
	check(sim.residents.size() == 4, "Four residents to begin with")
	sim._maybe_immigrate()
	check(sim.residents.size() == 5 and sim.residents[4].home >= 0, "Newcomers move into free beds")
	sim._maybe_immigrate()
	sim._maybe_immigrate()
	check(sim.residents.size() <= sim.housing(), "Population never exceeds housing")
	var crowded := LifeSim.new()
	for i in range(6):
		crowded._spawn_resident()
	check(crowded.residents.size() <= crowded.housing(), "No beds, no arrivals")
	var hungry := LifeSim.new()
	hungry.food = 0
	hungry.meals = 0
	check(not hungry._spawn_resident(), "Newcomers need food in the larder")
	# The council reads the town's needs.
	var needy := LifeSim.new()
	needy.money = 4000
	needy.wood = 100
	needy.food = 300
	for i in range(2):
		needy._spawn_resident()
	var needs := CityPlanner.needs(needy)
	check(float(needs.home) > 0.3, "A full town needs homes")
	var options := CityPlanner.options(needy)
	check(not options.is_empty() and float(options[0].score) >= float(options[options.size() - 1].score), "Plans are sorted best first")
	var kinds := {}
	for o in options:
		kinds[o.type] = true
		check(o.has("label") and o.has("reason") and o.has("coins"), "Every plan explains itself")
	check(kinds.has("build") and kinds.has("expand"), "The council can propose building and expanding")
	var top: Dictionary = options[0]
	var buildings_before := needy.buildings.size()
	var districts_before := needy.map.claimed.size()
	var result := needy.apply_option(top)
	check(result != "" and (needy.buildings.size() > buildings_before or needy.map.claimed.size() > districts_before), "Applying a plan changes the town")
	check(needy.decisions.size() == 1 and needy.decisions[0].by == "Council", "Decisions are recorded")
	check(needy.apply_option({"type": "build", "kind": "home", "tile": [1, 1], "label": "x"}).length() > 0 and needy.decisions.size() == 1, "Invalid plans are rejected and not recorded")
	var broke := LifeSim.new()
	broke.money = 20
	check(CityPlanner.options(broke).is_empty(), "A broke council proposes nothing")
	var manual := LifeSim.new()
	manual.auto_plan = false
	manual.money = 5000
	manual.wood = 100
	manual._new_day()
	check(manual.decisions.is_empty(), "With auto-planning off the council waits for the chief")
	var observation: Dictionary = needy.observation(0, "")
	check(observation.city.population == needy.residents.size() and observation.city.has("free_lots"), "The AI sees a city summary")


func test_saves() -> void:
	var sim := LifeSim.new()
	sim.money = 3000
	sim.wood = 80
	sim.place_building("home", Vector2i(5, 1))
	sim.claim_district(Vector2i(0, 1))
	sim.residents[0].queue = ["cook"]
	sim.tick(600.0)
	var data: Variant = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var loaded := LifeSim.new()
	check(loaded.load_data(data), "A save round-trips")
	check(loaded.buildings.size() == sim.buildings.size() and loaded.map.claimed.size() == sim.map.claimed.size(), "Buildings and land survive a save")
	check(loaded.money == sim.money and loaded.residents.size() == sim.residents.size(), "Resources and residents survive a save")
	check(loaded.map.occupied.has(Vector2i(5, 1)) and not loaded.map.is_buildable(Vector2i(5, 1)), "Occupied lots are restored")
	check(loaded.residents[0].queue == ["cook"] or loaded.residents[0].queue.is_empty(), "Queues survive a save")
	var path := loaded.map.find_path(Vector2i(0, 0), Vector2i(8, 4))
	check(not path.is_empty(), "Navigation works after loading")
	var bad: Variant = JSON.parse_string(JSON.stringify(sim.to_dict()))
	bad.buildings[0].level = 99
	check(not LifeSim.new().load_data(bad), "Out-of-range levels are rejected")
	bad = JSON.parse_string(JSON.stringify(sim.to_dict()))
	bad.map.claimed = []
	check(not LifeSim.new().load_data(bad), "A save with no land is rejected")
	bad = JSON.parse_string(JSON.stringify(sim.to_dict()))
	bad.residents[0].needs.hunger = "bad"
	check(not LifeSim.new().load_data(bad), "Malformed needs are rejected")
	bad = JSON.parse_string(JSON.stringify(sim.to_dict()))
	bad.residents[0].queue = ["teleport"]
	check(not LifeSim.new().load_data(bad), "Unknown queued actions are rejected")
	bad = JSON.parse_string(JSON.stringify(sim.to_dict()))
	bad.buildings.append(bad.buildings[0].duplicate(true))
	check(not LifeSim.new().load_data(bad), "Duplicate building ids are rejected")
	check(not LifeSim.new().load_data({"version": 1}), "Unknown versions are rejected")
	# Saves from the old fixed-layout village migrate: people and memories survive, the city is rebuilt.
	var old := {"version": 2, "minutes": 5000.0, "money": 900, "food": 40, "wood": 30, "meals": 9, "harvest": 50.0, "residents": []}
	for i in range(4):
		var needs := {}
		for n in LifeSim.NEEDS:
			needs[n] = 60.0
		old.residents.append({"name": "Old%d" % i, "needs": needs, "skills": {"craft": 61.0, "cooking": 0.0, "gardening": 5.0, "knowledge": 0.0, "fitness": 0.0}, "relations": {"Old0": 40.0}, "memory": ["Day 2: hello"], "career": 3, "earned": 100, "completed": 12, "bond": 33.0, "points": 40, "counts": {"play": 3}})
	var migrated := LifeSim.new()
	check(migrated.load_data(old), "Old saves migrate")
	check(migrated.residents.size() == 4 and migrated.residents[1].skills.craft == 61.0 and migrated.residents[2].memory[0] == "Day 2: hello" and float(migrated.residents[0].bond) == 33.0, "Migration keeps people, skills, memories and bonds")
	check(migrated.buildings.size() == 9 and migrated.map.claimed.size() == 2 and migrated.money >= 900, "Migration rebuilds the town and keeps the money")
	old.residents.pop_back()
	check(not LifeSim.new().load_data(old), "Malformed old saves are rejected")


func test_long_run() -> void:
	var sim := LifeSim.new()
	for i in range(30 * 1440):
		sim.tick(1.0)
		if i % 720 == 0:
			for r in sim.residents:
				for value in r.needs.values():
					if value < 0 or value > 100:
						check(false, "A need escaped valid bounds")
	check(sim.food >= 0 and sim.meals >= 0 and sim.money >= 0 and sim.wood >= 0, "Economy stays non-negative for 30 days")
	check(sim.residents.size() > 12, "The town grows well beyond the first four residents (got %d)" % sim.residents.size())
	check(sim.residents.size() <= sim.housing(), "Everyone has a bed")
	check(sim.stage() >= 2, "The town reaches at least Town stage in 30 days (is %s)" % sim.stage_name())
	check(sim.map.claimed.size() >= 3, "The council claims more land as the town grows")
	var kinds := {}
	for b in sim.buildings:
		kinds[b.kind] = true
	check(kinds.has("farm") and kinds.has("market") and kinds.has("workshop") and kinds.has("park"), "The council builds a balanced town")
	check(sim.decisions.size() > 0, "The council records its decisions")
	check(sim.goals.harvest and sim.goals.skilled and sim.goals.builder, "Milestones are reached")
	for i in range(sim.residents.size()):
		var r: Dictionary = sim.residents[i]
		check(r.memory.size() <= 12 and r.completed > (20 if i < 4 else 0), "%s lives an active life" % r.name)
	check(sim.journal.size() <= 60, "The journal is bounded")
	var friendships := 0
	var points := 0
	for r in sim.residents:
		points += int(r.points)
		for score in r.relations.values():
			if float(score) >= 30.0:
				friendships += 1
	check(friendships > 0 and points > 0, "Residents make friends and fulfil wishes")
