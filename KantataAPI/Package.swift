// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KantataAPI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KantataAPI", targets: ["KantataAPI"]),
    ],
    targets: [
        .target(name: "KantataAPI"),
        .testTarget(name: "KantataAPITests", dependencies: ["KantataAPI"]),
    ]
)
