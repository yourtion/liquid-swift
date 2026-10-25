// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "LiquidServerRenderExample",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LiquidServer", targets: ["LiquidServer"])],
    dependencies: [
        .package(name: "Liquid", path: "../.."),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.28.0"),
    ],
    targets: [
        .executableTarget(
            name: "LiquidServer",
            dependencies: [
                .product(name: "Liquid", package: "Liquid"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            resources: [.copy("Templates")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
