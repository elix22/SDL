#!/usr/bin/env bash
# Build SDL3 for iOS: STATIC, Release — device (arm64) + simulator (arm64 + x86_64).
#
# Part of the threejs-native-runtime prebuilt-SDK pipeline (phase 9). The artifact
# carries BOTH forms the consumer needs:
#   device/ , simulator/    — full `cmake --install` trees. The runtime imports the
#                             slice matching its configure via find_package, so SDL's
#                             own SDL3Config.cmake supplies the exact iOS framework
#                             link interface (UIKit/CoreMotion/GameController/...) —
#                             no hand-maintained list to drift.
#   SDL3.xcframework        — the same two static libs in the standard container
#                             (§0.2), for non-CMake consumers and Xcode-first users.
#
#   scripts/build-ios.sh <sdl-src-dir> <out-dir>
#
# Output: <out-dir>/sdl3-ios-static-Release.tar.gz
set -euo pipefail
SRC="${1:?usage: build-ios.sh <sdl-src-dir> <out-dir>}"
OUT="${2:?usage: build-ios.sh <sdl-src-dir> <out-dir>}"
STAGE="$OUT/stage-ios"
rm -rf "$STAGE" "$OUT/build-ios-device" "$OUT/build-ios-sim"
mkdir -p "$STAGE"

# build <builddir> <sysroot> <archs> <prefix>
build_slice() {
  local dir="$1" sysroot="$2" archs="$3" prefix="$4"
  cmake -S "$SRC" -B "$dir" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_STATIC=ON -DSDL_SHARED=OFF \
    -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF \
    -DCMAKE_INSTALL_PREFIX="$prefix"
  cmake --build "$dir" --parallel
  cmake --install "$dir"
  [ -f "$prefix/lib/libSDL3.a" ] || { echo "FAIL: $prefix/lib/libSDL3.a missing"; exit 1; }
  [ -f "$prefix/lib/cmake/SDL3/SDL3Config.cmake" ] || { echo "FAIL: $prefix cmake package config missing"; exit 1; }
}

build_slice "$OUT/build-ios-device" iphoneos        "arm64"        "$STAGE/device"
build_slice "$OUT/build-ios-sim"    iphonesimulator "arm64;x86_64" "$STAGE/simulator"

DEV_ARCHS=$(lipo -archs "$STAGE/device/lib/libSDL3.a")
SIM_ARCHS=$(lipo -archs "$STAGE/simulator/lib/libSDL3.a")
echo "device archs: $DEV_ARCHS / simulator archs: $SIM_ARCHS"
case "$DEV_ARCHS" in *arm64*) ;; *) echo "FAIL: device arm64 slice missing"; exit 1 ;; esac
case "$SIM_ARCHS" in *arm64*) ;; *) echo "FAIL: simulator arm64 slice missing"; exit 1 ;; esac
case "$SIM_ARCHS" in *x86_64*) ;; *) echo "FAIL: simulator x86_64 slice missing"; exit 1 ;; esac

xcodebuild -create-xcframework \
  -library "$STAGE/device/lib/libSDL3.a"    -headers "$STAGE/device/include" \
  -library "$STAGE/simulator/lib/libSDL3.a" -headers "$STAGE/simulator/include" \
  -output "$STAGE/SDL3.xcframework"

{ echo "source-commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "config: Release static (device arm64; sim arm64+x86_64), min iOS 13.0; install trees + xcframework"
} > "$STAGE/MANIFEST.txt"

tar -C "$STAGE" -czf "$OUT/sdl3-ios-static-Release.tar.gz" .
echo "artifact: $OUT/sdl3-ios-static-Release.tar.gz ($(du -h "$OUT/sdl3-ios-static-Release.tar.gz" | cut -f1))"
