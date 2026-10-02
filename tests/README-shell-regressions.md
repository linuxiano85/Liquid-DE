# Shell regressions

Run from the repository root on Linux with Node.js 22 or newer and Python 3:

```sh
node --test tests/shell-regressions.mjs
python3 tests/test_greeter_state.py
dart run tests/desktop_launcher_test.dart
```

The suite executes JavaScript function and handler bodies extracted from the
production QML. It runs the generated network query against a temporary fake
`nmcli`, tracks notification fixtures and drives profile/password callbacks.
A real temporary child records its own `/proc/self/cmdline` before receiving a
fake password on stdin. No real password, radio change or privileged helper is
used. `SHELL_SOURCE_ROOT` can point to an earlier source snapshot for comparison;
failures can include helpers/handlers that do not exist in the earlier version.

The Python suite tests the actual installed greeter-state module. Its permission
class needs real root privileges to use two distinct unprivileged UIDs on files
under a fresh temporary directory. It never changes system accounts, `/etc`,
`/var`, display managers or passwords. Restricted runtimes explicitly skip
that class; CI uses the following command and fails if privilege tests cannot run:

```sh
sudo env REQUIRE_GREETER_PRIVILEGES=1 python3 tests/test_greeter_state.py
```

It checks permanent UID/GID reduction, symlink/hardlink destinations, a concurrent
link replacement, root-only source rejection, a private readable image, first
installation, legacy settings, cache/log links, atomic failure and the separation
between the runtime settings and the administrative autologin snapshot. Image
checks validate header signatures; they do not run an image decoder.

After installing this change, run `sudo minerva-greetd configura` from the user's
session to create the root-only snapshot before activation. Existing runtime
settings are deliberately not trusted as a source of autologin configuration.
Python 3 and the installed `minerva-greeter-state.py` module are required.

The Dart launcher tests require SDK 3.12 or newer and use only the standard
library. CI installs that SDK, compiles the full daemon to check IPC integration,
and exercises the actual guard/parser on temporary `.desktop` files. The only
program started by these tests writes a harmless marker inside the temporary
test directory. Previewing the file never runs it. Tests cover missing/forged,
cross-client, reused, canceled and expired consent, content/symlink changes,
malformed/oversized/FIFO input, NoDisplay semantics, capacity and read timeout.
No app-specific code is edited: the confirmation window is created on demand
by the shared IPC singleton.

These checks do not load QML or test Qt signal ordering. Before merging, run
the Shell on its supported Quickshell version and verify:

| Area | Native check |
|---|---|
| Password | With a disposable account, test success, cancellation, denied authorization, missing executable and two successive changes. Verify no password in process arguments or logs. |
| Installed helpers | Without `/usr/local/bin/liquid-de-utente` or `/usr/local/bin/minerva-greetd`, verify a clear error and no attempt to elevate project scripts. |
| Login files | With a disposable test installation, configure appearance and keyboard, check the root-only snapshot and image permissions, and verify normal login and intended autologin after reinstalling the updated helper. |
| Desktop launchers | Open a temporary `.desktop` from the desktop; verify command/path preview, default Cancel focus, Tab/Escape, multi-monitor and small-screen behavior. Cancel must create no marker; explicit approval creates one. Edit the file while the dialog is open: approval must fail. Repeat after disconnect/reconnect and verify there is no deferred launch. The native dialog is not covered by the JS extraction or Dart kernel compile. |
| Notifications | Send more than 60, read/remove/clear them, check DBus closure and retained objects, and verify lock privacy modes and literal markup text. |
| Wi-Fi | Check active AP, duplicate SSIDs, colon/backslash/tab characters and Ethernet connection names against real NetworkManager. Newline and arbitrary-byte SSIDs remain outside these regressions. |
| Power profile | Leave fullscreen while profile read is pending; check ordered performance/restore commands with power-profiles-daemon. Crash recovery and rapid reentry remain separate issues. |
| Night light | Change the start/end hour while the schedule is enabled and check immediate application, including midnight crossings. |

The changes use Quickshell `Process.started`, `write()` and `stdinEnabled`.
The password stream is closed after queuing its single line. Native PAM,
polkit, greetd, Bluetooth and monitor integration still require system testing.
