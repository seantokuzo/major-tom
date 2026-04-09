// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GroundControl",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "GroundControl",
            path: "GroundControl",
            exclude: ["Info.plist"]
        ),
    ]
)
