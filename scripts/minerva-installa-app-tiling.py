#!/usr/bin/env python3
"""Install reversible user launchers for the optional tiling app adapters."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APPS = {'cosmic-term': 'com.system76.CosmicTerm.desktop',
        'cosmic-files': 'com.system76.CosmicFiles.desktop',
        'shelly-ui': 'com.shellyorg.shelly.desktop'}
MARKER = 'X-MinervaTiledHeaders=true'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def save(receipt, data):
    receipt.parent.mkdir(parents=True, exist_ok=True)
    temporary = receipt.with_suffix('.new')
    temporary.write_text(json.dumps(data, indent=2)+'\n')
    temporary.replace(receipt)


def quote(value):
    # Desktop Entry Exec escaping (not shell quoting).
    return '"'+''.join('\\'+c if c in '\\"`$' else '%%' if c == '%' else c
                       for c in value)+'"'


def transform(text, app):
    lines = []
    for line in text.splitlines():
        if line.startswith('Exec='):
            # The pinned system launchers use a plain executable followed by
            # field codes/arguments; reject other syntax instead of guessing.
            command = line[5:]
            executable, _, arguments = command.partition(' ')
            if executable not in (app, '/usr/bin/'+app):
                raise RuntimeError('Unexpected system launcher command: '+executable)
            line = 'Exec='+quote(str(ROOT/'scripts/minerva-app-tiling'))+' '+app
            if arguments: line += ' '+arguments
        elif line.startswith('DBusActivatable='):
            line = 'DBusActivatable=false'
        lines.append(line)
        if line == '[Desktop Entry]': lines.append(MARKER)
    return '\n'.join(lines)+'\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--remove', action='store_true')
    args = parser.parse_args()
    data = Path(os.environ.get('XDG_DATA_HOME') or str(Path.home()/'.local/share'))
    state = Path(os.environ.get('XDG_STATE_HOME') or str(Path.home()/'.local/state'))/'liquid-de/app-tiling'
    apps = data/'applications'
    receipt = state/'installazione.json'
    previous = json.loads(receipt.read_text()) if receipt.exists() else {'apps': {}}
    entries = previous['apps']
    if args.remove:
        # Check the whole set before restoring anything.
        for app, info in entries.items():
            destination = apps/APPS[app]
            accepted = {info.get('installed_sha256'), info.get('original_sha256'),
                        info.get('interrupted_sha256')}
            if destination.exists() and digest(destination) not in accepted:
                raise RuntimeError('Launcher changed since installation: '+str(destination))
        for app, info in list(entries.items()):
            destination = apps/APPS[app]
            accepted = {info.get('installed_sha256'), info.get('original_sha256'),
                        info.get('interrupted_sha256')}
            if destination.exists() and digest(destination) not in accepted:
                raise RuntimeError('Launcher changed since installation: '+str(destination))
            print('Restore '+APPS[app])
            if args.dry_run: continue
            backup = info.get('backup')
            if backup:
                temp = destination.with_suffix('.desktop.new')
                shutil.copy2(backup, temp)
                temp.replace(destination)
            else:
                destination.unlink(missing_ok=True)
            del entries[app]
            save(receipt, previous)
    else:
        planned = {}
        for app, desktop in APPS.items():
            source = Path('/usr/share/applications')/desktop
            if not source.exists(): continue
            if app != 'shelly-ui' and not (ROOT/'libexec/tiling'/app).is_file():
                print('Skip '+app+': adapter not built')
                continue
            if app == 'shelly-ui' and not (ROOT/'lib/minerva/libminervatiledheaders.so').is_file():
                print('Skip Shelly: GTK adapter not built')
                continue
            text = transform(source.read_text(), app)
            destination = apps/desktop
            if destination.is_symlink():
                raise RuntimeError('Custom symlink launcher: '+str(destination))
            if destination.exists():
                if app not in entries and MARKER in destination.read_text():
                    raise RuntimeError('Untracked Minerva launcher: '+str(destination))
                if app in entries and digest(destination) not in {
                        entries[app].get('installed_sha256'), entries[app].get('original_sha256'),
                        entries[app].get('interrupted_sha256')}:
                    raise RuntimeError('Launcher changed since installation: '+str(destination))
            with tempfile.TemporaryDirectory(prefix='minerva-launcher-') as tempdir:
                validation = Path(tempdir)/desktop
                validation.write_text(text)
                subprocess.run(['desktop-file-validate', str(validation)], check=True)
            planned[app] = text
        for app, text in planned.items():
            destination = apps/APPS[app]
            print('Install '+APPS[app])
            if args.dry_run: continue
            apps.mkdir(parents=True, exist_ok=True)
            state.mkdir(parents=True, exist_ok=True)
            if app not in entries:
                backup = None
                original_hash = digest(destination)
                if destination.exists():
                    if MARKER in destination.read_text():
                        raise RuntimeError('Untracked Minerva launcher: '+str(destination))
                    backup = state/(APPS[app]+'.original')
                    shutil.copy2(destination, backup)
                entries[app] = {'backup': str(backup) if backup else None,
                                'original_sha256': original_hash}
            temp = destination.with_suffix('.desktop.new')
            temp.write_text(text)
            # Retain the currently active hash until activation finishes. An
            # interrupted upgrade can still have the previous adapter on disk.
            entries[app]['interrupted_sha256'] = digest(destination)
            entries[app]['installed_sha256'] = digest(temp)
            save(receipt, previous)
            temp.replace(destination)
            entries[app].pop('interrupted_sha256', None)
            save(receipt, previous)
    if not args.dry_run and receipt.exists():
        save(receipt, previous)
    if not args.dry_run and apps.exists():
        subprocess.run(['update-desktop-database', str(apps)], check=True)


if __name__ == '__main__':
    main()
