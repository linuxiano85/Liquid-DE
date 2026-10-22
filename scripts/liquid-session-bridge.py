#!/usr/bin/env python3
"""Render a session template with a literal, shell-quoted installed root."""
from pathlib import Path
import shlex
import sys


def render(template, root):
    if not Path(root).is_absolute() or any(c in root for c in '\n\r\0'):
        raise ValueError('La radice installata deve essere un percorso assoluto su una sola riga')
    marker = '"@MINERVA_DIR@/'
    rendered = []
    replacements = 0
    execs = 0
    for line in template.splitlines(keepends=True):
        if line.lstrip().startswith('exec '):
            execs += 1
        if not line.lstrip().startswith('#'):
            # Recovery also sets MINERVA_DENTRO before its indented exec.
            # Quote every path token, including assignment values.
            while marker in line:
                start = line.find(marker)
                end = line.find('"', start + len(marker))
                if end < 0:
                    raise ValueError('Percorso non terminato nel modello di sessione')
                suffix = line[start + len(marker):end]
                if not suffix.startswith('scripts/') or '..' in Path(suffix).parts:
                    raise ValueError('Destinazione del ponte non valida')
                line = line[:start] + shlex.quote(str(Path(root) / suffix)) + line[end + 1:]
                replacements += 1
        rendered.append(line)
    if execs != 1 or replacements < 1:
        raise ValueError('Il modello deve contenere un solo comando exec e i percorsi attesi')
    return ''.join(rendered)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Uso: liquid-session-bridge.py MODELLO RADICE_INSTALLATA')
    try:
        sys.stdout.write(render(Path(sys.argv[1]).read_text(), sys.argv[2]))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
