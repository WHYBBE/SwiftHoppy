// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftHoppy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SwiftHoppy",
            targets: ["SwiftHoppy"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftHoppy",
            path: "Sources"
        )
    ]
)
