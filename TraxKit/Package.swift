// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraxKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TraxKit", targets: ["TraxKit"]),
    ],
    targets: [
        .target(name: "TraxKit"),
        .testTarget(
            name: "TraxKitTests",
            dependencies: ["TraxKit"]
        ),
    ]
)
