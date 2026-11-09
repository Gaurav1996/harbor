import XCTest
import HarborLegacyNTFS
import Foundation
import Darwin
@testable import HarborCore

final class NativeDriverTests: XCTestCase {
    func testApprovedNativeDriverOnDisposableImage() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let imagePath = environment["HARBOR_NATIVE_TEST_IMAGE"],
              let device = environment["HARBOR_NATIVE_TEST_DEVICE"] else {
            throw XCTSkip("Native-driver tests require the explicitly prepared disposable image.")
        }
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let trial = project.appendingPathComponent(".integration/native-driver-trial").resolvingSymlinksInPath()
        let image = URL(fileURLWithPath: imagePath)
        guard image.resolvingSymlinksInPath().deletingLastPathComponent() == trial,
              image.lastPathComponent.hasPrefix("disposable-"),
              device.range(of: "^disk[0-9]+(?:s[0-9]+)*$", options: .regularExpression) != nil else {
            throw TransferFailure("Refusing an image or device outside the isolated driver trial.")
        }
        var imageStat = stat()
        guard lstat(image.path, &imageStat) == 0, imageStat.st_mode & S_IFMT == S_IFREG,
              imageStat.st_uid == getuid(), imageStat.st_nlink == 1 else {
            throw TransferFailure("The fixture must be a new regular image owned by the current user.")
        }
        let attachedData = try SystemCommand.run("/usr/bin/hdiutil", ["info", "-plist"])
        let attached = try XCTUnwrap(try PropertyListSerialization.propertyList(from: attachedData, format: nil) as? [String: Any])
        let images = try XCTUnwrap(attached["images"] as? [[String: Any]])
        let fixture = try XCTUnwrap(images.first { $0["image-path"] as? String == imagePath })
        let entities = try XCTUnwrap(fixture["system-entities"] as? [[String: Any]])
        guard entities.contains(where: { $0["dev-entry"] as? String == "/dev/" + device }) else {
            throw TransferFailure("The test device does not belong to the disposable image.")
        }
        let info = try SystemCommand.info(device)
        let originalAttach = try Data(contentsOf: trial.appendingPathComponent("attach.plist"))
        let originalAttachInfo = try XCTUnwrap(try PropertyListSerialization.propertyList(from: originalAttach, format: nil) as? [String: Any])
        let probed = try XCTUnwrap(originalAttachInfo["system-entities"] as? [[String: Any]])
        guard probed.contains(where: { $0["dev-entry"] as? String == "/dev/" + device && $0["volume-kind"] as? String == "ttntfs" }) else {
            throw TransferFailure("Disk Arbitration did not select the approved native module for this fixture.")
        }
        let destination = URL(fileURLWithPath: try XCTUnwrap(info["MountPoint"] as? String))
        var fs = statfs()
        guard statfs(destination.path, &fs) == 0 else { throw TransferFailure("Test volume is unavailable.") }
        let kind = withUnsafePointer(to: &fs.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
        // On this OS the approved TT module advertises `ttntfs` at probe time,
        // while the kernel exposes the mounted filesystem's canonical `ntfs` name.
        guard kind == "ntfs", fs.f_flags & UInt32(MNT_RDONLY) == 0 else {
            throw TransferFailure("The target must actually be the approved writable native driver, not another filesystem.")
        }
        let source = trial.appendingPathComponent("Synthetic source \(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: source.appendingPathComponent("Nested एक"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appendingPathComponent("Empty folder"), withIntermediateDirectories: true)
        try Data(repeating: 0xa7, count: 3_145_745).write(to: source.appendingPathComponent("Nested एक/photo ' sample.bin"))
        try Data("hidden synthetic data".utf8).write(to: source.appendingPathComponent(".hidden"))
        try Data().write(to: source.appendingPathComponent("empty.txt"))
        let receipt = try Transfer.copy(source: source, to: destination)
        XCTAssertEqual(receipt.fileCount, 3)
        try Transfer.validateForRemoval(receipt)
        XCTAssertTrue(fm.fileExists(atPath: source.path), "The integration test never removes its source.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: trial.appendingPathComponent("native-receipt.json"), options: .atomic)
        print("NATIVE_DRIVER_VERIFIED: \(kind), \(receipt.fileCount) files, \(receipt.bytes) bytes")
    }
}
