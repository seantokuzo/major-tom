// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GroundControl",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "GroundControl",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "GroundControl",
            exclude: ["Info.plist"]
        ),
    ]
)
