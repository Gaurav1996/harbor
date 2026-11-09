import Foundation
import AppKit
import HarborCore

private final class ProgressLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    func allows(_ phase: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) > 0.12 || phase == "Verified" else { return false }
        last = now; return true
    }
}

private struct TrashOutcome: Sendable {
    var moved: [URL] = []
    var warning: String?
}

@MainActor final class TransferModel: ObservableObject {
    @Published var sources: [URL] = []
    @Published var destination: URL?
    @Published var drive: ExternalDrive?
    @Published var busy = false
    @Published var canCancel = false
    @Published var showSupport = false
    @Published var status = "Choose files or folders and a destination."
    @Published var detail = "Your originals stay in place until you choose otherwise."
    @Published var progress: Double = 0
    @Published var receipts: [Receipt] = []
    @Published var savedRecordIDs: [UUID] = []
    @Published var originalTrashed = false
    @Published var problem: String?
    var cancellation = Cancellation()
    var quitAfterStopping = false
    private var activeJob: UUID?
    private let access = FolderAccess()
    private var drives: [ExternalDrive] = []
    private var approvedVolumeUUID: String?

    var receipt: Receipt? { receipts.first }
    var sourceName: String { sources.count == 1 ? sources[0].lastPathComponent : sources.isEmpty ? "Choose files or folders" : "\(sources.count) items selected" }
    var sourceDetail: String { sources.isEmpty ? "Or drop files and folders here" : sources.count == 1 ? "Original kept unless you choose to move it" : sources.map(\.lastPathComponent).joined(separator: ", ") }
    var canCopy: Bool { !busy && !sources.isEmpty && destination != nil && drive?.readOnly == false }
    var canTrash: Bool {
        !busy && !sources.isEmpty && receipts.count == savedRecordIDs.count && !receipts.isEmpty
            && sources.allSatisfy { source in receipts.contains { $0.source == source } }
            && receipts.allSatisfy { $0.destination.deletingLastPathComponent() == destination }
            && drive != nil
    }
    var destinationName: String {
        guard let destination else { return drives.isEmpty ? "Connect your external drive" : "Choose where to save" }
        return destination == drive?.root ? (drive?.name ?? destination.lastPathComponent) : destination.lastPathComponent
    }
    var destinationDetail: String {
        guard let drive else { return destination == nil ? "You choose the destination; Harbor checks the drive" : "Reconnect this drive or choose another destination" }
        return "\(drive.name) · \(Self.size(drive.freeBytes)) available · \(drive.readOnly ? "Read-only" : "Ready to copy")"
    }

    init() {
        approvedVolumeUUID = UserDefaults.standard.string(forKey: "approvedDestinationVolume")
        do { sources = try access.restoreSources() }
        catch { status = "Choose your files again"; detail = "The previous selection is no longer available." }
        destination = try? access.restore(.destination)
        refresh()
        let defaults = UserDefaults.standard
        let identifiers = defaults.stringArray(forKey: "lastVerifiedTransfers")
            ?? defaults.string(forKey: "lastVerifiedTransfer").map { [$0] } ?? []
        let saved = identifiers.compactMap(UUID.init(uuidString:)).compactMap { try? TransferRecordStore.standard.load($0) }
        if !saved.isEmpty, saved.count == identifiers.count,
           saved.allSatisfy({ $0.receipt.destination.deletingLastPathComponent() == destination }),
           saved.filter({ $0.originalState == .kept }).map({ $0.receipt.source }) == sources {
            receipts = saved.map(\.receipt); savedRecordIDs = saved.map(\.id)
            originalTrashed = saved.allSatisfy { $0.originalState == .trashed }
            progress = 1; status = "Last transfer verified"
            detail = "\(Self.fileCount(receipts.reduce(0) { $0 + $1.fileCount })) · \(Self.size(receipts.reduce(0) { $0 + $1.bytes })) · \(originalTrashed ? "Originals moved to Trash at completion" : "Originals kept")"
        }
        if defaults.bool(forKey: "transferWasRunning") {
            receipts = []; savedRecordIDs = []; progress = 0; status = "The previous transfer was interrupted"
            detail = "Your originals were kept. Completed items and partial copies remain on the destination."
        }
    }

