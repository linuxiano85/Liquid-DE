"""Local Debian bootstrap: build native packages as the user, install with APT."""
import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

from native import DEPS, VERSION, audit, prepare, source_fingerprint
from runtime import digest

DART_VERSION = '3.12.0'
DART_URL = ('https://storage.googleapis.com/dart-archive/channels/stable/release/'
            + DART_VERSION + '/sdk/dartsdk-linux-x64-release.zip')


def preflight(source, work):
    if os.geteuid() == 0:
        raise ValueError('Avvia come utente normale: solo APT userà sudo.')
    status = Path('/proc/self/status').read_text()
    if re.search(r'^NoNewPrivs:\s+1$', status, re.M):
        raise ValueError('Il sandbox impedisce sudo (NoNewPrivs=1). Esegui '
                         './install.sh --build-local dal terminale normale di Mint.')
    if not shutil.which('sudo') or not shutil.which('apt-get'):
        raise ValueError('Servono sudo e APT per installare le dipendenze.')
    if work.is_relative_to(source):
        raise ValueError('La directory di lavoro deve stare fuori dai sorgenti.')
    for relative in ('compositore/meson.build', 'minervad/pubspec.yaml',
                     'native/window-identity/CMakeLists.txt'):
        if not (source / relative).is_file():
            raise ValueError('Avvia la build dalla cartella completa dei sorgenti: manca ' + relative)
    parent = work
    while not parent.exists():
        parent = parent.parent
    if shutil.disk_usage(parent).free < 24 * 1024 ** 3:
        raise ValueError('Servono almeno 24 GiB liberi per sorgenti Qt, build e pacchetti.')
    if work.exists() and (work.stat().st_uid != os.getuid() or work.stat().st_mode & 0o077):
        raise ValueError('Usa una directory di lavoro privata, di proprietà del tuo utente (modo 0700).')


def read_https(url, limit):
    with urllib.request.urlopen(url, timeout=60) as response:
        if urllib.parse.urlsplit(response.geturl()).scheme != 'https':
            raise ValueError('Download toolchain reindirizzato fuori da HTTPS')
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Risposta toolchain troppo grande')
    return data


def dart_version(executable):
    result = subprocess.run([str(executable), '--version'], text=True,
                            capture_output=True, check=True, timeout=15)
    match = re.search(r'Dart SDK version:\s+(\d+)\.(\d+)\.(\d+)', result.stdout + result.stderr)
    return tuple(map(int, match.groups())) if match else None


def ensure_dart(work):
    system = shutil.which('dart')
    if system:
        version = dart_version(system)
        if version and (3, 12, 0) <= version < (4, 0, 0):
            return Path(system).resolve().parent
    folder = work / 'toolchain'
    folder.mkdir(exist_ok=True)
    sdk = folder / 'dart-sdk'
    if (sdk / 'bin/dart').is_file():
        if dart_version(sdk / 'bin/dart') != (3, 12, 0):
            raise ValueError('SDK Dart locale incompleto o diverso dalla versione registrata')
        return sdk / 'bin'
    archive = folder / ('dart-' + DART_VERSION + '.zip')
    # The checksum is obtained from the official archive over authenticated TLS,
    # and recorded locally. This is publisher verification, not a pinned digest.
    checksum = read_https(DART_URL + '.sha256sum', 4096).decode('ascii').split()[0]
    if not re.fullmatch('[0-9a-f]{64}', checksum):
        raise ValueError('Checksum ufficiale Dart non valido')
    if not archive.exists():
        temporary = archive.with_suffix('.part')
        try:
            with urllib.request.urlopen(DART_URL, timeout=60) as response, temporary.open('wb') as output:
                if urllib.parse.urlsplit(response.geturl()).scheme != 'https':
                    raise ValueError('Download SDK non HTTPS')
                shutil.copyfileobj(response, output)
            if digest(temporary) != checksum:
                raise ValueError('Checksum SDK Dart non corrispondente')
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if digest(archive) != checksum:
        raise ValueError('Archivio SDK Dart locale corrotto')
    with tempfile.TemporaryDirectory(prefix='.dart-extract-', dir=folder) as temp:
        temp = Path(temp)
        with zipfile.ZipFile(archive) as stream:
            entries = stream.infolist()
            if len(entries) > 30000 or sum(entry.file_size for entry in entries) > 2 * 1024 ** 3:
                raise ValueError('Archivio SDK Dart eccessivo')
            for entry in entries:
                relative = PurePosixPath(entry.filename)
                if (relative.is_absolute() or '..' in relative.parts or '\\' in entry.filename
                        or not relative.parts or relative.parts[0] != 'dart-sdk'
                        or stat.S_ISLNK(entry.external_attr >> 16)):
                    raise ValueError('Percorso non consentito nell’SDK Dart')
                target = temp.joinpath(*relative.parts)
                if entry.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with stream.open(entry) as source, target.open('wb') as output:
                        shutil.copyfileobj(source, output)
                    target.chmod(0o755 if (entry.external_attr >> 16) & 0o111 else 0o644)
        (temp / 'dart-sdk').rename(sdk)
    (folder / 'sdk.json').write_text(json.dumps({'version': DART_VERSION,
        'url': DART_URL, 'sha256': checksum}, indent=2) + '\n')
    if dart_version(sdk / 'bin/dart') != (3, 12, 0):
        raise ValueError('L’SDK Dart scaricato non corrisponde alla versione prevista')
    return sdk / 'bin'


