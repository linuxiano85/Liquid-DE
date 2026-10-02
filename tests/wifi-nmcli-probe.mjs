// Run real nmcli on a private test bus, with production QML JS around its pipes.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import { wifiFixture } from './wifi-harness.mjs';

const f = wifiFixture();
const secret = process.env.TEST_WIFI_SECRET;
if (!secret || !process.env.DBUS_SYSTEM_BUS_ADDRESS) throw new Error('Private bus and fictitious secret required');
if (!f.page.connect('Audit_Test_AP', secret, true)) throw new Error('Connection rejected');
const argv = process.argv.includes('--agent')
    ? ['env', 'LC_ALL=C', 'nmcli', '--colors', 'no', '--ask', 'agent', 'secret']
    : f.connector.command;
const child = spawn(argv[0], argv.slice(1), { stdio: ['pipe', 'pipe', 'pipe'] });
let output = '', errors = '', writes = 0, cmdlineHasSecret = false;
let finishAgent;
const timeout = setTimeout(() => child.kill('SIGKILL'), 10000);
f.connector.write = data => {
    const pidArgs = fs.readFileSync(`/proc/${child.pid}/cmdline`);
    cmdlineHasSecret ||= pidArgs.includes(Buffer.from(secret));
    writes++;
    child.stdin.end(data);
    if (process.argv.includes('--agent')) finishAgent = setTimeout(() => child.kill('SIGTERM'), 1000);
};
child.stdin.on('error', () => {}); // failure/EOF is reported through the exit result
child.stdout.on('data', data => { output += data; f.page.wifiOutput(data.toString()); });
child.stderr.on('data', data => { errors += data; });
child.on('error', err => { throw err; });
child.on('close', (code, signal) => {
    clearTimeout(timeout); clearTimeout(finishAgent);
    console.log(JSON.stringify({ code, signal, writes, secretCleared: f.page._wifiSecret === '',
        argvHasSecret: JSON.stringify(argv).includes(secret), cmdlineHasSecret,
        outputHasSecret: (output + errors).includes(secret),
        debug: process.env.WIFI_PROBE_DEBUG ? (output + errors).replaceAll(secret, '[REDACTED]') : undefined }));
});
