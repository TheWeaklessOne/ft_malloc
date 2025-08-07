// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTMallocDocs",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FTMallocDocs", targets: ["FTMallocDocs"]) 
    ],
    targets: [
        .target(name: "FTMallocDocs", path: "Sources/FTMalloc"),
    ]
)


