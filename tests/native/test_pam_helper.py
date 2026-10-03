"""Real helper/libpam checks; run only in the disposable native CI container."""
import ctypes
import os
from pathlib import Path
import pwd
import signal
import subprocess
import time
import unittest

HELPER = "/usr/local/bin/minerva-pam"
PASSWORD = b"Liquid-CI-only-42!"
SPECIAL = 'päss\n\t$`\\"word'.encode()


class PamHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("LIQUID_NATIVE_CI") != "1" or not Path("/.dockerenv").exists() or os.getuid() != 0:
            raise RuntimeError("Disposable CI root required")
        cls.account = pwd.getpwnam("liquidci")
        for mode in ("special", "echo", "multiple", "sequential", "length", "maxtries"):
            Path(f"/etc/pam.d/liquid-ci-{mode}").write_text(
                f"auth required /tmp/liquid-ci-pam-conversation.so {mode}\n")
        bad = Path("/etc/pam.d/liquid-ci-writable")
        bad.write_text("auth required pam_permit.so\n")
        bad.chmod(0o666)
        owned = Path("/etc/pam.d/liquid-ci-owned")
        owned.write_text("auth required pam_permit.so\n")
        os.chown(owned, cls.account.pw_uid, cls.account.pw_gid)

    def start(self, service, **kwargs):
        return subprocess.Popen([HELPER, service], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                user=self.account.pw_uid, group=self.account.pw_gid,
                                extra_groups=[], **kwargs)

    def check_result(self, service, password, code, token, **kwargs):
        with self.start(service, **kwargs) as process:
            out, err = process.communicate(password, timeout=8)
        self.assertEqual((process.returncode, out, err), (code, token + b"\n", b""))

    def test_real_password_rejection_and_success(self):
        self.check_result("liquid-ci", b"wrong-ci-password", 1, b"denied")
        self.check_result("liquid-ci", PASSWORD, 0, b"ok")

    def test_actual_uid_not_environment_user(self):
        self.check_result("liquid-ci", PASSWORD, 0, b"ok", env={**os.environ, "USER": "root", "LOGNAME": "root"})

    def test_stdin_preserves_unicode_newlines_and_metacharacters(self):
        self.check_result("liquid-ci-special", SPECIAL, 0, b"ok")

    def test_password_size_boundary(self):
        self.check_result("liquid-ci-length", b"a" * 4096, 0, b"ok")
        self.check_result("liquid-ci-length", b"a" * 4097, 3, b"error")

    def test_empty_and_embedded_nul_rejected(self):
        for password in (b"", PASSWORD + b"\0suffix"):
            with self.subTest(password_length=len(password)):
                self.check_result("liquid-ci", password, 3, b"error")

    def test_missing_service_and_path_traversal(self):
        for service in ("", "../other", "/etc/pam.d/other", "liquid-ci-absent", "x" * 129):
            with self.subTest(service=service):
                self.check_result(service, PASSWORD, 3, b"error")

    def test_untrusted_service_files(self):
        for service in ("liquid-ci-writable", "liquid-ci-owned"):
            with self.subTest(service=service):
                self.check_result(service, PASSWORD, 3, b"error")

    def test_missing_module_is_system_error(self):
        self.check_result("liquid-ci-broken", PASSWORD, 3, b"error")

    def test_echo_and_additional_prompts_fail_closed(self):
        for mode in ("echo", "multiple", "sequential"):
            with self.subTest(mode=mode):
                self.check_result("liquid-ci-" + mode, SPECIAL, 4, b"unsupported")

    def test_maxtries_is_distinct(self):
        self.check_result("liquid-ci-maxtries", PASSWORD, 2, b"maxtries")

    def test_secret_absent_from_arguments_and_environment(self):
        with self.start("liquid-ci-stall") as process:
            try:
                process.stdin.write(PASSWORD)
                process.stdin.close()
                self.wait_for_stall(process.pid)
                for name in ("cmdline", "environ"):
                    self.assertNotIn(PASSWORD, Path(f"/proc/{process.pid}/{name}").read_bytes())
                process.kill()
                self.assertEqual(process.wait(timeout=3), -signal.SIGKILL)
                self.assertEqual(process.stdout.read(), b"")
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=3)

    def wait_for_stall(self, pid):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if "pause" in Path(f"/proc/{pid}/wchan").read_text():
                return
            time.sleep(0.02)
        self.fail("PAM module did not enter its controlled stall")

    def test_helper_dies_with_parent(self):
        # Adopt and reap the orphan ourselves, avoiding leftover CI processes.
        self.assertEqual(ctypes.CDLL(None).prctl(36, 1, 0, 0, 0), 0)
        script = """
import os, subprocess, sys
p = subprocess.Popen([sys.argv[1], 'liquid-ci-stall'], stdin=subprocess.PIPE,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     user=int(sys.argv[2]), group=int(sys.argv[3]), extra_groups=[])
p.stdin.write(b'parent-death-fixture'); p.stdin.close()
print(p.pid, flush=True)
sys.stdin.read()
os._exit(0)
"""
        with subprocess.Popen(["python", "-c", script, HELPER, str(self.account.pw_uid), str(self.account.pw_gid)],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE) as parent:
            child = int(parent.stdout.readline())
            reaped = False
            try:
                self.wait_for_stall(child)
                parent.stdin.close()
                parent.wait(timeout=3)
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    found, status = os.waitpid(child, os.WNOHANG)
                    if found:
                        reaped = True
                        self.assertTrue(os.WIFSIGNALED(status))
                        self.assertEqual(os.WTERMSIG(status), signal.SIGKILL)
                        break
                    time.sleep(0.02)
                self.assertTrue(reaped, "PAM helper survived its parent")
            finally:
                if parent.poll() is None:
                    parent.kill(); parent.wait(timeout=3)
                if not reaped:
                    try:
                        os.kill(child, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    os.waitpid(child, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
