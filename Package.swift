// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Relocate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Relocate", targets: ["Relocate"])
    ],
    targets: [
        .executableTarget(
            name: "Relocate",
            path: "Sources/Relocate"
        ),
        .testTarget(
            name: "RelocateTests",
            dependencies: ["Relocate"],
            path: "Tests/RelocateTests"
        )
    ]
)
