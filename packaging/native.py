#!/usr/bin/env python3
"""Build, stage and package Liquid without installing it into the build host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

from platforms import detect
from runtime import digest, environment

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
PREFIX = Path('usr/lib/liquid-de')
VERSION = (SOURCE / 'minerva-shell/VERSION').read_text().strip()
DEPS = json.loads((HERE / 'dependencies.json').read_text())
REWRITES = {
    '/usr/local/bin/': '/usr/bin/',
    '/usr/local/share/minerva': '/usr/lib/liquid-de',
    '/usr/local/lib/minerva': '/usr/lib/liquid-de/login',
}
REQUIRED = (
    'compositore/build-native/minerva-wayland',
    'compositore/build-native/minerva-cattura',
    'compositore/build-native/minerva-pty',
    'compositore/build-native/minerva-pam',
    'permessi/build/minerva-polkit',
    'minervad/build/minervad', 'minervad/build/minerva-terminale-motore',
    'posta/daemon/build/cli/bundle/bin/liquid_maild',
    'posta/daemon/build/cli/bundle/lib/libsqlite3.so',
    'minerva-shell/native/Minerva/WindowIdentity/libminervawindowidentity.so',
    'minerva-shell/native/Liquid/Media/libliquidmedia.so',
    'lib/minerva/libminervatiledheaders.so', 'libexec/quickshell/qs',
)
SOURCE_DIRECTORIES = ('scripts', 'config', 'desktop', 'assets', 'minerva-shell',
                      'minervad', 'posta', 'compositore', 'permessi', 'native',
                      'patches', 'packaging')
SOURCE_IGNORE = shutil.ignore_patterns('.git', '.agents', '.codex', '.aws', 'build',
    'build-native', '__pycache__', '.dart_tool', 'node_modules', 'prove',
    'cli-precedente-*', '*.so', '*.so.*', 'qs', 'runtime.json', '*.jpg')


def source_fingerprint(source):
    """Hash precisely the inputs admitted by prepare, including executable bits."""
    result = hashlib.sha256()
    files = [source / 'LICENSE']
    for directory in SOURCE_DIRECTORIES:
        for base, directories, names in os.walk(source / directory, followlinks=False):
            base = Path(base)
            ignored = SOURCE_IGNORE(str(base), [*directories, *names])
            files.extend(base / name for name in directories if (base / name).is_symlink() and name not in ignored)
            directories[:] = sorted(name for name in directories if name not in ignored and not (base / name).is_symlink())
            files.extend(base / name for name in names if name not in ignored)
    for path in sorted(files):
        result.update(str(path.relative_to(source)).encode() + b'\0')
        if path.is_symlink():
            result.update(b'link\0' + os.readlink(path).encode() + b'\0')
        else:
            result.update(str(bool(path.stat().st_mode & 0o111)).encode() + b'\0')
            result.update(bytes.fromhex(digest(path)))
    return result.hexdigest()


def target(value):
    name, _, version = value.partition('-')
    result = detect({'ID': name, 'VERSION_ID': version}, 'x86_64', False)
    if result['family'] != 'deb':
        raise ValueError('Packaging nativo attualmente disponibile solo per Debian/Ubuntu/Mint')
    return result


def run(*args, **kwargs):
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def write(path, text, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755 if executable else 0o644)


def rewrite(path):
    try:
        value = path.read_text()
    except (UnicodeError, OSError):
        return
    for before, after in REWRITES.items():
        value = value.replace(before, after)
    path.write_text(value)


def prepare(source, destination):
    if destination.exists():
        raise ValueError('La directory di build deve essere nuova')
    if destination.is_relative_to(source):
        raise ValueError('La copia di build deve stare fuori dai sorgenti')
    # Never publish the developer's prebuilt binaries, private assets or caches.
    destination.mkdir(parents=True)
    for directory in SOURCE_DIRECTORIES:
        shutil.copytree(source / directory, destination / directory, ignore=SOURCE_IGNORE, symlinks=True)
    shutil.copy2(source / 'LICENSE', destination / 'LICENSE')
    for folder in ('scripts', 'config', 'minerva-shell', 'minervad'):
        for path in (destination / folder).rglob('*'):
            if path.is_file() and not path.is_symlink():
                rewrite(path)
    write(destination / 'package-source.json', '{"schema":1,"nativePaths":true}\n')
    # Source verification expects the declaration of the private fork and the
    # complete inputs; it never requires products copied from another machine.


def build(source, runtime, jobs):
    if not (source / 'package-source.json').is_file():
        raise ValueError('Eseguire prima prepare: la build nativa usa una copia separata dei sorgenti')
    env = environment(runtime)
    env['MINERVA_MARCH'] = 'x86-64'
    env['LIQUID_PREFISSO'] = str(source / '.package-prefix')
    env['CMAKE_BUILD_PARALLEL_LEVEL'] = str(jobs)
    env['LIQUID_PACKAGE_BUILD'] = '1'
    run('sh', source / 'compositore/costruisci.sh', '--build-only', env=env)
    for script in ('costruisci-window-identity.sh', 'costruisci-mpv.sh', 'costruisci-tiled-headers.sh'):
        run('sh', source / 'scripts' / script, env=env)
    run('sh', source / 'permessi/costruisci.sh', env=env)
    run('python3', source / 'scripts/costruisci-quickshell.py', '--jobs', jobs,
        '--work-dir', source / '.quickshell-build', env=env)
    run('sh', source / 'scripts/minerva-compila', env=env)


def is_elf(path):
    if not path.is_file() or path.is_symlink():
        return False
    with path.open('rb') as stream:
        return stream.read(4) == b'\x7fELF'


def elf_files(root):
    return sorted(path for path in root.rglob('*') if is_elf(path))


def copy_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    destination.chmod(0o755 if source.stat().st_mode & 0o111 else 0o644)


def stage(source, runtime, destination, platform):
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('DESTDIR deve essere vuoto')
    for relative in REQUIRED:
        path = source / relative
        if not is_elf(path):
            raise ValueError('Binario compilato mancante: ' + relative)
    metadata = json.loads((runtime / 'runtime.json').read_text())
    source_manifest = source / 'packaging/runtime-sources.json'
    pinned_runtime = json.loads(source_manifest.read_text())
    if (metadata.get('sourceManifestSha256') != digest(source_manifest)
            or metadata.get('qtVersion') != pinned_runtime['qtVersion']):
        raise ValueError('Runtime non corrispondente ai sorgenti registrati')
    qs = json.loads((source / 'libexec/quickshell/runtime.json').read_text())
    if metadata.get('qtVersion') != qs.get('qtVersion') or qs.get('sha256') != digest(source / 'libexec/quickshell/qs'):
        raise ValueError('Quickshell e runtime devono essere compilati con la stessa Qt')
    root = destination / PREFIX
    for folder in ('scripts', 'config', 'assets', 'desktop', 'minerva-shell', 'packaging'):
        shutil.copytree(source / folder, root / folder, symlinks=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '*.jpg', 'proposte.*'))
    for relative in REQUIRED:
        copy_file(source / relative, root / relative)
    bundle = Path('posta/daemon/build/cli/bundle')
    shutil.copytree(source / bundle, root / bundle, dirs_exist_ok=True, symlinks=True)
    shutil.copytree(source / 'libexec/quickshell', root / 'libexec/quickshell',
                    dirs_exist_ok=True, symlinks=True)
    shutil.copytree(runtime, root / 'runtime', symlinks=True)
    # Headers, CMake metadata and SDK executables are build inputs, not runtime.
    for relative in ('include', 'lib/cmake', 'lib/pkgconfig', 'share/pkgconfig', 'bin'):
        path = root / 'runtime' / relative
        if path.is_dir():
            shutil.rmtree(path)
    for path in list((root / 'runtime').rglob('*.a')):
        path.unlink()
    write(root / 'package-install.json', json.dumps({
        'schema': 1, 'version': VERSION, 'family': platform['family'],
        'target': platform['repository'], 'architecture': 'x86_64',
    }, indent=2) + '\n')
    copy_file(source / 'LICENSE', destination / 'usr/share/licenses/liquid-de/LICENSE')
    copy_file(source / 'compositore/subprojects/wlroots/LICENSE',
              destination / 'usr/share/licenses/liquid-de/wlroots-LICENSE')
    for path in root.rglob('*'):
        if path.is_file() and not path.is_symlink() and not is_elf(path):
            rewrite(path)
    # Every qs caller uses our verified launcher, never a global qs replacement.
    (root / 'scripts/qs').symlink_to('minerva-quickshell')
    for name in ('minerva-wayland', 'minerva-cattura', 'minerva-pty', 'minerva-pam'):
        binary = root / 'bin' / name
        copy_file(root / 'compositore/build-native' / name, binary)
    copy_file(root / 'permessi/build/minerva-polkit', root / 'bin/minerva-polkit')
    for file in (root / 'desktop').glob('*.desktop'):
        value = re.sub(r'(?m)^Exec=(minerva-[a-z0-9-]+)(?=\s|$)', r'Exec=/usr/bin/\1', file.read_text())
        value = value.replace('Exec=/usr/bin/minerva-polkit', 'Exec=/usr/lib/liquid-de/bin/minerva-polkit')
        file.write_text(value)
        copy_file(file, destination / 'usr/share/applications' / file.name)
    for file in (root / 'assets/icons').glob('*.svg'):
        copy_file(file, destination / 'usr/share/icons/hicolor/scalable/apps' / file.name)
    for file in (root / 'config/xdg-desktop-portal').glob('*'):
        directory = 'portals' if file.suffix == '.portal' else ''
        copy_file(file, destination / 'usr/share/xdg-desktop-portal' / directory / file.name)
    for file in (root / 'config/polkit').glob('*.policy'):
        copy_file(file, destination / 'usr/share/polkit-1/actions' / file.name)
    copy_file(root / 'config/pam/liquid-de', destination / 'etc/pam.d/liquid-de')
    copy_file(root / 'config/udev/70-liquid-de-pad-led.rules',
              destination / 'usr/lib/udev/rules.d/70-liquid-de-pad-led.rules')
    apps = [line.strip() for line in (source / 'config/liquid-install-apps.list').read_text().splitlines()
            if line.strip() and not line.startswith('#')]
    for name in apps + ['minerva-blocca', 'minerva-filemanager1', 'minerva-portale', 'minerva-salvaschermo']:
        write(destination / 'usr/bin' / name,
              '#!/bin/sh\nexport PATH="/usr/lib/liquid-de/scripts:/usr/lib/liquid-de/bin:$PATH"\n'
              'export MINERVA_ROOT=/usr/lib/liquid-de\n'
              'exec /usr/lib/liquid-de/scripts/' + name + ' "$@"\n', True)
    for name, original in [('liquid-de-utente', 'minerva-utente'), ('liquid-de-radice', 'minerva-radice')]:
        copy_file(root / 'scripts' / original, destination / 'usr/bin' / name)
    (destination / 'usr/bin/minerva-pam').symlink_to('../lib/liquid-de/bin/minerva-pam')
    (destination / 'usr/bin/minerva-greetd').symlink_to('../lib/liquid-de/scripts/liquid-login-manager')
    # The historical source-copy helper must never rewrite package-owned files.
    (root / 'scripts/minerva-greetd').unlink()
    (root / 'scripts/minerva-greetd').symlink_to('liquid-login-manager')
    for name, output in [('greetd.toml', 'etc/greetd/liquid-de.toml'),
                         ('sysusers.conf', 'usr/lib/sysusers.d/liquid-de-login.conf'),
                         ('tmpfiles.conf', 'usr/lib/tmpfiles.d/liquid-de-login.conf')]:
        copy_file(source / 'packaging/login' / name, destination / output)
    copy_file(root / 'config/mimeapps/liquidde-mimeapps.list',
              destination / 'usr/share/applications/liquidde-mimeapps.list')
    write(root / 'liquid-build.json', json.dumps({
        'repository': 'linuxiano85/Liquid-DE', 'version': VERSION,
        'revision': os.environ.get('GITHUB_SHA', ''), 'dirty': False,
    }, indent=2) + '\n')
    # The greeter's session helper is installed by the optional login package.
    copy_file(root / 'scripts/minerva-avvia-sessione', root / 'login/minerva-avvia-sessione')
    for name, script in [('liquid-de-sessione', 'minerva-session-wayland'),
                         ('liquid-de-recupero', 'minerva-session-recupero')]:
        value = (source / 'scripts' / script).read_text().replace('@MINERVA_DIR@', '/usr/lib/liquid-de')
        write(destination / 'usr/bin' / name, value, True)
        recovery = name.endswith('recupero')
        write(destination / 'usr/share/wayland-sessions' / ('liquid-de-recupero.desktop' if recovery else 'liquid-de.desktop'),
              '[Desktop Entry]\nName=Liquid DE' + (' (recupero)' if recovery else '') +
              '\nComment=Liquid Wayland session\nExec=/usr/bin/' + name +
              '\nTryExec=/usr/bin/' + name + '\nType=Application\nDesktopNames=LiquidDE;Minerva;\n')
    for name, bus in [('minerva-filemanager1', 'org.freedesktop.FileManager1'),
                      ('minerva-portale', 'org.freedesktop.impl.portal.desktop.liquidde'),
                      ('minerva-salvaschermo', 'org.freedesktop.ScreenSaver')]:
        write(destination / 'usr/share/dbus-1/services' / (bus + '.service'),
              '[D-BUS Service]\nName=' + bus + '\nExec=/usr/bin/' + name + '\n')
    write(root / 'libexec/quickshell/qt.conf',
          '[Paths]\nPrefix=../../runtime\nLibraries=lib\nPlugins=plugins\nQmlImports=qml\nTranslations=translations\n')
    for path in elf_files(destination):
        # DT_RPATH also resolves indirect/dlopen dependencies. No LD_LIBRARY_PATH
        # is exported by the desktop, so external applications keep system Qt.
        run('patchelf', '--force-rpath', '--set-rpath',
            '$ORIGIN:$ORIGIN/../lib:/usr/lib/liquid-de/runtime/lib', path)
    # Patching changes the binary hash; publish it only after final relocation.
    qs['sha256'] = digest(root / 'libexec/quickshell/qs')
    write(root / 'libexec/quickshell/runtime.json', json.dumps(qs, indent=2) + '\n')
    for path in destination.rglob('*'):
        if not path.is_symlink():
            path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
    audit(destination)


def audit(destination):
    root = destination / PREFIX
    for path in destination.rglob('*'):
        if path.is_symlink():
            resolved = (path.parent / os.readlink(path)).resolve()
            if not resolved.is_relative_to(destination.resolve()) or not resolved.exists():
                raise ValueError('Symlink fuori dal pacchetto o interrotto: ' + str(path))
        elif path.is_file() and path.stat().st_mode & 0o022:
            raise ValueError('File di sistema scrivibile da gruppo/altri: ' + str(path))
    if (destination / 'usr/local').exists():
        raise ValueError('I pacchetti non devono scrivere in /usr/local')
    if not (root / 'package-install.json').is_file():
        raise ValueError('Manifesto di installazione mancante')
    env = dict(os.environ)
    env['LC_ALL'] = 'C'
    env['LD_LIBRARY_PATH'] = ':'.join([str(root / 'runtime/lib'),
        str(root / 'posta/daemon/build/cli/bundle/lib')])
    for binary in elf_files(destination):
        header = subprocess.check_output(['readelf', '-h', str(binary)], text=True, env=env)
        if 'Advanced Micro Devices X86-64' not in header:
            raise ValueError('Architettura ELF diversa da x86_64: ' + str(binary))
        result = subprocess.run(['ldd', str(binary)], env=env,
                                capture_output=True, text=True, timeout=30)
        if ('not found' in result.stdout or re.search(r'lib(wlroots|scenefx)', result.stdout)):
            raise ValueError('Dipendenza ELF mancante o esterna vietata: ' + str(binary) + '\n' + result.stdout)
        if result.returncode and 'not a dynamic executable' not in (result.stdout + result.stderr):
            raise ValueError('Impossibile controllare le dipendenze ELF: ' + str(binary))


def split(stage_dir, output):
    if output.exists() and any(output.iterdir()):
        raise ValueError('La directory dei pacchetti deve essere vuota')
    desktop = output / 'liquid-de'
    shutil.copytree(stage_dir, desktop, symlinks=True)
    runtime = output / 'liquid-de-runtime' / PREFIX
    runtime.mkdir(parents=True)
    shutil.move(desktop / PREFIX / 'runtime', runtime / 'runtime')
    login = output / 'liquid-de-login'
    for relative in ('usr/bin/minerva-greetd', 'etc/greetd/liquid-de.toml',
                     'usr/lib/sysusers.d/liquid-de-login.conf', 'usr/lib/tmpfiles.d/liquid-de-login.conf',
                     str(PREFIX / 'scripts/minerva-greetd'),
                     str(PREFIX / 'login/minerva-avvia-sessione'),
                     str(PREFIX / 'scripts/liquid-login-manager'), str(PREFIX / 'scripts/liquid-login-session')):
        original = desktop / relative
        final = login / relative
        final.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(original, final)
    return [desktop, output / 'liquid-de-runtime', login]


def deb_dependencies(stage_dir, payload, package, version, work):
    work.mkdir(parents=True, exist_ok=True)
    shlibs = []
    for binary in elf_files(stage_dir):
        text = subprocess.check_output(['objdump', '-p', str(binary)], text=True)
        match = re.search(r'\bSONAME\s+(\S+)\.so\.(\S+)', text)
        if match:
            owner = 'liquid-de-runtime' if '/runtime/' in str(binary) else 'liquid-de'
            shlibs.append(f'{match[1]} {match[2]} {owner} (= {version})')
    local = work / 'shlibs.local'
    local.write_text('\n'.join(sorted(set(shlibs))) + ('\n' if shlibs else ''))
    write(work / 'debian/control', 'Source: liquid-de\nSection: x11\nPriority: optional\n'
          'Maintainer: Liquid DE contributors <noreply@liquid-de.invalid>\nStandards-Version: 4.7.0\n\n'
          'Package: liquid-de\nArchitecture: amd64\nDescription: Liquid desktop\n')
    binaries = elf_files(payload)
    if not binaries:
        return []
    library_dirs = sorted({str(path.parent) for path in elf_files(stage_dir)})
    command = ['dpkg-shlibdeps', '-O', '-L' + str(local), '-x' + package]
    command += ['-l' + path for path in library_dirs]
    command += ['-e' + str(path) for path in binaries]
    result = subprocess.check_output(command, cwd=work, text=True)
    value = next((line.partition('=')[2] for line in result.splitlines() if line.startswith('shlibs:Depends=')), '')
    return value.split(', ') if value else []


def package(stage_dir, output, platform, version):
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*(?:[+~][A-Za-z0-9.]+)?', version):
        raise ValueError('Versione pacchetto non valida')
    audit(stage_dir)
    with tempfile.TemporaryDirectory(prefix='liquid-package-') as temp:
        temp = Path(temp)
        payloads = split(stage_dir, temp / 'payloads')
        output.mkdir(parents=True, exist_ok=True)
        family = platform['family']
        for payload in payloads:
            name = payload.name
            # dpkg-shlibdeps identifies $ORIGIN relative to the nearest DEBIAN
            # directory, which must exist before analyzing private libraries.
            (payload / 'DEBIAN').mkdir(exist_ok=True)
            kind = 'runtime' if name.endswith('-runtime') else 'login' if name.endswith('-login') else 'desktop'
            dependencies = list(DEPS[family][kind])
            if name in ('liquid-de', 'liquid-de-login'):
                dependencies.append(('liquid-de-runtime' if name == 'liquid-de' else 'liquid-de') + f' (= {version}-1)')
            if family == 'deb':
                dependencies += deb_dependencies(stage_dir, payload, name, version + '-1', temp / name)
                write(payload / 'DEBIAN/control', f'Package: {name}\nVersion: {version}-1\n'
                      'Architecture: amd64\nSection: x11\nPriority: optional\n'
                      'Maintainer: Liquid DE contributors <noreply@liquid-de.invalid>\n'
                      'X-Liquid-Target: ' + platform['repository'] + '\n'
                      'Depends: ' + ', '.join(sorted(set(dependencies))) + '\n'
                      'Description: Liquid DE ' + ('private runtime' if name.endswith('-runtime') else 'Wayland desktop') + '\n')
                configs = [f'/{p.relative_to(payload)}' for p in (payload / 'etc').rglob('*') if p.is_file()]
                if configs:
                    write(payload / 'DEBIAN/conffiles', '\n'.join(configs) + '\n')
                if name == 'liquid-de-login':
                    write(payload / 'DEBIAN/prerm', '#!/bin/sh\nset -e\n'
                          'if [ "$1" = remove ]; then\n'
                          '    /usr/lib/liquid-de/scripts/liquid-login-manager rimuovi\n'
                          'fi\n', True)
                run('dpkg-deb', '--root-owner-group', '--build', payload, output / f'{name}_{version}-1_amd64.deb')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'build', 'stage', 'package', 'audit', 'build-dependencies'))
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--target', required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--runtime-prefix', type=Path)
    parser.add_argument('--destdir', type=Path)
    parser.add_argument('--version', help='Versione Debian; di serie include la base ABI')
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    for option, actions in [('output', ('prepare', 'package')),
                            ('runtime_prefix', ('build', 'stage')),
                            ('destdir', ('stage', 'package', 'audit'))]:
        if args.action in actions and getattr(args, option) is None:
            parser.error('--' + option.replace('_', '-') + ' richiesto per ' + args.action)
    if not 1 <= args.jobs <= 32:
        parser.error('--jobs deve essere compreso tra 1 e 32')
    platform = target(args.target)
    source = args.source.resolve()
    if args.action == 'build-dependencies':
        print(' '.join(DEPS[platform['family']]['build']))
    elif args.action == 'prepare':
        prepare(source, args.output.resolve())
    elif args.action == 'build':
        build(source, args.runtime_prefix.resolve(), args.jobs)
    elif args.action == 'stage':
        stage(source, args.runtime_prefix.resolve(), args.destdir.resolve(), platform)
    elif args.action == 'audit':
        audit(args.destdir.resolve())
    elif args.action == 'package':
        version = args.version or VERSION + '+' + platform['repository'].replace('-', '')
        package(args.destdir.resolve(), args.output.resolve(), platform, version)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('Packaging Liquid: ' + str(error), file=sys.stderr)
        sys.exit(1)
