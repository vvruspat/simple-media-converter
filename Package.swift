// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleMediaConverter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SimpleMediaConverter",
            path: "Sources/SimpleMediaConverter",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
