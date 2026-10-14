#!/usr/bin/env python3
"""Prove con API file, finestre Wayland e input reali, in una sessione privata."""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time

if not os.environ.get('LIQUID_TEST_BUS'):
    os.environ['LIQUID_TEST_BUS'] = '1'
    os.execvp('dbus-run-session', ['dbus-run-session', '--', sys.executable, *sys.argv])

ROOT = Path(__file__).resolve().parents[1]
ART = Path(os.environ.get('MINERVA_TEST_REPORT_DIR', str(ROOT.parent / 'Liquid_test-principale/rapporti/gestore-file-evoluzione')))
ART.mkdir(parents=True, exist_ok=True)
checks = []
children = []
handles = []
completed = False

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
        time.sleep(.08)
    raise AssertionError('attesa scaduta')

def spawn(args, env, name):
    stream = (ART / (name + '.log')).open('w')
    handles.append(stream)
    process = subprocess.Popen(args, env=env, stdout=stream, stderr=stream, start_new_session=True)
    children.append(process)
    return process

def source_hashes():
    paths = list((ROOT / 'minerva-shell/files').rglob('*'))
    paths += list((ROOT / 'minerva-shell/windows11').rglob('*'))
    paths += [ROOT / path for path in (
        'minervad/lib/core/settings_api.dart', 'minervad/lib/core/desktop_profiles.dart',
        'minervad/lib/services/luoghi_remoti.dart', 'minervad/lib/ipc/websocket_server.dart',
        'minerva-shell/core/Ipc.qml', 'minerva-shell/ui/WindowTitleBar.qml',
        'minerva-shell/ui/TitleBarContent.qml', 'minerva-shell/ui/DragSelection.qml',
        'minerva-shell/menu/ContextMenu.qml', 'scripts/install-minerva.sh')]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()}

