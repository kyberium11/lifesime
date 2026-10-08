class_name Brain
extends Node
## Talks to a local Ollama model and returns one structured action as a Dictionary.

signal decided(action: Dictionary, raw: String, latency: float)
signal failed(reason: String)

const ACTIONS := ["gather", "eat", "sleep", "build", "explore", "rest", "talk"]

var busy := false
var ready_to_think := false
var http: HTTPRequest
var _warm: HTTPRequest
var _t0 := 0


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = float(Data.config.get("timeout_seconds", 90))
	add_child(http)
	http.request_completed.connect(_on_done)
	_warm = HTTPRequest.new()
	_warm.timeout = 300.0
	add_child(_warm)
	_warm.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: ready_to_think = true)
	_warm_up()


## Load the model into VRAM once at startup (a cold load can take over a minute).
func _warm_up() -> void:
	var body := {
		"model": Data.config.model, "stream": false, "think": false,
		"keep_alive": Data.config.get("keep_alive", "30m"),
		"messages": [{"role": "user", "content": "Reply with OK."}],
		"options": {"num_ctx": Data.config.get("num_ctx", 4096), "num_predict": 2},
	}
	if _warm.request(Data.config.ollama_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		ready_to_think = true  # let the first real request surface the error


func decide(system_prompt: String, user_prompt: String) -> void:
	busy = true
	_t0 = Time.get_ticks_msec()
	var body := {
		"model": Data.config.model,
		"stream": false,
		"think": false,
		"keep_alive": Data.config.get("keep_alive", "30m"),
		"format": _schema(),
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
		"options": {
			"temperature": Data.config.get("temperature", 0.8),
			"num_ctx": Data.config.get("num_ctx", 4096),
			"num_predict": Data.config.get("num_predict", 300),
		},
	}
	var err := http.request(Data.config.ollama_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		failed.emit("request error %d (is Ollama running?)" % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Ollama unreachable or error (result %d, http %d)" % [result, code])
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("message"):
		failed.emit("unexpected Ollama response")
		return
	var content := str(parsed.message.get("content", ""))
	var action: Variant = JSON.parse_string(content)
	if typeof(action) != TYPE_DICTIONARY:
		failed.emit("model did not return JSON: %s" % content.left(120))
		return
	decided.emit(action, content, (Time.get_ticks_msec() - _t0) / 1000.0)


func _schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"thought": {"type": "string"},
			"action": {"type": "string", "enum": ACTIONS},
			"target": {"type": "string"},
			"say": {"type": "string"},
			"note": {"type": "string"},
		},
		"required": ["thought", "action", "target", "say", "note"],
	}
