#!/usr/bin/env python3
"""Privilege boundary for greeter data; installed alongside minerva-greetd.

Root prepares only top-level directory descriptors. Session files are opened
after permanently dropping to the caller; runtime data is written as greeter.
The root-only configuration snapshot is separate from mutable runtime data.
"""
import base64
import json
import os
import pwd
import re
import select
import secrets
import signal
import stat
import sys
import time

MAX_SETTINGS = 512 * 1024
MAX_IMAGE = 32 * 1024 * 1024
MAX_REPLY = 48 * 1024 * 1024
DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
REGULAR = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC


def trusted_directory(path):
    fd = os.open(path, DIRECTORY)
    info = os.fstat(fd)
    if info.st_uid != 0 or info.st_mode & 0o022:
        os.close(fd)
        raise ValueError("Directory amministrativa non protetta")
    return fd


def prepare_directory(path, user, mode):
    parent, name = os.path.split(os.path.abspath(path))
    with_fd = trusted_directory(parent)
    try:
        try:
            os.mkdir(name, 0o700, dir_fd=with_fd)
        except FileExistsError:
            pass
        fd = os.open(name, DIRECTORY, dir_fd=with_fd)
    finally:
        os.close(with_fd)
    try:
        info = os.fstat(fd)
        if info.st_uid not in (0, user.pw_uid):
            raise ValueError("Proprietario della directory del greeter non valido")
        # Never recurse into names controlled by greeter, or resolve chown by path.
        os.fchown(fd, user.pw_uid, user.pw_gid)
        os.fchmod(fd, mode)
    except BaseException:
        os.close(fd)
        raise
    return fd


def runtime_directory(path, user):
    parent, name = os.path.split(os.path.abspath(path))
    parent_fd = trusted_directory(parent)
    try:
        fd = os.open(name, DIRECTORY, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)
    info = os.fstat(fd)
    if info.st_uid != user.pw_uid or stat.S_IMODE(info.st_mode) != 0o700:
        os.close(fd)
        raise ValueError("Directory di stato del greeter non valida")
    return fd


def drop_privileges(user):
    if user.pw_uid == 0:
        raise ValueError("Non si possono importare dati come root")
    os.initgroups(user.pw_name, user.pw_gid)
    os.setresgid(user.pw_gid, user.pw_gid, user.pw_gid)
    os.setresuid(user.pw_uid, user.pw_uid, user.pw_uid)
    if os.getresuid() != (user.pw_uid,) * 3 or os.getresgid() != (user.pw_gid,) * 3:
        raise PermissionError("Riduzione dei privilegi non riuscita")


def as_user(user, action, timeout=15):
    """Bounded JSON IPC; no pickle or code deserialization in the root parent."""
    read_fd, write_fd = os.pipe2(os.O_CLOEXEC)
    pid = os.fork()
    if pid == 0:
        os.close(read_fd)
        try:
            # Nothing of root's survives the drop but the reply pipe and
            # stderr: stdout may be the root-only staging file of minerva-greetd.
            null = os.open(os.devnull, os.O_RDWR)
            os.dup2(null, 0)
            os.dup2(null, 1)
            if null > 2:
                os.close(null)
            os.closerange(3, write_fd)
            os.closerange(write_fd + 1, os.sysconf("SC_OPEN_MAX"))
            drop_privileges(user)
            result = {"ok": True, "value": action()}
        except BaseException as error:
            result = {"ok": False, "error": str(error)}
        try:
            data = memoryview(json.dumps(result, ensure_ascii=True, allow_nan=False).encode())
            if len(data) > MAX_REPLY:
                raise ValueError("Risposta troppo grande")
            while data:
                count = os.write(write_fd, data)
                data = data[count:]
        except BaseException:
            os._exit(1)
        os.close(write_fd)
        os._exit(0)
    os.close(write_fd)
    chunks = bytearray()
    deadline = time.monotonic() + timeout
    reaped = False
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([read_fd], [], [], remaining)[0]:
                raise TimeoutError("Tempo massimo per importare i dati del greeter")
            block = os.read(read_fd, 65536)
            if not block:
                break
            chunks.extend(block)
            if len(chunks) > MAX_REPLY:
                raise ValueError("Risposta troppo grande")
        # EOF is not a guarantee that the child exited: enforce the same deadline.
        while True:
            found, status = os.waitpid(pid, os.WNOHANG)
            if found:
                reaped = True
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Processo di importazione non terminato")
            time.sleep(0.005)
        if status != 0:
            raise ValueError("Processo di importazione fallito")
        reply = json.loads(chunks)
        if not reply.get("ok"):
            raise ValueError(reply.get("error", "Importazione fallita"))
        return reply["value"]
    finally:
        os.close(read_fd)
        if not reaped:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)