snapshot = source_hashes()
temp = tempfile.TemporaryDirectory(prefix='liquid-files-test-')
directory = Path(temp.name)
try:
    data = directory / 'data'
    data.mkdir()
    for name in ('A', 'B', 'C', 'D', 'E', 'F'):
        folder = data / name
        folder.mkdir()
        (folder / (name + '.txt')).write_text('contenuto ' + name)
    (data / 'nota.txt').write_text('appunti')
    (data / 'rapporto.pdf').write_bytes(b'%PDF-1.4\nfixture')
    (data / 'codice.py').write_text('print(1)')
    (data / 'tabella.csv').write_text('a,b\n1,2\n')
    (data / '.prova-nascosta').write_text('nascosto')
    (data / 'A/trovami.txt').write_text('ricerca ricorsiva')
    (data / 'foto.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="#4488ee"/></svg>')
    env = dict(os.environ, MINERVA_PROVA='1', WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2',
        WLR_RENDERER='gles2', MINERVA_SCRIVANIA='0', MINERVA_IPC_SOCKET=str(directory / 'daemon.sock'),
        MINERVA_CONFIG_DIR=str(directory / 'config'), XDG_CONFIG_HOME=str(directory / 'config'),
        XDG_STATE_HOME=str(directory / 'state'), XDG_CACHE_HOME=str(directory / 'cache'),
        XDG_RUNTIME_DIR=str(directory), MINERVA_SESSIONE='files-test', XDG_SESSION_ID='files-test',
        QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
        QML_IMPORT_PATH=str(ROOT / 'minerva-shell/native'), TEST_FILES_ROOT=str(data),
        QT_NO_XDG_DESKTOP_PORTAL='1', GTK_USE_PORTAL='0', NO_AT_BRIDGE='1')
    env.pop('MINERVA_CANALE', None)
    comp = spawn([str(ROOT / 'compositore/build-native/minerva-wayland')], env, 'compositore')
    def info():
        log = (ART / 'compositore.log').read_text()
        display = re.search(r'in ascolto su (\S+)', log)
        channel = re.search(r'canale su (\S+)', log)
        return (display[1], channel[1]) if display and channel else None
    display, channel = wait(info)
    env.update(WAYLAND_DISPLAY=str(directory / display), MINERVA_CANALE=channel)
    def command(line):
        with socket.socket(socket.AF_UNIX) as sock:
            sock.settimeout(5)
            sock.connect(channel)
            sock.sendall((line + '\n').encode())
            reply = b''
            while b'\n' not in reply:
                chunk = sock.recv(65536)
                assert chunk
                reply += chunk
        reply = reply.decode().strip()
        assert reply.startswith('ok'), (line, reply)
        return reply[3:]
    command('schermo HEADLESS-1 1920x1080@60 1 0')
    # Il backend headless nasce senza tastiera: la si crea prima delle finestre.
    command('tasto Shift_L premi')
    command('tasto Shift_L lascia')
    daemon = spawn(['dart', 'run', str(ROOT / 'minervad/test/files_fixture.dart'), str(directory)], env, 'demone')
    wait(lambda: (directory / 'daemon.sock').exists())
    token = directory / 'liquid-de/sessioni/files-test/canale'
    token.parent.mkdir(parents=True)
    token.write_text('socket=' + str(directory / 'daemon.sock') + '\nsegreto=files-private-test\n')
    token.chmod(0o600)
    fixture = directory / 'files.qml'
    fixture.write_text((ROOT / 'tests/fixtures/files-session.qml').read_text()
        .replace('@FILES@', (ROOT / 'minerva-shell/files').as_uri())
        .replace('@CORE@', (ROOT / 'minerva-shell/core').as_uri())
        .replace('@THEME@', (ROOT / 'minerva-shell/theme').as_uri()))
    ui = spawn(['qs', '-p', str(fixture)], env, 'file-manager')
    def call(method, *args):
        result = subprocess.run(['qs', 'ipc', '--pid', str(ui.pid), 'call', 'files-test', method,
            *map(str, args)], env=env, text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, result.stdout + result.stderr
        assert not result.stdout.startswith(('Target not found', 'Function not found', 'Too many arguments', 'Too few arguments')), result.stdout
        return result.stdout.strip()
    def status():
        raw = call('status')
        return json.loads(raw)
    def manager():
        return status()['managers'][0]
    def settle():
        time.sleep(.25)
    def key(name, mods=()):
        for modifier in mods:
            command('tasto ' + modifier + ' premi')
        command('tasto ' + name + ' premi')
        command('tasto ' + name + ' lascia')
        for modifier in reversed(mods):
            command('tasto ' + modifier + ' lascia')
        settle()
    def pref(path, value):
        call('preference', path, json.dumps({'value': value}, separators=(',', ':')))
        wait(lambda: status()['settings'].get(path.split('.')[0], {}).get(path.split('.')[1]) == value)
        settle()
    def windows():
        return json.loads(command('finestre'))
    def main_window():
        return next(window for window in windows() if window['titolo'] == 'File prova principale')
    def point(control):
        item = manager()['controls'][control]
        if item.get('global'):
            return item['x'], item['y']
        window = main_window()
        return window['x'] + item['x'], window['y'] + item['y']
    def click(control, button=''):
        x, y = point(control)
        command(f'dito {x} {y}')
        suffix = (' ' + button) if button else ''
        command('dito premi' + suffix)
        command('dito lascia' + suffix)
        settle()
    def screenshot(name):
        subprocess.run(['grim', str(ART / (name + '.png'))], env=env, check=True, timeout=10)
    wait(lambda: ui.poll() is None and 'Configuration Loaded' in (ART / 'file-manager.log').read_text())
    wait(lambda: status()['connected'] and manager()['panes'] and 'nota.txt' in manager()['panes'][0]['entries'])
    command('fuoco ' + main_window()['id'])
    settle()
    # La rinomina deve usare l'elemento scelto all'apertura del dialogo.
    rename_dir = data / 'Win11'
    rename_dir.mkdir()
    (rename_dir / 'contenuto.txt').write_text('da conservare')
    (data / 'selezione-diversa.jpg').write_bytes(b'fotografia da conservare')
    key('F5')
    wait(lambda:'Win11' in manager()['panes'][0]['entries'])
    call('selectFile', str(rename_dir))
    key('F2')
    check('F2 apre rinomina sulla cartella scelta',manager()['controls']['fileNamePrompt']['mode']=='rename')
    call('clipboard', 'Win11 icon theme - By\n  Yeyushengfan258')
    key('v', ('Control_L',))
    # Una selezione aggiornata mentre la richiesta è aperta non deve
    # deviare la rinomina su una fotografia, come nella segnalazione.
    call('selectFile', str(data / 'selezione-diversa.jpg'))
    click('fileNameInput')
    key('Return')
    expected = data / 'Win11 icon theme - By Yeyushengfan258'
    wait(lambda: expected.exists())
    check('nome incollato multilinea rinomina una directory',expected.is_dir())
    check('rinomina conserva il contenuto della cartella', (expected / 'contenuto.txt').read_text()=='da conservare')
    check('rinomina conserva il file selezionato successivamente', (data / 'selezione-diversa.jpg').read_bytes()==b'fotografia da conservare')
    actions=json.loads((directory / 'actions.json').read_text())
    check('rinomina non invia alcuna creazione di file',not any(a['action']=='fs_touch' for a in actions))
    check('conferma rinomina invia un solo comando',sum(a['action']=='fs_rename' for a in actions)==1)
    # Si ripristina il nome nella sola fixture per gli scenari successivi.
    (expected / "contenuto.txt").unlink()
    expected.rmdir()
    (data / "selezione-diversa.jpg").unlink()
    call("selectFile", "")
    key('F5')
    settle()
    if os.environ.get('MINERVA_FILES_RENAME_ONLY')=='1':
        check('sorgenti invariati durante la prova mirata',snapshot==source_hashes())
        completed=True
        sys.exit(0)
    # Comandi Windows reali: API file e tastiera nel compositore privato.
    controls = manager()['controls']
    tabs = controls['fileTabs']
    toolbar = controls['filesToolbar']
    check('Windows dispone schede sopra la barra dei comandi',
        tabs['y'] + tabs['height'] / 2 <= toolbar['y'] - toolbar['height'] / 2 + 1)
    check('Windows non eredita il ciano Liquid nella selezione', manager()['presentation']['accent'].lower() == '#0067c0')
    check('Windows presenta un corpo bianco continuo', manager()['presentation']['paper'].lower() == '#ffffff')
    check('comandi senza selezione mantengono posizione ma restano disabilitati',
        all(not controls['filesCommand-' + name]['enabled'] for name in ('copy', 'cut', 'rename', 'delete')))
    screenshot('windows-comandi-senza-selezione')
    call('selectFile', str(data / 'nota.txt'))
    click('fileCell-nota.txt', 'destro')
    wait(lambda: manager()['contextOpen'])
    check('tasto destro Windows dispone i comandi principali in icone',
        all('contextQuick-' + name in manager()['controls'] for name in ('cut', 'copy', 'rename', 'trash')))
    screenshot('windows-menu-insider')
    call('selectFile', str(data / 'codice.py'))
    click('contextQuick-copy')
    wait(lambda: status()['fileClipboard'] == [str(data / 'nota.txt')])
    check('azione contestuale resta legata alla selezione del clic destro', status()['fileClipboard'] == [str(data / 'nota.txt')])
    click('fileCell-nota.txt', 'destro')
    click('contextMenu-__customize')
    check('Personalizza menu apre il pannello dedicato', 'contextCustomize' in manager()['controls'])
    click('contextCustomize-inline')
    wait(lambda: status()['settings']['windows11']['contextInline'])
    click('contextCustomize-done')
    check('comandi testuali sostituiscono la riga di icone',
        'contextQuick-copy' not in manager()['controls'] and 'contextMenu-copy' in manager()['controls'])
    click('contextMenu-__customize')
    click('contextCustomize-inline')
    wait(lambda: not status()['settings']['windows11']['contextInline'])
    key('Escape')
    check('Escape lascia il pannello e conserva il menu', manager()['contextOpen'] and 'contextCustomize' not in manager()['controls'])
    key('Escape')
    check('Escape successivo chiude il menu senza azioni', not manager()['contextOpen'])
    grid = manager()['controls']['filesGrid']
    x, y = point('filesGrid')
    command(f'dito {x} {y + grid["height"] / 2 - 8}')
    command('dito premi destro')
    command('dito lascia destro')
    settle()
    check('tasto destro sul vuoto non conserva le azioni del file precedente',
        manager()['contextOpen'] and not any(item.get('action') == 'open' for item in manager()['contextItems']))
    key('Escape')
    original_window = main_window()
    second_screen = next(output for output in json.loads(command('schermi')) if output['nome'] == 'HEADLESS-2')
    command(f'sposta {original_window["id"]} {second_screen["x"] + 40} {second_screen["y"] + 40}')
    settle()
    click('fileCell-nota.txt', 'destro')
    wait(lambda: manager()['contextOpen'])
    check('menu contestuale segue il file manager sul secondo monitor', manager()['contextScreen'] == 'HEADLESS-2')
    click('contextQuick-copy')
    check('comandi sul secondo monitor conservano il destinatario', status()['fileClipboard'] == [str(data / 'nota.txt')])
    # Qt può scegliere come schermo iniziale il secondo output annunciato.
    # Le prove di quattro riquadri massimizzati richiedono quello da 1920 px.
    first_screen = next(output for output in json.loads(command('schermi')) if output['nome'] == 'HEADLESS-1')
    command(f'sposta {original_window["id"]} {first_screen["x"] + 100} {first_screen["y"] + 100}')
    command(f'dito {first_screen["x"] + 150} {first_screen["y"] + 150}')
    command('fuoco ' + original_window['id'])
    settle()
    call('selectFile', str(data / 'nota.txt'))
    check('selezione abilita copia taglia rinomina e cestino',
        all(manager()['controls']['filesCommand-' + name]['enabled'] for name in ('copy', 'cut', 'rename', 'delete')))
    click('filesCommand-rename')
    check('rinomina dalla barra usa il dialogo sul file selezionato', manager()['controls']['fileNamePrompt']['mode'] == 'rename')
    check('dialogo aperto impedisce nuove operazioni dalla barra',
        manager()['dialogOpen'] and not manager()['controls']['filesCommand-new']['enabled'])
    key('Escape')
    click('filesCommand-copy')
    call('add', str(data / 'F'))
    wait(lambda: manager()['panes'][-1]['path'] == str(data / 'F'))
    wait(lambda: manager()['controls']['filesCommand-paste']['enabled'])
    click('filesCommand-paste')
    wait(lambda: (data / 'F/nota.txt').exists())
    check('copia e incolla dalla barra conservano contenuto e sorgente',
        (data / 'F/nota.txt').read_text() == 'appunti' and (data / 'nota.txt').read_text() == 'appunti')
    key('z', ('Control_L',))
    wait(lambda: not (data / 'F/nota.txt').exists())
    check('Ctrl Z annulla la copia della barra senza rimuovere la sorgente', (data / 'nota.txt').exists())
    call('close', 1)
    call('select', 0)
    call('selectFile', '')
    click('filesCommand-new')
    check('Nuovo apre cartella e documento', all('filesMenu-' + name in manager()['controls'] for name in ('newFolder', 'newFile')))
    key('Down')
    key('Return')
    check('menu Nuovo si naviga con freccia e Invio', manager()['controls']['fileNamePrompt']['mode'] == 'newFile')
    call('clipboard', 'Creato dalla barra.txt')
    click('fileNameInput')
    key('a', ('Control_L',))
    key('v', ('Control_L',))
    key('Return')
    wait(lambda: (data / 'Creato dalla barra.txt').exists())
    check('Nuovo documento crea davvero il file nella cartella attiva', (data / 'Creato dalla barra.txt').is_file())
    (data / 'Creato dalla barra.txt').unlink()
    key('F5')
    click('filesCommand-sort')
    screenshot('windows-menu-ordina')
    click('filesMenu-sort-size')
    check('Ordina dimensione applica la colonna e il verso', manager()['panes'][0]['sort'] == 'size' and manager()['panes'][0]['descending'])
    click('filesCommand-sort')
    click('filesMenu-ascending')
    check('Ordina crescente si applica senza cambiare colonna', manager()['panes'][0]['sort'] == 'size' and not manager()['panes'][0]['descending'])
    click('filesCommand-sort')
    click('filesMenu-sort-name')
    click('filesCommand-view')
    click('filesMenu-grid')
    check('Visualizza icone cambia la vista reale', manager()['panes'][0]['viewMode'] == 'grid')
    click('filesCommand-view')
    click('filesMenu-list')
    check('Visualizza dettagli ripristina elenco', manager()['panes'][0]['viewMode'] == 'list')
    click('filesCommand-view')
    click('filesMenu-checkboxes')
    check('Visualizza caselle cambia la preferenza condivisa', status()['settings']['files']['caselleSelezione'])
    pref('files.caselleSelezione', False)
    click('filesCommand-view')
    click('filesMenu-hidden')
    check('Visualizza nascosti mostra i file nascosti reali', any(Path(path).name == '.prova-nascosta' for path in manager()['panes'][0]['shown']))
    click('filesCommand-view')
    click('filesMenu-hidden')
    click('filesCommand-more')
    key('Escape')
    check('Escape chiude il menu senza chiudere la finestra', 'filesMenu-refresh' not in manager()['controls'] and ui.poll() is None)
    search = 'filesSearchInput-' + manager()['panes'][0]['id']
    click(search)
    call('clipboard', 'trovami')
    key('v', ('Control_L',))
    key('Return')
    wait(lambda: manager()['panes'][0]['searchDone'])
    check('Invio nel campo Windows cerca anche nelle sottocartelle',
        str(data / 'A/trovami.txt') in manager()['panes'][0]['shown'])
    check('ricerca non apre un documento tramite il launcher',
        not any(action.get('action') == 'open_default' for action in json.loads((directory / 'actions.json').read_text())))
    screenshot('windows-ricerca-sottocartelle')
    call('selectFile', str(data / 'A/trovami.txt'))
    click(search)
    before_clipboard = status()['fileClipboard']
    key('a', ('Control_L',))
    key('c', ('Control_L',))
    check('Ctrl C nella ricerca copia il testo senza copiare i file selezionati',
        status()['clipboardText'] == 'trovami' and status()['fileClipboard'] == before_clipboard)
    check('scrivere nella ricerca lascia disponibili i comandi del mouse',
        manager()['typing'] and all(manager()['controls']['filesCommand-' + name]['enabled']
            for name in ('new', 'copy', 'sort', 'view')))
    click('filesCommand-sort')
    click('filesMenu-sort-size')
    check('Ordina funziona anche partendo dal campo ricerca attivo', manager()['panes'][0]['sort'] == 'size')
    click(search)
    click('filesCommand-copy')
    wait(lambda: status()['fileClipboard'] == [str(data / 'A/trovami.txt')])
    check('Copia dal mouse usa il percorso reale del risultato ricorsivo',
        status()['fileClipboard'] == [str(data / 'A/trovami.txt')])
    click('filesCommand-sort')
    click('filesMenu-sort-name')
    click(search)
    key('Escape')
    key('Escape')
    (data / 'A/trovami.txt').unlink()
    (data / '.prova-nascosta').unlink()
    key('F5')
    pref('windows11.theme', 'dark')
    check('tema scuro Windows aggiorna corpo e titolo leggibile', manager()['presentation']['paper'].lower() == '#191919' and manager()['titleInk'].lower() == '#ffffff')
    screenshot('windows-comandi-scuro')
    pref('windows11.theme', 'light')
    pref('stile.attuale', 'liquid')
    check('Liquid conserva i propri comandi e la disposizione', 'filesWindowsCommands' not in manager()['controls'] and not manager()['presentation']['windows'])
    controls = manager()['controls']
    check('Liquid conserva i quattro pulsanti tondi della barra del titolo',
        all('titleButton-' + name in controls for name in ('minimize', 'maximize', 'fullscreen', 'close'))
        and controls['titleButton-close']['width'] < 46, controls.get('titleButton-close'))
    screenshot('liquid-comandi-conservati')
    pref('stile.attuale', 'windows')
    check('ritorno Windows conserva cartella e scheda', manager()['panes'][0]['path'] == str(data) and manager()['count'] == 1)
    # Pulsanti della barra del titolo come Windows 11: tre rettangoli da 46
    # attaccati all'angolo destro, «chiudi» rosso sotto il puntatore.
    controls = manager()['controls']
    bar = controls['minervaWindowTitleBar']
    buttons = [controls.get('titleButton-' + name) for name in ('minimize', 'maximize', 'close')]
    check('Windows mostra tre pulsanti da 46 alti quanto la barra, senza schermo intero',
        all(b and b['width'] == 46 and abs(b['height'] - bar['height']) < 1 for b in buttons)
        and 'titleButton-fullscreen' not in controls, controls.get('titleButton-close'))
    close = buttons[2]
    check('«chiudi» è attaccato al bordo destro, gli altri subito a sinistra',
        abs((close['x'] + 23) - (bar['x'] + bar['width'] / 2)) <= 1
        and abs(buttons[1]['x'] - (close['x'] - 46)) <= 1
        and abs(buttons[0]['x'] - (close['x'] - 92)) <= 1, (bar, buttons))
    pref('windows.buttonsSide', 'sinistra')
    check('in Windows i pulsanti restano a destra anche col lato sinistro salvato',
        abs(manager()['controls']['titleButton-close']['x'] - close['x']) <= 1)
    pref('windows.buttonsSide', 'destra')
    x, y = point('titleButton-close')
    command(f'dito {x} {y}')
    wait(lambda: manager()['controls']['titleButton-close']['color'].lower() == '#c42b1c')
    check('«chiudi» diventa rosso #C42B1C sotto il puntatore', True)
    screenshot('windows-pulsanti-chiudi-rosso')
    x, y = point('titleButton-minimize')
    command(f'dito {x} {y}')
    wait(lambda: manager()['controls']['titleButton-close']['color'].lower() in ('#00000000', 'transparent'))
    check('lasciato «chiudi», il rosso sparisce', True)
    before = status()['closeRequests']
    click('titleButton-close')
    wait(lambda: status()['closeRequests'] == before + 1)
    check('un clic vero su «chiudi» chiede di chiudere la finestra', True)
    command('fuoco ' + main_window()['id'])
    settle()
    # ── Riquadro dei dettagli e dell'anteprima, come Esplora file ────────
    def anteprime():
        return [a for a in json.loads((directory / 'actions.json').read_text())
                if a.get('action') == 'fs_anteprima']
    def panel():
        return manager()['controls']
    (data / 'punto.png').write_bytes(__import__('base64').b64decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAFElEQVR4nGN06XjHAAZMEIqBgQEAHqYBvpG5uYAAAAAASUVORK5CYII='))
    (data / 'lenta.txt').write_text('RISPOSTA VECCHIA')
    key('F5')
    wait(lambda: 'punto.png' in manager()['panes'][0]['entries'] and 'lenta.txt' in manager()['panes'][0]['entries'])
    width_before = manager()['panes'][0]['width']
    # La selezione di prima si rimette a posto alla fine: le prove dopo
    # riordinano le schede e la ritroverebbero in un'altra.
    selection_before = manager()['panes'][0]['selection']
    lette = len(anteprime())
    call('selectFile', str(data / 'nota.txt'))
    time.sleep(.6)
    check('a riquadro chiuso non si legge niente per l\'anteprima',
        len(anteprime()) == lette and 'filesPannelloLaterale' not in panel())
    click('filesCommand-view')
    click('filesMenu-detailsPane')
    wait(lambda: status()['settings']['files'].get('pannelloLaterale') == 'dettagli')
    wait(lambda: panel().get('filesPannelloNome', {}).get('text') == 'nota.txt')
    c = panel()
    check('Riquadro dettagli: nome, tipo e dimensione del file scelto',
        c['filesPannelloValore-Tipo']['text'] == 'File TXT' and c['filesPannelloValore-Dimensione']['text'] != '', c)
    check('il riquadro stringe l\'elenco invece di coprirlo',
        manager()['panes'][0]['width'] < width_before - 200, (width_before, manager()['panes'][0]['width']))
    screenshot('windows-riquadro-dettagli')
    call('selectFile', str(data / 'punto.png'))
    wait(lambda: panel().get('filesPannelloValore-Dimensioni', {}).get('text') == '3 × 2')
    check('un\'immagine mostra le sue misure, lette dal demone', True)
    call('selectFiles', '|'.join([str(data / 'nota.txt'), str(data / 'codice.py'), str(data / 'A')]))
    wait(lambda: 'filesPannelloRiassunto' in panel())
    check('più elementi: quanti sono e quanto pesano i file',
        panel()['filesPannelloRiassunto']['text'].startswith('3 elementi selezionati')
        and 'cartelle escluse' in panel()['filesPannelloRiassunto']['text'], panel()['filesPannelloRiassunto'])
    call('selectFile', '')
    wait(lambda: 'filesPannelloVuoto' in panel())
    check('senza selezione il riquadro lo dice', 'dettagli' in panel()['filesPannelloVuoto']['text'])
    key('p', ('Alt_L',))
    wait(lambda: status()['settings']['files'].get('pannelloLaterale') == 'anteprima')
    call('selectFile', str(data / 'codice.py'))
    wait(lambda: panel().get('filesPannelloTesto', {}).get('text') == 'print(1)')
    check('Alt+P passa all\'anteprima e mostra le prime righe del testo', True)
    screenshot('windows-riquadro-anteprima')
    call('selectFile', str(data / 'punto.png'))
    wait(lambda: 'filesPannelloImmagine' in panel())
    check('un\'immagine si vede nel riquadro di anteprima', 'filesPannelloTesto' not in panel())
    # Una risposta che arriva dopo un cambio di selezione si butta via: il
    # demone di prova risponde tardi per i file con «lenta» nel nome.
    call('selectFile', str(data / 'lenta.txt'))
    wait(lambda: any(a['path'] == str(data / 'lenta.txt') for a in anteprime()))
    call('selectFile', str(data / 'nota.txt'))
    wait(lambda: panel().get('filesPannelloTesto', {}).get('text') == 'appunti')
    time.sleep(1)
    check('la risposta tardiva di una selezione vecchia non sostituisce quella nuova',
        panel().get('filesPannelloTesto', {}).get('text') == 'appunti', panel().get('filesPannelloTesto'))
    lette = len(anteprime())
    call('selectInTurn', '|'.join(str(data / name) for name in
        ('codice.py', 'tabella.csv', 'nota.txt', 'rapporto.pdf', 'tabella.csv')))
    wait(lambda: panel().get('filesPannelloNome', {}).get('text') == 'tabella.csv')
    time.sleep(.6)
    nuove = anteprime()[lette:]
    check('scorrendo in fretta si legge solo il file dove ci si ferma',
        [a['path'] for a in nuove] == [str(data / 'tabella.csv')], nuove)
    pref('stile.attuale', 'liquid')
    check('il riquadro è una scelta del preset: in Liquid resta chiuso',
        'filesPannelloLaterale' not in panel() and status()['settings']['files'].get('pannelloLaterale') == 'niente')
    pref('stile.attuale', 'windows')
    wait(lambda: 'filesPannelloLaterale' in panel())
    check('tornando a Windows il riquadro di anteprima riapre',
        status()['settings']['files'].get('pannelloLaterale') == 'anteprima')
    key('p', ('Alt_L',))
    wait(lambda: 'filesPannelloLaterale' not in panel())
    check('Alt+P di nuovo chiude il riquadro e l\'elenco torna largo',
        abs(manager()['panes'][0]['width'] - width_before) <= 1, (width_before, manager()['panes'][0]['width']))
    if selection_before:
        call('selectFiles', '|'.join(selection_before))
    else:
        call('selectFile', '')
    (data / 'punto.png').unlink()
    (data / 'lenta.txt').unlink()
    key('F5')
    check('Windows usa una sola vista con schede', manager()['tabbed'] and sum(p['visible'] for p in manager()['panes']) == 1)
    first = manager()['panes'][0]['id']
    full_width = manager()['panes'][0]['width']
    for name in ('A', 'B', 'C', 'D', 'E'):
        call('add', str(data / name))
        wait(lambda: manager()['panes'][-1]['path'] == str(data / name) and manager()['panes'][-1]['entries'])
        settle()
    m = manager()
    check('sei schede conservano sei identificativi distinti', m['count'] == 6 and len({p['id'] for p in m['panes']}) == 6, m)
    check('aprire la quinta e sesta scheda non comprime la vista', sum(p['visible'] for p in m['panes']) == 1 and m['panes'][5]['width'] == full_width, m)
    key('Tab', ('Control_L',))
    check('Ctrl Tab torna alla prima scheda', manager()['current'] == 0, manager())
    key('Tab', ('Control_L', 'Shift_L'))
    check('Ctrl Shift Tab torna all ultima scheda', manager()['current'] == 5, manager())
    active = manager()['panes'][5]['id']
    removed = manager()['panes'][1]['id']
    call('close', 1)
    settle()
    check('chiudere una scheda precedente conserva quella attiva', manager()['panes'][manager()['current']]['id'] == active, manager())
    check('chiusura intermedia non rinomina i riquadri successivi', first == manager()['panes'][0]['id'] and removed not in [p['id'] for p in manager()['panes']], manager())
    call('lateReply', removed, str(data / 'A'))
    settle()
    check('risposta di una scheda chiusa non contamina le altre', all('RISPOSTA-OBSOLETA' not in p['entries'] for p in manager()['panes']), manager())
    call('lateReply', active, str(data / 'A'))
    settle()
    check('risposta del percorso precedente non sostituisce la cartella attuale', all('RISPOSTA-OBSOLETA' not in p['entries'] for p in manager()['panes']), manager())
    call('move', manager()['current'], 0)
    settle()
    check('riordino conserva identita percorso e focus', manager()['current'] == 0 and manager()['panes'][0]['id'] == active and manager()['panes'][0]['path'] == str(data / 'E'), manager())
    pref('files.disposizione', 'affiancata')
    check('finestra normale affianca due cartelle leggibili', sum(p['visible'] for p in manager()['panes']) == 2 and all(p['width'] >= 320 for p in manager()['panes'] if p['visible']), manager())
    command('ingrandisci ' + main_window()['id'] + ' si')
    settle()
    check('affiancamento mostra al massimo quattro schede', sum(p['visible'] for p in manager()['panes']) == 4, manager())
    breadcrumbs = [control for name, control in manager()['controls'].items() if name.startswith('pathBreadcrumb-')]
    check('percorsi lunghi restano dentro le quattro barre affiancate', len(breadcrumbs) == 4 and all(control['contentWidth'] <= control['width'] + 1 for control in breadcrumbs), breadcrumbs)
    call('select', 4)
    settle()
    check('quinta scheda affiancata passa al gruppo successivo', sum(p['visible'] for p in manager()['panes']) == 1 and manager()['panes'][4]['visible'], manager())
    command('ingrandisci ' + main_window()['id'] + ' no')
    settle()
    pref('files.disposizione', 'schede')
    call('select', 1)
    settle()
    click('fileCell-F', 'centrale')
    check('clic centrale su cartella apre una nuova scheda', manager()['count'] == 6 and manager()['panes'][-1]['path'] == str(data / 'F'), manager())
    call('select', 1)
    settle()
    pref('files.caselleSelezione', True)
    click('fileCheck-nota.txt')
    click('fileCheck-codice.py')
    check('caselle selezionano piu file senza Ctrl', set(manager()['panes'][1]['selection']) == {str(data / 'nota.txt'), str(data / 'codice.py')}, manager())
    key('a', ('Control_L',))
    check('Ctrl A usa lo stesso modello delle caselle', len(manager()['panes'][1]['selection']) == 11, manager())
    screenshot('windows-schede-caselle')
    click('fileCheck-nota.txt')
    check('casella deseleziona solo il proprio file', str(data / 'nota.txt') not in manager()['panes'][1]['selection'] and len(manager()['panes'][1]['selection']) == 10, manager())
    call('another', str(data / 'C'))
    wait(lambda: len(status()['managers']) == 2 and status()['managers'][1]['panes'][0]['entries'])
    check('finestre separate mantengono riquadri e percorsi indipendenti', status()['managers'][1]['panes'][0]['id'] not in [p['id'] for p in manager()['panes']] and status()['managers'][1]['panes'][0]['path'] == str(data / 'C'), status())
    (data / '.nascosto-globale').write_text('in tutte le schede')
    (data / 'C/.nascosto-globale').write_text('nella seconda finestra')
    pref('files.showHidden', True)
    wait(lambda: '.nascosto-globale' in status()['managers'][1]['panes'][0]['entries']
        and any(Path(path).name == '.nascosto-globale' for path in manager()['panes'][1]['shown']))
    check('cambio nascosti rilegge tutte le schede e finestre',
        all(pane['hidden'] for m in status()['managers'] for pane in m['panes']))
    command('fuoco ' + main_window()['id'])
    key('h', ('Control_L',))
    wait(lambda: not status()['settings']['files']['showHidden'])
    wait(lambda: '.nascosto-globale' not in status()['managers'][1]['panes'][0]['entries'])
    check('Ctrl H conserva il binding condiviso tra tutte le finestre',
        all(not pane['hidden'] for m in status()['managers'] for pane in m['panes']))
    (data / '.nascosto-globale').unlink()
    (data / 'C/.nascosto-globale').unlink()
    pref('stile.attuale', 'liquid')
    check('Liquid recupera affiancamento e caselle proprie', not manager()['tabbed'] and not status()['settings']['files']['caselleSelezione'], manager())
    pref('stile.attuale', 'windows')
    check('Windows recupera schede e caselle senza perdere cartelle', manager()['tabbed'] and status()['settings']['files']['caselleSelezione'] and manager()['count'] == 6, manager())
    # Lo spostamento delle schede si prova anche col mouse, sulla finestra davanti.
    command('fuoco ' + main_window()['id'])
    call('select', 0)
    settle()
    start_x, start_y = point('fileTab-' + manager()['panes'][0]['id'])
    end_x, end_y = point('fileTab-' + manager()['panes'][2]['id'])
    moved_id = manager()['panes'][0]['id']
    command(f'dito {start_x} {start_y}')
    command('dito premi')
    for step in range(1, 9):
        command(f'dito {start_x + (end_x-start_x)*step/8} {end_y}')
        time.sleep(.03)
    command('dito lascia')
    settle()
    check('trascinamento reale riordina la scheda senza ricrearla', manager()['panes'][2]['id'] == moved_id, manager())
    call('select', 0)
    settle()
    click('fileCell-nota.txt')
    key('c', ('Control_L',))
    call('select', 5)
    settle()
    key('v', ('Control_L',))
    copied = data / 'F/nota.txt'
    wait(copied.exists)
    check('copia da scheda nascosta usa la selezione giusta', copied.read_text() == 'appunti' and (data / 'nota.txt').read_text() == 'appunti')
    key('z', ('Control_L',))
    wait(lambda: not copied.exists())
    check('annullare copia conserva la sorgente e usa il cestino', (data / 'nota.txt').read_text() == 'appunti' and list((directory / 'cestino/files').glob('nota*')))
    count_before = manager()['count']
    key('t', ('Control_L',))
    check('Ctrl T crea una scheda con il percorso corrente', manager()['count'] == count_before + 1 and manager()['panes'][-1]['path'] == str(data / 'F'), manager())
    key('w', ('Control_L',))
    check('Ctrl W chiude solo la scheda attiva', manager()['count'] == count_before and len(windows()) == 2, manager())
    tab_id = manager()['panes'][0]['id']
    call('select', 0)
    settle()
    click('fileTab-' + tab_id, 'centrale')
    check('clic centrale chiude solo la scheda indicata', manager()['count'] == count_before - 1 and tab_id not in [pane['id'] for pane in manager()['panes']], manager())
    pref('files.disposizione', 'affiancata')
    command('tiling colonne')
    settle()
    check('due finestre restano affiancate nel tiling', len(windows()) == 2 and all(w['tiling'] for w in windows()), windows())
    check('tiling riduce i riquadri senza stringere gli elenchi', all(p['width'] >= 320 for p in manager()['panes'] if p['visible']), manager())
    screenshot('liquid-affiancamento-tiling')
    # Telefoni simulati: la prova verifica UI e instradamento, senza dispositivi host.
    call('phoneState', json.dumps({'mancano': ['gvfs-mtp', 'gvfs-gphoto2'], 'luoghi': []}))
    settle()
    controls = manager()['controls']
    check('senza telefono nessuna voce USB fissa o guida separata', 'collegaTelefono' not in controls and 'telefonoUsb' not in controls and not any(name.startswith('luogoRemoto-') for name in controls), controls)
    check('senza telefono il titolo mostra solo la rete', controls['titoloLuoghiRemoti']['text'] == 'RETE', controls)
    screenshot('nessun-telefono-rilevato')
    call('language', 'en')
    settle()
    check('rete senza telefono tradotta in inglese', manager()['controls']['titoloLuoghiRemoti']['text'] == 'NETWORK')
    call('phoneState', json.dumps({'luoghi': [
        {'nome': 'Telefono prova A', 'uri': 'mtp://test-a/', 'tipo': 'telefono', 'montato': True, 'percorso': str(data / 'C')},
        {'nome': 'Telefono prova B', 'uri': 'gphoto2://test-b/', 'tipo': 'telefono', 'montato': False}
    ], 'mancano': []}))
    settle()
    check('due telefoni rilevati compaiono direttamente nella barra laterale', all('luogoRemoto-' + str(index) in manager()['controls'] for index in (0, 1)) and 'telefonoUsb' not in manager()['controls'])
    screenshot('telefoni-dispositivi-disponibili')
    click('luogoRemoto-0')
    wait(lambda: manager()['panes'][manager()['current']]['path'] == str(data / 'C'))
    check('clic sul telefono apre il percorso del volume senza dialoghi', 'telefonoUsb' not in manager()['controls'])
    call('phoneState', json.dumps({'luoghi': [
        {'nome': 'Server prova', 'uri': 'sftp://test-server/', 'tipo': 'server', 'montato': False}
    ], 'mancano': []}))
    settle()
    check('rimuovere i telefoni conserva la voce del server', 'luogoRemoto-0' in manager()['controls'] and 'luogoRemoto-1' not in manager()['controls'] and manager()['controls']['titoloLuoghiRemoti']['text'] == 'NETWORK', manager())
    call('phoneState', json.dumps({'luoghi': [], 'mancano': []}))
    settle()
    check('dopo scollegamento spariscono tutte le voci dei telefoni', not any(name.startswith('luogoRemoto-') for name in manager()['controls']))
    call('language', 'it')
    call('select', 0)
    call('connectRemote', 'mtp://test-a/')
    token_a = next(iter(manager()['pending']))
    pane_a = manager()['panes'][0]['id']
    call('select', 1)
    call('connectRemote', 'mtp://test-b/')
    token_b = next(token for token in manager()['pending'] if token != token_a)
    pane_b = manager()['panes'][1]['id']
    call('select', 2)
    call('connectReply', token_b, str(data / 'D'))
    call('connectReply', token_a, str(data / 'A'))
    settle()
    check('risposte inverse aprono ogni telefono nella propria scheda', manager()['current'] == 2 and next(p for p in manager()['panes'] if p['id'] == pane_a)['path'] == str(data / 'A') and next(p for p in manager()['panes'] if p['id'] == pane_b)['path'] == str(data / 'D'), manager())
    call('select', 0)
    call('connectRemote', 'mtp://vecchio/')
    token_old = next(iter(manager()['pending']))
    call('connectRemote', 'mtp://nuovo/')
    token_new = next(iter(manager()['pending']))
    call('connectReply', token_old, str(data / 'F'))
    settle()
    check('richiesta remota sostituita non modifica il percorso', manager()['panes'][0]['path'] == str(data / 'A') and token_new in manager()['pending'])
    call('connectReply', token_new, str(data / 'B'))
    settle()
    call('select', 4)
    call('connectRemote', 'mtp://chiuso/')
    token_closed = next(iter(manager()['pending']))
    call('close', 4)
    call('connectReply', token_closed, str(data / 'F'))
    settle()
    check('chiudere la scheda cancella la sua apertura USB pendente', not manager()['pending'] and manager()['count'] == 4, manager())
    tokens = [action['richiesta'] for action in anteprime()]
    check('anteprime riaperte usano token distinti fra istanze',
        bool(tokens) and all(isinstance(token, str) for token in tokens) and len(tokens) == len(set(tokens)))
    for name in ('file-manager', 'demone'):
        errors = re.findall(r'(?:TypeError|ReferenceError|Cannot assign|Binding loop|Possible anchor loop|Error:)[^\n]*', (ART / (name + '.log')).read_text())
        check(name + ' senza errori runtime', not errors, errors)
    check('sorgenti invariati durante la prova', snapshot == source_hashes())
    completed = True
finally:
    if (directory / 'actions.json').exists():
        (ART / 'azioni.json').write_bytes((directory / 'actions.json').read_bytes())
    for process in reversed(children):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
    for process in reversed(children):
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
    for stream in handles:
        stream.close()
    (ART / 'verifica.json').write_text(json.dumps({'completed': completed, 'checks': checks, 'verified_sources': snapshot}, indent=2))
    temp.cleanup()
