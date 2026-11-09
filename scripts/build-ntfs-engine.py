#!/usr/bin/env python3
# NTFS-3G excerpts/adaptations below retain upstream GPL-2.0-or-later licensing.
# See NOTICE.md and LICENSES/GPL-2.0.txt; original Harbor tooling remains MIT.
"""Build a local NTFS-3G with one Darwin/FSKit compatibility adjustment.

The original setuid/setgid refusal stays intact. No privileges are acquired;
the OS still enforces ordinary user's read/write access to the device.
"""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tarfile

project = Path(__file__).resolve().parent.parent
archive = Path(subprocess.check_output(["/opt/homebrew/bin/brew", "--cache", "--build-from-source", "gromgit/fuse/ntfs-3g-mac"], text=True).strip())
expected = "8a75293f07bf40df5701d296de32a4cb0e46d6ae135abb4f41b438df9868a390"
assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected, "Source archive checksum mismatch"
vendor = project / ".vendor"
vendor.mkdir(exist_ok=True)
source = vendor / "ntfs-3g-2026.9.28"
if not source.exists():
    with tarfile.open(archive) as tar:
        tar.extractall(vendor, filter="data")
path = source / "src/ntfs-3g.c"
code = path.read_text()
old = "#if !(defined(__sun) && defined (__SVR4))\n\t/* Always use fuseblk for block devices unless it's surely missing. */"
new = """/* HARBOR_FSKIT_COMPAT: Linux fuseblk is not used by macOS FSKit.
 * Permit the already-authorized user to open a device with ordinary OS
 * permissions when the FSKit backend is explicitly selected. This does
 * not change setuid refusal, device permissions, or NTFS recovery policy.
 */
#ifdef __APPLE__
    {
        const char *backend = strstr(parsed_options, "backend=fskit");
        if (backend && (backend == parsed_options || backend[-1] == ',')
            && (backend[13] == ',' || backend[13] == '\\0'))
            fstype = FSTYPE_FUSE;
    }
#endif

#if !(defined(__sun) && defined (__SVR4))
\t/* Always use fuseblk for block devices unless it's surely missing. */"""
if "HARBOR_FSKIT_COMPAT" not in code:
    assert code.count(old) == 1, "Upstream source changed; inspect before patching"
    path.write_text(code.replace(old, new))
io_path = source / "libntfs-3g/unix_io.c"
io_code = io_path.read_text()
io_old = "\t*(int*)dev->d_private = open(dev->d_name, flags);"
io_new = """/* HARBOR_AUTHORIZED_FD: duplicate the single descriptor explicitly
     * handed over by HarborMount. Reopening a root-owned device through
     * /dev/fd would repeat a pathname permission check after privilege drop.
     * dup preserves the existing capability; it grants no new device access.
     */
#ifdef __APPLE__
    if (!strcmp(dev->d_name, "/dev/fd/3")) {
        int inherited_flags = fcntl(3, F_GETFL);
        if (inherited_flags < 0 ||
            (((flags & O_ACCMODE) == O_RDWR) &&
             ((inherited_flags & O_ACCMODE) != O_RDWR))) {
            errno = EACCES;
            *(int*)dev->d_private = -1;
        } else {
            *(int*)dev->d_private = fcntl(3, F_DUPFD_CLOEXEC, 4);
        }
    } else {
        *(int*)dev->d_private = open(dev->d_name, flags);
    }
#else
    *(int*)dev->d_private = open(dev->d_name, flags);
#endif"""
if "HARBOR_AUTHORIZED_FD" not in io_code:
    assert io_code.count(io_old) == 1, "Upstream I/O source changed; inspect before patching"
    io_path.write_text(io_code.replace(io_old, io_new))
env = os.environ.copy()
env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/opt/libtool/libexec/gnubin:" + env["PATH"]
env["PKG_CONFIG_PATH"] = "/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
env["CPPFLAGS"] = "-I/usr/local/include -I/opt/homebrew/opt/gettext/include"
env["LDFLAGS"] = "-L/usr/local/lib -L/opt/homebrew/opt/gettext/lib -lintl"
prefix = vendor / "engine"
def run(*args):
    subprocess.run(args, cwd=source, env=env, check=True)
run("./autogen.sh")
run("./configure", f"--prefix={prefix}", "--with-fuse=external", "--disable-shared", "--enable-static", "--disable-ntfsprogs", "--disable-ldconfig")
run("make", "-j4")
prefix.mkdir(exist_ok=True)
shutil.copy2(source / "src/ntfs-3g", prefix / "ntfs-3g-fskit")
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(prefix / "ntfs-3g-fskit")], check=True)
print(f"Built {prefix / 'ntfs-3g-fskit'}")
