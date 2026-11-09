# Changelog

## 0.3.0-beta.2 — 10 November 2026

First public app beta for Apple Silicon, macOS 26+.

- NTFS-enabled Harbor.app download with no separate driver download or compilation.
- Complete upstream-designated TT NTFS Native 0.4.1 source archive and original
  notices included inside the app and alongside the download.
- Published source audit, unresolved embedded-commit difference and beta/signing
  limitations remain explicit. No independent source-to-binary verification claim.
- Transfer executable behavior is unchanged from the tested local 0.3 candidate.
- Harbor remains ad-hoc signed and is not notarized.

## 0.3.0 source beta — 10 November 2026

First public source snapshot. No public combined app binary is released.

- Native SwiftUI macOS interface for individual files, folders and mixed selections.
- SHA-256 source hashing, destination readback, mount/source checks and exclusive final rename.
- Batch preflight, original retention, explicit partial-copy handling and cancellation.
- Private durable reports, restored selections/results and separately checked macOS Trash.
- Included signed NTFS provider for private local builds, with one OS approval flow.
- Developer tests, CI, user/troubleshooting guide and private vulnerability reporting.

Known issues: first-use read-only mounts can need eject/reconnect and destination
confirmation; provider corresponding-source identity is unresolved; Harbor is not
notarized and broad OS/hardware/interruption coverage is incomplete.
