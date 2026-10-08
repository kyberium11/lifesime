class_name VoiceService
extends Node
## Speech in and out. Output uses a local neural voice (Piper) with a distinct voice per resident and
## emotion in the delivery, falling back to the operating system's text-to-speech if it is not installed. Input records the microphone, stops by itself when you finish speaking, and transcribes
## with a local Whisper server (falling back to the Windows recognizer if it is not installed).

signal utterance_started(id: int)
signal utterance_ended(id: int)
signal listening_changed(on: bool)
signal transcribed(text: String)
signal stt_failed(reason: String)
signal stt_status_changed(text: String)

const WHISPER_PORT := 18766
const PIPER_PORT := 18767
## How each emotion changes delivery: length (higher = slower), noise (pitch/energy variation), noise_w (rhythm variation).
const EMOTION_DELIVERY := {
	"happy": {"length": 0.93, "noise": 0.85, "noise_w": 1.0},
	"content": {"length": 1.0, "noise": 0.75, "noise_w": 0.9},
	"excited": {"length": 0.86, "noise": 0.95, "noise_w": 1.1},
	"angry": {"length": 0.88, "noise": 0.95, "noise_w": 1.1},
	"gloomy": {"length": 1.16, "noise": 0.5, "noise_w": 0.6},
	"lonely": {"length": 1.12, "noise": 0.55, "noise_w": 0.65},
	"tired": {"length": 1.24, "noise": 0.45, "noise_w": 0.55},
	"sick": {"length": 1.2, "noise": 0.5, "noise_w": 0.6},
	"bored": {"length": 1.12, "noise": 0.5, "noise_w": 0.6},
	"hungry": {"length": 1.0, "noise": 0.8, "noise_w": 0.9},
	"dirty": {"length": 1.0, "noise": 0.7, "noise_w": 0.8},
}
const BUS := "VoiceCapture"
const SAMPLE_RATE := 16000
const MAX_SECONDS := 22.0
const NO_SPEECH_SECONDS := 9.0
const END_SILENCE := 1.25

var tts_enabled := true
## How loud residents speak, 0-150 (80 is the normal level).
var master_volume := 80
var stt_status := "Voice input not started"
var whisper_ready := false
var listening := false
var transcribing := false
var mic_level := 0.0
var heard_speech := false

var _voices: Array = []
var _next_id := 1
var _fake: Dictionary = {}  # utterance id -> seconds left (used when no OS voice exists, e.g. headless)
var _speaking: Dictionary = {}
var _record: AudioEffectRecord
var _mic_player: AudioStreamPlayer
var _bus_index := -1
var _listen_time := 0.0
var _silence_time := 0.0
var _floor_db := -60.0  # the room's background level, tracked while listening
var _floor_cap := -30.0
var _floor_set := false
var _whisper_pid := -1
var _health := HTTPRequest.new()
var _stt_http := HTTPRequest.new()
var _health_timer := 0.0
var _fallback_thread: Thread
var piper_ready := false
var _piper_pid := -1
var _cast: Dictionary = {}
var _tts_health := HTTPRequest.new()
var _tts_timer := 0.0
var _tts_queue: Array = []  # {id, text, profile, volume, stream, state: pending|loading|ready|failed, http}
var _tts_http: Array = [HTTPRequest.new(), HTTPRequest.new()]
var _tts_player := AudioStreamPlayer.new()
var _tts_current := -1


func _ready() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		_voices = DisplayServer.tts_get_voices_for_language("en")
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, _on_tts_started)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_tts_ended)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_tts_ended)
	add_child(_health)
	add_child(_stt_http)
	add_child(_tts_health)
	_tts_health.request_completed.connect(_on_tts_health)
	for slot in range(_tts_http.size()):
		var http: HTTPRequest = _tts_http[slot]
		http.timeout = 30.0
		add_child(http)
		http.request_completed.connect(_on_tts_audio.bind(slot))
	add_child(_tts_player)
	_tts_player.finished.connect(_on_tts_player_finished)
	_start_piper()
	_health.request_completed.connect(_on_health)
	_stt_http.request_completed.connect(_on_transcribed)
	_stt_http.timeout = 40.0
	_setup_capture()
	_start_whisper()


