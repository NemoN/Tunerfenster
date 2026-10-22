// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tunerfenster",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tunerfenster", targets: ["Tunerfenster"])],
    targets: [
        .executableTarget(name: "Tunerfenster", resources: [.process("Resources")]),
        .testTarget(name: "TunerfensterTests", dependencies: ["Tunerfenster"])
    ]
)
