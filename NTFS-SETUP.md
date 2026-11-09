> Legacy developer experiment only. The consumer Harbor app does not use this
> NTFS-3G/macFUSE route. Do not run these setup scripts for normal app use.

# Harbor NTFS setup

This describes the experimental prototype backend using macFUSE 5.5.0 and a
project-built NTFS-3G 2026.9.28 engine adapted for macOS FSKit. It does not mean
these components are installed on the current machine. This is a developer
workflow, not the proposed end-user onboarding. See docs/PRODUCT-DESIGN.md.

## Components required by this backend

- The signed and notarized macFUSE vendor package.
- Homebrew's NTFS-3G engine, gettext and build dependencies.
- The reviewed NTFS-3G Homebrew formula was trusted individually, not the whole tap.
- Both sandboxed macFUSE FSKit app extensions must be registered and enabled by the user.
- Startup Security, SIP and raw-device ownership/permissions were not changed.

If extension switches do nothing in the “By App” view, use:
System Settings → General → Login Items → **By Category → File System Extensions**.
This is the maintainer-recommended workaround:
https://github.com/macfuse/macfuse/issues/1194

## Why Harbor builds its own engine

The stock NTFS-3G external-FUSE build assumes block devices require Linux-style
fuseblk/root mounting. Root uses a different FSKit activation context from your
logged-in account. A narrow Darwin-only adjustment selects ordinary FUSE mode
only when the explicit `backend=fskit` option is present.

This does not grant privileges. The original setuid/setgid refusal and ordinary
OS device-access checks remain intact. No device permissions are modified.
The NTFS algorithms and recovery checks are upstream code.

For a physical HDD whose device is reserved to administrators, Harbor uses an
additional one-shot helper after a macOS authorization dialog. The helper checks
the external partition's UUID before and after a normal unmount, opens only that
partition, checks its NTFS boot sector, and permanently drops root UID/GID and
supplementary groups before execing the adjacent engine. Only that partition's
open descriptor is inherited by the user-level engine. No privileged daemon,
setuid binary, broad device access, or device-permission change is installed.

The local engine is built by `scripts/build-ntfs-engine.py` from the upstream
2026.9.28 archive, checked against SHA-256:
`8a75293f07bf40df5701d296de32a4cb0e46d6ae135abb4f41b438df9868a390`.

The app bundles this separate GPL executable, its corresponding modified source
archive, license, and build script. The standard Homebrew engine remains unchanged.

## Use

Physical raw-disk access requires **Full Disk Access for Harbor** under System
Settings → Privacy & Security → Full Disk Access. macOS attributes the one-shot
helper to Harbor. This is broader than the selected HDD: it permits access to
protected file areas as described by macOS. Only the user can grant it. It may
be revoked after the transfer; future physical NTFS connections will need it
again. Disposable user-owned images do not exercise this privacy requirement.

1. Connect the HDD. Open Harbor and refresh.
2. Close documents and Finder previews using the drive.
3. Choose **Connect with FSKit**. Harbor checks that the partition is external,
   verifies its identity, unmounts the read-only volume normally, and reconnects
   it through your user's FSKit extension. macOS may ask to authorize the single
   partition handoff described above.
4. The mounted volume lives under your private
   `~/Library/Application Support/Harbor/Mounts` directory. Use Harbor's
   **Show copied folder** button to open it in Finder.
5. Choose **Copy & verify**. Existing destination folders are never overwritten.
6. After verification, optionally choose **Move original to Trash**. Both copies
   are verified again before that separate action.
7. Use **Eject drive** in Harbor before unplugging.

Harbor checks both the backing partition's NTFS serial and the mounted filesystem
identity before writing. Generic FSKit volumes do not appear in diskutil as
ordinary disk partitions, so Harbor stores and validates their connection records.
UUIDs are used for backing partitions when available; disposable images without
a macOS UUID are checked through the NTFS serial.

## Failure handling

Only `backend=fskit,norecover,windows_names` is used. Harbor never forces an
unmount, clears a journal, removes hibernation data or formats the HDD.
It briefly retries a normal unmount when FSKit is completing close callbacks.

If NTFS reports an unclean or hibernated volume after the outage, keep the
original photos. Do not force recovery on this HDD. An unsuccessful connection
attempt restores the ordinary macOS read-only mount when safe.

## Rebuild

```sh
HOMEBREW_NO_AUTO_UPDATE=1 brew fetch --build-from-source gromgit/fuse/ntfs-3g-mac
python3 scripts/build-ntfs-engine.py
bash scripts/build-app.sh
```

The build requires macFUSE headers and Homebrew autoconf, automake, libgcrypt,
libtool, pkgconf and gettext. The source build affects the project directory only.

## Integration validation

`python3 scripts/test-ntfs-image.py` creates and formats only a new regular image
file in `.integration`. It proves the attached device belongs to that image,
runs Harbor's actual connection and transfer methods, verifies content, unmounts
normally, remounts with macOS's native read-only driver, and checks all hashes again.
It never chooses or formats a physical HDD.
Pass `--authorized` to exercise the administrator-approved descriptor handoff
on the same disposable-image workflow. Historical image tests passed on one
development machine; this does not establish a supported OS/hardware matrix.

