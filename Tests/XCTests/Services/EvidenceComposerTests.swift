import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// C1 coverage: pure composition rules for `EvidenceComposer.compose(...)`.
/// Tests cover per-category emission rules, empty-category omission,
/// rev.3 audit decisions (degraded `filesTouched` count, omitted
/// `recentToolOps`, `.unknown` taskPhase omission, `lastProgress`
/// fallback cascade), and the §9 ordering invariant.
final class EvidenceComposerTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        sessionID: String = "s1",
        title: String = "test",
        currentTaskSummary: String? = nil,
        taskPhase: TaskPhase = .unknown,
        cwd: String? = nil,
        branch: String? = nil,
        filesTouched: Int = 0,
        lastProgress: String? = nil
    ) -> SessionSummary {
        SessionSummary(
            ref: SessionRef(providerID: "claude", sessionID: sessionID),
            title: title,
            currentTaskSummary: currentTaskSummary,
            runtimeState: .active,
            taskPhase: taskPhase,
            cwd: cwd,
            branch: branch,
            turnCount: 0,
            filesTouched: filesTouched,
            recentErrorCount: 0,
            createdAt: Date(timeIntervalSince1970: 1000),
            lastActiveAt: Date(timeIntervalSince1970: 2000),
            contextUsage: nil,
            smartTitle: nil,
            lastProgress: lastProgress,
            entrypoint: nil
        )
    }

    private func item(_ pkg: EvidencePackage, _ category: EvidenceCategory) -> EvidenceItem? {
        pkg.items.first(where: { $0.category == category })
    }

    // MARK: - Empty / minimal

    func testMinimalSessionEmitsTimeAnchorsOnly() {
        // Defaults: no files / no cwd / no branch / no progress / .unknown phase / no relations.
        // Time anchors always emit because createdAt + lastActiveAt are non-optional.
        let pkg = EvidenceComposer.compose(session: makeSession(), relations: [])
        XCTAssertEqual(pkg.items.count, 1)
        XCTAssertEqual(pkg.items.first?.category, .timeAnchors)
    }

    // MARK: - Source 1: recentFiles (degraded count line)

    func testRecentFilesDegradedToCount() {
        let session = makeSession(filesTouched: 12)
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        let recent = item(pkg, .recentFiles)
        XCTAssertNotNil(recent)
        XCTAssertEqual(recent?.lines, ["12 个文件被修改"])
    }

    func testRecentFilesOmittedWhenZero() {
        let session = makeSession(filesTouched: 0)
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        XCTAssertNil(item(pkg, .recentFiles), "0 files must omit the category, not show '0 files'")
    }

    // MARK: - Source 2: recentToolOps (omitted entirely from P4)

    func testToolOpsCategoryNotInEnum() {
        // Audit row 2: P4 omits the recentToolOps category. The enum
        // intentionally has no case for it. Asserting via CaseIterable
        // catches accidental future re-introduction.
        let cases = EvidenceCategory.allCases
        XCTAssertEqual(cases.count, 7)
        XCTAssertFalse(cases.map(\.rawValue).contains("recentToolOps"))
    }

    // MARK: - Source 3: time anchors

    func testTimeAnchorsAlwaysEmitTwoLines() {
        let pkg = EvidenceComposer.compose(session: makeSession(), relations: [])
        let anchors = item(pkg, .timeAnchors)
        XCTAssertNotNil(anchors)
        XCTAssertEqual(anchors?.lines.count, 2)
        XCTAssertTrue(anchors?.lines[0].hasPrefix("创建于 ") == true)
        XCTAssertTrue(anchors?.lines[1].hasPrefix("最近活跃 ") == true)
    }

    // MARK: - Source 4: branch + cwd

    func testBranchCwdOmittedWhenBothNil() {
        let pkg = EvidenceComposer.compose(session: makeSession(), relations: [])
        XCTAssertNil(item(pkg, .branchCwd))
    }

    func testBranchCwdShowsBoth() {
        let session = makeSession(cwd: "/tmp/repo", branch: "main")
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        let bc = item(pkg, .branchCwd)
        XCTAssertEqual(bc?.lines, ["路径 · /tmp/repo", "分支 · main"])
    }

    func testBranchCwdShowsOnlyOnePresent() {
        let session = makeSession(cwd: "/tmp/repo", branch: nil)
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        let bc = item(pkg, .branchCwd)
        XCTAssertEqual(bc?.lines, ["路径 · /tmp/repo"])
    }

    func testBranchCwdOmittedWhenBothEmpty() {
        // Empty strings count as missing for omission purposes.
        let session = makeSession(cwd: "", branch: "")
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        XCTAssertNil(item(pkg, .branchCwd))
    }

    // MARK: - Source 5: related sessions

    func testRelatedSessionsOmittedWhenEmpty() {
        let pkg = EvidenceComposer.compose(session: makeSession(), relations: [])
        XCTAssertNil(item(pkg, .relatedSessions))
    }

    func testRelatedSessionsLinesPerRelation() {
        let relations = [
            SessionRelation(otherSessionID: "abc12345-rest-of-uuid", type: .sameBranch),
            SessionRelation(otherSessionID: "def67890-rest-of-uuid", type: .timeOverlap),
            SessionRelation(otherSessionID: "ghi24680-rest-of-uuid", type: .continuation)
        ]
        let pkg = EvidenceComposer.compose(session: makeSession(), relations: relations)
        let rs = item(pkg, .relatedSessions)
        XCTAssertEqual(rs?.lines.count, 3)
        XCTAssertEqual(rs?.lines[0], "abc12345 · 同分支")
        XCTAssertEqual(rs?.lines[1], "def67890 · 时间重叠")
        XCTAssertEqual(rs?.lines[2], "ghi24680 · 延续")
    }

    // MARK: - Source 6: project name

    func testProjectNameOmittedWhenCwdNil() {
        let pkg = EvidenceComposer.compose(session: makeSession(), relations: [])
        XCTAssertNil(item(pkg, .projectName))
    }

    func testProjectNameUsesResolver() {
        let session = makeSession(cwd: "/Users/me/Documents/projectX")
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        let pn = item(pkg, .projectName)
        XCTAssertNotNil(pn)
        XCTAssertEqual(pn?.lines, [ProjectNameResolver.displayName(for: "/Users/me/Documents/projectX")])
    }

    // MARK: - Source 7: current phase (.unknown omission)

    func testCurrentPhaseOmittedWhenUnknown() {
        let session = makeSession(taskPhase: .unknown)
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        XCTAssertNil(
            item(pkg, .currentPhase),
            ".unknown is the documented placeholder, not a missing value — but P4 still omits"
        )
    }

    func testCurrentPhaseShownForKnownPhases() {
        for (phase, expectedLine) in [
            (TaskPhase.inProgress, "进行中"),
            (.blocked, "阻塞"),
            (.done, "完成")
        ] {
            let session = makeSession(taskPhase: phase)
            let pkg = EvidenceComposer.compose(session: session, relations: [])
            let cp = item(pkg, .currentPhase)
            XCTAssertEqual(cp?.lines, [expectedLine], "phase=\(phase)")
        }
    }

    // MARK: - Source 8: latest assistant progress (cascade)

    func testLatestProgressUsesLastProgress() {
        let session = makeSession(
            currentTaskSummary: "summary fallback",
            lastProgress: "primary progress"
        )
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        let lp = item(pkg, .latestProgress)
        XCTAssertEqual(lp?.lines, ["primary progress"], "lastProgress wins when both are present")
    }

    func testLatestProgressFallsBackToCurrentTaskSummary() {
        let session = makeSession(
            currentTaskSummary: "summary fallback",
            lastProgress: nil
        )
        let pkg = EvidenceComposer.compose(session: session, relations: [])
        let lp = item(pkg, .latestProgress)
        XCTAssertEqual(lp?.lines, ["summary fallback"])
    }

    func testLatestProgressOmittedWhenBothNilOrEmpty() {
        for (summary, progress) in [
            (nil, nil),
            ("", nil),
            (nil, ""),
            ("", "")
        ] as [(String?, String?)] {
            let session = makeSession(currentTaskSummary: summary, lastProgress: progress)
            let pkg = EvidenceComposer.compose(session: session, relations: [])
            XCTAssertNil(item(pkg, .latestProgress))
        }
    }

    // MARK: - Ordering (§9 listing order)

    func testItemsOrderedPerSection9() {
        // Build a fully-populated session so all 7 categories emit.
        let session = makeSession(
            currentTaskSummary: nil,
            taskPhase: .inProgress,
            cwd: "/repo",
            branch: "main",
            filesTouched: 3,
            lastProgress: "did things"
        )
        let relations = [SessionRelation(otherSessionID: "other1234", type: .sameBranch)]
        let pkg = EvidenceComposer.compose(session: session, relations: relations)
        XCTAssertEqual(
            pkg.items.map(\.category),
            [
                .recentFiles,
                .timeAnchors,
                .branchCwd,
                .relatedSessions,
                .projectName,
                .currentPhase,
                .latestProgress
            ],
            "items must follow PLAN §9 listing order minus omitted recentToolOps"
        )
    }
}
