"""Isolated checks for Fucina's privileged kernel boundaries.

These execute the actual shell branches against temporary directories; no
system kernel, boot files, or installed packages are changed.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "scripts/minerva-radice").read_text()


def shell_branch(label):
    return SOURCE.split(f"    {label})\n", 1)[1].split("\n        ;;", 1)[0]


def shell_function(name, next_marker):
    return SOURCE.split(f"{name}() {{\n", 1)[1].split(next_marker, 1)[0]


class KernelSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fucina-kernel-safety-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.boot = self.root / "boot"
        self.modules = self.root / "usr/lib/modules"
        self.boot.mkdir()
        self.modules.mkdir(parents=True)

    def run_removal(self, release):
        body = shell_branch("fucina-togli")
        body = body.replace("/usr/lib/modules", str(self.modules))
        body = body.replace("/boot", str(self.boot))
        script = f'''set -eu
muori() {{ echo "$*" >&2; exit 1; }}
controlla_rilascio() {{ :; }}
blocca_fucina_kernel() {{ :; }}
uname() {{ echo 99.0-fucina-running; }}
annota() {{ :; }}
togli_voce_avvio() {{ printf '%s\\n' "$1" > "{self.root}/voce-tolta"; }}
case fucina-togli in
fucina-togli)
{body}
;;
esac
'''
        return subprocess.run(["sh", "-c", script, "test", release],
                              capture_output=True, text=True, timeout=5)

    def test_removal_only_deletes_the_exact_release(self):
        selected = "6.17.2-fucina-a"
        similar = "6.17.2-fucina-ab"
        distro = "6.17.2-arch1-1"
        for rel in (selected, similar, distro):
            (self.modules / rel).mkdir()
            (self.modules / rel / "sentinel").write_text(rel)
            for artifact in (f"vmlinuz-{rel}", f"initramfs-{rel}.img",
                             f"initramfs-{rel}-fallback.img", f"config-{rel}"):
                (self.boot / artifact).write_text(rel)

        result = self.run_removal(selected)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.modules / selected).exists())
        self.assertFalse((self.boot / f"vmlinuz-{selected}").exists())
        self.assertFalse((self.boot / f"initramfs-{selected}.img").exists())
        self.assertFalse((self.boot / f"initramfs-{selected}-fallback.img").exists())
        self.assertFalse((self.boot / f"config-{selected}").exists())
        for rel in (similar, distro):
            self.assertEqual((self.modules / rel / "sentinel").read_text(), rel)
            self.assertEqual((self.boot / f"vmlinuz-{rel}").read_text(), rel)
            self.assertEqual((self.boot / f"initramfs-{rel}.img").read_text(), rel)
        self.assertEqual((self.root / "voce-tolta").read_text().strip(), selected)

    def test_symlinked_modules_directory_aborts_without_touching_boot(self):
        selected = "6.17.2-fucina-a"
        peer = "6.17.2-fucina-ab"
        target = self.root / "protected-modules"
        target.mkdir()
        (target / "sentinel").write_text("untouched")
        (self.modules / selected).symlink_to(target)
        (self.modules / peer).mkdir()
        (self.boot / f"vmlinuz-{selected}").write_text("kernel")
        (self.boot / f"vmlinuz-{peer}").write_text("peer")

        result = self.run_removal(selected)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((target / "sentinel").read_text(), "untouched")
        self.assertTrue((self.modules / selected).is_symlink())
        self.assertTrue((self.modules / peer / "").is_dir())
        self.assertEqual((self.boot / f"vmlinuz-{selected}").read_text(), "kernel")
        self.assertEqual((self.boot / f"vmlinuz-{peer}").read_text(), "peer")

    def test_grub_failure_keeps_existing_menu_byte_for_byte(self):
        grub_dir = self.boot / "grub"
        grub_dir.mkdir()
        config = grub_dir / "grub.cfg"
        original = "menuentry old-kernel {}\nmenuentry another-kernel {}\n"
        config.write_text(original)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        generator = bin_dir / "grub-mkconfig"
        generator.write_text("#!/bin/sh\nexit 1\n")
        generator.chmod(0o755)
        function = SOURCE.split("rigenera_grub_sicuro() {\n", 1)[1].split(
            "\n}\n\n# ── La voce", 1)[0]
        function = function.replace("/boot/grub", str(grub_dir))
        script = f"rigenera_grub_sicuro() {{\n{function}\n}}\nrigenera_grub_sicuro"

        result = subprocess.run(["sh", "-c", script], env=dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}"),
                                capture_output=True, text=True, timeout=5)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(config.read_text(), original)
        self.assertEqual(list(grub_dir.glob(".grub.cfg.fucina.*")), [])

    def test_grub_success_atomically_publishes_complete_menu(self):
        grub_dir = self.boot / "grub"
        grub_dir.mkdir()
        config = grub_dir / "grub.cfg"
        config.write_text("old menu\n")
        new_menu = "menuentry distro {}\nmenuentry fucina {}\n"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        generator = bin_dir / "grub-mkconfig"
        generator.write_text('''#!/bin/sh
[ "$1" = -o ] || exit 2
printf '%s' "$MENU_CONTENT" > "$2"
''')
        generator.chmod(0o755)
        function = SOURCE.split("rigenera_grub_sicuro() {\n", 1)[1].split(
            "\n}\n\n# ── La voce", 1)[0]
        function = function.replace("/boot/grub", str(grub_dir))
        script = f"rigenera_grub_sicuro() {{\n{function}\n}}\nrigenera_grub_sicuro"

        result = subprocess.run(["sh", "-c", script],
                                env=dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", MENU_CONTENT=new_menu),
                                capture_output=True, text=True, timeout=5)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_text(), new_menu)
        self.assertEqual(list(grub_dir.glob(".grub.cfg.fucina.*")), [])


if __name__ == "__main__":
    unittest.main()
