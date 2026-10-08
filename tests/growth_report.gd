extends SceneTree
## Prints how the town develops day by day under the council (tune Catalog / CityPlanner with this).
## Run: godot --headless --path . --script tests/growth_report.gd -- [days]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 40
	var sim := LifeSim.new()
	var last_pop := -1
	for i in range(days * 1440):
		sim.tick(1)
		if i % 1440 == 1439:
			var kinds := {}
			var levels := 0
			for b in sim.buildings:
				if int(b.level) >= 1 and b.kind != "plaza":
					kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
					levels += int(b.level)
			var line := "day %2d  %-9s pop %2d/%2d  districts %2d  bldgs %2d (lvl %2d)  coins %5d mats %3d food %4d  mood %2d  %s" % [sim.day() - 1, sim.stage_name(), sim.residents.size(), sim.housing(), sim.map.claimed.size(), sim.buildings.size() - 1, levels, sim.money, sim.wood, sim.food + sim.meals * 2, int(sim.average_mood()), str(kinds).replace('"', "")]
			if sim.day() % 6 == 1:
				print(line)
			last_pop = sim.residents.size()
	print("decisions:")
	for d in sim.decisions:
		print("  day %d %s: %s" % [d.day, d.by, d.text])
	quit()
