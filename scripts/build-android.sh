#!/usr/bin/env bash
# Build SDL3 for Android: SHARED libSDL3.so per ABI, Release.
#
# Part of the threejs-native-runtime prebuilt-SDK pipeline (phase 9). Android is the
# one platform where SDL MUST be shared (SDL's Java activity System.loadLibrary's
# libSDL3.so before libmain.so), and where the Java classes shipped in the app MUST
# come from the same SDL commit as the .so — a mismatch dies at startup with
# NoSuchMethodError on nativeSetupJNI. The runtime keeps taking the Java layer from
# its commit-pinned submodule; this artifact carries only the native side, so the
# commit-pinned fetch keeps both sides matched by construction.
#
# Flags mirror the consuming app's gradle exactly: android-24, c++_static.
#
#   scripts/build-android.sh <sdl-src-dir> <out-dir>     (needs ANDROID_NDK_LATEST_HOME
#                                                         or ANDROID_NDK_HOME)
#
# Output: <out-dir>/sdl3-android-Release.tar.gz
#   containing <abi>/{lib/libSDL3.so, lib/cmake/SDL3, include/SDL3} for
#   arm64-v8a and armeabi-v7a, each a full `cmake --install` tree.
set -euo pipefail
SRC="${1:?usage: build-android.sh <sdl-src-dir> <out-dir>}"
OUT="${2:?usage: build-android.sh <sdl-src-dir> <out-dir>}"
NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}"
[ -n "$NDK" ] && [ -f "$NDK/build/cmake/android.toolchain.cmake" ] \
  || { echo "FAIL: no Android NDK (set ANDROID_NDK_LATEST_HOME or ANDROID_NDK_HOME)"; exit 1; }
STAGE="$OUT/stage-android"
rm -rf "$STAGE"

for ABI in arm64-v8a armeabi-v7a; do
  BUILD="$OUT/build-android-$ABI"
  rm -rf "$BUILD"
  cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM=android-24 \
    -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF \
    -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" \
    -DCMAKE_INSTALL_PREFIX="$STAGE/$ABI"
  cmake --build "$BUILD" --parallel
  cmake --install "$BUILD"
  [ -f "$STAGE/$ABI/lib/libSDL3.so" ] || { echo "FAIL: $ABI libSDL3.so missing"; exit 1; }
  [ -f "$STAGE/$ABI/lib/cmake/SDL3/SDL3Config.cmake" ] || { echo "FAIL: $ABI cmake package config missing"; exit 1; }
done

# 16 KB page sizes (runtime phase11 P11.1): Google Play requires 16 KB-aligned
# 64-bit libraries from API 35. The flags above make it explicit for BOTH ABIs
# (harmless on 32-bit: alignment is a multiple of the 4 KB page); this assert
# makes the artifact unable to ship misaligned regardless of the NDK's defaults.
OBJDUMP=$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-objdump | head -1)
for ABI in arm64-v8a armeabi-v7a; do
  MIN=$("$OBJDUMP" -p "$STAGE/$ABI/lib/libSDL3.so" | grep -E '^\s*LOAD' | grep -Eo 'align 2\*\*[0-9]+' | grep -Eo '[0-9]+$' | sort -un | head -1)
  [ -n "$MIN" ] && [ "$MIN" -ge 14 ] || { echo "FAIL: $ABI libSDL3.so LOAD align 2**${MIN:-none} < 16 KB"; exit 1; }
  echo "16 KB check: $ABI libSDL3.so min LOAD align 2**$MIN"
done

# Each .so must be the machine it claims (the fleet is mixed-ABI; a wrong-arch lib
# only fails at install/launch time on a user's device).
file "$STAGE/arm64-v8a/lib/libSDL3.so" | grep -q 'aarch64' || { echo "FAIL: arm64-v8a .so is not aarch64"; exit 1; }
file "$STAGE/armeabi-v7a/lib/libSDL3.so" | grep -qE 'ARM(,| )' || { echo "FAIL: armeabi-v7a .so is not 32-bit ARM"; exit 1; }

{ echo "source-commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "config: Release shared per-ABI (arm64-v8a, armeabi-v7a), android-24, c++_static, 16 KB max-page-size (both ABIs, asserted)"
  echo "note: Java classes must come from the SAME SDL commit (the runtime's submodule pin)"
} > "$STAGE/MANIFEST.txt"

tar -C "$STAGE" -czf "$OUT/sdl3-android-Release.tar.gz" .
echo "artifact: $OUT/sdl3-android-Release.tar.gz ($(du -h "$OUT/sdl3-android-Release.tar.gz" | cut -f1))"
