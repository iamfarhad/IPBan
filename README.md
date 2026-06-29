# IPBan

IPBan is a Linux server utility for managing country-based network access rules with `iptables` and `xt_geoip`. Choose a traffic direction, choose one or more countries, and choose whether matching traffic should be blocked, rejected, or accepted.

---

## Quick start

Run directly from this repository — no download step required:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/iamfarhad/IPBan/main/ipban.sh) \
  -add OUTPUT -geoip CN,IR,RU -limit DROP
```

The command above blocks all outbound traffic to China, Iran, and Russia in a single step. Replace `OUTPUT` with `INPUT` to block inbound traffic, or use `INPUT,OUTPUT,FORWARD` for all directions. See [Usage examples](#usage-examples) for the full option set.

> **Before blocking inbound traffic:** confirm you have console or recovery access, and that your SSH session originates from an allowed country.

---

## Design goals

| Goal | Description |
| --- | --- |
| Safe by default | Never flush the whole firewall and never change default policies automatically. |
| Project-owned rules | Keep all managed rules inside dedicated chains such as `IPBAN_INPUT`, `IPBAN_OUTPUT`, and `IPBAN_FORWARD`. |
| Reversible changes | Reset removes only IPBan-managed rules. Uninstall does not damage unrelated firewall configuration. |
| Explicit input | Validate direction, country codes, action targets, and yes/no flags before applying changes. |
| Production friendly | No runlevel changes, no broad crontab edits, no world-writable directories. |
| Observable | A status command that clearly shows active IPBan-managed rules. |
| Persistent | Rules saved in standard persistence locations when the target system supports them. |

---

## How IPBan works

IPBan uses the Linux `xt_geoip` module. The high-level flow is:

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
- `curl` for database updates
- `gzip`, `tar`, and basic shell utilities
- A persistence backend such as `iptables-persistent`, `netfilter-persistent`, or distro-specific iptables services

Recommended operational requirements:

- Console or recovery access before testing inbound rules
- A backup of current firewall rules
- A known-good SSH allow rule before blocking inbound countries
- A disposable test VM before production rollout

---

## Actions and options

| Option | Required | Values | Description |
| --- | --- | --- | --- |
| `-add` | For adding rules | `INPUT`, `OUTPUT`, `FORWARD`, or comma-separated list | Selects where country rules are applied. Aliases: `IN`, `OUT`, `FWD`. |
| `-geoip` | For adding rules | ISO 3166-1 alpha-2 codes | Comma-separated countries such as `CN,IR,RU`. |
| `-limit` | No | `DROP`, `REJECT`, `ACCEPT` | Target action for matching traffic. Default: `DROP`. |
| `-icmp` | No | `yes`, `no` | Use `no` to block inbound ICMP/IPv6-ICMP through IPBan-managed rules. |
| `-reset` | No | `yes` | Remove IPBan-managed rules and chains only. |
| `-remove` | No | `yes` | Remove IPBan-managed runtime files, cron file, and rules. |
| `-update-db` | No | `yes` | Download and rebuild the GeoIP database without changing rules. |
| `-status` | No | `yes` | Print active IPBan-managed chains and rules. |
| `--no-install-deps` | No | flag | Do not install missing packages automatically; fail with instructions instead. |

---

## Usage examples

### Check current IPBan status

```bash
./ipban.sh -status yes
```

### Block outbound traffic to selected countries

Useful when you do not want the server to connect to services hosted in specific countries.

```bash
./ipban.sh -add OUTPUT -geoip CN,IR -limit DROP
```

### Block inbound traffic from selected countries

Use this carefully on remote servers. Make sure your SSH access is not affected.

```bash
./ipban.sh -add INPUT -geoip CN,IR,RU -limit DROP
```

### Reject instead of silently dropping

`REJECT` sends a rejection response. `DROP` silently discards packets.

```bash
./ipban.sh -add INPUT -geoip CN -limit REJECT
```

### Apply rules to multiple directions

```bash
./ipban.sh -add INPUT,OUTPUT,FORWARD -geoip CN,IR,RU -limit DROP
```

### Block ping through IPBan-managed rules

```bash
./ipban.sh -add INPUT -geoip CN,IR -limit DROP -icmp no
```

### Update GeoIP database only

```bash
./ipban.sh -update-db yes
```

### Reset IPBan rules only

Removes only IPBan-managed chains and jump rules. Does not flush unrelated firewall rules.

```bash
./ipban.sh -reset yes
```

### Uninstall IPBan

```bash
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
| `REJECT` | Refuses matching packets with a response | Useful for debugging or clear network failure signalling. |
| `ACCEPT` | Allows matching packets | Useful only when you already have a deny-by-default firewall policy. |

`ACCEPT` does not change your server's default firewall policy. Default policies and SSH safety rules should be managed manually and explicitly.

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

Rules are persisted through the standard mechanism available on the host system:

- Debian/Ubuntu: `/etc/iptables/rules.v4` and `/etc/iptables/rules.v6` when `iptables-persistent` or `netfilter-persistent` is installed.
- RHEL/CentOS/Fedora-style systems: `/etc/sysconfig/iptables` and `/etc/sysconfig/ip6tables` via the iptables service.

---

## Cron and GeoIP updates

IPBan uses a dedicated cron file at `/etc/cron.d/ipban` to refresh the GeoIP database on a daily schedule. It does not edit the system crontab or remove unrelated entries.

---

## File layout

Runtime files:

```text
/usr/share/ipban/
  backup-rules-ipv4.txt
  backup-rules-ipv6.txt
  download-build-dbip.sh
  ipban-update.sh

/usr/share/xt_geoip/
  (binary database files built for xt_geoip)

/etc/cron.d/ipban
```

---

## Validation

IPBan rejects invalid input before applying any firewall change.

| Input | Result |
| --- | --- |
| `-add OUTPUUT` | Error: invalid direction |
| `-geoip IRAN` | Error: country codes must be two letters |
| `-geoip IR,us` | Error: lowercase codes are rejected |
| `-limit BAN` | Error: target must be `DROP`, `REJECT`, or `ACCEPT` |
| `-icmp maybe` | Error: value must be `yes` or `no` |

---

## Development roadmap

- Add dry-run mode.
- Add explicit backup and restore commands.
- Add examples for VPN/gateway use cases.
- Add nftables support as a future backend.

---

## Disclaimer

This project changes firewall behaviour. Incorrect rules can interrupt SSH, web traffic, package updates, monitoring, VPN routing, or production services. Use it only when you understand the network path and have a recovery plan.