def dependency_commands():
    return [
        ['sudo', 'apt-get', 'update'],
        ['sudo', 'apt-get', '--no-remove', 'install', '--yes',
         *sorted(set(DEPS['deb']['build'] + DEPS['deb']['desktop'] + DEPS['deb']['runtime']))],
    ]


def runtime_command(source, work, jobs):
    return [sys.executable, str(source / 'packaging/runtime.py'), '--work-dir', str(work / 'runtime-build'),
            '--prefix', str(work / 'runtime'), '--jobs', str(jobs), '--resume']


def verify_packages(include_login):
    names = ['liquid-de', 'liquid-de-runtime'] + (['liquid-de-login'] if include_login else [])
    result = subprocess.run(['dpkg-query', '-W', '-f=${Package}\t${Status}\n', *names],
                            text=True, capture_output=True, check=True)
    statuses = dict(line.split('\t', 1) for line in result.stdout.splitlines() if '\t' in line)
    if any(statuses.get(name) != 'install ok installed' for name in names):
        raise ValueError('Pacchetti Liquid non completamente configurati: ' + result.stdout.strip())
    audit_result = subprocess.run(['dpkg', '--audit'], text=True, capture_output=True, check=True)
    if audit_result.stdout.strip() or audit_result.stderr.strip():
        raise ValueError('DPKG segnala problemi da risolvere: ' +
                         (audit_result.stdout + audit_result.stderr).strip())


def build_plan(source, work, target, jobs, include_login=False):
    key = source_fingerprint(source)[:20]
    snapshot, stage, packages = [work / (name + '-' + key) for name in ('source', 'stage', 'packages')]
    base = [sys.executable, str(source / 'packaging/native.py')]
    version = VERSION + '+' + target['repository'].replace('-', '') + '-1_amd64.deb'
    names = ['liquid-de', 'liquid-de-runtime'] + (['liquid-de-login'] if include_login else [])
    return [*dependency_commands(),
        [*base, 'prepare', '--target', target['repository'], '--output', str(snapshot)],
        runtime_command(source, work, jobs),
        [*base, 'build', '--target', target['repository'], '--source', str(snapshot),
         '--runtime-prefix', str(work / 'runtime'), '--jobs', str(jobs)],
        [*base, 'stage', '--target', target['repository'], '--source', str(snapshot),
         '--runtime-prefix', str(work / 'runtime'), '--destdir', str(stage)],
        [*base, 'package', '--target', target['repository'], '--destdir', str(stage), '--output', str(packages)],
        ['sudo', 'apt-get', '--no-remove', '--reinstall', 'install',
         *[str(packages / (name + '_' + version)) for name in names]],
    ]


