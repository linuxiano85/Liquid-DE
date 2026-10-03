#!/usr/bin/env bash
set -euo pipefail
# Only run inside the disposable CI container; no production login service.
[[ ${LIQUID_NATIVE_CI:-} == 1 && -e /.dockerenv ]] || { echo 'Disposable CI container required'; exit 1; }
repo=$(pwd)
output="$repo/native-results"
# Quickshell confines QML imports to the entry point's directory. Keep the
# test entry point alongside the production modules in this disposable tree.
sed 's|../../minerva-shell/|./|g' tests/native/scene.qml > minerva-shell/native-ci.qml
mkdir -p "$output"
useradd -m liquidci
printf '%s\n' 'liquidci:Liquid-CI-only-42!' | chpasswd
gcc -std=c11 -Wall -Wextra -Werror -O2 compositore/src/minerva-pam.c -lpam -o /tmp/minerva-pam
install -Dm755 /tmp/minerva-pam /usr/local/bin/minerva-pam
install -m 644 config/pam/liquid-de /etc/pam.d/liquid-ci
printf '%s\n' 'auth required /missing/liquid-ci-pam-module.so' > /etc/pam.d/liquid-ci-broken
gcc -shared -fPIC -Wall -Wextra -Werror tests/native/pam_stall.c -o /tmp/liquid-ci-pam-stall.so
printf '%s\n' 'auth required /tmp/liquid-ci-pam-stall.so' > /etc/pam.d/liquid-ci-stall
gcc -shared -fPIC -Wall -Wextra -Werror tests/native/pam_conversation.c -lpam -o /tmp/liquid-ci-pam-conversation.so
python tests/native/test_pam_helper.py 2>&1 | tee "$output/helper-tests.log"
mkdir -p /tmp/liquid-native-runtime
chown liquidci:liquidci /tmp/liquid-native-runtime "$output"
chmod 700 /tmp/liquid-native-runtime
qs --version | tee "$output/versions.txt"
pacman -Q quickshell qt6-base qt6-declarative pam mesa >> "$output/versions.txt"
Xvfb :99 -screen 0 1360x768x24 -nolisten tcp > "$output/xvfb.log" 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
for i in $(seq 1 50); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep .1; done
run_case() {
    local broken=$1 config=$2 log=$3 keyboard=${4:-0} stalled=${5:-0}
    runuser -u liquidci -- env DISPLAY=:99 XDG_RUNTIME_DIR=/tmp/liquid-native-runtime \
        QT_QPA_PLATFORM=xcb QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 \
        QT_LOGGING_RULES='quickshell.service.pam.debug=true' \
        MINERVA_PAM="$config" NATIVE_BROKEN="$broken" NATIVE_KEYBOARD="$keyboard" NATIVE_STALL="$stalled" NATIVE_OUTPUT="$output" \
        dbus-run-session -- timeout 45 qs -p "$repo/minerva-shell/native-ci.qml" > "$output/$log" 2>&1 &
    local runner=$!
    (
        sleep 12
        if kill -0 "$runner" 2>/dev/null; then
            for child in $(pgrep -u liquidci -x 'quickshell|qs|minerva-pam'); do
                echo "PAM_DIAGNOSTIC pid=$child"
                timeout 8 gdb -q -batch -ex 'set pagination off' \
                    -ex 'thread apply all bt 12' -p "$child" || true
            done
        fi
    ) > "$output/$log-stacks.txt" 2>&1 &
    local monitor=$! result=0
    wait "$runner" || result=$?
    kill "$monitor" 2>/dev/null || true
    wait "$monitor" 2>/dev/null || true
    if [[ -s "$output/$log-stacks.txt" ]]; then cat "$output/$log-stacks.txt"; fi
    return "$result"
}
status=0
run_case 0 liquid-ci graphics-pam.log || status=1
run_case 1 liquid-ci-broken pam-error.log || status=1
run_case 0 liquid-ci keyboard-pam.log 1 || status=1
run_case 0 liquid-ci-stall pam-timeout.log 0 1 || status=1
# A previous run stalled once while waiting for the first PAM response.
# Keep a short repetition gate; a later success must not hide a failed run.
for attempt in $(seq 1 20); do
    repeated="repeat-$attempt.log"
    run_case 0 liquid-ci "$repeated" || status=1
    cat "$output/$repeated"
    if ! grep -q NATIVE_GRAPHICS_PAM_PASSED "$output/$repeated" \
        || grep -q NATIVE_FAIL "$output/$repeated"; then status=1; break; fi
done
cat "$output/graphics-pam.log" "$output/pam-error.log" "$output/keyboard-pam.log" "$output/pam-timeout.log"
grep -q NATIVE_GRAPHICS_PAM_PASSED "$output/graphics-pam.log" || status=1
grep -q NATIVE_PAM_ERROR_PASSED "$output/pam-error.log" || status=1
grep -q NATIVE_KEYBOARD_PAM_PASSED "$output/keyboard-pam.log" || status=1
grep -q NATIVE_PAM_TIMEOUT_PASSED "$output/pam-timeout.log" || status=1
if grep -E 'NATIVE_FAIL|TypeError:|ReferenceError:|is not a type|Cannot assign to non-existent property' "$output/graphics-pam.log" "$output/pam-error.log" "$output/keyboard-pam.log" "$output/pam-timeout.log"; then status=1; fi
python - <<'PY'
import base64,pathlib
for p in pathlib.Path('native-results').glob('*.png'):
    print('NATIVE_SCREENSHOT '+p.name+' '+base64.b64encode(p.read_bytes()).decode())
PY
exit "$status"
