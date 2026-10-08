extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var f := FileAccess.open(OS.get_environment("APPDATA") + "/Godot/app_userdata/Pocket Village/village3d.json", FileAccess.READ)
	var sim := LifeSim.new()
	sim.load_data(JSON.parse_string(f.get_as_text()))
	print("day ", sim.day(), " pop ", sim.residents.size(), " housing ", sim.housing(), " money ", sim.money, " mats ", sim.materials(), " stage ", sim.stage(), " free lots ", sim.map.free_lots().size(), " claimed ", sim.map.claimed.size())
	print("needs ", CityPlanner.needs(sim))
	var opts := CityPlanner.options(sim)
	print("options ", opts.size())
	for o in opts:
		print("  ", o.label, " score ", o.score, " coins ", o.coins)
	for d in sim.map.frontier():
		print("frontier ", d, " blocker '", sim.claim_blocker(d), "' cost ", sim.claim_cost(d))
	print("projects ", sim.projects().size(), " ask_chief ", sim.ask_chief, " auto ", sim.auto_plan)
	print("advice ", sim.advice.get("kind", "-"), " ", sim.advice.get("state", "-"))
	sim.ask_chief = true
	for i in range(30 * 1440 / 4):
		sim.tick(4.0)
	print("AFTER 30 days: day ", sim.day(), " pop ", sim.residents.size(), " housing ", sim.housing(), " buildings ", sim.buildings.size(), " claimed ", sim.map.claimed.size(), " money ", sim.money)
	quit()
