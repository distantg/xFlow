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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "XFlow",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/XFlow",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "XFlowTests",
            dependencies: ["XFlow"]
        )
    ]
)
