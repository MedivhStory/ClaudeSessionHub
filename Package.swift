// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSessionHub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeSessionHubLib",
            path: "Sources/ClaudeSessionHub",
            exclude: ["App"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudeSessionHub",
            dependencies: ["ClaudeSessionHubLib"],
            path: "Sources/ClaudeSessionHub/App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["ClaudeSessionHubLib"],
            path: "Tests/ClaudeSessionHubTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
