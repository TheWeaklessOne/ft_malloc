// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTMallocDemo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FTMallocDemo", targets: ["FTMallocDemo"]) 
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FTMallocDemo",
            path: ".",
            sources: ["App.swift", "ContentView.swift"],
            swiftSettings: [
                .define("APPLICATION_EXTENSION_API_ONLY", .when(platforms: [.macOS]))
            ]
        )
    ]
)


