import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
import { body } from './qml-body.mjs';
import { wifiFixture } from './wifi-harness.mjs';

// Execute the bodies from the production QML, rather than a second parser.
// This validates JS and generated shell commands, not QML loading or Qt signals.
const root = process.env.SHELL_SOURCE_ROOT || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = name => fs.readFileSync(path.join(root, name), 'utf8');
function optional(text, marker) { try { return body(text, marker); } catch { return null; } }
const network = source('minerva-shell/settings/sections/Network.qml');
const notifSource = source('minerva-shell/core/Notifications.qml');
const gameSource = source('minerva-shell/core/Gioco.qml');
const userSource = source('minerva-shell/settings/sections/Utente.qml');

function scan(wifi, wired = '') {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-nmcli-'));
    try {
        fs.writeFileSync(path.join(dir, 'nmcli'), '#!/bin/sh\ncase "$*" in\n "radio wifi") printf "enabled\\n";;\n *"device status"*) printf "%s\\n" "$TEST_WIRED";;\n *"device wifi list"*) printf "%s\\n" "$TEST_WIFI";;\n *) exit 7;;\nesac\n', { mode: 0o755 });
        let command;
        const page = { networks: [], wired: 'old', scanning: true };
        const parser = optional(network, 'function campiNmcli(');
        if (parser) page.campiNmcli = new Function('riga', parser);
        new Function('soloLettura', 'page', 'query', body(network, 'function refresh('))(true, page, { sh: s => command = s });
        const r = spawnSync('sh', ['-c', command], { encoding: 'utf8', env: { ...process.env, PATH: dir + ':' + process.env.PATH, TEST_WIFI: wifi, TEST_WIRED: wired } });
        assert.equal(r.status, 0, r.stderr);
        new Function('out', 'page', body(network, 'onDone: function(out)'))(r.stdout, page);
        return page;
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
for (const ssid of ['constructor', '__proto__', 'toString']) {
    test(`Wi-Fi SSID ${ssid} cannot break refresh`, () => {
        assert.equal(scan(`${ssid}:90:WPA2:*`).networks[0].ssid, ssid);
    });
}
test('Wi-Fi decodes colons/backslashes/tabs without moving signal or active state', () => {
    const p = scan('Garage\\:AP:82:WPA2:*\nFolder\\\\AP:40:--:\nTab\tAP:35:WPA2:', 'ethernet:connected:Office\\:LAN\nwifi:connected:Garage\\:AP');
    assert.deepEqual(p.networks.map(n => [n.ssid, n.signal, n.active]), [['Garage:AP', 82, true], ['Folder\\AP', 40, false], ['Tab\tAP', 35, false]]);
    assert.equal(p.wired, 'Office:LAN');
});
test('Wi-Fi merges the active AP and strongest signal, and clears disconnected wired state', () => {
    const p = scan('Home:97:WPA2:\nHome:65:WPA2:*');
    assert.equal(p.networks.length, 1);
    assert.equal(p.networks[0].signal, 97);
    assert.equal(p.networks[0].active, true);
    assert.equal(p.wired, '');
});

function notifications() {
    const n = { items: [], capacity: 60, inSilenzio: true, bloccoMostra: 'tutto', fileDi: () => '', _diPosta: () => false };
    for (const name of ['_contaNonLette', '_chiudi', '_aggiungi', 'markAllRead', 'clear', '_perIlBlocco']) {
        const b = optional(notifSource, `function ${name}(`);
        if (b) n[name] = new Function('notifications', 'item', b).bind(null, n);
    }
    const counter = optional(notifSource, 'function _contaNonLette(');
    if (counter) Object.defineProperty(n, 'unread', { get: () => n._contaNonLette() });
    else n.unread = 0;
    n.remove = i => new Function('index', 'notifications', body(notifSource, 'function remove('))(i, n);
    n.receive = x => new Function('notif', 'notifications', body(notifSource, 'onNotification: function(notif)'))(x, n);
    return n;
}
function fixture(id, live, appName = 'Mail') {
    const n = { id, appName, summary: `Message ${id}`, body: 'demo', actions: [], expireTimeout: 5000,
        dismiss() { this.tracked = false; live.delete(this.id); } };
    live.set(id, n);
    return n;
}
test('1,000 notifications retain at most 60 live objects and clear closes all of them', () => {
    const n = notifications(), live = new Map();
    for (let i = 0; i < 1000; i++) n.receive(fixture(i, live));
    assert.equal(n.items.length, 60);
    assert.equal(n.unread, 60);
    assert.equal(live.size, 60);
    n.clear();
    assert.equal(live.size, 0);
    assert.equal(n.unread, 0);
});
test('Removing the newest unread message cannot export an older read message to the lock', () => {
    const n = notifications(), live = new Map();
    n.receive(fixture(1, live)); n.markAllRead(); n.receive(fixture(2, live)); n.remove(1);
    assert.equal(n.unread, 0);
    assert.deepEqual(n._perIlBlocco().voci, []);
    assert.equal(live.size, 1);
});
test('Lock notification grouping accepts inherited object names and counts by app', () => {
    const n = notifications(), live = new Map();
    for (let i = 0; i < 2; i++) n.receive(fixture(i, live, 'constructor'));
    n.receive(fixture(2, live, '__proto__'));
    assert.deepEqual(n._perIlBlocco().gruppi.map(g => [g.app, g.quante]), [['__proto__', 1], ['constructor', 2]]);
});
test('Invalid removal leaves notifications and read state untouched', () => {
    const n = notifications(), live = new Map(); n.receive(fixture(1, live));
    n.remove(-1); n.remove(9);
    assert.equal(n.items.length, 1); assert.equal(n.unread, 1); assert.equal(live.size, 1);
});
test('Lock privacy modes do not export message bodies outside tutto', () => {
    const n = notifications(), live = new Map(); n.receive(fixture(1, live));
    n.bloccoMostra = 'numero'; assert.deepEqual(n._perIlBlocco().voci, []);
    n.bloccoMostra = 'niente'; assert.deepEqual(n._perIlBlocco().gruppi, []);
});

function profile(code, output, enabled) {
    const calls = [], g = { prestazioni: enabled, _leggendoProfilo: true, _profiloPrima: '', _scrivi: { start: a => calls.push(a), fireSh: a => calls.push(a) } };
    const completed = optional(gameSource, 'onCompleted: function (code, out, error)');
    if (completed) new Function('code', 'out', 'error', 'gioco', completed)(code, output, '', g);
    else new Function('out', 'gioco', body(gameSource, 'onDone: function (out)'))(output, g);
    return { calls, g };
}
test('Late profile read after the game ends cannot activate performance', () => {
    assert.deepEqual(profile(0, 'power-saver', false).calls, []);
});
test('Failed or malformed profile read cannot change power policy', () => {
    assert.deepEqual(profile(1, '', true).calls, []);
    assert.deepEqual(profile(0, 'unexpected-output', true).calls, []);
});
test('Valid profile read applies performance and restores the original profile through the queue', () => {
    const { calls, g } = profile(0, 'power-saver', true);
    new Function('gioco', body(gameSource, 'function rimettiProfilo('))(g);
    assert.deepEqual(calls, [['powerprofilesctl', 'set', 'performance'], ['powerprofilesctl', 'set', 'power-saver']]);
    assert.equal(g._profiloPrima, '');
});

function change(secret) {
    const page = { passwordPronta: true, io: { nome: 'demo' }, passoPassword: 'aperta', comandoUtente: '/usr/local/bin/liquid-de-utente', it: true, racconta() {} };
    const cambio = { running: false }, nuova = { text: secret };
    new Function('page', 'cambio', 'nuova', body(userSource, 'function cambiaPassword('))(page, cambio, nuova);
    return { page, cambio };
}
test('Password change never embeds a secret in argv or environment', () => {
    const secret = 'DEMO-password-42!';
    const { cambio } = change(secret);
    assert.deepEqual(cambio.command, ['pkexec', '/usr/local/bin/liquid-de-utente', 'password', 'demo']);
    assert.ok(!JSON.stringify(cambio.command).includes(secret));
});
test('Password is sent once on stdin, then the pending copy and write channel are closed', () => {
    const { page, cambio } = change('DEMO-password-42!'); const sent = [];
    cambio.write = s => sent.push(s);
    new Function('page', 'cambio', body(userSource, 'onStarted:'))(page, cambio);
    assert.deepEqual(sent, ['DEMO-password-42!\n']);
    assert.equal(page._passwordDaInviare, ''); assert.equal(cambio.stdinEnabled, false);
});
test('Password change rejects line delimiters and NUL', () => {
    for (const bad of ['pass\nword', 'pass\rword', 'pass\0word']) assert.equal(change(bad).cambio.command, undefined);
});
test('A helper that fails to start clears the pending password and reports failure', () => {
    const { page, cambio } = change('DEMO-password-42!'); const errors = [];
    page.racconta = (...args) => errors.push(args);
    new Function('running', 'page', 'cambio', body(userSource, 'onRunningChanged:'))(false, page, cambio);
    assert.equal(page._passwordDaInviare, ''); assert.equal(cambio.stdinEnabled, false);
    assert.equal(errors.length, 1); assert.equal(errors[0][1], true);
});
test('A failed password helper cannot be mistaken for success because output contains fatto', () => {
    let closed = 0; const results = [];
    const page = { it: true, chiudiPassword: () => closed++, racconta: (...a) => results.push(a) };
    const done = new Function('code', 'out', 'err', 'page', body(userSource, 'function completaCambioPassword('));
    done(1, 'non fatto', 'Policy denied', page); assert.equal(closed, 0); assert.equal(results[0][1], true);
    done(0, 'fatto\n', '', page); assert.equal(closed, 1);
});
test('A real child receives a fake password through stdin while its /proc argv contains no secret', { timeout: 5000 }, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-password-'));
    let child;
    try {
        const secret = 'DEMO-password-42!', { page, cambio } = change(secret);
        const helper = path.join(dir, 'pkexec');
        const record = path.join(dir, 'argv');
        // /proc/self also works when the parent and /proc use different PID namespaces.
        fs.writeFileSync(helper, '#!/usr/bin/env python3\nimport os, sys\nwith open(os.environ["TEST_ARGV_RECORD"], "wb") as f:\n    f.write(open("/proc/self/cmdline", "rb").read())\nsys.stdout.write(sys.stdin.readline().rstrip("\\n"))\n', { mode: 0o755 });
        child = spawn(helper, cambio.command.slice(1), { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, TEST_ARGV_RECORD: record } });
        const finished = new Promise(resolve => child.on('close', resolve));
        await once(child, 'spawn');
        let out = ''; child.stdout.on('data', x => out += x);
        cambio.write = s => child.stdin.write(s);
        new Function('page', 'cambio', body(userSource, 'onStarted:'))(page, cambio);
        child.stdin.end(); assert.equal(await finished, 0); assert.equal(out, secret);
        const argv = fs.readFileSync(record, 'utf8');
        assert.ok(argv.includes('password\0demo'));
        assert.ok(!argv.includes(secret));
    } finally { child?.kill(); fs.rmSync(dir, { recursive: true, force: true }); }
});
test('Privileged account/login helpers never fall back to mutable scripts in the project directory', () => {
    for (const file of ['Utente', 'Accesso']) {
        const text = source(`minerva-shell/settings/sections/${file}.qml`);
        const query = text.slice(text.indexOf('id: doveSta'), text.indexOf('onDone:', text.indexOf('id: doveSta')));
        assert.ok(!query.includes('Quickshell.shellDir'), `${file}: mutable privileged fallback`);
    }
});
test('External notification text is explicitly PlainText in popup, history and lock', () => {
    for (const [file, expr] of [
        ['spine/Toasts.qml', /text: toast\.(?:appName|summary|body)/g],
        ['spine/panels/NotificationsPanel.qml', /text: note\.modelData\.(?:appName|summary|body)/g],
        ['blocco/Notifiche.qml', /text: (?:scheda\.modelData\.app|pannello\.completo \? scheda\.modelData\.(?:titolo|testo)|pannello\.completo \? "" : pannello\._quante)/g],
    ]) {
        const text = source('minerva-shell/' + file); const matches = [...text.matchAll(expr)];
        assert.ok(matches.length >= 3);
        for (const m of matches) assert.match(text.slice(Math.max(0, m.index - 100), m.index), /textFormat: Text\.PlainText\s+$/);
    }
});
test('Night light schedule refreshes immediately and handles midnight boundaries', () => {
    const text = source('minerva-shell/core/LuceNotturna.qml');
    assert.match(text, /onOraInizioChanged: luce\.aggiornaOrario\(\)/);
    assert.match(text, /onOraFineChanged: luce\.aggiornaOrario\(\)/);
    const update = new Function('luce', 'Date', body(text, 'function aggiornaOrario('));
    for (const [hour, from, to, expected] of [[22,21,7,true],[6,21,7,true],[7,21,7,false],[12,9,17,true],[12,12,12,false]]) {
        const luce = { oraInizio: from, oraFine: to };
        update(luce, class { getHours() { return hour; } }); assert.equal(luce.dentroLOrario, expected);
    }
});

