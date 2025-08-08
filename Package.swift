// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTMalloc",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FTMalloc", targets: ["FTMalloc"]) 
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        // Main module points to the allocator sources
        .target(name: "FTMalloc", path: "src/swift"),
    ]
)


