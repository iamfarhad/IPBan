#!/usr/bin/env bash
# Unit tests for ipban.sh validation logic.
# Tests run the script as a subprocess with bad/good arguments and assert
# exit codes and error message content. No iptables or xt_geoip needed.
# Run with: sudo bash tests/unit.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/ipban.sh"
PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────
_run() {
  set +e
  output=$(bash "$SCRIPT" "$@" 2>&1)
  code=$?
  set -e
}

pass() { printf 'PASS  %s\n' "$1"; PASS=$(( PASS + 1 )); }

fail() {
  printf 'FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '      → %s\n' "$2"
  FAIL=$(( FAIL + 1 ))
}

# Asserts the script exits non-zero and stderr/stdout matches a pattern.
expect_error() {
  local desc="$1" pattern="$2"; shift 2
  _run "$@"
  if [[ "$code" -eq 0 ]]; then
    fail "$desc" "expected non-zero exit, got 0"; return
  fi
  if ! echo "$output" | grep -qi "$pattern"; then
    fail "$desc" "pattern '${pattern}' not found in: ${output}"; return
  fi
  pass "$desc"
}

# Asserts the script exits 0.
expect_ok() {
  local desc="$1"; shift
  _run "$@"
  if [[ "$code" -ne 0 ]]; then
    fail "$desc" "expected exit 0, got ${code}: ${output}"
  else
    pass "$desc"
  fi
}

# ── Direction validation ───────────────────────────────────────────────────────
echo "--- Direction validation ---"
expect_error "bad direction: OUTPUUT"       "invalid direction"  -add OUTPUUT      -geoip CN -limit DROP
expect_error "bad direction: input (lower)" "invalid direction"  -add input        -geoip CN -limit DROP
expect_error "bad direction: INPU"          "invalid direction"  -add INPU         -geoip CN -limit DROP
expect_error "bad direction: IN,BADDIR"     "invalid direction"  -add "IN,BADDIR"  -geoip CN -limit DROP
expect_error "bad direction: ICMP"          "invalid direction"  -add ICMP         -geoip CN -limit DROP

# ── Country code validation ────────────────────────────────────────────────────
echo "--- Country code validation ---"
expect_error "3-letter code: CHN"    "invalid country"  -add OUTPUT -geoip CHN        -limit DROP
expect_error "full name: IRAN"       "invalid country"  -add OUTPUT -geoip IRAN       -limit DROP
expect_error "lowercase: cn"         "invalid country"  -add OUTPUT -geoip cn         -limit DROP
expect_error "digit in code: C1"     "invalid country"  -add OUTPUT -geoip C1         -limit DROP
expect_error "empty code: CN,"       "invalid country"  -add OUTPUT -geoip "CN,"      -limit DROP
expect_error "space in list: CN IR"  "invalid country"  -add OUTPUT -geoip "CN IR"    -limit DROP

# ── Limit validation ───────────────────────────────────────────────────────────
echo "--- Limit validation ---"
expect_error "bad limit: BAN"        "invalid.*limit"   -add OUTPUT -geoip CN -limit BAN
expect_error "bad limit: DENY"       "invalid.*limit"   -add OUTPUT -geoip CN -limit DENY
expect_error "bad limit: drop (lc)"  "invalid.*limit"   -add OUTPUT -geoip CN -limit drop
expect_error "bad limit: empty"      "invalid.*limit"   -add OUTPUT -geoip CN -limit ""

# ── ICMP validation ────────────────────────────────────────────────────────────
echo "--- ICMP validation ---"
expect_error "bad icmp: maybe"       "invalid.*icmp"    -add OUTPUT -geoip CN -limit DROP -icmp maybe
expect_error "bad icmp: 1"           "invalid.*icmp"    -add OUTPUT -geoip CN -limit DROP -icmp 1
expect_error "bad icmp: YES (upper)" "invalid.*icmp"    -add OUTPUT -geoip CN -limit DROP -icmp YES

# ── Unknown option ─────────────────────────────────────────────────────────────
echo "--- Unknown option ---"
expect_error "unknown option: --foo"  "unknown option"   --foo
expect_error "unknown option: -x"     "unknown option"   -x value

# ── No-arg usage message ───────────────────────────────────────────────────────
echo "--- Usage message ---"
_run
if [[ "$code" -ne 0 ]] && echo "$output" | grep -qi "usage"; then
  pass "no args: prints usage and exits non-zero"
else
  fail "no args: expected usage message and non-zero exit" \
       "exit=${code} output=${output}"
fi

# ── Valid inputs are accepted (validation layer only, exits at module check) ──
echo "--- Valid input accepted by validator ---"
# These reach load_geoip_module which may fail — but the exit message
# should NOT be a validation error (it should be about the module).
_run -add OUTPUT -geoip CN -limit DROP
if echo "$output" | grep -qi "invalid\|must be"; then
  fail "valid args: validation should not reject CN/OUTPUT/DROP" "$output"
else
  pass "valid args CN/OUTPUT/DROP not rejected by validator"
fi

_run -add INPUT,OUTPUT,FORWARD -geoip CN,IR,RU -limit REJECT
if echo "$output" | grep -qi "invalid\|must be"; then
  fail "valid args: validation should not reject multi-dir/multi-country" "$output"
else
  pass "valid args multi-dir/multi-country not rejected by validator"
fi

# LIMIT normalisation: lowercase 'drop' is rejected, confirming exact-case check
_run -add OUTPUT -geoip US -limit DROP
if echo "$output" | grep -qi "invalid.*limit"; then
  fail "DROP should be accepted by validator" "$output"
else
  pass "DROP accepted by validator"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
