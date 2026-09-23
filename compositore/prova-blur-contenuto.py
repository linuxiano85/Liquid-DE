#!/usr/bin/env python3
"""Il blur non deve rendere trasparente un'app opaca, neppure alla nascita.

Prova pixel con Alacritty, grim e Pillow, in un runtime headless privato.
Non avvia la shell e non modifica la sessione corrente.
"""
import importlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

from PIL import Image

wait_for = importlib.import_module("prova-app-native").wait_for
BUILD = Path(os.environ.get("MINERVA_BIN", Path(__file__).resolve().parent / "build-native")).resolve()


def main():
    children = []
    with tempfile.TemporaryDirectory(prefix="minerva-blur-content-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ)
        for key in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            env.pop(key, None)
        env.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        with (BUILD / "blur-contenuto.log").open("w") as log:
            try:
                comp = subprocess.Popen([str(BUILD / "minerva-wayland")], env=env,
                                        stdout=log, stderr=log)
                children.append(comp)

                def endpoints():
                    assert comp.poll() is None, "Compositore terminato"
                    text = (BUILD / "blur-contenuto.log").read_text()
                    display = re.search(r"^minerva-wayland: in ascolto su (.+)$", text, re.M)
                    channel = re.search(r"^minerva-wayland: canale su (.+)$", text, re.M)
                    return (display[1], channel[1]) if display and channel else None

                display, channel = wait_for(endpoints)
                env["WAYLAND_DISPLAY"] = display

                def command(value):
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                        sock.settimeout(3)
                        sock.connect(channel)
                        sock.sendall((value + "\n").encode())
                        data = b""
                        while b"\n" not in data:
                            part = sock.recv(65536)
                            if not part:
                                break
                            data += part
                    reply = data.decode().strip()
                    assert reply.startswith("ok"), (value, reply)
                    return reply[3:]

                def windows():
                    return json.loads(command("finestre"))

                def check(label, expected):
                    time.sleep(.3)
                    path = base / "frame.png"
                    subprocess.run(["grim", str(path)], env=env, check=True, timeout=10)
                    f = windows()[0]
                    with Image.open(path) as image:
                        rgb = image.convert("RGB").getpixel(
                            (f["x"] + f["larghezza"] // 2, f["y"] + f["altezza"] // 2))
                    assert all(abs(a - b) <= 2 for a, b in zip(rgb, expected)), (label, rgb, expected)
                    print("ok:", label, rgb, flush=True)

                command("effetto blur 0.50")
                for startup in ("Windowed", "Fullscreen"):
                    term = subprocess.Popen(["alacritty", "--config-file", "/dev/null",
                        "-o", 'colors.primary.background="#ff0000"', "-o", "window.opacity=1.0",
                        "-o", f'window.startup_mode="{startup}"', "-e", "sleep", "120"],
                        env=env, stdout=log, stderr=log)
                    children.append(term)
                    wait_for(windows)
                    check("nascita " + startup + " con blur", (255, 0, 0))
                    command("schermointero attiva 1")
                    wait_for(lambda: windows()[0]["schermoIntero"])
                    for mode in ("vetro", "blur", "nessuno"):
                        command("effetto " + mode + " 0.50")
                        check("fullscreen " + mode, (255, 0, 0))
                    command("schermointero attiva 0")
                    wait_for(lambda: not windows()[0]["schermoIntero"])
                    command("effetto vetro 0.50")
                    check("vetro esplicito in finestra", (128, 0, 0))
                    command("effetto blur 0.50")
                    check("ritorno al blur in finestra", (255, 0, 0))
                    term.terminate()
                    term.wait(timeout=6)
                    wait_for(lambda: not windows())
            finally:
                for child in reversed(children):
                    if child.poll() is None:
                        child.terminate()
                        try:
                            child.wait(timeout=6)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait(timeout=6)


if __name__ == "__main__":
    main()
