# Publication preparation

The source-only beta is published at https://github.com/Gaurav1996/harbor.
The user has reported a successful physical-drive transfer. That acceptance does
not clear the combined app binary for redistribution. Build/export scripts do
not upload anything; publication is a separate maintainer action.

Harbor 0.3 addresses the consumer setup by including an unchanged, independently
signed official TT NTFS Native bundle. Original Harbor sources remain MIT; the
provider is separate GPL-2.0 code, never re-signed or claimed as Harbor's own
extension. Pin/check its official DMG hash, signature, version and Gatekeeper
assessment. The end-user app needs no downloader or separate installer.

PUBLIC BINARY REDISTRIBUTION IS BLOCKED. Its embedded TTGitCommit does not match
the public release-tag source and could not be resolved in the public repository.
Do not ship the combined binary publicly until complete corresponding source is
established and the applicable notices/source/build materials are prepared.
A source URL alone is not asserted to solve this. Private local testing and
source-code publication are different activities. HARBOR_PUBLIC_RELEASE=1 is
refused by the build until maintainers deliberately resolve this gate.

Run scripts/prepare-public-source.py to prepare the explicit allowlisted original
source tree under .publication/Harbor-0.3.0-beta.1-source. It rejects symlinks, binary
content, machine home paths and common token/private-key patterns and writes a
SHA-256 manifest without replacing an existing candidate. Review the exact tree;
a scan is not proof of privacy. Do not upload the working directory or private
history wholesale. Exclude receipts, photos, setup history, vendor binaries,
signing profiles, credentials, .integration and .build. Use only gh for Git work.

Before a public release: establish the maintainer/reporting route, verify the
exact source tree, test clean-machine installation/approval/disable/eject/update,
use physical disposable media for hardware/interruption cases, and verify the
actual downloaded artifact. Harbor is currently sandboxed/ad-hoc signed, not
notarized. Never promise warning-free downloads or zero macOS authorizations.
Retained legacy NTFS-3G/macFUSE experiments retain their separate licensing and
are excluded from the consumer app.
