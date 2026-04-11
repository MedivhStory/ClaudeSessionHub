import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class MilestoneSamplerTests: XCTestCase {

    func test_adaptiveK_zero() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 0), 0) }
    func test_adaptiveK_one() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 1), 1) }
    func test_adaptiveK_two() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 2), 2) }
    func test_adaptiveK_three() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 3), 3) }
    func test_adaptiveK_four() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 4), 4) }
    func test_adaptiveK_39() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 39), 4) }
    func test_adaptiveK_40() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 40), 4) }
    func test_adaptiveK_50() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 50), 5) }
    func test_adaptiveK_60() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 60), 6) }
    func test_adaptiveK_70() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 70), 7) }
    func test_adaptiveK_80() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 80), 8) }
    func test_adaptiveK_200() { XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 200), 8) }
    func test_adaptiveK_smallHistory_doesNotExceedCount() {
        XCTAssertEqual(MilestoneSampler.adaptiveK(historyCount: 2), 2)
    }
}
