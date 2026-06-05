// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "modex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "modex", targets: ["modex"]),
        .library(name: "ModexCore", targets: ["ModexCore"]),
    ],
    targets: [
        .target(
            name: "ModexCore"
        ),
        .executableTarget(
            name: "modex",
            dependencies: ["ModexCore"]
        ),
        .testTarget(
            name: "modexTests",
            dependencies: ["ModexCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
