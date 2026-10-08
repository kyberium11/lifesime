class_name ConversationDirector
extends Node
## Stages conversations you can see and hear.
##  - Resident-to-resident scenes: the two residents stop, face each other and trade lines written by the
##    AI (or by the offline writer), each spoken aloud in that resident's own voice. Lines play strictly
##    one after another: the next speaker waits for the previous voice to finish.
##  - Replies to the chief: the resident turns to you and answers out loud.
## Scenes only play near the chief (that is where you can see and hear them); elsewhere the town carries on.

signal overheard(speaker: int, listener: int, text: String)
signal line_started(speaker: int, text: String, utterance: int)
signal line_ended(speaker: int, utterance: int)
signal scene_started(a: int, b: int)
signal scene_ended(a: int, b: int, summary: String)

const HEARING_DISTANCE := 26.0
const MIN_SECONDS_BETWEEN_SCENES := 14.0
const MAX_QUEUED := 3
const AI_WAIT := 11.0
const LINE_GAP := 0.35
const SCENE_TIMEOUT := 80.0

var sim: LifeSim
var voice: VoiceService
var ai: AiClient
var use_ai := true
var last_source := "offline"
var scenes: Array = []

var _next_scene := 1
var silenced_until := 0.0
var _last_scene_end := -100.0
var _chief_speaking: Dictionary = {}  # utterance id -> resident index


func setup(sim_: LifeSim, voice_: VoiceService, ai_: AiClient) -> void:
	sim = sim_
	voice = voice_
	ai = ai_
	voice.utterance_ended.connect(_on_utterance_ended)
	ai.completed.connect(_on_ai_completed)
	ai.failed.connect(_on_ai_failed)


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func active_scene() -> Dictionary:
	for s in scenes:
		if s.state == "playing":
			return s
	return {}


func in_scene(resident: int) -> bool:
	for s in scenes:
		if s.a == resident or s.b == resident:
			return true
	return false


## A resident interaction happened (sim fx event {type: conversation, a, b, kind, success, summary}).
func begin_scene(event: Dictionary) -> bool:
	var a := int(event.a)
	var b := int(event.b)
	if now() < silenced_until:
		return false
	if a >= sim.residents.size() or b >= sim.residents.size() or in_scene(a) or in_scene(b):
		return false
	var middle := (Vector2(sim.residents[a].pos[0], sim.residents[a].pos[1]) + Vector2(sim.residents[b].pos[0], sim.residents[b].pos[1])) * 0.5
	if middle.distance_to(sim.chief_pos) * CityMap.TILE > HEARING_DISTANCE:
		return false
	if scenes.size() >= MAX_QUEUED or now() - _last_scene_end < MIN_SECONDS_BETWEEN_SCENES and scenes.is_empty():
		return false
	var scene := {"id": _next_scene, "a": a, "b": b, "kind": str(event.kind), "success": bool(event.success), "summary": str(event.get("summary", "")), "state": "waiting", "lines": [], "index": 0, "utterance": -1, "gap": 0.0, "born": now(), "asked": now()}
	_next_scene += 1
	scenes.append(scene)
	sim.talking[a] = "listen"
	sim.talking[b] = "listen"
	sim.talk_with[a] = b
	sim.talk_with[b] = a
	if use_ai and ai.enabled:
		ai.request("talk", Dialogue.payload(sim, a, b, scene.kind, scene.success), scene.id, AI_WAIT)
	else:
		_use_offline(scene)
	return true


func _find(id: int) -> Dictionary:
	for s in scenes:
		if int(s.id) == id:
			return s
	return {}


func _on_ai_completed(_id: int, kind: String, data: Dictionary, tag: Variant) -> void:
	if kind != "talk":
		return
	var scene := _find(int(tag))
	if scene.is_empty() or not scene.lines.is_empty():
		return
	var lines: Array = []
	for e in data.get("lines", []):
		lines.append({"speaker": int(e.speaker), "text": str(e.text)})
	if lines.size() < 2:
		_use_offline(scene)
		return
	scene.lines = lines
	if str(data.get("summary", "")) != "":
		scene.summary = str(data.summary)
	scene.source = "ai"
	scene.state = "ready"


func _on_ai_failed(_id: int, kind: String, _reason: String, tag: Variant) -> void:
	if kind != "talk":
		return
	var scene := _find(int(tag))
	if not scene.is_empty() and scene.lines.is_empty():
		_use_offline(scene)


