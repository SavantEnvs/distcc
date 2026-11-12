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

TEST_BIN=/mayhem/test-bin
for b in distcc distccd h_scanargs h_hosts h_strip h_parsemask h_dotd h_exten h_issource h_getline; do
  [ -x "$TEST_BIN/$b" ] || { echo "missing $TEST_BIN/$b — mayhem/build.sh should have built it" >&2; emit_ctrf "distcc" 0 1 0; exit 1; }
done
export PATH="$TEST_BIN:$PATH"
export PYTHONPATH="$SRC/test"
export PYTHONDONTWRITEBYTECODE=1

passed=0 ; failed=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# 1) Upstream's own comfychair cases for the pure-function test drivers (no daemon, no compiler run).
for c in VersionOption_Case HelpOption_Case BogusOption_Case StripArgs_Case IsSource_Case ScanArgs_Case \
         ExtractExtension_Case InvalidHostSpec_Case ParseHostSpec_Case ParseMask_Case Getline_Case; do
  out="$(timeout 300 python3 "$SRC/test/onetest.py" "$c" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qE "^$c +OK\$"; then
    passed=$((passed+1)); echo "PASS $c"
  else
    failed=$((failed+1)); echo "FAIL $c (rc=$rc)"; printf '%s\n' "$out" | tail -15
  fi
done

# 2) Known-answer probes: the test drivers must print exactly the documented decision/parse result.
kat() {  # kat <name> <expected stdout> <cmd...>
  local name="$1" want="$2" got; shift 2
  got="$("$@" 2>/dev/null)"
  if [ "$got" = "$want" ]; then passed=$((passed+1)); echo "PASS $name"
  else failed=$((failed+1)); echo "FAIL $name: want [$want] got [$got]"; fi
}
katrc() {  # katrc <name> <expected exit code> <cmd...>
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq "$want" ]; then passed=$((passed+1)); echo "PASS $name"
  else failed=$((failed+1)); echo "FAIL $name: want rc=$want got rc=$rc"; fi
}

kat scan_compile  "distribute foo.c foo.o" h_scanargs gcc -c foo.c -o foo.o
kat scan_implied_o "distribute foo.c foo.o" h_scanargs gcc -c foo.c
kat scan_asm       "distribute foo.c foo.s" h_scanargs gcc -S foo.c
kat scan_cpp_local "local (NULL) (NULL)" h_scanargs gcc -E foo.c
kat scan_link_local "local (NULL) foo.o" h_scanargs gcc foo.o -o prog
kat scan_x_asm_local "local (NULL) (NULL)" h_scanargs gcc -x assembler -c foo.s
kat strip_cpp_opts "gcc -Wall -c foo.c -o foo.o" h_strip gcc -DFOO -I/inc -Wall -c foo.c -o foo.o -MD -MF x.d
kat dotd_md  "{'dotd_fname':'foo.d', 'needs_dotd':1, 'sets_dotd_target':0, 'dotd_target':'None'}" \
    h_dotd dcc_get_dotd_info gcc -c foo.c -o foo.o -MD
kat dotd_mf_mt "{'dotd_fname':'bar.d', 'needs_dotd':1, 'sets_dotd_target':1, 'dotd_target':'None'}" \
    h_dotd dcc_get_dotd_info gcc -c foo.c -MD -MF bar.d -MT t
kat dotd_none "{'dotd_fname':'/x/y.d', 'needs_dotd':0, 'sets_dotd_target':0, 'dotd_target':'None'}" \
    h_dotd dcc_get_dotd_info gcc -c /a/b/foo.c -o /x/y.o
kat hosts_parse "$(printf '3\n   3 LOCAL\n   4 TCP red 3633\n   4 SSH user blue /usr/bin/ssh/2')" \
    env DISTCC_HOSTS="localhost/3 red:3633/4 user@blue:/usr/bin/ssh/2" h_hosts
katrc hosts_bad_multiplier 106 env DISTCC_HOSTS="a/b/c:::" h_hosts
katrc mask_allowed 0   h_parsemask 10.0.0.0/8 10.1.2.3
katrc mask_denied  113 h_parsemask 192.168.0.0/16 10.1.2.3
kat exten_source ".bar" h_exten foo.c.bar
kat issource_c   "source not-preprocessed" h_issource foo.cc
kat issource_txt "not-source not-preprocessed" h_issource foo.txt

emit_ctrf "distcc-comfychair+kat" "$passed" "$failed" 0
