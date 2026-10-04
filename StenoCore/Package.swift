// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StenoCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StenoCore", targets: ["StenoCore"]),
    ],
    targets: [
        .target(name: "StenoCore"),
        .testTarget(name: "StenoCoreTests", dependencies: ["StenoCore"]),
    ]
)
