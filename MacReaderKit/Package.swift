// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacReaderKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "MacReaderKit", targets: ["MacReaderKit"]),
    ],
    targets: [
        .target(name: "MacReaderKit"),
        .testTarget(name: "MacReaderKitTests", dependencies: ["MacReaderKit"]),
    ]
)