func _exit_tree() -> void:
	stop_speaking()
	if _fallback_thread != null and _fallback_thread.is_started():
		_fallback_thread.wait_to_finish()


# --- speech output --------------------------------------------------------------------------------

func _voice_ids() -> Dictionary:
	var out := {"female": "", "male": ""}
	for v in DisplayServer.tts_get_voices():
		var n := str(v.get("name", "")).to_lower()
		if out.female == "" and (n.contains("zira") or n.contains("hazel") or n.contains("susan") or n.contains("female")):
			out.female = str(v.id)
		if out.male == "" and (n.contains("david") or n.contains("mark") or n.contains("george") or n.contains("male")):
			out.male = str(v.id)
	if out.female == "" and not _voices.is_empty():
		out.female = str(_voices[0])
	if out.male == "" and not _voices.is_empty():
		out.male = str(_voices[_voices.size() - 1])
	return out


## A stable voice for one resident: gender from their model, pitch and pace from their name.
func profile_for(resident: Dictionary, emotion: String = "") -> Dictionary:
	var look: String = Catalog.LOOKS[int(resident.get("look", 0)) % Catalog.LOOKS.size()]
	var female := look in Catalog.FEMALE_LOOKS
	var h := absi(hash(str(resident.get("name", "x"))))
	var ids := _voice_ids() if not _voices.is_empty() else {"female": "", "male": ""}
	var cast: Array = _cast.get("female" if female else "male", [])
	var piper: Dictionary = cast[h % cast.size()] if not cast.is_empty() else {}
	var delivery: Dictionary = EMOTION_DELIVERY.get(emotion, {"length": 1.0, "noise": 0.7, "noise_w": 0.85})
	return {
		"voice": ids.female if female else ids.male,
		"pitch": (1.12 if female else 0.88) + ((h % 7) - 3) * 0.05,
		"rate": 0.98 + ((h / 7) % 5) * 0.035,
		"piper": piper,
		"emotion": emotion,
		"length": float(delivery.length) * (0.96 + float((h / 11) % 5) * 0.02),
		"noise": float(delivery.noise),
		"noise_w": float(delivery.noise_w),
	}


func estimate_seconds(text: String) -> float:
	return clampf(text.split(" ", false).size() / 2.7 + 0.5, 1.0, 14.0)


## Speaks `text` and returns an utterance id; utterance_started / utterance_ended fire for it.
func speak(text: String, profile: Dictionary = {}, volume: int = -1) -> int:
	if volume < 0:
		volume = master_volume
	var id := _next_id
	_next_id += 1
	text = text.strip_edges()
	if text == "":
		call_deferred("_emit_end", id)
		return id
	if tts_enabled and piper_ready and not (profile.get("piper", {}) as Dictionary).is_empty():
		# Delivery follows the punctuation: excited lines run a little faster, trailing-off lines slower.
		var shaped := profile.duplicate()
		if text.ends_with("!"):
			shaped.length = float(shaped.get("length", 1.0)) * 0.94
		elif text.ends_with("..."):
			shaped.length = float(shaped.get("length", 1.0)) * 1.08
		_tts_queue.append({"id": id, "text": text, "profile": shaped, "volume": volume, "stream": null, "state": "pending", "http": -1})
		_pump_tts()
	elif tts_enabled and not _voices.is_empty():
		DisplayServer.tts_speak(text, str(profile.get("voice", "")), volume, float(profile.get("pitch", 1.0)), float(profile.get("rate", 1.0)), id, false)
	else:
		_fake[id] = estimate_seconds(text)
		call_deferred("_emit_start", id)
	return id


func stop_speaking() -> void:
	var queued := _tts_queue.duplicate()
	_tts_queue.clear()
	_tts_current = -1
	_tts_player.stop()
	for http: HTTPRequest in _tts_http:
		http.cancel_request()
	for item in queued:
		_emit_end(int(item.id))
	if tts_enabled and not _voices.is_empty():
		DisplayServer.tts_stop()
	for id in _fake.keys():
		_emit_end(int(id))
	_fake.clear()


func is_speaking() -> bool:
	return not _speaking.is_empty() or not _fake.is_empty() or not _tts_queue.is_empty()


