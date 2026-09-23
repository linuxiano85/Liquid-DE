#!/usr/bin/env python3
"""Carica le pagine QML in un compositore isolato, senza demone o socket reali."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
BUILD = Path(os.environ.get('MINERVA_BIN', ROOT / 'compositore/build-native'))
with tempfile.TemporaryDirectory(prefix='minerva-settings-check-') as tmp:
    base = Path(tmp)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ)
    for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    env.update(WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='gles2',
        MINERVA_PROVA='1', MINERVA_SESSIONE='prova-hardware', XDG_RUNTIME_DIR=str(runtime),
        XDG_CONFIG_HOME=str(base/'config'), MINERVA_CONFIG_DIR=str(base/'minerva'),
        MINERVA_IPC_SOCKET=str(base/'assente.sock'), MINERVA_TOKEN_FILE=str(base/'assente'),
        MINERVA_CANALE=str(base/'assente.sock'), QT_QPA_PLATFORM='wayland')
    with (BUILD/'settings-check-compositor.log').open('w') as log:
        comp = subprocess.Popen([str(BUILD/'minerva-wayland')], env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                text = (BUILD/'settings-check-compositor.log').read_text(errors='replace')
                match = re.search(r'^minerva-wayland: in ascolto su (.+)$', text, re.M)
                canale = re.search(r'^minerva-wayland: canale su (.+)$', text, re.M)
                if match and canale: break
                if comp.poll() is not None: raise RuntimeError(text[-2000:])
                time.sleep(.1)
            else: raise RuntimeError('Compositore non pronto')
            env['WAYLAND_DISPLAY'] = match[1]
            # Il canale VERO del compositore: senza, la pagina Schermi non
            # potrebbe avere schermi e il controllo qui sotto non proverebbe
            # niente. Il demone invece resta finto (socket assente).
            env['MINERVA_CANALE'] = canale[1]
            result = subprocess.run(['qs', '-p', str(ROOT/'minerva-shell/prova-impostazioni-hardware.qml')],
                env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            (BUILD/'settings-check-qml.log').write_text(output)
            print(output)
            assert result.returncode == 0 and '4/4 pagine caricate' in output
            assert re.search(r'(\d+) schermi nella pagina', output) and \
                int(re.search(r'(\d+) schermi nella pagina', output)[1]) > 0, \
                'la pagina Schermi si è aperta vuota'
            assert not any(word in output for word in ('ERROR:', 'ReferenceError:', 'TypeError:', 'Unable to assign'))
        finally:
            comp.terminate()
            try: comp.wait(timeout=5)
            except subprocess.TimeoutExpired:
                comp.kill(); comp.wait(timeout=5)
