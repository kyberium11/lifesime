extends SceneTree
## Professions, wages, shifts, shop ownership, savings, medicine and the clinic loop.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _rich(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 4000
	sim.food = 200
	sim.wood = 200
	sim.stage_floor = 2
	for r in sim.residents:
		r.values = ["Community"]
		r.skills.cooking = 40.0
	return sim


func _build_done(sim: LifeSim, kind: String) -> Dictionary:
	var spot := Orders._spot_near_chief(sim, kind)
	sim.place_building(kind, spot)
	var b: Dictionary = sim.buildings[sim.buildings.size() - 1]
	b.level = 1
	b.target = 0
	b.progress = 100.0
	return b


func _init() -> void:
	var sim := _rich()
	# openings depend on what the village has
	check(Jobs.openings(sim, "farmer") >= 2 and Jobs.openings(sim, "shopkeeper") == 1, "farms and markets create openings")
	check(Jobs.openings(sim, "doctor") == 0, "no clinic, no doctor post")
	check(not Jobs.assign(sim, 0, "doctor").ok, "you cannot hire a doctor without a clinic")
	check(not Jobs.assign(sim, 0, "wizard").ok, "unknown trades are refused")
	# assigning
	var pip: Dictionary = sim.residents[0]
	var hired := Jobs.assign(sim, 0, "farmer")
	check(hired.ok and Jobs.title_of(pip) == "farmer" and int(pip.employer) >= 0, "a farmer is hired onto a farm: " + str(hired.message))
	check(not Jobs.assign(sim, 0, "farmer").ok, "they already hold the job")
	var shop := Jobs.assign(sim, 1, "shopkeeper")
	var market: Dictionary = sim.building_by_id(int(sim.residents[1].employer))
	check(shop.ok and str(market.get("owner", "")) == str(sim.residents[1].name), "the shopkeeper owns the shop")
	check(not Jobs.assign(sim, 2, "shopkeeper").ok, "one market has one shopkeeper")
	var child := _rich(2)
	child.residents[0].age = 9
	check(not Jobs.assign(child, 0, "farmer").ok, "children cannot work")
	# shifts
	check(Jobs.in_shift("farmer", 10.0) and not Jobs.in_shift("farmer", 22.0), "farmers work by day")
	check(Jobs.in_shift("guard", 23.0) and Jobs.in_shift("guard", 3.0) and not Jobs.in_shift("guard", 12.0), "guards work nights (shifts wrap past midnight)")
	sim.minutes = 1440.0 + 10.0 * 60.0
	check(Jobs.preferred_action(sim, pip) == "farm", "on shift a farmer goes to the farm")
	sim.minutes = 1440.0 + 22.0 * 60.0
	check(Jobs.preferred_action(sim, pip) == "", "off shift there is nothing to do for work")
	# choose_action follows the job
	sim.minutes = 1440.0 + 10.0 * 60.0
	pip.needs.hunger = 90.0
	pip.needs.energy = 90.0
	pip.needs.hygiene = 90.0
	pip.needs.social = 90.0
	pip.needs.fun = 90.0
	pip.needs.health = 90.0
	var farm_picks := 0
	for i in range(60):
		if sim.choose_action(pip) == "farm":
			farm_picks += 1
	check(farm_picks > 35, "a farmer on shift usually chooses farm work (%d/60)" % farm_picks)
	# payroll: wages from the treasury, part saved
	var coins := sim.money
	var savings := int(pip.savings)
	Jobs.payroll(sim)
	check(sim.money < coins and int(pip.savings) > savings, "wages come from the treasury and part is saved")
	var broke := _rich(3)
	Jobs.assign(broke, 0, "farmer")
	broke.money = 10
	var stress := float(broke.residents[0].stress)
	Jobs.payroll(broke)
	check(float(broke.residents[0].stress) > stress and broke.money == 10, "an empty treasury leaves workers unpaid and unhappy")
	# savings buy furniture for the resident's own home
	var rich_resident := _rich(4)
	var rr: Dictionary = rich_resident.residents[0]
	rr.savings = 500
	var before := Ownership.summary(rich_resident, str(rr.name))
	var bought := false
	for i in range(40):
		Jobs._spend_savings(rich_resident, rr)
		if Ownership.summary(rich_resident, str(rr.name)) != before:
			bought = true
			break
	check(bought and int(rr.savings) < 500, "residents spend savings on their own homes")
	# fill vacancies automatically and prune dead posts
	var auto := _rich(5)
	var filled := Jobs.fill_vacancies(auto)
	check(filled > 0, "empty posts are filled automatically (%d)" % filled)
	var holders := 0
	for title in Jobs.JOBS:
		holders += Jobs.holders(auto, title).size()
	check(holders == filled, "each post has one holder")
	var farm_b: Dictionary = auto.buildings_of("farm")[0]
	auto.buildings.erase(farm_b)
	Jobs.prune(auto)
	check(Jobs.holders(auto, "farmer").size() <= Jobs.openings(auto, "farmer"), "posts that no longer exist are closed")
	# dismissing
	var dismissed := Jobs.dismiss(sim, 0)
	check(dismissed.ok and Jobs.title_of(pip) == "", "a dismissed worker has no job")
	Jobs.dismiss(sim, 1)
	check(str(market.get("owner", "")) == "", "and gives up the shop")
	# suitability prefers skill and temperament
	var gardener := {"skills": {"gardening": 50.0, "fitness": 0.0, "craft": 0.0, "knowledge": 0.0, "cooking": 0.0}, "trait": "Curious gardener", "values": [], "age": 30, "profession": ""}
	var bookworm := {"skills": {"gardening": 0.0, "fitness": 0.0, "craft": 0.0, "knowledge": 60.0, "cooking": 0.0}, "trait": "Creative bookworm", "values": [], "age": 30, "profession": ""}
	check(Jobs.suitability(gardener, "farmer") > Jobs.suitability(bookworm, "farmer"), "a gardener suits farming better than a bookworm")
	check(Jobs.suitability(bookworm, "librarian") > Jobs.suitability(gardener, "librarian"), "a bookworm suits the library")
	# the clinic loop: doctor and medicine
	var clinic_sim := _rich(6)
	var clinic := _build_done(clinic_sim, "clinic")
	check(Jobs.openings(clinic_sim, "doctor") == 1, "a clinic opens a doctor post")
	var doc := Jobs.assign(clinic_sim, 0, "doctor")
	check(doc.ok, "a doctor is hired: " + str(doc.message))
	var doctor: Dictionary = clinic_sim.residents[0]
	clinic_sim.minutes = 1440.0 + 9.0 * 60.0
	clinic_sim.last_day = clinic_sim.day()
	doctor.needs.hunger = 90.0
	doctor.needs.energy = 90.0
	check(clinic_sim.medicine == 0, "no medicine yet")
	check(clinic_sim.command(0, "work").ok, "the doctor is ordered to work")
	for i in range(300):
		clinic_sim.tick(2.0)
		if clinic_sim.medicine > 0:
			break
	check(clinic_sim.medicine > 0, "a doctor at work makes medicine (%d)" % clinic_sim.medicine)
	# treatment is better with medicine and a doctor
	var patient_sim := _rich(7)
	var pc := _build_done(patient_sim, "clinic")
	Jobs.assign(patient_sim, 0, "doctor")
	patient_sim.medicine = 2
	var patient: Dictionary = patient_sim.residents[1]
	Health.infect(patient_sim, 1, "flu")
	patient.needs.health = 40.0
	patient_sim.minutes = 1440.0 + 9.0 * 60.0
	patient_sim.last_day = patient_sim.day()
	check(patient_sim.command(1, "treat").ok, "the patient goes to the clinic")
	for i in range(400):
		patient_sim.tick(2.0)
		if float(patient.ill_until) == 0.0:
			break
	check(float(patient.ill_until) == 0.0 and patient_sim.medicine < 2, "medicine cures the flu and is used up")
	var bare := _rich(7)
	_build_done(bare, "clinic")
	var sick: Dictionary = bare.residents[1]
	Health.infect(bare, 1, "flu")
	var left_before := float(sick.ill_until) - bare.minutes
	bare.minutes = 1440.0 + 9.0 * 60.0
	bare.last_day = bare.day()
	sick.ill_until = bare.minutes + left_before
	bare.command(1, "treat")
	for i in range(400):
		bare.tick(2.0)
		if bare.log_has("only rest"):
			break
	check(float(sick.ill_until) == 0.0 or float(sick.ill_until) - bare.minutes < left_before, "without doctor or medicine the clinic only helps a little")
	# medicine can be traded
	var trade := _rich(8)
	trade.medicine = 5
	check(Economy.trade(trade, "sell", "medicine", 3).ok and trade.medicine == 2, "medicine sells at the market")
	check(Economy.trade(trade, "buy", "medicine", 2).ok and trade.medicine == 4, "and can be bought")
	# orders
	var o := _rich(9)
	var named: String = o.residents[1].name
	var order := Orders.parse("make %s the shopkeeper" % named, o)
	check(order.intent == "assign_job" and order.title == "shopkeeper", "hire order parses")
	check(Orders.parse("hire %s as a farmer" % named, o).title == "farmer", "hire as a farmer parses")
	check(Orders.parse("fire %s" % named, o).intent == "dismiss_job", "fire order parses")
	check(Orders.parse("find everyone a job", o).intent == "fill_jobs", "fill jobs parses")
	check(Orders.execute(o, order, 0).ok and Jobs.title_of(o.residents[1]) == "shopkeeper", "the hire order is carried out")
	check(Orders.execute(o, Orders.parse("fire %s" % named, o), 0).ok and Jobs.title_of(o.residents[1]) == "", "the fire order is carried out")
	check(Orders.execute(o, Orders.parse("find everyone a job", o), 0).ok, "the fill order is carried out")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(auto.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with jobs loads")
	var kept := 0
	for r in back.residents:
		if Jobs.title_of(r) != "":
			kept += 1
	check(kept == holders - 1 or kept == holders or kept > 0, "jobs survive saving (%d)" % kept)
	check(back.medicine == auto.medicine, "medicine survives saving")
	print("JOBS TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
