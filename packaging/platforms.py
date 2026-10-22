"""Distribution policy shared by bootstrap, packaging and regression tests."""
import json
from pathlib import Path
import platform
import shlex

HERE = Path(__file__).resolve().parent


def os_release(path=Path('/etc/os-release')):
    data = {}
    for line in Path(path).read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        # Parse data, never source an arbitrary os-release as shell code.
        words = shlex.split(value, comments=True)
        data[key] = ' '.join(words)
    return data


def detect(data=None, architecture=None, immutable=None):
    data = os_release() if data is None else data
    architecture = architecture or platform.machine()
    if architecture not in ('x86_64', 'amd64'):
        raise ValueError('Prima release disponibile soltanto per x86_64.')
    if immutable is None:
        immutable = Path('/run/ostree-booted').exists() or Path('/ostree').exists()
    if immutable or data.get('VARIANT_ID', '').lower() in (
            'silverblue', 'kinoite', 'sericea', 'onyx', 'coreos', 'bootc'):
        raise ValueError('I sistemi immutabili non sono ancora supportati.')
    policy = json.loads((HERE / 'platforms.json').read_text())
    name = data.get('ID', '')
    base = policy['derivatives'].get(name, name)
    target = policy['targets'].get(base)
    if not target:
        raise ValueError('Distribuzione non certificata: ' + name +
                         '. ID_LIKE da solo non garantisce compatibilità.')
    version = data.get('VERSION_ID', '')
    if name == 'linuxmint':
        if data.get('UBUNTU_CODENAME') != 'noble':
            raise ValueError('Mint richiede la base Ubuntu noble; LMDE è esclusa.')
        version = version.split('.')[0]
    if version not in target['versions']:
        raise ValueError(f'Versione non supportata: {name} {version}.')
    # Mint consumes packages built on its Ubuntu ABI baseline.
    repository = 'ubuntu-24.04' if name == 'linuxmint' else f'{base}-{version}'
    return dict(id=name, version=version, family=target['family'],
                repository=repository, architecture='x86_64',
                certified=False)


def commands(target, action='install', include_login=False):
    if action not in ('install', 'update'):
        raise ValueError('Azione non valida')
    if target['family'] != 'deb':
        raise ValueError('Supporto nativo attualmente limitato a Debian/Ubuntu/Mint')
    packages = ['liquid-de'] + (['liquid-de-login'] if include_login else [])
    return [['apt-get', 'update'], ['apt-get', '--no-remove', 'install', *packages]]