def install(source, work, target, jobs, include_login, install_packages):
    source, work = source.resolve(), work.resolve()
    preflight(source, work)
    work.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (work / 'install.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Un’altra installazione locale usa questa directory.') from error
        log = work / ('install-' + time.strftime('%Y%m%d-%H%M%S') + '.log')
        state_file = work / 'install-state.json'
        if state_file.exists() and json.loads(state_file.read_text()).get('target') != target['repository']:
            raise ValueError('La directory contiene una build di un’altra base: scegline una nuova.')
        state = {'schema': 1, 'target': target['repository'], 'phase': 'preflight',
                 'sessionVerified': False, 'log': str(log)}
        print('Registro di installazione: ' + str(log), flush=True)
        with log.open('w') as output:
            def save(phase, **values):
                state.update(phase=phase, **values)
                temporary = state_file.with_suffix('.new')
                temporary.write_text(json.dumps(state, indent=2) + '\n')
                temporary.replace(state_file)
                message = '\n[Liquid DE] ' + phase + '\n'
                print(message, flush=True)
                output.write(message)
                output.flush()

            def run(command, env=None, capture=True):
                if not capture:
                    subprocess.run(command, env=env, check=True)
                    return
                process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True, errors='replace')
                try:
                    for line in process.stdout:
                        print(line, end='', flush=True)
                        output.write(line)
                        output.flush()
                    code = process.wait()
                    if code:
                        raise subprocess.CalledProcessError(code, command)
                finally:
                    process.stdout.close()
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()

            try:
                # The password prompt remains attached to the real terminal.
                # No build process is ever run through sudo.
                run(['sudo', '-v'], capture=False)
                save('dipendenze')
                for command in dependency_commands():
                    run(command)
                save('toolchain-dart')
                dart = ensure_dart(work)
                env = dict(os.environ, PATH=str(dart) + os.pathsep + os.environ['PATH'])
                fingerprint = source_fingerprint(source)
                snapshot = work / ('source-' + fingerprint[:20])
                if not snapshot.exists():
                    save('preparazione-sorgenti')
                    with tempfile.TemporaryDirectory(prefix='.source-', dir=work) as temporary:
                        prepared = Path(temporary) / 'source'
                        prepare(source, prepared)
                        if source_fingerprint(source) != fingerprint:
                            raise ValueError('Sorgenti cambiati durante la copia: rilancia l’installer.')
                        prepared.rename(snapshot)
                save('compilazione-runtime', sourceFingerprint=fingerprint)
                run(runtime_command(source, work, jobs), env)
                save('compilazione-desktop')
                base = [sys.executable, str(source / 'packaging/native.py')]
                run([*base, 'build', '--target', target['repository'], '--source', str(snapshot),
                     '--runtime-prefix', str(work / 'runtime'), '--jobs', str(jobs)], env)
                save('staging')
                stage = work / ('stage-' + fingerprint[:20])
                if not stage.exists():
                    with tempfile.TemporaryDirectory(prefix='.stage-', dir=work) as temporary:
                        staging = Path(temporary) / 'stage'
                        run([*base, 'stage', '--target', target['repository'], '--source', str(snapshot),
                             '--runtime-prefix', str(work / 'runtime'), '--destdir', str(staging)], env)
                        staging.rename(stage)
                audit(stage)
                save('pacchetti')
                packages = work / ('packages-' + fingerprint[:20])
                if not packages.exists():
                    with tempfile.TemporaryDirectory(prefix='.packages-', dir=work) as temporary:
                        candidates = Path(temporary) / 'packages'
                        run([*base, 'package', '--target', target['repository'], '--destdir', str(stage),
                             '--output', str(candidates)], env)
                        candidates.rename(packages)
                save('installazione-pacchetti', packages=str(packages))
                install_packages(packages, target, include_login)
                save('verifica-installazione')
                run(['/usr/lib/liquid-de/scripts/minerva-quickshell', '--runtime'], env)
                verify_packages(include_login)
                for relative in ('usr/share/wayland-sessions/liquid-de.desktop',
                                 'usr/share/wayland-sessions/liquid-de-recupero.desktop',
                                 'usr/lib/liquid-de/package-install.json', 'etc/pam.d/liquid-de'):
                    if not (Path('/') / relative).is_file():
                        raise ValueError('File installato mancante: /' + relative)
                save('installato')
                print('Pacchetti installati. Al prossimo accesso scegli Liquid DE; '
                      'il primo accesso deve ancora essere verificato.', flush=True)
            except BaseException as error:
                save('interrotto', error=str(error))
                raise
