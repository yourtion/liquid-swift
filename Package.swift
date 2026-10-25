// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Liquid",
    products: [
        .library(name: "Liquid", targets: ["Liquid"]),
        .executable(name: "LiquidSpecAdapter", targets: ["LiquidSpecAdapter"]),
    ],
    targets: [
        .executableTarget(name: "LiquidSpecAdapter", dependencies: ["Liquid"], path: "Tools/LiquidSpecAdapter"),
        .target(
            name: "Liquid",
            dependencies: []),
        .testTarget(
            name: "LiquidTests",
            dependencies: ["Liquid"]),
    ],
    swiftLanguageModes: [.v6]
)
