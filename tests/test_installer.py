#!/usr/bin/env python3
"""Checks the installer boundary with fake system commands; no packages change."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def command(folder, name, body):
    path = folder / name
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(0o755)


class InstallerTests(unittest.TestCase):
    def test_installed_root_contains_compositor_for_login_installer(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "source"
            (source / "scripts").mkdir(parents=True)
            for name in ("minerva-installa-radice", "minerva-cartelle.sh"):
                shutil.copy2(ROOT / "scripts" / name, source / "scripts" / name)
            for name in ("minervad/build/minervad",
                         "minervad/build/minerva-terminale-motore",
                         "compositore/build-native/minerva-wayland"):
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("#!/bin/sh\nexit 0\n")
                path.chmod(0o755)
            env = dict(os.environ, HOME=str(base / "home"),
                       XDG_CONFIG_HOME=str(base / "config"),
                       LIQUID_PREFISSO=str(base / "installed"))
            result = subprocess.run([str(source / "scripts/minerva-installa-radice")],
                                    env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            copied = base / "installed/radice/compositore/build-native/minerva-wayland"
            self.assertTrue(copied.is_file())
            self.assertTrue(os.access(copied, os.X_OK))

    def test_scan_uses_the_real_dependency_list_and_reports_greetd(self):
        with tempfile.TemporaryDirectory() as temporary:
            bin_dir = Path(temporary)
            command(bin_dir, "pacman", 'test "$1" = -T || exit 2\nprintf "greetd\\n"\nexit 127\n')
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            result = subprocess.run([str(ROOT / "scripts/install-minerva.sh"), "--scan"],
                                    env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("missing\tgreetd\n", result.stdout)
            self.assertRegex(result.stdout, r"total\t[1-9][0-9]*\n")

    def test_scan_reports_a_broken_package_database_as_an_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            bin_dir = Path(temporary)
            command(bin_dir, "pacman", "exit 42\n")
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            result = subprocess.run([str(ROOT / "scripts/install-minerva.sh"), "--scan"],
                                    env=env, text=True, capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("total\t", result.stdout)

    def test_bootstrap_installs_only_missing_gui_packages_before_qs(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            bin_dir = base / "bin"
            bin_dir.mkdir()
            command(bin_dir, "pacman", 'test "$1" = -T || exit 2\nprintf "quickshell\\nzenity\\n"\nexit 127\n')
            command(bin_dir, "pkexec", 'printf "%s\\n" "$@" > "$TEST_BOOTSTRAP_CALL"\n')
            command(bin_dir, "qs", 'printf "%s\\n" "$@" > "$TEST_QS_CALL"\n')
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                       DISPLAY=":test", XDG_STATE_HOME=str(base / "state"),
                       TEST_BOOTSTRAP_CALL=str(base / "bootstrap"),
                       TEST_QS_CALL=str(base / "qs"))
            result = subprocess.run([str(ROOT / "install.sh")], env=env, text=True,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((base / "bootstrap").read_text().splitlines(),
                             ["/usr/bin/pacman", "-S", "--needed", "--noconfirm", "--",
                              "quickshell", "zenity"])
            self.assertEqual((base / "qs").read_text().splitlines()[-2:],
                             ["-p", str(ROOT / "minerva-shell/installer.qml")])
            logs = list((base / "state/liquid-de/installer").glob("launch-*.log"))
            self.assertEqual(len(logs), 1)
            self.assertIn("Quickshell terminato con codice 0", logs[0].read_text())


if __name__ == "__main__":
    unittest.main()
