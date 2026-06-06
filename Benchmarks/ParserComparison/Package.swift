// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ParserComparison",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ParserComparison", targets: ["ParserComparison"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/orlandos-nl/swift-json.git", from: "2.5.0")
    ],
    targets: [
        .executableTarget(
            name: "ParserComparison",
            dependencies: [
                .product(name: "ModexCore", package: "modex"),
                .product(name: "IkigaJSON", package: "swift-json"),
                .product(name: "NIOCore", package: "swift-nio")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
