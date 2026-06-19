// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftGNUInfo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SwiftGNUInfo",
            targets: ["SwiftGNUInfo"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftGNUInfo",
            path: "Sources"
        )
    ]
)