const ipcSource = source('minerva-shell/core/Ipc.qml');
const consentSource = source('minerva-shell/ui/LauncherConsent.qml');
function launcherIpc(connected = true) {
    const sent = [], shown = [], ipc = { connected, _vivo: connected ? {} : null, _launcherSerial: 0,
        _launcherCurrent: '', _coda: [], _launcherWindow: null,
        _launcherWait: { restart() {}, stop() {} }, _scrivi: s => sent.push(JSON.parse(s)),
        _showLauncher: d => { shown.push(d); return true; } };
    for (const name of ['launchDesktop', '_launcherSendNow', '_cancelLauncher', '_launcherPrepared', '_launcherResult'])
        ipc[name] = new Function('path', 'payload', 'data', 'ipc', body(ipcSource, `function ${name}(`));
    const invoke = (name, arg) => ipc[name](arg, arg, arg, ipc);
    for (const name of ['_launcherSendNow', '_cancelLauncher']) {
        const fn = ipc[name]; ipc[name] = arg => fn(arg, arg, arg, ipc);
    }
    return { ipc, sent, shown, invoke };
}
test('Opening a desktop launcher prepares consent without sending any launch command', () => {
    const { sent, shown, invoke } = launcherIpc();
    assert.equal(invoke('launchDesktop', '/tmp/demo.desktop'), true);
    assert.equal(sent.length, 1); assert.equal(sent[0].action, 'prepare_desktop');
    assert.equal(shown.length, 1);
});
test('Offline launcher requests are rejected and never enter the offline queue', () => {
    const { ipc, sent, shown, invoke } = launcherIpc(false);
    assert.equal(invoke('launchDesktop', '/tmp/demo.desktop'), false);
    assert.deepEqual(sent, []); assert.deepEqual(ipc._coda, []);
    assert.ok(shown.at(-1).error); assert.equal(ipc._launcherCurrent, '');
});
test('Late launcher previews cannot reopen a canceled dialog and their tokens are revoked', () => {
    const { sent, shown, invoke } = launcherIpc();
    invoke('_launcherPrepared', { request: 'old', path: '/tmp/demo.desktop', token: 'old-token' });
    assert.equal(shown.length, 0); assert.equal(sent[0].action, 'cancel_desktop');
});
test('The current preview is displayed, without approving it', () => {
    const { ipc, sent, shown, invoke } = launcherIpc(); ipc._launcherCurrent = 'current';
    const d = { request: 'current', token: 'token', path: '/tmp/demo.desktop', command: 'echo demo' };
    invoke('_launcherPrepared', d);
    assert.deepEqual(shown, [d]); assert.deepEqual(sent, []);
});
test('Only a matching launcher result can report failure to the active request', () => {
    const { ipc, shown, invoke } = launcherIpc(); ipc._launcherCurrent = 'current';
    invoke('_launcherResult', { request: 'old', error: 'stale' }); assert.equal(shown.length, 0);
    invoke('_launcherResult', { request: 'current', error: 'changed' });
    assert.equal(shown[0].error, 'changed'); assert.equal(ipc._launcherCurrent, '');
});
test('Expired, waiting and errored prompts cannot approve a launch', () => {
    const approve = new Function('prompt', 'scadenza', 'Date', body(consentSource, 'function consenti('));
    for (const [allowed, expires] of [[false, 5000], [true, 999]]) {
        let starts = 0; const p = { autorizzabile: allowed, italiano: true, proposta: { expires }, accepted: () => starts++ };
        approve(p, { stop() {} }, { now: () => 1000 }); assert.equal(starts, 0);
    }
});
test('An approved prompt emits exactly its token, path and request, and clears the pending proposal', () => {
    const started = [], p = { autorizzabile: true, proposta: { expires: 5000, token: 't', path: '/tmp/demo.desktop', request: 'r' },
                             accepted: (...args) => started.push(args) };
    new Function('prompt', 'scadenza', 'Date', body(consentSource, 'function consenti('))(p, { stop() {} }, { now: () => 1000 });
    assert.deepEqual(started, [['t', '/tmp/demo.desktop', 'r']]); assert.deepEqual(p.proposta, {}); assert.equal(p.visible, false);
});
test('Launcher text cannot conceal controls or interpret markup', () => {
    const display = new Function('value', body(consentSource, 'function visibile('));
    assert.equal(display('abc\u202E\n'), 'abc\\u202e\\u000a');
    assert.match(consentSource, /textFormat: TextEdit\.PlainText/);
    const colors = source('minerva-shell/theme/Colors.qml');
    for (const name of new Set([...consentSource.matchAll(/Theme\.Colors\.(\w+)/g)].map(m => m[1])))
        assert.match(colors, new RegExp(`property color ${name}\\b`));
});