def read_regular(path, limit, *, dir_fd=None, follow=False, root_only=False):
    flags = REGULAR & ~os.O_NOFOLLOW if follow else REGULAR
    fd = os.open(path, flags, dir_fd=dir_fd)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError("File non regolare o troppo grande")
        if root_only and (info.st_uid != 0 or info.st_mode & 0o022 or info.st_nlink != 1):
            raise ValueError("Snapshot amministrativo non protetto")
        chunks = bytearray()
        while len(chunks) <= limit:
            block = os.read(fd, min(65536, limit + 1 - len(chunks)))
            if not block:
                break
            chunks.extend(block)
        if len(chunks) > limit:
            raise ValueError("File troppo grande")
        return bytes(chunks)
    finally:
        os.close(fd)


def filtered_settings(data):
    if not isinstance(data, dict):
        raise ValueError("Le impostazioni non sono un oggetto")
    def section(name, keys=None):
        value = data.get(name, {})
        if not isinstance(value, dict):
            raise ValueError("Sezione impostazioni non valida: " + name)
        return dict(value) if keys is None else {key: value[key] for key in keys if key in value}
    return {
        "greeter": section("greeter"),
        "weather": section("weather", ("enabled", "name", "lat", "lon")),
        "input": section("input", ("layout", "naturalScroll", "tapToClick",
                                    "disableWhileTyping", "sensitivity", "repeatRate", "repeatDelay")),
    }


def image_extension(data):
    # Signature checks, not full image decoding. Never trust the filename suffix.
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "gif"
    if data.startswith(b"BM"):
        return "bmp"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp"
    if data[4:8] == b"ftyp" and any(data[i:i + 4] in (b"avif", b"avis") for i in (8, *range(16, min(len(data), 64), 4))):
        return "avif"
    if data.startswith((b"\xff\x0a", b"\x00\x00\x00\x0cJXL \r\n\x87\n")):
        return "jxl"
    raise ValueError("Lo sfondo non ha una firma immagine supportata")


def import_session(user):
    data = None
    for family in ("liquid-de", "minerva"):
        path = os.path.join(user.pw_dir, ".config", family, "settings.json")
        try:
            raw = read_regular(path, MAX_SETTINGS, follow=True)
        except FileNotFoundError:
            continue
        except PermissionError as error:
            raise ValueError("Impostazioni dell'utente chiamante non leggibili") from error
        data = filtered_settings(json.loads(raw))
        break
    if data is None:
        data = filtered_settings({})
    selected = data["greeter"].get("wallpaper", "")
    if not isinstance(selected, str):
        raise ValueError("Percorso dello sfondo non valido")
    # A failed/cleared wallpaper never leaves a private source path in runtime data.
    data["greeter"]["wallpaper"] = ""
    image, extension, warning = "", "", ""
    if selected:
        try:
            path = selected.removeprefix("file://")
            if not os.path.isabs(path):
                raise ValueError("Lo sfondo deve avere un percorso assoluto")
            raw = read_regular(path, MAX_IMAGE, follow=True)
            extension = image_extension(raw)
            image = base64.b64encode(raw).decode("ascii")
        except (OSError, ValueError) as error:
            warning = "Sfondo non copiato: " + str(error)
    return {"settings": data, "image": image, "extension": extension, "warning": warning}


