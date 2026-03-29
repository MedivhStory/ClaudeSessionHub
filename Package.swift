// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSessionHub",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeSessionHub",
            path: "Sources/ClaudeSessionHub",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeSessionHubTests",
            dependencies: ["ClaudeSessionHub"],
            path: "Tests/ClaudeSessionHubTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
    ]
)
