#!/usr/bin/env bash
# IPBan v6.0 — github.com/iamfarhad/IPBan
# Ubuntu ≥20 · Debian ≥11 · CentOS Stream 8+ · RHEL 8+ · Fedora
# Usage: ipban.sh -add INPUT,OUTPUT -geoip CN,IR -limit DROP [-icmp no]
set -Eeuo pipefail

# ── Defaults ───────────────────────────────────────────────────────────────────
GEOIP="CN,IR,RU"
LIMIT="DROP"
RESET="n"
REMOVE="n"
ADD=""
ICMP="yes"
UPDATE_DB="n"
STATUS="n"
NO_INSTALL_DEPS="n"

PM=""

IPBAN_DIR="/usr/share/ipban"
GEOIP_DIR="/usr/share/xt_geoip"
CRON_FILE="/etc/cron.d/ipban"

CHAIN_INPUT="IPBAN_INPUT"
CHAIN_OUTPUT="IPBAN_OUTPUT"
CHAIN_FORWARD="IPBAN_FORWARD"

# ── Root check ─────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && echo "Run as root!" && exit 1

# ── Output helpers ─────────────────────────────────────────────────────────────
_success() { echo -e "\e[1;42m $* \e[0m"; }
_error()   { echo -e "\e[1;41m $* \e[0m" >&2; }
_info()    { echo -e "\e[1;44m $* \e[0m"; }
_warning() { echo -e "\e[1;43m $* \e[0m"; }

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -add)             ADD="$2";       shift 2 ;;
    -reset)           RESET="$2";     shift 2 ;;
    -remove)          REMOVE="$2";    shift 2 ;;
    -icmp)            ICMP="$2";      shift 2 ;;
    -geoip)           GEOIP="$2";     shift 2 ;;
    -limit)           LIMIT="$2";     shift 2 ;;
    -update-db)       UPDATE_DB="$2"; shift 2 ;;
    -status)          STATUS="$2";    shift 2 ;;
    --no-install-deps) NO_INSTALL_DEPS="y"; shift 1 ;;
    *) _error "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Input validation ───────────────────────────────────────────────────────────
validate_inputs() {
  LIMIT="${LIMIT^^}"
  GEOIP="${GEOIP^^}"
  GEOIP="${GEOIP// /}"
  ADD="${ADD^^}"
  ADD="${ADD// /}"

  case "$LIMIT" in
    DROP|REJECT|ACCEPT) ;;
    *) _error "Invalid -limit '${LIMIT}'. Must be DROP, REJECT, or ACCEPT."; exit 1 ;;
  esac

  IFS=',' read -ra DIRS <<< "$ADD"
  for dir in "${DIRS[@]}"; do
    case "$dir" in
      INPUT|IN|OUTPUT|OUT|FORWARD|FWD) ;;
      *) _error "Invalid direction '${dir}'. Must be INPUT, OUTPUT, or FORWARD (or IN, OUT, FWD)."; exit 1 ;;
    esac
  done

  IFS=',' read -ra CODES <<< "$GEOIP"
  for code in "${CODES[@]}"; do
    if ! [[ "$code" =~ ^[A-Z]{2}$ ]]; then
      _error "Invalid country code '${code}'. Must be a 2-letter ISO 3166-1 alpha-2 code (e.g. CN, IR, RU)."; exit 1
    fi
  done

  case "$ICMP" in
    yes|no) ;;
    *) _error "Invalid -icmp '${ICMP}'. Must be yes or no."; exit 1 ;;
  esac
}

# ── OS detection ───────────────────────────────────────────────────────────────
detect_os() {
  if type yum &>/dev/null || type dnf &>/dev/null; then
    PM="yum"
  else
    PM="apt"
  fi
}

