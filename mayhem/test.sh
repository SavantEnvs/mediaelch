#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Both Catch2 suites were built by build.sh (normal flags). We parse each suite's own summary line:
# a neutered/missing binary prints no summary, which is counted as a failure rather than a pass.
export QT_QPA_PLATFORM=offscreen
BUILD="$SRC/mayhem/build-tests"
UNIT="$BUILD/test/unit/mediaelch_unit_test"
INTEG="$BUILD/test/integration/mediaelch_test_integration"
for bin in "$UNIT" "$INTEG"; do
  [ -x "$bin" ] || { echo "missing test binary $bin (build.sh should have built it)" >&2; emit_ctrf "catch2" 0 1 0; exit 1; }
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

passed=0; failed=0; skipped=0

# run_suite <min-test-cases> <command...>: adds the suite's case counts to the totals.
run_suite() {
  local min="$1"; shift
  local out cases p f s
  out="$("$@" 2>&1)" || true
  printf '%s\n' "$out" | tail -n 6
  if printf '%s\n' "$out" | grep -q '^All tests passed'; then
    cases="$(printf '%s\n' "$out" | sed -n 's/^All tests passed (.* assertions\? in \([0-9]*\) test cases\?).*/\1/p' | tail -n1)"
    p="$cases"; f=0; s=0
  elif printf '%s\n' "$out" | grep -q '^test cases:'; then
    local line
    line="$(printf '%s\n' "$out" | grep '^test cases:' | tail -n1)"
    p="$(printf '%s' "$line" | sed -n 's/.*| *\([0-9]*\) passed.*/\1/p')"
    f="$(printf '%s' "$line" | sed -n 's/.*| *\([0-9]*\) failed.*/\1/p')"
    s="$(printf '%s' "$line" | sed -n 's/.*| *\([0-9]*\) skipped.*/\1/p')"
  else
    echo "no Catch2 summary line found for: $*" >&2
    p=0; f=1; s=0
  fi
  p="${p:-0}"; f="${f:-0}"; s="${s:-0}"
  if [ $((p + f + s)) -lt "$min" ]; then
    echo "suite ran only $((p + f + s)) test cases (expected >= $min): $*" >&2
    f=$((f + 1))
  fi
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + s))
}

run_suite 40 "$UNIT"
# "[database]" compares SQLite's generated schema text with a reference file and depends on the
# system SQLite version, not on MediaElch's code.
run_suite 8 "$INTEG" "~[database]" --resource-dir "$SRC/test/resources" --temp-dir "$TMP_DIR"

emit_ctrf "catch2" "$passed" "$failed" "$skipped"
