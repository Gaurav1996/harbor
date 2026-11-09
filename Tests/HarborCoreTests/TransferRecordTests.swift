import XCTest
import Foundation
import Darwin
@testable import HarborCore

final class TransferRecordTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var receipt: Receipt!
    private var store: TransferRecordStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborRecords-\(UUID().uuidString)")
        source = root.appendingPathComponent("Source")
        let destination = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("synthetic content".utf8).write(to: source.appendingPathComponent("file.txt"))
        receipt = try Transfer.copy(source: source, to: destination)
        store = TransferRecordStore(directory: root.appendingPathComponent("Reports"))
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testCommittedRecordRoundTripsWithPrivatePermissions() throws {
        let original = StoredTransfer(receipt: receipt)
        try store.save(original)
        let loaded = try store.load(original.id)
        XCTAssertEqual(loaded.receipt, receipt)
        XCTAssertEqual(loaded.originalState, .kept)
        XCTAssertNil(loaded.trashURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: recordURL(original.id).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count, 1)
    }

    func testRecordsActualTrashOutcomeWithoutPromisingItStillExists() throws {
        var record = StoredTransfer(receipt: receipt)
        let historicalURL = root.appendingPathComponent("not-an-existing-trash-item")
        record.recordTrashResult(historicalURL)
        try store.save(record)
        let loaded = try store.load(record.id)
        XCTAssertEqual(loaded.originalState, .trashed)
        XCTAssertEqual(loaded.trashURL, historicalURL)
        XCTAssertNotNil(loaded.trashedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRefusesSymlinkedRecord() throws {
        let record = StoredTransfer(receipt: receipt)
        try store.save(record)
        let outside = root.appendingPathComponent("outside.json")
        try FileManager.default.moveItem(at: recordURL(record.id), to: outside)
        try FileManager.default.createSymbolicLink(at: recordURL(record.id), withDestinationURL: outside)
        XCTAssertThrowsError(try store.load(record.id))
    }

    func testRefusesWritableByOthersRecordDirectory() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        XCTAssertEqual(chmod(store.directory.path, 0o777), 0)
        XCTAssertThrowsError(try store.save(StoredTransfer(receipt: receipt)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRejectsUnsupportedSchemaAndWrongRecordIdentity() throws {
        let record = StoredTransfer(receipt: receipt)
        try store.save(record)
        let another = UUID()
        try FileManager.default.copyItem(at: recordURL(record.id), to: recordURL(another))
        XCTAssertThrowsError(try store.load(another))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL(record.id))) as? [String: Any])
        object["schema"] = 999
        try JSONSerialization.data(withJSONObject: object).write(to: recordURL(record.id))
        XCTAssertThrowsError(try store.load(record.id))
    }

    func testRejectsPathTraversalInSavedManifest() throws {
        let record = StoredTransfer(receipt: receipt)
        try store.save(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL(record.id))) as? [String: Any])
        var storedReceipt = try XCTUnwrap(object["receipt"] as? [String: Any])
        var entries = try XCTUnwrap(storedReceipt["entries"] as? [[String: Any]])
        entries[1]["path"] = "../outside"
        storedReceipt["entries"] = entries; object["receipt"] = storedReceipt
        try JSONSerialization.data(withJSONObject: object).write(to: recordURL(record.id))
        XCTAssertThrowsError(try store.load(record.id))
    }

    func testReportFailurePreservesBothCopies() throws {
        let unavailable = root.appendingPathComponent("not-a-directory")
        try Data().write(to: unavailable)
        let failedStore = TransferRecordStore(directory: unavailable)
        XCTAssertThrowsError(try failedStore.save(StoredTransfer(receipt: receipt)))
        XCTAssertEqual(try Transfer.digest(source.appendingPathComponent("file.txt")), receipt.hashes["file.txt"])
        XCTAssertEqual(try Transfer.digest(receipt.destination.appendingPathComponent("file.txt")), receipt.hashes["file.txt"])
    }

    private func recordURL(_ id: UUID) -> URL { store.directory.appendingPathComponent(id.uuidString + ".json") }
}
