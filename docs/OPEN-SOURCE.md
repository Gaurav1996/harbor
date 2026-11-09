# Release and source status

Harbor's repository is public at https://github.com/Gaurav1996/harbor. The user
approved publishing the app as an early beta with the upstream-designated driver
source, notices and the unresolved provenance question disclosed.

## Included third-party component

TT NTFS Native 0.4.1 remains an unchanged, independently signed GPL-2.0 component.
Harbor's own code is MIT licensed. The app carries the complete upstream release-
tag source archive in `Contents/Resources/ThirdParty`, together with upstream's
LICENSE, COPYRIGHT and source/build information. The same archive and notices
are available beside the beta download. End users do not need to fetch a driver.

The source commit is `3891dcbb5eebce1baff5c8fe5aee3c00ff11df9e`, tree
`864515292bf94ee23f1ee5e9b97c927dde6bdb9a`. Its 343 tracked files were checked
against the public tree, its static core compiled, and all 255 global NTFS C
symbols in the shipped extension were accounted for in that core or bridge.
Upstream's official release identifies its source as the public repository.

The embedded binary commit is still `v0.3-ui-fixes-112-gfc418d028`, which does not
resolve publicly. Independent source-to-binary identity remains unconfirmed.
[The audit](DRIVER-SOURCE-VERIFICATION.md) and
[upstream question](https://github.com/dr-kbadawi/ttntfs/issues/5) remain open;
publishing the beta does not convert this uncertainty into a verified match.
Do not describe it as independently source-verified or as a security audit.

## Build and publication

The builder requires the exact pinned binary DMG and audited upstream source
archive, checks their hashes, validates vendor signatures and Gatekeeper
assessment, and includes source/notices with the app. It fails if source or
notices are missing. `HARBOR_PUBLIC_RELEASE=1` uses this same mandatory-source
packaging path. The old blanket publication guard has been replaced with these
packaging requirements; the independent-verification flag stays false.

Only publish an allowlisted source export and the reviewed app package. Never
upload this working directory or local history wholesale. The exporter rejects
symlinks, binary content, machine home paths and common credential signatures.
Review the exact tree; a scan is not proof of privacy. Exclude personal receipts,
photos, setup history, signing credentials, .integration and .build. Use gh for
Git-related operations.

Harbor is ad-hoc signed, not Developer ID-signed or notarized. The beta requires
Apple Silicon and macOS 26+. Broad compatibility, clean-machine installation,
signed updates and power-loss validation remain incomplete. No claim of a
warning-free download or zero macOS approval prompts is made.
