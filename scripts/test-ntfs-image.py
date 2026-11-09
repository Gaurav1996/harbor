#!/usr/bin/env python3
"""Test Harbor's NTFS path on a newly created, disposable image, never a real HDD."""
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import uuid

project = Path(__file__).resolve().parent.parent
run = project / ".integration" / str(uuid.uuid4())
run.mkdir(parents=True)
engine = next((Path(p) for p in ("/opt/homebrew/sbin/mkntfs", "/opt/homebrew/bin/mkntfs", "/usr/local/sbin/mkntfs") if Path(p).is_file()), None)
if engine is None:
    raise SystemExit("Install NTFS-3G before running this integration test.")

def command(*args):
    return subprocess.check_output(args)

# Format a regular file first. No mkntfs invocation ever receives a /dev path.
partition = run / "partition.raw"
partition_size = 96 * 1024 * 1024
with partition.open("xb") as f:
    f.truncate(partition_size)
subprocess.run([str(engine), "--force", "--quick", "--label", "HarborDisposable", str(partition)], check=True)
image = run / "disposable.img"
mbr = bytearray(512)
mbr[446:462] = struct.pack("<B3sB3sII", 0, b"\x00\x02\x00", 0x07, b"\xfe\xff\xff", 2048, partition_size // 512)
mbr[510:512] = b"\x55\xaa"
with image.open("xb") as out, partition.open("rb") as src:
    out.write(mbr)
    out.seek(1024 * 1024)
    shutil.copyfileobj(src, out)
    out.flush()
    os.fsync(out.fileno())

attached = plistlib.loads(command("/usr/bin/hdiutil", "attach", "-nomount", "-nobrowse", "-imagekey", "diskimage-class=CRawDiskImage", "-plist", str(image)))
devices = [e["dev-entry"] for e in attached["system-entities"] if "dev-entry" in e]
partition_device = next((d for d in devices if d.endswith("s1")), None)
whole = next((d for d in devices if d.rsplit("/", 1)[-1].removeprefix("disk").isdigit()), None)
if not partition_device or not whole:
    raise SystemExit(f"Unexpected image device layout: {devices}; inspect {image}")
try:
    # Ordinary macOS mount is read-only. The test exercises Harbor's own FSKit helper.
    subprocess.run(["/usr/sbin/diskutil", "mount", partition_device], check=True)
    env = os.environ.copy()
    env["CLANG_MODULE_CACHE_PATH"] = str(project / ".build/ModuleCache")
    env["HARBOR_TEST_IMAGE"] = str(image)
    env["HARBOR_TEST_DEVICE"] = partition_device
    if "--authorized" in sys.argv:
        env["HARBOR_TEST_FORCE_AUTH"] = "1"
    subprocess.run(["/usr/bin/swift", "test", "--disable-sandbox", "--filter", "TransferTests/testNTFSImageIntegration"], cwd=project, env=env, check=True)
finally:
    # Detach only the device returned by attaching this fresh image. Never force.
    subprocess.run(["/usr/bin/hdiutil", "detach", whole], check=False)
print(f"Integration passed. Disposable artifacts retained at {run}")
