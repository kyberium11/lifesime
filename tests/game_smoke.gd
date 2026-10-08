extends SceneTree
## Drives the real game scene: HUD layout, pie menus, avatar interactions, chat, picking,
## growth visuals and saves. Run: godot --headless --path . --script tests/game_smoke.gd -- --fresh --nosave --offline

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		print("FAIL: " + message)


func _initialize() -> void:
	call_deferred("run")


func inside_viewport(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - 2 and rect.position.y >= bounds.position.y - 2 and rect.end.x <= bounds.end.x + 2 and rect.end.y <= bounds.end.y + 2


func pie_labels(game: Node) -> Array:
	return game.pie._items.map(func(item: Dictionary) -> String: return str(item.label))


func run() -> void:
	var game: Node = load("res://scenes/village3d.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var sim: LifeSim = game.sim
	var art: VillageArt = game.art
	var bounds := Rect2(Vector2.ZERO, game.get_viewport().get_visible_rect().size)

	# Pause freezes time.
	game.speed = 0
	var before: float = sim.minutes
	await process_frame
	check(sim.minutes == before, "Pause must freeze simulation")
	game.speed = 1.0

	# Layout: every visible HUD panel stays on screen.
	await process_frame
	for child in game.hud.root.get_children():
		if child is Control and child.visible:
			check(inside_viewport(child.get_global_rect(), bounds), "HUD panel %s stays on screen" % child.name)
	check(game.hud.portraits.size() == 4 and game.hud.portraits[0].texture() != null, "Live portraits render for every resident")

	# Selecting residents from the household cards.
	game.hud.resident_picked.emit(2, false)
	check(game.selected == 2, "Household card selects a resident")
	game._refresh_hud()
	check(game.hud._dock_name.text == "Theo", "Dock shows the selected resident")
	game.hud.resident_picked.emit(1, true)
	check(game.selected == 1 and game.follow, "Double click follows a resident")
	game.follow = false

	# Pie menu: categories, sub-menu and the walk-over interaction.
	game._open_resident_pie(2, Vector2(700, 400))
	check(game.pie.is_open() and game.pie._items.size() == 6, "Clicking a resident opens the pie menu")
	check(pie_labels(game).has("Social") and pie_labels(game).has("Needs") and pie_labels(game).has("Activities"), "Pie offers social, needs and activities")
	game.pie._activate(game.pie._items[0])
	check(game.pie.is_open() and game.pie._items.size() == 7 and pie_labels(game).has("Hug"), "Social sub-menu lists the interactions")
	check(not game.pie._items[4].enabled, "Hug is locked for a stranger")
	var chat_index := pie_labels(game).find("Chat")
	game.pie._activate(game.pie._items[chat_index])
	check(not game.pie.is_open() and not game.avatar_pending.is_empty(), "Choosing an interaction sends the avatar over")
	var theo: Dictionary = sim.residents[2]
	theo.action = "play"
	theo.remaining = 40.0
	theo.route = []
	art.avatar.position = Vector3(theo.pos[0] + 1.0, 0, theo.pos[1])
	var bond_before := float(theo.bond)
	game._update_avatar(0.1)
	check(game.avatar_pending.is_empty() and float(theo.bond) > bond_before, "The avatar chats and the bond grows")
	game.overlay.feed(sim.drain_fx())
	await process_frame
	check(game.overlay._bubbles.size() >= 1, "Speech bubbles appear over characters")

	# Commands from menus and from buildings.
	game._command(1, "study")
	check(sim.residents[1].action == "study" and sim.residents[1].commanded, "Needs/activities menu commands a resident")
	game.selected = 1
	game._open_facility_pie("Market", Vector2(700, 400))
	var facility_labels := pie_labels(game)
	check(facility_labels.has("Eat") and facility_labels.has("Upgrade") and facility_labels.has("Town"), "Clicking a building offers its actions")
	game.pie.close()

	# Picking residents, facilities and open ground.
	for a in art.actors:
		a.visible = false
	var market_screen: Vector2 = game.camera.unproject_position(Vector3(8, 0, -6))
	var hit: Dictionary = game.pick(market_screen)
	check(hit.type == "facility" and hit.place == "Market", "Picking a building returns the facility")
	var ground_hit: Dictionary = game.pick(game.camera.unproject_position(Vector3(18, 0, 18)))
	check(ground_hit.type == "ground", "Picking empty ground returns ground")
	art.actors[3].visible = true
	art.actors[3].position = Vector3(-12, 0, -12)
	var person_screen: Vector2 = game.camera.unproject_position(art.actors[3].position + Vector3(0, 1, 0))
	check(game.pick(person_screen).type == "resident" and game.pick(person_screen).index == 3, "Picking a character returns the resident")

	# Chat (offline replies).
	game.ai_enabled = false
	game._open_chat(0)
	check(game.hud.chat.visible, "Talk opens the conversation window")
	check(inside_viewport(game.hud.chat.get_global_rect(), bounds) and game.hud.chat.get_global_rect().position.y > 64, "Chat window stays on screen below the top bar")
	game.hud.chat._send("how are you?")
	var chat_log: Array = game.hud.chat._logs.get(0, [])
	var replied := false
	for m in chat_log:
		if not m.player:
			replied = true
	check(chat_log.size() >= 2 and replied, "The resident answers a chat message")
	game.hud.chat.close()

	# Every drawer tab builds and refreshes.
	for i in range(6):
		game.hud.show_tab(i)
		game._refresh_hud()
		await process_frame
		check(game.hud._pages[i].visible and inside_viewport(game.hud._pages[i].get_global_rect(), bounds), "Tab %d fits the drawer" % i)

	# Build mode and the placement preview.
	game.build_kind = "cottage"
	game._update_ghost()
	check(game.ghost.material_override != null, "Placement preview exists")
	game.build_kind = ""
	sim.build("garden", Vector2(-15, -14))
	art.update_buildings(sim)
	check(art.built_count == 1 and art.site_nodes[0].stage == 0, "A new building starts as a construction site")
	sim.buildings[0].progress = 100.0
	art.update_buildings(sim)
	check(art.site_nodes[0].stage == 4, "Finished construction becomes the real building")

	# Tier upgrades, scaffolding, stages and living scenery.
	check(art.facility_drawn["Market"] == 0, "Facilities start at tier 0")
	sim.facility_tier["Market"] = 2
	art.update_buildings(sim)
	check(art.facility_drawn["Market"] == 2, "Tier upgrades redraw the facility")
	sim.facility_xp["Library"] = 6
	sim.money = 400
	sim.wood = 20
	game.hud.upgrade_requested.emit("Library")
	check(sim.projects.size() == 1 and art.scaffold_key == "Library:1", "Upgrading from the UI raises scaffolding")
	sim.facility_tier["Home"] = 3
	sim.facility_tier["Workshop"] = 3
	sim.facility_tier["Market"] = 3
	art.update_buildings(sim)
	check(art.stage_drawn == sim.stage() and art.stage_drawn >= 1 and art.stage_sign.text.ends_with(["", "VILLAGE", "TOWN", "THRIVING TOWN"][sim.stage()]), "Village stage changes the environment")
	sim.harvest = 100.0
	art.sync(sim, 0, 0.1)
	check(art.crops_ripe, "Crops ripen with the harvest timer")
	sim.orchard = 90.0
	art.sync(sim, 0, 0.1)
	check(art.orchard_fruit[0].visible, "Orchard trees bear fruit")

	# Characters: faces, poses and building entry.
	art.set_expression(art.actors[0], "happy")
	check(art.actors[0].get_meta("emotion") == "happy", "Faces follow emotion")
	for mode in ["idle", "walk", "talk", "play", "exercise", "bend", "wave"]:
		art.pose(art.actors[0], mode, 1.3)
	sim.residents[0].action = "eat"
	sim.residents[0].target = "Market"
	sim.residents[0].route = []
	sim.residents[0].remaining = 20.0
	art.sync(sim, 0, 0.1)
	check(not art.actors[0].visible, "A resident using a building goes inside")
	sim.residents[0].action = "play"
	sim.residents[0].target = "Park"
	art.sync(sim, 0, 0.1)
	check(art.actors[0].visible, "...and comes back out")

	# Persistence.
	var save_path := "user://smoke_%d.json" % Time.get_ticks_usec()
	game.nosave = false
	check(game.save_game(save_path), "First save succeeds")
	var saved_money: int = sim.money
	check(game.save_game(save_path), "Atomic replacement succeeds")
	sim.money = 0
	game.load_game(save_path)
	check(sim.money == saved_money, "Save restores household")
	var corrupt := FileAccess.open(save_path, FileAccess.WRITE)
	corrupt.store_string("broken JSON")
	corrupt.close()
	sim.money = 0
	game.load_game(save_path)
	check(sim.money == saved_money, "Backup recovers corrupted primary save")
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path + ".bak")
	game.nosave = true
	game._shutdown()
	print("GAME SMOKE: %d failure(s)" % failures)
	quit(1 if failures else 0)
