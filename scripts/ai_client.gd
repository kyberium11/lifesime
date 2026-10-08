class_name AiClient
extends Node
## Talks to the local bridge. Two lanes run side by side so a slow background request never blocks
## something you are waiting on:
##   fast lane: replies to the chief, advice, resident-to-resident conversations (local Qwen, ~2 s)
##   slow lane: background decisions (Claude Code, 20-40 s)

signal completed(id: int, kind: String, data: Dictionary, tag: Variant)
signal failed(id: int, kind: String, reason: String, tag: Variant)

const URL := "http://127.0.0.1:18765"
const ENDPOINT := {"chat": "/chat", "decide": "/decide", "talk": "/talk", "advise": "/advise", "chronicle": "/chronicle"}
const LANE := {"chat": "fast", "advise": "fast", "talk": "fast", "decide": "slow", "chronicle": "fast"}
const PRIORITY := {"chat": 0, "advise": 1, "talk": 2, "decide": 3, "chronicle": 2}
## Minimum seconds between two dispatches of this kind.
const GAP := {"chat": 0.3, "advise": 2.0, "talk": 1.0, "decide": 15.0, "chronicle": 2.0}

var enabled := true
var status := "AI · idle"
var last_error := ""
var busy: bool:
	get: return not _lanes.fast.job.is_empty() or not _lanes.slow.job.is_empty()

var _queue: Array = []
var _lanes := {"fast": {"http": HTTPRequest.new(), "job": {}, "retry": 0.0}, "slow": {"http": HTTPRequest.new(), "job": {}, "retry": 0.0}}
var _next_id := 1
var _last_dispatch := {}


func _ready() -> void:
	for lane in _lanes:
		var http: HTTPRequest = _lanes[lane].http
		http.timeout = 95.0
		add_child(http)
		http.request_completed.connect(_on_done.bind(lane))


## Queue a request. `max_wait` is how long it may sit in the queue before it is dropped.
func request(kind: String, payload: Dictionary, tag: Variant = null, max_wait: float = 40.0) -> int:
	var id := _next_id
	_next_id += 1
	if not enabled:
		call_deferred("_fail_now", id, kind, "AI is switched off.", tag)
		return id
	_queue.append({"id": id, "kind": kind, "payload": payload, "tag": tag, "queued": Time.get_ticks_msec() / 1000.0, "deadline": max_wait})
	return id


func queued_count(kind: String) -> int:
	var n := 0
	for q in _queue:
		if q.kind == kind:
			n += 1
	for lane in _lanes:
		var job: Dictionary = _lanes[lane].job
		if not job.is_empty() and job.kind == kind:
			n += 1
	return n


func cancel_all(kind: String) -> void:
	_queue = _queue.filter(func(q: Dictionary) -> bool: return q.kind != kind)


func clear() -> void:
	_queue.clear()
	for lane in _lanes:
		if not _lanes[lane].job.is_empty():
			(_lanes[lane].http as HTTPRequest).cancel_request()
			_lanes[lane].job = {}


func _fail_now(id: int, kind: String, reason: String, tag: Variant) -> void:
	failed.emit(id, kind, reason, tag)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_queue.size() - 1, -1, -1):
		var q: Dictionary = _queue[i]
		if now - float(q.queued) > float(q.deadline):
			_queue.remove_at(i)
			failed.emit(int(q.id), str(q.kind), "Timed out waiting for the AI.", q.tag)
	if not enabled:
		return
	for lane in _lanes:
		_dispatch(lane, now)


func _dispatch(lane: String, now: float) -> void:
	var state: Dictionary = _lanes[lane]
	if not state.job.is_empty() or now < float(state.retry):
		return
	var best := -1
	for i in range(_queue.size()):
		var q: Dictionary = _queue[i]
		if LANE[q.kind] != lane:
			continue
		if now - float(_last_dispatch.get(q.kind, -1000.0)) < float(GAP[q.kind]):
			continue
		if best < 0 or int(PRIORITY[q.kind]) < int(PRIORITY[_queue[best].kind]):
			best = i
	if best < 0:
		return
	var job: Dictionary = _queue[best]
	_queue.remove_at(best)
	state.job = job
	_last_dispatch[job.kind] = now
	status = "AI · thinking (%s)" % job.kind
	var http: HTTPRequest = state.http
	var err := http.request(URL + ENDPOINT[job.kind], ["Content-Type: application/json", "X-Pocket-Village: local-game"], HTTPClient.METHOD_POST, JSON.stringify(job.payload))
	if err != OK:
		state.job = {}
		_fail(job, "Cannot reach the bridge (is Node installed?).")


func _fail(job: Dictionary, reason: String) -> void:
	last_error = reason
	status = "AI unavailable · local autonomy"
	failed.emit(int(job.id), str(job.kind), reason, job.tag)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, lane: String) -> void:
	var state: Dictionary = _lanes[lane]
	var job: Dictionary = state.job
	state.job = {}
	if job.is_empty():
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code == 429:
		# The bridge is busy or cooling down: put the job back and try again shortly.
		state.retry = Time.get_ticks_msec() / 1000.0 + 1.2
		_queue.push_front(job)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary:
		var message := str(data.get("error", "")) if data is Dictionary else ""
		_fail(job, message if message != "" else "The AI bridge is not responding (%d)." % code)
		return
	last_error = ""
	status = "AI connected"
	completed.emit(int(job.id), str(job.kind), data, job.tag)
