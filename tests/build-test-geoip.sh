#!/usr/bin/env bash
# Build a minimal xt_geoip binary database for CI integration tests.
# Creates a small CSV with real public IP ranges for a few countries,
# then runs xt_geoip_build to produce the binary files iptables expects.
# Exits 0 in all cases — failure just means geoip tests will be skipped.
set -euo pipefail

GEOIP_DIR="/usr/share/xt_geoip"
mkdir -p "${GEOIP_DIR}"
chmod 750 "${GEOIP_DIR}"

CSV="${GEOIP_DIR}/dbip-country-lite.csv"

# Minimal DB-IP lite format: ip_start,ip_end,country_code
# Real public ranges so xt_geoip_build validates the data correctly.
cat > "${CSV}" <<'EOF'
1.0.0.0,1.0.0.255,AU
1.0.1.0,1.0.3.255,CN
1.0.4.0,1.0.7.255,AU
1.0.8.0,1.0.15.255,CN
8.8.8.0,8.8.8.255,US
8.8.4.0,8.8.4.255,US
45.33.32.0,45.33.32.255,US
77.88.0.0,77.88.63.255,RU
91.108.4.0,91.108.7.255,NL
91.108.56.0,91.108.63.255,SG
EOF

# Locate the build tool
BUILD_BIN=""
for p in \
    /usr/lib/xtables-addons/xt_geoip_build \
    /usr/libexec/xtables-addons/xt_geoip_build; do
  if [[ -x "$p" ]]; then
    BUILD_BIN="$p"
    break
  fi
done

if [[ -z "$BUILD_BIN" ]]; then
  echo "[skip] xt_geoip_build not found — geoip integration tests will be skipped"
  rm -f "${CSV}"
  exit 0
fi

echo "Using build tool: ${BUILD_BIN}"

cd "${GEOIP_DIR}"

# Try the most common invocation forms for different xtables-addons versions.
if "${BUILD_BIN}" "${CSV}" 2>&1; then
  echo "GeoIP database built successfully."
elif "${BUILD_BIN}" -D "${GEOIP_DIR}" "${CSV}" 2>&1; then
  echo "GeoIP database built successfully (with -D)."
elif "${BUILD_BIN}" -s < "${CSV}" 2>&1; then
  echo "GeoIP database built successfully (from stdin)."
else
  echo "[warn] xt_geoip_build failed — geoip integration tests will be skipped"
fi

rm -f "${CSV}"

# Show what was produced
echo "Files in ${GEOIP_DIR}:"
ls -lh "${GEOIP_DIR}/" 2>/dev/null || true
