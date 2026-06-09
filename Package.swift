// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReedKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ReedKit", targets: ["ReedKit"]),
    ],
    targets: [
        .target(name: "ReedKit", path: "Sources/ReedKit"),
        .testTarget(name: "ReedKitTests", dependencies: ["ReedKit"], path: "Tests/ReedKitTests"),
    ]
)
