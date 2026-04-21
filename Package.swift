// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "XFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "XFlow", targets: ["XFlow"])
    ],
    targets: [
        .executableTarget(
            name: "XFlow",
            path: "Sources/XFlow"
        ),
        .testTarget(
            name: "XFlowTests",
            dependencies: ["XFlow"]
        )
    ]
)
