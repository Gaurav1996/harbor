import Foundation
import DiskArbitration
import Darwin

public struct ExternalDrive: Identifiable, Sendable, Equatable {
    public let root: URL
    public let name: String
    public let filesystem: String
    public let uuid: String
    public let device: String?
    public let freeBytes: Int64
    public let readOnly: Bool
    public let isDiskImage: Bool
    public let fsid0: Int32
    public let fsid1: Int32
    public var id: String { "\(root.path):\(fsid0):\(fsid1)" }
}

/// Metadata and mount identity only. No raw-device opens, shell execution or mounting.
public enum DriveCatalog {
    public static func snapshot(containing url: URL) throws -> ExternalDrive {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var fs = statfs()
        guard statfs(resolved.path, &fs) == 0 else {
            throw TransferFailure("This drive is no longer available. Reconnect it and choose the destination again.")
        }
        let rootPath = withUnsafePointer(to: &fs.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
        }
        guard rootPath.hasPrefix("/Volumes/"), fs.f_flags & UInt32(MNT_LOCAL) != 0 else {
            throw TransferFailure("Choose a folder on a mounted external drive or disk image.")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let filesystem = withUnsafePointer(to: &fs.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
        let values = try? root.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey, .volumeIsInternalKey])
        var description: [String: Any] = [:]
        var device: String?
        if let session = DASessionCreate(kCFAllocatorDefault),
           let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, root as CFURL) {
            description = DADiskCopyDescription(disk) as? [String: Any] ?? [:]
            if let name = DADiskGetBSDName(disk) { device = String(cString: name) }
        }
        guard values?.volumeIsInternal != true,
              description[kDADiskDescriptionDeviceInternalKey as String] as? Bool != true else {
            throw TransferFailure("Harbor's destination must be an external drive.")
        }
        let model = description[kDADiskDescriptionDeviceModelKey as String] as? String ?? ""
        let proto = description[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
        let isImage = model.localizedCaseInsensitiveContains("disk image") || proto == "Disk Image"
        var uuid = values?.volumeUUIDString ?? ""
        if uuid.isEmpty, let rawUUID = description[kDADiskDescriptionVolumeUUIDKey as String] {
            let value = rawUUID as CFTypeRef
            if CFGetTypeID(value) == CFUUIDGetTypeID() {
                uuid = CFUUIDCreateString(kCFAllocatorDefault, (rawUUID as! CFUUID)) as String
            }
        }
        let available = UInt64(fs.f_bavail).multipliedReportingOverflow(by: UInt64(fs.f_bsize))
        let bytes = available.overflow ? Int64.max : Int64(min(available.partialValue, UInt64(Int64.max)))
        return ExternalDrive(root: root,
                             name: values?.volumeName ?? root.lastPathComponent,
                             filesystem: filesystem, uuid: uuid,
                             device: device, freeBytes: bytes,
                             readOnly: fs.f_flags & UInt32(MNT_RDONLY) != 0,
                             isDiskImage: isImage, fsid0: fs.f_fsid.val.0, fsid1: fs.f_fsid.val.1)
    }

    public static func externalDrives() -> [ExternalDrive] {
        let roots = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
        return roots.compactMap { try? snapshot(containing: $0) }
            .filter { !$0.isDiskImage }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func validate(_ expected: ExternalDrive, folder: URL, requireWritable: Bool = true) throws {
        let current = try snapshot(containing: folder)
        guard current.root == expected.root, current.fsid0 == expected.fsid0,
              current.fsid1 == expected.fsid1, current.uuid == expected.uuid,
              !requireWritable || !current.readOnly else {
            throw TransferFailure("The destination changed or became read-only. Your original folder has been kept.")
        }
    }
}
