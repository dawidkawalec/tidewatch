// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidewatchCore",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "TidewatchCore", targets: ["TidewatchCore"]),
    ],
    targets: [
        .target(name: "TidewatchCore"),
        .testTarget(name: "TidewatchCoreTests", dependencies: ["TidewatchCore"]),
    ]
)
