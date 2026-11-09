#!/usr/bin/env python3
"""Prepare a new, reviewed source tree; never publish or copy private artifacts."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
FILES = (
    ".gitignore", "LICENSE", "NOTICE.md", "README.md", "NTFS-SETUP.md",
    "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md",
    ".github/workflows/ci.yml", ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/ISSUE_TEMPLATE/config.yml", "docs/assets/harbor.svg", "Package.swift", "LICENSES/GPL-2.0.txt",
    "Sources/Harbor/App.swift", "Sources/Harbor/TransferModel.swift",
    "Sources/Harbor/FolderAccess.swift", "Sources/Harbor/DriverSupport.swift",
    "Sources/HarborCore/Transfer.swift", "Sources/HarborCore/TransferBatch.swift", "Sources/HarborCore/Drives.swift",
    "Sources/HarborLegacyNTFS/Volumes.swift", "Sources/HarborMount/main.swift",
    "Sources/HarborCore/TransferRecords.swift",
    "Tests/HarborCoreTests/TransferTests.swift",
    "Tests/HarborCoreTests/TransferRecordTests.swift", "Tests/HarborCoreTests/TransferBatchTests.swift",
    "Tests/HarborCoreTests/NativeDriverTests.swift", "config/Harbor.entitlements",
    "scripts/build-app.sh", "scripts/make-icon.swift", "scripts/include-ntfs-provider.py", "scripts/build-ntfs-engine.py",
    "scripts/setup-ntfs.sh", "scripts/test-ntfs-image.py",
    "scripts/prepare-public-source.py", "docs/PRODUCT-DESIGN.md",
    "docs/LEARNINGS.md", "docs/OPEN-SOURCE.md", "docs/USER-GUIDE.md",
    "docs/IMPLEMENTATION-STATUS.md",
)
RULES = (
    ("machine home path", re.compile(r"/Users/[A-Za-z0-9_.-]+/")),
    ("private key", re.compile(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})")),
)

def main():
    target = ROOT / ".publication" / "Harbor-0.3.0-beta.1-source"
    if target.exists() or target.is_symlink():
        raise SystemExit("Candidate already exists. Review it before preparing a new one.")
    if target.parent.is_symlink():
        raise SystemExit("Refusing a symlink publication directory.")
    payloads = {}
    for relative in FILES:
        source = ROOT / relative
        if source.is_symlink() or any(p.is_symlink() for p in source.parents if p != ROOT.parent):
            raise SystemExit(f"Refusing a symlink in {relative}")
        if not source.is_file() or not source.resolve().is_relative_to(ROOT):
            raise SystemExit(f"Missing or invalid allowlisted file: {relative}")
        data = source.read_bytes()
        if b"\x00" in data:
            raise SystemExit(f"Binary content rejected: {relative}")
        text = data.decode("utf-8")
        for label, rule in RULES:
            if rule.search(text):
                raise SystemExit(f"Publication blocked: {label} in {relative}")
        payloads[relative] = data
    target.mkdir(parents=True)
    try:
        manifest = {}
        for relative, data in payloads.items():
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            manifest[relative] = hashlib.sha256(data).hexdigest()
        (target / "SOURCE-MANIFEST.json").write_text(
            json.dumps({"schema": 1, "files": manifest}, indent=2, sort_keys=True) + "\n"
        )
    except BaseException:
        shutil.rmtree(target)
        raise
    print(f"Prepared {len(payloads)} allowlisted files at {target}")
    print("Review this tree before publication. Nothing has been uploaded.")

if __name__ == "__main__":
    main()
