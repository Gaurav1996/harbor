# Security policy

Harbor is an early source beta. There is no public app binary and no production
security-audit claim. Security fixes currently target the latest source on main.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/Gaurav1996/harbor/security/advisories/new).
Describe the affected revision, impact and a minimal synthetic reproduction.
Do not send personal files, full transfer reports, credentials or raw disk images.
Avoid publishing exploit details before maintainers have assessed the report.
No response-time SLA is promised.

## Security model

Harbor's app sandbox permits selected files/folders and saved bookmarks. The app
has no network entitlement, privileged helper, raw-device access, login item or
Full Disk Access request. It never empties Trash or forces recovery.

The optional component included by private local packaging retains an independent
vendor identity and broader access to NTFS volumes while enabled through macOS.
Harbor registers only that component's metadata, never launches its menu-bar host,
and never edits Apple's enablement database or lowers security protections.
Its source-identity verification remains a public-binary release blocker; see
[release status](docs/OPEN-SOURCE.md).

Review copying/verification, source removal, bookmarks, reports, mount identity,
signature checks and dependency/update integrity. Successful tests do not prove
safety against malicious media or local attackers. Retained legacy experiments
are not part of the consumer target and should not be installed for normal use.
