# IPBan

IPBan is a Linux server utility for managing country-based network access rules with `iptables` and `xt_geoip`.

The goal of this repository is to provide a safer, maintained replacement for the old `AliDbg/IPBAN` script while keeping the same simple command-line idea: choose a traffic direction, choose one or more countries, and choose whether matching traffic should be blocked, rejected, or accepted.

> Current status: v6.0 — fully implemented and replaces the upstream `AliDbg/IPBAN` v5.x script. All upstream issues have been resolved.

---

## Why this rewrite exists

The upstream script was useful, but it had several risky behaviours for production servers:

- It could clear all firewall rules instead of only removing rules managed by the tool.
- It matched directions by checking letters inside words, which could make `FORWARD` accidentally trigger `OUTPUT` logic.
- It changed Linux runlevels during install and update.
- It created world-writable runtime directories.
- It edited root crontab broadly instead of using a dedicated project-owned cron file.
- It did not strictly validate country codes, targets, or yes/no flags before touching networking rules.
- It assumed backup files always existed during uninstall.

IPBan is being redesigned around safer defaults, project-owned chains, strict validation, and reversible changes.

---

## Design goals

| Goal | Description |
| --- | --- |
| Safe by default | Never flush the whole firewall and never change default policies automatically. |
| Project-owned rules | Keep all managed rules inside dedicated chains such as `IPBAN_INPUT`, `IPBAN_OUTPUT`, and `IPBAN_FORWARD`. |
| Reversible changes | Reset should remove only IPBan-managed rules. Uninstall should not damage unrelated firewall configuration. |
| Explicit input | Validate direction, country codes, action targets, and yes/no flags before applying changes. |
| Production friendly | Avoid runlevel changes, broad crontab edits, and world-writable directories. |
| Observable | Provide a status command that clearly shows active IPBan-managed rules. |
| Persistent | Save rules in standard persistence locations when the target system supports them. |

---

## How IPBan works

IPBan is intended to use the Linux `xt_geoip` module. The high-level flow is:

1. Install required packages for `iptables`, `xtables-addons`, and GeoIP database building.
2. Download a country IP database from a supported public source.
3. Build the database into the format expected by `xt_geoip`.
4. Create dedicated IPBan chains for the selected traffic directions.
5. Attach the IPBan chains to `INPUT`, `OUTPUT`, or `FORWARD` only when requested.
6. Add country-matching rules into the IPBan chains.
7. Persist rules so they survive reboot.
8. Refresh the GeoIP database through a dedicated project cron file.

---

## Supported platforms

Target support:

- Ubuntu 20.04 and newer
- Debian 11 and newer
- CentOS Stream / RHEL-compatible systems where `xtables-addons` is available
- Fedora-style systems where `xtables-addons` is available

Kernel module availability is the most important requirement. If `xt_geoip` cannot be installed or loaded on the server, country-based matching will not work.

---

## Requirements

Required system capabilities:

- Root privileges
- `iptables` and `ip6tables`
- `xtables-addons` / `xt_geoip`
- `curl` or another download tool for database updates
- `gzip`, `tar`, and basic shell utilities
- A persistence backend such as `iptables-persistent`, `netfilter-persistent`, or distro-specific iptables services

Recommended operational requirements:

- Console or recovery access before testing inbound rules
- A backup of current firewall rules
- A known-good SSH allow rule before blocking inbound countries
- A disposable test VM before production rollout

---

## Intended command format

```text
ipban.sh [action] [options]
```

Examples in this document use `./ipban.sh`. In a real installation, the script may also be installed as `ipban` in the system path.

---

## Actions and options

| Option | Required | Values | Description |
| --- | --- | --- | --- |
| `-add` | For adding rules | `INPUT`, `OUTPUT`, `FORWARD`, or comma-separated list | Selects where country rules are applied. Aliases may include `IN`, `OUT`, and `FWD`. |
| `-geoip` | For adding rules | ISO-3166 alpha-2 country codes | Comma-separated countries such as `CN,IR,RU`. |
| `-limit` | No | `DROP`, `REJECT`, `ACCEPT` | Target action for matching traffic. Default should be `DROP`. |
| `-icmp` | No | `yes`, `no` | Use `no` to block inbound ICMP/IPv6 ICMP through IPBan-managed rules. |
| `-reset` | No | `yes` | Remove IPBan-managed rules and chains only. |
| `-remove` | No | `yes` | Remove IPBan-managed runtime files, cron file, and rules. |
| `-update-db` | No | `yes` | Download and rebuild the GeoIP database without changing rules. |
| `-status` | No | `yes` | Print active IPBan-managed chains and rules. |
| `--no-install-deps` | No | flag | Do not install missing packages automatically; fail with instructions instead. |

---

## Usage examples

### Check current IPBan status

```text
./ipban.sh -status yes
```

### Block outbound traffic to selected countries

