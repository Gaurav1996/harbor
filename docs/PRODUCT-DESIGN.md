# Harbor: verified external-drive transfers

Design proposal · 8 November 2026 · implementation and release gates below

> Roadmap, not the current feature list. Harbor 0.3.0 privately includes an unchanged
> signed provider, has no resume feature and is not notarized. Current behavior
> and evidence are in IMPLEMENTATION-STATUS.md and USER-GUIDE.md.

## Product decision

Harbor should ask people for a folder, a destination, and permission for the work
they chose. It should discover everything else. The normal flow is:

**Choose folder → choose drive → Copy & verify → View files or Eject.**

The desired NTFS experience uses one bundled, signed Harbor filesystem extension
and a maintained NTFS engine. Replacing the prototype's macFUSE/raw-device chain
with native FSKit is the preferred research direction. It is not yet a proven
solution. Do not advertise “no passwords,” “one approval forever,” or “no Full
Disk Access” for NTFS until physical-device tests establish those properties.

Native writable APFS/exFAT destinations should work without the NTFS component.
NTFS remains central to the product; ordinary-drive support is not evidence that
the NTFS experience is finished. Publish source as a clearly labeled prototype
while investigating NTFS. Ship a consumer NTFS release only after its gates pass.

## First use

1. Open a Developer ID-signed, notarized app. No account, Terminal, Homebrew,
   device identifier, formatting choice, or dependency installer in this flow.
2. Choose or drop a folder. Show its name, total size and file count after scanning.
   Obtain access through the standard system picker; dragging must be tested for
   equivalent access. Never scan Downloads looking for a likely personal folder.
3. Show connected external drives with name, capacity, free space and readiness.
   Select the only suitable drive visually, but never begin a write automatically.
   Selecting a drive card does not itself grant file access: use the system picker
   to authorize a destination folder on that drive when needed.
4. If NTFS writing is needed, explain: “Enable Harbor’s NTFS support to copy to
   this drive.” Show only the next unmet requirement. Link to Apple's supported
   filesystem-extension settings UI; re-read actual extension state when returning.
   An extension switch may require macOS authorization. Never simulate approval.
5. Offer **Copy & verify**, with “Your original stays on this Mac.” Report the
   current phase, bytes and remaining work. An ETA is an estimate, not a promise.
6. Finish with the verified file count and **View files** / **Eject**. Keep the
   original by default. Put **Move original to Trash…** in a separate deliberate
   action that performs fresh checks. Never empty Trash.

An ordinary transfer needs no questionnaire. Advanced details belong in a
read-only inspector. Avoid exposing FSKit, BSD disk names, hashes and helper
architecture in normal task screens; explain the access being requested plainly.

## Returning users and permission policy

Remember the last destination and explicitly approved folder access using
security-scoped bookmarks, with a visible **Forget access** action. Stop active
security-scoped access when work ends. Offer persistence only when useful, with
clear scope. A stale/revoked bookmark leads to one focused folder selection,
not an administrator prompt or a broad-permission workaround. Reconnection can
change the mounted URL, so bookmark behavior across native/FSKit mounts is a gate.

For ordinary writable drives, target zero administrator password prompts. Folder
pickers, removable-volume privacy prompts and Gatekeeper's first-open dialog are
different from administrator authorization and must be measured separately.
For NTFS, target extension approval during initial setup and no authorization
per file or per transfer. The exact prompt count is **unproven**, especially on
standard-user accounts, managed Macs and after upgrades or permission revocation.

Do not collect or cache passwords. Do not keep an administrator authorization
alive to hide an underlying permission problem. Do not use Full Disk Access as
the fix for selected-folder access. The native backend's FDA-free goal remains
a feasibility test, not a claim about the current prototype.

## Why the prototype asked repeatedly

There were separate requests for installer authorization, extension enablement,
raw-partition access and Full Disk Access. Some repeated FDA work followed
changing ad-hoc-signed builds. One Settings route also ignored extension toggles.
These are different failure classes; a single “grant permissions” screen cannot
solve them. Stable release signing should avoid the development identity churn,
but cannot prevent an OS from requesting legitimate renewed consent.

The prototype's one-shot helper intentionally acquired a capability for one
partition and then dropped root. Removing repeated authorization by leaving a
general privileged daemon installed would change the security tradeoff. It is
not the default recommendation for a product whose users want minimal residue.

## Architecture

The proposed components are:

- **Sandboxed UI and transfer worker:** access only approved folders; scan,
  plan, copy, verify, journal and write a local receipt. No root or raw disk API.
- **Volume coordinator:** observe Disk Arbitration, classify readiness, bind a
  job to the current device/resource and mount, and cancel safely on replacement.
  Use supported APIs and structured errors, not shell text parsing in production.
- **Optional Harbor NTFS FSKit extension:** runs in user space under the system's
  extension lifecycle. Reuse NTFS-3G through a narrow adapter; do not write a new
  NTFS implementation. Obtain partition I/O through FSBlockDeviceResource when
  the system supplies it, rather than opening /dev/disk* in the GUI.
