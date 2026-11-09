# Harbor 0.3.0 validation

10 November 2026. Early app beta approved for publication with upstream-designated
driver source/notices included and the independent provenance gap disclosed.

## Changes addressing acceptance feedback

- Source picker accepts files, folders, multiple selections and mixed selections.
  Dropped items use the same source-selection path. Single files copy directly
  under their names, without an extra wrapper folder.
- Batch preflight catches duplicate destination names, overlap and collisions.
  Copy failures retain every original and accurately describe completed earlier
  items. Durable reports and bookmarks support each item independently.
- Checked Trash validates all remaining items and then each immediately before
  moving it. Partial outcomes preserve the distinction between moved and kept
  originals. Moved-source access is forgotten.
- The official TT NTFS Native 0.4.1 app is included unchanged inside
  Harbor.app/Contents/Helpers. Harbor validates host/extension signatures and
  version, registers only extension metadata, and opens OS Settings. No separate
  user download, driver selection or installation is part of the flow.
- No provider host launch, Full Disk Access, login item, privileged helper,
  raw-device access, network entitlement or security-policy change is used.

## Observed tests

- 32 ordinary tests: 30 passed, 2 explicitly configured integrations skipped.
  New tests cover direct single-file contents/reports/corruption/collision,
  zero-byte files, mixed selections, batch preflight before writes, overlap,
  cancellation and later failure preserving earlier verified copies/originals.
- Installed sandboxed UI: selecting an individual file worked; copying it to the
  disposable NTFS image verified 1 file. A mixed selection of two files and a
  folder verified 3 files, including nested Unicode names and an empty folder.
- Reopening restored all three security-scoped sources, destination and reports.
  Fresh checked Trash moved only the three synthetic originals and cleared their
  remembered access. Safe eject succeeded.
- The included NTFS setup action opened the OS extension switch with no driver
  picker, download or password prompt on this Mac. The running extension process
  paths were inside the installed Harbor bundle, proving this test did not use
  the old standalone copy. Global pluginkit enumeration omitted this registration;
  enumeration alone is not an accurate extension readiness check on this OS.
- After clean eject, independent NTFS-3G readback reproduced hashes for all four
  files written by the two UI tests. No physical disk or personal file was used.

Earlier 0.2 tests separately covered folder transfers, source mutations, tampered
reports, Finder-added metadata, folder replacement, collisions and cancellation.
Ordinary readback is not a hardware-cache/power-loss durability guarantee.

## Remaining release gates

The bundled component has a verified vendor Developer ID signature (team
HU5S996C2K), matching official DMG checksum, and accepted Gatekeeper assessment.
However, its embedded source identity could not be matched to the public v0.4.1
tag. The public beta includes the complete source designated by upstream for
that release and preserves the unresolved independent-provenance question.
The builder requires the pinned source archive and notices as packaging inputs.
No confirmed source-to-binary identity or production-security claim is made.

Harbor itself is ad-hoc signed and sandboxed, not Developer ID-signed/notarized.
The candidate requires Apple Silicon/macOS 26+, matching the included provider's
minimum. Clean-machine/older-OS coverage, physical disposable-media acceptance,
large transfers, power-loss tests, signed updates and update policy remain release
validation. No own Harbor FSKit module or resumability is implemented.

The app beta and source are approved for publication. Personal receipts, images,
credentials and local vendor caches remain excluded from the source repository.
Third-party source/notices accompany the app as separate release material.

## Physical-drive acceptance feedback, 10 November 2026

The user reported a successful transfer on a physical NTFS HDD after a normal
unmount/remount activated the enabled provider and the same destination was
reselected to confirm its changed filesystem UUID. The agent independently
observed read/write mount status and an enabled Copy button, but did not run or
verify that user-initiated physical transfer. No forced mount or recovery option
was used. This documents one configuration, not general hardware validation.
The first-use readiness gap is now described in the guide and README; its fully
guided in-app handling remains open work. No private paths or drive IDs are
included in the public evidence.

## Public beta packaging

Beta 2 retains the tested executable code and unchanged vendor component; changes
are packaging, source/notices, provenance, version metadata and documentation.
The provider release-tag archive is included inside the app and alongside its
download. The source-identity flag remains false. Signatures, mandatory source
contents, package roundtrip and checksums are checked before publishing.
