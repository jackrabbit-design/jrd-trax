// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraxApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "trax-cli", targets: ["TraxAppExecutable"]),
        .library(name: "TraxApp", targets: ["TraxApp"]),
    ],
    dependencies: [
        .package(path: "TraxKit"),
        .package(path: "KantataAPI"),
    ],
    targets: [
        .target(name: "TraxApp", dependencies: ["TraxKit", "KantataAPI"], path: "TraxApp/Sources/TraxApp"),
        .executableTarget(name: "TraxAppExecutable", dependencies: ["TraxApp"], path: "TraxApp/Sources/TraxAppExecutable"),
        .testTarget(name: "TraxAppTests", dependencies: ["TraxApp"], path: "TraxApp/Tests/TraxAppTests"),
    ]
)
