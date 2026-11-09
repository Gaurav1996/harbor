<p align="center"><img src="docs/assets/harbor.svg" width="112" alt="Harbor"></p>

<h1 align="center">Harbor</h1>
<p align="center"><strong>Copy files to NTFS drives on your Mac. Verify every file.</strong></p>
<p align="center">
  <a href="https://github.com/Gaurav1996/harbor/actions/workflows/ci.yml"><img src="https://github.com/Gaurav1996/harbor/actions/workflows/ci.yml/badge.svg" alt="Build and tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Harbor-MIT-24665a" alt="Harbor code: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-555555" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-555555" alt="Apple Silicon">
</p>

Your Mac can read your NTFS external drive, but will not let you copy files onto
it? **That is the main problem Harbor is built to solve.**

Harbor combines NTFS writing support with verified transfers, so you can copy
files and folders from a Mac to a supported NTFS drive **without reformatting it**.
Choose your items, choose a destination, and **Copy & verify**. Every copied file
is checked, and the originals stay in place unless you separately choose to move
them to Mac Trash. It also works with already-writable external filesystems.

> **Early source beta.** The source is public; there is no public Harbor app
> download yet. The working local candidate includes an independently signed
> NTFS component, whose corresponding-source identity remains under verification.
> Its combined binary is held from public distribution. See [release status](docs/OPEN-SOURCE.md) and the
> [driver source audit](docs/DRIVER-SOURCE-VERIFICATION.md).

## Why an NTFS drive looks read-only on a Mac

