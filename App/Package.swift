// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThirtyThreeRPM",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ThirtyThreeRPM",
            path: "Sources/ThirtyThreeRPM"
        )
    ]
)
