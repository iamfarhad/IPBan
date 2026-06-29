# Review notes

I reviewed the upstream project and found these issues:

1. The old reset path removes all firewall chains instead of only rules created by the project.
2. The old direction parser checks characters inside a word, so one direction can accidentally match another direction.
3. The old installer changes Linux runlevels, which can disrupt a remote server.
4. The old installer creates world-writable runtime directories.
5. The old cron cleanup removes broad entries matching generic words instead of only its own managed cron file.
6. The old persistence logic writes rule data into files that are not always rule files.
7. The old CLI does not validate country codes, action targets, or yes/no flags before changing firewall state.
8. The old uninstall path assumes backup files exist.

The replacement should use dedicated project-owned chains, strict argument validation, project-owned cron files, normal directory permissions, safe persistence targets, and no runlevel changes.
