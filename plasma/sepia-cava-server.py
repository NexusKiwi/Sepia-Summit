#!/usr/bin/env python3
"""sepia-cava-server — runs CAVA and serves its latest bar levels on localhost.

The Sepia Summit (live) wallpaper polls  http://127.0.0.1:37421/  and gets back
one line like  "12;340;998;...;0"  (values 0-1000, 128 bars).
Only listens on 127.0.0.1. Restarts CAVA if it exits.
"""
import os, re, subprocess, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("SEPIA_PORT", "37421"))
BARS = int(os.environ.get("SEPIA_BARS", "128"))
CONF = """[general]
bars = {bars}
framerate = 60
autosens = 1

[input]
method = {method}
source = auto

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
frame_delimiter = 10
channels = mono

[smoothing]
noise_reduction = 60
"""
# Not every cava build has PipeWire input (Fedora's doesn't), so fall back to Pulse.
METHODS = ("pipewire", "pulse")
TITLE = re.compile(rb"\x1b\][^\x07]*\x07")  # cava sets a terminal title on stdout
FRAME = re.compile(rb"[0-9]+(;[0-9]+)*")
ZERO = ";".join(["0"] * BARS).encode()
state = {"frame": ZERO, "t": 0.0}


def reader():
    fd, path = tempfile.mkstemp(prefix="sepia-cava-", suffix=".conf")
    os.close(fd)
    m = 0
    while True:
        with open(path, "w") as f:
            f.write(CONF.format(bars=BARS, method=METHODS[m]))
        got_frame = False
        try:
            p = subprocess.Popen(["cava", "-p", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            for line in p.stdout:
                frame = TITLE.sub(b"", line).strip().rstrip(b";")
                if FRAME.fullmatch(frame):
                    got_frame = True
                    state["frame"] = frame
                    state["t"] = time.monotonic()
            p.wait()
        except FileNotFoundError:
            pass
        if not got_frame:
            m = (m + 1) % len(METHODS)
        time.sleep(2)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = state["frame"] if time.monotonic() - state["t"] < 0.5 else ZERO
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=reader, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
