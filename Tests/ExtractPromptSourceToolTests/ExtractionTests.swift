import XCTest

final class ExtractionTests: XCTestCase {

    private func toolPath() throws -> String {
        // The tool binary should be at .build/debug/ExtractPromptSourceTool
        // after `swift build`
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Tests/ExtractPromptSourceToolTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // project root
        let path = projectRoot
            .appendingPathComponent(".build/debug/ExtractPromptSourceTool")
            .path
        if !FileManager.default.fileExists(atPath: path) {
            // Try building the target
            let buildProcess = Process()
            buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            buildProcess.currentDirectoryURL = projectRoot
            buildProcess.arguments = ["build", "--target", "ExtractPromptSourceTool"]
            try buildProcess.run()
            buildProcess.waitUntilExit()
        }
        return path
    }

    private func run(args: [String]) throws -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try toolPath())
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        return (process.terminationStatus, errStr)
    }

    func test_extract_validFunction_success() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let inputPath = tmpDir.appendingPathComponent("Test.swift").path
        let outputPath = tmpDir.appendingPathComponent("Generated.swift").path

        let testSource = """
        public enum Foo {
            public static func titleInput(from x: String) -> String {
                return "hello"
            }
        }
        """
        try testSource.write(toFile: inputPath, atomically: true, encoding: .utf8)

        let result = try run(args: [inputPath, outputPath])
        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        let generated = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(generated.contains("titleInputFunctionSource"))
        XCTAssertTrue(generated.contains("return \\\"hello\\\""))
    }

    func test_extract_missingFile_exits2() throws {
        let result = try run(args: ["/nonexistent/path.swift", "/tmp/out.swift"])
        XCTAssertEqual(result.exitCode, 2)
    }

    func test_extract_missingFunction_exits3() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let inputPath = tmpDir.appendingPathComponent("NoFunc.swift").path
        try "public enum Empty {}".write(toFile: inputPath, atomically: true, encoding: .utf8)

        let result = try run(args: [inputPath, "/tmp/out.swift"])
        XCTAssertEqual(result.exitCode, 3)
    }

    func test_extract_againstRealLLMPrompts_succeeds() throws {
        // Run against the actual LLMPrompts.swift in the repo
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let realPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClaudeSessionHub/Services/LLMPrompts.swift")
            .path
        let outputPath = tmpDir.appendingPathComponent("Gen.swift").path

        let result = try run(args: [realPath, outputPath])
        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        let generated = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(generated.contains("titleInputFunctionSource"))
        XCTAssertTrue(generated.contains("MilestoneSampler"))
    }
}
