"""Production windows and IPC on disposable headless Wayland/Sway.

File's context menus require layer-shell, so Xvfb cannot complete its QML tree.
No production daemon, display, packages or user files are modified.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import time

repo = Path.cwd()
out = repo / 'native-results'
runtime = Path(os.environ['XDG_RUNTIME_DIR'])

def run(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=20, **kw)

def until(predicate, description):
    end = time.monotonic() + 15
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(.2)
    raise AssertionError(description)

def windows(pattern):
    response = run('swaymsg', '-t', 'get_tree', '-r')
    assert response.returncode == 0, response.stderr
    found = []
    def visit(node):
        if pattern in (node.get('name') or '') and node.get('pid'):
            found.append(node)
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            visit(child)
    visit(json.loads(response.stdout))
    return found

def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()

def scenario(name, config, env, target, pattern, preload=False):
    log = out / (name + '.log')
    with log.open('w') as f:
        p = subprocess.Popen(['qs', '-p', str(repo / 'minerva-shell' / config)],
                             env=dict(os.environ, **env), stdout=f, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            def ipc(*args):
                return run('qs', 'ipc', '-p', str(repo / 'minerva-shell' / config),
                           'call', target, *args)
            until(lambda: ipc('ping').stdout.strip() == 'ok', name + ': IPC not ready')
            if preload:
                time.sleep(3.5)
                assert not windows(pattern), 'preload showed a window'
                opened = run('sh', str(repo / 'scripts/minerva-files'), str(Path.home()))
                assert opened.returncode == 0, opened.stderr
            until(lambda: bool(windows(pattern)), name + ': no visible window')
            if target == 'files':
                assert ipc('avvia', str(Path.home())).stdout.strip() == 'ok'
                for _ in range(5):
                    r = run('sh', str(repo / 'scripts/minerva-files'), str(Path.home()))
                    assert r.returncode == 0, r.stderr
                    assert windows(pattern), 'window disappeared'
            shot = run('grim', str(out / (name + '.png')))
            assert shot.returncode == 0, shot.stderr
            assert p.poll() is None, 'Quickshell exited'
        except Exception:
            print(log.read_text(), flush=True)
            raise
        finally:
            stop(p)
    text = log.read_text()
    for error in ('TypeError:', 'ReferenceError:', 'is not a type', 'Cannot assign to non-existent property', 'Failed to load configuration'):
        assert error not in text, f'{name}: {error}\n{text}'
    until(lambda: not windows(pattern), name + ': window survived process shutdown')
    print(name + ': PASS', flush=True)

config = out / 'sway.conf'
config.write_text('output * resolution 1360x900\ninput * xkb_layout us\ndefault_border none\n')
with (out / 'sway.log').open('w') as sway_log:
    sway = subprocess.Popen(['sway', '--unsupported-gpu', '-c', str(config)],
        env=dict(os.environ, WLR_BACKENDS='headless', WLR_RENDERER='pixman', WLR_LIBINPUT_NO_DEVICES='1'),
        stdout=sway_log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        until(lambda: bool(list(runtime.glob('sway-ipc.*.sock'))), 'Sway socket unavailable')
        os.environ['SWAYSOCK'] = str(next(runtime.glob('sway-ipc.*.sock')))
        until(lambda: any(p.is_socket() for p in runtime.glob('wayland-*')), 'Wayland socket unavailable')
        os.environ['WAYLAND_DISPLAY'] = next(p.name for p in runtime.glob('wayland-*') if p.is_socket())
        os.environ['QT_QPA_PLATFORM'] = 'wayland'
        scenario('fucina', 'app.qml', {'MINERVA_APP_APRI': 'fucina'}, 'app', 'Fucina')
        scenario('files-cold', 'filemanager.qml', {}, 'files', 'File')
        scenario('files-preload', 'filemanager.qml', {'MINERVA_FILES_DORMIENTE': '1'}, 'files', 'File', True)
        print('NATIVE_APPS_RECOVERY_PASSED')
    finally:
        stop(sway)
