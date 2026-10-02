# Shell regressions

Run from the repository root on Linux with Node.js 22 or newer and Python 3:

```sh
node --test tests/shell-regressions.mjs
```

The suite executes JavaScript function and handler bodies extracted from the
production QML. It runs the generated network query against a temporary fake
`nmcli`, tracks notification fixtures and drives profile/password callbacks.
A real temporary child records its own `/proc/self/cmdline` before receiving a
fake password on stdin. No real password, radio change or privileged helper is
used. `SHELL_SOURCE_ROOT` can point to an earlier source snapshot for comparison;
failures can include helpers/handlers that do not exist in the earlier version.

These checks do not load QML or test Qt signal ordering. Before merging, run
the Shell on its supported Quickshell version and verify:

| Area | Native check |
|---|---|
| Password | With a disposable account, test success, cancellation, denied authorization, missing executable and two successive changes. Verify no password in process arguments or logs. |
| Installed helpers | Without `/usr/local/bin/liquid-de-utente` or `/usr/local/bin/minerva-greetd`, verify a clear error and no attempt to elevate project scripts. |
| Notifications | Send more than 60, read/remove/clear them, check DBus closure and retained objects, and verify lock privacy modes and literal markup text. |
| Wi-Fi | Check active AP, duplicate SSIDs, colon/backslash/tab characters and Ethernet connection names against real NetworkManager. Newline and arbitrary-byte SSIDs remain outside these regressions. |
| Power profile | Leave fullscreen while profile read is pending; check ordered performance/restore commands with power-profiles-daemon. Crash recovery and rapid reentry remain separate issues. |
| Night light | Change the start/end hour while the schedule is enabled and check immediate application, including midnight crossings. |

The changes use Quickshell `Process.started`, `write()` and `stdinEnabled`.
The password stream is closed after queuing its single line. Native PAM,
polkit, greetd, Bluetooth and monitor integration still require system testing.
