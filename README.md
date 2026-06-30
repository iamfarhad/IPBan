# IPBan

<p align="center">
  <a href="https://github.com/iamfarhad/IPBan/actions/workflows/ci.yml">
    <img src="https://github.com/iamfarhad/IPBan/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <img src="https://img.shields.io/badge/version-v1.0.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey?logo=linux" alt="Platform">
  <img src="https://img.shields.io/badge/bash-4.0%2B-yellow?logo=gnubash" alt="Bash">
  <img src="https://img.shields.io/badge/iptables-based-orange" alt="iptables">
</p>

**IPBan** is a Linux firewall utility that blocks or restricts network traffic by country using `iptables` and the `xt_geoip` kernel module. Choose a direction, choose countries, and choose whether to DROP, REJECT, or ACCEPT — all in a single command.

---

## Quick start

Run directly from this repository — no download or installation step required:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/iamfarhad/IPBan/main/ipban.sh) \
  -add OUTPUT -geoip CN,IR,RU -limit DROP
```

This blocks all outbound traffic to China, Iran, and Russia in a single step. Replace `OUTPUT` with `INPUT` to block inbound traffic, or use `INPUT,OUTPUT,FORWARD` for all directions.

> **Before blocking inbound traffic:** confirm you have console or out-of-band access, and that your SSH session originates from an allowed country.

---

## Features

- **Country-based firewall rules** — block or restrict traffic by ISO 3166-1 country code using `xt_geoip`
- **IPv4 and IPv6** — rules apply to both `iptables` and `ip6tables` simultaneously
- **Project-owned chains** — all rules live in `IPBAN_INPUT`, `IPBAN_OUTPUT`, and `IPBAN_FORWARD`; resetting never touches unrelated firewall rules
- **Safe reset and uninstall** — removes only IPBan-managed rules; restores your original firewall state on uninstall
- **Strict input validation** — rejects invalid country codes, directions, and targets before touching the firewall
- **Auto GeoIP updates** — installs a dedicated cron job (`/etc/cron.d/ipban`) that refreshes the country database daily
- **Multi-distro support** — Ubuntu, Debian, CentOS Stream, RHEL, and Fedora
- **One-command install** — auto-detects distro, installs dependencies, builds the GeoIP database, and applies rules

---

## How it works

IPBan uses the Linux `xt_geoip` netfilter extension to match packets by country of origin or destination.

```
curl | ipban.sh
     │
     ├─ detect distro (apt / yum)
     ├─ install iptables + xtables-addons + GeoIP tools
     ├─ download DB-IP country database
     ├─ build binary GeoIP database for xt_geoip
     ├─ create IPBAN_* chains
     ├─ attach chains to INPUT / OUTPUT / FORWARD
     ├─ add country-match rules
     └─ persist rules + schedule daily DB update
