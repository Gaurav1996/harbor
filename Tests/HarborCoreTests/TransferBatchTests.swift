import XCTest
import Foundation
@testable import HarborCore

final class TransferBatchTests: XCTestCase {
    private var root: URL!
    private var target: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborItems-\(UUID().uuidString)")
        target = root.appendingPathComponent("External")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func file(_ name: String, _ data: Data = Data("synthetic file".utf8)) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }
    func testStandaloneFileCopiesDirectlyAndRecordRoundTrips() throws {
        let source = try file("photo ' एक.jpg", Data(repeating: 0xa7, count: 2_100_013))
        let receipt = try Transfer.copy(source: source, to: target)
        XCTAssertEqual(receipt.destination, target.appendingPathComponent(source.lastPathComponent))
        XCTAssertEqual(receipt.fileCount, 1)
        XCTAssertEqual(receipt.entries.count, 1)
        XCTAssertFalse(receipt.entries[0].directory)
        XCTAssertEqual(receipt.hashes[""], try Transfer.digest(source))
        try Transfer.validateForRemoval(receipt)
        let store = TransferRecordStore(directory: root.appendingPathComponent("Reports"))
        let saved = StoredTransfer(receipt: receipt)
        try store.save(saved)
        XCTAssertEqual(try store.load(saved.id).receipt, receipt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target))
        try Data("corrupt".utf8).write(to: receipt.destination)
        XCTAssertThrowsError(try Transfer.validateForRemoval(receipt))
    }
    func testEmptyStandaloneFileAndMixedSelection() throws {
        let empty = try file("empty.bin", Data())
        let regular = try file("photo.jpg")
        let nested = try file("Folder/nested/one.txt")
        let folder = root.appendingPathComponent("Folder")
        let receipts = try TransferBatch.copy(sources: [empty, regular, folder], to: target)
        XCTAssertEqual(receipts.count, 3)
        XCTAssertEqual(receipts.reduce(0) { $0 + $1.fileCount }, 3)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("Folder/nested/one.txt")), try Data(contentsOf: nested))
        for receipt in receipts { try Transfer.validateForRemoval(receipt) }
    }
    func testBatchCollisionIsDetectedBeforeAnyItemCopies() throws {
        let first = try file("first.txt"), second = try file("second.txt")
        try Data("keep this".utf8).write(to: target.appendingPathComponent("second.txt"))
        XCTAssertThrowsError(try TransferBatch.copy(sources: [first, second], to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("first.txt").path))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("second.txt"), encoding: .utf8), "keep this")
    }
    func testSameNamesAndOverlappingSelectionsRejectedBeforeCopy() throws {
        let one = try file("A/one.txt"), another = try file("B/one.txt")
        XCTAssertThrowsError(try TransferBatch.copy(sources: [one, another], to: target))
        XCTAssertThrowsError(try TransferBatch.copy(sources: [root.appendingPathComponent("A"), one], to: target))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }
    func testCancellingStandaloneFileRetainsOriginalAndNoFinalItem() throws {
        let source = try file("large.bin", Data(repeating: 42, count: 2_100_000))
        let cancellation = Cancellation()
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target, cancellation: cancellation) { _ in cancellation.cancel() })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("large.bin").path))
    }
    func testLaterFailureRetainsEarlierCompletedCopyAndEveryOriginal() throws {
        let first = try file("first.txt"), second = try file("second.bin", Data(repeating: 3, count: 2_100_000))
        let cancellation = Cancellation()
        XCTAssertThrowsError(try TransferBatch.copy(sources: [first, second], to: target, cancellation: cancellation) { update in
            if update.path == "second.bin" && update.phase == "Copying" { cancellation.cancel() }
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(try Transfer.digest(first), try Transfer.digest(target.appendingPathComponent("first.txt")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("second.bin").path))
    }
}
