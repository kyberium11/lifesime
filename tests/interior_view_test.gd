extends SceneTree
## The interior scene: shell pieces, furniture nodes, residents inside, collision, door, queries.
## godot --headless --path . -s tests/interior_view_test.gd

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sim := LifeSim.new()
	sim.rng.seed = 3
	sim.money = 5000
	var art := CityArt.new()
	root.add_child(art)
	art.generate(sim)
	var home: Dictionary = sim.buildings_of("home")[0]
	Interiors.ensure(sim, home)
	var pip: Dictionary = sim.residents[0]
	pip.home = int(home.id)
	pip.action = "sleep"
	pip.target_id = int(home.id)
	pip.route = []
	pip.remaining = 600.0
	Ownership.refresh(sim, home)
	var view := InteriorView.new()
	root.add_child(view)
	view.setup(sim, art, home)
	for i in range(700):
		await process_frame
	check(view.position == InteriorView.ORIGIN, "the room sits away from the city")
	var items := Interiors.furniture_of(home)
	var furniture_nodes := 0
	for child in view.get_children():
		if child.has_meta("item_id"):
			furniture_nodes += 1
	check(furniture_nodes == items.size(), "every furniture item has a node (%d of %d)" % [furniture_nodes, items.size()])
	check(view.get_child_count() > items.size() + 40, "the shell has floor, walls and lights")
	# the sleeper is in the room, in their own bed
	check(view.actor_indices().has(0), "a resident who is inside appears in the room")
	var bed := Interiors.find_item(sim, home, "sleep", str(pip.name))
	var slot := Interiors.slot_of(bed)
	var anchor := view.actor_anchor(0)
	check(anchor != Vector3.ZERO and Vector2(anchor.x, anchor.z).distance_to(Vector2(view.to_world(slot.pos).x, view.to_world(slot.pos).z)) < 0.6, "the sleeper settles on their bed")
	# residents leaving disappear
	pip.action = "play"
	pip.target_id = -1
	for i in range(10):
		await process_frame
	check(not view.actor_indices().has(0), "when they go out they leave the room")
	# residents walk round the furniture
	for kind in ["home", "market", "workshop", "library", "bathhouse"]:
		var kb: Dictionary = sim.buildings_of(kind)[0]
		Interiors.ensure(sim, kb)
		var knav := InteriorNav.new()
		knav.build(kb)
		var start := Interiors.entrance(kb)
		var reached := 0
		var tried := 0
		for it in Interiors.furniture_of(kb):
			if str(it.role) in ["bed", "stove", "table", "sofa", "desk", "bench_work", "bath", "bookcase", "counter", "armchair"]:
				tried += 1
				var slot2 := Interiors.slot_of(it)
				var route := knav.path(start, slot2.pos)
				if not route.is_empty():
					reached += 1
					var clear := true
					for point in route:
						if not knav.is_open(point):
							clear = false
					check(clear, "%s: the route to the %s avoids furniture" % [kind, it.role])
		check(tried > 0 and reached >= tried - 1, "%s: people can walk to nearly every place (%d of %d)" % [kind, reached, tried])
	var hnav := InteriorNav.new()
	hnav.build(home)
	var stove_item := Interiors.find_item(sim, home, "cook", "")
	var there := hnav.path(Interiors.entrance(home), Interiors.slot_of(stove_item).pos)
	check(not there.is_empty() and there.size() < 40, "a route across the room is short and exists (%d steps)" % there.size())
	# a resident entering walks in rather than appearing
	pip.action = "cook"
	pip.target_id = int(home.id)
	pip.route = []
	pip.remaining = 600.0
	for i in range(3):
		await process_frame
	var walker_start := view.actor_anchor(0)
	var distances := []
	for i in range(60):
		await process_frame
		distances.append(view.actor_anchor(0))
	var travelled := 0.0
	for k in range(1, distances.size()):
		travelled += Vector2(distances[k].x, distances[k].z).distance_to(Vector2(distances[k - 1].x, distances[k - 1].z))
	check(travelled > 0.2, "a newly arrived resident walks to their place (%.2f units)" % travelled)
	pip.action = "play"
	pip.target_id = -1
	for i in range(5):
		await process_frame
	# collision
	var size := view.size
	check(view.blocked(Vector2(-0.5, 2.0)) and view.blocked(Vector2(size.x + 0.5, 2.0)), "the walls stop people")
	check(not view.blocked(Interiors.entrance(home)), "the entrance is open")
	check(not view.blocked(Vector2(Interiors.door_x(size), size.y + 0.4)), "the doorway lets people out")
	var fridge := {}
	for it in items:
		if str(it.model) == "kitchenFridge":
			fridge = it
	check(not fridge.is_empty() and view.blocked(Vector2(float(fridge.x), float(fridge.z))), "furniture blocks the way")
	# door queries
	check(view.at_door(Vector2(Interiors.door_x(size), size.y - 0.3)), "next to the door counts as at the door")
	check(not view.at_door(Vector2(1.0, 1.0)), "the far corner does not")
	# nearest item and tags
	var table := {}
	for it in items:
		if str(it.role) == "table":
			table = it
	var near := view.nearest_item(Vector2(float(table.x), float(table.z) + 0.2), 0.9)
	check(not near.is_empty(), "a table is found when standing next to it")
	check(view.item_anchor(table).y > 0.3, "item tags float above the furniture")
	# buying while inside shows up in the room
	var before := Interiors.furniture_of(home).size()
	var result := Ownership.furnish(sim, home, "loungeSofaLong", "")
	check(result.ok, "furnishing works: " + str(result.message))
	for i in range(5):
		await process_frame
	var after_nodes := 0
	for child in view.get_children():
		if child.has_meta("item_id"):
			after_nodes += 1
	check(Interiors.furniture_of(home).size() == before + 1 and after_nodes == before + 1, "the new furniture appears without rebuilding the room")
	# removing it takes it away
	Interiors.remove(home, int(result.item.id))
	for i in range(5):
		await process_frame
	var final_nodes := 0
	for child in view.get_children():
		if child.has_meta("item_id"):
			final_nodes += 1
	check(final_nodes == before, "removed furniture disappears")
	print("INTERIOR VIEW TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
