#!/usr/bin/env python3
"""Informazioni statiche per le Impostazioni: una lettura, nessun polling."""
import json
import platform
from pathlib import Path
import sys


def read(path):
    try:
        return Path(path).read_text(errors='replace').strip()
    except OSError:
        return ''


def summary():
    cpu = next((line.split(':', 1)[1].strip() for line in read('/proc/cpuinfo').splitlines()
                if line.startswith('model name') and ':' in line), platform.machine())
    memory = next((int(line.split()[1])*1024 for line in read('/proc/meminfo').splitlines()
                   if line.startswith('MemTotal:')), 0)
    release = {}
    for line in read('/etc/os-release').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            release[key] = value.strip('"')
    vendor = read('/sys/class/dmi/id/sys_vendor')
    model = read('/sys/class/dmi/id/product_name')
    return {'hostname': read('/proc/sys/kernel/hostname'), 'model': ' '.join(filter(None, [vendor, model])),
            'cpu': cpu, 'memory': memory, 'os': release.get('PRETTY_NAME', 'Linux'),
            'kernel': platform.release()}


if __name__ == '__main__':
    # Le catture del banco grafico non devono contenere il nome del PC vero.
    data = {'hostname':'LIQUID-TEST', 'model':'Computer di prova', 'cpu':'Processore di prova',
            'memory':8*1024**3, 'os':'Linux di prova', 'kernel':'6.test'} if '--fixture' in sys.argv else summary()
    print(json.dumps(data))
