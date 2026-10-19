#!/usr/bin/env python3
"""Move bundled asset paths under the installed root, preserving user data.

Linux: shares the resolved parent-directory flock used by SettingsApi.
"""
import errno
import fcntl
import json
import os
from pathlib import Path
import secrets
import stat
import sys
import time


def version(value):
    return (value.st_dev, value.st_ino, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns)


def migrate(logical, root):
    target = Path(logical).resolve(strict=True)
    directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    staging = None
    staging_fd = None
    committed = False
    try:
        deadline = time.monotonic() + 2
        while True:
            try:
                fcntl.flock(directory, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(errno.ETIMEDOUT, 'settings directory lock')
                time.sleep(0.02)

        # Read only after acquiring the shared writer lock. Resolve again so
        # a changed configuration link is never overwritten as a regular file.
        if Path(logical).resolve(strict=True) != target:
            raise OSError(errno.ESTALE, 'settings link changed')
        descriptor = os.open(target.name, os.O_RDONLY | os.O_CLOEXEC |
                             os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(descriptor, 'r', encoding='utf-8') as source:
            original = os.fstat(source.fileno())
            if not stat.S_ISREG(original.st_mode):
                raise OSError(errno.EINVAL, 'settings is not regular')
            data = json.load(source)
        if not isinstance(data, dict):
            raise ValueError('settings root must be an object')

        installed = str(Path(root).resolve()).rstrip('/')
        marker = '/minerva-shell/assets/'

        def rewrite(value):
            if isinstance(value, dict):
                return {key: rewrite(item) for key, item in value.items()}
            if isinstance(value, list):
                return [rewrite(item) for item in value]
            if (isinstance(value, str) and value.startswith('/') and marker in value
                    and not value.startswith(installed + '/')):
                candidate = installed + value[value.index(marker):]
                if os.path.exists(candidate):
                    return candidate
            return value

        updated = rewrite(data)
        if updated == data:
            return False

        # Private staging uses only descriptors of directories we own/opened;
        # never open the historical predictable settings.json.nuovo path.
        for _ in range(128):
            name = '.settings-migrate-' + secrets.token_hex(12)
            try:
                os.mkdir(name, 0o700, dir_fd=directory)
                staging = name
                break
            except FileExistsError:
                continue
        if staging is None:
            raise FileExistsError('settings staging unavailable')
        staging_fd = os.open(staging, os.O_RDONLY | os.O_DIRECTORY |
                             os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=directory)
        descriptor = os.open('settings.json', os.O_WRONLY | os.O_CREAT |
                             os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                             0o600, dir_fd=staging_fd)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as output:
            json.dump(updated, output, indent=2, ensure_ascii=False)
            output.write('\n')
            output.flush()
            os.fchmod(output.fileno(), stat.S_IMODE(original.st_mode) & 0o777)
            os.fsync(output.fileno())

        current = os.stat(target.name, dir_fd=directory, follow_symlinks=False)
        if (not stat.S_ISREG(current.st_mode) or version(current) != version(original)
                or Path(logical).resolve(strict=True) != target
                or os.stat(target.parent).st_ino != os.fstat(directory).st_ino
                or os.stat(target.parent).st_dev != os.fstat(directory).st_dev):
            raise OSError(errno.ESTALE, 'settings changed during migration')
        os.replace('settings.json', target.name,
                   src_dir_fd=staging_fd, dst_dir_fd=directory)
        committed = True
        os.fsync(directory)
        return True
    except OSError:
        if committed:
            print('minerva: impostazioni migrate; sincronizzazione directory non confermata.',
                  file=sys.stderr)
        raise
    finally:
        failed = sys.exc_info()[0] is not None
        cleanup_error = None
        try:
            if staging_fd is not None:
                try:
                    os.unlink('settings.json', dir_fd=staging_fd)
                except FileNotFoundError:
                    pass
                except OSError as error:
                    cleanup_error = error
                finally:
                    os.close(staging_fd)
            if staging is not None:
                try:
                    os.rmdir(staging, dir_fd=directory)
                except OSError as error:
                    cleanup_error = cleanup_error or error
        finally:
            # Always release flock, including when staging cleanup fails.
            os.close(directory)
        if cleanup_error is not None:
            if committed:
                print('minerva: impostazioni migrate; pulizia temporanei non completata.',
                      file=sys.stderr)
            else:
                print('minerva: pulizia temporanei impostazioni non completata.', file=sys.stderr)
            if not failed:
                raise cleanup_error


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Uso: minerva-migra-impostazioni.py FILE RADICE')
    try:
        if migrate(sys.argv[1], sys.argv[2]):
            print('  impostazioni: percorsi portati nella radice')
    except (OSError, ValueError, UnicodeError) as error:
        # Never print JSON, paths or the exception text from user content.
        print('minerva: migrazione impostazioni terminata con errore '
              f'(errno={getattr(error, "errno", None)}).',
              file=sys.stderr)
        raise SystemExit(1)
