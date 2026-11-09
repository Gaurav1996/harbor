# Component notices

Harbor's original code is MIT licensed; see LICENSE. That does not relicense the
included third-party NTFS component or retained developer experiments.

## Included NTFS component: TT NTFS Native 0.4.1

Copyright 2026 TechTag GmbH and original Linux NTFS contributors. GPL-2.0.
Official source/release: https://github.com/dr-kbadawi/ttntfs/releases/tag/v0.4.1
Full license: NTFS-LICENSE.txt in the app, or LICENSES/GPL-2.0.txt in this source.

The complete official provider app is included unchanged as a separate nested
bundle. Its host is never launched by Harbor. Its vendor Developer ID signature
and FSKit profile are preserved; Harbor does not sign the extension as its own.
The official DMG checksum, release URL, vendor team and observed source-identity
mismatch are recorded in NTFS-PROVENANCE.json inside the app.

PRIVATE ACCEPTANCE CANDIDATE ONLY. The binary's embedded TTGitCommit could not be
matched to the public release-tag source. Do not publicly redistribute this
combined binary until complete corresponding-source verification is resolved.
An upstream source link is not asserted to satisfy that requirement.

## Retained legacy developer tooling

The consumer app contains no NTFS-3G executable, macFUSE binary or privileged
mount helper. HarborLegacyNTFS/HarborMount and the old engine scripts are excluded
from the consumer target. NTFS-3G portions retain GPL-2.0-or-later terms; see
LICENSES/GPL-2.0.txt and https://github.com/tuxera/ntfs-3g. macFUSE is not bundled
and retains its separate terms. Apple frameworks/toolchain are supplied by Apple
under their own terms.
