// Tests/XCTests/Models/VersionMentionTests.swift
import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

final class VersionMentionTests: XCTestCase {
    func test_init_historyKindRequiresNonNilIndex() {
        let ref = SourceRef(kind: .history, index: 3)
        XCTAssertEqual(ref.kind, .history)
        XCTAssertEqual(ref.index, 3)
    }

    func test_init_nonHistoryKindRequiresNilIndex() {
        let ref = SourceRef(kind: .taskSubject)
        XCTAssertEqual(ref.kind, .taskSubject)
        XCTAssertNil(ref.index)
    }

    func test_versionMention_jsonRoundTrip() throws {
        let vm = VersionMention(
            raw: "v0.2.5",
            normalized: "0.2.5",
            selectedSource: SourceRef(kind: .history, index: 3),
            occurrenceCount: 3
        )
        let data = try JSONEncoder().encode(vm)
        let decoded = try JSONDecoder().decode(VersionMention.self, from: data)
        XCTAssertEqual(decoded, vm)
    }

    func test_sourceRef_decoder_rejectsHistoryWithoutIndex() {
        let json = #"{"kind":"history","index":null}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SourceRef.self, from: json))
    }

    func test_sourceRef_decoder_rejectsNonHistoryWithIndex() {
        let json = #"{"kind":"taskSubject","index":3}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SourceRef.self, from: json))
    }

    func test_sourceRef_decoder_acceptsValidHistory() throws {
        let json = #"{"kind":"history","index":2}"#.data(using: .utf8)!
        let ref = try JSONDecoder().decode(SourceRef.self, from: json)
        XCTAssertEqual(ref.kind, .history)
        XCTAssertEqual(ref.index, 2)
    }

    func test_sourceKind_allCases_countIsSix() {
        XCTAssertEqual(SourceKind.allCases.count, 6)
    }
}
