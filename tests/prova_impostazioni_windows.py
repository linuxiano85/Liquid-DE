#!/usr/bin/env python3
"""Prova delle Impostazioni nella presentazione Windows 11 (12 ottobre 2026).

    python3 tests/prova_impostazioni_windows.py

La finestra vera (`settings/System.qml`) in un compositore senza schermo,
col demone di prova (impostazioni in memoria) e il mouse del compositore. La
sessione di chi la lancia non cambia, e nemmeno il suo preset.

Controlla che:
  · in Liquid la finestra resti quella di prima (colonna a gruppi, colori e
    carattere di Liquid);
  · in Windows compaiano navigazione a categorie, pagina di categoria e
    briciola, coi colori e il carattere di Windows 11, chiaro e scuro;
  · la briciola riporti alla categoria, la ricerca porti alla pagina giusta;
  · un interruttore cliccato scriva la sua scelta al demone, come prima;
  · tornando a Liquid tutto torni com'era.

Le catture vanno in MINERVA_TEST_REPORT_DIR (di serie
../Liquid_test-principale/rapporti/impostazioni-windows).
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

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parent.parent
ART = Path(os.environ.get('MINERVA_TEST_REPORT_DIR',
                          str(ROOT.parent / 'Liquid_test-principale/rapporti/impostazioni-windows')))
PASSATI = 0

CATEGORIE_SEZIONI = {
    'home': (),
    'sistema': ('display', 'audio', 'notifiche', 'power', 'scorciatoie', 'shell'),
    'dispositivi': ('bluetooth', 'input', 'controller'),
    'rete': ('network',),
    'personalizzazione': ('preset', 'appearance', 'scrivania', 'finestre', 'dock'),
    'app': ('defaults', 'avvio'),
    'account': ('utente', 'account', 'accesso'),
    'ora': ('dataora',),
    'giochi': (),
    'accessibilita': ('accesso-facile',),
    'privacy': (),
    'update': (),
}
CATEGORIE = tuple(CATEGORIE_SEZIONI)


def controlla(condizione, cosa, dettagli=None):
    global PASSATI
    if not condizione:
        raise AssertionError(f'{cosa}: {dettagli}')
    PASSATI += 1
    print('PASS', cosa, flush=True)


def aspetta(funzione, secondi=15):
    fine = time.time() + secondi
    while time.time() < fine:
        risultato = funzione()
        if risultato:
            return risultato
        time.sleep(0.1)
    raise AssertionError('tempo scaduto')


def main():
    ART.mkdir(parents=True, exist_ok=True)
    # Il demone di prova accetta solo cartelle con questo nome: è la sua
    # garanzia di non scrivere mai nelle impostazioni vere.
    tmp = tempfile.mkdtemp(prefix='minerva-tiling-windows11-', dir='/tmp')
    figli = []
    update_server = None

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
                    XDG_RUNTIME_DIR=tmp, MINERVA_SESSIONE='impostazioni-test',
                    XDG_SESSION_ID='impostazioni-test', QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software',
                    QT_QPA_PLATFORMTHEME='', QT_NO_XDG_DESKTOP_PORTAL='1')
    ambiente.pop('MINERVA_CANALE', None)
    ambiente.pop('WAYLAND_DISPLAY', None)
    riuscita = False
    try:
        if os.environ.get('MINERVA_TEST_LIQUID_UPDATE') == '1':
            import http.server
            import io
            import random
            import threading
            import zipfile
            package = io.BytesIO()
            with zipfile.ZipFile(package, 'w') as archive:
                archive.writestr('Liquid-DE/prova.txt', random.Random(13).randbytes(1024 * 1024))
            package = package.getvalue()
            update_mode = {'status': 200}
            class GithubFixture(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args):
                    pass
                def do_GET(self):
                    try:
                        if '/zip/' in self.path:
                            self.send_response(200)
                            self.send_header('Content-Length', str(len(package)))
                            self.end_headers()
                            for offset in range(0, len(package), 8192):
                                self.wfile.write(package[offset:offset+8192])
                                self.wfile.flush()
                                time.sleep(.02)
                        else:
                            self.send_response(update_mode['status'])
                            if update_mode['status'] == 429:
                                self.send_header('x-ratelimit-reset', '2000000000')
                            self.end_headers()
                            body = {'status':'ahead', 'total_commits':1, 'commits':[{'sha':'2'*40,'commit':{'message':'Menu aggiornato'}}], 'files':[{'filename':'minerva-shell/menu.qml','status':'modified','additions':1,'deletions':1,'patch':'@@ -1 +1 @@\n-old\n+new'}]} if '/compare/' in self.path else {'sha': '2'*40, 'commit': {'message':'<b>Aggiornamento di prova</b>', 'committer':{'date':'2026-10-13T12:00:00Z'}}} if '/commits/' in self.path else {'full_name':'linuxiano85/Liquid-DE','default_branch':'principale'}
                            self.wfile.write(json.dumps(body).encode())
                    except (BrokenPipeError, ConnectionResetError):
                        pass
            update_server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), GithubFixture)
            threading.Thread(target=update_server.serve_forever, daemon=True).start()
            ambiente['MINERVA_UPDATE_TEST_API'] = 'http://127.0.0.1:' + str(update_server.server_port) + '/'
            installed = Path(tmp)/'update-install'
            installed.mkdir()
            (installed/'liquid-build.json').write_text(json.dumps({'repository':'linuxiano85/Liquid-DE','revision':'1'*40,'dirty':True,'version':'1.0.0'}))
        lancia([os.environ.get('MINERVA_TEST_COMPOSITOR', str(ROOT / 'compositore/build-native/minerva-wayland'))], ambiente, 'compositore')

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

        # Il primo evento crea la tastiera sintetica del compositore. Farlo
        # prima della finestra evita di usarne la prima lettera come ingresso
        # nel seat invece che come digitazione (come nel test Windows).
        cmd('tasto Shift_L premi')
        cmd('tasto Shift_L lascia')
        presa = tmp + '/settings.sock'
        lancia(['dart', 'run', str(ROOT / 'minervad/test/windows11_fixture.dart'), tmp], ambiente, 'demone')
        aspetta(lambda: Path(presa).exists(), 60)
        canale_demone = Path(tmp) / 'liquid-de/sessioni/impostazioni-test/canale'
        canale_demone.parent.mkdir(parents=True)
        canale_demone.write_text('socket=' + presa + '\nsegreto=private-category-fixture\n')
        canale_demone.chmod(0o600)

        photos = Path(tmp) / 'photos-personnalisees'
        photos.mkdir()
        (photos / 'album').mkdir()
        (photos / 'autre').mkdir()
        Image.new('RGB', (300, 200), '#347DC8').save(photos / 'photo # été.png')
        Image.new('RGB', (300, 200), '#56B89E').save(photos / 'album/deux.png')
        (photos / 'document.txt').write_text('Pas une image')
        (photos / 'cassee.png').write_text('Fichier corrompu')
        shell = Path(tmp) / 'shell.qml'
        # Wallpaper.ownDir segue la cartella della shell: la fixture vive
        # in /tmp, quindi le servono gli stessi asset dell'app installata.
        (Path(tmp) / 'assets').symlink_to(ROOT / 'minerva-shell/assets', target_is_directory=True)
        testo = (ROOT / 'tests/fixtures/impostazioni-windows.qml').read_text()
        for segno, cartella in (('@CORE@', 'minerva-shell/core'), ('@SETTINGS@', 'minerva-shell/settings'),
                                ('@THEME@', 'minerva-shell/theme')):
            testo = testo.replace(segno, (ROOT / cartella).as_uri())
        shell.write_text(testo)
        ambiente_ui = dict(ambiente, MINERVA_SCRIVANIA='1', MINERVA_IPC_SOCKET=presa)
        if os.environ.get('MINERVA_TEST_PICKER_NATIVE_CHANNEL') == '1':
            ambiente_ui['MINERVA_CANALE'] = canale
        ambiente_ui['QML_IMPORT_PATH'] = str(ROOT / 'minerva-shell/native')
        lancia(['qs', '-p', str(shell)], ambiente_ui, 'shell')

        def chiama(*argomenti):
            r = subprocess.run(['qs', '-p', str(shell), 'ipc', 'call', 'impostazioni-windows', *argomenti],
                               env=ambiente_ui, text=True, capture_output=True, timeout=10)
            return r.stdout.strip() if r.returncode == 0 else ''

        def stato():
            grezzo = chiama('stato')
            return json.loads(grezzo) if grezzo.startswith('{') else {}

        def finestra():
            elenco = json.loads(cmd('finestre')[3:])
            return next(w for w in elenco if w['titolo'].startswith('Minerva'))

        def clic(x, y):
            w = finestra()
            cmd(f"dito {w['x'] + x} {w['y'] + y}")
            time.sleep(0.15)
            cmd('dito premi')
            cmd('dito lascia')
            time.sleep(0.6)

        def clic_su(nome):
            chiama('mostra', nome)
            time.sleep(0.1)
            c = stato()['controlli'].get(nome)
            assert c, (nome, sorted(stato()['controlli']))
            clic(c['x'], c['y'])

        def cattura(nome):
            percorso = ART / (nome + '.png')
            subprocess.run(['grim', '-o', 'HEADLESS-1', str(percorso)], env=ambiente, check=True, timeout=10)
            with Image.open(percorso) as img:
                variazione = ImageStat.Stat(img.convert('RGB').resize((128, 72))).stddev
            controlla(max(variazione) > 8, nome + ': la cattura non è vuota', variazione)

        aspetta(lambda: stato().get('pronto'), 60)
        chiama('preset', 'liquid')
        aspetta(lambda: stato().get('preset') == 'liquid')
        time.sleep(1)

        # ── In Liquid non cambia niente ──────────────────────────────────
        s = stato()
        liquid = s['colori']
        controlla(not s['windows'], 'in Liquid la finestra non è in stile Windows')
        controlla('colonnaLiquid' in s['controlli'] and not any(k.startswith('navWindows-') for k in s['controlli']),
                  'in Liquid si vede la colonna a gruppi, non la navigazione Windows')
        controlla(s['carattere'] == 'Adwaita Sans', 'in Liquid il carattere resta quello di Liquid', s['carattere'])
        cattura('liquid')

        # ── Windows, chiaro ─────────────────────────────────────────────
        chiama('tema', 'chiaro')
        chiama('preset', 'windows')
        aspetta(lambda: stato().get('windows'))
        time.sleep(1)
        if os.environ.get('MINERVA_TEST_SETTINGS_TITLEBAR') == '1':
            def titolo_stato():
                return json.loads(chiama('titoloStato'))
            def tasto(nome):
                cmd('tasto ' + nome + ' premi')
                cmd('tasto ' + nome + ' lascia')
                time.sleep(0.1)
            s = stato()
            categorie = [k for k in s['controlli'] if k.startswith('navWindows-')]
            controlla(len(categorie) == 12, 'presenti le dodici categorie misurate nella VM', categorie)
            campo = s['controlli']['cercaWindows']
            controlla(campo['w'] == 516 and campo['h'] == 32 and campo['y'] == 24,
                      'ricerca 516×32 a y=8 come nella VM', campo)
            indietro = s['controlli']['indietroWindows']
            controlla(indietro['w'] == 40 and indietro['h'] == 36,
                      'Indietro misura 40×36', indietro)
            chiama('paginaWindows', 'w-sfondo')
            aspetta(lambda: titolo_stato()['pagina'] == 'w-sfondo')
            clic_su('indietroWindows')
            aspetta(lambda: titolo_stato()['pagina'] == 'w-personalizzazione')
            controlla(True, 'clic Indietro riporta Sfondo a Personalizzazione')
            chiama('paginaWindows', 'w-colori')
            aspetta(lambda: titolo_stato()['pagina'] == 'w-colori')
            controlla(stato()['controlli']['paginaTitolo']['testo'] == 'Colori',
                      'la nuova pagina Colori è caricata nella finestra vera')
            titoli = titolo_stato()['titoli']
            controlla(len(titoli) == 3 and all(w > 100 for w in titoli.values()),
                      'i titoli delle schede Colori hanno spazio e sono visibili', titoli)
            clic_su('ricercaWindows')
            for lettera in 'audio':
                tasto(lettera)
            aspetta(lambda: titolo_stato()['ricerca'] == 'audio')
            controlla('navCerca-audio' in stato()['controlli'], 'la ricerca digitata trova Audio')
            tasto('Escape')
            aspetta(lambda: titolo_stato()['ricerca'] == '')
            controlla(titolo_stato()['campo']['testo'] == '', 'Esc cancella anche il testo visibile')
            chiama('cerca', 'volume')
            aspetta(lambda: titolo_stato()['campo']['testo'] == 'volume')
            controlla(True, 'il campo segue anche la ricerca cambiata da un altro controllo')
            chiama('cerca', '')
            cattura('titolo-windows-chiaro')
            chiama('tema', 'scuro')
            time.sleep(1)
            cattura('titolo-windows-scuro')
            chiama('preset', 'liquid')
            aspetta(lambda: not stato()['windows'])
            controlla('cercaWindows' not in stato()['controlli'], 'Liquid mantiene la propria barra')
            errori = [r for r in Path(tmp + '/shell.log').read_text().splitlines()
                      if re.search(r'ReferenceError|TypeError|Cannot assign|is not a type|Error loading QML|Binding loop', r)]
            controlla(not errori, 'nessun errore QML nelle pagine e nella barra', errori)
            (ART / 'esito-titolo.json').write_text(json.dumps({'passati': PASSATI, 'erroriQml': errori}, indent=2))
            print(f'FINE {PASSATI} controlli passati')
            riuscita = True
            return 0
        if os.environ.get('MINERVA_TEST_LIQUID_UPDATE') == '1':
            def update():
                return json.loads(chiama('updateState'))
            clic_su('navWindows-update')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update' and update().get('repository'))
            controlla(stato()['categoriaAttiva'] == 'update', 'Liquid Update è collegato alla categoria reale')
            controlla(stato()['controlli']['paginaTitolo']['testo'] == 'Liquid Update', 'nome Liquid Update nel titolo')
            clic_su('liquidUpdateCheck')
            aspetta(lambda: update().get('phase') == 'checked')
            controlla(update()['updateAvailable'], 'la pagina riceve la nuova revisione GitHub')
            controlla(update()['installed']['dirty'], 'le modifiche locali restano dichiarate')
            cattura('liquid-update-chiaro')
            controlla(update()['comparison']['components'] == {'shell':1}, 'changelog identifica solo la Shell interessata')
            clic_su('liquidUpdateChanges')
            aspetta(lambda: 'liquidUpdateFile' in stato()['controlli'])
            controlla(stato()['controlli']['paginaTitolo']['testo'] == 'Cosa cambia', 'dettaglio modifiche nella pagina reale')
            clic_su('liquidUpdateFile')
            aspetta(lambda: 'liquidUpdatePatch' in stato()['controlli'])
            controlla('\n+new' in stato()['controlli']['liquidUpdatePatch']['testo'], 'espansione mostra righe del confronto reale')
            cattura('liquid-update-modifiche')
            clic_su('briciolaCategoria')
            aspetta(lambda: 'liquidUpdateDownload' in stato()['controlli'])
            clic_su('liquidUpdateDownload')
            aspetta(lambda: update().get('phase') == 'downloading' and update().get('received',0) > 0)
            controlla(True, 'Scarica avvia un trasferimento reale')
            clic_su('liquidUpdateCancel')
            aspetta(lambda: update().get('phase') == 'cancelled')
            controlla(not list((Path(tmp)/'updates').glob('*.part')), 'Annulla non lascia archivi parziali')
            clic_su('liquidUpdateDownload')
            aspetta(lambda: update().get('phase') == 'ready', 30)
            controlla(update()['downloaded'] and len(update()['history']) == 1, 'download verificato e cronologia vera')
            controlla(len(update()['history'][0]['sha256']) == 64, 'SHA-256 presente dopo il download')
            cattura('liquid-update-pronto')
            clic_su('liquidUpdatePause')
            aspetta(lambda: update()['paused'])
            controlla(True, 'Sospendi imposta la pausa nel servizio')
            clic_su('liquidUpdatePause')
            aspetta(lambda: not update()['paused'])
            controlla(True, 'Riprendi toglie la pausa')
            clic_su('liquidUpdateHistory')
            aspetta(lambda: stato()['controlli']['paginaTitolo']['testo'] == 'Cronologia dei download')
            controlla(True, 'Cronologia apre una pagina con i dati del servizio')
            cattura('liquid-update-cronologia')
            clic_su('briciolaCategoria')
            aspetta(lambda: 'liquidUpdateAdvanced' in stato()['controlli'])
            clic_su('liquidUpdateAdvanced')
            aspetta(lambda: stato()['controlli']['paginaTitolo']['testo'] == 'Opzioni avanzate')
            controlla(True, 'Opzioni avanzate mostra repository e versione')
            clic_su('briciolaCategoria')
            aspetta(lambda: 'liquidUpdateCheck' in stato()['controlli'])
            update_mode['status'] = 429
            clic_su('liquidUpdateCheck')
            aspetta(lambda: update().get('phase') == 'error')
            controlla(update()['error'] == 'http_429', 'limite GitHub viene presentato come errore')
            cattura('liquid-update-errore')
            update_mode['status'] = 200
            chiama('tema','scuro')
            aspetta(lambda: stato()['colori']['scura'])
            clic_su('liquidUpdateCheck')
            aspetta(lambda: update().get('phase') == 'checked')
            cattura('liquid-update-scuro')
            chiama('lingua','en')
            aspetta(lambda: stato()['controlli']['liquidUpdateStatus']['testo'] == 'Source archive ready')
            controlla(True, 'Liquid Update risponde al cambio di lingua in inglese')
            cattura('liquid-update-inglese')
            logs = (Path(tmp)/'shell.log').read_text().splitlines()
            errors = [line for line in logs if re.search(r'ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop|Error loading QML', line)]
            controlla(not errors, 'nessun errore QML in Liquid Update', errors)
            (ART/'liquid-update.json').write_text(json.dumps({'passati':PASSATI,'erroriQml':errors},indent=2))
            riuscita = True
            return 0
        if os.environ.get('MINERVA_TEST_WALLPAPER_PICKER') == '1':
            chiama('paginaWindows', 'w-sfondo')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sfondo')
            def scelta():
                return json.loads(chiama('sceltaStato'))
            def clic_dialogo(nome):
                control = scelta()['controls'][nome]
                win = next(w for w in json.loads(cmd('finestre')[3:]) if w['titolo'] == 'Apri')
                cmd(f"dito {win['x'] + control['x']} {win['y'] + control['y']}")
                cmd('dito premi')
                cmd('dito lascia')
                time.sleep(0.5)
            def tasto_dialogo(key):
                cmd('tasto ' + key + ' premi')
                cmd('tasto ' + key + ' lascia')
                time.sleep(0.1)
            def digita_dialogo(text):
                for char in text:
                    if char == '/' and os.environ.get('MINERVA_TEST_PICKER_NATIVE_CHANNEL') == '1':
                        cmd('tasto Shift_L premi')
                        tasto_dialogo('7')
                        cmd('tasto Shift_L lascia')
                    else:
                        tasto_dialogo({'/': 'slash', '.': 'period', ' ': 'space', '-': 'minus'}.get(char, char))
            def cancella_campo():
                cmd('tasto Control_L premi')
                tasto_dialogo('a')
                cmd('tasto Control_L lascia')
                tasto_dialogo('BackSpace')
            before = json.loads(chiama('valore', 'desktop.wallpaper'))
            clic_su('sfogliaFoto')
            aspetta(lambda: scelta().get('directory') == str(photos) and not scelta().get('loading'), 20)
            pick = scelta()
            controlla(pick['hasOwner'] and pick['modality'] == 1, 'finestra Apri separata, modale e collegata alle Impostazioni', pick)
            controlla('document.txt' in pick['names'] and 'photo # été.png' in pick['names'], 'Tutti i file mostra l’elenco vero con nomi Unicode')
            controlla(pick['controls']['fileWindowsNome']['text'] == '', 'il dialogo non preseleziona arbitrariamente una cartella')
            nav = stato()['controlli']['navWindows-rete']
            clic(nav['x'] - nav['w'] / 2 + 4, nav['y'])
            controlla(stato()['paginaWindows'] == 'w-sfondo' and scelta()['directory'] == str(photos), 'la finestra modale blocca i clic alle Impostazioni sottostanti')
            cattura('sfondo-modal-dopo-owner')
            clic_dialogo('fileWindowsFiltro')
            clic_dialogo('tendinaVoce-images')
            controlla('document.txt' not in scelta()['names'] and 'photo # été.png' in scelta()['names'], 'il filtro Immagini nasconde i documenti e conserva le cartelle', scelta())
            clic_dialogo('fileWindowsVista')
            clic_dialogo('fileWindowsAnteprima')
            clic_dialogo('fileWindowsRicerca')
            digita_dialogo('zzz')
            controlla(scelta()['names'] == [], 'ricerca senza risultati non lascia anteprime o selezioni vecchie')
            cancella_campo()
            chiama('tema', 'scuro')
            time.sleep(0.3)
            cattura('sfondo-apri-scuro')
            chiama('tema', 'chiaro')
            aspetta(lambda: not stato()['colori']['scura'])
            time.sleep(0.2)
            cattura('sfondo-finestra-apri')
            clic_dialogo('fileWindowsAnnulla')
            aspetta(lambda: not scelta()['visible'])
            controlla(json.loads(chiama('valore', 'desktop.wallpaper')) == before, 'Annulla conserva lo sfondo')
            clic_su('sfogliaFoto')
            aspetta(lambda: scelta().get('directory') == str(photos) and not scelta().get('loading'))
            # Selezione con mouse; ricerca del nome nel modello anziché indice fisso.
            index = scelta()['names'].index('photo # été.png')
            clic_dialogo('fileWindowsVoce-' + str(index))
            clic_dialogo('fileWindowsConferma')
            aspetta(lambda: not scelta()['visible'])
            controlla(json.loads(chiama('valore', 'desktop.wallpaper')) == str(photos / 'photo # été.png'), 'Scegli immagine applica il file selezionato con spazi, # e Unicode')
            aspetta(lambda: stato()['controlli'].get('anteprimaSfondoFoto', {}).get('status') == 1)
            controlla(True, 'l’immagine con # è realmente decodificata nell’anteprima dello sfondo')
            clic_su('sfogliaFoto')
            aspetta(lambda: not scelta().get('loading') and scelta()['visible'])
            index = scelta()['names'].index('cassee.png')
            clic_dialogo('fileWindowsVoce-' + str(index))
            clic_dialogo('fileWindowsConferma')
            aspetta(lambda: bool(scelta().get('error')))
            controlla(scelta()['visible'] and json.loads(chiama('valore', 'desktop.wallpaper')) == str(photos / 'photo # été.png'), 'immagine corrotta resta nel dialogo senza cambiare sfondo')
            tasto_dialogo('Escape')
            aspetta(lambda: not scelta()['visible'])
            controlla(True, 'Esc annulla il dialogo')
            clic_su('sfogliaFoto')
            aspetta(lambda: scelta()['visible'] and not scelta()['loading'])
            clic_dialogo('fileWindowsNome')
            cancella_campo()
            digita_dialogo('album/deux.png')
            tasto_dialogo('Return')
            aspetta(lambda: not scelta()['visible'])
            controlla(json.loads(chiama('valore', 'desktop.wallpaper')) == str(photos / 'album/deux.png'), 'un percorso digitato naviga e applica l’immagine esistente')
            clic_su('sfogliaFoto')
            aspetta(lambda: scelta()['visible'] and not scelta()['loading'])
            cmd('tasto Alt_L premi')
            tasto_dialogo('Left')
            cmd('tasto Alt_L lascia')
            # Una nuova apertura ricrea lo storico: Alt+Su torna alla cartella padre.
            cmd('tasto Alt_L premi')
            tasto_dialogo('Up')
            cmd('tasto Alt_L lascia')
            aspetta(lambda: scelta()['directory'] == str(photos) and not scelta()['loading'])
            controlla(True, 'Alt+Su sale di una cartella')
            clic_dialogo('fileWindowsNuovaCartella')
            digita_dialogo('nouveau')
            tasto_dialogo('Return')
            aspetta(lambda: scelta()['directory'] == str(photos / 'nouveau') and not scelta()['loading'])
            controlla((photos / 'nouveau').is_dir(), 'Nuova cartella crea realmente una cartella nella fixture')
            clic_dialogo('fileWindowsAnnulla')
            aspetta(lambda: not scelta()['visible'])
            chiama('fuoco', 'tendinaTipoSfondo')
            tasto_dialogo('Down')
            tasto_dialogo('Down')
            aspetta(lambda: json.loads(chiama('valore', 'desktop.wallpaperMode')) == 'folder')
            clic_su('sfogliaAlbum')
            aspetta(lambda: scelta()['visible'] and scelta()['folderOnly'] and not scelta()['loading'])
            controlla(all(name in ['album', 'autre', 'nouveau'] for name in scelta()['names']), 'l’album mostra soltanto cartelle')
            clic_dialogo('fileWindowsConferma')
            aspetta(lambda: not scelta()['visible'])
            controlla(json.loads(chiama('valore', 'desktop.wallpaperFolder')) == str(photos), 'Seleziona cartella applica la cartella corrente come album')
            # La nuova politica del compositore riguarda solo i modali:
            # una finestra non modale deve lasciare utilizzare la madre.
            chiama('fuoco', 'tendinaTipoSfondo')
            tasto_dialogo('Down')
            aspetta(lambda: json.loads(chiama('valore', 'desktop.wallpaperMode')) == 'image')
            clic_su('sfogliaFoto')
            aspetta(lambda: scelta()['visible'] and not scelta()['loading'])
            chiama('sceltaModale', 'false')
            nav = stato()['controlli']['navWindows-rete']
            clic(nav['x'] - nav['w']/2 + 4, nav['y'])
            cattura('dialogo-non-modale-dopo-click')
            aspetta(lambda: stato()['sezione'] == 'network' and stato()['paginaWindows'] == '')
            controlla(True, 'un dialogo non modale lascia usare la madre e si chiude quando cambia pagina')
            actions = json.loads((Path(tmp) / 'actions.json').read_text())
            listings = [a for a in actions if a.get('action') == 'fs_list' and str(a.get('pane', '')).startswith('scelta-windows-')]
            controlla(listings and all(a.get('watch') is False for a in listings), 'tutti gli elenchi del selettore escludono gli osservatori persistenti')
            logs = (Path(tmp) / 'shell.log').read_text().splitlines()
            errors = [line for line in logs if re.search(r'ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop|Error loading QML', line)]
            controlla(not errors, 'nessun errore QML nel selettore', errors)
            (ART / 'selettore.json').write_text(json.dumps({'passati': PASSATI, 'erroriQml': errors}, indent=2))
            riuscita = True
            return 0
        if os.environ.get('MINERVA_TEST_SETTINGS_HISTORY') == '1':
            def key(name):
                cmd('tasto ' + name + ' premi')
                cmd('tasto ' + name + ' lascia')
                time.sleep(0.1)
            chiama('paginaWindows','w-home')
            initial = len(stato()['cronologia'])
            clic_su('navWindows-home')
            controlla(len(stato()['cronologia']) == initial, 'ripetere la stessa destinazione non duplica lo storico')
            clic_su('navWindows-sistema')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sistema')
            clic_su('categoriaVoce-shell')
            aspetta(lambda: stato()['sezione'] == 'shell' and stato()['paginaWindows'] == '')
            controlla(stato()['categoriaAttiva'] == 'sistema', 'pagina legacy conserva il contesto registrato')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sistema')
            controlla(True, 'Indietro ripristina la categoria appena visitata')
            cmd('tasto Alt_L premi')
            key('Left')
            cmd('tasto Alt_L lascia')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            controlla(True, 'Alt+Sinistra torna alla Home precedente')
            clic_su('navWindows-update')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update')
            clic_su('liquidUpdateHistory')
            aspetta(lambda: stato()['percorso']['vista'] == 'history')
            clic_su('briciolaCategoria')
            aspetta(lambda: stato()['percorso']['vista'] == '')
            controlla(True, 'la briciola torna alla radice Liquid Update')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['percorso']['vista'] == 'history')
            controlla(True, 'Indietro dopo la briciola ripristina la cronologia interna')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update' and stato()['percorso']['vista'] == '')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            controlla(True, 'storico interno e categorie tornano senza cicli')
            clic_su('navWindows-sistema')
            chiama('mostra','categoriaVoce-shell')
            time.sleep(0.3)
            scroll = stato()['percorso']['scorrimento']
            controlla(scroll > 0, 'pagina lunga scorsa prima della navigazione')
            clic_su('categoriaVoce-shell')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sistema' and abs(stato()['percorso']['scorrimento'] - scroll) < 2)
            controlla(True, 'Indietro ripristina la posizione di scorrimento')
            cattura('navigazione-scorrimento-ripristinato')
            for index in range(55):
                chiama('paginaWindows','w-home' if index % 2 else 'w-sistema')
            controlla(len(stato()['cronologia']) == 50, 'lo storico resta limitato a cinquanta destinazioni')
            chiama('preset','liquid')
            aspetta(lambda: not stato()['windows'])
            controlla(not stato()['cronologia'], 'cambio preset azzera lo storico Windows')
            chiama('sezione','finestre')
            chiama('scorrimento','200')
            time.sleep(0.2)
            classic_scroll = stato()['percorso']['scorrimento']
            chiama('sezione','finestre')
            time.sleep(0.2)
            controlla(classic_scroll > 0 and abs(stato()['percorso']['scorrimento'] - classic_scroll) < 2, 'richiamare una pagina Liquid non altera lo scorrimento')
            chiama('preset','windows')
            aspetta(lambda: stato()['windows'])
            controlla(not stato()['cronologia'], 'ritorno a Windows non recupera percorsi di Liquid')
            logs = (Path(tmp)/'shell.log').read_text().splitlines()
            errors = [line for line in logs if re.search(r'ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop|Error loading QML', line)]
            controlla(not errors, 'nessun errore QML nello storico', errors)
            (ART/'storico.json').write_text(json.dumps({'passati':PASSATI,'erroriQml':errors},indent=2))
            riuscita = True
            return 0
        if os.environ.get('MINERVA_TEST_SETTINGS_SYSTEM') == '1':
            clic_su('navWindows-sistema')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sistema')
            controlla(stato()['controlli']['paginaTitolo']['testo'] == 'Sistema', 'Sistema nativo usa il titolo della VM')
            controlla(stato()['controlli']['indietroWindows']['enabled'], 'Sistema conserva la pagina visitata prima')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == '' and stato()['sezione'] == 'display')
            clic_su('navWindows-sistema')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sistema')
            voci = [k for k in stato()['controlli'] if k.startswith('categoriaVoce-')]
            controlla(len(voci) == 20, 'Sistema comprende le voci previste e le scorciatoie Liquid', voci)
            cattura('sistema-stretto-chiaro')
            for control, section in [('display','display'), ('audio','audio'), ('notifiche','notifiche'), ('power','power'), ('multitasking','finestre'), ('shell','shell'), ('scorciatoie','scorciatoie')]:
                clic_su('categoriaVoce-' + control)
                aspetta(lambda: stato()['sezione'] == section and stato()['paginaWindows'] == '')
                controlla(stato()['categoriaAttiva'] == 'sistema', control + ' conserva il contesto Sistema')
                controlla(stato()['controlli']['briciolaCategoria']['testo'] == 'Sistema', control + ' mostra la briciola corretta')
                clic_su('indietroWindows')
                aspetta(lambda: stato()['paginaWindows'] == 'w-sistema')
                controlla(True, control + ' torna a Sistema con Indietro')
            controlla(not stato()['controlli']['categoriaVoce-concentrazione']['enabled'], 'funzione assente disabilitata anche per accessibilità')
            clic_su('categoriaVoce-concentrazione')
            controlla(stato()['paginaWindows'] == 'w-sistema', 'funzione assente non apre una pagina estranea')
            cmd('schermo HEADLESS-1 1920x1080@60 1 0')
            cmd(f'ridimensiona {finestra()["id"]} 1920 980')
            cmd(f'sposta {finestra()["id"]} 0 0')
            chiama('mostra','systemDeviceName')
            time.sleep(0.4)
            cattura('sistema-largo-chiaro')
            chiama('tema','scuro')
            time.sleep(0.3)
            cattura('sistema-scuro')
            clic_su('systemUpdate')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update')
            controlla(stato()['controlli']['indietroWindows']['enabled'], 'Liquid Update conserva Sistema nello storico')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-sistema')
            clic_su('systemUpdate')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update')
            clic_su('liquidUpdateHistory')
            aspetta(lambda: stato()['controlli']['indietroWindows']['enabled'])
            clic_su('indietroWindows')
            aspetta(lambda: 'liquidUpdateHistory' in stato()['controlli'])
            controlla(stato()['paginaWindows'] == 'w-update', 'Indietro dalla cronologia resta in Liquid Update')
            clic_su('navWindows-home')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            controlla(stato()['controlli']['indietroWindows']['enabled'], 'Home conserva la pagina precedente nello storico')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update')
            clic_su('navWindows-home')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            clic_su('homePersonalization')
            aspetta(lambda: stato()['paginaWindows'] == 'w-personalizzazione')
            clic_su('categoriaVoce-colori')
            aspetta(lambda: stato()['paginaWindows'] == 'w-colori')
            clic_su('indietroWindows')
            aspetta(lambda: stato()['paginaWindows'] == 'w-personalizzazione')
            controlla(True, 'Indietro da Colori conserva la navigazione Personalizzazione')
            chiama('preset','liquid')
            aspetta(lambda: not stato()['windows'])
            controlla(stato()['paginaWindows'] == '', 'Liquid mantiene le sue pagine indipendenti')
            logs = (Path(tmp)/'shell.log').read_text().splitlines()
            errors = [line for line in logs if re.search(r'ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop|Error loading QML', line)]
            controlla(not errors, 'nessun errore QML in Sistema e navigazione', errors)
            (ART/'sistema.json').write_text(json.dumps({'passati':PASSATI,'erroriQml':errors},indent=2))
            riuscita = True
            return 0
        if os.environ.get('MINERVA_TEST_SETTINGS_HOME') == '1':
            clic_su('navWindows-home')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home' and stato()['controlli'].get('homeDeviceName', {}).get('testo') == 'LIQUID-TEST')
            controlla(stato()['categoriaAttiva'] == 'home', 'Home nativa collegata alla navigazione reale')
            controlla(stato()['controlli']['paginaTitolo']['testo'] == 'Home', 'titolo Home come nella VM')
            controlla('homeRecommended-power' in stato()['controlli'] and 'homePersonalization' in stato()['controlli'], 'schede Home concrete, non categoria vuota')
            cattura('home-stretta-chiaro')
            for control, section in [('homeRecommended-power','power'), ('homeRecommended-defaults','defaults'), ('homeAccessibility','accesso-facile'), ('homeAbout','shell')]:
                clic_su(control)
                aspetta(lambda: stato()['sezione'] == section and stato()['paginaWindows'] == '')
                controlla(True, control + ' apre la pagina funzionale')
                clic_su('navWindows-home')
                aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            clic_su('homePersonalization')
            aspetta(lambda: stato()['paginaWindows'] == 'w-personalizzazione')
            controlla(True, 'Esplora temi apre Personalizzazione nativa')
            clic_su('navWindows-home')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            cmd('schermo HEADLESS-1 1920x1080@60 1 0')
            cmd(f'ridimensiona {finestra()["id"]} 1920 980')
            cmd(f'sposta {finestra()["id"]} 0 0')
            time.sleep(0.5)
            controlla('homeUpdate' in stato()['controlli'], 'Home larga mostra Liquid Update')
            cattura('home-larga-chiaro')
            clic_su('homeUpdate')
            aspetta(lambda: stato()['paginaWindows'] == 'w-update')
            controlla(True, 'riepilogo aggiornamenti apre il servizio reale')
            clic_su('navWindows-home')
            aspetta(lambda: stato()['paginaWindows'] == 'w-home')
            clic_su('homeTheme-windows-scuro')
            aspetta(lambda: json.loads(chiama('valore','windows11.theme')) == 'dark')
            controlla(stato()['colori']['scura'], 'tema rapido cambia preferenza e colori della Home')
            cattura('home-larga-scuro')
            clic_su('homeColorMode')
            cattura('home-tendina-click')
            clic_su('tendinaVoce-light')
            aspetta(lambda: not stato()['colori']['scura'])
            controlla(True, 'tendina Modalità colore riporta in chiaro')
            chiama('lingua','en')
            time.sleep(0.3)
            cattura('home-inglese')
            controlla(stato()['categoriaAttiva'] == 'home', 'cambio lingua conserva la Home')
            cmd(f'ridimensiona {finestra()["id"]} 850 650')
            time.sleep(0.4)
            cattura('home-piccola')
            controlla('homeUpdate' not in stato()['controlli'], 'layout stretto evita sovrapposizioni nella testata')
            clic_su('homeAbout')
            aspetta(lambda: stato()['sezione'] == 'shell')
            controlla(True, 'pagina lunga resta navigabile con scorrimento')
            chiama('preset','liquid')
            aspetta(lambda: not stato()['windows'])
            controlla(stato()['paginaWindows'] == '', 'ritorno a Liquid rimuove la pagina Windows')
            logs = (Path(tmp)/'shell.log').read_text().splitlines()
            errors = [line for line in logs if re.search(r'ReferenceError|TypeError|Cannot assign|Unable to assign|Binding loop|Error loading QML', line)]
            controlla(not errors, 'nessun errore QML nella Home', errors)
            (ART/'home.json').write_text(json.dumps({'passati':PASSATI,'erroriQml':errors},indent=2))
            riuscita = True
            return 0
        if os.environ.get('MINERVA_TEST_SETTINGS_ENTRYPOINT') == '1':
            # L'ingresso produttivo completo, con un osservatore solo nella
            # copia temporanea: il comando IPC rimane quello di produzione.
            source = (ROOT / 'minerva-shell/settings.qml').read_text()
            for module in ['theme', 'core', 'settings']:
                source = source.replace('import "' + module + '"', 'import "' + (ROOT / 'minerva-shell' / module).as_uri() + '"')
            observer = """
    IpcHandler {
        target: "entry-test"
        function stato(): string {
            return JSON.stringify({ready: Core.Ipc.impostazioniArrivate,
                windows: panel.stileWindows, page: panel.paginaWindows, section: panel.section, initialized:panel.avvioGestito});
        }
    }
