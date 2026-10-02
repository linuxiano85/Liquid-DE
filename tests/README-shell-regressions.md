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

## Wi-Fi credentials (piece 3)

`node --test tests/shell-regressions.mjs` also executes the Wi-Fi functions
from Network.qml: no secrets in argv or queued commands; recognized prompts
only; one response; stale completion, failure/start/timeout cleanup; dialog
clear and press-to-reveal. This still does not load QML.

The CI `wifi-credentials` job extracts nmcli from Ubuntu's network-manager
package without installing or starting its daemon. Python dbusmock creates a
private system bus and simulated AP/NetworkManager. Run with a real nmcli,
Node and system Python's dbusmock installed:

```sh
sudo env "PATH=$PATH" /usr/bin/python3 tests/test_wifi_nmcli.py
```

The simulated NetworkManager bus owner runs as root because libnm verifies
that UID before registering a SecretAgent. Everything stays on the private
bus; no host NetworkManager calls are made.

Two integration tests exercise real nmcli/readline: device wifi connect and
SecretAgent GetSecrets through activation of the saved profile UUID. The
production lookup also executes against the private mock bus. This avoids
nmcli 1.46 wifi-connect ignoring a replacement for a saved password, including replacement of a prefilled credential,
spaces, quotes and shell metacharacters. They inspect /proc argv while the
client is alive, exact credentials delivered over the mock bus, and output
for accidental echo. All credentials and APs are fictitious. The test driver
alone supplies its fake credential through an environment variable;
production credentials are never placed in environment variables.

Before native acceptance, load Network.qml in Quickshell and verify open,
known PSK, new PSK, incorrect saved/input secret, WEP where supported, nmcli
absent, timeout, closing the page during a prompt, radio-off and repeated
clicks. Observe actual NetworkManager device state and DHCP rather than only
an exit message. Check no secret appears in /proc command lines, application
logs, UI errors or deferred IPC; inspect secrets only with disposable test
credentials. An interrupted nmcli client does not promise rollback of an
activation already submitted to NetworkManager. 802.1X configuration with
multiple credentials/certificates is outside this patch. Control characters
in passwords are explicitly rejected rather than interpreted by readline.


Saved-profile lookup is read-only and compares the unescaped SSID literally,
including surrounding spaces. It activates a validated UUID with connection
up --ask, which supplies a SecretAgent on older nmcli releases too. No secret
is passed to the lookup; failures and late replies cannot start activation.
Multiple matching profiles/adapters, modern nmcli and real radio/DHCP remain
native acceptance cases.

## Login transport regressions

The JS suite also executes real IPC/greeter function bodies for offline
credential rejection, legacy queue filtering, retired socket callbacks,
field/state cleanup, late replies and explicit retry after reconnection.
It does not run Qt signals or PAM. Native acceptance must interrupt the
minervad connection while typing, awaiting PAM and starting a session:
no credential or session command may replay, the field must clear, and
Enter must start a fresh cancellation/retry after reconnection. Test user
selection while disconnected and verify the greeter never exits because
of a late success. Server-side concurrent conversations remain open.
