#!/usr/bin/env python3
"""Prova del selettore dei preset (Super+P), con tastiera e mouse veri.

    python3 tests/prova_selettore_preset.py

Gira tutto in un compositore senza schermo e con un demone di prova: la
sessione di chi lancia la prova non viene toccata, e il preset della sua
scrivania non cambia. I tasti e il puntatore li muove il compositore stesso
(`tasto`, `dito`, che esistono solo con MINERVA_PROVA=1), quindi passano per
la stessa strada di quelli veri: la tastiera arriva al selettore solo se ha
davvero preso il fuoco.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASSATI = 0


def controlla(condizione, cosa, dettagli=None):
    global PASSATI
    if not condizione:
        raise AssertionError(f'{cosa}: {dettagli}')
    PASSATI += 1
    print('PASS', cosa)


def aspetta(funzione, secondi=15):
    fine = time.time() + secondi
    while time.time() < fine:
        risultato = funzione()
        if risultato:
            return risultato
        time.sleep(0.1)
    raise AssertionError('tempo scaduto')


def main():
    # Il demone di prova (`minervad/test/windows11_fixture.dart`) accetta solo
    # cartelle con questo nome: è la sua garanzia di non scrivere mai nelle
    # impostazioni vere.
    tmp = tempfile.mkdtemp(prefix='minerva-tiling-windows11-', dir='/tmp')
    figli = []

    def lancia(argomenti, ambiente, nome):
        registro = open(Path(tmp) / f'{nome}.log', 'w')
        p = subprocess.Popen(argomenti, env=ambiente, stdout=registro, stderr=subprocess.STDOUT,
                             start_new_session=True)
        figli.append(p)
        return p

    ambiente = dict(os.environ, MINERVA_PROVA='1', WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1',
                    WLR_RENDERER='pixman', MINERVA_SCRIVANIA='0', MINERVA_IPC_SOCKET=tmp + '/assente',
                    MINERVA_CONFIG_DIR=tmp + '/config', XDG_CONFIG_HOME=tmp + '/config',
                    XDG_CACHE_HOME=tmp + '/cache', XDG_STATE_HOME=tmp + '/state', LIQUID_DE=str(ROOT),
                    XDG_RUNTIME_DIR=tmp, MINERVA_SESSIONE='preset-test', XDG_SESSION_ID='preset-test',
                    QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
                    QT_NO_XDG_DESKTOP_PORTAL='1')
    ambiente.pop('MINERVA_CANALE', None)
    ambiente.pop('WAYLAND_DISPLAY', None)
    riuscita = False
    try:
        lancia([str(ROOT / 'compositore/build-native/minerva-wayland')], ambiente, 'compositore')

        def indirizzi():
            t = (Path(tmp) / 'compositore.log').read_text()
            a = re.search(r'in ascolto su (\S+)', t)
            b = re.search(r'canale su (\S+)', t)
            return (a[1], b[1]) if a and b else None

        display, canale = aspetta(indirizzi)
        ambiente['WAYLAND_DISPLAY'] = str(Path(tmp) / display)

        def cmd(riga):
            with socket.socket(socket.AF_UNIX) as s:
                s.settimeout(5)
                s.connect(canale)
                s.sendall((riga + '\n').encode())
                uscita = b''
                while b'\n' not in uscita:
                    uscita += s.recv(65536)
            testo = uscita.decode().strip()
            assert testo.startswith('ok'), (riga, testo)
            return testo

        def tasto(nome):
            cmd(f'tasto {nome} premi')
            cmd(f'tasto {nome} lascia')
            time.sleep(0.25)

        def clic(x, y):
            cmd(f'dito {x} {y}')
            time.sleep(0.15)
            cmd('dito premi')
            cmd('dito lascia')
            time.sleep(0.4)

        # Il demone di prova: le impostazioni in memoria, preset compresi.
        presa = tmp + '/settings.sock'
        lancia(['dart', 'run', str(ROOT / 'minervad/test/windows11_fixture.dart'), tmp], ambiente, 'demone')
        aspetta(lambda: Path(presa).exists(), 60)
        canale_demone = Path(tmp) / 'liquid-de/sessioni/preset-test/canale'
        canale_demone.parent.mkdir(parents=True)
        canale_demone.write_text('socket=' + presa + '\nsegreto=private-category-fixture\n')
        canale_demone.chmod(0o600)

        shell = Path(tmp) / 'shell.qml'
        shell.write_text((ROOT / 'tests/fixtures/selettore-preset.qml').read_text()
                         .replace('@CORE@', (ROOT / 'minerva-shell/core').as_uri())
                         .replace('@MENU@', (ROOT / 'minerva-shell/menu').as_uri()))
        ambiente_ui = dict(ambiente, MINERVA_SCRIVANIA='1', MINERVA_IPC_SOCKET=presa)
        lancia(['qs', '-p', str(shell)], ambiente_ui, 'shell')

        def chiama(metodo):
            r = subprocess.run(['qs', '-p', str(shell), 'ipc', 'call', 'preset-test', metodo],
                               env=ambiente_ui, text=True, capture_output=True, timeout=10)
            return r.stdout.strip() if r.returncode == 0 else ''

        def stato():
            grezzo = chiama('stato')
            return json.loads(grezzo) if grezzo.startswith('{') else {}

        aspetta(lambda: stato().get('pronto'), 60)
        inizio = stato()['attuale']
        schermo = json.loads(cmd('schermi')[3:])[0]
        # Il compositore senza schermo crea la tastiera virtuale al primo
        # tasto: uno a vuoto prima di cominciare, e il puntatore sullo
        # schermo (lo fa anche `tests/prova_windows11.py`).
        cmd(f"dito {schermo['x'] + 100} {schermo['y'] + 100}")
        tasto('Shift_L')

        # ── Tastiera ─────────────────────────────────────────────────────
        chiama('commuta')
        s = aspetta(lambda: (lambda x: x if x.get('aperto') else None)(stato()))
        controlla(s['evidenziato'] == inizio, 'si apre sul preset in uso', s)
        indice = s['indice']
        tasto('Right')
        controlla(stato()['indice'] == (indice + 1) % 5, 'la freccia destra passa al successivo', stato())
        tasto('Left')
        controlla(stato()['indice'] == indice, 'la freccia sinistra torna indietro', stato())
        tasto('Tab')
        controlla(stato()['indice'] == (indice + 1) % 5, 'Tab passa al successivo', stato())
        chiama('commuta')
        controlla(stato()['indice'] == (indice + 2) % 5, 'Super+P a selettore aperto passa al successivo', stato())
        tasto('Escape')
        s = stato()
        controlla(not s['aperto'] and s['attuale'] == inizio, 'Esc chiude senza cambiare preset', s)

        chiama('commuta')
        aspetta(lambda: stato().get('aperto'))
        tasto('4')
        s = aspetta(lambda: (lambda x: x if x.get('attuale') == 'windows' else None)(stato()))
        controlla(not s['aperto'] and s['ultimoScelto'] == 'windows', 'il tasto 4 applica Windows 11 e chiude', s)

        chiama('commuta')
        aspetta(lambda: stato().get('aperto'))
        tasto('Right')
        tasto('Return')
        s = aspetta(lambda: (lambda x: x if x.get('attuale') != 'windows' else None)(stato()))
        controlla(s['attuale'] == 'libero', 'freccia e Invio applicano il preset evidenziato', s)

        # ── Mouse ────────────────────────────────────────────────────────
        chiama('commuta')
        s = aspetta(lambda: (lambda x: x if x.get('aperto') and len(x.get('schede', {})) == 5 else None)(stato()))
        time.sleep(0.8)  # le molle della capsula
        s = stato()
        # PRESET_FOTO=/percorso.png salva il selettore aperto, per guardarlo.
        if os.environ.get('PRESET_FOTO'):
            subprocess.run(['grim', '-o', 'HEADLESS-1', os.environ['PRESET_FOTO']],
                           env=ambiente, check=True, timeout=10)
        mac = s['schede']['mac']
        cmd(f"dito {schermo['x'] + mac['x']} {schermo['y'] + mac['y']}")
        time.sleep(0.3)
        controlla(stato()['evidenziato'] == 'mac', 'il passaggio del mouse evidenzia la scheda', stato())
        clic(schermo['x'] + mac['x'], schermo['y'] + mac['y'])
        s = aspetta(lambda: (lambda x: x if x.get('attuale') == 'mac' else None)(stato()))
        controlla(not s['aperto'], 'il clic su una scheda la applica e chiude', s)

        chiama('commuta')
        aspetta(lambda: stato().get('aperto'))
        time.sleep(0.6)
        clic(schermo['x'] + 20, schermo['y'] + schermo['altezza'] - 20)
        s = stato()
        controlla(not s['aperto'] and s['attuale'] == 'mac', 'il clic fuori chiude senza cambiare', s)
        s = aspetta(lambda: (lambda x: x if not x.get('mostrato') else None)(stato()))
        controlla(True, 'chiuso, la superficie se ne va (niente schermo intero trasparente sempre acceso)')

        errori = [r for r in (Path(tmp) / 'shell.log').read_text().splitlines()
                  if ('ERROR' in r or 'TypeError' in r or 'ReferenceError' in r) and 'pipewire' not in r]
        controlla(not errori, 'nessun errore nel registro della shell', errori[:3])
        print(f'RISULTATO {PASSATI} controlli passati')
        riuscita = True
    finally:
        for p in reversed(figli):
            try:
                os.killpg(p.pid, 15)
            except ProcessLookupError:
                pass
        time.sleep(0.5)
        if riuscita:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            # Andata male: i registri restano, e si mostra la fine di ognuno.
            for registro in sorted(Path(tmp).glob('*.log')):
                print(f'── {registro.name} ──')
                print('\n'.join(registro.read_text(errors='replace').splitlines()[-12:]))
            print(f'Cartella della prova conservata: {tmp}')


if __name__ == '__main__':
    sys.exit(main())
