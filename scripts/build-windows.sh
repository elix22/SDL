#!/usr/bin/env bash
# Build SDL3 for Windows x64: STATIC, Release (MSVC).
#
# Part of the threejs-native-runtime prebuilt-SDK pipeline (phase 9). Runs under
# git-bash on a windows-latest runner (or any Windows box with VS + CMake). The
# artifact is SDL's own `cmake --install` tree, so the consumer's find_package gets
# SDL's exact link interface from SDL3Config.cmake — nothing hand-maintained.
#
#   scripts/build-windows.sh <sdl-src-dir> <out-dir>
#
# Output: <out-dir>/sdl3-windows-x64-Release.tar.gz
#   containing lib/SDL3-static.lib + include/SDL3 + the CMake package config.
set -euo pipefail
SRC="${1:?usage: build-windows.sh <sdl-src-dir> <out-dir>}"
OUT="${2:?usage: build-windows.sh <sdl-src-dir> <out-dir>}"
BUILD="$OUT/build-windows"
STAGE="$OUT/stage-windows"
rm -rf "$BUILD" "$STAGE"

# Default generator = newest installed Visual Studio (the ci.yml lesson: hardcoding
# a VS year broke when the runner image moved on).
cmake -S "$SRC" -B "$BUILD" -A x64 \
  -DSDL_STATIC=ON -DSDL_SHARED=OFF \
  -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF \
  -DCMAKE_INSTALL_PREFIX="$STAGE"
cmake --build "$BUILD" --config Release --parallel
cmake --install "$BUILD" --config Release

[ -f "$STAGE/lib/SDL3-static.lib" ] || { echo "FAIL: SDL3-static.lib missing after install"; exit 1; }
# SDL's CMake package lands at <prefix>/cmake on Windows (not lib/cmake/SDL3 as on
# Unix) — accept either, the consumer's find_package handles both.
[ -f "$STAGE/cmake/SDL3Config.cmake" ] || [ -f "$STAGE/lib/cmake/SDL3/SDL3Config.cmake" ] \
  || { echo "FAIL: cmake package config missing"; exit 1; }

{ echo "source-commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "config: Release static x64 (MSVC, newest VS on the runner)"
} > "$STAGE/MANIFEST.txt"

tar -C "$STAGE" -czf "$OUT/sdl3-windows-x64-Release.tar.gz" .
echo "artifact: $OUT/sdl3-windows-x64-Release.tar.gz ($(du -h "$OUT/sdl3-windows-x64-Release.tar.gz" | cut -f1))"
