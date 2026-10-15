#!/usr/bin/env python3
"""Informazioni statiche per le Impostazioni: una lettura, nessun polling."""
import json
import platform
import os
import re
import shutil
import subprocess
from pathlib import Path
import sys


def read(path):
    try:
        return Path(path).read_text(errors='replace').strip()
    except OSError:
        return ''


def number(text):
    try:
        return max(0, int(text))
    except (ValueError, TypeError):
        return 0


def graphics(directory=Path('/sys/class/drm')):
    # Solo le schede DRM, non i connettori. Niente seriali, UUID o MAC.
    cards = sorted(p for p in directory.glob('card*') if re.fullmatch(r'card[0-9]+', p.name))
    cards.sort(key=lambda p: read(p/'device/boot_vga') != '1')
    for card in cards:
        device = card/'device'
        if not device.exists():
            continue
        name = ''
        address = device.resolve().name
        if re.fullmatch(r'[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]', address):
            try:
                result = subprocess.run(['lspci', '-D', '-s', address], capture_output=True,
                                        text=True, timeout=2, check=False)
                if result.returncode == 0:
                    name = result.stdout.strip().split(': ', 1)[-1][:256]
            except (OSError, subprocess.TimeoutExpired):
                pass
        if not name:
            vendor = read(device/'vendor').removeprefix('0x')
            identifier = read(device/'device').removeprefix('0x')
            name = f'GPU {vendor}:{identifier}' if vendor and identifier else ''
        return {'name': name, 'memory': number(read(device/'mem_info_vram_total')) or None}
    return {'name': '', 'memory': None}


def summary():
    cpu = next((line.split(':', 1)[1].strip() for line in read('/proc/cpuinfo').splitlines()
                if line.startswith('model name') and ':' in line), platform.machine())
    memory = next((number(line.split()[1])*1024 for line in read('/proc/meminfo').splitlines()
                   if line.startswith('MemTotal:')), 0)
    release = {}
    for line in read('/etc/os-release').splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            release[key] = value.strip('"')
    vendor = read('/sys/class/dmi/id/sys_vendor')
    model = read('/sys/class/dmi/id/product_name')
    try:
        disk = shutil.disk_usage('/')
        storage = {'total': disk.total, 'used': disk.used}
    except OSError:
        storage = {'total': 0, 'used': 0}
    return {'hostname': read('/proc/sys/kernel/hostname'), 'model': ' '.join(filter(None, [vendor, model])),
            'cpu': cpu, 'memory': memory, 'os': release.get('PRETTY_NAME', 'Linux'),
            'kernel': platform.release(), 'architecture': platform.machine(),
            'osVersion': release.get('VERSION_ID', ''), 'osBuild': release.get('BUILD_ID', ''),
            'cpuCount': os.cpu_count(), 'cpuFrequency': number(read('/sys/devices/system/cpu/cpu0/cpufreq/base_frequency')),
            'graphics': graphics(), 'storage': storage,
            'liquidVersion': read(Path(__file__).resolve().parent.parent/'minerva-shell/VERSION')}


if __name__ == '__main__':
    # Le catture del banco grafico non devono contenere il nome del PC vero.
    data = {'hostname':'LIQUID-TEST', 'model':'Computer di prova', 'cpu':'Processore di prova',
            'memory':8*1024**3, 'os':'Linux di prova', 'kernel':'6.test',
            'architecture':'x86_64', 'osVersion':'2026.10', 'osBuild':'test-build',
            'cpuCount':8, 'cpuFrequency':3500000, 'graphics':{'name':'Scheda grafica di prova', 'memory':4*1024**3},
            'storage':{'total':256*1024**3,'used':64*1024**3}, 'liquidVersion':'1.test'} if '--fixture' in sys.argv else summary()
    print(json.dumps(data))
