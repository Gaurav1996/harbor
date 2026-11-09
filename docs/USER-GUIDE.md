# Harbor

Choose **Choose files & folders…** to select one or more files, folders, or a
mixture. Use Command-click or Shift-click for multiple selections. You can also
drop items onto the source area. Choose a destination on your external drive,
then **Copy & verify**. Each selected item keeps its name directly inside the
destination. Existing items are never merged or replaced.

Harbor checks every file's contents and keeps the originals. After success use
**Show files** or **Eject drive**. **Verified copy → Move originals to Trash…**
rechecks the originals, their copies and saved reports before using macOS Trash.
Harbor never empties Trash. If moving a batch stops partway through, the app
reports how many moved and how many stayed. It does not claim an all-or-nothing
Trash operation.

## NTFS support is included

No separate download, installation or driver picker is needed. In **⋯ → NTFS
writing support**, select **Enable NTFS writing…**. Harbor prepares its included
component and opens macOS File System Extensions. Turn on **TT NTFS Native**, then
reconnect your drive. On macOS versions affected by the Settings switch issue,
use **By Category → File System Extensions**.

If Copy remains disabled, check the destination status. An already mounted drive
can remain read-only after enabling the extension. Use **Eject drive**, unplug
and reconnect it, then **Choose destination…** again if requested. Different
drivers can report different volume identifiers; Harbor requires confirmation
instead of trusting the old path. If the drive still reports read-only, stop
and preserve the original files. Do not force a mount or enable repair options.

The component can access attached NTFS volumes while enabled. After ejecting your
drive, turn it off in the same settings if you no longer need NTFS writing.
macOS controls approval prompts; another Mac or managed policy can require an
administrator. Harbor never requests Full Disk Access, adds a login item, opens
the provider's menu-bar app, lowers security protections or repairs a drive.
Keep dirty or hibernated volumes read-only; do not force recovery for a transfer.

Harbor includes the unmodified, independently signed TT NTFS Native 0.4.1 component
by TechTag GmbH. Its GPL v2 license, notices and provenance are included in the
app. This is a private acceptance candidate; public distribution is still held
for corresponding-source verification and release validation.

## Remembered access and interrupted work

Only selected items and the destination are remembered with macOS bookmarks.
**Forget selections** removes that remembered access; private local transfer
reports remain. Reopening a completed job restores its saved result. A recorded
Trash result describes the move at that time, not current recoverability.

Cancellation, disconnection and errors keep all originals. Earlier completed
items and uniquely named partial copies remain on the drive. Retrying starts
fresh and refuses collisions; this version does not resume or delete partial
copies. Close apps modifying either copy during copying or removal.

This is a file-content transfer tool, not a full Mac backup. File contents and
modification dates are preserved. Resource forks, symlinks, special files, nested
mounts and ambiguous case/Unicode names are rejected. Finder tags, creation dates,
ACLs, all extended attributes and hard-link relationships are not preserved.
Checksum readback cannot prove a hardware cache will survive a power cut. Keep
another backup of irreplaceable files.

Harbor 0.3 requires Apple Silicon and macOS 26 or later. This local Harbor build
is sandboxed and ad-hoc signed, not Developer ID-signed or notarized. The bundled
component retains its separate vendor signature. Downloaded Harbor builds can
show first-open warnings; GitHub hosting does not remove signing requirements.
