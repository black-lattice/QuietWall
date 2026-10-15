// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuietWall",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "QuietWall", targets: ["QuietWall"])],
    targets: [
        .target(name: "QuietWallCore"),
        .executableTarget(name: "QuietWall", dependencies: ["QuietWallCore"]),
        .testTarget(name: "QuietWallCoreTests", dependencies: ["QuietWallCore"]),
        .testTarget(name: "QuietWallTests", dependencies: ["QuietWall"])
    ]
)
