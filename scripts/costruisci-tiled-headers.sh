#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake -S "$ROOT/native/tiled-headers" -B "$ROOT/native/tiled-headers/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/native/tiled-headers/build" --parallel 2
cmake --install "$ROOT/native/tiled-headers/build" --prefix "$ROOT"
