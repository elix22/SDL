#!/usr/bin/env bash
# Build SDL3 for macOS: STATIC, UNIVERSAL (arm64 + x86_64), Release-only.
#
# Part of the threejs-native-runtime prebuilt-SDK pipeline (phase 9): CI runs this and
# publishes the result as a GitHub Release asset; the runtime's fetch-libs step downloads
# it into its gitignored libs/ folder. Users can also run it locally — the output layout
# is identical, so a local build is a drop-in overwrite of the fetched one.
#
#   scripts/build-macos.sh <sdl-src-dir> <out-dir>
#
# Output: <out-dir>/sdl3-macos-universal-Release.tar.gz
#   containing lib/libSDL3.a (universal) + include/SDL3 + the CMake package config.
set -euo pipefail
SRC="${1:?usage: build-macos.sh <sdl-src-dir> <out-dir>}"
OUT="${2:?usage: build-macos.sh <sdl-src-dir> <out-dir>}"
BUILD="$OUT/build-macos"
STAGE="$OUT/stage-macos"
rm -rf "$BUILD" "$STAGE"

cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DSDL_STATIC=ON -DSDL_SHARED=OFF \
  -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF \
  -DCMAKE_INSTALL_PREFIX="$STAGE"
cmake --build "$BUILD" --parallel
cmake --install "$BUILD"

# The artifact must actually be what it claims: static, present, and BOTH architectures.
# (A single-arch lib here would surface much later as a "cannot link for x86_64" on some
# user's Intel Mac — fail in CI instead.)
LIB="$STAGE/lib/libSDL3.a"
[ -f "$LIB" ] || { echo "FAIL: $LIB missing after install"; exit 1; }
ARCHS=$(lipo -archs "$LIB")
echo "libSDL3.a archs: $ARCHS"
case "$ARCHS" in *arm64*) ;; *) echo "FAIL: arm64 slice missing"; exit 1 ;; esac
case "$ARCHS" in *x86_64*) ;; *) echo "FAIL: x86_64 slice missing"; exit 1 ;; esac

# Provenance: which source produced this binary (the fetch pipeline pins by commit).
{ echo "source-commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "config: Release static universal (arm64;x86_64)"
} > "$STAGE/MANIFEST.txt"

tar -C "$STAGE" -czf "$OUT/sdl3-macos-universal-Release.tar.gz" .
echo "artifact: $OUT/sdl3-macos-universal-Release.tar.gz ($(du -h "$OUT/sdl3-macos-universal-Release.tar.gz" | cut -f1))"
