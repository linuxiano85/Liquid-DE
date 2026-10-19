#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=${LIQUID_MPV_BUILD_DIR:-"$ROOT/native/mpv/build"}
PREFIX=${LIQUID_MPV_PREFIX:-"$ROOT"}
cmake -S "$ROOT/native/mpv" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel 2
cmake --install "$BUILD" --prefix "$PREFIX"
