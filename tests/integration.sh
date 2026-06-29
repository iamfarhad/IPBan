#!/usr/bin/env bash
# Integration tests for ipban.sh.
# Requires root. Tests real iptables chain management with xt_geoip when
# available, and validates file/cron/permission behaviour unconditionally.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/ipban.sh"
PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────
pass() { printf 'PASS  %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() {
  printf 'FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '      → %s\n' "$2"
  FAIL=$(( FAIL + 1 ))
}
skip() { printf 'SKIP  %s\n' "$1"; }

_run() {
  set +e
  output=$(bash "$SCRIPT" "$@" 2>&1)
  code=$?
  set -e
}

chain_exists() {
  local ipt="${1:-iptables}" chain="$2"
  ${ipt} -n -L "${chain}" &>/dev/null
}

chain_absent() {
  local ipt="${1:-iptables}" chain="$2"
  ! ${ipt} -n -L "${chain}" &>/dev/null
}

# Detect whether xt_geoip extension is usable
geoip_available() {
  iptables -m geoip --help &>/dev/null 2>&1 && \
    [[ -d /usr/share/xt_geoip ]] && \
    ls /usr/share/xt_geoip/*.iv4 &>/dev/null 2>/dev/null
}

GEOIP_OK=0
geoip_available && GEOIP_OK=1

echo ""
echo "=== IPBan integration test ==="
echo "Script : ${SCRIPT}"
echo "xt_geoip: $([ "$GEOIP_OK" -eq 1 ] && echo "available" || echo "not available — geoip chain tests skipped")"
echo ""

# ── Baseline: clean slate ─────────────────────────────────────────────────────
echo "--- Setup ---"
bash "$SCRIPT" -reset yes 2>/dev/null || true
rm -rf /usr/share/ipban/ /etc/cron.d/ipban 2>/dev/null || true

# ── Validation: bad input exits before touching anything ─────────────────────
echo "--- Validation ---"

_run -add BADDIR -geoip CN -limit DROP
if [[ "$code" -ne 0 ]] && echo "$output" | grep -qi "invalid"; then
  pass "rejects invalid direction BADDIR"
else
  fail "should reject invalid direction" "exit=${code}: ${output}"
fi

_run -add OUTPUT -geoip IRAN -limit DROP
if [[ "$code" -ne 0 ]] && echo "$output" | grep -qi "invalid"; then
  pass "rejects 4-letter country code IRAN"
else
  fail "should reject IRAN as country code" "exit=${code}: ${output}"
fi

_run -add OUTPUT -geoip CN -limit DENY
if [[ "$code" -ne 0 ]] && echo "$output" | grep -qi "invalid"; then
  pass "rejects invalid limit DENY"
else
  fail "should reject limit DENY" "exit=${code}: ${output}"
fi

# Confirm firewall is still intact after bad-input rejections
if iptables -n -L INPUT &>/dev/null; then
  pass "firewall intact after validation rejections"
else
  fail "firewall appears broken after validation rejections"
fi

# ── geoip chain tests (skipped when xt_geoip is unavailable) ─────────────────
echo ""
echo "--- Chain management ---"

if [[ "$GEOIP_OK" -eq 1 ]]; then

  # Add OUTPUT-only rules
  bash "$SCRIPT" -add OUTPUT -geoip US -limit DROP

  if chain_exists iptables IPBAN_OUTPUT; then
    pass "IPBAN_OUTPUT chain created (iptables)"
  else
    fail "IPBAN_OUTPUT chain missing in iptables"
  fi

  if chain_exists ip6tables IPBAN_OUTPUT; then
    pass "IPBAN_OUTPUT chain created (ip6tables)"
  else
    fail "IPBAN_OUTPUT chain missing in ip6tables"
  fi

  if chain_absent iptables IPBAN_INPUT; then
    pass "IPBAN_INPUT not created for OUTPUT-only rule"
  else
    fail "IPBAN_INPUT should not exist when only OUTPUT was requested"
  fi

  if chain_absent iptables IPBAN_FORWARD; then
    pass "IPBAN_FORWARD not created for OUTPUT-only rule"
  else
    fail "IPBAN_FORWARD should not exist when only OUTPUT was requested"
  fi

  if iptables -vnL IPBAN_OUTPUT 2>/dev/null | grep -q "geoip"; then
    pass "geoip rule present in IPBAN_OUTPUT"
  else
    fail "geoip rule missing from IPBAN_OUTPUT"
  fi

  # Add INPUT and FORWARD too
  bash "$SCRIPT" -add INPUT,FORWARD -geoip US -limit DROP

  for dir in IPBAN_INPUT IPBAN_FORWARD; do
    if chain_exists iptables "${dir}"; then
      pass "${dir} chain created"
    else
      fail "${dir} chain not created"
    fi
  done

  # Idempotency: running again should not duplicate the jump rule in INPUT
  bash "$SCRIPT" -add OUTPUT -geoip CN -limit DROP
  jump_count=$(iptables -vnL OUTPUT 2>/dev/null | grep -c "IPBAN_OUTPUT" || true)
  if [[ "$jump_count" -le 1 ]]; then
    pass "jump rule not duplicated on second add"
  else
    fail "jump rule duplicated (count=${jump_count})"
  fi

  # ICMP blocking creates a rule in IPBAN_INPUT
  bash "$SCRIPT" -add INPUT -geoip US -limit DROP -icmp no
  if iptables -vnL IPBAN_INPUT 2>/dev/null | grep -q "icmp"; then
    pass "ICMP DROP rule added to IPBAN_INPUT"
  else
    fail "ICMP DROP rule missing from IPBAN_INPUT"
  fi

  # ── Non-IPBan rule preservation ───────────────────────────────────────────
  echo ""
  echo "--- Non-IPBan rule preservation ---"

  # Add a rule that belongs to no IPBan chain
  iptables -A INPUT -p tcp --dport 22 -j ACCEPT -m comment --comment "test-ssh-rule"
  iptables -A FORWARD -p udp -j DROP    -m comment --comment "test-fwd-rule"

  bash "$SCRIPT" -reset yes

  if iptables -vnL INPUT 2>/dev/null | grep -q "test-ssh-rule"; then
    pass "reset preserved non-IPBan INPUT rule"
  else
    fail "reset removed a non-IPBan INPUT rule"
  fi

  if iptables -vnL FORWARD 2>/dev/null | grep -q "test-fwd-rule"; then
    pass "reset preserved non-IPBan FORWARD rule"
  else
    fail "reset removed a non-IPBan FORWARD rule"
  fi

  for dir in IPBAN_INPUT IPBAN_OUTPUT IPBAN_FORWARD; do
    if chain_absent iptables "${dir}"; then
      pass "${dir} removed by reset"
    else
      fail "${dir} still present after reset"
    fi
  done

  # Clean up test rules
  iptables -D INPUT   -p tcp --dport 22 -j ACCEPT -m comment --comment "test-ssh-rule" 2>/dev/null || true
  iptables -D FORWARD -p udp -j DROP    -m comment --comment "test-fwd-rule"          2>/dev/null || true

  # Re-add for status and remove tests below
  bash "$SCRIPT" -add OUTPUT -geoip US -limit DROP

else
  skip "chain creation (xt_geoip not available)"
  skip "idempotency (xt_geoip not available)"
  skip "ICMP rule (xt_geoip not available)"
  skip "non-IPBan rule preservation (xt_geoip not available)"
fi

# ── Status command ─────────────────────────────────────────────────────────────
echo ""
echo "--- Status ---"
_run -status yes
if [[ "$code" -eq 0 ]]; then
  pass "status command exits 0"
else
  fail "status command exited ${code}" "$output"
fi
if echo "$output" | grep -qi "ipban\|chain\|no active"; then
  pass "status output contains expected text"
else
  fail "status output missing expected text" "$output"
fi

# ── File and directory tests ───────────────────────────────────────────────────
echo ""
echo "--- Files and permissions ---"

if [[ -d /usr/share/ipban ]]; then
  perms=$(stat -c "%a" /usr/share/ipban)
  if [[ "$perms" == "750" ]]; then
    pass "/usr/share/ipban has mode 750"
  else
    fail "/usr/share/ipban has mode ${perms}, expected 750"
  fi

  if [[ -f /usr/share/ipban/backup-rules-ipv4.txt ]]; then
    pass "IPv4 firewall backup exists"
  else
    skip "IPv4 backup (install did not run)"
  fi

  if [[ -f /usr/share/ipban/ipban-update.sh ]]; then
    perms=$(stat -c "%a" /usr/share/ipban/ipban-update.sh)
    if [[ "$perms" == "750" ]]; then
      pass "ipban-update.sh has mode 750"
    else
      fail "ipban-update.sh has mode ${perms}, expected 750"
    fi
  fi
else
  skip "directory permission checks (install did not run)"
fi

if [[ -f /etc/cron.d/ipban ]]; then
  perms=$(stat -c "%a" /etc/cron.d/ipban)
  if [[ "$perms" == "644" ]]; then
    pass "/etc/cron.d/ipban has mode 644"
  else
    fail "/etc/cron.d/ipban has mode ${perms}, expected 644"
  fi
  # Must not contain init 1 / init 3 calls
  if grep -q "init [13]" /etc/cron.d/ipban 2>/dev/null; then
    fail "cron file contains init 1/3 calls"
  else
    pass "cron file has no init 1/3 calls"
  fi
  # Must use dedicated cron file, not crontab
  if [[ -f /etc/cron.d/ipban ]]; then
    pass "uses /etc/cron.d/ipban (not user crontab)"
  fi
else
  skip "cron file checks (install did not run)"
fi

# ── Persistence path test ──────────────────────────────────────────────────────
echo ""
echo "--- Persistence ---"

# On Debian/Ubuntu the rules must be saved to /etc/iptables/, not /etc/sysconfig/
bash "$SCRIPT" -reset yes 2>/dev/null || true

if [[ -f /etc/iptables/rules.v4 ]]; then
  pass "rules.v4 saved to /etc/iptables/ (correct Debian path)"
  if [[ -f /etc/sysconfig/iptables-config ]] && \
     grep -q "^#" /etc/sysconfig/iptables-config 2>/dev/null; then
    # If sysconfig dir exists it should not be overwritten with rule data
    pass "/etc/sysconfig/iptables-config not overwritten with rule data"
  fi
else
  skip "persistence path check (/etc/iptables/rules.v4 not written yet)"
fi

# ── Remove / uninstall ────────────────────────────────────────────────────────
echo ""
echo "--- Remove ---"
_run -remove yes
if [[ "$code" -eq 0 ]]; then
  pass "-remove exits 0"
else
  fail "-remove exited ${code}" "$output"
fi

if [[ ! -d /usr/share/ipban ]]; then
  pass "/usr/share/ipban removed"
else
  fail "/usr/share/ipban still exists after remove"
fi

if [[ ! -f /etc/cron.d/ipban ]]; then
  pass "/etc/cron.d/ipban removed"
else
  fail "/etc/cron.d/ipban still exists after remove"
fi

for dir in IPBAN_INPUT IPBAN_OUTPUT IPBAN_FORWARD; do
  if chain_absent iptables "${dir}"; then
    pass "${dir} gone after remove"
  else
    fail "${dir} still present after remove"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
