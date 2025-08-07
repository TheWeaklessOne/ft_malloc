// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTMallocDocs",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FTMallocDocs", targets: ["FTMallocDocs"]) 
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        .target(name: "FTMallocDocs", path: "Sources/FTMalloc"),
    ]
)


