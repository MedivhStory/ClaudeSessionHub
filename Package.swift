// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessionHub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeSessionHubLib",
            path: "Sources/ClaudeSessionHub",
            exclude: ["App"]
        ),
        .executableTarget(
            name: "ClaudeSessionHub",
            dependencies: ["ClaudeSessionHubLib"],
            path: "Sources/ClaudeSessionHub/App"
        ),
        .testTarget(
            name: "ClaudeSessionHubTests",
            dependencies: ["ClaudeSessionHubLib"],
            path: "Tests/XCTests",
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["ClaudeSessionHubLib"],
            path: "Tests/TestRunner"
        ),
        .target(
            name: "EvalHarnessCore",
            dependencies: ["ClaudeSessionHubLib"],
            path: "Sources/EvalHarnessCore"
        ),
        .testTarget(
            name: "EvalHarnessTests",
            dependencies: ["EvalHarnessCore"],
            path: "Tests/EvalHarnessTests"
        ),
        .executableTarget(
            name: "ExtractPromptSourceTool",
            path: "Sources/ExtractPromptSourceTool"
        ),
        .testTarget(
            name: "ExtractPromptSourceToolTests",
            dependencies: [],
            path: "Tests/ExtractPromptSourceToolTests"
        ),
    ]
)