    func chooseSource() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Choose items"; panel.message = "Choose files, folders, or both. Harbor keeps your originals by default."
        if panel.runModal() == .OK { useSources(panel.urls) }
    }
    private func useSources(_ urls: [URL]) {
        defer { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            guard !urls.isEmpty else { return }
            // Inspect only the selected roots here; the cancellable copy checks their trees.
            for url in urls {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                    throw TransferFailure("Choose regular files or folders. Symbolic links and special files are not supported.")
                }
            }
            sources = try access.rememberSources(urls); resetResult()
        } catch { problem = error.localizedDescription }
    }
    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !busy, !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let data: Data? = await withCheckedContinuation { continuation in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in continuation.resume(returning: data) }
                }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    problem = "One of the dropped items could not be opened. Use Choose files & folders instead."; return
                }
                urls.append(url)
            }
            guard !busy else { return }
            useSources(urls)
        }
        return true
    }
    func chooseDestination() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Use this destination"
        panel.message = "Choose a destination on your external drive. Selected files and folders keep their names; existing items are never replaced."
        panel.directoryURL = drive?.root ?? drives.first?.root ?? URL(fileURLWithPath: "/Volumes")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let chosen = try DriveCatalog.snapshot(containing: url)
            let granted = try access.remember(url, for: .destination)
            approvedVolumeUUID = chosen.uuid
            UserDefaults.standard.set(chosen.uuid, forKey: "approvedDestinationVolume")
            destination = granted; drive = chosen; resetResult()
        } catch { problem = error.localizedDescription }
    }
    func refresh() {
        guard !busy else { return }
        drives = DriveCatalog.externalDrives()
        if destination == nil { destination = try? access.restore(.destination) }
        guard let destination else { drive = nil; return }
        do {
            let current = try FolderAccess.withAccess([destination]) { try DriveCatalog.snapshot(containing: destination) }
            guard let approvedVolumeUUID, !approvedVolumeUUID.isEmpty, current.uuid == approvedVolumeUUID else {
                drive = nil; detail = "Choose this destination again so Harbor can confirm the drive."; return
            }
            drive = current
        } catch { drive = nil }
    }
    func driveDisconnected() { if busy { cancellation.cancel() } else { refresh() } }
    private func resetResult() {
        receipts = []; savedRecordIDs = []; originalTrashed = false; progress = 0; problem = nil
        status = "Ready when you are"; detail = "Copy and verify every file. Your originals stay in place."
    }
    func copy() {
        guard canCopy, let destination, let drive else { return }
        let sources = sources
        resetResult(); busy = true; canCancel = true; status = "Checking selection and drive…"
        cancellation = Cancellation(); let cancellation = cancellation
        let job = UUID(); activeJob = job
        UserDefaults.standard.set(true, forKey: "transferWasRunning")
        UserDefaults.standard.removeObject(forKey: "lastVerifiedTransfer")
        UserDefaults.standard.removeObject(forKey: "lastVerifiedTransfers")
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Copying and verifying the selected items")
        Task {
            defer { ProcessInfo.processInfo.endActivity(activity); finishOperation() }
            do {
                let result = try await Task.detached {
                    try FolderAccess.withAccess(sources + [destination]) {
                        try DriveCatalog.validate(drive, folder: destination)
                        let limiter = ProgressLimiter()
                        return try TransferBatch.copy(sources: sources, to: destination, cancellation: cancellation) { update in
                            guard limiter.allows(update.phase) else { return }
                            Task { @MainActor in
                                guard self.activeJob == job else { return }
                                self.status = update.phase; self.detail = update.path
                                self.progress = update.total == 0 ? 0 : min(1, Double(update.bytes) / Double(update.total))
                            }
                        }
                    }
                }.value
                activeJob = nil; receipts = result; progress = 1; status = "Every file verified"
                detail = "\(Self.fileCount(result.reduce(0) { $0 + $1.fileCount })) · \(Self.size(result.reduce(0) { $0 + $1.bytes })) · originals kept in place"
                UserDefaults.standard.set(false, forKey: "transferWasRunning")
                do {
                    let records = result.map { StoredTransfer(receipt: $0) }
                    for record in records { try TransferRecordStore.standard.save(record) }
                    savedRecordIDs = records.map(\.id)
                    UserDefaults.standard.set(records.map { $0.id.uuidString }, forKey: "lastVerifiedTransfers")
                } catch { detail += " · Keep the originals: transfer reports could not be saved."; problem = error.localizedDescription }
            } catch {
                activeJob = nil; problem = error.localizedDescription; status = "Transfer stopped"
                UserDefaults.standard.set(false, forKey: "transferWasRunning")
                detail = "All originals were kept. Completed copies and any partial items remain on the destination."
            }
        }
    }
    func trashOriginal() {
        guard canTrash, let destination, let drive else { return }
        let sources = sources, receipts = receipts, ids = savedRecordIDs
        busy = true; canCancel = true; status = "Rechecking originals and copies…"
        detail = "No original moves unless its verification passes."
        cancellation = Cancellation(); let cancellation = cancellation
        Task {
            defer { finishOperation() }
            let outcome = await Task.detached {
                FolderAccess.withAccess(sources + [destination]) {
                    var outcome = TrashOutcome()
                    do {
                        let store = TransferRecordStore.standard
                        var records = try ids.map { try store.load($0) }
                        for (index, record) in records.enumerated() {
                            guard record.receipt == receipts[index] else { throw TransferFailure("A saved report changed. Keep the originals.") }
                            if sources.contains(record.receipt.source) {
                                guard record.originalState == .kept else { throw TransferFailure("An original has already moved. Keep remaining items.") }
                                try DriveCatalog.validate(drive, folder: record.receipt.destination, requireWritable: false)
                                try Transfer.validateForRemoval(record.receipt, cancellation: cancellation)
                            }
                        }
                        for index in records.indices where sources.contains(records[index].receipt.source) {
                            let receipt = records[index].receipt
                            try DriveCatalog.validate(drive, folder: receipt.destination, requireWritable: false)
                            try Transfer.validateForRemoval(receipt, cancellation: cancellation); try cancellation.check()
                            var resultingURL: NSURL?
                            try FileManager.default.trashItem(at: receipt.source, resultingItemURL: &resultingURL)
                            outcome.moved.append(receipt.source)
                            records[index].recordTrashResult(resultingURL as URL?)
                            try store.save(records[index])
                        }
                    } catch { outcome.warning = error.localizedDescription }
                    return outcome
                }
            }.value
            let remaining = sources.filter { !outcome.moved.contains($0) }
            if !outcome.moved.isEmpty {
                access.forget(.source)
                self.sources = []
                if !remaining.isEmpty {
                    do { self.sources = try access.rememberSources(remaining) }
                    catch { problem = "Choose the remaining originals again: \(error.localizedDescription)" }
                }
            }
            originalTrashed = remaining.isEmpty
            if let warning = outcome.warning {
                status = outcome.moved.isEmpty ? "Originals kept" : "Some originals moved"
                detail = "\(outcome.moved.count) moved to Trash; \(remaining.count) kept. Verified copies remain on the drive."
                problem = warning
            } else {
                status = "Move complete"; detail = "Verified copies on your drive. Originals moved to Mac Trash."
            }
        }
    }
    func eject() {
        guard !busy, let drive else { return }
        busy = true; canCancel = false; status = "Ejecting drive…"
        Task {
            defer { finishOperation(); refresh() }
            do {
                try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: drive.root) }.value
                status = "Drive ejected"; detail = "You can unplug it now."
            } catch { problem = "Close files using the drive and try ejecting again. \(error.localizedDescription)" }
        }
    }
    private func finishOperation() {
        activeJob = nil; busy = false; canCancel = false
        if quitAfterStopping { NSApp.reply(toApplicationShouldTerminate: true) }
    }
    func newTransfer() { guard !busy else { return }; resetResult(); chooseSource() }
    func forgetFolders() {
        guard !busy else { return }
        access.forget(); sources = []; destination = nil; drive = nil; approvedVolumeUUID = nil
        UserDefaults.standard.removeObject(forKey: "approvedDestinationVolume")
        resetResult(); status = "Selections forgotten"; detail = "Choose items next time. Local transfer reports are retained."
    }
    func revealCopies() { FolderAccess.withAccess([destination].compactMap { $0 }) { NSWorkspace.shared.activateFileViewerSelecting(receipts.map(\.destination)) } }
    func openLicenses() { if let url = Bundle.main.url(forResource: "NOTICE", withExtension: "md") { NSWorkspace.shared.open(url) } }
    func openGuide() { if let url = Bundle.main.url(forResource: "USER-GUIDE", withExtension: "md") { NSWorkspace.shared.open(url) } }
    static func fileCount(_ value: Int) -> String { "\(value) \(value == 1 ? "file" : "files")" }
    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