def atomic_write(directory_fd, name, data, mode):
    temp = ".minerva-" + secrets.token_hex(16)
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                 mode, dir_fd=directory_fd)
    try:
        os.fchmod(fd, mode)
        remaining = memoryview(data)
        while remaining:
            remaining = remaining[os.write(fd, remaining):]
        os.fsync(fd)
        os.replace(temp, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        os.fsync(directory_fd)
    finally:
        os.close(fd)
        try:
            os.unlink(temp, dir_fd=directory_fd)
        except FileNotFoundError:
            pass


def write_runtime(directory_fd, state, imported):
    data = imported["settings"]
    target = ""
    if imported["image"]:
        if imported["extension"] not in ("png", "jpg", "gif", "bmp", "webp", "avif", "jxl"):
            raise ValueError("Formato immagine non valido")
        raw = base64.b64decode(imported["image"], validate=True)
        if len(raw) > MAX_IMAGE or image_extension(raw) != imported["extension"]:
            raise ValueError("Immagine non valida")
        # Publish the image before a JSON file that points to its unique name.
        target = "sfondo." + secrets.token_hex(12) + "." + imported["extension"]
        data["greeter"]["wallpaper"] = os.path.join(state, target)
    encoded = json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False).encode()
    if len(encoded) > MAX_SETTINGS:
        raise ValueError("Impostazioni filtrate troppo grandi")
    try:
        if target:
            atomic_write(directory_fd, target, raw, 0o600)
        atomic_write(directory_fd, "settings.json", encoded, 0o600)
    except BaseException:
        if target:
            try:
                os.unlink(target, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        raise
    for name in os.listdir(directory_fd):
        if name.startswith("sfondo.") and name != target:
            try:
                os.unlink(name, dir_fd=directory_fd)
            except (FileNotFoundError, IsADirectoryError):
                pass


def prepare_runtime(state_fd, logs_fd):
    try:
        os.mkdir("cache", 0o700, dir_fd=state_fd)
    except FileExistsError:
        pass
    cache = os.open("cache", DIRECTORY, dir_fd=state_fd)
    try:
        os.fchmod(cache, 0o700)
    finally:
        os.close(cache)
    for name in os.listdir(logs_fd):
        try:
            fd = os.open(name, REGULAR, dir_fd=logs_fd)
        except OSError:
            continue
        try:
            info = os.fstat(fd)
            if stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and info.st_nlink == 1:
                os.fchmod(fd, 0o640)
        finally:
            os.close(fd)


def prepare(state, logs, greeter):
    state_fd = prepare_directory(state, greeter, 0o700)
    try:
        logs_fd = prepare_directory(logs, greeter, 0o750)
        try:
            as_user(greeter, lambda: prepare_runtime(state_fd, logs_fd))
        finally:
            os.close(logs_fd)
    finally:
        os.close(state_fd)


def copy_session(state, caller, greeter):
    imported = as_user(caller, lambda: import_session(caller))
    fd = runtime_directory(state, greeter)
    try:
        as_user(greeter, lambda: write_runtime(fd, state, imported))
    finally:
        os.close(fd)
    if imported["warning"]:
        print(imported["warning"], file=sys.stderr)
    # Kept by root in a private staging directory, never read back from runtime.
    return imported["settings"]


def save_config(directory, source):
    data = filtered_settings(json.loads(read_regular(source, MAX_SETTINGS, root_only=True)))
    fd = trusted_directory(directory)
    try:
        atomic_write(fd, "minerva-settings.json", json.dumps(data, allow_nan=False).encode(), 0o600)
    finally:
        os.close(fd)


def config_value(directory, key):
    fd = trusted_directory(directory)
    try:
        try:
            data = json.loads(read_regular("minerva-settings.json", MAX_SETTINGS, dir_fd=fd, root_only=True))
        except FileNotFoundError:
            return ""
    finally:
        os.close(fd)
    data = filtered_settings(data)
    if key == "layout":
        layout = data["input"].get("layout", "")
        return layout if isinstance(layout, str) else ""
    if key != "autologin":
        raise ValueError("Chiave non consentita")
    g = data["greeter"]
    user, session = g.get("user", ""), g.get("session", "minerva")
    if g.get("autologin") is not True:
        return ""
    if not isinstance(user, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*\$?", user):
        raise ValueError("Utente dell'accesso automatico non valido")
    if not isinstance(session, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", session) or ".." in session:
        raise ValueError("Sessione dell'accesso automatico non valida")
    if pwd.getpwnam(user).pw_uid == 0 or user == "greeter":
        raise ValueError("Accesso automatico non consentito per questo utente")
    return user + "\t" + session


def main(args):
    if os.geteuid() != 0:
        raise PermissionError("Il coordinatore richiede root")
    action = args[0]
    if action == "prepare":
        prepare(args[1], args[2], pwd.getpwnam("greeter"))
    elif action == "copy":
        print(json.dumps(copy_session(args[1], pwd.getpwnam(args[2]), pwd.getpwnam("greeter")), allow_nan=False))
    elif action == "save-config":
        save_config(args[1], args[2])
    elif action == "read-config":
        print(config_value(args[1], args[2]))
    else:
        raise ValueError("Azione sconosciuta")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception as error:
        print("minerva-greeter-state: " + str(error), file=sys.stderr)
        sys.exit(1)
