// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraxApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Trax", targets: ["TraxApp"]),
    ],
    dependencies: [
        .package(path: "TraxKit"),
        .package(path: "KantataAPI"),
    ],
    targets: [
        .executableTarget(name: "TraxApp", dependencies: ["TraxKit", "KantataAPI"], path: "TraxApp/Sources/TraxApp"),
        .testTarget(name: "TraxAppTests", dependencies: ["TraxApp"], path: "TraxApp/Tests/TraxAppTests"),
    ]
)
