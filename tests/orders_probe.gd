extends SceneTree

func _init() -> void:
	var sim := LifeSim.new()
	var names: Array = []
	for r in sim.residents:
		names.append(r.name)
	print("residents: ", names)
	var n: String = names[0]
	for phrase in [
		"Everyone follow me", "stop following me", "Stay here", "everyone gather round", "gather wood", "everyone go to bed",
		"stop talking", "build a house", "build two farms", "upgrade the market", "expand the village", "everyone get back to work",
		"%s, go farm" % n, "How are you today?", "I love farming", "farm", "can you cook dinner?", "hold a festival", "pause the game",
		"how is everyone doing?", "meet at the plaza", "go home", "carry on", "let the council decide", "what should we build?",
		"build something", "claim more land", "everyone study at the library", "keep talking", "Did you eat?", "all of you exercise", "go to the park",
	]:
		var o := Orders.parse(phrase, sim)
		print("%-34s -> %s %s %s" % [phrase, o.intent, o.scope, o.get("action", o.get("kind", ""))])
	quit()
