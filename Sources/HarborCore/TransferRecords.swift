import Foundation
import Darwin

/// A durable result, distinct from progress and from permission to remove a source.
public struct StoredTransfer: Codable, Identifiable, Sendable {
    public enum OriginalState: String, Codable, Sendable { case kept, trashed }
    public let schema: Int
    public let id: UUID
    public let receipt: Receipt
    public private(set) var originalState: OriginalState
    public private(set) var trashedAt: Date?
    /// Historical result returned by macOS; it does not prove future recoverability.
    public private(set) var trashURL: URL?

    public init(receipt: Receipt, id: UUID = UUID()) {
        schema = 1; self.id = id; self.receipt = receipt
        originalState = .kept; trashedAt = nil; trashURL = nil
    }

    public mutating func recordTrashResult(_ url: URL?, at date: Date = Date()) {
        originalState = .trashed; trashURL = url; trashedAt = date
    }
}

/// Local-only, private records. Saving must succeed before the UI offers source removal.
public struct TransferRecordStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var standard: TransferRecordStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TransferRecordStore(directory: base.appendingPathComponent("Harbor/Reports", isDirectory: true))
    }

    private func openDirectory() throws -> Int32 {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TransferFailure("Cannot open the private transfer records directory.") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else {
            close(fd)
            throw TransferFailure("The transfer records directory must be owned by you and not writable by others.")
        }
        return fd
    }

    private func validate(_ record: StoredTransfer) throws {
        guard record.schema == 1, record.receipt.source.isFileURL, record.receipt.destination.isFileURL,
              record.originalState != .trashed || record.trashedAt != nil else {
            throw TransferFailure("This transfer record is incomplete or uses an unsupported format.")
        }
        var paths = Set<String>()
        let entries = record.receipt.entries
        guard let root = entries.first, root.path == "", root.directory || entries.count == 1 else {
            throw TransferFailure("The transfer record has no valid root item.")
        }
        for entry in entries {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard paths.insert(entry.path).inserted, !entry.path.utf8.contains(0),
                  entry.path.isEmpty || parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  entry.size >= 0 else { throw TransferFailure("The transfer record contains an invalid relative path.") }
            if !entry.directory {
                guard let hash = record.receipt.hashes[entry.path], hash.count == 64,
                      hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                    throw TransferFailure("The transfer record contains an invalid file hash.")
                }
            }
        }
        guard Set(record.receipt.hashes.keys) == Set(entries.filter { !$0.directory }.map(\.path)) else {
            throw TransferFailure("The transfer record's file list does not match its hashes.")
        }
    }

    public func save(_ record: StoredTransfer) throws {
        try validate(record)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= 64 * 1024 * 1024 else { throw TransferFailure("The transfer report exceeds the supported size.") }
        let directoryFD = try openDirectory(); defer { close(directoryFD) }
        let temporary = ".\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw TransferFailure("Cannot create the private transfer report.") }
        defer { unlinkat(directoryFD, temporary, 0) }
        let writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? writer.close() }
        try writer.write(contentsOf: data)
        try writer.synchronize()
        try writer.close()
        let final = record.id.uuidString + ".json"
        guard renameat(directoryFD, temporary, directoryFD, final) == 0 else {
            throw TransferFailure("Cannot commit the transfer report. Keep the original folder.")
        }
        guard fsync(directoryFD) == 0 else {
            throw TransferFailure("The transfer report could not be synchronized. Keep the original folder.")
        }
    }

    public func load(_ id: UUID) throws -> StoredTransfer {
        let directoryFD = try openDirectory(); defer { close(directoryFD) }
        let fd = openat(directoryFD, id.uuidString + ".json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TransferFailure("The saved transfer report is not available.") }
        let reader = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? reader.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_size >= 0, info.st_size <= 64 * 1024 * 1024 else {
            throw TransferFailure("The saved transfer report is not a supported private file.")
        }
        let data = try reader.read(upToCount: 64 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024 * 1024 else { throw TransferFailure("The saved transfer report is too large.") }
        let record = try JSONDecoder().decode(StoredTransfer.self, from: data)
        guard record.id == id else { throw TransferFailure("The saved transfer report identity changed.") }
        try validate(record)
        return record
    }
}
