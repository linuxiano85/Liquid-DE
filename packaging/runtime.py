#!/usr/bin/env python3
"""Build pinned private libraries in a disposable, unprivileged build directory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent


def digest(path, algorithm='sha256'):
    result = hashlib.new(algorithm)
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def fetch(spec, cache):
    algorithm = 'sha512' if 'sha512' in spec else 'sha256'
    expected = spec[algorithm]
    if not re.fullmatch('[a-f0-9]{' + str(hashlib.new(algorithm).digest_size * 2) + '}', expected):
        raise ValueError('Checksum non valido: ' + spec['name'])
    archive = cache / (spec['name'] + '-' + spec['version'] + '.tar')
    if not archive.exists():
        if urllib.parse.urlsplit(spec['url']).scheme != 'https':
            raise ValueError('I sorgenti richiedono HTTPS')
        temporary = archive.with_suffix('.part')
        try:
            with urllib.request.urlopen(spec['url'], timeout=120) as source, temporary.open('wb') as output:
                if urllib.parse.urlsplit(source.geturl()).scheme != 'https':
                    raise ValueError('Redirect sorgenti non HTTPS')
                shutil.copyfileobj(source, output)
            if digest(temporary, algorithm) != expected:
                raise ValueError('Checksum sorgenti diverso: ' + spec['name'])
            temporary.rename(archive)
        finally:
            temporary.unlink(missing_ok=True)
    if digest(archive, algorithm) != expected:
        raise ValueError('Cache sorgenti corrotta: ' + spec['name'])
    return archive


def extract(archive, destination):
    if destination.exists():
        raise ValueError('La directory dei sorgenti esiste già: ' + str(destination))
    # data_filter blocks escaping symlinks, devices and traversal. Never reuse
    # a source directory whose contents might predate the verified archive.
    with tempfile.TemporaryDirectory(prefix='.' + destination.name + '-', dir=destination.parent) as temp:
        temporary = Path(temp) / 'contents'
        temporary.mkdir()
        with tarfile.open(archive) as stream:
            stream.extractall(temporary, filter='data')
        directories = list(temporary.iterdir())
        if len(directories) != 1 or not directories[0].is_dir():
            raise ValueError('Archivio sorgenti senza una radice unica')
        name = directories[0].name
        temporary.rename(destination)
    return destination / name


def environment(prefix):
    env = dict(os.environ)
    env['PATH'] = str(prefix / 'bin') + os.pathsep + env['PATH']
    env['PKG_CONFIG_PATH'] = str(prefix / 'lib/pkgconfig') + ':' + str(prefix / 'share/pkgconfig')
    env['CMAKE_PREFIX_PATH'] = str(prefix)
    # Build-only. These values are never written into the session environment.
    env['LD_LIBRARY_PATH'] = str(prefix / 'lib')
    env['CFLAGS'] = '-O2 -march=x86-64 -mtune=generic'
    env['CXXFLAGS'] = env['CFLAGS']
    env['LDFLAGS'] = '-Wl,-rpath,' + str(prefix / 'lib')
    return env


def build(work, prefix, jobs, resume=False):
    spec = json.loads((HERE / 'runtime-sources.json').read_text())
    work.mkdir(parents=True, exist_ok=True)
    state_file = work / 'progress.json'
    identity = {'schema': 1, 'sourceManifestSha256': digest(HERE / 'runtime-sources.json'),
                'recipeSha256': digest(Path(__file__)), 'prefix': str(prefix)}
    completed = []
    if resume and state_file.exists():
        saved = json.loads(state_file.read_text())
        if any(saved.get(key) != value for key, value in identity.items()):
            raise ValueError('Ricetta runtime modificata: usare una directory di build nuova')
        completed = saved.get('completed', [])
        names = [item['name'] for item in spec['sources']]
        if not isinstance(completed, list) or completed != names[:len(completed)]:
            raise ValueError('Stato di compilazione runtime non valido')
    elif prefix.exists() and any(prefix.iterdir()):
        raise ValueError('Il prefisso del runtime deve essere vuoto')
    elif state_file.exists():
        raise ValueError('La build esiste già: usare --resume')
    prefix.mkdir(parents=True, exist_ok=True)

    def save():
        temporary = state_file.with_suffix('.new')
        temporary.write_text(json.dumps(dict(identity, completed=completed), indent=2) + '\n')
        temporary.replace(state_file)

    save()
    cache = work / 'downloads'
    cache.mkdir(exist_ok=True)
    env = environment(prefix)

    def run(*args, cwd=None):
        subprocess.run(list(map(str, args)), env=env, cwd=cwd, check=True)

    for item in spec['sources']:
        if item['name'] in completed:
            print('Runtime già compilato: ' + item['name'], flush=True)
            continue
        print('Compilo runtime: ' + item['name'] + ' ' + item['version'], flush=True)
        destination = work / (item['name'] + '-source')
        if destination.exists():
            if not resume:
                raise ValueError('Usare una directory di build nuova: ' + str(destination))
            directories = list(destination.iterdir())
            if len(directories) != 1 or not directories[0].is_dir():
                raise ValueError('Sorgenti runtime incompleti: ' + str(destination))
            source = directories[0]
        else:
            source = extract(fetch(item, cache), destination)
        output = work / (item['name'] + '-build')
        if item['name'] == 'qt':
            output.mkdir(exist_ok=True)
            # Selecting modules avoids building QtWebEngine and other unrelated SDKs.
            if not (output / 'CMakeCache.txt').exists():
                run(source / 'configure', '-prefix', prefix, '-release', '-opensource',
                    '-confirm-license', '-nomake', 'examples', '-nomake', 'tests',
                    '-xcb', '-opengl', 'desktop',
                    '-submodules', ','.join(item['modules']), '--',
                    '-DCMAKE_INSTALL_LIBDIR=lib', '-DCMAKE_BUILD_RPATH=' + str(prefix / 'lib'),
                    '-DCMAKE_INSTALL_RPATH=$ORIGIN', cwd=output)
            run('cmake', '--build', output, '--parallel', jobs)
            run('cmake', '--install', output)
        else:
            if not (output / 'meson-private/coredata.dat').exists():
                run('meson', 'setup', output, source, '--prefix=' + str(prefix),
                    '--libdir=lib', '--buildtype=release', '--wrap-mode=nofallback', *item['options'])
            run('meson', 'compile', '-C', output, '-j', jobs)
            run('meson', 'install', '-C', output)
        license_dir = prefix / 'licenses' / item['name']
        license_dir.mkdir(parents=True, exist_ok=True)
        patterns = ['COPYING*', 'LICENSE*', 'LICENSES/*', 'qtbase/LICENSES/*'] + item.get('licenseFiles', [])
        licenses = {p for pattern in patterns for p in source.glob(pattern) if p.is_file()}
        if item['name'] == 'qt':
            for module in item['modules']:
                for path in (source / module).rglob('*'):
                    if path.is_file() and (path.name.startswith(('LICENSE', 'COPYING', 'NOTICE'))
                                           or path.name == 'qt_attribution.json'):
                        licenses.add(path)
        for license_file in licenses:
            destination = license_dir / license_file.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(license_file, destination)
        if not any(license_dir.iterdir()):
            raise ValueError('Licenza sorgenti mancante: ' + item['name'])
        completed.append(item['name'])
        save()
    (prefix / 'runtime.json').write_text(json.dumps({
        'schema': 1, 'qtVersion': spec['qtVersion'], 'sources': spec['sources'],
        'sourceManifestSha256': digest(HERE / 'runtime-sources.json'),
    }, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', required=True, type=Path)
    parser.add_argument('--prefix', required=True, type=Path)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    build(args.work_dir.resolve(), args.prefix.resolve(), max(1, args.jobs), args.resume)
