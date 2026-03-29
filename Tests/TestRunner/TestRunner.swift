import Foundation

// Minimal test harness — no Xcode/XCTest required, runs via `swift run TestRunner`

var passed = 0
var failed = 0
var errors: [String] = []

func check(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        let loc = "\((file as NSString).lastPathComponent):\(line)"
        errors.append("  FAIL \(loc): \(message)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        let loc = "\((file as NSString).lastPathComponent):\(line)"
        errors.append("  FAIL \(loc): \(message.isEmpty ? "\(a) != \(b)" : message)")
    }
}

func assertApprox(_ a: Double, _ b: Double, accuracy: Double = 0.001, file: String = #file, line: Int = #line) {
    if abs(a - b) < accuracy {
        passed += 1
    } else {
        failed += 1
        let loc = "\((file as NSString).lastPathComponent):\(line)"
        errors.append("  FAIL \(loc): \(a) !≈ \(b)")
    }
}

func printResults() {
    print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
    for e in errors { print(e) }
    if failed > 0 {
        print("\n❌ TESTS FAILED")
        exit(1)
    } else {
        print("\n✅ ALL TESTS PASSED")
    }
}

// Run all test suites
@main
struct TestMain {
    static func main() {
        print("Running Claude Session Hub Tests...\n")
        CanonicalModelsTests.run()
        JSONLParserTests.run()
        ClaudeProviderTests.run()
        HealthEngineTests.run()
        LabelStoreTests.run()
        printResults()
    }
}
