import Foundation

public enum TransferBatch {
    /// Check the whole selection before creating anything. A completed item is
    /// retained if a later item fails; originals are never removed by copying.
    public static func copy(sources: [URL], to destination: URL,
                            cancellation: Cancellation = Cancellation(),
                            progress: @escaping @Sendable (TransferProgress) -> Void = { _ in }) throws -> [Receipt] {
        guard !sources.isEmpty else { throw TransferFailure("Choose files or folders to transfer.") }
        let roots = sources.map { $0.standardizedFileURL }
        var names = Set<String>()
        var sizes: [Int64] = []
        for source in roots {
            try cancellation.check()
            let entries = try Transfer.scan(source)
            let name = source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(name).inserted else {
                throw TransferFailure("Selected items have the same destination name: \(source.lastPathComponent). Choose them separately or rename one.")
            }
            guard !roots.contains(where: { $0 != source && source.path.hasPrefix($0.path + "/") }) else {
                throw TransferFailure("A selected file is already inside another selected folder. Select the folder alone.")
            }
            let final = destination.appendingPathComponent(source.lastPathComponent)
            // Include dangling links in collisions without following them.
            if (try? FileManager.default.attributesOfItem(atPath: final.path)) != nil {
                throw TransferFailure("An item named \(source.lastPathComponent) already exists at the destination. Nothing was overwritten.")
            }
            sizes.append(entries.reduce(0) { $0 + $1.size })
        }
        let total = sizes.reduce(Int64(0), +)
        let values = try destination.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let available = values.volumeAvailableCapacity, Int64(available) > total + 32 * 1024 * 1024 else {
            throw TransferFailure("The destination needs more free space for the selected items.")
        }
        var receipts: [Receipt] = []
        var completed: Int64 = 0
        for (index, source) in roots.enumerated() {
            try cancellation.check()
            let offset = completed, size = sizes[index]
            do {
                let receipt = try Transfer.copy(source: source, to: destination, cancellation: cancellation) { update in
                    let work: Int64
                    switch update.phase {
                    case "Verified": work = size * 2
                    case "Verifying": work = size + update.bytes
                    default: work = update.bytes
                    }
                    progress(TransferProgress(phase: update.phase, path: update.path.isEmpty ? source.lastPathComponent : update.path,
                                              bytes: offset + work, total: total * 2))
                }
                receipts.append(receipt); completed += size * 2
            } catch {
                throw TransferFailure("\(error.localizedDescription)\n\nAll originals were kept. \(receipts.count) earlier item(s) finished copying and remain on the drive.")
            }
        }
        return receipts
    }
}
