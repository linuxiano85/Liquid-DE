#!/usr/bin/env python3
"""Verifica WebEngine con un host Qt corretto, senza aprire finestre personali."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    flags = subprocess.run(['pkg-config', '--cflags', '--libs',
                            'Qt6WebEngineQuick', 'Qt6Qml', 'Qt6Quick'],
                           capture_output=True, text=True)
    if flags.returncode:
        print('SKIP: Qt WebEngine Quick non installato (dipendenza del solo banco)')
        return 77
    with tempfile.TemporaryDirectory(prefix='liquid-webengine-') as directory:
        binary = str(Path(directory)/'host')
        subprocess.run(['c++', '-std=c++17', '-fPIC',
                        str(ROOT/'tests/fixtures/qt-webengine/main.cpp'),
                        *shlex.split(flags.stdout), '-o', binary], check=True)
        result = subprocess.run([binary, str(ROOT/'tests/fixtures/qt-webengine/view.qml')],
                                env=dict(os.environ, QT_QPA_PLATFORM='offscreen',
                                         QT_QUICK_BACKEND='software',
                                         QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu'),
                                capture_output=True, text=True, timeout=20)
        if result.returncode or 'LIQUID_WEBENGINE_LOADED=1' not in result.stdout:
            print(result.stdout)
            print(result.stderr)
            raise RuntimeError('Pagina Qt WebEngine non caricata')
        print('PASS: host Qt inizializzato, pagina locale caricata, nessun crash')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
