import XCTest
@testable import HarborLegacyNTFS
import Darwin
@testable import HarborCore

final class TransferTests: XCTestCase {
    var root: URL!
    var source: URL!
    var target: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborTests-\(UUID().uuidString)")
        source = root.appendingPathComponent("Photos ' नवंबर")
        target = root.appendingPathComponent("External")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func write(_ name: String, _ data: Data = Data("photo bytes".utf8)) throws {
        let url = source.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func testNestedHiddenEmptyUnicodeAndContentVerification() throws {
        try write("Wedding/IMG 001.jpg", Data(repeating: 0x9c, count: 2_500_001))
        try write(".hidden")
        try write("शानू.jpg")
        try write("empty", Data())
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Empty folder"), withIntermediateDirectories: false)
        let receipt = try Transfer.copy(source: source, to: target)
        XCTAssertEqual(receipt.fileCount, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.destination.appendingPathComponent("Empty folder").path))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("Wedding/IMG 001.jpg")), try Data(contentsOf: receipt.destination.appendingPathComponent("Wedding/IMG 001.jpg")))
        try Transfer.validateForRemoval(receipt)
        let report = try JSONEncoder().encode(receipt)
        XCTAssertEqual(try JSONDecoder().decode(Receipt.self, from: report).hashes, receipt.hashes)
    }
    func testDestinationCollisionDoesNotOverwrite() throws {
        try write("photo.jpg")
        let first = try Transfer.copy(source: source, to: target)
        let before = try Data(contentsOf: first.destination.appendingPathComponent("photo.jpg"))
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target))
        XCTAssertEqual(before, try Data(contentsOf: first.destination.appendingPathComponent("photo.jpg")))
    }
    func testCorruptedDestinationBlocksRemoval() throws {
        try write("photo.jpg")
        let receipt = try Transfer.copy(source: source, to: target)
        try Data("corrupted".utf8).write(to: receipt.destination.appendingPathComponent("photo.jpg"))
        XCTAssertThrowsError(try Transfer.validateForRemoval(receipt))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testFinderMetadataAddedOnlyToDestinationDoesNotBlockRemoval() throws {
        try write("nested/photo.jpg")
        let receipt = try Transfer.copy(source: source, to: target)
        try Data("finder settings".utf8).write(to: receipt.destination.appendingPathComponent(".DS_Store"))
        try Data("finder settings".utf8).write(to: receipt.destination.appendingPathComponent("nested/.DS_Store"))
        try Transfer.validateForRemoval(receipt)
        try Data("unexpected".utf8).write(to: receipt.destination.appendingPathComponent("extra.jpg"))
        XCTAssertThrowsError(try Transfer.validateForRemoval(receipt))
    }
    func testSourceFinderMetadataStillRequiresMatchingContent() throws {
        try write(".DS_Store")
        let receipt = try Transfer.copy(source: source, to: target)
        try Data("changed finder settings".utf8).write(to: receipt.destination.appendingPathComponent(".DS_Store"))
        XCTAssertThrowsError(try Transfer.validateForRemoval(receipt))
    }
    func testInternalDestinationRejectedByConsumerCatalog() throws {
        XCTAssertThrowsError(try DriveCatalog.snapshot(containing: target))
    }
    func testSourceChangedAfterCopyBlocksRemoval() throws {
        try write("photo.jpg")
        let receipt = try Transfer.copy(source: source, to: target)
        try write("new photo.jpg")
        XCTAssertThrowsError(try Transfer.validateForRemoval(receipt))
    }
    func testSourceMutatingDuringCopyDoesNotFinalize() throws {
        try write("photo.jpg", Data(repeating: 42, count: 2_500_000))
        let token = Cancellation()
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target, cancellation: token) { [source = source!] update in
            if update.phase == "Copying" {
                try? Data("new".utf8).write(to: source.appendingPathComponent("new file"))
            }
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(source.lastPathComponent).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testCancellationLeavesOriginalAndNoCompletedFolder() throws {
        try write("photo.jpg", Data(repeating: 42, count: 2_500_000))
        let token = Cancellation()
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target, cancellation: token) { _ in token.cancel() })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("photo.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(source.lastPathComponent).path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasSuffix(".partial") })
    }
    func testSymlinkRejectedAndBrokenDestinationNotOverwritten() throws {
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: target)
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target))
        try FileManager.default.removeItem(at: source.appendingPathComponent("link"))
        let final = target.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.createSymbolicLink(at: final, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: final.path), root.appendingPathComponent("missing").path)
    }
    func testNestedDestinationRejected() throws {
        let nested = source.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        XCTAssertThrowsError(try Transfer.copy(source: source, to: nested))
    }
    func testEmptyFolder() throws {
        let receipt = try Transfer.copy(source: source, to: target)
        XCTAssertEqual(receipt.fileCount, 0)
        try Transfer.validateForRemoval(receipt)
    }
    func testNTFSArgumentsAreScopedAndNeverForceRecovery() throws {
        let volume = Volume(id: "disk9s1", name: "A ' $(touch /tmp/no) drive", mount: target, device: "disk9s1", uuid: "12345678-1234-1234-1234-123456789ABC", filesystem: "ntfs", readOnly: true, free: 1000)
        let args = try NTFS.mountArguments(volume: volume, mount: target)
        XCTAssertEqual(args[0], "/dev/disk9s1")
        XCTAssertEqual(args[1], target.path)
        XCTAssertTrue(args[3].contains("backend=fskit,norecover,windows_names"))
        XCTAssertFalse(args.joined().contains("touch /tmp/no"))
        XCTAssertFalse(args.joined().contains("remove_hiberfile"))
        XCTAssertFalse(args.joined().contains("backend=kernel"))
        let malicious = Volume(id: "bad", name: "bad", mount: target, device: "disk9s1;whoami", uuid: volume.uuid, filesystem: "ntfs", readOnly: true, free: 1000)
        XCTAssertThrowsError(try NTFS.mountArguments(volume: malicious, mount: target))
    }
    func testSHA256KnownVector() throws {
        try write("abc", Data("abc".utf8))
        XCTAssertEqual(try Transfer.digest(source.appendingPathComponent("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testMutationDuringVerificationBlocksFinalization() throws {
        try write("photo.jpg")
        let folder = source!
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target) { update in
            if update.phase == "Verifying" {
                try? Data("new file".utf8).write(to: folder.appendingPathComponent("added.jpg"))
            }
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(source.lastPathComponent).path))
    }
    func testResourceForkRejected() throws {
        try write("old photo")
        let resource = source.appendingPathComponent("old photo/..namedfork/rsrc")
        try Data("resource data".utf8).write(to: resource)
        XCTAssertThrowsError(try Transfer.copy(source: source, to: target))
    }
    func testReplacementDestinationBlocksRemovalEvenWithMatchingContent() throws {
        try write("photo.jpg")
        let receipt = try Transfer.copy(source: source, to: target)
        try FileManager.default.moveItem(at: receipt.destination, to: target.appendingPathComponent("old copy"))
        try FileManager.default.copyItem(at: source, to: receipt.destination)
        XCTAssertThrowsError(try Transfer.validateForRemoval(receipt))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testNTFSImageIntegration() throws {
        let env = ProcessInfo.processInfo.environment
        guard let image = env["HARBOR_TEST_IMAGE"], let device = env["HARBOR_TEST_DEVICE"] else {
            throw XCTSkip("Run scripts/test-ntfs-image.py for the disposable NTFS integration test.")
        }
        // Prove the requested device belongs to our generated image, never a physical HDD.
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertTrue(image.hasPrefix(project.appendingPathComponent(".integration").path + "/"))
        guard image.hasPrefix(project.appendingPathComponent(".integration").path + "/") else { return }
        let hdiInfo = try SystemCommand.run("/usr/bin/hdiutil", ["info", "-plist"])
        let data = try XCTUnwrap(try PropertyListSerialization.propertyList(from: hdiInfo, format: nil) as? [String: Any])
        let images = try XCTUnwrap(data["images"] as? [[String: Any]])
        let attached = try XCTUnwrap(images.first { $0["image-path"] as? String == image })
        let entities = try XCTUnwrap(attached["system-entities"] as? [[String: Any]])
        XCTAssertTrue(entities.contains { $0["dev-entry"] as? String == device })
        guard entities.contains(where: { $0["dev-entry"] as? String == device }) else { return }
        let initial = try SystemCommand.info(device)
        let mount = try XCTUnwrap(initial["MountPoint"] as? String)
        let volume = Volume(id: device, name: "HarborDisposable", mount: URL(fileURLWithPath: mount),
                            device: try XCTUnwrap(initial["DeviceIdentifier"] as? String),
                            uuid: initial["VolumeUUID"] as? String ?? "", filesystem: "ntfs", readOnly: true, free: 0)
        let connected = try NTFS.enable(volume, forceAuthorization: env["HARBOR_TEST_FORCE_AUTH"] == "1")
        defer { try? NTFS.disconnect(connected) }
        let destination = connected.mount
        try NTFS.validate(connected)
        XCTAssertTrue(NTFS.managedVolumes().contains { $0.device == volume.device })
        var sourceStat = stat()
        var destinationStat = stat()
        guard lstat(source.path, &sourceStat) == 0, lstat(destination.path, &destinationStat) == 0,
              sourceStat.st_dev != destinationStat.st_dev else {
            throw TransferFailure("The NTFS test mount did not appear. Refusing to test against an ordinary local folder.")
        }
        try write("nested/photo ' एक.jpg", Data(repeating: 0xa7, count: 8_000_001))
        try write(".hidden")
        try write("empty.jpg", Data())
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Empty folder"), withIntermediateDirectories: false)
        let receipt = try Transfer.copy(source: source, to: destination)
        XCTAssertEqual(receipt.fileCount, 3)
        try Transfer.validateForRemoval(receipt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        // Flush and unmount the image, reconnect, and independently read the hashes again.
        try NTFS.disconnect(connected)
        _ = try SystemCommand.run("/usr/sbin/diskutil", ["mount", volume.device])
        let remounted = try SystemCommand.info(device)
        let remount = URL(fileURLWithPath: try XCTUnwrap(remounted["MountPoint"] as? String))
        for (path, hash) in receipt.hashes {
            XCTAssertEqual(try Transfer.digest(remount.appendingPathComponent(source.lastPathComponent).appendingPathComponent(path)), hash)
        }
    }
}
