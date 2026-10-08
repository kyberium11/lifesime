"""Local neural text-to-speech for the village (Piper). 127.0.0.1 only.

POST /speak  {"text", "voice", "speaker", "length", "noise", "noise_w", "volume"} -> audio/wav (16-bit mono)
GET  /health -> {"ok": true, "voices": [...]}
Run: tts_server.py <voices_dir> [--port N] [--parent-pid PID]
"""
import ctypes
import io
import json
import os
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from piper import PiperVoice, SynthesisConfig

PORT = 18767
voices_dir = sys.argv[1] if len(sys.argv) > 1 else "tools/piper-voices"
parent_pid = 0
args = sys.argv[2:]
for i, a in enumerate(args):
    if a == "--port":
        PORT = int(args[i + 1])
    if a == "--parent-pid":
        parent_pid = int(args[i + 1])

loaded = {}
lock = threading.Lock()


def voice_names():
    return sorted(f[:-5] for f in os.listdir(voices_dir) if f.endswith(".onnx"))


def get_voice(name):
    names = voice_names()
    if name not in names:
        name = names[0]
    with lock:
        if name not in loaded:
            loaded[name] = PiperVoice.load(os.path.join(voices_dir, name + ".onnx"))
        return loaded[name], name


def synth(req):
    voice, name = get_voice(str(req.get("voice", "")))
    cfg = SynthesisConfig(
        speaker_id=int(req["speaker"]) if req.get("speaker") is not None and voice.config.num_speakers > 1 else None,
        length_scale=float(req.get("length", 1.0)),
        noise_scale=float(req.get("noise", 0.667)),
        noise_w_scale=float(req.get("noise_w", 0.8)),
        volume=float(req.get("volume", 1.0)),
    )
    buf = io.BytesIO()
    with lock:  # onnx sessions are not guaranteed thread safe
        with wave.open(buf, "wb") as w:
            voice.synthesize_wav(str(req.get("text", "")), w, syn_config=cfg)
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, json.dumps({"ok": True, "voices": voice_names()}).encode())
        else:
            self._send(404, b"{}")

    def do_POST(self):
        if self.path != "/speak":
            return self._send(404, b"{}")
        try:
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n))
            if not str(req.get("text", "")).strip():
                return self._send(400, b'{"error":"empty"}')
            self._send(200, synth(req), "audio/wav")
        except Exception as e:  # noqa: BLE001
            self._send(500, json.dumps({"error": str(e)}).encode())


def alive(pid):
    # os.kill(pid, 0) would send Ctrl+C to the game on Windows, so ask the OS directly.
    handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    code = ctypes.c_ulong()
    ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(handle)
    return bool(ok) and code.value == 259


def watch_parent():
    while parent_pid:
        time.sleep(2)
        if not alive(parent_pid):
            os._exit(0)


if __name__ == "__main__":
    threading.Thread(target=watch_parent, daemon=True).start()
    for n in voice_names()[:1]:
        get_voice(n)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
