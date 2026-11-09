import Foundation
import Darwin
import HarborCore

public struct Volume: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let mount: URL
    public let device: String
    public let uuid: String
    public let filesystem: String
    public let readOnly: Bool
    public var free: Int64
    public var ntfsSerial: String? = nil
    public var mountFSID0: Int32? = nil
    public var mountFSID1: Int32? = nil
}

public enum SystemCommand {
    public static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = pipe
        try task.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw TransferFailure(String(data: output, encoding: .utf8) ?? "Command failed.")
        }
        return output
    }
    public static func info(_ path: String) throws -> [String: Any] {
        let data = try run("/usr/sbin/diskutil", ["info", "-plist", path])
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw TransferFailure("Could not read drive information.")
        }
        return result
    }
    public static func volumes() -> [Volume] {
        let roots = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
        let managed = NTFS.managedVolumes()
        let volumes: [Volume] = roots.compactMap { root in
            guard let info = try? info(root.path), info["Internal"] as? Bool == false,
                  info["BusProtocol"] as? String != "Disk Image",
                  let device = info["DeviceIdentifier"] as? String,
                  let mount = info["MountPoint"] as? String, !mount.isEmpty,
                  !managed.contains(where: { $0.device == device }) else { return nil }
            return Volume(id: device, name: info["VolumeName"] as? String ?? root.lastPathComponent,
                          mount: URL(fileURLWithPath: mount), device: device,
                          uuid: info["VolumeUUID"] as? String ?? "",
                          filesystem: info["FilesystemType"] as? String ?? "unknown",
                          readOnly: !(info["WritableVolume"] as? Bool ?? false),
                          free: (info["FreeSpace"] as? NSNumber)?.int64Value ?? 0)
        }
        return (volumes + managed).sorted { $0.name < $1.name }
    }
}

