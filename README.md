# IPBan

This repository is being rebuilt as a safer maintained replacement for the old `AliDbg/IPBAN` script.

The upstream script was useful, but it has several high-risk behaviours for production servers. The review notes are in `REVIEW.md`.

## Main problems found

- It can remove all existing firewall rules instead of only its own rules.
- Its direction parser can treat `FORWARD` as `OUTPUT` because it checks single letters inside the word.
- It changes Linux runlevels during install/update, which is unsafe on a remote server.
- It creates world-writable runtime directories.
- It edits root crontab broadly instead of owning a dedicated project cron file.
- It does not validate user input before changing server networking rules.

## Intended safer design

- Use project-owned chains only.
- Validate direction, country code, target, and yes/no flags.
- Never change runlevels.
- Never disable another firewall automatically.
- Keep backups before changes.
- Persist rules only to standard rule files.
- Use a dedicated project cron file.

## Status

Review notes have been pushed. The executable rewrite still needs to be added after final validation.
