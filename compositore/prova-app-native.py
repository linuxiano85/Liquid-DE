#!/usr/bin/env python3
"""Avvio reale delle app in un compositore headless e un demone privati.

Non invia comandi alla sessione corrente. Conserva i log nella build scelta.
"""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
BUILD = Path(os.environ.get("MINERVA_BIN", ROOT / "compositore/build-native")).resolve()


def wait_for(check, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.1)
    raise RuntimeError("Tempo scaduto in attesa dell'avvio")


def main():
    processes = []
    logs = []
    with tempfile.TemporaryDirectory(prefix="minerva-app-audit-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ)
        for key in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY"):
            env.pop(key, None)
        env.update(MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER=os.environ.get("WLR_RENDERER", "gles2"),
                   XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_CONFIG_DIR=str(base / "minerva"), MINERVA_SESSIONE="audit-app",
                   MINERVA_IPC_SOCKET=str(base / "daemon.sock"),
                   MINERVA_TOKEN_FILE=str(base / "token"), MINERVA_IPC_PORT="0",
                   MINERVA_COMPOSITORE="minerva-wayland", MINERVA_ROOT=str(ROOT),
                   MINERVA_FILES_PATH=tmp, QT_QPA_PLATFORM="wayland")

        def start(args, name, extra=None, cwd=None):
            log = BUILD / ("app-audit-" + name + ".log")
            handle = log.open("w")
            logs.append(handle)
            child = subprocess.Popen(args, env=env | (extra or {}), cwd=cwd,
                                     stdout=handle, stderr=subprocess.STDOUT)
            processes.append(child)
            return child, log

        try:
            comp, log = start([str(BUILD / "minerva-wayland")], "compositore")

            def endpoints():
                if comp.poll() is not None:
                    raise RuntimeError("Compositore terminato: " + str(log))
                text = log.read_text(errors="replace")
                display = re.search(r"^minerva-wayland: in ascolto su (.+)$", text, re.M)
                channel = re.search(r"^minerva-wayland: canale su (.+)$", text, re.M)
                return (display[1], channel[1]) if display and channel else None

            display, channel = wait_for(endpoints)
            env.update(WAYLAND_DISPLAY=display, MINERVA_CANALE=channel)
            daemon, _ = start(["dart", "run", "bin/minervad.dart"], "demone", cwd=ROOT / "minervad")
            wait_for(lambda: (base / "daemon.sock").exists() and (base / "token").exists())

            def windows():
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                    sock.settimeout(3)
                    sock.connect(channel)
                    sock.sendall(b"finestre\n")
                    data = b""
                    while b"\n" not in data:
                        block = sock.recv(65536)
                        if not block:
                            break
                        data += block
                response = data.decode()
                if not response.startswith("ok "):
                    raise RuntimeError(response)
                return json.loads(response[3:])

            for script in ("minerva-files", "minerva-custodia", "minerva-monitor"):
                previous = {w["id"] for w in windows()}
                _, app_log = start([str(ROOT / "scripts" / script)], script)
                created = wait_for(lambda: [w for w in windows() if w["id"] not in previous])
                time.sleep(.5)
                text = app_log.read_text(errors="replace")
                if re.search(r"Failed to load|TypeError:|ReferenceError:|is not installed", text):
                    raise RuntimeError("Errore QML: " + str(app_log))
                if comp.poll() is not None or daemon.poll() is not None:
                    raise RuntimeError("Compositore o demone terminato")
                print(script + ": finestra aperta — " + ", ".join(w["titolo"] for w in created), flush=True)
            # Il processo intercetta SIGTERM: anche il log deve confermare
            # l'arresto pulito, perché storicamente usciva con 0 sugli errori.
            daemon.terminate()
            assert daemon.wait(timeout=10) == 0
            daemon_text = (BUILD / "app-audit-demone.log").read_text(errors="replace")
            if "Arresto non pulito" in daemon_text or "Minerva Core arrestato" not in daemon_text:
                raise RuntimeError("Arresto del demone fallito con client collegati")
            print("OK: tre app aperte dai launcher reali e arresto pulito con client collegati")
        finally:
            # I launcher usano qs -d: il processo grafico sopravvive al launcher.
            # La selezione IPC è confinata al runtime privato creato qui sopra.
            for config in ("app.qml", "filemanager.qml"):
                subprocess.run(["qs", "kill", "-p", str(ROOT / "minerva-shell" / config)],
                               env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=5, check=False)
            # Solo processi avviati da questa prova, mai ricerche globali per nome.
            for child in reversed(processes):
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
            for handle in logs:
                handle.close()


if __name__ == "__main__":
    main()
