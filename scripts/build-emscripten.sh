#!/usr/bin/env bash
# Build SDL3 for Emscripten (wasm): STATIC, Release. PUBLISH-ONLY for now — the
# consuming runtime has no wasm host target yet (phase9 §5 P9.5 calls this out
# explicitly); the artifact exists so a future web target starts from the same
# commit-pinned, immutable-release flow as every other platform.
#
# Requires an activated emsdk (the workflow uses mymindstorm/setup-emsdk; locally:
# source <emsdk>/emsdk_env.sh first). emcmake must be on PATH.
#
#   scripts/build-emscripten.sh <sdl-src-dir> <out-dir>
#
# Output: <out-dir>/sdl3-emscripten-Release.tar.gz
#   containing lib/libSDL3.a (wasm) + include/SDL3 + the CMake package config.
set -euo pipefail
SRC="${1:?usage: build-emscripten.sh <sdl-src-dir> <out-dir>}"
OUT="${2:?usage: build-emscripten.sh <sdl-src-dir> <out-dir>}"
command -v emcmake > /dev/null 2>&1 || { echo "FAIL: emcmake not on PATH — activate emsdk first"; exit 1; }
BUILD="$OUT/build-emscripten"
STAGE="$OUT/stage-emscripten"
rm -rf "$BUILD" "$STAGE"

emcmake cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSDL_STATIC=ON -DSDL_SHARED=OFF \
  -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF \
  -DCMAKE_INSTALL_PREFIX="$STAGE"
cmake --build "$BUILD" --parallel
cmake --install "$BUILD"

[ -f "$STAGE/lib/libSDL3.a" ] || { echo "FAIL: libSDL3.a missing after install"; exit 1; }
[ -f "$STAGE/lib/cmake/SDL3/SDL3Config.cmake" ] || { echo "FAIL: cmake package config missing"; exit 1; }
# CMAKE_SYSTEM_NAME is not a CACHE variable — the cached proof of an emscripten
# cross-compile is the toolchain file emcmake injected.
grep -q 'CMAKE_TOOLCHAIN_FILE:FILEPATH=.*Emscripten\.cmake' "$BUILD/CMakeCache.txt" \
  || { echo "FAIL: build was not an Emscripten cross-compile (no Emscripten toolchain in the cache)"; exit 1; }

{ echo "source-commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "config: Release static wasm (emscripten: $(emcc --version | head -1))"
  echo "note: PUBLISH-ONLY — no consumer in threejs-native-runtime yet (phase9 P9.5)"
} > "$STAGE/MANIFEST.txt"

tar -C "$STAGE" -czf "$OUT/sdl3-emscripten-Release.tar.gz" .
echo "artifact: $OUT/sdl3-emscripten-Release.tar.gz ($(du -h "$OUT/sdl3-emscripten-Release.tar.gz" | cut -f1))"
