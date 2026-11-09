import Foundation
import CryptoKit
import Darwin

public struct TransferFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct Entry: Codable, Equatable, Sendable {
    public let path: String
    public let directory: Bool
    public let size: Int64
    public let modified: Date
    public let inode: UInt64
    public let device: Int32
}

public struct TransferProgress: Sendable {
    public let phase: String
    public let path: String
    public let bytes: Int64
    public let total: Int64
}

public struct Receipt: Codable, Equatable, Sendable {
    public let source: URL
    public let destination: URL
    public let entries: [Entry]
    public let hashes: [String: String]
    public let destinationDevice: Int32
    public let destinationInode: UInt64
    public let completed: Date
    public var fileCount: Int { hashes.count }
    public var bytes: Int64 { entries.reduce(0) { $0 + ($1.directory ? 0 : $1.size) } }
}

public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw TransferFailure("Cancelled. Your original folder is untouched.") }
    }
}

public enum Transfer {
    private static let fm = FileManager.default
    private static let chunkSize = 1024 * 1024

    private static func attributes(_ url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw posix("Cannot inspect", url) }
        return value
    }

    private static func posix(_ action: String, _ url: URL) -> TransferFailure {
        TransferFailure("\(action) \(url.path): \(String(cString: strerror(errno)))")
    }

    private static func exists(_ url: URL) -> Bool {
        var value = stat()
        return lstat(url.path, &value) == 0
    }

    public static func scan(_ root: URL) throws -> [Entry] {
        let rootAttributes = try attributes(root)
        guard [S_IFDIR, S_IFREG].contains(rootAttributes.st_mode & S_IFMT) else {
            throw TransferFailure("Choose a regular file or folder, not a symbolic link or special file.")
        }
        var entries: [Entry] = []
        var folded = Set<String>()
        func visit(_ url: URL, _ relative: String) throws {
            let info = try attributes(url)
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFDIR || kind == S_IFREG else {
                throw TransferFailure("Unsupported link or special file: \(relative). Nothing has been removed.")
            }
            if kind == S_IFREG {
                let forkSize = getxattr(url.path, "com.apple.ResourceFork", nil, 0, 0, XATTR_NOFOLLOW)
                if forkSize > 0 {
                    throw TransferFailure("This file contains a resource fork: \(relative). Use a Mac backup tool that preserves it.")
                }
                if forkSize < 0 && errno != ENOATTR && errno != ENOTSUP {
                    throw posix("Cannot inspect file metadata", url)
                }
            }
            guard info.st_dev == rootAttributes.st_dev else {
                throw TransferFailure("The folder contains another mounted volume: \(relative).")
            }
            let key = relative.precomposedStringWithCanonicalMapping.lowercased()
            guard folded.insert(key).inserted else {
                throw TransferFailure("Names differ only by case or Unicode spelling: \(relative). Rename them before copying to an external drive.")
            }
            let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
            entries.append(Entry(path: relative, directory: kind == S_IFDIR,
                                 size: kind == S_IFDIR ? 0 : info.st_size, modified: modified,
                                 inode: info.st_ino, device: info.st_dev))
            if kind == S_IFDIR {
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(root, "")
        return entries
    }

    private static func filesystem(_ url: URL) throws -> statfs {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { throw posix("Cannot access drive", url) }
        return info
    }

    private static func itemURL(_ root: URL, _ path: String) -> URL {
        path.isEmpty ? root : root.appendingPathComponent(path)
    }

    private static func assertVolume(_ root: URL, _ expected: statfs) throws {
        let current = try filesystem(root)
        guard current.f_fsid.val.0 == expected.f_fsid.val.0,
              current.f_fsid.val.1 == expected.f_fsid.val.1 else {
            throw TransferFailure("The destination drive disconnected or changed. Your original folder is untouched.")
        }
    }

    public static func digest(_ url: URL, cancellation: Cancellation = Cancellation()) throws -> String {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posix("Cannot read", url) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw TransferFailure("Expected a regular file: \(url.path)")
        }
        var hash = SHA256()
        while true {
            try cancellation.check()
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Does not delete source data. Failed jobs retain a uniquely named partial folder.
    public static func copy(source input: URL, to targetInput: URL,
                            cancellation: Cancellation = Cancellation(),
                            progress: @escaping @Sendable (TransferProgress) -> Void = { _ in }) throws -> Receipt {
        try cancellation.check()
        // Inspect before canonicalizing, so a selected symlink is rejected.
        let initialEntries = try scan(input)
        let source = input.resolvingSymlinksInPath().standardizedFileURL
        let target = targetInput.resolvingSymlinksInPath().standardizedFileURL
        let isDirectory = initialEntries.first?.directory == true
        let final = target.appendingPathComponent(source.lastPathComponent, isDirectory: isDirectory)
        guard target.path != source.path, !target.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(target.path + "/") else {
            throw TransferFailure("Choose a destination outside the source folder and its parents.")
        }
        guard !exists(final) else { throw TransferFailure("An item named \(source.lastPathComponent) already exists at the destination. Nothing was overwritten.") }
        guard try attributes(target).st_mode & S_IFMT == S_IFDIR else { throw TransferFailure("Destination is not a folder.") }
        let volume = try filesystem(target)
        guard volume.f_flags & UInt32(MNT_RDONLY) == 0 else {
            throw TransferFailure("This volume is read-only. NTFS writing must be enabled before copying.")
        }
        let entries = try scan(source)
        guard entries == initialEntries else { throw TransferFailure("The selected item changed while preparing the transfer. Retry with it closed in other apps.") }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        let free = UInt64(volume.f_bavail) * UInt64(volume.f_bsize)
        guard free > UInt64(total) + 32 * 1024 * 1024 else { throw TransferFailure("The destination needs more free space.") }
        let partial = target.appendingPathComponent(".Harbor-\(UUID().uuidString).partial", isDirectory: isDirectory)
        if entries.first?.directory == true {
            try fm.createDirectory(at: partial, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        var hashes: [String: String] = [:]
        var copied: Int64 = 0
        do {
            for entry in entries where !entry.path.isEmpty || !entry.directory {
                try cancellation.check()
                try assertVolume(target, volume)
                let from = itemURL(source, entry.path)
                let to = itemURL(partial, entry.path)
                if entry.directory {
                    try fm.createDirectory(at: to, withIntermediateDirectories: false)
                    continue
                }
                let fd = open(from.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw posix("Cannot read", from) }
                let reader = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? reader.close() }
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                      info.st_ino == entry.inode, info.st_dev == entry.device else {
                    throw TransferFailure("The source changed while copying: \(entry.path)")
                }
                let out = open(to.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard out >= 0 else { throw posix("Cannot create", to) }
                let writer = FileHandle(fileDescriptor: out, closeOnDealloc: true)
                defer { try? writer.close() }
                var hash = SHA256()
                var size: Int64 = 0
                while true {
                    try cancellation.check()
                    try assertVolume(target, volume)
                    let data = try reader.read(upToCount: chunkSize) ?? Data()
                    if data.isEmpty { break }
                    try writer.write(contentsOf: data)
                    hash.update(data: data)
                    size += Int64(data.count)
                    copied += Int64(data.count)
                    progress(TransferProgress(phase: "Copying", path: entry.path, bytes: copied, total: total))
                }
                guard size == entry.size else { throw TransferFailure("The source changed size: \(entry.path)") }
                try writer.synchronize()
                try writer.close()
                hashes[entry.path] = hash.finalize().map { String(format: "%02x", $0) }.joined()
                // Modification dates are preserved. This is a file-content transfer,
                // not a backup of Finder tags, ACLs, resource forks or all xattrs.
                try fm.setAttributes([.modificationDate: entry.modified], ofItemAtPath: to.path)
            }
            guard try scan(source) == entries else { throw TransferFailure("The source folder changed during transfer. Retry with the folder closed in other apps.") }
            var verified: Int64 = 0
            for entry in entries where !entry.directory {
                try cancellation.check()
                try assertVolume(target, volume)
                progress(TransferProgress(phase: "Verifying", path: entry.path, bytes: verified, total: total))
                guard try digest(itemURL(partial, entry.path), cancellation: cancellation) == hashes[entry.path] else {
                    throw TransferFailure("Verification failed: \(entry.path). Your original is untouched.")
                }
                verified += entry.size
            }
            try cancellation.check()
            try assertVolume(target, volume)
            guard try scan(source) == entries else { throw TransferFailure("The source changed during verification. Keep the original and retry.") }
            // Atomic, exclusive rename; never replaces an existing destination.
            guard renamex_np(partial.path, final.path, UInt32(RENAME_EXCL)) == 0 else { throw posix("Cannot finalize folder", final) }
            let finalAttributes = try attributes(final)
            progress(TransferProgress(phase: "Verified", path: final.path, bytes: total, total: total))
            return Receipt(source: source, destination: final, entries: entries, hashes: hashes,
                           destinationDevice: finalAttributes.st_dev, destinationInode: finalAttributes.st_ino, completed: Date())
        } catch {
            throw TransferFailure("\(error.localizedDescription)\n\nPartial copy (kept for inspection): \(partial.path)")
        }
    }

    /// Rechecks both copies immediately before a separately requested move to Trash.
    public static func validateForRemoval(_ receipt: Receipt, cancellation: Cancellation = Cancellation()) throws {
        guard try scan(receipt.source) == receipt.entries else { throw TransferFailure("The original folder changed. Keep it and copy the changes first.") }
        // Finder may add its own view settings after the verified copy. Ignore
        // only new regular .DS_Store files, never changes to a source .DS_Store.
        let sourcePaths = Set(receipt.entries.map(\.path))
        let destinationEntries = try scan(receipt.destination).filter {
            sourcePaths.contains($0.path) || $0.directory || ($0.path as NSString).lastPathComponent != ".DS_Store"
        }
        guard destinationEntries.first?.device == receipt.destinationDevice,
              destinationEntries.first?.inode == receipt.destinationInode,
              destinationEntries.map(\.path) == receipt.entries.map(\.path),
              destinationEntries.map(\.directory) == receipt.entries.map(\.directory) else {
            throw TransferFailure("The destination folder changed. The original must be kept.")
        }
        for entry in receipt.entries where !entry.directory {
            guard try digest(itemURL(receipt.source, entry.path), cancellation: cancellation) == receipt.hashes[entry.path],
                  try digest(itemURL(receipt.destination, entry.path), cancellation: cancellation) == receipt.hashes[entry.path] else {
                throw TransferFailure("A file changed or failed verification: \(entry.path). The original must be kept.")
            }
        }
        guard try scan(receipt.source) == receipt.entries else { throw TransferFailure("The source changed during verification. The original must be kept.") }
        let finalDestination = try attributes(receipt.destination)
        guard finalDestination.st_dev == receipt.destinationDevice,
              finalDestination.st_ino == receipt.destinationInode else {
            throw TransferFailure("The destination drive or folder changed. The original must be kept.")
        }
    }
}
