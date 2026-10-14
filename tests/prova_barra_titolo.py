#!/usr/bin/env python3
"""Pulsanti della barra del titolo disegnata dal compositore, Liquid e Windows.

il manutentore, 11 ottobre 2026: col preset Windows le finestre devono avere i
pulsanti di Windows 11 (tre rettangoli attaccati all'angolo, «chiudi» rosso).
Le barre delle nostre app le prova `prova_file_manager.py`; qui ci sono quelle
dei programmi degli altri, che disegna `compositore/src/barra.c`.

Nel compositore privato, senza schermo, con un Alacritty vero:
- `stilebarra` accetta solo «liquid» e «windows»;
- in Windows, col puntatore su «chiudi», l'angolo della barra è rosso;
- in Liquid lo stesso punto non lo è;
- un clic vero su «chiudi» chiude il programma.

Le foto vanno in ../Liquid_test-principale/rapporti/barra-titolo/.
"""
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = Path(os.environ.get('MINERVA_TEST_REPORT_DIR',
                          str(ROOT.parent / 'Liquid_test-principale/rapporti/barra-titolo')))
ART.mkdir(parents=True, exist_ok=True)
ROSSO = (0xC4, 0x2B, 0x1C)

checks = []
children = []
handles = []


def check(name, condition, detail=None):
    checks.append({'name': name, 'passed': bool(condition)})
    print(('PASS ' if condition else 'FAIL ') + name, flush=True)
    assert condition, (name, detail)


def wait(fn, timeout=15):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        result = fn()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError('tempo scaduto')


def spawn(args, env, name):
    handle = open(ART / (name + '.log'), 'w')
    handles.append(handle)
    process = subprocess.Popen(args, env=env, stdout=handle, stderr=handle, start_new_session=True)
    children.append(process)
    return process


def rosso(pixel):
    return all(abs(a - b) <= 6 for a, b in zip(pixel[:3], ROSSO))


temp = tempfile.TemporaryDirectory(prefix='minerva-barra-titolo-')
tmp = temp.name
completed = False
try:
    env = dict(os.environ, MINERVA_PROVA='1', WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1',
               WLR_RENDERER='gles2', MINERVA_SCRIVANIA='0', MINERVA_IPC_SOCKET=tmp + '/assente',
               MINERVA_CONFIG_DIR=tmp + '/config', XDG_CONFIG_HOME=tmp + '/config',
               XDG_CACHE_HOME=tmp + '/cache', XDG_STATE_HOME=tmp + '/state',
               XDG_RUNTIME_DIR=tmp, NO_AT_BRIDGE='1')
    env.pop('MINERVA_CANALE', None)
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('DISPLAY', None)
    comp = spawn([str(ROOT / 'compositore/build-native/minerva-wayland')], env, 'compositore')

    def info():
        text = (ART / 'compositore.log').read_text()
        a = re.search(r'in ascolto su (\S+)', text)
        b = re.search(r'canale su (\S+)', text)
        return (a[1], b[1]) if a and b else None

    display, channel = wait(info)
    env.update(WAYLAND_DISPLAY=str(Path(tmp) / display))

    def cmd(line, success=True):
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(5)
            s.connect(channel)
            s.sendall((line + '\n').encode())
            out = b''
            while b'\n' not in out:
                chunk = s.recv(65536)
                if not chunk:
                    raise RuntimeError('canale chiuso')
                out += chunk
        text = out.decode().strip()
        if success:
            assert text.startswith('ok'), (line, text)
        return text

    def windows():
        return json.loads(cmd('finestre')[3:])

    def screenshot(name):
        path = ART / (name + '.png')
        subprocess.run(['grim', str(path)], env=env, check=True, timeout=10)
        return Image.open(path).convert('RGB')

    # ── Il verbo ─────────────────────────────────────────────────────────
    check('stilebarra rifiuta uno stile sconosciuto',
          cmd('stilebarra pippo', success=False).startswith('no'))
    check('stilebarra accetta windows', cmd('stilebarra windows') == 'ok windows')

    # Alacritty in Wayland: la barra la disegna il compositore.
    terminal = spawn(['alacritty', '--config-file', '/dev/null', '--title', 'Barra prova',
                      '-e', 'sleep', '120'], env, 'alacritty')
    window = wait(lambda: next((w for w in windows() if w.get('pid') == terminal.pid), None))
    time.sleep(1)
    window = next(w for w in windows() if w.get('pid') == terminal.pid)
    # `finestre` dà la cornice con la barra compresa, che sta in cima. Senza
    # shell nessuno manda «aspetto», quindi la barra ha l'altezza di fabbrica
    # (`BARRA_ALTA` in `barra.h`).
    alta = 42
    check('la finestra ha la barra del compositore', window['decorata'], window)
    destra = window['x'] + window['larghezza']
    cima = window['y']
    chiudi = (destra - 23, cima + alta // 2)

    cmd(f'dito {chiudi[0]} {chiudi[1]}')
    time.sleep(.5)
    foto = screenshot('windows-chiudi-sotto-il-puntatore')
    check('Windows: col puntatore sopra, l\'angolo della barra è rosso #C42B1C',
          rosso(foto.getpixel((destra - 40, cima + alta - 4))), foto.getpixel((destra - 40, cima + alta - 4)))
    check('Windows: il rosso è largo 46 pixel e non di più',
          not rosso(foto.getpixel((destra - 50, cima + alta - 4))), foto.getpixel((destra - 50, cima + alta - 4)))

    check('stilebarra torna a liquid', cmd('stilebarra liquid') == 'ok liquid')
    cmd(f'dito {chiudi[0] - 200} {chiudi[1]}')
    cmd(f'dito {chiudi[0]} {chiudi[1]}')
    time.sleep(.5)
    foto = screenshot('liquid-stesso-punto')
    check('Liquid: lo stesso angolo non è rosso',
          not rosso(foto.getpixel((destra - 40, cima + alta - 4))), foto.getpixel((destra - 40, cima + alta - 4)))

    # ── Un clic vero su «chiudi», in stile Windows ───────────────────────
    cmd('stilebarra windows')
    cmd(f'dito {chiudi[0] - 200} {chiudi[1]}')
    cmd(f'dito {destra - 2} {cima + 2}')
    cmd('dito premi')
    cmd('dito lascia')
    wait(lambda: terminal.poll() is not None or not any(w.get('pid') == terminal.pid for w in windows()))
    check('Windows: un clic sull\'ultimo pixel dell\'angolo chiude il programma', True)

    errors = re.findall(r'(?:Segmentation|ERROR|assert)[^\n]*', (ART / 'compositore.log').read_text())
    check('compositore senza errori', not errors, errors)
    completed = True
finally:
    for process in reversed(children):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
    for process in reversed(children):
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
    for handle in handles:
        handle.close()
    (ART / 'verifica.json').write_text(json.dumps({'completed': completed, 'checks': checks}, indent=2))
    temp.cleanup()
    print('RISULTATO', sum(c['passed'] for c in checks), 'controlli passati' if completed else 'INCOMPLETO')
