#!/usr/bin/env python3
"""Build optional COSMIC adapters without changing system packages or configs."""
import argparse
import collections
import json
import os
from pathlib import Path
import shutil
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parent.parent


def run(args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def original(path, name):
    return subprocess.check_output(['git', 'show', 'HEAD:' + name], cwd=path)


def dependencies(data):
    # Only the patched libcosmic workspace changes from git to local paths.
    return collections.Counter(
        (p['name'], p['version'], p.get('source'), p.get('checksum'))
        for p in tomllib.loads(data.decode())['package']
        if p.get('source') and not p['source'].startswith(
            'git+https://github.com/pop-os/libcosmic'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=Path(os.environ.get(
        'XDG_CACHE_HOME', str(Path.home()/'.cache')))/'liquid-de/apps-tiling')
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 32:
        parser.error('--jobs must be 1..32')
    cache = args.cache.resolve()
    versions = json.loads((ROOT/'patches/apps-tiling/versions.json').read_text())
    for name, info in versions.items():
        path = cache/'src'/name
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            run(['git', 'clone', '--filter=blob:none', '--no-checkout', info['url'], str(path)])
            run(['git', 'fetch', '--depth=1', 'origin', info['commit']], path)
            run(['git', 'checkout', '--detach', info['commit']], path)
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=path).decode().strip()
        if head != info['commit']:
            raise RuntimeError(f'{name}: cache uses another revision; choose another --cache')
    lib = cache/'src/libcosmic'
    run(['git', 'submodule', 'update', '--init', '--recursive', '--depth=1'], lib)
    patch = ROOT/'patches/apps-tiling/libcosmic-1.9-tiled-headers.patch'
    applied = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)],
                             cwd=lib, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if applied.returncode:
        run(['git', 'apply', '--check', str(patch)], lib)
        run(['git', 'apply', str(patch)], lib)
    if subprocess.check_output(['git', 'diff', '--binary'], cwd=lib) != patch.read_bytes():
        raise RuntimeError('libcosmic cache contains changes outside the pinned patch')
    output = ROOT/'libexec/tiling'
    output.mkdir(parents=True, exist_ok=True)
    for name in ('cosmic-term', 'cosmic-files'):
        path = cache/'src'/name
        modified = set(subprocess.check_output(['git', 'diff', '--name-only'], cwd=path)
                       .decode().splitlines())
        if modified - {'Cargo.toml', 'Cargo.lock'}:
            raise RuntimeError(f'{name}: cache contains other source changes')
        lock = original(path, 'Cargo.lock')
        names = {p['name'] for p in tomllib.loads(lock.decode())['package']
                 if p.get('source', '').startswith('git+https://github.com/pop-os/libcosmic')}
        members = {}
        for manifest in [lib/'Cargo.toml', *lib.glob('*/Cargo.toml'), *lib.glob('iced/**/Cargo.toml')]:
            package = tomllib.loads(manifest.read_text()).get('package', {}).get('name')
            if package in names:
                members[package] = os.path.relpath(manifest.parent, path)
        if names != members.keys():
            raise RuntimeError('Missing workspace packages: '+str(names-members.keys()))
        manifest = original(path, 'Cargo.toml').decode()
        manifest += '\n[patch."https://github.com/pop-os/libcosmic"]\n'
        manifest += ''.join(f'{name} = {{ path = {json.dumps(member)} }}\n'
                            for name, member in sorted(members.items()))
        (path/'Cargo.toml').write_text(manifest)
        (path/'Cargo.lock').write_bytes(lock)
        # Resolve local patches first; reject any change to other pinned dependencies.
        with open(os.devnull, 'w') as sink:
            subprocess.run(['cargo', 'metadata', '--format-version=1'], cwd=path,
                           stdout=sink, check=True)
        if dependencies(lock) != dependencies((path/'Cargo.lock').read_bytes()):
            raise RuntimeError(f'{name}: dependency versions changed; refusing the build')
        defaults = tomllib.loads(manifest)['features']['default']
        # Minerva has no cosmic-settings-daemon. Use libcosmic's file watcher
        # instead of retrying a missing DBus service; retain every other feature.
        features = ','.join(f for f in defaults if f != 'dbus-config')
        command = ['cargo', 'build', '--release', '--locked', '--no-default-features',
                   '--features', features, '--jobs', str(args.jobs),
                   '--target-dir', str(cache/'target')]
        if shutil.which('ionice'): command = ['ionice', '-c', '3', *command]
        if shutil.which('nice'): command = ['nice', '-n', '10', *command]
        run(command, path)
        temporary = output/(name+'.new')
        shutil.copy2(cache/'target/release'/name, temporary)
        temporary.replace(output/name)
    licenses = output/'licenses'
    licenses.mkdir(exist_ok=True)
    for name in versions:
        source = cache/'src'/name
        target = licenses/name
        target.mkdir(exist_ok=True)
        for license_file in source.glob('LICENSE*'):
            shutil.copy2(license_file, target/license_file.name)
    shutil.copy2(patch, licenses/patch.name)
    shutil.copy2(ROOT/'patches/apps-tiling/versions.json', output/'versions.json')
    print('App adapters ready. Test them before running minerva-installa-app-tiling.py.')


if __name__ == '__main__':
    main()
