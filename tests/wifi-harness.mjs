import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { body } from './qml-body.mjs';

const root = process.env.SHELL_SOURCE_ROOT || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const wifiSource = fs.readFileSync(path.join(root, 'minerva-shell/settings/sections/Network.qml'), 'utf8');

// Minimal Qt substitutes around actual production function bodies.
export function wifiFixture() {
    const page = { collegando: '', _provaSenzaPassword: false, _wifiSecret: '', _wifiPrompt: '',
        _wifiFailure: '', _wifiEpoch: 0, wifiOn: true, it: false, error: '', refresh() {} };
    const connector = { running: false, stdinEnabled: false, command: [], writes: [], signals: [],
        write(data) { this.writes.push(data); }, signal(n) { this.signals.push(n); } };
    const timer = () => ({ active: false, restart() { this.active = true; }, stop() { this.active = false; } });
    const wifiDeadline = timer(), wifiFailedStart = timer();
    const passwordInput = { text: '', forceActiveFocus() {} };
    const connectDialog = { visible: false, ssid: '', opened: [] };
    const wifiLookup = { busy: false, epoch: -1, command: [],
        start(argv) { this.command = argv; page.profileLookedUp(0, '', this.epoch); } };
    const names = ['wifiLookup', 'page', 'connector', 'wifiDeadline', 'wifiFailedStart', 'connectDialog', 'passwordInput'];
    const values = [wifiLookup, page, connector, wifiDeadline, wifiFailedStart, connectDialog, passwordInput];
    const args = { profileLookedUp: ['code', 'out', 'epoch'], startWifiCommand: ['uuid'],
        wifiProfileCommand: ['ssid'], connect: ['ssid', 'password', 'protetta'], wifiOutput: ['data'], wifiError: ['data'],
        completeWifi: ['code', 'epoch'], stopWifi: [], mancaLaPassword: ['testo'] };
    for (const [name, params] of Object.entries(args)) {
        const fn = new Function(...names, ...params, body(wifiSource, `function ${name}(`));
        page[name] = (...call) => fn(...values, ...call);
    }
    const dialogSource = wifiSource.slice(wifiSource.indexOf('id: connectDialog'));
    for (const [name, params] of [['cancel', []], ['submit', []], ['open', ['s']]]) {
        const fn = new Function(...names, ...params, body(dialogSource, `function ${name}(`));
        connectDialog[name] = (...call) => fn(...values, ...call);
    }
    return { page, connector, wifiLookup, wifiDeadline, wifiFailedStart, connectDialog, passwordInput };
}
