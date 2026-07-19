#!/usr/bin/env bash
# Build SDL3 for Linux x64: STATIC, Release.
#
# Part of the threejs-native-runtime prebuilt-SDK pipeline (phase 9). The X11/Wayland/
# audio -dev packages must be installed BEFORE this runs (the workflow does it; the
# list mirrors the consuming runtime's ci.yml) — SDL disables at CONFIGURE time any
# video/audio driver whose headers are missing, and a silently X11-less libSDL3.a
# would only fail at app runtime on a user's desktop. The asserts below catch that
# here instead.
#
#   scripts/build-linux.sh <sdl-src-dir> <out-dir>
#
# Output: <out-dir>/sdl3-linux-x64-Release.tar.gz
#   containing lib/libSDL3.a + include/SDL3 + the CMake package config.
set -euo pipefail
SRC="${1:?usage: build-linux.sh <sdl-src-dir> <out-dir>}"
OUT="${2:?usage: build-linux.sh <sdl-src-dir> <out-dir>}"
BUILD="$OUT/build-linux"
STAGE="$OUT/stage-linux"
rm -rf "$BUILD" "$STAGE"

cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSDL_STATIC=ON -DSDL_SHARED=OFF \
  -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF \
  -DCMAKE_INSTALL_PREFIX="$STAGE"

# The drivers the consuming runtime depends on must have been detected — fail the
# publish, not some user's first launch.
grep -q 'SDL_X11 *(TRUE)\|VIDEO_X11.*ON\|SDL_VIDEO_DRIVER_X11' "$BUILD/CMakeCache.txt" "$BUILD/include-config-release/build_config/SDL_build_config.h" 2>/dev/null \
  || grep -rq '#define SDL_VIDEO_DRIVER_X11' "$BUILD" \
  || { echo "FAIL: X11 video driver not enabled — install the X11 -dev packages first"; exit 1; }

cmake --build "$BUILD" --parallel
cmake --install "$BUILD"

[ -f "$STAGE/lib/libSDL3.a" ] || { echo "FAIL: libSDL3.a missing after install"; exit 1; }
[ -f "$STAGE/lib/cmake/SDL3/SDL3Config.cmake" ] || { echo "FAIL: cmake package config missing"; exit 1; }

{ echo "source-commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "config: Release static x64 (X11 asserted; Wayland/audio per installed -dev packages)"
} > "$STAGE/MANIFEST.txt"

tar -C "$STAGE" -czf "$OUT/sdl3-linux-x64-Release.tar.gz" .
echo "artifact: $OUT/sdl3-linux-x64-Release.tar.gz ($(du -h "$OUT/sdl3-linux-x64-Release.tar.gz" | cut -f1))"
