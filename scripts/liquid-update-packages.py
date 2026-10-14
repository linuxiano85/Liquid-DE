#!/usr/bin/env python3
"""Crea e confronta release a oggetti: nessuna installazione o pubblicazione.

L'inventario esplicito evita di includere file personali o asset locali privi
 di licenza. La radice deve essere una distribuzione già assemblata: i binari
si compilano sul sistema di build, non sul computer dell'utente.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import urllib.request
import urllib.parse
import io

REPOSITORY = 'linuxiano85/Liquid-DE'
MAX_FILE = 512 * 1024 * 1024
MAX_FILES = 20000
COMPONENTS = {'shell', 'native', 'daemon', 'compositor', 'fucina', 'integration'}


def canonical(data):
    return json.dumps(data, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(value):
    if not isinstance(value, str) or not value or '\\' in value or '\0' in value:
        raise ValueError('Percorso non valido')
    if any(part in ('', '.', '..') for part in value.split('/')):
        raise ValueError('Percorso non relativo o non normalizzato')
    return value


def component(path):
    if path.startswith('compositore/build-native/'):
        return 'compositor'
    if path.startswith('minervad/build/'):
        return 'daemon'
    if path.startswith(('minerva-shell/native/', 'lib/minerva/', 'libexec/tiling/')):
        return 'native'
    if path.startswith('minerva-shell/'):
        return 'shell'
    if path.startswith('fucina2/'):
        return 'fucina'
    if path.startswith(('scripts/', 'assets/', 'config/', 'desktop/')) or path == 'LICENSE':
        return 'integration'
    raise ValueError(f'File non appartenente alla distribuzione: {path}')


def atomic_write(destination, data):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix='.liquid-object-', dir=destination.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
        os.replace(name, destination)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def build(root, inventory, output, version, revision, platform, notes):
    root = Path(root).resolve()
    output = Path(output).resolve()
    if output == root or root in output.parents:
        raise ValueError('La destinazione deve stare fuori dalla distribuzione')
    if not re.fullmatch('[0-9a-f]{40}', revision) or not version or not platform:
        raise ValueError('Versione, revisione e piattaforma obbligatorie')
    if not isinstance(inventory, list) or len(inventory) > MAX_FILES or len(set(inventory)) != len(inventory):
        raise ValueError('Inventario non valido')
    files = {}
    objects = {}
    for relative in sorted(inventory):
        safe_path(relative)
        group = component(relative)
        path = root / relative
        # Neppure un genitore symlink può portare il lettore fuori radice.
        if any(parent.is_symlink() for parent in path.parents if parent != root and root in parent.parents):
            raise ValueError(f'Genitore simbolico: {relative}')
        info = path.lstat()
        entry = {'component': group}
        if stat.S_ISLNK(info.st_mode):
            target = os.readlink(path)
            if PurePosixPath(target).is_absolute() or '\0' in target or '\\' in target:
                raise ValueError('Destinazione simbolica non relativa')
            resolved = (path.parent / target).resolve()
            if resolved != root and root not in resolved.parents:
                raise ValueError('Destinazione simbolica esterna')
            entry.update({'kind': 'symlink', 'target': target})
        elif stat.S_ISREG(info.st_mode):
            if info.st_size > MAX_FILE:
                raise ValueError('File oltre il limite')
            # Un file per oggetto: un'icona non trascina con sé tutti gli sfondi.
            data = path.read_bytes()
            digest = sha(data)
            compressed = gzip.compress(data, mtime=0)
            entry.update({'kind': 'file', 'sha256': digest, 'size': len(data),
                          'mode': 0o755 if info.st_mode & 0o111 else 0o644})
            objects[digest] = {'bytes': len(compressed), 'sha256': sha(compressed)}
            destination = output / 'objects' / f'{digest}.gz'
            if not destination.exists() or sha(destination.read_bytes()) != sha(compressed):
                atomic_write(destination, compressed)
        else:
            raise ValueError(f'Tipo file non distribuibile: {relative}')
        files[relative] = entry
    groups = {name: sha(canonical({p: e for p, e in files.items() if e['component'] == name}))
              for name in sorted({e['component'] for e in files.values()})}
    manifest = {'schema': 1, 'repository': REPOSITORY, 'version': version,
                'revision': revision, 'platform': platform, 'notes': notes,
                'components': groups, 'files': files, 'objects': objects}
    validate(manifest)
    atomic_write(output / 'manifest.json', canonical(manifest) + b'\n')
    return manifest


def digest_ok(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def validate(manifest):
    if not isinstance(manifest, dict) or manifest.get('schema') != 1 or manifest.get('repository') != REPOSITORY:
        raise ValueError('Manifesto non valido')
    if not isinstance(manifest.get('revision'), str) or not re.fullmatch('[a-f0-9]{40}', manifest['revision']) or not isinstance(manifest.get('version'), str) or not manifest['version'] or not isinstance(manifest.get('notes'), str):
        raise ValueError('Identità release non valida')
    if not isinstance(manifest.get('platform'), str) or not manifest['platform']:
        raise ValueError('Piattaforma non valida')
    files = manifest.get('files')
    objects = manifest.get('objects')
    if not isinstance(files, dict) or len(files) > MAX_FILES or not isinstance(objects, dict):
        raise ValueError('Inventario non valido')
    for path, entry in files.items():
        safe_path(path)
        if not isinstance(entry, dict) or entry.get('component') != component(path):
            raise ValueError('Componente non valido')
        if entry.get('kind') == 'file':
            size = entry.get('size')
            digest = entry.get('sha256')
            if not digest_ok(digest) or type(size) is not int or not 0 <= size <= MAX_FILE or entry.get('mode') not in (0o644, 0o755):
                raise ValueError('Metadati file non validi')
            obj = objects.get(digest)
            if not isinstance(obj, dict) or not digest_ok(obj.get('sha256')) or type(obj.get('bytes')) is not int or not 0 < obj['bytes'] <= MAX_FILE + 1048576:
                raise ValueError('Metadati oggetto non validi')
        elif entry.get('kind') == 'symlink':
            target = entry.get('target')
            if not isinstance(target, str) or not target or '\0' in target or '\\' in target or PurePosixPath(target).is_absolute():
                raise ValueError('Symlink non valido')
            # Controllo lessicale, senza seguire il filesystem del client.
            depth = len(PurePosixPath(path).parent.parts)
            for part in target.split('/'):
                depth += -1 if part == '..' else 0 if part in ('', '.') else 1
                if depth < 0:
                    raise ValueError('Symlink esterno')
        else:
            raise ValueError('Tipo non valido')
    expected_objects = {e['sha256'] for e in files.values() if e['kind'] == 'file'}
    if set(objects) != expected_objects:
        raise ValueError('Oggetti estranei o mancanti')
    for path in files:
        if any(str(parent) in files for parent in PurePosixPath(path).parents):
            raise ValueError('Collisione file/directory')
    expected = {name: sha(canonical({p: e for p, e in files.items() if e['component'] == name}))
                for name in sorted({e['component'] for e in files.values()})}
    if manifest.get('components') != expected:
        raise ValueError('Impronte componenti non valide')
    return manifest


def plan(installed, latest, cache=None):
    validate(installed)
    validate(latest)
    if installed['platform'] != latest['platform']:
        raise ValueError('Release per piattaforma diversa')
    changes = []
    needed = set()
    available = {e['sha256']:p for p,e in installed['files'].items() if e['kind'] == 'file'}
    reuse = {}
    for path in sorted(set(installed['files']) | set(latest['files'])):
        old = installed['files'].get(path)
        new = latest['files'].get(path)
        if old == new:
            continue
        changes.append({'path': path, 'status': 'added' if old is None else 'removed' if new is None else 'modified',
                        'component': (new or old)['component'], 'old': old, 'new': new})
        # Modalità/nomi possono cambiare senza riscaricare lo stesso contenuto.
        if new and new['kind'] == 'file':
            digest = new['sha256']
            cached = Path(cache) / f'{digest}.gz' if cache else None
            valid_cache = cached and cached.is_file() and sha(cached.read_bytes()) == latest['objects'][digest]['sha256']
            if not valid_cache:
                if digest in available:
                    reuse[digest] = available[digest]
                else:
                    needed.add(digest)
    return {'changes': changes, 'components': sorted({c['component'] for c in changes}),
            'objects': sorted(needed), 'reuseInstalled': reuse, 'downloadBytes': sum(latest['objects'][h]['bytes'] for h in needed),
            'releaseBytes': sum(obj['bytes'] for obj in latest['objects'].values())}


def fetch(manifest, update_plan, base, cache, *, test=False):
    """Scarica solo oggetti del piano; niente estrazione o avvio di processi."""
    validate(manifest)
    url = urllib.parse.urlparse(base)
    production = url.scheme == 'https' and url.hostname == 'github.com'
    local = test and url.scheme == 'http' and url.hostname == '127.0.0.1'
    if not production and not local:
        raise ValueError('Origine non consentita')
    cache = Path(cache)
    transferred = 0
    for digest in update_plan['objects']:
        if not digest_ok(digest) or digest not in manifest['objects']:
            raise ValueError('Oggetto non presente nel manifesto')
        expected = manifest['objects'][digest]
        request = urllib.request.Request(base.rstrip('/') + '/' + digest + '.gz', headers={'Accept-Encoding':'identity'})
        with urllib.request.urlopen(request, timeout=30) as response:
            compressed = response.read(expected['bytes'] + 1)
        if len(compressed) != expected['bytes'] or sha(compressed) != expected['sha256']:
            raise ValueError('Oggetto danneggiato o incompleto')
        # Limite anche sull'espansione: l'hash compresso da solo non basta.
        sizes = {e['size'] for e in manifest['files'].values() if e.get('sha256') == digest}
        if len(sizes) != 1:
            raise ValueError('Dimensioni oggetto incoerenti')
        declared_size = next(iter(sizes))
        with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as archive:
            data = archive.read(declared_size + 1)
        if len(data) > MAX_FILE or sizes != {len(data)} or sha(data) != digest:
            raise ValueError('Contenuto oggetto non valido')
        atomic_write(cache / f'{digest}.gz', compressed)
        transferred += len(compressed)
    return transferred


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    creator = commands.add_parser('build')
    for name in ('root', 'inventory', 'output', 'version', 'revision', 'platform', 'notes'):
        creator.add_argument('--' + name, required=True)
    planner = commands.add_parser('plan')
    planner.add_argument('installed')
    planner.add_argument('latest')
    planner.add_argument('--cache')
    args = parser.parse_args()
    if args.command == 'build':
        result = build(args.root, json.loads(Path(args.inventory).read_text()), args.output,
                       args.version, args.revision, args.platform, Path(args.notes).read_text())
        print(json.dumps({'files':len(result['files']), 'components':result['components']}, indent=2))
    else:
        print(json.dumps(plan(json.loads(Path(args.installed).read_text()),
                              json.loads(Path(args.latest).read_text()), args.cache), indent=2))


if __name__ == '__main__':
    main()
