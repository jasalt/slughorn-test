"""Waits for the web selftest verdict in a Chromium tab over the DevTools protocol.

Usage: cdp_selftest.py <devtools port> <timeout seconds> <page url> [screenshot.png]

Two phases, both on the live WebGL2 canvas:
  1. waits for the in-page selftest (`?selftest`) verdict;
  2. reloads the page normally and sends real keyboard, mouse and wheel input through
     the DevTools Input domain, checking the app state after each gesture.

Standard library only: a minimal WebSocket client is enough for CDP's unfragmented
JSON messages. Prints a report and exits 0 when everything passes, 1 otherwise.
"""

import base64
import json
import os
import socket
import struct
import sys
import time
import urllib.request


class Cdp:
    def __init__(self, ws_url):
        host_port, path = ws_url.removeprefix("ws://").split("/", 1)
        host, port = host_port.split(":")
        self.sock = socket.create_connection((host, int(port)), 10)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            (
                f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\nUpgrade: websocket\r\n"
                f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
            ).encode()
        )
        response = b""
        while b"\r\n\r\n" not in response:
            response += self.sock.recv(1)
        if b" 101 " not in response.split(b"\r\n", 1)[0]:
            raise RuntimeError(f"websocket handshake failed: {response!r}")
        self.next_id = 0

    def _recv_exact(self, n):
        data = b""
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise RuntimeError("devtools connection closed")
            data += chunk
        return data

    def _recv_message(self):
        payload = b""
        while True:
            b0, b1 = self._recv_exact(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._recv_exact(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._recv_exact(8))[0]
            payload += self._recv_exact(n)
            if b0 & 0x80:
                return json.loads(payload)

    def call(self, method, **params):
        self.next_id += 1
        data = json.dumps({"id": self.next_id, "method": method, "params": params}).encode()
        mask = os.urandom(4)
        header = bytes([0x81])
        if len(data) < 126:
            header += bytes([0x80 | len(data)])
        elif len(data) < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", len(data))
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", len(data))
        self.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
        while True:
            msg = self._recv_message()
            if msg.get("id") == self.next_id:
                if "error" in msg:
                    raise RuntimeError(msg["error"])
                return msg["result"]

    def eval(self, expression):
        return self.call("Runtime.evaluate", expression=expression, returnByValue=True)["result"].get("value")


# (DOM code, key, Windows virtual key code) for the keys the input phase uses.
KEYS = {
    "Digit3": ("3", 51),
    "F1": ("F1", 112),
    "BracketRight": ("]", 221),
    "Space": (" ", 32),
}


def key(cdp, code, kind):
    text, vk = KEYS[code]
    cdp.call("Input.dispatchKeyEvent", type=kind, code=code, key=text, windowsVirtualKeyCode=vk)


def tap(cdp, code):
    key(cdp, code, "keyDown")
    key(cdp, code, "keyUp")


BUTTON_MASK = {"left": 1, "right": 2, "middle": 4}


def drag(cdp, button, start, end, modifiers=0, steps=8):
    mask = BUTTON_MASK[button]
    x0, y0 = start
    x1, y1 = end
    cdp.call("Input.dispatchMouseEvent", type="mouseMoved", x=x0, y=y0)
    cdp.call("Input.dispatchMouseEvent", type="mousePressed", x=x0, y=y0, button=button, buttons=mask, clickCount=1, modifiers=modifiers)
    for i in range(1, steps + 1):
        x = x0 + (x1 - x0) * i / steps
        y = y0 + (y1 - y0) * i / steps
        cdp.call("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y, button=button, buttons=mask, modifiers=modifiers)
    cdp.call("Input.dispatchMouseEvent", type="mouseReleased", x=x1, y=y1, button=button, buttons=0, clickCount=1, modifiers=modifiers)


def wait_for(cdp, expression, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if cdp.eval(expression):
            return True
        time.sleep(0.2)
    return False


def interaction_phase(cdp, url, timeout):
    """Returns the number of failed checks."""
    cdp.call("Page.navigate", url=url)
    if not wait_for(cdp, "window.vectorFeedback && window.vectorFeedback.state().frame > 20", timeout):
        print("FAIL input: page did not start rendering")
        return 1
    state = lambda: cdp.eval("window.vectorFeedback.state()")
    failures = 0

    def check(name, ok, detail):
        nonlocal failures
        print(f"{'PASS' if ok else 'FAIL'} input: {name} ({detail})")
        failures += 0 if ok else 1

    s0 = state()
    tap(cdp, "Digit3")
    tap(cdp, "F1")
    s1 = state()
    check("key 3 selects the text seed", s1["seed"] == "TEXT", s1["seed"])
    check("F1 toggles the help overlay", s1["help"] and not s0["help"], s1["help"])

    drag(cdp, "left", (640, 400), (840, 400))
    s2 = state()
    check("left drag pans the plane", s2["pan_x"] - s1["pan_x"] > 0.3, f"pan_x {s1['pan_x']:.3f} -> {s2['pan_x']:.3f}")

    drag(cdp, "right", (640, 400), (640, 300))
    s3 = state()
    check("right drag up zooms in", s3["zoom"] > s2["zoom"] * 1.2, f"zoom {s2['zoom']:.3f} -> {s3['zoom']:.3f}")

    drag(cdp, "left", (640, 400), (740, 450), modifiers=8)
    s4 = state()
    check("shift+left drag tilts", s4["yaw"] > s3["yaw"] and s4["pitch"] > s3["pitch"] and s4["pan_x"] == s3["pan_x"],
          f"yaw {s4['yaw']:.3f} pitch {s4['pitch']:.3f}")

    drag(cdp, "middle", (640, 400), (540, 400))
    s5 = state()
    check("middle drag tilts", s5["yaw"] < s4["yaw"], f"yaw {s4['yaw']:.3f} -> {s5['yaw']:.3f}")

    cdp.call("Input.dispatchMouseEvent", type="mouseWheel", x=640, y=400, deltaX=0, deltaY=300)
    s6 = state()
    check("wheel down zooms out", s6["zoom"] < s5["zoom"], f"zoom {s5['zoom']:.3f} -> {s6['zoom']:.3f}")

    key(cdp, "BracketRight", "keyDown")
    time.sleep(0.8)
    key(cdp, "BracketRight", "keyUp")
    s7 = state()
    check("holding ] lengthens the tail", s7["tail"] > s6["tail"], f"tail {s6['tail']:.3f} -> {s7['tail']:.3f}")

    frame = s7["frame"]
    time.sleep(1.0)
    s8 = state()
    check("animation keeps running with FPS measured", s8["frame"] > frame and s8["fps"] > 0,
          f"{s8['frame'] - frame} frames in 1s, {s8['fps']:.1f} fps")
    return failures


def main():
    port, timeout, url = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
    shot = sys.argv[4] if len(sys.argv) > 4 else None

    deadline = time.time() + 15
    while True:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=2) as r:
                pages = [t for t in json.load(r) if t.get("type") == "page"]
            if pages:
                break
        except OSError:
            pass
        if time.time() > deadline:
            sys.exit("cdp_selftest: no devtools page target")
        time.sleep(0.2)

    cdp = Cdp(pages[0]["webSocketDebuggerUrl"])
    start = time.time()
    status = None
    while time.time() - start < timeout:
        status = cdp.eval("document.body && document.body.dataset.selftest || null")
        if status:
            break
        time.sleep(0.5)

    print(cdp.eval("document.getElementById('log') ? document.getElementById('log').textContent : ''") or "", end="")
    result = cdp.eval("document.getElementById('result').textContent") or "none"
    print(f"result: {result} after {time.time() - start:.1f}s")
    failures = 0 if status == "pass" else 1
    if status == "pass":
        failures += interaction_phase(cdp, url, timeout)
    if shot:
        data = cdp.call("Page.captureScreenshot", format="png")["data"]
        with open(shot, "wb") as f:
            f.write(base64.b64decode(data))
        print(f"screenshot: {shot}")
    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
