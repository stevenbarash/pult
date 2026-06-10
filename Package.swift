// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Pult",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PultApp", targets: ["PultApp"]),
        .executable(name: "PultCoreCheck", targets: ["PultCoreCheck"]),
        .library(name: "PultCore", targets: ["PultCore"])
    ],
    targets: [
        .target(
            name: "PultCore",
            path: "Sources/PultCore"
        ),
        .executableTarget(
            name: "PultApp",
            dependencies: ["PultCore"],
            path: "Sources/PultApp",
            exclude: ["Supporting/Info.plist"]
        ),
        .executableTarget(
            name: "PultCoreCheck",
            dependencies: ["PultCore"],
            path: "Sources/PultCoreCheck"
        ),
        .testTarget(
            name: "PultCoreTests",
            dependencies: ["PultCore"],
            path: "Tests/PultCoreTests"
        )
    ]
)
