// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Harbor", platforms: [.macOS("26.0")],
    products: [.executable(name: "Harbor", targets: ["Harbor"]), .executable(name: "HarborMount", targets: ["HarborMount"])],
    targets: [
        .target(name: "HarborCore"),
        .executableTarget(name: "Harbor", dependencies: ["HarborCore"]),
        .target(name: "HarborLegacyNTFS", dependencies: ["HarborCore"]),
        .executableTarget(name: "HarborMount", dependencies: ["HarborCore", "HarborLegacyNTFS"]),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore", "HarborLegacyNTFS"])
    ], swiftLanguageModes: [.v5]
)
