# Contributing

Start with README.md, docs/USER-GUIDE.md and docs/IMPLEMENTATION-STATUS.md.
PRODUCT-DESIGN.md includes future proposals, not an implemented feature checklist.

Use synthetic folders and explicitly disposable disk images. Never format,
repair or interrupt personal media. Ordinary tests must not request administrator
authorization, install a driver or change macOS privacy settings.

Run `swift test --disable-sandbox` and `bash scripts/build-app.sh`. The flag affects
SwiftPM's build sandbox only. Integration tests skip unless explicitly configured;
they are not ordinary CI prerequisites. NTFS-SETUP.md is legacy developer tooling,
not consumer setup.

Changes affecting verification or removal need meaningful failure tests. Preserve
originals on uncertainty, never overwrite final folders, and never make permanent
deletion or forced recovery part of the normal flow. Distinguish unit, sandboxed
UI, disposable-image and physical-hardware evidence.

Use synthetic reproductions and redacted diagnostics. Use only the gh CLI for
Git and GitHub workflows. Do not publish local artifacts or signing credentials.
