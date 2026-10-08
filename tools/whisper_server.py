"""Local speech-to-text server for the game (faster-whisper, CPU, offline after the model is downloaded).

POST /transcribe  (body: WAV bytes)  ->  {"text": "..."}
GET  /health                         ->  {"ready": true, "model": "small.en"}

Bound to 127.0.0.1 only. Exits when the game (--parent-pid) exits.
"""
import argparse
import ctypes
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io

HERE = os.path.dirname(os.path.abspath(__file__))

parser = argparse.ArgumentParser()
parser.add_argument("--model", default="small.en")
parser.add_argument("--model-dir", default=os.path.join(HERE, "whisper-models"))
parser.add_argument("--port", type=int, default=18766)
parser.add_argument("--parent-pid", type=int, default=0)
args = parser.parse_args()

PROMPT = "A conversation with villagers in Willowbrook: Pip, Mira, Theo, June, the chief, farm, market, workshop, library, houses, build, upgrade."
state = {"model": None, "lock": threading.Lock()}


def alive(pid: int) -> bool:
    handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    code = ctypes.c_ulong()
    ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(handle)
    return bool(ok) and code.value == 259


def watch_parent() -> None:
    while True:
        time.sleep(2)
        if args.parent_pid and not alive(args.parent_pid):
            os._exit(0)


def load_model() -> None:
    from faster_whisper import WhisperModel
    state["model"] = WhisperModel(args.model, device="cpu", compute_type="int8", download_root=args.model_dir, cpu_threads=max(2, (os.cpu_count() or 4) // 2))
    # Warm up so the first real request is fast.
    import wave
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\x00\x00" * 8000)
    buffer.seek(0)
    list(state["model"].transcribe(buffer, language="en", beam_size=1)[0])
    print("whisper ready", flush=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def _send(self, status: int, data: dict) -> None:
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _allowed(self) -> bool:
        return not self.headers.get("Origin") and self.headers.get("X-Pocket-Village") == "local-game"

    def do_GET(self):
        if not self._allowed():
            return self._send(403, {"error": "Local game requests only."})
        if self.path == "/health":
            return self._send(200, {"ready": state["model"] is not None, "model": args.model})
        self._send(404, {"error": "Unknown endpoint."})

    def do_POST(self):
        if not self._allowed():
            return self._send(403, {"error": "Local game requests only."})
        if self.path != "/transcribe":
            return self._send(404, {"error": "Unknown endpoint."})
        if state["model"] is None:
            return self._send(503, {"error": "Model still loading."})
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 44 or length > 8_000_000:
            return self._send(400, {"error": "Bad audio size."})
        audio = io.BytesIO(self.rfile.read(length))
        try:
            with state["lock"]:
                segments, _info = state["model"].transcribe(
                    audio, language="en", beam_size=1, vad_filter=True, condition_on_previous_text=False, initial_prompt=PROMPT
                )
                text = " ".join(segment.text.strip() for segment in segments).strip()
            self._send(200, {"text": text})
        except Exception as error:  # noqa: BLE001
            self._send(500, {"error": str(error)[:200]})


if __name__ == "__main__":
    if args.parent_pid:
        threading.Thread(target=watch_parent, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    threading.Thread(target=load_model, daemon=True).start()
    print("whisper server on 127.0.0.1:%d" % args.port, flush=True)
    server.serve_forever()
