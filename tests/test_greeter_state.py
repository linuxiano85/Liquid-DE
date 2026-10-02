#!/usr/bin/env python3
"""No real /etc, /var, users, services or credentials are modified.

CI runs with sudo and requires actual UID/GID transitions. A restricted local
runtime may skip that class explicitly; pure filesystem and IPC tests still run.
"""
import importlib.util
import base64
import json
import os
from pathlib import Path
import pwd
import stat
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("greeter_state", ROOT / "scripts/minerva-greeter-state.py")
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)
PNG = b"\x89PNG\r\n\x1a\n" + b"FAKE-IMAGE-FOR-PERMISSION-TESTS"


class LogicTests(unittest.TestCase):
    def test_filter_exports_only_login_weather_and_input(self):
        got = state.filtered_settings({"greeter": {"blur": 12}, "weather": {"name": "Roma", "secret": "x"},
                                       "input": {"layout": "it", "password": "x"}, "accounts": {"token": "x"}})
        self.assertEqual(got, {"greeter": {"blur": 12}, "weather": {"name": "Roma"}, "input": {"layout": "it"}})

    def test_invalid_sections_are_rejected(self):
        for data in ([], {"greeter": []}, {"weather": False}, {"input": "it"}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                state.filtered_settings(data)

    def test_signature_rejects_disguised_text(self):
        self.assertEqual(state.image_extension(PNG), "png")
        self.assertEqual(state.image_extension(b"\xff\xd8\xffabc"), "jpg")
        self.assertEqual(state.image_extension(b"RIFF1234WEBPabc"), "webp")
        with self.assertRaises(ValueError):
            state.image_extension(b"private text with .png suffix")

    def test_non_regular_and_oversized_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            fifo = Path(folder) / "fifo"
            os.mkfifo(fifo)
            with self.assertRaises(ValueError):
                state.read_regular(str(fifo), 20)
            file = Path(folder) / "large"
            file.write_bytes(b"x" * 21)
            with self.assertRaises(ValueError):
                state.read_regular(str(file), 20)

    def test_atomic_write_replaces_link_without_touching_target(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / "target"
            target.write_bytes(b"keep")
            (root / "settings.json").symlink_to(target)
            fd = os.open(root, state.DIRECTORY)
            try:
                state.atomic_write(fd, "settings.json", b"new", 0o600)
            finally:
                os.close(fd)
            self.assertEqual(target.read_bytes(), b"keep")
            self.assertFalse((root / "settings.json").is_symlink())
            self.assertEqual((root / "settings.json").read_bytes(), b"new")

    def test_failed_publish_keeps_previous_file_and_removes_temporary(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "settings.json").write_bytes(b"old")
            fd = os.open(root, state.DIRECTORY)
            try:
                with patch.object(state.os, "replace", side_effect=OSError("simulated failure")), self.assertRaises(OSError):
                    state.atomic_write(fd, "settings.json", b"new", 0o600)
            finally:
                os.close(fd)
            self.assertEqual((root / "settings.json").read_bytes(), b"old")
            self.assertEqual(list(root.glob(".minerva-*")), [])

    def test_ipc_timeout_kills_and_reaps_worker(self):
        # Only this transport test mocks dropping privileges; it touches no files.
        before = time.monotonic()
        with patch.object(state, "drop_privileges"), self.assertRaises(TimeoutError):
            state.as_user(None, lambda: time.sleep(10), timeout=0.05)
        self.assertLess(time.monotonic() - before, 2)
        with self.assertRaises(ChildProcessError):
            os.waitpid(-1, os.WNOHANG)

    def test_oversized_export_does_not_leave_an_orphan_image(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "settings.json").write_bytes(b"previous")
            data = {"settings": {"greeter": {"text": "x" * 300}, "input": {}, "weather": {}},
                    "image": base64.b64encode(PNG).decode(), "extension": "png"}
            fd = os.open(root, state.DIRECTORY)
            try:
                with patch.object(state, "MAX_SETTINGS", 200), self.assertRaises(ValueError):
                    state.write_runtime(fd, folder, data)
            finally:
                os.close(fd)
            self.assertEqual(list(root.glob("sfondo.*")), [])
            self.assertEqual((root / "settings.json").read_bytes(), b"previous")

    def test_shell_uses_admin_snapshot_instead_of_greeter_owned_settings(self):
        source = (ROOT / "scripts/minerva-greetd").read_text()
        config = source[source.index("scrivi_config() {"):source.index("# ── Le azioni")]
        self.assertNotIn("$STATO/settings.json", config.replace('in «$STATO/settings.json»', ''))
        self.assertIn('stato_sicuro read-config "$CONF" autologin', config)
        self.assertNotIn('chown -R greeter', source)
        self.assertIn('install -m644 "$ROOT/scripts/minerva-greeter-state.py"', source)


class PrivilegeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            if os.geteuid() != 0:
                raise PermissionError("requires sudo")
            nobody = pwd.getpwnam("nobody")
            cls.caller_template = nobody
            cls.greeter = SimpleNamespace(pw_name="nobody", pw_uid=65533, pw_gid=nobody.pw_gid)
            state.as_user(nobody, lambda: list(os.getresuid()))
        except Exception as error:
            if os.environ.get("REQUIRE_GREETER_PRIVILEGES") == "1":
                raise RuntimeError("CI must exercise real privileges: " + str(error)) from error
            raise unittest.SkipTest("UID/GID transitions unavailable: " + str(error))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="liquid-greeter-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.base.chmod(0o755)
        self.runtime = self.base / "state"
        self.logs = self.base / "logs"
        self.home = self.base / "home"
        self.home.mkdir(mode=0o700)
        os.chown(self.home, self.caller_template.pw_uid, self.caller_template.pw_gid)
        self.caller = SimpleNamespace(pw_name="nobody", pw_uid=self.caller_template.pw_uid,
                                     pw_gid=self.caller_template.pw_gid, pw_dir=str(self.home))
        self.settings = self.home / ".config/liquid-de/settings.json"
        self.settings.parent.mkdir(parents=True)
        for directory in (self.home / ".config", self.settings.parent):
            os.chown(directory, self.caller.pw_uid, self.caller.pw_gid)
        self.secret = self.base / "root-only.png"
        self.secret.write_bytes(PNG + b"ROOT-PRIVATE-DATA")
        self.secret.chmod(0o600)
        self.before = self.metadata(self.secret)
        state.prepare(str(self.runtime), str(self.logs), self.greeter)

    @staticmethod
    def metadata(path):
        info = path.stat()
        return path.read_bytes(), info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)

    def configure(self, greeter=None, **extra):
        self.settings.write_text(json.dumps({"greeter": greeter or {"blur": 12}, "input": {"layout": "it"}, **extra}))
        os.chown(self.settings, self.caller.pw_uid, self.caller.pw_gid)
        self.settings.chmod(0o600)

    def test_drop_is_permanent_and_uses_caller_groups(self):
        def identities():
            denied = False
            try:
                os.setuid(0)
            except PermissionError:
                denied = True
            return {"uids": os.getresuid(), "gids": os.getresgid(), "denied": denied}
        got = state.as_user(self.caller, identities)
        self.assertEqual(got["uids"], [self.caller.pw_uid] * 3)
        self.assertEqual(got["gids"], [self.caller.pw_gid] * 3)
        self.assertTrue(got["denied"])

    def test_settings_symlink_does_not_truncate_chown_or_chmod_root_target(self):
        self.configure()
        (self.runtime / "settings.json").symlink_to(self.secret)
        state.copy_session(str(self.runtime), self.caller, self.greeter)
        self.assertEqual(self.metadata(self.secret), self.before)
        self.assertFalse((self.runtime / "settings.json").is_symlink())
        self.assertEqual((self.runtime / "settings.json").stat().st_uid, self.greeter.pw_uid)

    def test_hardlink_does_not_modify_root_target(self):
        self.configure()
        os.link(self.secret, self.runtime / "settings.json")
        state.copy_session(str(self.runtime), self.caller, self.greeter)
        self.assertEqual(self.metadata(self.secret), self.before)

    def test_root_only_wallpaper_is_not_exported(self):
        self.configure({"wallpaper": str(self.secret)})
        saved = state.copy_session(str(self.runtime), self.caller, self.greeter)
        actual = json.loads((self.runtime / "settings.json").read_text())
        self.assertEqual(saved["greeter"]["wallpaper"], "")
        self.assertEqual(actual["greeter"]["wallpaper"], "")
        self.assertEqual(list(self.runtime.glob("sfondo.*")), [])
        self.assertEqual(self.metadata(self.secret), self.before)

    def test_legitimate_private_image_is_copied_as_greeter_and_can_be_cleared(self):
        image = self.home / "photo with spaces.dat"
        image.write_bytes(PNG)
        image.chmod(0o600)
        os.chown(image, self.caller.pw_uid, self.caller.pw_gid)
        self.configure({"wallpaper": "file://" + str(image)}, accounts={"token": "SECRET"})
        state.copy_session(str(self.runtime), self.caller, self.greeter)
        data = json.loads((self.runtime / "settings.json").read_text())
        exported = Path(data["greeter"]["wallpaper"])
        self.assertEqual(exported.read_bytes(), PNG)
        self.assertEqual(exported.stat().st_uid, self.greeter.pw_uid)
        self.assertEqual(stat.S_IMODE(exported.stat().st_mode), 0o600)
        self.assertNotIn("accounts", data)
        self.configure()
        state.copy_session(str(self.runtime), self.caller, self.greeter)
        self.assertEqual(list(self.runtime.glob("sfondo.*")), [])

    def test_root_only_settings_source_is_not_read_and_previous_runtime_survives(self):
        self.configure()
        state.copy_session(str(self.runtime), self.caller, self.greeter)
        previous = (self.runtime / "settings.json").read_bytes()
        private = self.base / "root-settings.json"
        private.write_text('{"greeter":{"blur":999}}')
        private.chmod(0o600)
        self.settings.unlink()
        self.settings.symlink_to(private)
        with self.assertRaises(ValueError):
            state.copy_session(str(self.runtime), self.caller, self.greeter)
        self.assertEqual((self.runtime / "settings.json").read_bytes(), previous)

    def test_state_symlink_is_rejected_without_changing_external_directory(self):
        external = self.base / "external"
        external.mkdir(mode=0o711)
        bad = self.base / "bad-state"
        bad.symlink_to(external)
        before = external.stat()
        with self.assertRaises(OSError):
            state.prepare(str(bad), str(self.logs), self.greeter)
        after = external.stat()
        self.assertEqual((before.st_uid, before.st_gid, before.st_mode), (after.st_uid, after.st_gid, after.st_mode))

    def test_first_install_without_session_settings_uses_empty_factory_overrides(self):
        saved = state.copy_session(str(self.runtime), self.caller, self.greeter)
        self.assertEqual(saved, {"greeter": {"wallpaper": ""}, "weather": {}, "input": {}})
        self.assertEqual(json.loads((self.runtime / "settings.json").read_text()), saved)

    def test_old_minerva_settings_are_imported_when_liquid_settings_are_absent(self):
        legacy = self.home / ".config/minerva"
        legacy.mkdir()
        os.chown(legacy, self.caller.pw_uid, self.caller.pw_gid)
        file = legacy / "settings.json"
        file.write_text('{"input":{"layout":"it"},"greeter":{"blur":12}}')
        os.chown(file, self.caller.pw_uid, self.caller.pw_gid)
        file.chmod(0o600)
        saved = state.copy_session(str(self.runtime), self.caller, self.greeter)
        self.assertEqual(saved["input"], {"layout": "it"})

    def test_cache_and_logs_links_do_not_change_root_targets(self):
        cache = self.runtime / "cache"
        cache.rmdir()
        cache.symlink_to(self.base)
        with self.assertRaises(ValueError):
            state.prepare(str(self.runtime), str(self.logs), self.greeter)
        cache.unlink()
        (self.logs / "link.log").symlink_to(self.secret)
        os.link(self.secret, self.logs / "hard.log")
        os.mkfifo(self.logs / "fifo.log")
        state.prepare(str(self.runtime), str(self.logs), self.greeter)
        self.assertEqual(self.metadata(self.secret), self.before)

    def test_authorization_snapshot_is_not_read_from_runtime(self):
        config = self.base / "config"
        config.mkdir(mode=0o700)
        source = self.base / "snapshot.json"
        source.write_text(json.dumps({"greeter": {"autologin": True, "user": "nobody", "session": "minerva"}, "input": {"layout": "it"}}))
        source.chmod(0o600)
        state.save_config(str(config), str(source))
        (self.runtime / "settings.json").write_text('{"greeter":{"user":"root","autologin":true},"input":{"layout":"evil"}}')
        self.assertEqual(state.config_value(str(config), "layout"), "it")
        self.assertEqual(state.config_value(str(config), "autologin"), "nobody\tminerva")
        snapshot = config / "minerva-settings.json"
        snapshot.unlink()
        snapshot.symlink_to(source)
        with self.assertRaises(OSError):
            state.config_value(str(config), "autologin")

    def test_autologin_rejects_root_and_path_injection(self):
        config = self.base / "config"
        config.mkdir(mode=0o700)
        source = self.base / "snapshot.json"
        for user, session in (("root", "minerva"), ("nobody", "../../bad"), ("nobody\nroot", "minerva")):
            source.write_text(json.dumps({"greeter": {"autologin": True, "user": user, "session": session}}))
            source.chmod(0o600)
            state.save_config(str(config), str(source))
            with self.subTest(user=user, session=session), self.assertRaises(ValueError):
                state.config_value(str(config), "autologin")

    def test_repeated_hostile_link_replacement_never_changes_root_target(self):
        self.configure()
        stop = self.base / "stop"
        stop.write_text("")
        stop.chmod(0o666)
        pid = os.fork()
        if pid == 0:
            try:
                state.drop_privileges(self.greeter)
                path = self.runtime / "settings.json"
                while not stop.read_text():
                    try:
                        path.unlink(missing_ok=True)
                        path.symlink_to(self.secret)
                    except FileExistsError:
                        pass
                os._exit(0)
            except BaseException:
                os._exit(1)
        try:
            for _ in range(8):
                state.copy_session(str(self.runtime), self.caller, self.greeter)
            self.assertEqual(self.metadata(self.secret), self.before)
        finally:
            stop.write_text("stop")
            found, status = os.waitpid(pid, 0)
            self.assertEqual((found, status), (pid, 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
