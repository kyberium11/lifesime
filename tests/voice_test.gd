extends SceneTree
## Exercises the real voice stack (windowed: needs audio). Speaks one short line out loud, transcribes
## two recorded fixtures through the Whisper server, and checks the microphone starts and stops cleanly.
## godot --path . --script tests/voice_test.gd

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
	else:
		print("ok:   " + message)


func _initialize() -> void:
	call_deferred("run")


func wait_signal_or_timeout(sig: Signal, seconds: float) -> bool:
	var state := {"fired": false}
	sig.connect(func(_a: Variant = null) -> void: state.fired = true, CONNECT_ONE_SHOT)
	var start := Time.get_ticks_msec()
	while not state.fired and (Time.get_ticks_msec() - start) < seconds * 1000.0:
		await process_frame
	return state.fired


func run() -> void:
	var voice := VoiceService.new()
	root.add_child(voice)
	await process_frame
	print("voices: ", DisplayServer.tts_get_voices_for_language("en").size(), "  inputs: ", AudioServer.get_input_device_list())
	check(voice.profile_for({"name": "Pip", "look": 0}).has("voice"), "Residents get a voice profile")
	var other := voice.profile_for({"name": "Mira", "look": 1})
	check(float(other.pitch) != float(voice.profile_for({"name": "Pip", "look": 0}).pitch), "Different residents sound different")
	# Text to speech: a short line, audible.
	var started := {"v": false}
	var ended := {"v": false}
	voice.utterance_started.connect(func(_id: int) -> void: started.v = true)
	voice.utterance_ended.connect(func(_id: int) -> void: ended.v = true)
	var t0 := Time.get_ticks_msec()
	voice.speak("Voice test.", voice.profile_for({"name": "Pip", "look": 0}), 55)
	var waited := 0.0
	while not ended.v and waited < 8.0:
		await process_frame
		waited = (Time.get_ticks_msec() - t0) / 1000.0
	check(started.v and ended.v, "Text-to-speech starts and finishes (%.1fs)" % waited)
	# Whisper.
	var waited_ready := 0.0
	while not voice.whisper_ready and waited_ready < 40.0:
		await create_timer(0.5).timeout
		waited_ready += 0.5
	check(voice.whisper_ready, "Whisper server is ready (%.1fs)" % waited_ready)
	for case in [["res://tests/fixtures/farm_request.wav", "farm"], ["res://tests/fixtures/hello_pip.wav", "pip"]]:
		var bytes := FileAccess.get_file_as_bytes(case[0])
		var got := {"text": ""}
		voice.transcribed.connect(func(text: String) -> void: got.text = text, CONNECT_ONE_SHOT)
		voice._transcribe(bytes)
		var w := 0.0
		while got.text == "" and w < 20.0:
			await create_timer(0.25).timeout
			w += 0.25
		print("heard: ", got.text)
		check(got.text.to_lower().contains(case[1]), "Whisper hears '%s' in %s" % [case[1], case[0].get_file()])
	# Microphone: opens, reports a level and closes without errors (audio is discarded).
	voice.start_listening()
	check(voice.listening, "Microphone starts")
	var peak := 0.0
	for i in range(40):
		await process_frame
		peak = maxf(peak, voice.mic_level)
	voice.stop_listening(true)
	check(not voice.listening, "Microphone stops (peak level %.2f)" % peak)
	voice.stop_speaking()
	print("VOICE TEST: %d failure(s)" % failures)
	quit(1 if failures else 0)