```

---

## Supported platforms

| Distribution | Versions |
| --- | --- |
| Ubuntu | 20.04 LTS, 22.04 LTS, 24.04 LTS |
| Debian | 11 (Bullseye), 12 (Bookworm) |
| CentOS Stream | 8, 9 |
| RHEL-compatible | 8, 9 (AlmaLinux, Rocky Linux) |
| Fedora | Where `xtables-addons` is available |

> The `xt_geoip` kernel module must be loadable on the target system. VPS providers that use custom kernels without module support may not be compatible.

---

## Requirements

- Root privileges
- `iptables` and `ip6tables`
- `xtables-addons` / `xt_geoip` kernel module
- `curl`, `gzip`, `tar`, `perl`
- A persistence backend: `iptables-persistent` (Debian/Ubuntu) or `iptables-services` (RHEL/CentOS)

IPBan installs all of the above automatically unless `--no-install-deps` is passed.

---

## Usage

```bash
ipban.sh [action] [options]
```

### Options

| Option | Values | Default | Description |
| --- | --- | --- | --- |
| `-add` | `INPUT`, `OUTPUT`, `FORWARD` | — | Direction(s) to apply rules. Accepts comma-separated list and aliases `IN`, `OUT`, `FWD`. |
| `-geoip` | ISO 3166-1 codes | `CN,IR,RU` | Countries to match. Comma-separated, e.g. `CN,IR,RU`. |
| `-limit` | `DROP`, `REJECT`, `ACCEPT` | `DROP` | Action for matching traffic. |
| `-icmp` | `yes`, `no` | `yes` | Set to `no` to also block ICMP / ICMPv6 from matching countries. |
| `-reset` | `yes` | — | Remove all IPBan-managed chains and rules only. |
| `-remove` | `yes` | — | Full uninstall: remove rules, cron, and runtime files. |
| `-update-db` | `yes` | — | Refresh the GeoIP database without changing rules. |
| `-status` | `yes` | — | Show active IPBan chains and rules. |
| `--no-install-deps` | — | — | Fail instead of auto-installing missing packages. |

---

## Examples

### Block outbound connections to China, Iran, and Russia

```bash
bash ipban.sh -add OUTPUT -geoip CN,IR,RU -limit DROP
```

### Block inbound traffic from multiple countries

```bash
bash ipban.sh -add INPUT -geoip CN,IR,RU -limit DROP
```

### Apply to all directions at once

```bash
bash ipban.sh -add INPUT,OUTPUT,FORWARD -geoip CN,IR,RU -limit DROP
```

### Reject instead of silently dropping

```bash
bash ipban.sh -add INPUT -geoip CN -limit REJECT
```

### Block inbound traffic and ICMP ping from China

```bash
bash ipban.sh -add INPUT -geoip CN -limit DROP -icmp no
```

### Check active rules

```bash
bash ipban.sh -status yes
```

### Update the GeoIP database without changing rules

```bash
bash ipban.sh -update-db yes
```

### Remove all IPBan rules (keep other firewall rules intact)

```bash
bash ipban.sh -reset yes
```

### Full uninstall

```bash
bash ipban.sh -remove yes
```

---

## Traffic directions

| Direction | Meaning | Use case |
| --- | --- | --- |
| `INPUT` | Traffic arriving at the server | Block inbound connections from selected countries |
| `OUTPUT` | Traffic leaving the server | Prevent the server from reaching selected countries |
| `FORWARD` | Traffic routed through the server | Use on VPN servers, gateways, and proxies |

---

## DROP vs REJECT vs ACCEPT

| Target | Behaviour | When to use |
| --- | --- | --- |
| `DROP` | Silently discards packets | Default; exposes no information about the firewall |
| `REJECT` | Returns an ICMP error to the sender | Useful for debugging; clients know the connection was refused |
| `ACCEPT` | Allows packets | Use when your default policy is already DROP/REJECT |

---

## Validation

IPBan validates all input before touching the firewall.

| Invalid input | Error |
| --- | --- |
| `-add OUTPUUT` | Invalid direction |
| `-geoip IRAN` | Country code must be 2 letters |
| `-geoip CN,` | Trailing comma in country list |
| `-limit BAN` | Target must be DROP, REJECT, or ACCEPT |
| `-icmp maybe` | Must be `yes` or `no` |

---

## Safety checklist

Before applying inbound rules on a remote server:

1. Confirm you have console or out-of-band access.
2. Confirm your SSH session originates from an allowed country.
3. Back up existing firewall rules.
4. Add an explicit SSH allow rule outside IPBan.
5. Test on a disposable VM first.
6. Start with one direction and one country.
7. Check `-status yes` before adding more rules.

---

## File layout

```
/usr/share/ipban/
  backup-rules-ipv4.txt       original firewall rules (restored on -remove)
  backup-rules-ipv6.txt
  download-build-dbip.sh      fetches and builds the GeoIP database
  ipban-update.sh             called by cron for daily updates

/usr/share/xt_geoip/          binary GeoIP database read by xt_geoip module

/etc/cron.d/ipban             daily GeoIP refresh (project-owned, not crontab)

/etc/iptables/rules.v4        persisted rules (Debian/Ubuntu)
/etc/iptables/rules.v6
/etc/sysconfig/iptables       persisted rules (RHEL/CentOS)
/etc/sysconfig/ip6tables
```

---

## Persistence

| Distro family | Persistence mechanism |
| --- | --- |
| Debian / Ubuntu | `/etc/iptables/rules.v4` and `rules.v6` via `iptables-persistent` |
| RHEL / CentOS / Fedora | `/etc/sysconfig/iptables` and `ip6tables` via `iptables-services` |

---

## Roadmap

- Dry-run mode (`--dry-run`)
- Explicit backup and restore commands
- nftables backend
- VPN and gateway usage examples

---

## License

MIT

---

## Disclaimer

This project modifies firewall rules. Misconfigured rules can block SSH, web traffic, monitoring, and other services. Always test on a non-production system first and ensure you have an alternative access method before applying inbound rules.