# --- neural voices (Piper) -----------------------------------------------------------------------------------------

func _start_piper() -> void:
	var python := ProjectSettings.globalize_path("res://tools/piper-env/Scripts/python.exe")
	var script := ProjectSettings.globalize_path("res://tools/tts_server.py")
	var voices := ProjectSettings.globalize_path("res://tools/piper-voices")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists(script) or not DirAccess.dir_exists_absolute(voices):
		return
	var cast_file := FileAccess.open(voices + "/cast.json", FileAccess.READ)
	if cast_file != null:
		var parsed: Variant = JSON.parse_string(cast_file.get_as_text())
		if parsed is Dictionary:
			_cast = parsed
	_piper_pid = OS.create_process(python, [script, voices, "--port", str(PIPER_PORT), "--parent-pid", str(OS.get_process_id())], false)


## Start synthesising the next lines (two at a time, so the following line is ready when this one ends),
## and start playing the first line as soon as its audio arrives.
func _pump_tts() -> void:
	for item in _tts_queue.slice(0, 3):
		if item.state != "pending":
			continue
		var slot := -1
		for k in range(_tts_http.size()):
			var busy := false
			for other in _tts_queue:
				if other.state == "loading" and int(other.http) == k:
					busy = true
			if not busy:
				slot = k
				break
		if slot < 0:
			break
		var p: Dictionary = item.profile
		var piper: Dictionary = p.piper
		var body := {"text": item.text, "voice": piper.get("voice", ""), "speaker": piper.get("speaker", null), "length": p.length, "noise": p.noise, "noise_w": p.noise_w}
		var err := (_tts_http[slot] as HTTPRequest).request("http://127.0.0.1:%d/speak" % PIPER_PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
		if err == OK:
			item.state = "loading"
			item.http = slot
		else:
			item.state = "failed"
	_play_next_tts()


func _on_tts_audio(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, slot: int) -> void:
	for item in _tts_queue:
		if item.state == "loading" and int(item.http) == slot:
			var stream: AudioStreamWAV = _wav_from_bytes(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
			item.stream = stream
			item.state = "ready" if stream != null else "failed"
			break
	_pump_tts()


func _play_next_tts() -> void:
	if _tts_current >= 0 or _tts_queue.is_empty():
		return
	var item: Dictionary = _tts_queue[0]
	if item.state == "failed":
		# No audio for this line: let it run for a natural length so conversations keep their rhythm.
		_tts_queue.pop_front()
		_fake[int(item.id)] = estimate_seconds(str(item.text))
		_emit_start(int(item.id))
		_pump_tts()
		return
	if item.state != "ready":
		return
	_tts_current = int(item.id)
	_tts_player.stream = item.stream
	_tts_player.volume_db = linear_to_db(clampf(float(item.volume) / 80.0, 0.05, 1.5))
	_tts_player.play()
	_emit_start(_tts_current)


func _on_tts_player_finished() -> void:
	if _tts_current < 0:
		return
	var id := _tts_current
	_tts_current = -1
	if not _tts_queue.is_empty() and int(_tts_queue[0].id) == id:
		_tts_queue.pop_front()
	_emit_end(id)
	_pump_tts()


## Piper returns a standard 16-bit mono WAV; wrap its samples in an AudioStreamWAV.
func _wav_from_bytes(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var rate := 22050
	var channels := 1
	var pos := 12
	while pos + 8 <= bytes.size():
		var tag := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var length := bytes.decode_u32(pos + 4)
		if tag == "fmt ":
			channels = bytes.decode_u16(pos + 10)
			rate = bytes.decode_u32(pos + 12)
		elif tag == "data":
			var stream := AudioStreamWAV.new()
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.mix_rate = rate
			stream.stereo = channels == 2
			stream.data = bytes.slice(pos + 8, mini(pos + 8 + length, bytes.size()))
			return stream
		pos += 8 + length + (length & 1)
	return null


func _on_tts_health(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("ok", false):
		piper_ready = true


func _on_tts_started(id: int) -> void:
	_emit_start(id)


func _on_tts_ended(id: int) -> void:
	_emit_end(id)


func _emit_start(id: int) -> void:
	_speaking[id] = true
	utterance_started.emit(id)


func _emit_end(id: int) -> void:
	_speaking.erase(id)
	_fake.erase(id)
	utterance_ended.emit(id)


# --- microphone --------------------------------------------------------------------------------------

func _setup_capture() -> void:
	_bus_index = AudioServer.get_bus_index(BUS)
	if _bus_index < 0:
		# The capture bus must stay unmuted so its level meter works; it feeds a muted sink so the
		# microphone is never played back through the speakers.
		var sink := AudioServer.bus_count
		AudioServer.add_bus(sink)
		AudioServer.set_bus_name(sink, "VoiceSink")
		AudioServer.set_bus_mute(sink, true)
		_bus_index = AudioServer.bus_count
		AudioServer.add_bus(_bus_index)
		AudioServer.set_bus_name(_bus_index, BUS)
		AudioServer.set_bus_send(_bus_index, "VoiceSink")
		_record = AudioEffectRecord.new()
		AudioServer.add_bus_effect(_bus_index, _record)
	else:
		_record = AudioServer.get_bus_effect(_bus_index, 0) as AudioEffectRecord
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS
	add_child(_mic_player)


func microphone_names() -> Array:
	return Array(AudioServer.get_input_device_list())


func set_microphone(device_name: String) -> void:
	AudioServer.input_device = device_name


func start_listening() -> void:
	if listening or transcribing:
		return
	_record.set_recording_active(false)
	if not _mic_player.playing:
		_mic_player.play()
	_record.set_recording_active(true)
	listening = true
	heard_speech = false
	_listen_time = 0.0
	_silence_time = 0.0
	_floor_set = false
	listening_changed.emit(true)


## Stops recording and sends what was heard for transcription. `discard` drops the audio.
func stop_listening(discard: bool = false) -> void:
	if not listening:
		return
	listening = false
	var recording: AudioStreamWAV = _record.get_recording()
	_record.set_recording_active(false)
	_mic_player.stop()
	mic_level = 0.0
	listening_changed.emit(false)
	if discard or recording == null or recording.data.size() < 4000 or not heard_speech:
		stt_failed.emit("I didn't hear anything. Try again a little louder.")
		return
	_transcribe(_to_wav_16k(recording))


func _process(dt: float) -> void:
	if not piper_ready and _piper_pid > 0:
		_tts_timer -= dt
		if _tts_timer <= 0.0:
			_tts_timer = 1.0
			if _tts_health.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				_tts_health.request("http://127.0.0.1:%d/health" % PIPER_PORT)
	for id in _fake.keys():
		_fake[id] -= dt
		if _fake[id] <= 0.0:
			_emit_end(int(id))
	if listening:
		var db := AudioServer.get_bus_peak_volume_left_db(_bus_index, 0)
		_listen_time += dt
		# Microphones deliver silence for the first moments, then a room tone that differs a lot between
		# devices. Track the quiet end of the signal and call anything well above it speech.
		if db > -120.0:
			if not _floor_set:
				_floor_db = db
				_floor_cap = db + 8.0
				_floor_set = true
			elif db < _floor_db:
				_floor_db = lerpf(_floor_db, db, 0.5)
			else:
				_floor_db = minf(_floor_cap, _floor_db + dt)
		mic_level = clampf((db - _floor_db) / 35.0, 0.0, 1.0) if _floor_set else 0.0
		if _floor_set and db > maxf(_floor_db + 9.0, -50.0):
			heard_speech = true
			_silence_time = 0.0
		elif heard_speech and db < _floor_db + 6.0:
			_silence_time += dt
		if heard_speech and _silence_time >= END_SILENCE:
			stop_listening()
		elif not heard_speech and _listen_time >= NO_SPEECH_SECONDS:
			stop_listening(true)
			stt_failed.emit("I didn't hear anything. Is the right microphone selected?")
		elif _listen_time >= MAX_SECONDS:
			stop_listening()
	if not whisper_ready and _whisper_pid > 0:
		_health_timer -= dt
		if _health_timer <= 0.0:
			_health_timer = 2.0
			if _health.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				_health.request("http://127.0.0.1:%d/health" % WHISPER_PORT, ["X-Pocket-Village: local-game"])


## Converts a Godot recording to 16 kHz mono 16-bit PCM, boosting quiet microphones.
func _to_wav_16k(recording: AudioStreamWAV) -> PackedByteArray:
	var src := recording.data
	var channels := 2 if recording.stereo else 1
	var rate := float(recording.mix_rate)
	var frames := src.size() / (2 * channels)
	var out_frames := int(frames * float(SAMPLE_RATE) / rate)
	var peak := 1
	var samples := PackedInt32Array()
	samples.resize(out_frames)
	for i in range(out_frames):
		var at := int(i * rate / SAMPLE_RATE) * 2 * channels
		var v := src.decode_s16(at)
		if channels == 2:
			v = (v + src.decode_s16(at + 2)) / 2
		samples[i] = v
		peak = maxi(peak, absi(v))
	var gain := clampf(26000.0 / float(peak), 1.0, 8.0)
	var out := PackedByteArray()
	out.resize(44 + out_frames * 2)
	out.encode_u32(0, 0x46464952)  # RIFF
	out.encode_u32(4, 36 + out_frames * 2)
	out.encode_u32(8, 0x45564157)  # WAVE
	out.encode_u32(12, 0x20746d66)  # fmt
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)
	out.encode_u16(22, 1)
	out.encode_u32(24, SAMPLE_RATE)
	out.encode_u32(28, SAMPLE_RATE * 2)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(36, 0x61746164)  # data
	out.encode_u32(40, out_frames * 2)
	for i in range(out_frames):
		out.encode_s16(44 + i * 2, clampi(int(samples[i] * gain), -32768, 32767))
	return out


# --- transcription -------------------------------------------------------------------------------------

func _transcribe(wav: PackedByteArray) -> void:
	transcribing = true
	stt_status_changed.emit("Transcribing…")
	if whisper_ready:
		var err := _stt_http.request_raw("http://127.0.0.1:%d/transcribe" % WHISPER_PORT, ["Content-Type: audio/wav", "X-Pocket-Village: local-game"], HTTPClient.METHOD_POST, wav)
		if err == OK:
			return
	# Fallback: the Windows recognizer, run off the main thread.
	var path := ProjectSettings.globalize_path("user://stt_input.wav")
	var file := FileAccess.open("user://stt_input.wav", FileAccess.WRITE)
	if file == null:
		_finish_transcription("", "Could not save the recording.")
		return
	file.store_buffer(wav)
	file.close()
	if _fallback_thread != null and _fallback_thread.is_started():
		_fallback_thread.wait_to_finish()
	_fallback_thread = Thread.new()
	_fallback_thread.start(_windows_stt.bind(path))


func _windows_stt(path: String) -> void:
	var script := ProjectSettings.globalize_path("res://tools/stt.ps1")
	var output: Array = []
	OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Wav", path], output, true)
	var text := str(output[0]).strip_edges() if not output.is_empty() else ""
	call_deferred("_finish_transcription", text, "")


func _on_transcribed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_transcription("", "Speech recognition failed (%d)." % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	_finish_transcription(str(data.get("text", "")).strip_edges() if data is Dictionary else "", "")


func _finish_transcription(text: String, error: String) -> void:
	transcribing = false
	stt_status_changed.emit(stt_status)
	if error != "":
		stt_failed.emit(error)
	elif text == "":
		stt_failed.emit("I couldn't make out any words. Try again.")
	else:
		transcribed.emit(text)


# --- whisper server lifecycle --------------------------------------------------------------------------

func _start_whisper() -> void:
	var python := ProjectSettings.globalize_path("res://tools/whisper-env/Scripts/python.exe")
	var script := ProjectSettings.globalize_path("res://tools/whisper_server.py")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists(script):
		stt_status = "Voice input: Windows recognizer (install Whisper for better accuracy)"
		stt_status_changed.emit(stt_status)
		return
	_whisper_pid = OS.create_process(python, [script, "--parent-pid=%d" % OS.get_process_id()], false)
	stt_status = "Voice input: loading Whisper…"
	stt_status_changed.emit(stt_status)


func _on_health(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("ready", false):
		whisper_ready = true
		stt_status = "Voice input: Whisper ready"
		stt_status_changed.emit(stt_status)
