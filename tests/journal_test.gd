extends SceneTree
## Chronicle, yearly stories, save slots, settings, tutorial, and the journal/menu/photo UI.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sim := LifeSim.new()
	sim.rng.seed = 1
	sim.minutes = 3.0 * 1440.0
	Chronicle.add(sim, "birth", "Pip was born to A and B.")
	Chronicle.add(sim, "bogus", "Something odd")
	check(sim.chronicle.size() == 2 and sim.chronicle[1].kind == "growth", "unknown kinds fall back to growth")
	check(Chronicle.classify("Mira and Tom got married!") == "wedding" and Chronicle.classify("Day 3: Clear skies.") == "", "log lines are classified")
	sim.log_event("Mira and Tom got married!")
	check(Chronicle.entries(sim, "wedding").size() == 1, "log_event feeds the chronicle")
	check(Chronicle.year_of(1) == 1 and Chronicle.year_of(28) == 1 and Chronicle.year_of(29) == 2, "years are 28 days")
	check(Chronicle.story_offline(sim, 1).contains("Year 1"), "offline story reads out")
	check(Chronicle.facts(sim, 1).events.size() >= 2, "facts list events")
	# year rollover
	sim.minutes = 27.0 * 1440.0 + 600.0
	sim.last_day = sim.day()
	sim.minutes += 1440.0
	Chronicle.daily(sim)
	check(sim.stories.has("1") and sim.story_due == 1, "a finished year gets its story and is flagged")
	for i in range(Chronicle.MAX_ENTRIES + 20):
		Chronicle.add(sim, "job", "x")
	check(sim.chronicle.size() == Chronicle.MAX_ENTRIES, "the chronicle is capped")
	var back := LifeSim.new()
	check(back.load_data(JSON.parse_string(JSON.stringify(sim.to_dict()))) and back.chronicle.size() == sim.chronicle.size() and back.stories.has("1"), "chronicle survives saving")
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	old.erase("chronicle")
	old.erase("stories")
	check(LifeSim.new().load_data(old), "older saves load")
	# slots
	var dir := "user://test_slots"
	var s := LifeSim.new()
	check(SaveSlots.save(s, 2, dir) and SaveSlots.list(dir)[2].exists and not SaveSlots.list(dir)[0].exists, "saving fills one slot")
	check(SaveSlots.describe(SaveSlots.list(dir)[2]).contains("people") and SaveSlots.describe(SaveSlots.list(dir)[0]) == "Empty", "slots are described")
	var loaded := LifeSim.new()
	check(SaveSlots.load_into(loaded, 2, dir) and loaded.residents.size() == s.residents.size(), "a slot loads")
	check(not SaveSlots.save(s, 9, dir), "bad slot refused")
	check(SaveSlots.delete(2, dir) and not SaveSlots.list(dir)[2].exists, "a slot deletes")
	# settings
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	GameSettings.set_value("difficulty", "peaceful")
	check(GameSettings.monster_factor() == 0.0 and Survival.cap_for(s) == 0, "peaceful means no monsters")
	GameSettings.set_value("difficulty", "harsh")
	check(Survival.cap_for(s) >= 1, "harsh has monsters")
	GameSettings.set_value("difficulty", "normal")
	var spath := "user://test_settings.json"
	GameSettings.set_value("voice_volume", 40)
	check(GameSettings.save_to(spath), "settings save")
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	GameSettings.load_from(spath)
	check(int(GameSettings.value("voice_volume")) == 40, "settings load back")
	# tutorial
	Tutorial.reset()
	check(Tutorial.remaining() == Tutorial.STEPS.size() and Tutorial.mark("move") and not Tutorial.mark("move") and Tutorial.remaining() == Tutorial.STEPS.size() - 1, "tutorial steps tick off once")
	Tutorial.reset()
	# panels
	var journal := JournalPanel.new()
	journal.sim = sim
	root.add_child(journal)
	var menu := MenuPanel.new()
	menu.slot_dir = dir
	root.add_child(menu)
	var card := TutorialCard.new()
	root.add_child(card)
	var photo := PhotoMode.new()
	photo.photo_dir = "user://test_photos"
	root.add_child(photo)
	await process_frame
	journal.visible = true
	journal.refresh()
	check(journal._timeline.get_parsed_text().length() > 0, "journal shows the timeline")
	journal.show_ai_story(1, "A long and lovely story of the first year in the village.")
	check(journal.story_for(1).begins_with("A long"), "AI story replaces the offline one")
	var seen := []
	menu.setting_changed.connect(func(k: String, v: Variant) -> void: seen.append(k))
	menu.open()
	menu.slot_saved.connect(func(i: int) -> void: SaveSlots.save(s, i, dir))
	await process_frame
	check(menu.visible and menu._slot_box.get_child_count() == SaveSlots.COUNT, "menu lists every slot")
	menu._apply_setting("quality", "low")
	check(seen == ["quality"], "settings changes are announced")
	check(card.visible, "tutorial card shows at first")
	photo.enter()
	photo.cycle_filter(1)
	check(photo.filter == 1, "filters cycle")
	var path: String = await photo.take_photo()
	check(path != "" and FileAccess.file_exists(path), "a photo is saved")
	GameSettings.data = GameSettings.DEFAULTS.duplicate(true)
	print("JOURNAL TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
