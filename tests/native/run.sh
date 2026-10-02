#!/usr/bin/env bash
set -euo pipefail
# Only run inside the disposable CI container; no production login service.
[[ ${LIQUID_NATIVE_CI:-} == 1 && -e /.dockerenv ]] || { echo 'Disposable CI container required'; exit 1; }
repo=$(pwd)
output="$repo/native-results"
mkdir -p "$output"
useradd -m liquidci
printf '%s\n' 'liquidci:Liquid-CI-only-42!' | chpasswd
install -m 644 config/pam/liquid-de /etc/pam.d/liquid-ci
printf '%s\n' 'auth required /missing/liquid-ci-pam-module.so' > /etc/pam.d/liquid-ci-broken
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
    local broken=$1 config=$2 log=$3
    runuser -u liquidci -- env DISPLAY=:99 XDG_RUNTIME_DIR=/tmp/liquid-native-runtime \
        QT_QPA_PLATFORM=xcb QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 \
        MINERVA_PAM="$config" NATIVE_BROKEN="$broken" NATIVE_OUTPUT="$output" \
        dbus-run-session -- timeout 45 qs -p "$repo/tests/native/scene.qml" > "$output/$log" 2>&1
}
status=0
run_case 0 liquid-ci graphics-pam.log || status=1
run_case 1 liquid-ci-broken pam-error.log || status=1
cat "$output/graphics-pam.log" "$output/pam-error.log"
grep -q NATIVE_GRAPHICS_PAM_PASSED "$output/graphics-pam.log" || status=1
grep -q NATIVE_PAM_ERROR_PASSED "$output/pam-error.log" || status=1
if grep -E 'NATIVE_FAIL|TypeError:|ReferenceError:|is not a type|Cannot assign to non-existent property' "$output/graphics-pam.log" "$output/pam-error.log"; then status=1; fi
python - <<'PY'
import base64,pathlib
for p in pathlib.Path('native-results').glob('*.png'):
    print('NATIVE_SCREENSHOT '+p.name+' '+base64.b64encode(p.read_bytes()).decode())
PY
exit "$status"
