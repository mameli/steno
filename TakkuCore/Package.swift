// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TakkuCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TakkuCore", targets: ["TakkuCore"]),
    ],
    targets: [
        .target(name: "TakkuCore"),
        .testTarget(name: "TakkuCoreTests", dependencies: ["TakkuCore"]),
    ]
)