# ── Package installation ───────────────────────────────────────────────────────
install_dependencies() {
  if [[ "$NO_INSTALL_DEPS" == "y" ]]; then
    _error "Missing dependencies. Install xtables-addons and related packages, then retry."
    exit 1
  fi

  _info "Installing dependencies..."

  if [[ "$PM" == "apt" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get -y update
    DEBIAN_FRONTEND=noninteractive apt-get -y install \
      build-essential \
      "linux-headers-$(uname -r)" \
      curl gzip tar perl \
      xtables-addons-common \
      xtables-addons-dkms \
      libtext-csv-xs-perl \
      libmoosex-types-netaddr-ip-perl \
      libnet-cidr-lite-perl \
      iptables-persistent

    if ! lsmod | grep -q "xt_geoip\|x_tables"; then
      DEBIAN_FRONTEND=noninteractive apt-get -y install module-assistant xtables-addons-source
      module-assistant prepare -f
      module-assistant -f auto-install xtables-addons-source
    fi
  else
    local centosV rhelV fedoraV
    centosV=$(rpm -E '%centos' 2>/dev/null || echo "0")
    rhelV=$(rpm -E '%rhel' 2>/dev/null || echo "0")
    fedoraV=$(rpm -E '%fedora' 2>/dev/null || echo "0")

    if [[ "$centosV" =~ ^[0-9]+$ && "$centosV" -gt 0 ]]; then
      dnf -y install \
        "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${centosV}.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${centosV}.noarch.rpm" || true
    elif [[ "$rhelV" =~ ^[0-9]+$ && "$rhelV" -gt 0 ]]; then
      dnf -y install \
        "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rhelV}.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${rhelV}.noarch.rpm" || true
    elif [[ "$fedoraV" =~ ^[0-9]+$ && "$fedoraV" -gt 0 ]]; then
      dnf -y install \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedoraV}.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedoraV}.noarch.rpm" || true
    fi

    yum -y install \
      "kernel-devel-$(uname -r)" \
      iptables iptables-devel iptables-services \
      perl-Net-CIDR-Lite perl-Text-CSV_XS \
      epel-release epel-next-release || true
    dnf -y install xtables-addons akmod-xtables-addons
    dnf -y install perl-App-cpanminus
    cpanm Net::CIDR::Lite
    cpanm Text::CSV_XS
  fi

  systemctl daemon-reload           2>/dev/null || true
  systemctl enable iptables.service  2>/dev/null || true
  systemctl enable ip6tables.service 2>/dev/null || true
  systemctl enable netfilter-persistent.service 2>/dev/null || true
}

# ── Module loading ─────────────────────────────────────────────────────────────
load_geoip_module() {
  if ! lsmod | grep -q "xt_geoip\|x_tables"; then
    modprobe x_tables 2>/dev/null || true
    modprobe xt_geoip 2>/dev/null || true
  fi
  if ! lsmod | grep -q "xt_geoip\|x_tables"; then
    _error "xt_geoip module is not loaded. Install xtables-addons first."
    exit 1
  fi
}

# ── GeoIP database scripts ─────────────────────────────────────────────────────
write_download_script() {
  cat > "${IPBAN_DIR}/download-build-dbip.sh" <<'DLEOF'
#!/usr/bin/env bash
set -Eeuo pipefail
dtmp="/usr/share/xt_geoip/tmp"
rm -rf "${dtmp}" && mkdir -p "${dtmp}" && cd "${dtmp}"

timestamp=$(date "+%Y-%m")

curl -m 60 -fLo "dbip-country-lite-${timestamp}.csv.gz" \
  "https://download.db-ip.com/free/dbip-country-lite-${timestamp}.csv.gz" || true

if ! curl -m 60 -fLo "GeoIP-legacy.csv.gz" \
    "https://mailfud.org/geoip-legacy/GeoIP-legacy.csv.gz"; then
  curl -m 60 -fLo "GeoIP-legacy.tar.gz" \
    "https://legacy-geoip-csv.ufficyo.com/Legacy-MaxMind-GeoIP-database.tar.gz" || true
fi

gzip -dfq *.gz 2>/dev/null || true
find . -maxdepth 2 -name "*.tar"    -exec tar xf  {} \;
find . -maxdepth 2 -name "*.tar.gz" -exec tar xzf {} \;

if [[ -f "GeoIP-legacy.csv" ]]; then
  tr -d '"' < "GeoIP-legacy.csv" | cut -d, -f1,2,5 > "GeoIP-legacy-processed.csv"
  rm "GeoIP-legacy.csv"
fi

cat *.csv 2>/dev/null | sort -u > "/usr/share/xt_geoip/dbip-country-lite.csv"
rm -rf "${dtmp}"
DLEOF
  chmod 750 "${IPBAN_DIR}/download-build-dbip.sh"
}

