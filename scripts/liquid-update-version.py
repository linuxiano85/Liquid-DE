#!/usr/bin/env python3
"""Registra cosa è stato copiato, senza cambiare il checkout o creare tag."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def write_manifest(source, destination):
    source = Path(source).resolve()
    destination = Path(destination)
    def git(*arguments):
        result = subprocess.run(['git', '-C', str(source), *arguments],
                                capture_output=True, text=True, check=False)
        return result.stdout.strip() if result.returncode == 0 else ''
    checkout = git('rev-parse', '--show-toplevel')
    revision = git('rev-parse', 'HEAD') if checkout == str(source) else ''
    if not re.fullmatch(r'[a-f0-9]{40}', revision):
        revision = ''
    version_path = source / 'minerva-shell/VERSION'
    data = {
        'schema': 1, 'repository': 'linuxiano85/Liquid-DE',
        'revision': revision, 'dirty': bool(git('status', '--porcelain')),
        'version': version_path.read_text().strip() if version_path.exists() else '',
        'installedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.liquid-build-', dir=destination.parent)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(data, output, indent=2)
            output.write('\n')
        os.chmod(temporary, 0o644)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return data


if __name__ == '__main__':
    write_manifest(sys.argv[1], sys.argv[2])
