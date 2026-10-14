#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake -S "$ROOT/native/window-identity" -B "$ROOT/native/window-identity/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/native/window-identity/build" --parallel 2
cmake --install "$ROOT/native/window-identity/build" --prefix "$ROOT"
