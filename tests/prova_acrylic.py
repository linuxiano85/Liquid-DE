#!/usr/bin/env python3
"""L'Acrylic di Windows 11 nel compositore (verbo «vetrobarra» con la ricetta).

il manutentore, 11 ottobre 2026: le schede di Windows sono «leggermente in blur»,
e i colori devono adattarsi a ogni combinazione. La ricetta è quella di
WinUI (`windows11/Gettoni.js`): sfondo sfocato, luminosità della tinta,
tinta, rumore. Qui, nel compositore privato senza schermo:

- una superficie `liquid-windows11` grande quanto lo schermo, con la zona
  d'ingresso fatta di striscia e pannello, come la barra vera;
- uno sfondo azzurro con un disco blu;
- il verbo senza ricetta, con la ricetta chiara e con quella scura.

Si controlla che:
- il chiaro venga quasi bianco con un velo dello sfondo, e lo scuro scuro;
- la striscia sia uguale da un capo all'altro. Un rumore fatto con `sin`
  di numeri grandi lasciava una diagonale di pixel neri: radeonsi,
  11 ottobre 2026;
- fuori dalla superficie non cambi niente.

Le foto vanno in ../Liquid_test-principale/rapporti/acrylic/.
"""
import json
import os
import re
import socket
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = Path(os.environ.get('MINERVA_TEST_REPORT_DIR',
                          str(ROOT.parent / 'Liquid_test-principale/rapporti/acrylic')))
ART.mkdir(parents=True, exist_ok=True)

SCENA = '''import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    PanelWindow {
        anchors { left: true; right: true; top: true; bottom: true }
        color: "#88aadd"
        WlrLayershell.layer: WlrLayer.Background
        exclusionMode: ExclusionMode.Ignore
        Rectangle { x: 600; y: 100; width: 500; height: 500; radius: 250; color: "#2050c0" }
    }
    PanelWindow {
        anchors { left: true; right: true; bottom: true }
        implicitHeight: 720
        exclusiveZone: 48
        color: "transparent"
        WlrLayershell.namespace: "liquid-windows11"
        WlrLayershell.layer: WlrLayer.Top
        mask: Region { item: striscia; Region { item: pannello } }
        Rectangle { id: pannello; x: 12; y: 12; width: 760; height: 648; color: Qt.rgba(0.976, 0.976, 0.976, 0.25) }
        Rectangle { id: striscia; y: 672; width: parent.width; height: 48; color: Qt.rgba(0.933, 0.933, 0.933, 0.5) }
    }
}
'''

checks = []
processi = []


def check(nome, condizione, dettaglio=None):
    checks.append({'name': nome, 'passed': bool(condizione)})
    print(('PASS ' if condizione else 'FAIL ') + nome, flush=True)
    assert condizione, (nome, dettaglio)


def luminanza(rgb):
    return sum(c * w for c, w in zip(rgb, (0.2126, 0.7152, 0.0722))) / 255


cartella = tempfile.TemporaryDirectory(prefix='minerva-acrylic-')
tmp = cartella.name
completata = False
try:
    (Path(tmp) / 'scena.qml').write_text(SCENA)
    env = dict(os.environ, WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='gles2',
               MINERVA_PROVA='1', MINERVA_SCRIVANIA='0', XDG_RUNTIME_DIR=tmp,
               MINERVA_IPC_SOCKET=tmp + '/assente')
    for chiave in ('WAYLAND_DISPLAY', 'MINERVA_CANALE', 'DISPLAY'):
        env.pop(chiave, None)
    registro = open(ART / 'compositore.log', 'w')
    processi.append(subprocess.Popen([str(ROOT / 'compositore/build-native/minerva-wayland')], env=env,
                                     stdout=registro, stderr=registro, start_new_session=True))
    for _ in range(100):
        testo = (ART / 'compositore.log').read_text()
        schermo = re.search(r'in ascolto su (\S+)$', testo, re.M)
        canale = re.search(r'canale su (\S+)', testo)
        if schermo and canale:
            break
        time.sleep(0.1)
    env['WAYLAND_DISPLAY'] = tmp + '/' + schermo[1]

    def cmd(riga):
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(5)
            s.connect(canale[1])
            s.sendall((riga + '\n').encode())
            out = b''
            while b'\n' not in out:
                out += s.recv(4096)
        return out.decode().strip()

    processi.append(subprocess.Popen(['qs', '-n', '-p', tmp + '/scena.qml'],
                                     env=dict(env, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software'),
                                     stdout=open(ART / 'scena.log', 'w'), stderr=subprocess.STDOUT,
                                     start_new_session=True))
    time.sleep(4)

    def foto(nome):
        percorso = ART / (nome + '.png')
        subprocess.run(['grim', str(percorso)], env=env, check=True, timeout=10)
        return Image.open(percorso).convert('RGB')

    check('un compositore senza ricetta risponde come prima', cmd('vetrobarra si') == 'ok si')
    time.sleep(0.6)
    semplice = foto('semplice')
    check('la ricetta sbagliata si rifiuta', cmd('vetrobarra si FCFCFC 2 FCFCFC 0.85').startswith('no'))

    check('la ricetta chiara di Windows è accettata',
          cmd('vetrobarra si FCFCFC 0.00 FCFCFC 0.85') == 'ok si acrylic')
    time.sleep(0.6)
    chiaro = foto('chiaro')
    pannello = chiaro.getpixel((200, 150))
    check('chiaro: il pannello è quasi bianco (luminosità di #FCFCFC all\'85 %)',
          luminanza(pannello) > 0.88, pannello)
    check('chiaro: un velo dello sfondo passa (il blu non sparisce del tutto)',
          pannello[2] > pannello[0], pannello)
    righe = [chiaro.getpixel((x, 700)) for x in range(0, 1280, 40)]
    check('chiaro: la striscia è uguale da un capo all\'altro, nessun pixel nero',
          max(luminanza(p) for p in righe) - min(luminanza(p) for p in righe) < 0.05, righe)
    check('fuori dalla superficie non cambia niente',
          chiaro.getpixel((900, 300)) == semplice.getpixel((900, 300)))

    check('la ricetta scura di Windows è accettata',
          cmd('vetrobarra si 2C2C2C 0.15 2C2C2C 0.96') == 'ok si acrylic')
    time.sleep(0.6)
    scuro = foto('scuro')
    # La scena stende sempre un quarto di bianco sopra il pannello (nella
    # shell vera, col tema scuro, è un quarto del colore scuro): si guarda
    # la differenza dal chiaro, non un valore assoluto.
    check('scuro: il pannello è molto più scuro che col chiaro',
          luminanza(scuro.getpixel((200, 150))) < luminanza(pannello) - 0.4,
          (scuro.getpixel((200, 150)), pannello))
    righe = [scuro.getpixel((x, 700)) for x in range(0, 1280, 40)]
    check('scuro: la striscia è uguale da un capo all\'altro',
          max(luminanza(p) for p in righe) - min(luminanza(p) for p in righe) < 0.05, righe)

    check('spento, il vetro torna via', cmd('vetrobarra no') == 'ok no')
    completata = True
finally:
    for p in reversed(processi):
        if p.poll() is None:
            os.killpg(p.pid, 15)
    for p in processi:
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, 9)
    (ART / 'verifica.json').write_text(json.dumps({'completed': completata, 'checks': checks}, indent=2))
    cartella.cleanup()
    print('RISULTATO', sum(c['passed'] for c in checks), 'controlli' if completata else 'INCOMPLETA')