write_update_script() {
  cat > "${IPBAN_DIR}/ipban-update.sh" <<'UPDEOF'
#!/usr/bin/env bash
set -Eeuo pipefail
/usr/share/ipban/download-build-dbip.sh
cd /usr/share/xt_geoip/
if [[ -f /usr/libexec/xtables-addons/xt_geoip_build ]]; then
  /usr/libexec/xtables-addons/xt_geoip_build -s
elif [[ -f /usr/lib/xtables-addons/xt_geoip_build ]]; then
  /usr/lib/xtables-addons/xt_geoip_build -D /usr/share/xt_geoip/
fi
rm -f /usr/share/xt_geoip/dbip-country-lite.csv
UPDEOF
  chmod 750 "${IPBAN_DIR}/ipban-update.sh"
}

# ── Firewall chain helpers ─────────────────────────────────────────────────────
normalize_direction() {
  case "$1" in
    IN|INPUT)    echo "INPUT"   ;;
    OUT|OUTPUT)  echo "OUTPUT"  ;;
    FWD|FORWARD) echo "FORWARD" ;;
  esac
}

chain_for_dir() {
  case "$1" in
    INPUT)   echo "${CHAIN_INPUT}"   ;;
    OUTPUT)  echo "${CHAIN_OUTPUT}"  ;;
    FORWARD) echo "${CHAIN_FORWARD}" ;;
  esac
}

ensure_chain() {
  local ipt="$1" chain="$2" hook="$3"
  if ! ${ipt} -n -L "${chain}" &>/dev/null; then
    ${ipt} -N "${chain}"
  fi
  if ! ${ipt} -C "${hook}" -j "${chain}" 2>/dev/null; then
    ${ipt} -I "${hook}" -j "${chain}"
  fi
}

remove_chain() {
  local ipt="$1" chain="$2" hook="$3"
  if ${ipt} -n -L "${chain}" &>/dev/null; then
    ${ipt} -D "${hook}" -j "${chain}" 2>/dev/null || true
    ${ipt} -F "${chain}"
    ${ipt} -X "${chain}"
  fi
}

# ── Rule management ────────────────────────────────────────────────────────────
iptables_add_rules() {
  IFS=',' read -ra DIRS <<< "$ADD"
  for raw_dir in "${DIRS[@]}"; do
    local dir chain cc_flag
    dir=$(normalize_direction "$raw_dir")
    chain=$(chain_for_dir "$dir")
    case "$dir" in
      INPUT|FORWARD) cc_flag="--src-cc" ;;
      OUTPUT)        cc_flag="--dst-cc" ;;
    esac

    for ipt in iptables ip6tables; do
      ensure_chain "$ipt" "$chain" "$dir"
      ${ipt} -A "$chain" -m geoip "$cc_flag" "${GEOIP}" -j "${LIMIT}"
    done
  done

  if [[ "$ICMP" == "no" ]]; then
    for ipt in iptables ip6tables; do
      ensure_chain "$ipt" "${CHAIN_INPUT}" "INPUT"
    done
    iptables  -A "${CHAIN_INPUT}" -p icmp        -j DROP
    ip6tables -A "${CHAIN_INPUT}" -p ipv6-icmp   -j DROP
  fi
}

iptables_reset_ipban() {
  for dir in INPUT OUTPUT FORWARD; do
    local chain
    chain=$(chain_for_dir "$dir")
    for ipt in iptables ip6tables; do
      remove_chain "$ipt" "$chain" "$dir"
    done
  done
}

iptables_status() {
  local found=0
  for ipt in iptables ip6tables; do
    for chain in "${CHAIN_INPUT}" "${CHAIN_OUTPUT}" "${CHAIN_FORWARD}"; do
      if ${ipt} -n -L "${chain}" &>/dev/null; then
        found=1
        echo "--- ${ipt} ${chain} ---"
        ${ipt} -vnL "${chain}"
      fi
    done
  done
  [[ "$found" -eq 0 ]] && _info "No active IPBan chains found."
}

# ── Persistence ────────────────────────────────────────────────────────────────
save_rules() {
  detect_os
  local v4 v6
  if [[ "$PM" == "apt" ]]; then
    v4="/etc/iptables/rules.v4"
    v6="/etc/iptables/rules.v6"
  else
    v4="/etc/sysconfig/iptables"
    v6="/etc/sysconfig/ip6tables"
  fi
  mkdir -p "$(dirname "$v4")"
  iptables-save  | awk '/^COMMIT$/ { delete x }; !x[$0]++' > "$v4"
  ip6tables-save | awk '/^COMMIT$/ { delete x }; !x[$0]++' > "$v6"
  _info "Rules saved to ${v4} / ${v6}."
}

