import Foundation
import Darwin
import HarborCore
import HarborLegacyNTFS

// One-shot authorized capability handoff, not a privileged service.
// Opens only an identified external NTFS partition, drops every root identity,
// then execs the adjacent filesystem engine with that one inherited descriptor.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
let args = CommandLine.arguments
guard args.count == 7, geteuid() == 0,
      args[1].range(of: "^disk[0-9]+s[0-9]+$", options: .regularExpression) != nil,
      let uid = UInt32(args[4]), let gid = UInt32(args[5]), uid >= 501 else { fail("Invalid authorized mount request.") }
let device = args[1], expectedUUID = args[2], expectedSerial = args[3]
guard !expectedUUID.isEmpty || !expectedSerial.isEmpty else { fail("A partition identity is required.") }
var console = stat()
guard stat("/dev/console", &console) == 0, console.st_uid == uid,
      let account = getpwuid(uid), account.pointee.pw_gid == gid else { fail("The requested user must be the logged-in console user.") }
let userHome = String(cString: account.pointee.pw_dir)
let mount = URL(fileURLWithPath: args[6]).standardizedFileURL
let permittedBase = URL(fileURLWithPath: userHome).appendingPathComponent("Library/Application Support/Harbor/Mounts").path + "/"
guard mount.path.hasPrefix(permittedBase), UUID(uuidString: mount.lastPathComponent) != nil else { fail("Invalid private mount location.") }
let engine = URL(fileURLWithPath: args[0]).resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("ntfs-3g-fskit").path
guard FileManager.default.isExecutableFile(atPath: engine) else { fail("Adjacent NTFS engine is missing.") }
do {
    let initial = try SystemCommand.info(device)
    guard initial["Internal"] as? Bool == false,
          initial["FilesystemType"] as? String == "ntfs",
          initial["WritableMedia"] as? Bool == true,
          expectedUUID.isEmpty || initial["VolumeUUID"] as? String == expectedUUID else { fail("External NTFS identity check failed.") }
    _ = try SystemCommand.run("/usr/sbin/diskutil", ["unmount", device])
    let current = try SystemCommand.info(device)
    guard current["Internal"] as? Bool == false,
          current["DeviceTreePath"] as? String == initial["DeviceTreePath"] as? String,
          current["Size"] as? NSNumber == initial["Size"] as? NSNumber,
          expectedUUID.isEmpty || current["VolumeUUID"] as? String == expectedUUID else { fail("Partition identity changed while unmounting.") }
    let fd = open("/dev/" + device, O_RDWR | O_EXCL)
    guard fd >= 0 else { fail("Cannot open selected partition: " + String(cString: strerror(errno))) }
    var sector = [UInt8](repeating: 0, count: 512)
    let count = sector.withUnsafeMutableBytes { pread(fd, $0.baseAddress, 512, 0) }
    guard count == 512, Array(sector[3..<11]) == Array("NTFS    ".utf8), sector[510] == 0x55, sector[511] == 0xaa else { fail("Invalid NTFS boot sector.") }
    let serial = sector[72..<80].map { String(format: "%02x", $0) }.joined()
    guard expectedSerial.isEmpty || serial == expectedSerial else { fail("NTFS serial changed.") }
    if fd != 3 { guard dup2(fd, 3) == 3 else { fail("Cannot hand off device descriptor.") }; close(fd) }
    guard fcntl(3, F_SETFD, 0) == 0 else { fail("Cannot retain device descriptor.") }
    var group = gid
    guard setgroups(1, &group) == 0, setgid(gid) == 0, setuid(uid) == 0,
          getuid() == uid, geteuid() == uid, getgid() == gid, getegid() == gid else { fail("Cannot permanently drop administrator privileges.") }
    setenv("HOME", userHome, 1)
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
    FileHandle.standardOutput.write(Data(("HARBOR_SERIAL=" + serial + "\n").utf8))
    let parameters = [engine, "/dev/fd/3", mount.path, "-o", "backend=fskit,norecover,windows_names,uid=\(uid),gid=\(gid),umask=022"]
    var pointers = parameters.map { strdup($0) } + [nil]
    pointers.withUnsafeMutableBufferPointer { _ = execv(engine, $0.baseAddress!) }
    fail("Cannot start the unprivileged NTFS engine: " + String(cString: strerror(errno)))
} catch { fail(error.localizedDescription) }
