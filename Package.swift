// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tunerfenster",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tunerfenster", targets: ["Tunerfenster"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "Tunerfenster", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          resources: [.process("Resources")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "TunerfensterTests", dependencies: ["Tunerfenster"])
    ]
)
