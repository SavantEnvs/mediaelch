#!/usr/bin/env bash
#
# mayhem/build.sh — builds (1) the libFuzzer + standalone harnesses against a sanitized
# libmediaelch and (2) MediaElch's own Catch2 suites with normal flags (for mayhem/test.sh).
# Everything resolves from apt-installed -dev packages baked into the image, so a re-run is offline.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS SRC

# The Qt platform plugin (and CTest's post-build test discovery) needs a display-less backend.
export QT_QPA_PLATFORM=offscreen

cd "$SRC"

# CMake caches the compiler's absolute path, and a different one (e.g. the ccache pre-fill's
# masquerade dir vs /usr/bin) makes it wipe the cache and re-configure from scratch, which fails.
# Start such a tree clean instead, so re-running build.sh is idempotent.
reset_if_compiler_changed() {
  local cache="$1/CMakeCache.txt" cached
  [ -f "$cache" ] || return 0
  cached="$(sed -n 's/^CMAKE_CXX_COMPILER:[A-Z]*=//p' "$cache")"
  [ "$cached" = "$(command -v "$CXX")" ] || rm -rf "$1"
}
reset_if_compiler_changed mayhem/build-fuzz
reset_if_compiler_changed mayhem/build-tests

COMMON_ARGS=(
  -G Ninja
  -DENABLE_COLOR_OUTPUT=OFF
  -DMEDIAELCH_FORCE_QT6=ON
  -DUSE_EXTERN_QUAZIP=ON   # the third_party/quazip submodule is not part of the fork's tree
  -DDISABLE_UPDATER=ON
  -DCMAKE_C_COMPILER="$CC"
  -DCMAKE_CXX_COMPILER="$CXX"
)

# 1) Sanitized + SanCov-instrumented library and the harnesses (the harnesses are injected through
#    CMAKE_PROJECT_INCLUDE so upstream's CMakeLists.txt stays untouched). Debug build type, so Qt does
#    not define QT_NO_DEBUG: Q_ASSERT, assert() and MediaElch_Debug_{Expects,Ensures,Assert,Unreachable}
#    stay live (-O1 via the _DEBUG flags, no -DNDEBUG).
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
cmake -S . -B mayhem/build-fuzz "${COMMON_ARGS[@]}" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PROJECT_INCLUDE="$SRC/mayhem/fuzz_targets.cmake" \
  -DMAYHEM_LSAN_OFF="$SRC/mayhem/lsan_off.cc" \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_C_FLAGS_DEBUG="-O1" \
  -DCMAKE_CXX_FLAGS_DEBUG="-O1" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"

FUZZ_TARGETS=()
for n in movie_nfo tvshow_nfo episode_nfo concert_nfo album_nfo artist_nfo advanced_settings placeholder_parser; do
  FUZZ_TARGETS+=("fuzz_$n" "fuzz_$n-standalone")
done
cmake --build mayhem/build-fuzz -j"$MAYHEM_JOBS" --target "${FUZZ_TARGETS[@]}"

# 2) The project's own test suites, normal flags (no sanitizers, no -gdwarf-3).
cmake -S . -B mayhem/build-tests "${COMMON_ARGS[@]}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_TESTS=ON \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build mayhem/build-tests -j"$MAYHEM_JOBS" --target mediaelch_unit_test mediaelch_test_integration