Useful when you do not want the server to connect to services hosted in specific countries.

```text
./ipban.sh -add OUTPUT -geoip CN,IR -limit DROP
```

### Block inbound traffic from selected countries

Use this carefully on remote servers. Make sure your SSH access is not affected.

```text
./ipban.sh -add INPUT -geoip CN,IR,RU -limit DROP
```

### Reject instead of silently dropping

`REJECT` sends a rejection response. `DROP` silently discards packets.

```text
./ipban.sh -add INPUT -geoip CN -limit REJECT
```

### Apply rules to multiple directions

```text
./ipban.sh -add INPUT,OUTPUT,FORWARD -geoip CN,IR,RU -limit DROP
```

### Block ping through IPBan-managed rules

```text
./ipban.sh -add INPUT -geoip CN,IR -limit DROP -icmp no
```

### Update GeoIP database only

```text
./ipban.sh -update-db yes
```

### Reset IPBan rules only

This should remove only IPBan-managed chains and jump rules. It should not flush unrelated firewall rules.

```text
./ipban.sh -reset yes
```

### Uninstall IPBan runtime files

```text
./ipban.sh -remove yes
```

---

## Traffic direction explained

| Direction | Meaning | Typical use case |
| --- | --- | --- |
| `INPUT` | Traffic coming into the server | Block inbound requests from selected countries. |
| `OUTPUT` | Traffic leaving the server | Prevent the server from connecting to selected countries. |
| `FORWARD` | Traffic routed through the server | Gate traffic on router, gateway, proxy, or VPN servers. |

---

## DROP vs REJECT vs ACCEPT

| Target | Behaviour | When to use |
| --- | --- | --- |
| `DROP` | Silently discards matching packets | Default blocking behaviour; less information is exposed. |
| `REJECT` | Refuses matching packets with a response | Useful for debugging or clear network failure behaviour. |
| `ACCEPT` | Allows matching packets | Useful only when you already have a deny-by-default firewall policy. |

Important: `ACCEPT` should not automatically change your server to an allowlist firewall. Default policies and SSH safety rules should be managed manually and explicitly.

---

## Safety checklist before production use

Before applying inbound rules:

1. Confirm you have console or recovery access.
2. Confirm your current SSH session is from an allowed country.
3. Back up existing firewall rules.
4. Add a known-good SSH allow rule outside IPBan.
5. Test on a disposable VM.
6. Apply one direction and one country first.
7. Check status and logs before adding more countries.

---

## Persistence model

The maintained implementation should persist rules through the standard mechanism available on the host system:

- Debian/Ubuntu: `/etc/iptables/rules.v4` and `/etc/iptables/rules.v6` when `iptables-persistent` or `netfilter-persistent` is installed.
- RHEL/CentOS/Fedora-style systems: distro-supported iptables service files when available.

The script should not write iptables-save output into unrelated config files.

---

## Cron and GeoIP updates

The maintained implementation should use a dedicated cron file:

```text
/etc/cron.d/ipban
```

Expected behaviour:

- Refresh the GeoIP source database on a schedule.
- Rebuild the `xt_geoip` database.
- Avoid editing unrelated crontab entries.
- Avoid removing rules owned by other tools.

---

## File layout

Expected runtime layout:

```text
/usr/share/ipban/
  backup-rules-ipv4.txt
  backup-rules-ipv6.txt
  ipban-update-db.sh

/usr/share/xt_geoip/
  database files generated for xt_geoip

/etc/cron.d/ipban
  project-owned scheduled update
```

Expected repository layout:

```text
README.md
REVIEW.md
ipban.sh
.github/workflows/ci.yml
```

---

## Validation rules

The maintained implementation should reject invalid input before applying firewall changes.

Examples:

| Input | Expected result |
| --- | --- |
| `-add OUTPUUT` | Fail with a clear invalid direction error. |
| `-geoip IRAN` | Fail because country codes must be two letters. |
| `-geoip IR,us` | Normalize to uppercase or fail consistently. |
| `-limit BAN` | Fail because target must be `DROP`, `REJECT`, or `ACCEPT`. |
| `-icmp maybe` | Fail because value must be `yes` or `no`. |

---

## Development roadmap

- Add Bash syntax validation in CI.
- Add ShellCheck in CI.
- Add dry-run mode.
- Add distro detection tests.
- Add explicit backup and restore commands.
- Add examples for VPN/gateway use cases.
- Add nftables support as a future backend.

---

## Project status

v6.0 is a complete rewrite of the upstream `AliDbg/IPBAN` v5.x script. All upstream issues identified during review have been resolved. Validate on a disposable VM or a server with recovery console access before using in production.

---

## Disclaimer

This project changes firewall behaviour. Incorrect rules can interrupt SSH, web traffic, package updates, monitoring, VPN routing, or production services. Use it only when you understand the network path and have a recovery plan.
