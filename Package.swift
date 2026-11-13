// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppleMusicMetadataFixer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AppleMusicMetadataFixer",
            targets: ["AppleMusicMetadataFixer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppleMusicMetadataFixer",
            path: "Sources/AppleMusicMetadataFixer",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
