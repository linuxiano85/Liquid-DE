"""Esegue i rami shell privilegiati in directory temporanee, senza root.

Le destinazioni assolute vengono riscritte, chown/ownership simulate; cp,
mv, rm, flock e rollback sono reali. Nessun comando accede a /boot o ai
moduli del sistema. Fault injection solo nei programmi della fixture.
"""
import json
import os
import re
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "scripts/minerva-radice").read_text()
RELEASE = "7.2.9-fucina-prova"


def function(name):
    return name + "() {\n" + SOURCE.split(name + "() {\n", 1)[1].split("\n}\n", 1)[0] + "\n}\n"


class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fucina-transaction-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.boot = self.root / "boot"
        self.modules = self.root / "modules"
        self.bin = self.root / "bin"
        self.source = self.root / "output" / RELEASE
        for p in [self.boot, self.modules, self.bin, self.root / "run"]:
            p.mkdir()
        self.write(self.source / "boot" / f"vmlinuz-{RELEASE}", "new image")
        self.write(self.source / "boot" / f"config-{RELEASE}", "new config")
        self.write(self.source / "lib/modules" / RELEASE / "driver.ko", "new driver")
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin", PKEXEC_UID=str(os.getuid()),
                        FIXTURE_ROOT=str(self.root), RELEASE=RELEASE)
        # Ownership is the only privileged operation suppressed by the harness.
        self.command("chown", "exit 0")
        self.command("install", '''set -- "$@"
args=''
exec python3 - "$@" <<'PY'
import os, sys
a=sys.argv[1:]; out=[]; i=0
if os.environ.get('FAULT') == 'write-image' and a[-1].endswith('.nuovo') and '/.vmlinuz-' in a[-1]:
    sys.exit(1)
while i < len(a):
    if a[i] in ('-o','-g'): i+=2
    else: out.append(a[i]); i+=1
os.execv('/usr/bin/install',['install']+out)
PY''')
        self.command("uname", 'printf "%s\\n" "${RUNNING:-99.0-fucina-running}"')
        self.command("depmod", 'echo depmod-diagnostic >&2\n[ "${FAULT:-}" != depmod ]')
        self.command("mkinitcpio", '''echo initramfs-diagnostic >&2
[ "${FAULT:-}" != initramfs ] || exit 1
while [ "$1" != -g ]; do shift; done
if [ "${FAULT:-}" = empty-initramfs ]; then : > "$2"; else echo new-initramfs > "$2"; fi''')
        # Fail one move only; rollback moves can still succeed.
        self.command("mv", '''last=''; for a in "$@"; do last="$a"; done
if [ "${FAULT:-}" = "move-modules" ] && [ "$last" = "$FIXTURE_ROOT/modules/$RELEASE" ] && [ ! -e "$FIXTURE_ROOT/fault-used" ]; then
    touch "$FIXTURE_ROOT/fault-used"; exit 1
fi
if [ "${FAULT:-}" = "rollback-fails" ]; then
    case "$last" in
        "$FIXTURE_ROOT/boot/initramfs-$RELEASE.img") exit 1;;
        "$FIXTURE_ROOT/modules/$RELEASE")
            [ ! -e "$FIXTURE_ROOT/fault-used" ] || exit 1
            touch "$FIXTURE_ROOT/fault-used";;
    esac
fi
if [ "${FAULT:-}" = "move-image" ] && [ "$last" = "$FIXTURE_ROOT/boot/vmlinuz-$RELEASE" ] && [ ! -e "$FIXTURE_ROOT/fault-used" ]; then
    touch "$FIXTURE_ROOT/fault-used"; exit 1
fi
if [ "${FAULT:-}" = "move-initramfs" ] && [ "$last" = "$FIXTURE_ROOT/boot/initramfs-$RELEASE.img" ] && [ ! -e "$FIXTURE_ROOT/fault-used" ]; then
    touch "$FIXTURE_ROOT/fault-used"; exit 1
fi
if [ "${FAULT:-}" = "term-after-image" ] && [ "$last" = "$FIXTURE_ROOT/boot/vmlinuz-$RELEASE" ] && [ ! -e "$FIXTURE_ROOT/fault-used" ]; then
    touch "$FIXTURE_ROOT/fault-used"
    /usr/bin/mv "$@" || exit
    kill -TERM "$PPID"; exit 0
fi
exec /usr/bin/mv "$@"''')

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def command(self, name, body):
        p = self.bin / name
        p.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
        p.chmod(0o755)

    def script(self, action):
        body = SOURCE.split(f"    {action})\n", 1)[1].split("\n        ;;", 1)[0]
        header = "set -eu\nmuori() { echo \"$*\" >&2; exit 1; }\nannota() { :; }\n"
        header += function("controlla_percorso") + function("controlla_rilascio")
        header += function("blocca_fucina_kernel")
        header += 'voce_avvio() { echo boot-entry; }\ntogli_voce_avvio() { echo removed-entry; }\n'
        s = header + body
        # Source paths and destinations all live in the sandbox.
        for real, fake in [("/usr/lib/modules", self.modules), ("/boot", self.boot),
                           ("/run/minerva-fucina", self.root / "run/minerva-fucina")]:
            s = re.sub(r'(?<![\w$])' + re.escape(real), str(fake), s)
        return s

    def run_action(self, action="fucina-installa", release=RELEASE, fault="", **env):
        args = [str(self.source), release] if action == "fucina-installa" else [release]
        return subprocess.run(["sh", "-c", self.script(action), "fixture"] + args,
                              env=dict(self.env, FAULT=fault, **env), capture_output=True, text=True, timeout=10)

    def old_kernel(self, release=RELEASE):
        self.write(self.modules / release / "sentinel", "old modules")
        for name in [f"vmlinuz-{release}", f"initramfs-{release}.img", f"config-{release}"]:
            self.write(self.boot / name, "old " + name)

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for base in [self.boot, self.modules] for p in base.rglob("*") if p.is_file()}

    def test_success_and_peer_kernels(self):
        self.old_kernel()
        self.old_kernel(RELEASE + "-other")
        self.old_kernel("7.2.9-cachyos")
        peers = {k:v for k,v in self.snapshot().items() if RELEASE + "-other" in k or "cachyos" in k}
        r = self.run_action()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.modules / RELEASE / "driver.ko").read_text(), "new driver")
        self.assertEqual((self.boot / f"vmlinuz-{RELEASE}").read_text(), "new image")
        self.assertEqual((self.boot / f"initramfs-{RELEASE}.img").read_text(), "new-initramfs\n")
        for k,v in peers.items(): self.assertEqual((self.root / k).read_bytes(), v)
        self.assertEqual(list(self.modules.glob(".fucina-*")), [])

    def test_failure_matrix_restores_previous_kernel(self):
        for fault in ["depmod", "initramfs", "empty-initramfs", "move-modules", "write-image", "move-image", "move-initramfs"]:
            with self.subTest(fault=fault):
                self.old_kernel(); before = self.snapshot()
                (self.root / "fault-used").unlink(missing_ok=True)
                r = self.run_action(fault=fault)
                self.assertNotEqual(r.returncode, 0)
                self.assertEqual(self.snapshot(), before, r.stderr)

    def test_failure_without_previous_kernel_leaves_no_partial_install(self):
        r = self.run_action(fault="move-initramfs")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.snapshot(), {})

    def test_signal_during_publication_restores_previous_kernel(self):
        self.old_kernel(); before = self.snapshot()
        r = self.run_action(fault="term-after-image")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.snapshot(), before, r.stderr)

    def test_rejects_missing_empty_and_special_inputs(self):
        image = self.source / "boot" / f"vmlinuz-{RELEASE}"
        for kind in ["missing", "empty", "symlink", "fifo"]:
            with self.subTest(kind=kind):
                image.unlink(missing_ok=True)
                if kind == "empty": image.touch()
                if kind == "symlink": image.symlink_to("/etc/passwd")
                if kind == "fifo": os.mkfifo(image)
                r = self.run_action()
                self.assertNotEqual(r.returncode, 0, kind)
                self.assertEqual(self.snapshot(), {})

    def test_running_kernel_and_distro_are_rejected(self):
        self.old_kernel(); before = self.snapshot()
        for action in ["fucina-installa", "fucina-togli"]:
            r = self.run_action(action, RUNNING=RELEASE)
            self.assertNotEqual(r.returncode, 0)
            self.assertEqual(self.snapshot(), before)
            for release in ["7.2.9-cachyos", "../etc", RELEASE + "\nanything", RELEASE + "/../other"]:
                r = self.run_action(action, release)
                self.assertNotEqual(r.returncode, 0)
                self.assertEqual(self.snapshot(), before)

    def test_existing_boot_symlink_is_rejected(self):
        protected = self.boot / "other-config"
        protected.write_text("untouched")
        (self.boot / f"config-{RELEASE}").symlink_to(protected)
        r = self.run_action()
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(protected.read_text(), "untouched")

    def test_installation_diagnostics_are_not_discarded(self):
        r = self.run_action(fault="initramfs")
        self.assertIn("initramfs-diagnostic", r.stderr)

    def test_failed_recovery_keeps_backups_and_reports_location(self):
        self.old_kernel()
        self.old_kernel(RELEASE + '-other')
        peer = (self.modules / (RELEASE + '-other') / 'sentinel').read_bytes()
        r = self.run_action(fault='rollback-fails')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('recupero incompleto', r.stderr)
        backups = list(self.modules.glob('.fucina-*'))
        self.assertEqual(len(backups), 1, r.stderr)
        self.assertEqual((backups[0] / 'vecchi/sentinel').read_text(), 'old modules')
        self.assertEqual((backups[0] / f'vecchio-vmlinuz-{RELEASE}').read_text(), 'old vmlinuz-' + RELEASE)
        self.assertEqual((self.modules / (RELEASE + '-other') / 'sentinel').read_bytes(), peer)

    def test_lock_contends_across_processes(self):
        body = function("blocca_fucina_kernel").replace("/run/minerva-fucina",str(self.root / "run/minerva-fucina"))
        header = 'set -eu\nmuori() { echo "$*" >&2; exit 1; }\n'
        p = subprocess.Popen(["sh", "-c", header + body + "blocca_fucina_kernel\necho locked\nsleep 2"],
                             env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: p.poll() is None and p.terminate())
        self.assertEqual(p.stdout.readline().strip(), "locked")
        r = subprocess.run(["sh", "-c", header + body + "blocca_fucina_kernel"],env=self.env,capture_output=True,text=True,timeout=3)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("già in corso", r.stderr)
        p.communicate(timeout=4)


if __name__ == "__main__":
    unittest.main(verbosity=2)
