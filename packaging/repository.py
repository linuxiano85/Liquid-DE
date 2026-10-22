#!/usr/bin/env python3
"""Assemble and sign local repositories; never upload or generate signing keys."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from native import target


def run(*args, **kwargs):
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def sign(path, key, inline=False):
    output = path.parent / ('InRelease' if inline else path.name + '.asc')
    run('gpg', '--batch', '--local-user', key, '--armor', '--output', output,
        '--clearsign' if inline else '--detach-sign', path)


def assemble(packages, destination, platform, key, sources):
    if not re.fullmatch(r'[A-F0-9]{40,64}', key):
        raise ValueError('Usare il fingerprint completo della chiave di firma')
    if destination.exists():
        raise ValueError('Il repository deve essere generato in una directory nuova')
    extension = '*.deb'
    files = sorted(packages.glob(extension))
    if len(files) != 3:
        raise ValueError('Servono esattamente i tre pacchetti della stessa build')
    if not sources.is_dir() or not any(sources.iterdir()):
        raise ValueError('Fornire anche i sorgenti corrispondenti alla build')
    destination.mkdir(parents=True)
    shutil.copytree(sources, destination / 'sources', symlinks=False)
    public = subprocess.check_output(['gpg', '--batch', '--armor', '--export', key])
    if not public:
        raise ValueError('Chiave di firma non disponibile')
    (destination / 'key.asc').write_bytes(public)
    if platform['family'] == 'deb':
        pool = destination / 'pool'
        pool.mkdir()
        for file in files:
            shutil.copy2(file, pool / file.name)
        index = destination / 'dists/stable/main/binary-amd64'
        index.mkdir(parents=True)
        data = subprocess.check_output(['apt-ftparchive', 'packages', 'pool'], cwd=destination)
        (index / 'Packages').write_bytes(data)
        (index / 'Packages.gz').write_bytes(gzip.compress(data, mtime=0))
        release = destination / 'dists/stable/Release'
        release.write_bytes(subprocess.check_output([
            'apt-ftparchive', '-o', 'APT::FTPArchive::Release::Codename=stable',
            '-o', 'APT::FTPArchive::Release::Suite=stable',
            '-o', 'APT::FTPArchive::Release::Architectures=amd64',
            '-o', 'APT::FTPArchive::Release::Components=main',
            'release', 'dists/stable'], cwd=destination))
        sign(release, key, inline=True)
        run('gpg', '--batch', '--local-user', key, '--armor', '--detach-sign',
            '--output', release.parent / 'Release.gpg', release)
    (destination / 'channel.json').write_text(json.dumps({
        'target': platform['repository'], 'fingerprint': key,
        'keySha256': hashlib.sha256(public).hexdigest(),
    }, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packages', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--key', required=True)
    args = parser.parse_args()
    assemble(args.packages.resolve(), args.output.resolve(), target(args.target), args.key,
             args.sources.resolve())
