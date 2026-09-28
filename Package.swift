// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ClipHat", platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipHat", targets: ["ClipHat"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ClipHatCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "ClipHat", dependencies: ["ClipHatCore"]),
        .executableTarget(name: "ClipHatChecks", dependencies: ["ClipHatCore"], path: "Tests/ClipHatChecks")
    ])