func _use_offline(scene: Dictionary) -> void:
	var script := Dialogue.build(sim, int(scene.a), int(scene.b), str(scene.kind), bool(scene.success))
	scene.lines = script.lines
	scene.summary = script.summary
	scene.source = "offline"
	scene.state = "ready"


func _process(dt: float) -> void:
	var playing := active_scene()
	for s in scenes.duplicate():
		if now() - float(s.born) > SCENE_TIMEOUT:
			_finish(s)
			continue
		if s.state == "ready" and playing.is_empty():
			s.state = "playing"
			s.gap = 0.15
			playing = s
			scene_started.emit(int(s.a), int(s.b))
	if not playing.is_empty():
		_step(playing, dt)


func _step(scene: Dictionary, dt: float) -> void:
	if int(scene.utterance) >= 0:
		return
	scene.gap = float(scene.gap) - dt
	if float(scene.gap) > 0.0:
		return
	if int(scene.index) >= scene.lines.size():
		_finish(scene)
		return
	var line: Dictionary = scene.lines[int(scene.index)]
	var speaker := int(scene.a) if int(line.speaker) == 0 else int(scene.b)
	var listener := int(scene.b) if int(line.speaker) == 0 else int(scene.a)
	sim.talking[speaker] = "speak"
	sim.talking[listener] = "listen"
	last_source = str(scene.get("source", "offline"))
	var id := voice.speak(str(line.text), voice.profile_for(sim.residents[speaker], _scene_emotion(scene, speaker)))
	scene.utterance = id
	scene.speaker = speaker
	overheard.emit(speaker, listener, str(line.text))
	line_started.emit(speaker, str(line.text), id)


## How a line should sound: the scene's mood wins (an argument is angry, a joke is cheerful), else the speaker's own feeling.
func _scene_emotion(scene: Dictionary, speaker: int) -> String:
	match str(scene.kind):
		"argue":
			return "angry"
		"joke":
			return "excited"
		"hug", "compliment":
			if bool(scene.success):
				return "happy"
	return sim.emotion(sim.residents[speaker])


func _on_utterance_ended(id: int) -> void:
	if _chief_speaking.has(id):
		var who: int = _chief_speaking[id]
		_chief_speaking.erase(id)
		sim.talking.erase(who)
		sim.talk_with.erase(who)
		line_ended.emit(who, id)
		return
	for s in scenes:
		if int(s.utterance) == id:
			line_ended.emit(int(s.speaker), id)
			s.utterance = -1
			s.index = int(s.index) + 1
			s.gap = LINE_GAP
			return


func _finish(scene: Dictionary) -> void:
	scenes.erase(scene)
	sim.talking.erase(int(scene.a))
	sim.talking.erase(int(scene.b))
	sim.talk_with.erase(int(scene.a))
	sim.talk_with.erase(int(scene.b))
	if int(scene.utterance) >= 0:
		voice.stop_speaking()
	_last_scene_end = now()
	var a: Dictionary = sim.residents[int(scene.a)]
	var b: Dictionary = sim.residents[int(scene.b)]
	var summary := str(scene.summary)
	if summary != "":
		sim.remember(a, summary)
		sim.remember(b, summary)
	var emote_kind := "speech"
	if scene.kind == "argue":
		emote_kind = "anger"
	elif scene.kind == "joke":
		emote_kind = "laugh"
	elif bool(scene.success) and scene.kind in ["hug", "compliment"]:
		emote_kind = "heart"
	sim.emote(int(scene.a), emote_kind)
	scene_ended.emit(int(scene.a), int(scene.b), summary)


## The chief asks for quiet: every conversation ends now and residents stay quiet for a while.
func hush(seconds: float = 150.0) -> void:
	silenced_until = now() + seconds
	for s in scenes.duplicate():
		if int(s.utterance) >= 0:
			line_ended.emit(int(s.speaker), int(s.utterance))
			s.utterance = -1
		_finish(s)
	for id in _chief_speaking.keys():
		var who: int = _chief_speaking[id]
		_chief_speaking.erase(id)
		sim.talking.erase(who)
		sim.talk_with.erase(who)
		line_ended.emit(who, int(id))
	voice.stop_speaking()


func unhush() -> void:
	silenced_until = 0.0


## A resident answers the chief out loud.
func speak_to_chief(resident: int, text: String) -> int:
	sim.talking[resident] = "speak_chief"
	sim.talk_with[resident] = -1
	var id := voice.speak(text, voice.profile_for(sim.residents[resident], sim.emotion(sim.residents[resident])))
	_chief_speaking[id] = resident
	line_started.emit(resident, text, id)
	return id
