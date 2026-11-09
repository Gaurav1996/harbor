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

The app includes upstream's complete v0.4.1 source archive, LICENSE and COPYRIGHT
under Contents/Resources/ThirdParty, including its interfaces and build scripts.
The release also offers these alongside the app. Source commit:
3891dcbb5eebce1baff5c8fe5aee3c00ff11df9e.

Upstream designates its public repository as the release source. Its binary's
embedded commit differs from the public tag and has not been explained yet.
Independent source-to-binary identity is not confirmed; see
https://github.com/dr-kbadawi/ttntfs/issues/5. The beta does not claim otherwise.

## Retained legacy developer tooling

The consumer app contains no NTFS-3G executable, macFUSE binary or privileged
mount helper. HarborLegacyNTFS/HarborMount and the old engine scripts are excluded
from the consumer target. NTFS-3G portions retain GPL-2.0-or-later terms; see
LICENSES/GPL-2.0.txt and https://github.com/tuxera/ntfs-3g. macFUSE is not bundled
and retains its separate terms. Apple frameworks/toolchain are supplied by Apple
under their own terms.
