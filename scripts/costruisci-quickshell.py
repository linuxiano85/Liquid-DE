#!/usr/bin/env python3
"""Compila il runtime locale dei menu senza sostituire Quickshell di sistema."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(value) for value in args], check=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive(url, target, expected):
    if not target.exists():
        temporary = target.with_suffix('.part')
        try:
            with urllib.request.urlopen(url, timeout=30) as response, temporary.open('wb') as output:
                total = 0
                while chunk := response.read(65536):
                    total += len(chunk)
                    if total > 20 * 1024 * 1024:
                        raise RuntimeError('Archivio oltre il limite previsto')
                    output.write(chunk)
            if digest(temporary) != expected:
                raise RuntimeError('SHA-256 dei sorgenti non corrispondente')
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
    if digest(target) != expected:
        raise RuntimeError('Archivio nella cache alterato: ' + str(target))


def extract(archive_path, destination, extracted_name):
    if destination.is_dir():
        return
    with tarfile.open(archive_path) as source:
        # Il filtro rifiuta percorsi e collegamenti che escono dalla cartella.
        source.extractall(destination.parent, filter='data')
    os.replace(destination.parent / extracted_name, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default_cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache')))
    parser.add_argument('--work-dir', type=Path, default=default_cache / 'liquid-de/quickshell-0.3.2')
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 32:
        parser.error('--jobs deve essere compreso tra 1 e 32')
    for command in ['cmake', 'ninja', 'c++', 'pkg-config', 'patch', 'strip']:
        if not shutil.which(command):
            raise RuntimeError('Dipendenza mancante: ' + command)
    specification = json.loads((ROOT / 'native/quickshell/source.json').read_text())
    patch = ROOT / 'patches/quickshell-0.3.2-dbusmenu-order.patch'
    if digest(patch) != specification['patchSha256']:
        raise RuntimeError('Patch diversa dalla versione registrata')
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    source_archive = work / 'sorgenti.tar.gz'
    cli_archive = work / 'CLI11-v2.5.0.tar.gz'
    archive(specification['sourceUrl'], source_archive, specification['sourceSha256'])
    archive(specification['cli11Url'], cli_archive, specification['cli11Sha256'])
    source = work / 'sorgenti'
    cli = work / 'CLI11-2.5.0'
    extract(source_archive, source, 'quickshell-' + specification['commit'])
    extract(cli_archive, cli, cli.name)
    patched_file = source / specification['patchedFile']
    if digest(patched_file) != specification['patchedFileSha256']:
        run('patch', '--batch', '--forward', '-p1', '-i', patch, '-d', source)
    if digest(patched_file) != specification['patchedFileSha256']:
        raise RuntimeError('La patch non ha prodotto i sorgenti previsti')
    prefix = work / 'local'
    run('cmake', '-S', cli, '-B', work / 'cli-build', '-GNinja',
        '-DCLI11_BUILD_TESTS=OFF', '-DCLI11_BUILD_EXAMPLES=OFF',
        '-DCMAKE_INSTALL_PREFIX=' + str(prefix))
    run('cmake', '--install', work / 'cli-build')
    run('cmake', '-S', source, '-B', work / 'build', '-GNinja',
        '-DCMAKE_BUILD_TYPE=RelWithDebInfo', '-DBUILD_TESTING=ON',
        '-DDISTRIBUTOR=Liquid DE private test', '-DCMAKE_PREFIX_PATH=' + str(prefix))
    run('cmake', '--build', work / 'build', '-j', args.jobs)
    output = ROOT / 'libexec/quickshell'
    output.mkdir(parents=True, exist_ok=True)
    temporary = output / 'qs.nuovo'
    shutil.copy2(work / 'build/src/quickshell', temporary)
    run('strip', '--strip-unneeded', temporary)
    qt = subprocess.check_output(['pkg-config', '--modversion', 'Qt6Core'], text=True).strip()
    metadata = {'schema': 1, 'version': specification['version'],
                'sourceCommit': specification['commit'], 'patchSha256': digest(patch),
                'qtVersion': qt, 'sha256': digest(temporary)}
    # Le licenze viaggiano con il binario, anche nella sola installazione locale.
    for src, name in [(source / 'LICENSE', 'LICENSE-Quickshell'),
                      (source / 'LICENSE-GPL', 'LICENSE-GPL'), (cli / 'LICENSE', 'LICENSE-CLI11')]:
        shutil.copy2(src, output / name)
    os.replace(temporary, output / 'qs')
    manifest = output / 'runtime.json.nuovo'
    manifest.write_text(json.dumps(metadata, indent=2) + '\n')
    os.replace(manifest, output / 'runtime.json')
    print('Runtime locale pronto:', output / 'qs', flush=True)


if __name__ == '__main__':
    main()
