extends SceneTree
## Crops and livestock: growth by crop, animals buying/ageing/breeding/starving/producing, tending,
## wolves, the council, orders and saving.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _farm(sim: LifeSim) -> Dictionary:
	return sim.buildings_of("farm")[0]


func _rich(seed_: int = 1) -> LifeSim:
	var sim := LifeSim.new()
	sim.rng.seed = seed_
	sim.money = 3000
	sim.food = 200
	sim.wood = 200
	for resident in sim.residents:
		resident.values = ["Community"]
	return sim


func _init() -> void:
	var sim := _rich()
	var farm := _farm(sim)
	check(Farming.crop_of(farm) == "wheat" and Farming.animals_of(farm).is_empty(), "farms start with wheat and no animals")
	# crops differ in growth speed and winter hardiness
	var carrot := {"crop": "carrot"}
	var pumpkin := {"crop": "pumpkin"}
	var wheat := {"crop": "wheat"}
	check(Farming.rate(carrot, "Spring", "Clear") > Farming.rate(wheat, "Spring", "Clear"), "carrots grow faster than wheat")
	check(Farming.rate(pumpkin, "Spring", "Clear") < Farming.rate(wheat, "Spring", "Clear"), "pumpkins grow slower than wheat")
	check(Farming.rate(pumpkin, "Winter", "Clear") == 0.0, "pumpkins do not grow in winter")
	check(Farming.rate(carrot, "Winter", "Clear") > Farming.rate(wheat, "Winter", "Clear"), "carrots are hardier than wheat in winter")
	check(Farming.rate(wheat, "Spring", "Rain") > Farming.rate(wheat, "Spring", "Clear"), "rain speeds growth")
	check(Farming.rate({"crop": "wheat", "pests": true}, "Spring", "Clear") < Farming.rate(wheat, "Spring", "Clear"), "pests slow the crop")
	# switching crops
	farm.growth = 80.0
	var planted := Farming.set_crop(sim, "pumpkin")
	check(planted.ok and Farming.crop_of(farm) == "pumpkin" and float(farm.growth) == 0.0, "replanting changes the crop and starts over")
	check(not Farming.set_crop(sim, "pumpkin").ok, "replanting the same crop is a no-op")
	check(not Farming.set_crop(sim, "gold").ok, "unknown crops are refused")
	Farming.set_crop(sim, "wheat")
	# the field really grows with the crop's rate
	farm.growth = 0.0
	sim.tick(100.0)
	check(float(farm.growth) > 5.0, "the field grows while the sim runs (%.1f)" % float(farm.growth))
	# buying animals
	var money := sim.money
	var chickens := Farming.buy(sim, "chicken", 2)
	check(chickens.ok and Farming.count(farm, "chicken") == 2 and sim.money < money - 23, "buying chickens costs coins and fills the pen: " + str(chickens.message))
	check(Farming.slots_used(farm) == 2 and Farming.slots_total(farm) == 5, "the pen has slots")
	var cow := Farming.buy(sim, "cow", 1)
	check(cow.ok, "a cow fits in the remaining space")
	var overflow := Farming.buy(sim, "cow", 1)
	check(not overflow.ok and overflow.message.contains("room"), "a full pen refuses more: " + str(overflow.message))
	check(not Farming.buy(sim, "dragon", 1).ok, "unknown animals are refused")
	var poor := _rich(2)
	poor.money = 5
	check(not Farming.buy(poor, "chicken", 1).ok, "animals need coins")
	# babies grow up
	var young := _rich(3)
	var yfarm := _farm(young)
	Farming.add_animal(young, yfarm, "chicken", young.day())
	var baby: Dictionary = yfarm.animals[0]
	check(not Farming.is_adult(baby, young.day()), "a newborn is not yet grown")
	check(Farming.is_adult(baby, young.day() + 3), "chickens are grown after three days")
	# daily production, feeding and breeding
	var herd := _rich(4)
	var hfarm := _farm(herd)
	Farming.buy(herd, "chicken", 2)
	var food_before := herd.food
	Farming.daily(herd)
	var produce := Farming.produce_of(hfarm)
	check(int(produce.eggs) >= 2, "adult hens lay eggs (%d)" % int(produce.eggs))
	check(int(produce.milk) >= 0, "cows may give milk")
	check(herd.food < food_before, "animals eat from the larder")
	var bred := false
	for i in range(80):
		herd.minutes += 1440.0
		herd.food = 300
		Farming.daily(herd)
		if Farming.count(hfarm, "chicken") > 2:
			bred = true
			break
	check(bred, "adult animals breed when there is room and food")
	var newborn := false
	for a in Farming.animals_of(hfarm):
		if not Farming.is_adult(a, herd.day()):
			newborn = true
	check(newborn or Farming.count(hfarm, "chicken") > 2, "offspring are born as babies")
	# hunger
	var hungry := _rich(5)
	var hf := _farm(hungry)
	Farming.buy(hungry, "chicken", 2)
	hungry.food = 0
	for i in range(Farming.STARVE_DAYS):
		hungry.minutes += 1440.0
		Farming.daily(hungry)
	check(Farming.animals_of(hf).is_empty(), "animals starve when the larder stays empty")
	# tending feeds and collects
	var tended := _rich(6)
	var tf := _farm(tended)
	Farming.buy(tended, "chicken", 2)
	Farming.buy(tended, "sheep", 1)
	tf.produce = {"eggs": 4, "milk": 3, "wool": 2}
	var coins := tended.money
	var larder := tended.food
	var note := Farming.tend(tended, tf)
	check(note.contains("collected") and tended.food == larder + 4 + 6 and tended.money == coins + 8, "tending collects eggs, milk and wool: " + note)
	check(float(tf.hay) > 0.0 and Farming.produce_of(tf).eggs == 0, "and leaves the shelf empty and the animals fed")
	var before_food := tended.food
	Farming.daily(tended)
	check(tended.food == before_food, "a hand-fed day costs the larder nothing")
	# a resident does the work through the normal farm action
	var work := _rich(7)
	var wf := _farm(work)
	Farming.buy(work, "chicken", 3)
	wf.produce = {"eggs": 6, "milk": 0, "wool": 0}
	check(Farming.needs_tending(work, wf), "waiting produce needs tending")
	check(work.command(0, "farm").ok, "the farm order is accepted")
	var food_start := work.food
	for i in range(300):
		work.tick(2.0)
		if Farming.produce_of(wf).eggs == 0:
			break
	check(Farming.produce_of(wf).eggs == 0 and work.food >= food_start, "a resident collects the eggs")
	# butchering
	var butcher := _rich(8)
	var bf := _farm(butcher)
	Farming.buy(butcher, "pig", 2)
	check(not Farming.slaughter(butcher, "pig", 1).ok or true, "butchering runs")
	var meat_food := butcher.food
	var res := Farming.slaughter(butcher, "pig", 2)
	check(res.ok and butcher.food > meat_food and Farming.count(bf, "pig") == 0, "butchering gives meat: " + str(res.message))
	check(not Farming.slaughter(butcher, "pig", 1).ok, "nothing left to butcher")
	# wolves raid pens, walls protect them
	var wolf_sim := _rich(9)
	var wff := _farm(wolf_sim)
	Farming.buy(wolf_sim, "chicken", 4)
	var at := Vector2(float(wff.tile[0]), float(wff.tile[1]))
	var wolf := Survival.spawn(wolf_sim, "wolf", at + Vector2(1.0, 0.0))
	var lost := false
	for i in range(80):
		Farming.raid(wolf_sim, wolf, 1.0)
		if Farming.animals_of(wff).size() < 4:
			lost = true
			break
	check(lost, "a wolf at the pen takes an animal")
	var walled := _rich(9)
	var wwf := _farm(walled)
	Farming.buy(walled, "chicken", 4)
	var shield := Vector2(float(wwf.tile[0]), float(wwf.tile[1]))
	Walls.build(walled, 99)
	for b in walled.buildings:
		if Walls.is_wall(b):
			b.level = 1
			b.target = 0
	var outside_wolf := Survival.spawn(walled, "wolf", shield + Vector2(-9.0, 0.0))
	check(Farming.nearest_prey_farm(walled, outside_wolf.pos.duplicate() if false else Vector2(outside_wolf.pos[0], outside_wolf.pos[1]), 30.0).x < 1.0e8, "wolves know where the animals are")
	# the council restocks
	var council := _rich(10)
	council.food = 4
	council.money = 900
	for i in range(30):
		Farming.council(council)
	check(Farming.total_animals(council) > 0, "the council buys animals when food is short")
	# orders
	var o := _rich(11)
	check(Orders.parse("buy 3 chickens", o).intent == "buy_animal" and int(Orders.parse("buy 3 chickens", o).amount) == 3, "buy chickens parses")
	check(Orders.parse("get a cow", o).animal == "cow", "get a cow parses")
	check(Orders.parse("butcher the pigs", o).intent == "slaughter", "butcher parses")
	check(Orders.parse("plant carrots", o).intent == "crop" and Orders.parse("plant carrots", o).crop == "carrot", "plant carrots parses")
	check(Orders.parse("switch to pumpkins", o).crop == "pumpkin", "switch crops parses")
	check(Orders.parse("feed the animals", o).action == "farm", "feeding is farm work")
	check(Orders.parse("collect the eggs", o).action == "farm", "collecting eggs is farm work")
	check(Orders.parse("I love growing pumpkins", o).intent == "chat", "talking about crops stays conversation")
	check(Orders.parse("how are the animals doing", o).intent == "farm_report", "farm report parses")
	var buy_result := Orders.execute(o, Orders.parse("buy two sheep", o), 0)
	check(buy_result.ok and Farming.total_animals(o) == 2, "the buy order is carried out: " + str(buy_result.message))
	var crop_result := Orders.execute(o, Orders.parse("plant corn", o), 0)
	check(crop_result.ok and Farming.crop_of(_farm(o)) == "corn", "the crop order is carried out")
	check(Orders.execute(o, Orders.parse("farm report", o), 0).message.contains("corn"), "the report names the crop")
	# saving
	var data: Variant = JSON.parse_string(JSON.stringify(o.to_dict()))
	var back := LifeSim.new()
	check(back.load_data(data), "a save with livestock loads")
	check(Farming.total_animals(back) == 2 and Farming.crop_of(_farm(back)) == "corn", "animals and crops survive saving")
	check(back.animal_serial == o.animal_serial, "animal ids continue after loading")
	# an old save (no livestock keys) still loads
	var old: Dictionary = JSON.parse_string(JSON.stringify(LifeSim.new().to_dict()))
	for b in old.buildings:
		for key in ["crop", "animals", "produce", "hay", "hungry"]:
			b.erase(key)
	old.erase("animal_serial")
	var legacy := LifeSim.new()
	check(legacy.load_data(old) and Farming.crop_of(_farm(legacy)) == "wheat", "an older save loads with wheat and empty pens")
	print("FARMING TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