# ── Cron management ────────────────────────────────────────────────────────────
install_cron() {
  local minute hour
  minute=$(( RANDOM % 59 + 1 ))
  hour=$(( RANDOM % 23 + 1 ))
  cat > "${CRON_FILE}" <<EOF
# Managed by ipban.sh — do not edit manually
${minute} ${hour} * * * root ${IPBAN_DIR}/ipban-update.sh >/dev/null 2>&1
EOF
  chmod 644 "${CRON_FILE}"
}

# ── Install ────────────────────────────────────────────────────────────────────
do_install() {
  detect_os
  install_dependencies
  depmod -a

  mkdir -p "${IPBAN_DIR}"
  chmod 750 "${IPBAN_DIR}"
  mkdir -p "${GEOIP_DIR}"
  chmod 750 "${GEOIP_DIR}"

  iptables-save  > "${IPBAN_DIR}/backup-rules-ipv4.txt"
  ip6tables-save > "${IPBAN_DIR}/backup-rules-ipv6.txt"

  load_geoip_module
  write_download_script
  write_update_script
  "${IPBAN_DIR}/ipban-update.sh"
  install_cron

  _success "IPBan installed."
}

# ── Uninstall ──────────────────────────────────────────────────────────────────
do_uninstall() {
  iptables_reset_ipban

  if [[ -f "${IPBAN_DIR}/backup-rules-ipv4.txt" ]]; then
    iptables-restore  < "${IPBAN_DIR}/backup-rules-ipv4.txt"
  fi
  if [[ -f "${IPBAN_DIR}/backup-rules-ipv6.txt" ]]; then
    ip6tables-restore < "${IPBAN_DIR}/backup-rules-ipv6.txt"
  fi

  save_rules
  rm -f "${CRON_FILE}"
  rm -rf "${IPBAN_DIR}"
  _success "IPBan uninstalled."
  exit 0
}

# ── Add rules ──────────────────────────────────────────────────────────────────
do_add() {
  detect_os
  validate_inputs

  if [[ ! -d "${IPBAN_DIR}" ]]; then
    do_install
  else
    load_geoip_module
  fi

  iptables_add_rules
  save_rules
  iptables_status
  _success "Rules added."
}

# ── Reset ──────────────────────────────────────────────────────────────────────
do_reset() {
  iptables_reset_ipban
  save_rules
  _success "IPBan rules removed."
}

# ── Update DB ──────────────────────────────────────────────────────────────────
do_update_db() {
  if [[ ! -f "${IPBAN_DIR}/ipban-update.sh" ]]; then
    _error "IPBan is not installed. Run with -add first."; exit 1
  fi
  "${IPBAN_DIR}/ipban-update.sh"
  _success "GeoIP database updated."
}

# ── Main dispatch ──────────────────────────────────────────────────────────────
ran=0

if [[ -n "$ADD" ]]; then
  do_add; ran=1
fi

if [[ "${RESET,,}"     == "yes" || "${RESET,,}"     == "y" ]]; then
  do_reset; ran=1
fi

if [[ "${REMOVE,,}"    == "yes" || "${REMOVE,,}"    == "y" ]]; then
  do_uninstall; ran=1
fi

if [[ "${UPDATE_DB,,}" == "yes" || "${UPDATE_DB,,}" == "y" ]]; then
  do_update_db; ran=1
fi

if [[ "${STATUS,,}"    == "yes" || "${STATUS,,}"    == "y" ]]; then
  detect_os; iptables_status; ran=1
fi

if [[ "$ran" -eq 0 ]]; then
  cat <<USAGE
Usage: $0 <action> [options]

Actions:
  -add    INPUT|OUTPUT|FORWARD   Add country-based firewall rules
  -reset  yes                    Remove IPBan-managed rules only
  -remove yes                    Uninstall IPBan completely
  -update-db yes                 Refresh GeoIP database without changing rules
  -status yes                    Show active IPBan rules

Options:
  -geoip  CC[,CC,...]            Country codes (default: CN,IR,RU)
  -limit  DROP|REJECT|ACCEPT     Rule action (default: DROP)
  -icmp   yes|no                 Block ICMP via IPBan chains (default: yes)
  --no-install-deps              Fail instead of installing packages

Examples:
  $0 -add OUTPUT -geoip CN,IR -limit DROP
  $0 -add INPUT,OUTPUT,FORWARD -geoip CN,IR,RU -limit DROP -icmp no
  $0 -status yes
  $0 -reset yes
USAGE
  exit 1
fi
