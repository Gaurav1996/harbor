# Changelog

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
