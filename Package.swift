// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cc-manager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cc-manager", targets: ["CCManager"])
    ],
    targets: [
        .executableTarget(
            name: "CCManager",
            path: "Sources/CCManager"
        )
    ]
)
