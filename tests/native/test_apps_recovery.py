"""Real Quickshell windows on disposable Xvfb, without a production daemon."""
import os
from pathlib import Path
import signal
import subprocess
import time

repo = Path.cwd()
out = repo / 'native-results'

def run(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=20, **kw)

def window(pattern):
    return run('xdotool', 'search', '--onlyvisible', '--name', pattern).returncode == 0

def until(predicate, description):
    end = time.monotonic() + 15
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(.2)
    raise AssertionError(description)

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
            until(lambda: ipc('ping').returncode == 0, name + ': IPC not ready')
            if preload:
                time.sleep(3.5)
                assert not window(pattern), 'preload showed a window'
                opened = run('sh', str(repo / 'scripts/minerva-files'), str(Path.home()))
                assert opened.returncode == 0, opened.stderr
            until(lambda: window(pattern), name + ': no visible window')
            if target == 'files':
                for i in range(5):
                    r = run('sh', str(repo / 'scripts/minerva-files'), str(Path.home()))
                    assert r.returncode == 0, r.stderr
                    assert window(pattern), 'window disappeared'
            subprocess.run(['import', '-window', 'root', str(out / (name + '.png'))], check=True, timeout=10)
            assert p.poll() is None, 'Quickshell exited'
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGTERM)
                try: p.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGKILL); p.wait()
    text = log.read_text()
    for error in ('TypeError:', 'ReferenceError:', 'is not a type', 'Cannot assign to non-existent property', 'Failed to load configuration'):
        assert error not in text, f'{name}: {error}\n{text}'
    print(name + ': PASS', flush=True)

scenario('fucina', 'app.qml', {'MINERVA_APP_APRI': 'fucina'}, 'app', 'Fucina')
scenario('files-cold', 'filemanager.qml', {}, 'files', 'File')
scenario('files-preload', 'filemanager.qml', {'MINERVA_FILES_DORMIENTE': '1'}, 'files', 'File', True)
print('NATIVE_APPS_RECOVERY_PASSED')
