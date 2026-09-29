#!/usr/bin/env bash
# Builds and runs the firmware host tests (no board needed).
#   arduino/test/run_tests.sh            # uses $CXX, else g++, else clang++
# The sketches are compiled unchanged against the stand-ins in stubs/.
set -euo pipefail
cd "$(dirname "$0")"
CXX="${CXX:-$(command -v g++ || command -v clang++ || true)}"
if [ -z "$CXX" ]; then
  echo "Need a C++17 compiler (set CXX)." >&2
  exit 2
fi
OUT="${TMPDIR:-/tmp}/dorobot-fw-tests"
mkdir -p "$OUT"
FLAGS="-std=c++17 -O0 -g -Wall -Wno-unused-function -I stubs -I ."
status=0
build_run() {
  local name="$1"; shift
  "$CXX" $FLAGS "$@" -o "$OUT/$name" || { status=1; return; }
  "$OUT/$name" || status=1
}
build_run test_uno test_avr.cpp -DBOARD_UNO
build_run test_mega test_avr.cpp -DBOARD_MEGA
build_run test_esp32 test_esp32.cpp
exit $status