// Wi-Fi credentials bypass Core.Exec and its diagnostic/command queue.
test('Wi-Fi secret is absent from argv and waits for a recognized prompt', () => {
    const { page, connector } = wifiFixture();
    const secret = '  quote"$`\\end  ';
    assert.equal(page.connect('AP: $(touch /tmp/never)', secret, true), true);
    assert.equal(connector.command.at(-1), 'AP: $(touch /tmp/never)');
    assert.ok(connector.command.includes('--ask'));
    assert.ok(!connector.command.includes('password'));
    assert.ok(!JSON.stringify(connector.command).includes(secret));
    assert.equal(connector.writes.length, 0);
    page.wifiOutput('Username (802-1x.identity): ');
    assert.equal(connector.writes.length, 0);
    page.wifiOutput('\nPass'); page.wifiOutput('word: ');
    assert.deepEqual(connector.writes, ['\u0015' + secret + '\n']);
    assert.equal(page._wifiSecret, ''); assert.equal(connector.stdinEnabled, false);
    page.wifiOutput('\nPassword: ');
    assert.equal(connector.writes.length, 1);
});
test('Wi-Fi recognizes current SecretAgent PSK and WEP prompts across chunks', () => {
    for (const key of ['psk', 'wep-key0', 'wep-key3']) {
        const { page, connector } = wifiFixture();
        page.connect('Home', 'testpassword', true);
        for (const c of `Network needs a credential\nPassword (802-11-wireless-security.${key}): `)
            page.wifiOutput(c);
        assert.deepEqual(connector.writes, ['\u0015testpassword\n']);
    }
});
test('Wi-Fi without a password uses no interactive pipe or ask option', () => {
    const { page, connector } = wifiFixture();
    page.connect('Known', '', true);
    assert.equal(page._provaSenzaPassword, true);
    assert.equal(connector.stdinEnabled, false);
    assert.ok(!connector.command.includes('--ask'));
    page.wifiOutput('Password: ');
    assert.equal(connector.writes.length, 0);
});
test('Wi-Fi control keys and overlong secrets cannot become Readline commands', () => {
    for (const secret of ['a\nb', 'a\rb', 'a\0b', 'a\tb', 'a\x1bb', 'a\x7fb', 'a'.repeat(1025)]) {
        const { page, connector } = wifiFixture();
        assert.equal(page.connect('AP', secret, true), false);
        assert.deepEqual(connector.command, []); assert.equal(page._wifiSecret, '');
    }
});
test('Wi-Fi rejects overlapping attempts instead of mismatching queued SSIDs', () => {
    const { page, connector } = wifiFixture();
    page.connect('First', 'firstsecret', true);
    assert.equal(page.connect('Second', 'secondsecret', true), false);
    assert.equal(page.collegando, 'First'); assert.equal(page._wifiSecret, 'firstsecret');
    assert.equal(connector.command.at(-1), 'First');
});
test('Wi-Fi cancellation clears pending credentials, closes input and kills only its client', () => {
    const f = wifiFixture();
    f.page.connect('Home', 'secret', true);
    f.passwordInput.text = 'anothersecret'; f.connectDialog.visible = true;
    f.page.stopWifi();
    assert.equal(f.page._wifiSecret, ''); assert.equal(f.page._wifiPrompt, '');
    assert.equal(f.connector.stdinEnabled, false); assert.deepEqual(f.connector.signals, [9]);
    assert.equal(f.page.collegando, ''); assert.equal(f.passwordInput.text, '');
    assert.equal(f.connectDialog.visible, false);
    f.page.wifiOutput('Password: '); assert.equal(f.connector.writes.length, 0);
});
test('Wi-Fi delayed completion cannot finish a newer attempt after cancellation', () => {
    const { page, connector } = wifiFixture();
    page.connect('First', 'firstsecret', true); const oldEpoch = connector.epoch;
    page.stopWifi(); connector.running = false;
    page.connect('Second', 'secondsecret', true);
    page.completeWifi(0, oldEpoch);
    assert.equal(page.collegando, 'Second'); assert.equal(page._wifiSecret, 'secondsecret');
});
test('Wi-Fi failure categories never echo raw nmcli diagnostics in the interface', () => {
    const { page, connector } = wifiFixture();
    page.connect('First', 'fictitioussecret', true);
    page.wifiError('Error: password rejected: fictitioussecret <b>SSID</b>');
    page.completeWifi(4, connector.epoch);
    assert.equal(page._wifiFailure, ''); assert.equal(page._wifiSecret, '');
    assert.equal(page.error, 'The password was not accepted.');
});
test('Wi-Fi missing saved secret opens a cleared dialog for the attempted SSID', () => {
    const { page, connector, connectDialog, passwordInput } = wifiFixture();
    passwordInput.text = 'oldsecret';
    page.connect('Home', '', true);
    page.wifiError('Secrets were required, but not provided');
    page.completeWifi(4, connector.epoch);
    assert.equal(connectDialog.visible, true); assert.equal(connectDialog.ssid, 'Home');
    assert.equal(passwordInput.text, '');
});
test('Wi-Fi submit clears the visible password before starting; repeated submit is ignored', () => {
    const f = wifiFixture();
    f.connectDialog.open('Home'); f.passwordInput.text = 'testsecret';
    f.connectDialog.submit();
    assert.equal(f.passwordInput.text, ''); assert.equal(f.connectDialog.ssid, '');
    assert.equal(f.page._wifiSecret, 'testsecret');
    f.connectDialog.submit(); assert.equal(f.connector.command.at(-1), 'Home');
});
test('Wi-Fi deadline and failed start clear the credential without leaving the UI busy', () => {
    for (const marker of ['id: wifiDeadline', 'id: wifiFailedStart']) {
        const f = wifiFixture(); f.page.connect('Home', 'testsecret', true);
        f.connector.running = false;
        const handler = body(network.slice(network.indexOf(marker)), 'onTriggered:');
        new Function('page', 'connector', handler)(f.page, f.connector);
        assert.equal(f.page._wifiSecret, ''); assert.equal(f.page.collegando, '');
        assert.equal(f.connector.stdinEnabled, false); assert.ok(f.page.error.length > 0);
    }
});
test('Wi-Fi UI reveals only while pressed and external text uses PlainText', () => {
    assert.match(network, /echoMode:\s*revealMouse\.pressed/);
    assert.doesNotMatch(network, /echoMode:\s*revealMouse\.containsMouse/);
    assert.match(network, /text: connectDialog\.ssid\s+textFormat: Text\.PlainText/);
    assert.match(network, /text: page\.error\s+textFormat: Text\.PlainText/);
    assert.match(network, /text: page\.wired\s+textFormat: Text\.PlainText/);
    assert.match(network, /id: netName\s+textFormat: Text\.PlainText/);
    assert.match(network, /Component\.onDestruction: page\.stopWifi\(\)/);
});

