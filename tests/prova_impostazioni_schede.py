#!/usr/bin/env python3
"""Prova delle Impostazioni riordinate (11 ottobre 2026), con mouse vero.

    python3 tests/prova_impostazioni_schede.py

Le pagine vere «Barra e dock» e «Preset» (nella stessa finestra, una alla volta) in un compositore senza schermo, con
il demone di prova (impostazioni in memoria): la sessione di chi la lancia non
cambia, e nemmeno il suo preset.

Controlla che:
  · di serie sia aperta solo la prima scheda di una pagina;
  · un clic sul titolo apra e chiuda una scheda, e che il demone lo ricordi;
  · la ricerca apra la scheda chiusa che contiene la riga cercata;
  · col preset Windows spariscano le schede della barra di Liquid e compaia
    quella di Windows 11 nella pagina Preset, e viceversa.
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
    # Il demone di prova accetta solo cartelle con questo nome: è la sua
    # garanzia di non scrivere mai nelle impostazioni vere.
    tmp = tempfile.mkdtemp(prefix='minerva-tiling-windows11-', dir='/tmp')
    figli = []

    def lancia(argomenti, ambiente, nome):
        registro = open(Path(tmp) / f'{nome}.log', 'w')
        p = subprocess.Popen(argomenti, env=ambiente, stdout=registro, stderr=subprocess.STDOUT,
                             start_new_session=True)
        figli.append(p)
        return p

    ambiente = dict(os.environ, LANG='it_IT.UTF-8', LC_ALL='it_IT.UTF-8', MINERVA_PROVA='1', WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1',
                    WLR_RENDERER='pixman', MINERVA_SCRIVANIA='0', MINERVA_IPC_SOCKET=tmp + '/assente',
                    MINERVA_CONFIG_DIR=tmp + '/config', XDG_CONFIG_HOME=tmp + '/config',
                    XDG_CACHE_HOME=tmp + '/cache', XDG_STATE_HOME=tmp + '/state', LIQUID_DE=str(ROOT),
                    XDG_RUNTIME_DIR=tmp, MINERVA_SESSIONE='schede-test', XDG_SESSION_ID='schede-test',
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

        presa = tmp + '/settings.sock'
        lancia(['dart', 'run', str(ROOT / 'minervad/test/windows11_fixture.dart'), tmp], ambiente, 'demone')
        aspetta(lambda: Path(presa).exists(), 60)
        canale_demone = Path(tmp) / 'liquid-de/sessioni/schede-test/canale'
        canale_demone.parent.mkdir(parents=True)
        canale_demone.write_text('socket=' + presa + '\nsegreto=private-category-fixture\n')
        canale_demone.chmod(0o600)

        shell = Path(tmp) / 'shell.qml'
        testo = (ROOT / 'tests/fixtures/impostazioni-schede.qml').read_text()
        for segno, cartella in (('@CORE@', 'minerva-shell/core'), ('@SECTIONS@', 'minerva-shell/settings/sections'),
                                ('@THEME@', 'minerva-shell/theme')):
            testo = testo.replace(segno, (ROOT / cartella).as_uri())
        shell.write_text(testo)
        ambiente_ui = dict(ambiente, MINERVA_SCRIVANIA='1', MINERVA_IPC_SOCKET=presa)
        lancia(['qs', '-p', str(shell)], ambiente_ui, 'shell')

        def chiama(*argomenti):
            r = subprocess.run(['qs', '-p', str(shell), 'ipc', 'call', 'schede-prova', *argomenti],
                               env=ambiente_ui, text=True, capture_output=True, timeout=10)
            return r.stdout.strip() if r.returncode == 0 else ''

        def stato():
            grezzo = chiama('stato')
            return json.loads(grezzo) if grezzo.startswith('{') else {}

        def finestra(titolo):
            elenco = json.loads(cmd('finestre')[3:])
            return next(w for w in elenco if w['titolo'] == titolo)

        def clic_titolo(pagina, titolo_finestra, titolo_scheda):
            s = stato()
            scheda = next(c for c in s[pagina] if c['titolo'] == titolo_scheda)
            w = finestra(titolo_finestra)
            cmd(f"dito {w['x'] + scheda['x']} {w['y'] + scheda['y']}")
            time.sleep(0.15)
            cmd('dito premi')
            cmd('dito lascia')
            time.sleep(0.6)

        def scheda(pagina, titolo):
            return next((c for c in stato()[pagina] if c['titolo'] == titolo), None)

        aspetta(lambda: stato().get('pronto'), 60)
        # Il preset di partenza: Liquid, quello con la barra di Liquid.
        chiama('preset', 'liquid')
        aspetta(lambda: stato().get('preset') == 'liquid')
        time.sleep(1)

        # ── Di serie ─────────────────────────────────────────────────────
        s = stato()
        visibili = [c for c in s['dock'] if c['visibile']]
        controlla(len(visibili) >= 5, 'col preset Liquid si vedono le schede della barra di Liquid', [c['titolo'] for c in visibili])
        controlla(visibili[0]['aperta'] and not any(c['aperta'] for c in visibili[1:] if c['indice'] > 0),
                  'di serie è aperta solo la prima scheda', [(c['titolo'], c['aperta']) for c in visibili])
        chiuse = [c for c in visibili if not c['aperta']]
        controlla(all(c['altezza'] < 80 for c in chiuse), 'una scheda chiusa mostra solo il titolo',
                  [(c['titolo'], c['altezza']) for c in chiuse])

        # ── Aprire e chiudere col mouse ──────────────────────────────────
        cmd(f"dito 500 400")
        cmd('tasto Shift_L premi')
        cmd('tasto Shift_L lascia')
        bersaglio = chiuse[0]['titolo']
        prima = scheda('dock', bersaglio)['altezza']
        clic_titolo('dock', 'Impostazioni di prova', bersaglio)
        c = scheda('dock', bersaglio)
        controlla(c['aperta'] and c['altezza'] > prima + 40, 'il clic sul titolo apre la scheda', c)
        ricordate = aspetta(lambda: stato()['ricordate'].get(c['chiave']) is True and stato()['ricordate'])
        controlla(ricordate.get(c['chiave']) is True, 'il demone ricorda la scheda aperta', ricordate)
        clic_titolo('dock', 'Impostazioni di prova', bersaglio)
        c = scheda('dock', bersaglio)
        controlla(not c['aperta'] and c['altezza'] == prima, 'un secondo clic la richiude', c)
        controlla(stato()['ricordate'].get(c['chiave']) is False, 'e il demone ricorda anche la chiusura')

        # ── La ricerca apre la scheda giusta ─────────────────────────────
        controlla(not scheda('dock', "L'Isola")['aperta'], "la scheda dell'Isola parte chiusa")
        chiama('cerca', 'Isola a schermo intero')
        time.sleep(0.6)
        controlla(scheda('dock', "L'Isola")['aperta'], "la ricerca di una sua riga apre la scheda dell'Isola")

        # ── Il preset decide cosa si vede ────────────────────────────────
        controlla(not scheda('pagPreset', 'Windows 11')['visibile'], 'col preset Liquid la scheda Windows 11 non c\'è')
        chiama('preset', 'windows')
        aspetta(lambda: stato().get('preset') == 'windows')
        time.sleep(0.8)
        s = stato()
        liquid = [c['titolo'] for c in s['dock'] if c['visibile'] and c['titolo'] in
                  ('Dove stanno', 'La barra', 'Il tuo schermo', 'La molla', "L'Isola", 'I bordi')]
        controlla(not liquid, 'col preset Windows le schede della barra di Liquid spariscono', liquid)
        w = scheda('pagPreset', 'Windows 11')
        controlla(w['visibile'] and w['aperta'], 'e nella pagina Preset compare, aperta, la scheda Windows 11', w)
        chiama('preset', 'libero')
        aspetta(lambda: stato().get('preset') == 'libero')
        time.sleep(0.8)
        s = stato()
        controlla(all(c['visibile'] for c in s['dock'] if c['titolo'] in ('La barra', 'I bordi')) and
                  scheda('pagPreset', 'Windows 11')['visibile'], 'il preset Libero mostra tutto')

        errori = [r for r in (Path(tmp) / 'shell.log').read_text().splitlines()
                  if ('ERROR' in r or 'TypeError' in r or 'ReferenceError' in r or 'Binding loop' in r)
                  and 'pipewire' not in r]
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
            for registro in sorted(Path(tmp).glob('*.log')):
                print(f'── {registro.name} ──')
                print('\n'.join(registro.read_text(errors='replace').splitlines()[-12:]))
            print(f'Cartella della prova conservata: {tmp}')


if __name__ == '__main__':
    sys.exit(main())
