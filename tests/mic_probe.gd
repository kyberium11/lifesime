extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var voice := VoiceService.new()
	root.add_child(voice)
	await process_frame
	for dev in ["Default", "Microphone (M-930)", "Microphone (USB Camera)"]:
		AudioServer.input_device = dev
		await create_timer(0.3).timeout
		voice.start_listening()
		var samples: Array = []
		var started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 2600:
			await process_frame
			samples.append(snappedf(AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("VoiceCapture"), 0), 0.1))
		voice.stop_listening(true)
		var line := ""
		for i in range(0, samples.size(), 12):
			line += "%s " % str(samples[i])
		print("%-26s dB every ~0.2s: %s" % [dev, line])
		await create_timer(0.4).timeout
	quit()