test('Wi-Fi accepts a real masked prefilled SecretAgent prompt and replaces its value', () => {
    const { page, connector } = wifiFixture();
    page.connect('Home', 'newpassword', true);
    page.wifiOutput("Passwords or encryption keys are required to access the wireless network 'Home'.\nPassword (802-11-wireless-security.psk): ***********");
    assert.deepEqual(connector.writes, ['\u0015newpassword\n']);
    assert.equal(page._wifiSecret, '');
});

test('Wi-Fi saved profile uses UUID activation and clears the cached prompt before replacement', () => {
    const f = wifiFixture(), uuid = '12345678-abcd-1234-abcd-123456789012';
    f.wifiLookup.start = function(argv) {
        this.command = argv;
        f.page.profileLookedUp(0, uuid + '\n', this.epoch);
    };
    f.page.connect('Home', 'newsecret', true);
    assert.deepEqual(f.connector.command.slice(-4), ['connection', 'up', 'uuid', uuid]);
    assert.ok(f.connector.command.includes('--ask'));
    assert.ok(!JSON.stringify(f.wifiLookup.command).includes('newsecret'));
    f.page.wifiOutput('Password (802-11-wireless-security.psk): ***********');
    assert.deepEqual(f.connector.writes, ['\u0015newsecret\n']);
});
test('Wi-Fi failed or malformed profile lookup cannot launch or retain a secret', () => {
    for (const [code, out] of [[1, ''], [0, 'not-a-uuid'], [0, '12345678-abcd-1234-abcd-123456789012\nextra']]) {
        const f = wifiFixture();
        f.wifiLookup.start = function() { f.page.profileLookedUp(code, out, this.epoch); };
        f.page.connect('Home', 'newsecret', true);
        assert.deepEqual(f.connector.command, []);
        assert.equal(f.page._wifiSecret, ''); assert.equal(f.page.collegando, '');
        assert.equal(f.page.error, 'Cannot read network profiles.');
    }
});
test('Wi-Fi canceled profile lookup cannot start a late activation', () => {
    const f = wifiFixture();
    f.wifiLookup.start = function() {};
    f.page.connect('Home', 'newsecret', true);
    const epoch = f.wifiLookup.epoch;
    f.page.stopWifi();
    f.page.profileLookedUp(0, '12345678-abcd-1234-abcd-123456789012', epoch);
    assert.deepEqual(f.connector.command, []); assert.equal(f.page._wifiSecret, '');
});
test('Wi-Fi profile lookup matches literal SSID and supports both nmcli type names', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-wifi-profile-'));
    const uuid = '12345678-abcd-1234-abcd-123456789012';
    try {
        fs.writeFileSync(path.join(dir, 'nmcli'), '#!/bin/sh\ncase "$*" in\n "-t -f UUID,TYPE connection show") printf "%s:%s\\n" "$TEST_UUID" "$TEST_TYPE";;\n "--escape no -g 802-11-wireless.ssid connection show uuid $TEST_UUID") printf "%s\\n" "$TEST_SSID";;\n *) exit 7;;\nesac\n', { mode: 0o755 });
        for (const type of ['wifi', '802-11-wireless'])
            for (const ssid of ['  A:P\\folder  ', 'quotes" $() &; foo', '__proto__']) {
                const argv = wifiFixture().page.wifiProfileCommand(ssid);
                const env = { ...process.env, PATH: dir + ':' + process.env.PATH, TEST_UUID: uuid, TEST_TYPE: type, TEST_SSID: ssid };
                const r = spawnSync(argv[0], argv.slice(1), { env, encoding: 'utf8' });
                assert.equal(r.status, 0, r.stderr); assert.equal(r.stdout, uuid + '\n');
                const different = wifiFixture().page.wifiProfileCommand(ssid + ' other');
                const missing = spawnSync(different[0], different.slice(1), { env, encoding: 'utf8' });
                assert.equal(missing.status, 0, missing.stderr); assert.equal(missing.stdout, '');
            }
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

function greeterTransport(online = false) {
    const sent = [], ipc = { _aperto: online, _salutato: online, _vivo: online ? {} : null,
        _coda: [], _codaMax: 32, _scrivi: s => sent.push(JSON.parse(s)) };
    for (const name of ['_loginAction', 'send', '_svuotaCoda']) {
        const code = optional(ipcSource, `function ${name}(`);
        if (code) ipc[name] = new Function('ipc', 'payload', code).bind(null, ipc);
    }
    return { ipc, sent };
}
test('Offline login messages never enter the queue or replay after reconnect', () => {
    const { ipc, sent } = greeterTransport();
    for (const action of ['greeter_create_session', 'greeter_respond', 'greeter_start', 'greeter_cancel'])
        assert.equal(ipc.send({ action, response: 'fictitious-login-secret' }), false);
    assert.deepEqual(ipc._coda, []);
    ipc._aperto = ipc._salutato = true; ipc._vivo = {};
    ipc._svuotaCoda(); assert.deepEqual(sent, []);
});
test('Login rejects a missing socket and still sends once on a live channel', () => {
    const { ipc, sent } = greeterTransport(true);
    ipc._vivo = null;
    assert.equal(ipc.send({ action: 'greeter_respond', response: 'fake' }), false);
    assert.deepEqual(sent, []); assert.deepEqual(ipc._coda, []);
    ipc._vivo = {};
    assert.equal(ipc.send({ action: 'greeter_respond', response: 'fake' }), true);
    assert.deepEqual(sent, [{ action: 'greeter_respond', response: 'fake' }]);
});
test('Queue drain discards legacy login entries while preserving startup reads', () => {
    const { ipc, sent } = greeterTransport(true);
    ipc._coda = [{ action: 'greeter_respond', response: 'old' }, { action: 'greeter_info' }, { action: 'get_windows' }];
    ipc._svuotaCoda();
    assert.deepEqual(sent, [{ action: 'greeter_info' }, { action: 'get_windows' }]);
    assert.deepEqual(ipc._coda, []);
});
test('Retired socket callbacks cannot close or authenticate the live socket', () => {
    for (const marker of ['onError: function(quale)', 'onConnectionStateChanged:', 'function leggi(']) {
        const ipc = { _vivo: {}, _aperto: true, _salutato: true, _haProvato: false };
        const socket = { connected: false };
        const timer = { running: false, start() { throw new Error('retired socket restarted timer'); } };
        const code = body(ipcSource.slice(ipcSource.indexOf('property Component _stampo:')), marker);
        new Function('ipc', 'socket', 'reconnectTimer', 'message', code)(ipc, socket, timer, '{"event":"ciao","payload":{"ok":true}}');
        assert.equal(ipc._aperto, true); assert.equal(ipc._salutato, true); assert.equal(ipc._haProvato, false);
    }
});

const greeterSource = source('minerva-shell/greeter/Greeter.qml');
function loginFixture() {
    const greeter = { finto: false, it: false, informato: true, utente: { nome: 'demo' },
        domanda: 'Password:', inCorso: false, avviato: true, annullando: true,
        erroriMax: 4, erroriDiFila: 0, canalePerso: false };
    const campo = { text: 'fictitious-login-secret' }, riprova = { stopped: false, stop() { this.stopped = true; } };
    const sent = [], Core = { Ipc: { connected: false, greeterRespond: s => { sent.push(s); return false; }, greeterCancel: () => false } };
    for (const name of ['perdiCanale', 'rispondi', 'annullaERicomincia', 'comincia']) {
        const code = optional(greeterSource, `function ${name}(`);
        if (code) greeter[name] = new Function('greeter', 'campo', 'riprova', 'Core', 'testo', code).bind(null, greeter, campo, riprova, Core);
    }
    return { greeter, campo, riprova, Core, sent };
}
test('Login channel loss clears the field, cancels retry and resets pending state', () => {
    const f = loginFixture();
    f.greeter.perdiCanale();
    assert.equal(f.campo.text, ''); assert.equal(f.riprova.stopped, true);
    assert.equal(f.greeter.domanda, ''); assert.equal(f.greeter.inCorso, false);
    assert.equal(f.greeter.avviato, false); assert.equal(f.greeter.annullando, false);
    assert.equal(f.greeter.canalePerso, true); assert.ok(f.greeter.erroriDiFila > f.greeter.erroriMax);
});
test('Rejected login response clears input and does not leave the UI waiting', () => {
    const f = loginFixture(); f.greeter.rispondi(f.campo.text);
    assert.equal(f.campo.text, ''); assert.equal(f.greeter.inCorso, false);
    assert.equal(f.greeter.canalePerso, true); assert.equal(f.sent.length, 1);
});
test('Late login success cannot finish or restart a disconnected conversation', () => {
    const f = loginFixture(); f.greeter.canalePerso = true;
    f.greeter.finito = f.greeter.comincia = () => { throw new Error('late login response accepted'); };
    new Function('greeter', 'm', body(greeterSource, 'function onGreeterMessage('))(f.greeter, { type: 'success' });
    assert.equal(f.greeter.canalePerso, true);
});
test('Retry while still offline does not leave login stuck cancelling', () => {
    const f = loginFixture(); f.greeter.annullaERicomincia();
    assert.equal(f.greeter.annullando, false); assert.equal(f.greeter.inCorso, false);
    assert.equal(f.greeter.canalePerso, true);
});

test('Changing selection after connection loss cannot bypass explicit retry', () => {
    const f = loginFixture(); f.greeter.canalePerso = true;
    f.Core.Ipc.greeterCreateSession = () => { throw new Error('unexpected restart'); };
    f.greeter.comincia();
    assert.equal(f.greeter.inCorso, false); assert.equal(f.greeter.canalePerso, true);
    assert.ok(f.greeter.erroriDiFila > f.greeter.erroriMax);
});
test('Explicit retry after reconnect waits for cancellation before creating a session', () => {
    const f = loginFixture(); f.greeter.canalePerso = true; f.Core.Ipc.connected = true;
    let cancels = 0, creates = 0;
    f.Core.Ipc.greeterCancel = () => { cancels++; return true; };
    f.Core.Ipc.greeterCreateSession = () => { creates++; return true; };
    f.greeter.annullaERicomincia();
    assert.equal(cancels, 1); assert.equal(creates, 0);
    assert.equal(f.greeter.canalePerso, false); assert.equal(f.greeter.annullando, true);
    new Function('greeter', 'm', body(greeterSource, 'function onGreeterMessage('))(f.greeter, { type: 'success' });
    assert.equal(creates, 1); assert.equal(f.greeter.annullando, false);
    assert.equal(f.greeter.avviato, false);
});
