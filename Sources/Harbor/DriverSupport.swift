import Foundation
import AppKit
import Security
import FSKit
import HarborCore

/// The unchanged, independently signed provider travels inside Harbor. Only
/// extension metadata is registered; its menu-bar host is never launched.
enum DriverSupport {
    static let providerName = "TT NTFS Native"
    static let moduleID = "ch.techtag.ntfs.extension"
    static var bundledURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TT NTFS Native.app", isDirectory: true)
    }
    static func prepareBundledDriver() throws {
        let url = bundledURL
        let extensionURL = url.appendingPathComponent("Contents/Extensions/NTFSExtension.appex")
        guard validSignature(at: url, identifier: "ch.techtag.ntfs"),
              validSignature(at: extensionURL, identifier: moduleID),
              Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.4.1" else {
            throw TransferFailure("Harbor’s included NTFS component is missing or its signature is invalid. Reinstall Harbor; no extension has been enabled.")
        }
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        command.arguments = ["-a", extensionURL.path]
        let output = Pipe(); command.standardOutput = output; command.standardError = output
        try command.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        command.waitUntilExit()
        guard command.terminationStatus == 0 else {
            let reason = String(data: data, encoding: .utf8) ?? "Registration was refused."
            throw TransferFailure("macOS could not prepare NTFS support. \(reason)")
        }
    }
    static func validSignature(at url: URL, identifier: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"HU5S996C2K\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
    @MainActor static func openExtensionSettings() {
        if #available(macOS 27, *), FSClient.shared.openFileSystemExtensionsSettings() { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }
}
