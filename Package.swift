// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacErase",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacErase",
            path: "Sources/MacErase"
        ),
        .testTarget(
            name: "MacEraseTests",
            dependencies: ["MacErase"]
        )
    ]
)