- **Local job store:** versioned manifests, explicit states and receipts. File
  paths and hashes are private local data. Sharing diagnostics requires a
  redacted preview and the user's explicit action.

Apple's FSKit docs describe system-mediated partition I/O. This supports the
architecture direction, but does not prove that our sandboxed host can initiate
the necessary NTFS block-device mount without additional privileges. The local
SDK exposes mountSingleVolume and the FSKit mount entitlement, but no ordinary
public FSBlockDeviceResource initializer. Do not infer from that missing
initializer that all public mounting routes are blocked: Disk Arbitration is a
separate route. Evaluate DADiskMountWithArguments for attached devices; reserve
mountSingleVolume for resource types the host can construct publicly. Do not
use private initializers, KVC, handcrafted archives or private entitlements.

### Evaluate an existing adapter before building one

Harbor's distinctive work is verified transfer, interruption recovery, safe
source removal and clear consent. Audit existing native FSKit NTFS projects
before implementing a new adapter. [xntfs](https://github.com/HuanchuanTech/xntfs)
is an initial candidate because it uses libntfs-3g and documents OS-specific mount
behavior. Its [macOS 27 implementation notes](https://github.com/HuanchuanTech/xntfs/blob/main/docs/macos27-support.md)
describe a sandboxed Disk Arbitration path for attached devices, separate from
direct raw-image mounting. Their reported tests include attached image
partitions; they explicitly distinguish that from physical USB validation.
This is encouraging project-reported evidence, not Harbor validation.

[NTFSKit](https://github.com/whereteam/ntfskit) and
[TT NTFS Native](https://github.com/dr-kbadawi/ttntfs) are additional research
candidates. Do not adopt their performance, safety or “first” marketing claims
as established facts. Compare actual source, provenance, engine modifications,
GPL terms, maintenance, malformed-image tests and default recovery behavior.
Some projects expose repair/formatting features that Harbor should not inherit
into its normal flow. Pin a reviewed revision and preserve its notices if code
is reused; no third-party driver code has been imported by this design work.

The extension must handle probe, filesystem checks, load, activation, file and
directory operations, flush, unmount and failure semantics. A byte-I/O adapter
alone is not a filesystem driver. Pin and audit the engine and its dependencies.
Use one coherent FSKit I/O/cache strategy; mixing cached metadata and direct I/O
over the same ranges can produce inconsistent data.

Enabling an extension may let macOS invoke its probing code for other disks.
Do not claim that it can never inspect unselected volumes. Require a fresh,
scoped write approval tied to a validated live partition before writable
activation. Prove the host-to-extension approval channel using supported APIs;
do not assume app-group or mount-option transport works without testing it.
Do not globally seize NTFS automounts or silently replace another installed driver.

## Mount feasibility gate: do this before building the full extension

Use a small signed test extension with disposable media. Answer, with logs:

1. Can a correctly provisioned Developer ID host and extension discover each
   other and expose accurate enabled/disabled state on each candidate OS?
2. Does the public Disk Arbitration path select a physical partition and route it to Harbor's
   extension when Apple's read-only NTFS handler already exists? Can it do so
   without FDA, a raw-device helper, private APIs or security-policy changes?
3. Which prompts occur on first install, second transfer, reconnection, reboot,
   signed update, revoked consent, standard-user and managed accounts?
4. Can a user's write approval be confined to the selected partition/job, and
   can it expire reliably without leaving an unrestricted mount policy?
5. Can normal unmount/flush restore native read-only access and release the
   extension process, including after a crash or denied authorization?

Start with images; then use an explicitly disposable physical NTFS disk. Image
success does not establish physical-disk privacy behavior. If this gate fails,
stop the seamless-NTFS claim. Keep prototype NTFS experimental. A separately
reviewed, narrowly authenticated signed broker is a fallback product decision,
with its background/FDA implications disclosed; it is not silently added to the
main design. A user with no Windows computer must not be sent into a Windows-only
setup loop. Do not offer reformatting as an automatic fallback.

## Transfer correctness and power-loss behavior

Use a durable state machine:

`Selected → Preflight → Copying → Verifying → Finalizing → Verified → Ejected`

Persist failure/cancellation/interruption states without marking them verified.
Keep source removal as a separate transaction with its own outcome and receipt.

Preflight checks source readability, destination space and writability, filename
compatibility, unsupported content, driver conflicts, and filesystem health.
An unclean or hibernated NTFS volume after a power cut stays read-only. Do not
clear dirty flags, remove hibernation files, force-unmount, format or auto-repair.
Explain the issue and preserve readable data, including when no Windows device
is available. A USB light alone is not evidence of mountability or disk health.

Copy to a unique private partial directory. Never merge into or replace a final
folder. SHA-256 each source stream, flush writes, independently read destination
content and validate the source remained stable. Validate names and paths from
untrusted disks/manifests; use directory-relative, no-follow operations to resist
ancestor symlink substitutions. A UUID/NTFS serial prevents accidental mix-ups,
but is spoofable and is not authentication of an adversarial disk.

Record a versioned journal with completed files. On restart/reconnect, revalidate
the device, manifest and completed file contents before resuming. Recopy changed
or incomplete files into fresh temporary files. Never trust a journal as proof
of valid data, and never resume onto a different disk just because its name matches.
The current prototype starts a fresh partial copy; resumability is new work.

Publish a durable receipt only after content verification and exclusive final
rename. Synchronize receipt and directory updates with explicit error handling.
If copying succeeded but receipt persistence failed, show that exact state and
disable source removal until the receipt is reconstructed and revalidated.

Before removing a source, recheck access, identities and both contents. For NTFS,
require a successful normal unmount/remount and independent read-back before
enabling source removal; establish permission/bookmark behavior for that step.
If the drive is busy or consent is denied, keep the source. Checksums and a clean
unmount improve assurance but cannot prove a drive's hardware cache survived a
power failure. Concurrent source mutation remains a race unless an actual snapshot
or equivalent immutability is available; reject observed changes and state limits.

Resource forks and unsupported metadata must be detected before writing. Preserve
supported attributes or block the affected transfer with a precise reason. Do
not describe Harbor as a complete Mac backup. Finder-generated .DS_Store files
need an explicit metadata policy, not a rule that ignores arbitrary hidden files.

## Failures should offer the next useful action

- Permission denied: explain the specific missing folder/extension approval and
  offer the relevant picker/settings destination; never loop through password dialogs.
- Drive disconnected: stop the job, keep the original, show **Reconnect to continue**.
- Disk full: retain the resumable partial state and show required free space.
- Verification failed: keep the source; offer a new copy or diagnostics. Never
  offer “remove original anyway” as part of the verified-transfer flow.
- Existing folder name: offer a new copy name and destination review, no overwrite.
- Busy drive at eject: show **Close files and retry**; never force-eject automatically.

## Privacy, installation and leaving cleanly

No login item, general privileged daemon, telemetry or network listener in the
default product. The filesystem extension may remain alive while its volume is
mounted even if the GUI quits; say so and offer normal eject before quitting.
No filesystem engine runs after its final mount is released, subject to the OS's
extension lifecycle. Measure actual process behavior rather than promising
instant process termination under every OS condition.

Keep all product code inside the signed app bundle. Use stable app/extension
identifiers and designated signing requirements across releases. Sign nested
components with their own entitlements before signing the containing app; do
not mutate installed binaries after approval. Verify notarized downloads on a
clean machine. Source builders use a separate development identity.

**Forget access & remove support** should stop new jobs, require normal unmount,
clear Harbor's bookmarks and job policy, guide the user through Apple's extension
disable UI when required, and verify the outcome. It must not reset all macOS
privacy settings or uninstall a dependency used by another app. Receipts and
partial data get separate, explicit retention choices. Never empty Trash, erase
personal files, or claim removal succeeded from a helper's exit status alone.

## Release sequence and acceptance criteria

**Source preview:** sanitize the source export, document current limits and
publish source without positioning the prototype as seamless NTFS software.

**Feasibility:** prove the mount and consent lifecycle on a clean installation.
Decide minimum OS from measured support, not the mere presence of FSKit. Start
validation with Apple Silicon on the current supported macOS release; older
systems and Intel remain unsupported until separately tested.

**Consumer beta:** add native NTFS integration only after the gate passes; add
bookmark persistence, durable jobs, resume, explicit cleanup and signing pipeline.
Test denial, power interruption, unplug/reconnect, sleep, full disks, malformed
NTFS images, Windows-created names, 4Kn/512e media, driver conflicts and updates.
Use sanitizers/fuzzing on the NTFS adapter. Contributor changes must not receive
release signing credentials in untrusted CI contexts.

**Release:** a clean machine must complete repeated transfers, an update and
cleanup without Terminal, Homebrew, security downgrades or an approval loop.
Record administrator prompts separately from pickers/privacy prompts for every
scenario. An account or OS policy requiring additional consent must produce a
clear supported limitation, not a hidden bypass. Source deletion stays blocked
after every failed or ambiguous verification path. Review third-party licenses
and corresponding-source delivery before distributing an NTFS-linked binary.

## Primary references and evidence boundary

- [FSKit](https://developer.apple.com/documentation/fskit/): user-space app-extension model.
- [FSBlockDeviceResource](https://developer.apple.com/documentation/fskit/fsblockdeviceresource): system-mediated partition I/O and cache rules.
- [FSClient mounting](https://developer.apple.com/documentation/fskit/fsclient/mountsinglevolume(resource:bundleid:options:completionhandler:)): mount entitlement and workflow; documentation currently marked beta.
- [Apple block-device mount discussion](https://developer.apple.com/forums/thread/831391): historical concern about direct block-resource construction; assess alongside the separate Disk Arbitration route.
- [Selected-file sandbox access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox): folder scope, bookmarks and renewal.
- [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution): distribution checks; not a guarantee of correctness.
- [macFUSE toggle defect](https://github.com/macfuse/macfuse/issues/1194): maintainer's category-view workaround; availability can change.

The source and local SDK were inspected on 8 November 2026. The completed
prototype transfer validates one configuration. No native Harbor FSKit NTFS
extension, signed upgrade lifecycle or consumer prompt budget has been validated.
