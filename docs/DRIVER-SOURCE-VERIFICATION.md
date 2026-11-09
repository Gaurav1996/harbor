# NTFS driver source verification

10 November 2026. **Strong corroboration; source-to-binary identity is not yet confirmed.**
The early app beta carries the source archive designated by upstream. Its
independent source-to-binary identity remains unconfirmed. This report does
not allege an upstream license violation. It records what was checked and what
information is still missing.

## Binary under review

The unmodified official [TT NTFS Native 0.4.1 release](https://github.com/dr-kbadawi/ttntfs/releases/tag/v0.4.1):

| Evidence | Observed value |
| --- | --- |
| Official asset | `TT-NTFS-Native-0.4.1.dmg` |
| DMG SHA-256 | `1a4d90309bab95772ea5efefdf069da0f53de5c481b4e3a061b4fc9bd4fad5c4` |
| Vendor signing team | `HU5S996C2K` |
| App / extension version | `0.4.1` / build `164` |
| App / extension `TTGitCommit` | `v0.3-ui-fixes-112-gfc418d028` |
| Recorded build toolchain | Xcode 26.2, build `17C52`; macOS SDK 26.2, build `25C57` |
| Public release commit | `3891dcbb5eebce1baff5c8fe5aee3c00ff11df9e` |
| Public release tree | `864515292bf94ee23f1ee5e9b97c927dde6bdb9a` |

The downloaded asset digest matches GitHub's release metadata. Vendor signatures,
embedded extension profile and Gatekeeper assessment were checked separately.
Those establish artifact identity and signing status, not corresponding source.

## Source and history checks completed

1. Resolved the annotated v0.4.1 tag to the commit/tree above.
2. Enumerated all **164 commits** reachable from the release tag. That matches the
   binary's build number. The public comparison from `v0.3-ui-fixes` to `v0.4.1`
   contains exactly **112 commits**, matching its embedded description's distance.
3. Queried the embedded `fc418d028` through the upstream commit API and a public
   exact-hash commit search. The commit API reported no such commit; search found
   no matches. These checks cannot rule out private or rewritten history.
4. Downloaded the source archive pinned to the full public release commit. All
   **343 regular files** matched the public Git tree's blob identities. No source
   files were omitted, and no submodules needed separate fetching. The observed
   source-archive SHA-256 was
   `7abc7cc56d4c98881396df9eb303192f17395a5cbf5bd0b79ebf87f10d3af9b4`.
5. Reviewed the public version-stamping and packaging scripts. They derive
   `TT_GIT_COMMIT` from the build checkout and stamp it in both Info.plists.
   Source includes the core, FSKit/host code, interfaces, build descriptions,
   license/notices and packaging scripts.

Primary history: [tag comparison](https://github.com/dr-kbadawi/ttntfs/compare/v0.3-ui-fixes...v0.4.1),
[release commit](https://github.com/dr-kbadawi/ttntfs/commit/3891dcbb5eebce1baff5c8fe5aee3c00ff11df9e),
[version script](https://github.com/dr-kbadawi/ttntfs/blob/v0.4.1/fskit/scripts/version.sh),
[packaging script](https://github.com/dr-kbadawi/ttntfs/blob/v0.4.1/fskit/scripts/package.sh).

## Isolated build and symbol checks

The verified public release's static C core compiled successfully for arm64 with
sanitizers/tests off and a macOS 26 deployment target. This used the available
Xcode 27.1 / Swift 6.4 toolchain, not the binary's recorded Xcode 26.2 toolchain.
No replacement filesystem extension was built, registered or loaded. No installed
app, extension switch or personal drive was changed for this audit.

Of the **255 globally defined `ntfs*` symbols** in the shipped extension, **248**
were defined by the rebuilt static core. The other **7** are present in the
public FSKit bridge source. No symbol in that limited set was unaccounted for.
This supports the source match, but names alone do not establish matching code,
cover every Swift function, or prove the absence of extra modifications.

## Remaining gap and release decision

The matching version, build/history counts, source completeness and symbol
coverage are consistent with the published tag being the intended source.
A pre-publication or rewritten commit history could explain the different hash;
that is an inference, not a verified explanation.

We still need authoritative provenance connecting this exact official DMG to the
published tree, or the actual source revision/archive and any additional build
patches used. A byte-for-byte signed/notarized rebuild is **not** the requirement:
compiler versions, timestamps and signing can differ. The distinction is explained
in the [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#MustSourceBuildToMatchExactHashOfBinary).

The maintainer approved publishing an early beta using upstream's release source
designation, with that complete archive, build materials and notices inside the
app and beside the download. The independent-verification flag stays false, and
[upstream clarification](https://github.com/dr-kbadawi/ttntfs/issues/5) is still
pending. This release decision does not confirm the embedded hash's explanation
or claim independent proof of source-to-binary identity. Distribution validation
and provenance follow-up remain open work.