NTFS is a filesystem, not an inherently read-only file format. macOS’s built-in
NTFS support normally lets you read existing files without providing ordinary
write access. [Apple describes this limitation](https://support.apple.com/101830).
Harbor’s local candidate supplies that missing writing capability
through the included, independently signed TT NTFS Native FSKit component.
You approve the component in macOS Settings; Harbor handles its preparation.

This addresses the normal macOS NTFS write-support limitation. A damaged,
hibernated, write-protected or otherwise unsupported volume may still need to
stay read-only. Harbor does not bypass those protections or repair the disk.

## What it does

- **Files and folders together.** Select one item, multiple files, folders, or a
  mixture. Each keeps its name directly inside the selected destination.
- **Content verification.** Hashes source bytes with SHA-256 while copying,
  synchronizes writes, then reads back the copied files and compares every hash.
- **No overwrites.** Checks the selection for name conflicts and overlap. Copies
  into unique partial locations and exclusively renames verified items into place.
- **Originals kept.** Errors and cancellation retain every original. Completed
  earlier items and partial copies remain available for inspection.
- **Checked move to Trash.** A separate confirmation reloads private reports and
  rechecks both copies. Harbor reports partial batch outcomes and never empties Trash.
- **Remembered selections and safe eject.** macOS bookmarks retain access to
  chosen items. Forget selections removes that access; moved-source access is cleared.

## App and NTFS support

The local 0.3 candidate contains the unchanged [TT NTFS Native 0.4.1](https://github.com/dr-kbadawi/ttntfs/releases/tag/v0.4.1)
component, signed by TechTag GmbH. There is no separate download or driver picker
in the app. Harbor validates the included component, registers its extension
metadata, and opens macOS File System Extensions for the user's approval.
Harbor does not build or sign that extension with your Apple account.

The driver's main/menu-bar app is never launched. Harbor adds no login item,
requests no Full Disk Access, and does not lower macOS security protections.
While enabled, the NTFS extension has access to attached NTFS volumes, separately
from Harbor's selected-file permissions. macOS controls its own approval prompts.

**Known first-use issue:** enabling NTFS support does not replace an already
mounted read-only filesystem. Safely eject and reconnect the drive, then select
its destination again if asked: different drivers can report different volume
identifiers. Harbor deliberately keeps its identity check. It never forces a
mount, repairs a disk, replays a journal, or discards a Windows hibernation image.
See [using Harbor and troubleshooting](docs/USER-GUIDE.md).

## Build from source

Requirements: an Apple Silicon Mac, macOS 26+, **Xcode 27 with the macOS 27 SDK**,
Swift 6, and Python 3. The deployment target is macOS 26; the current source also
references a macOS 27 FSKit settings API inside an availability check. CI uses the
Xcode 27 runner. Compatibility across all supported OS versions is not established.

```sh
gh repo clone Gaurav1996/harbor
cd harbor
swift test --disable-sandbox
swift build -c release --product Harbor --disable-sandbox
```

The Swift app/core have no downloaded package dependencies. Building or testing
those targets does not install or enable a driver. SwiftPM's `--disable-sandbox`
affects its build process; the packaged app retains the macOS App Sandbox.

To package a **private local test candidate**:

```sh
bash scripts/build-app.sh
open dist/Harbor.app
```

The packaging script fetches/caches the pinned official driver DMG, checks its
SHA-256, version, vendor signatures and Gatekeeper assessment, and includes the
provider unchanged. This network access occurs at build time. The resulting app
works offline and has no network entitlement. The included extension retains its
vendor signing profile; no paid Apple account is needed to build Harbor's wrapper
locally. Harbor itself is ad-hoc signed by default and is **not notarized**.
A downloaded build can show macOS first-open warnings.

The script refuses `HARBOR_PUBLIC_RELEASE=1` while provider source verification is
unresolved. Do not upload a locally built combined app as a public release.

## Privacy

Harbor processes file contents locally. It contains no analytics, account system,
network entitlement, background login item, or privileged mount helper. The app
requests access through macOS file/folder pickers and saved bookmarks.

Transfer reports remain in Harbor's sandboxed Application Support directory. They
contain paths, sizes and hashes, so treat them as private. Forget selections
removes remembered access but retains those reports. A saved Trash result records
what happened at completion, not whether that item is still recoverable later.
Never post personal reports or unredacted filenames in issues.

## Limits that matter

This is a **file-content transfer tool, not a full Mac backup**. It preserves file
contents and modification dates, including hidden/empty files and empty folders.
It rejects resource forks, symlinks, special files, nested mounts and ambiguous
case/Unicode names. Finder tags, creation dates, ACLs, all extended attributes and
hard-link relationships are not preserved.

Retrying starts a fresh transfer; partial copies are not resumed or silently
removed. The app does not merge or replace existing destination items. Close apps
that modify either copy. A checksum cannot establish disk health, guarantee a
hardware cache survives power loss, or exclude changes after the final check.
Keep another backup of irreplaceable data.

## Validation and project status

The local suite passes **30 tests**, with **2 integration tests skipped** unless
explicitly configured. Coverage includes single/mixed selections, hashes,
collisions, source mutation, corruption, cancellation, replacement folders,
resource forks and report validation. Installed sandboxed UI tests used synthetic
files and a disposable NTFS image; independent NTFS-3G readback matched all four
files written in the 0.3 UI tests.

A user has also reported a successful transfer on a physical NTFS HDD after the
first-use remount/destination-confirmation steps. That is one Mac/drive result,
not a clean-machine, broad compatibility, large-transfer or power-loss test matrix.
See [the evidence and remaining work](docs/IMPLEMENTATION-STATUS.md).

Immediate priorities are clearer first-use readiness, provider source verification,
clean-machine tests, and a signed distribution/update plan. Resumability and an
owned Harbor filesystem extension are future work. Historical experiments under
`HarborLegacyNTFS`, `HarborMount`, and the old NTFS-3G/macFUSE scripts are excluded
from the consumer target; do not use [legacy setup](NTFS-SETUP.md) for normal use.

## Contributing, security and license

Bug reports with synthetic reproductions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md).
For vulnerabilities, use [private reporting](https://github.com/Gaurav1996/harbor/security/advisories/new);
see [SECURITY.md](SECURITY.md). Please avoid public personal data or exploit details.

Harbor's original code is **MIT licensed**. TT NTFS Native is a separate
**GPL-2.0** component; it is not redistributed in this source repository. Retained
legacy tooling has its own dependency terms. [NOTICE.md](NOTICE.md) explains the
boundaries; an MIT wrapper does not relicense filesystem code.