"""
            source = source.rsplit('}', 1)[0] + observer + '}\n'
            entry = Path(tmp) / 'entry.qml'
            entry.write_text(source)
            env_entry = dict(ambiente_ui, MINERVA_SETTINGS_SECTION='' if os.environ.get('MINERVA_TEST_SETTINGS_DEFAULT_HOME') == '1' else 'audio' if os.environ.get('MINERVA_TEST_SETTINGS_ENTRY_AUDIO') == '1' else 'w-barra')
            lancia(['qs', '-p', str(entry)], env_entry, 'entry')
            def entry_call(target, method, *args):
                result = subprocess.run(['qs', '-p', str(entry), 'ipc', 'call', target, method, *args],
                                        env=env_entry, capture_output=True, text=True, timeout=10)
                return result.stdout.strip()
            def entry_state():
                raw = entry_call('entry-test', 'stato')
                return json.loads(raw) if raw.startswith('{') else {}
            expected_page = 'w-home' if os.environ.get('MINERVA_TEST_SETTINGS_DEFAULT_HOME') == '1' else '' if os.environ.get('MINERVA_TEST_SETTINGS_ENTRY_AUDIO') == '1' else 'w-barra'
            aspetta(lambda: (lambda state: state.get('initialized') and state.get('ready') and state.get('windows') and state.get('page') == expected_page and (state.get('section') == 'audio' if expected_page == '' else True))(entry_state()), 30)
            controlla(True, 'ingresso produttivo rispetta Home o destinazione esplicita')
            entry_call('settings', 'open', 'w-start')
            aspetta(lambda: entry_state().get('page') == 'w-start')
            controlla(True, 'ingresso completo cambia pagina Windows via IPC')
            entry_call('settings', 'open', 'audio')
            aspetta(lambda: entry_state().get('page') == '' and entry_state().get('section') == 'audio')
            controlla(True, 'aprire Audio rimuove la precedente pagina Windows')
            entry_call('settings', 'open', 'w-barra')
            aspetta(lambda: entry_state().get('page') == 'w-barra')
            controlla(True, 'ingresso completo riapre Barra dopo una sezione Liquid')
            entry_call('settings','open','')
            time.sleep(0.2)
            controlla(entry_state()['page'] == 'w-barra', 'richiamare una finestra già aperta conserva la pagina scelta')
            errors = [r for r in (Path(tmp) / 'entry.log').read_text().splitlines()
                      if re.search(r'ReferenceError|TypeError|Cannot assign|is not a type|Error loading QML|Binding loop', r)]
            controlla(not errors, 'nessun errore QML nell’ingresso delle Impostazioni', errors)
            (ART / 'ingresso.json').write_text(json.dumps({'passati': PASSATI, 'erroriQml': errors}, indent=2))
            riuscita = True
            return 0
        s = stato()
        controlla(s['colori']['finestra'] == '#f3f3f3', 'in Windows chiaro il fondo è quello di Windows 11',
                  s['colori'])
        controlla(not s['colori']['scura'], 'in Windows chiaro la tavolozza è chiara')
        controlla(s['carattere'] != 'Adwaita Sans', 'in Windows il carattere è quello di Windows', s['carattere'])
        mancanti = [c for c in CATEGORIE if 'navWindows-' + c not in s['controlli']]
        controlla(not mancanti, 'la navigazione mostra le dodici categorie di Windows', mancanti)
        controlla('colonnaLiquid' not in s['controlli'], 'la colonna di Liquid non si vede in Windows')
        controlla(not s['fuoriPosto'], 'ogni pagina sta in una categoria e una sola', s['fuoriPosto'])
        controlla('utenteWindows' in s['controlli'], 'in cima alla navigazione c\'è il riquadro utente')
        controlla(s['categoriaAttiva'] == 'sistema', 'la sezione Schermo accende la categoria Sistema',
                  s['categoriaAttiva'])

        # ── Categoria, sezione, briciola ─────────────────────────────────
        clic_su('navWindows-personalizzazione')
        s = aspetta(lambda: (lambda t: t if t.get('paginaWindows') == 'w-personalizzazione' else None)(stato()))
        voci = [k for k in s['controlli'] if k.startswith('categoriaVoce-')]
        controlla(sorted(voci) == sorted('categoriaVoce-' + v for v in
                                         ('sfondo', 'colori', 'temi', 'illuminazione', 'blocco', 'immissione', 'start', 'barra', 'caratteri')),
                  'Personalizzazione elenca le voci misurate nella VM', voci)
        cattura('windows-categoria-chiaro')
        for id in ('sfondo', 'colori', 'temi', 'start', 'barra'):
            clic_su('categoriaVoce-' + id)
            aspetta(lambda: stato()['paginaWindows'] == 'w-' + id)
            controlla(stato()['categoriaAttiva'] == 'personalizzazione', id + ' mantiene la categoria corretta')
            cattura('windows-' + id + '-chiaro')
            clic_su('briciolaCategoria')
            aspetta(lambda: stato()['paginaWindows'] == 'w-personalizzazione')
            controlla(True, 'la briciola di ' + id + ' torna alla pagina principale')
        chiama('sezione', 'finestre')
        s = aspetta(lambda: (lambda t: t if t.get('sezione') == 'finestre' and t.get('categoria') == '' else None)(
            stato()))
        b = s['controlli'].get('briciolaCategoria')
        controlla(b and b['testo'] == 'Personalizzazione', 'la sezione mostra la briciola della categoria', b)
        controlla(s['controlli'].get('paginaTitolo', {}).get('testo') == 'Finestre', 'e il titolo della sezione',
                  s['controlli'].get('paginaTitolo'))
        controlla(s['categoriaAttiva'] == 'personalizzazione', 'la categoria resta accesa nella navigazione')
        cattura('windows-sezione-chiaro')
        clic_su('briciolaCategoria')
        aspetta(lambda: stato().get('paginaWindows') == 'w-personalizzazione')
        controlla(True, 'la briciola riporta alla pagina della categoria')

        # ── Categoria di una sezione sola ────────────────────────────────
        clic_su('navWindows-rete')
        s = aspetta(lambda: (lambda t: t if t.get('sezione') == 'network' else None)(stato()))
        controlla(s['categoria'] == '' and 'briciolaCategoria' not in s['controlli'],
                  'Rete e Internet apre direttamente la sua sezione, senza briciola')

        # ── Un interruttore scrive come prima ────────────────────────────
        clic_su('navWindows-sistema')
        aspetta(lambda: stato().get('paginaWindows') == 'w-sistema')
        clic_su('categoriaVoce-notifiche')
        aspetta(lambda: stato().get('sezione') == 'notifiche')
        time.sleep(0.6)
        i = stato()['interruttore']
        controlla(i is not None, 'la pagina Notifiche ha un interruttore visibile', i)
        prima = i['acceso']
        clic(i['x'], i['y'])
        aspetta(lambda: stato()['interruttore']['acceso'] != prima)
        controlla(True, 'il clic sull\'interruttore Windows cambia la scelta passando dal demone')
        cattura('windows-interruttore-chiaro')
        clic(i['x'], i['y'])
        aspetta(lambda: stato()['interruttore']['acceso'] == prima)
        controlla(True, 'un secondo clic la rimette com\'era')

        # ── La ricerca ──────────────────────────────────────────────────
        chiama('cerca', 'luce notturna')
        time.sleep(0.6)
        controlla('navCerca-display' in stato()['controlli'], 'cercando «luce notturna» compare Schermo')
        clic_su('navCerca-display')
        s = aspetta(lambda: (lambda t: t if t.get('sezione') == 'display' else None)(stato()))
        controlla(s['categoriaAttiva'] == 'sistema', 'il risultato apre Schermo, dentro Sistema')
        chiama('cerca', '')

        # ── Ogni pagina, una per una, in Windows chiaro ──────────────────
        # Le catture servono a guardarle: le pagine che disegnano a mano
        # qualcosa che le impalcature non coprono si vedono solo così.
        for categoria in CATEGORIE:
            for sezione in CATEGORIE_SEZIONI[categoria]:
                chiama('sezione', sezione)
                aspetta(lambda: stato().get('sezione') == sezione)
                time.sleep(0.5)
                s = stato()
                controlla(s['categoriaAttiva'] == categoria, sezione + ' sta nella categoria ' + categoria,
                          s['categoriaAttiva'])
                cattura('pagina-' + sezione)

        # ── Windows, scuro ──────────────────────────────────────────────
        # Interazioni native con i controlli nuovi, senza chiamare i loro
        # segnali scelto/applica direttamente dalla fixture.
        def valore(path):
            return json.loads(chiama('valore', path))
        def tasto_reale(name):
            cmd('tasto ' + name + ' premi')
            cmd('tasto ' + name + ' lascia')
            time.sleep(.2)
        chiama('paginaWindows', 'w-sfondo')
        aspetta(lambda: stato()['paginaWindows'] == 'w-sfondo')
        chiama('fuoco', 'tendinaTipoSfondo')
        tasto_reale('Down')
        aspetta(lambda: valore('desktop.wallpaperMode') == 'color')
        controlla(valore('windows11.wallpaper') == 'current', 'Tinta unita disattiva il Bloom automatico')
        tasto_reale('Up')
        aspetta(lambda: valore('desktop.wallpaperMode') == 'image')
        controlla(True, 'la tendina torna a Immagine attraverso il demone')
        chiama('fuoco', 'tendinaAdattamento')
        tasto_reale('Down')
        aspetta(lambda: valore('desktop.wallpaperFit') == 'adatta')
        controlla(True, 'Adatta modifica la chiave reale del layout dello sfondo')
        chiama('paginaWindows', 'w-colori')
        aspetta(lambda: stato()['paginaWindows'] == 'w-colori')
        chiama('fuoco', 'tendinaModalita')
        tasto_reale('Down')
        aspetta(lambda: valore('windows11.theme') == 'dark')
        controlla(valore('windows11.themeApp') == '', 'Scura mantiene app e shell nello stesso tema')
        tasto_reale('Down')
        aspetta(lambda: valore('windows11.themeApp') == 'dark')
        controlla(True, 'Personalizzata attiva la preferenza separata delle app')
        chiama('paginaWindows', 'w-temi')
        aspetta(lambda: stato()['paginaWindows'] == 'w-temi')
        clic_su('salvaTema')
        aspetta(lambda: len(valore('windows11.temi')) == 1)
        controlla(valore('windows11.temi')[0]['tema'] == 'dark', 'Salva tema memorizza tema e accento correnti')
        chiama('fuoco', 'tema-windows-chiaro')
        tasto_reale('Return')
        aspetta(lambda: valore('windows11.temaCorrente') == 'windows-chiaro')
        controlla(valore('windows11.accent').upper() == '#0078D4'
                  and stato()['colori']['accento'].lower() == '#0067c0'
                  and valore('windows11.themeApp') == '',
                  'il tema Windows ripristina accento base, sfumatura dei comandi e modalità comune')
        cattura('windows-temi-applicati')

        # Scelte nuove: clic e tastiera reali, non emissioni di segnali QML.
        chiama('paginaWindows', 'w-start')
        aspetta(lambda: stato()['paginaWindows'] == 'w-start')
        clic_su('layoutStart-pinned')
        aspetta(lambda: valore('windows11.startLayout') == 'pinned')
        controlla(True, 'clic sul layout applica quattro righe ancorate')
        chiama('fuoco', 'layoutStart-recommended')
        tasto_reale('Space')
        aspetta(lambda: valore('windows11.startLayout') == 'recommended')
        controlla(True, 'il layout Start si cambia anche con tastiera')
        consigliati = valore('windows11.recommendations')
        clic_su('startConsigliati')
        aspetta(lambda: valore('windows11.recommendations') != consigliati)
        controlla(True, 'la pagina Start modifica la visibilità dei file recenti')
        chiama('paginaWindows', 'w-barra')
        aspetta(lambda: stato()['paginaWindows'] == 'w-barra')
        clic_su('barraTaskView')
        aspetta(lambda: valore('windows11.taskbarTaskView') is False)
        controlla(True, 'Visualizzazione attività può essere nascosta')
        chiama('fuoco', 'barraWidgets')
        tasto_reale('Space')
        aspetta(lambda: valore('windows11.taskbarWidgets') is False)
        controlla(True, 'Widget si disattiva dalla tastiera')
        clic_su('barraAllineamento')
        tasto_reale('Home')
        tasto_reale('Return')
        aspetta(lambda: valore('windows11.taskbarAlignment') == 'left')
        controlla(True, 'la tendina salva allineamento a sinistra')
        clic_su('barraCerca')
        tasto_reale('End')
        tasto_reale('Return')
        aspetta(lambda: valore('windows11.taskbarSearch') == 'box')
        controlla(True, 'la tendina Cerca salva la casella di ricerca')
        cattura('windows-barra-configurata')

        chiama('tema', 'scuro')
        aspetta(lambda: stato()['colori']['scura'])
        s = stato()
        controlla(s['colori']['finestra'] == '#202020', 'in Windows scuro il fondo è quello di Windows 11',
                  s['colori'])
        clic_su('navWindows-dispositivi')
        aspetta(lambda: stato().get('categoria') == 'dispositivi')
        cattura('windows-categoria-scuro')
        clic_su('categoriaVoce-input')
        aspetta(lambda: stato().get('sezione') == 'input')
        cattura('windows-sezione-scuro')
        for c in CATEGORIE:
            clic_su('navWindows-' + c)
            s = stato()
            controlla(s['categoriaAttiva'] == c and (s['categoria'] == c or s['sezione'] != ''),
                      'la categoria ' + c + ' si apre col mouse', (s['categoria'], s['sezione']))
        chiama('tema', 'chiaro')

        # ── Tornando a Liquid ───────────────────────────────────────────
        chiama('preset', 'liquid')
        aspetta(lambda: not stato().get('windows'))
        time.sleep(0.8)
        s = stato()
        controlla(s['colori'] == liquid, 'tornando a Liquid i colori sono quelli di prima', (liquid, s['colori']))
        controlla(s['carattere'] == 'Adwaita Sans' and 'colonnaLiquid' in s['controlli'],
                  'e tornano carattere e colonna di Liquid')
        cattura('liquid-dopo')

        errori = [r for r in (Path(tmp) / 'shell.log').read_text().splitlines()
                  if ('ERROR' in r or 'TypeError' in r or 'ReferenceError' in r or 'Binding loop' in r
                      or 'anchor loop' in r) and 'pipewire' not in r.lower()]
        controlla(not errori, 'nessun errore nel registro della shell', errori[:5])
        print(f'RISULTATO {PASSATI} controlli passati')
        riuscita = True
    finally:
        if update_server is not None:
            update_server.shutdown()
            update_server.server_close()
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
                print('\n'.join(registro.read_text(errors='replace').splitlines()[-15:]))
            print(f'Cartella della prova conservata: {tmp}')


if __name__ == '__main__':
    sys.exit(main())
