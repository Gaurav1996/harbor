# What the prototype taught us

Sanitized engineering record · 8 November 2026

## Separate the permission layers

An external disk can be powered but absent from Finder. Device detection,
filesystem recognition, a mounted volume, folder access and filesystem write
support are separate states. Model each explicitly. Never infer health from an
LED or offer to format a disk merely because it is not mounted.

The prototype needed administrator authorization for installation and a selected
raw partition, extension enablement, and Full Disk Access for physical-device
access. A folder picker cannot authorize a raw block device. Likewise, root
privilege does not mean the process automatically satisfies macOS privacy rules.
Replacing password dialogs with a permanently privileged process would change
the risk, not remove the need for a permission architecture.

## Development signing is not release signing

Ad-hoc-signed rebuilds caused stale privacy approval records. Repeatedly asking
people to remove/re-add FDA is not acceptable onboarding. Use stable release
identities and test upgrades from previously approved signed builds. Notarization
is a distribution requirement, not proof of transfer correctness or consent continuity.

## Observe actual state after user actions

One System Settings route ignored filesystem-extension switches; the category
view worked. Link to the most specific supported settings destination, inspect
extension state on return, and offer a version-appropriate recovery instruction.
Do not ask the user to report technical identifiers. Avoid guessed delays and
“continue” buttons that assume permission was granted.

## Physical disks differ from disposable images

The image integration test passed before physical-device privacy restrictions
were understood. Root and user FSKit contexts also behaved differently. The
prototype ultimately passed one already-open partition descriptor to an engine
after dropping root. Keep that learning as a boundary test; do not extrapolate
it into evidence that a new native extension will have the same permissions.

Keep UUID, NTFS serial, mount identity and resource lifetime checks. A disk name
or a remembered disk number is insufficient. These identifiers help prevent
accidental wrong-drive writes; they are not cryptographic device authentication.

## Verification must survive the app session

The useful product feature is a verified transfer with a durable receipt, rather
than simply a writable disk. Copy to an exclusive partial location, verify file
contents, retain sources on failure and make source removal a separate action.
Support interrupted jobs explicitly. A receipt should reconstruct a result after
the GUI closes; it must not silently authorize later deletion from stale paths.

Finder may add metadata files. Define which additional metadata is harmless
without ignoring arbitrary hidden content. Preserve or reject resource forks and
unsupported metadata visibly. State that this is a content transfer, not a full
Mac backup. Read-back hashing alone does not establish power-loss durability.

## Cleanup is part of installation design

The vendor uninstaller removed privileged components but left bundles behind.
Check resulting files, receipts, registered extensions, launch jobs and running
processes; a successful exit code is not proof of complete removal. Avoid broad
Homebrew autoremove, TCC resets or background-item database resets. Never remove
another app's shared dependencies. A native bundled extension should eliminate
most system-wide installation residue, but still needs an observed disable and
unmount lifecycle.

The earlier source-removal receipt recorded a move to Trash. A later cleanup
inspection did not confirm that original there. Do not turn a historical receipt
into a current promise of recoverability. Harbor now records the actual
trash result and distinguishes “moved then” from “still recoverable now.” Cleanup
must never empty Trash.

## Publish software, not a personal support session

Private reports contain folder names, paths, disk identifiers and file hashes.
Support scripts can embed those values even when the app code does not. Exclude
them structurally through a publication allowlist, not only a best-effort text
search or .gitignore. Do not copy a local setup history into distributed apps.
Publish anonymized scenarios, synthetic fixtures and precise evidence limits.

Historical success is one development-machine result. A consumer release needs
clean-machine install, repeat use, signed update, denial and removal tests.

## Enabling a module does not replace an existing mount

A real-drive acceptance test found that the filesystem-extension switch was on
while the existing mount remained read-only under the earlier driver. A normal
unmount/remount activated the new provider. It reported a different volume UUID,
so the app correctly required selecting the destination again. Treat extension
approval, active driver, writable mount and authorized destination as distinct
states. Explain the next step without weakening wrong-drive checks.
