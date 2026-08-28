// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whamrando",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Whamrando", targets: ["Whamrando"]),
    ],
    targets: [
        .target(name: "Whamrando", dependencies: []),
        .testTarget(name: "WhamrandoTests", dependencies: ["Whamrando"], path: "Tests/UnitTests"),
    ]
)
