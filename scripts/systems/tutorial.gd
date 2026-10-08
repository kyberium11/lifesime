class_name Tutorial
extends RefCounted
## The first-run checklist. Steps are ticked off as the player does them, and remembered in the settings.

const STEPS := [
	{"id": "move", "text": "Walk the chief around (W A S D, hold Shift to run)"},
	{"id": "talk", "text": "Talk to a resident (click them, then Talk, or press T)"},
	{"id": "order", "text": "Give an order (O) such as \"chop wood\""},
	{"id": "advice", "text": "Answer a resident who comes to ask for advice"},
	{"id": "market", "text": "Open the market (K) and trade"},
	{"id": "enter", "text": "Go inside a building (stand at its door and press E)"},
	{"id": "journal", "text": "Read the village journal (J)"},
	{"id": "photo", "text": "Take a photo (P)"},
]


static func is_done(id: String) -> bool:
	return id in (GameSettings.value("tutorial_done") as Array)


static func mark(id: String) -> bool:
	if is_done(id):
		return false
	(GameSettings.value("tutorial_done") as Array).append(id)
	return true


static func remaining() -> int:
	var n := 0
	for s in STEPS:
		if not is_done(str(s.id)):
			n += 1
	return n


static func reset() -> void:
	GameSettings.set_value("tutorial_done", [])
	GameSettings.set_value("tutorial_hidden", false)