public enum NTFS {
    private static let fm = FileManager.default
    private static var support: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Harbor") }
    private static var recordsURL: URL { support.appendingPathComponent("mounts.json") }
    public static var engine: String? {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ntfs-3g-fskit").path,
                project.appendingPathComponent(".vendor/engine/ntfs-3g-fskit").path].compactMap { $0 }.first {
            fm.isExecutableFile(atPath: $0)
        }
    }
    public static var hasMacFUSE: Bool {
        guard let plist = NSDictionary(contentsOfFile: "/Library/Filesystems/macfuse.fs/Contents/Info.plist"),
              let version = plist["CFBundleShortVersionString"] as? String else { return false }
        return version.compare("5.0", options: .numeric) != .orderedAscending
    }
    private static var helper: String? {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("HarborMount").path,
                project.appendingPathComponent("dist/Harbor.app/Contents/MacOS/HarborMount").path].compactMap { $0 }.first {
            fm.isExecutableFile(atPath: $0)
        }
    }
    private static func authorize(_ volume: Volume, mount: URL, expectedSerial: String?) throws -> String {
        guard let helper else { throw TransferFailure("The one-shot partition authorization helper is missing.") }
        let arguments = [helper, volume.device, volume.uuid, expectedSerial ?? "", String(getuid()), String(getgid()), mount.path]
        let command = arguments.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let output = try SystemCommand.run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        guard let text = String(data: output, encoding: .utf8),
              let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("HARBOR_SERIAL=") }) else {
            throw TransferFailure("The partition authorization did not return its verified NTFS identity.")
        }
        let result = String(line.dropFirst("HARBOR_SERIAL=".count))
        guard result.range(of: "^[a-f0-9]{16}$", options: .regularExpression) != nil else { throw TransferFailure("Invalid NTFS serial from connection helper.") }
        return result
    }
    private static func eligible(_ volume: Volume) throws {
        guard volume.filesystem == "ntfs", volume.readOnly,
              volume.device.range(of: "^disk[0-9]+s[0-9]+$", options: .regularExpression) != nil,
              volume.uuid.isEmpty || volume.uuid.range(of: "^[A-Fa-f0-9-]{8,64}$", options: .regularExpression) != nil else {
            throw TransferFailure("This is not an eligible read-only NTFS partition.")
        }
    }
    public static func mountArguments(volume: Volume, mount: URL) throws -> [String] {
        try eligible(volume)
        return ["/dev/" + volume.device, mount.path, "-o",
                "backend=fskit,norecover,windows_names,uid=\(getuid()),gid=\(getgid()),umask=022"]
    }
    private static func snapshot(_ mount: URL) throws -> statfs {
        var value = statfs()
        guard statfs(mount.path, &value) == 0 else { throw TransferFailure("The destination is no longer available.") }
        return value
    }
    private static func isFSKitMount(_ mount: URL) -> Bool {
        guard var value = try? snapshot(mount) else { return false }
        let kind = withUnsafePointer(to: &value.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
        let point = withUnsafePointer(to: &value.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
        }
        return kind == "macfuse" && URL(fileURLWithPath: point).resolvingSymlinksInPath().path == mount.resolvingSymlinksInPath().path
    }
    /// Read only: identify the physical partition through its NTFS boot-sector serial.
    public static func serial(_ device: String) throws -> String {
        guard device.range(of: "^disk[0-9]+s[0-9]+$", options: .regularExpression) != nil else {
            throw TransferFailure("Invalid partition identifier.")
        }
        // A single aligned boot-sector read uses the raw interface; the block
        // interface can be busy while macOS has its read-only NTFS mount open.
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/r" + device))
        defer { try? file.close() }
        let bytes = try file.read(upToCount: 512) ?? Data()
        guard bytes.count == 512, Array(bytes[3..<11]) == Array("NTFS    ".utf8),
              bytes[510] == 0x55, bytes[511] == 0xaa else { throw TransferFailure("The selected partition is not an NTFS volume.") }
        return bytes[72..<80].map { String(format: "%02x", $0) }.joined()
    }
    public static func validate(_ volume: Volume, requireWritable: Bool = true) throws {
        let current = try SystemCommand.info(volume.device)
        guard current["Internal"] as? Bool == false else { throw TransferFailure("The external drive changed. Refresh the drive list.") }
        if let expected = volume.ntfsSerial {
            let samePartition = !volume.uuid.isEmpty ? current["VolumeUUID"] as? String == volume.uuid : (try serial(volume.device)) == expected
            guard samePartition, isFSKitMount(volume.mount) else {
                throw TransferFailure("The NTFS drive disconnected or its mount changed.")
            }
            let value = try snapshot(volume.mount)
            guard value.f_fsid.val.0 == volume.mountFSID0, value.f_fsid.val.1 == volume.mountFSID1,
                  !requireWritable || value.f_flags & UInt32(MNT_RDONLY) == 0 else {
                throw TransferFailure("The NTFS mount is no longer the verified writable volume.")
            }
        } else {
            guard (current["VolumeUUID"] as? String ?? "") == volume.uuid,
                  current["MountPoint"] as? String == volume.mount.path,
                  !requireWritable || current["WritableVolume"] as? Bool == true else {
                throw TransferFailure("The selected drive changed or is read-only. Refresh the drive list.")
            }
        }
    }
    private static func records() -> [Volume] {
        guard let data = try? Data(contentsOf: recordsURL) else { return [] }
        return (try? JSONDecoder().decode([Volume].self, from: data)) ?? []
    }
    private static func save(_ volumes: [Volume]) throws {
        try fm.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(volumes).write(to: recordsURL, options: .atomic)
    }
    public static func managedVolumes() -> [Volume] {
        records().compactMap { volume in
            guard (try? validate(volume)) != nil, let value = try? snapshot(volume.mount) else { return nil }
            var result = volume
            result.free = Int64(value.f_bavail) * Int64(value.f_bsize)
            return result
        }
    }
    /// Uses ordinary user permissions and FSKit only. No root, chmod, repair or force.
    @discardableResult public static func enable(_ volume: Volume, forceAuthorization: Bool = false) throws -> Volume {
        try eligible(volume)
        guard let engine else { throw TransferFailure("Build the bundled FSKit-compatible engine using the setup guide.") }
        let current = try SystemCommand.info(volume.device)
        guard current["Internal"] as? Bool == false,
              (current["VolumeUUID"] as? String ?? "") == volume.uuid,
              current["FilesystemType"] as? String == "ntfs",
              current["WritableVolume"] as? Bool == false,
              current["WritableMedia"] as? Bool == true else {
            throw TransferFailure("The selected partition changed or its media is read-only. Refresh the drives.")
        }
        let needsAuthorization = forceAuthorization || access("/dev/" + volume.device, R_OK | W_OK) != 0
        let readableSerial = try? serial(volume.device)
        guard !needsAuthorization || !volume.uuid.isEmpty || readableSerial != nil else {
            throw TransferFailure("The partition needs authorization but has no verifiable UUID or serial.")
        }
        let base = support.appendingPathComponent("Mounts")
        try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let mount = base.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        do {
            let expected: String
            if needsAuthorization {
                expected = try authorize(volume, mount: mount, expectedSerial: readableSerial)
            } else {
                expected = try serial(volume.device)
                _ = try SystemCommand.run("/usr/sbin/diskutil", ["unmount", volume.device])
                guard try serial(volume.device) == expected else { throw TransferFailure("The source partition changed during connection.") }
                _ = try SystemCommand.run(engine, try mountArguments(volume: volume, mount: mount))
            }
            for _ in 0..<30 {
                if isFSKitMount(mount) { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard isFSKitMount(mount) else {
                throw TransferFailure("FSKit did not create a mount. Check macFUSE under System Settings → General → Login Items → By Category → File System Extensions.")
            }
            let value = try snapshot(mount)
            var connected = Volume(id: volume.id, name: volume.name, mount: mount,
                                   device: volume.device, uuid: volume.uuid, filesystem: "ntfs", readOnly: false,
                                   free: Int64(value.f_bavail) * Int64(value.f_bsize))
            connected.ntfsSerial = expected
            connected.mountFSID0 = value.f_fsid.val.0; connected.mountFSID1 = value.f_fsid.val.1
            try validate(connected)
            try save(records().filter { $0.id != volume.id } + [connected])
            return connected
        } catch {
            if !isFSKitMount(mount) {
                // rmdir cannot remove any user content or follow a directory symlink.
                _ = rmdir(mount.path)
                let same = !volume.uuid.isEmpty ? (try? SystemCommand.info(volume.device)["VolumeUUID"] as? String) == volume.uuid : (readableSerial != nil && (try? serial(volume.device)) == readableSerial)
                if same {
                    _ = try? SystemCommand.run("/usr/sbin/diskutil", ["mount", volume.device])
                }
            }
            throw error
        }
    }
    public static func disconnect(_ volume: Volume) throws {
        try validate(volume, requireWritable: false)
        if volume.ntfsSerial != nil {
            // FSKit can briefly report EBUSY while completing close/flush callbacks.
            // Retry ordinary unmount only; never force or terminate another app.
            for attempt in 0..<6 {
                do {
                    _ = try SystemCommand.run("/sbin/umount", [volume.mount.path])
                    break
                } catch {
                    guard attempt < 5, error.localizedDescription.contains("Resource busy") else { throw error }
                    Thread.sleep(forTimeInterval: 0.4)
                }
            }
            try? save(records().filter { $0.id != volume.id })
            _ = rmdir(volume.mount.path)
        } else {
            _ = try SystemCommand.run("/usr/sbin/diskutil", ["unmount", volume.device])
        }
    }
    public static func eject(_ volume: Volume) throws {
        try disconnect(volume)
        _ = try SystemCommand.run("/usr/sbin/diskutil", ["eject", volume.device])
    }
}

