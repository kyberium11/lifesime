extends SceneTree
## Neural voice check: Piper server starts, lines are synthesised and played in order, stop works.

var failures := 0
var started: Array = []
var ended: Array = []


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	call_deferred("run")


func _wait(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame


func run() -> void:
	var voice := VoiceService.new()
	root.add_child(voice)
	voice.utterance_started.connect(func(id: int) -> void: started.append(id))
	voice.utterance_ended.connect(func(id: int) -> void: ended.append(id))
	var waited := 0.0
	while not voice.piper_ready and waited < 40.0:
		await _wait(0.5)
		waited += 0.5
	check(voice.piper_ready, "piper server became ready (%.1fs)" % waited)
	var sim := LifeSim.new()
	var a := voice.profile_for(sim.residents[0], "happy")
	var b := voice.profile_for(sim.residents[1], "gloomy")
	check(not (a.piper as Dictionary).is_empty(), "profile has a piper voice")
	check(float(b.length) > float(a.length), "gloomy speech is slower than happy")
	var t0 := Time.get_ticks_msec()
	var first := voice.speak("Good morning, Chief! The harvest looks wonderful this year.", a)
	var second := voice.speak("I suppose so. I'm just tired.", b)
	var guard := 0.0
	while ended.size() < 2 and guard < 30.0:
		await _wait(0.25)
		guard += 0.25
	check(started.size() == 2 and ended.size() == 2, "both lines started and ended: %s %s" % [started, ended])
	check(ended.size() == 2 and ended[0] == first and ended[1] == second, "lines finished in order")
	print("spoke two lines in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	started.clear()
	ended.clear()
	var third := voice.speak("This line will be cut off before it finishes, so it should not play to the end.", a)
	await _wait(0.3)
	voice.stop_speaking()
	check(ended.has(third) and not voice.is_speaking(), "stop_speaking ends queued lines")
	print("TTS TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
