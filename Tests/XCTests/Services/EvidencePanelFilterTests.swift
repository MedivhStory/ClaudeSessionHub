import XCTest
#if canImport(ClaudeSessionHubLib)
@testable import ClaudeSessionHubLib
#else
@testable import ClaudeSessionHub
#endif

/// C3.1 coverage: `EvidencePanel.expandedTileFiltered(_:)` is a pure
/// view-level display policy that hides categories duplicated elsewhere
/// in the expanded session tile. Tests assert which categories drop,
/// which are kept, and that the policy collapses to an empty package
/// (which the view treats as "render nothing") when nothing remains.
final class EvidencePanelFilterTests: XCTestCase {

    private func item(_ cat: EvidenceCategory) -> EvidenceItem {
        EvidenceItem(category: cat, title: "t", lines: ["l"])
    }

    // MARK: - Empty / pass-through

    func testEmptyPackagePassesThroughEmpty() {
        let pkg = EvidencePanel.expandedTileFiltered(EvidencePackage(items: []))
        XCTAssertTrue(pkg.isEmpty)
    }

    // MARK: - Each duplicate category drops

    func testDropsRecentFiles() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.recentFiles)])
        )
        XCTAssertTrue(
            pkg.isEmpty,
            "QuickFactsView shows concrete file names; coarser count must drop"
        )
    }

    func testDropsTimeAnchors() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.timeAnchors)])
        )
        XCTAssertTrue(pkg.isEmpty, "tile header already shows created/lastActive")
    }

    func testDropsBranchCwd() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.branchCwd)])
        )
        XCTAssertTrue(pkg.isEmpty, "metadata row already shows project + branch")
    }

    func testDropsProjectName() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.projectName)])
        )
        XCTAssertTrue(pkg.isEmpty, "metadata row already shows project + branch")
    }

    func testDropsRelatedSessions() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.relatedSessions)])
        )
        XCTAssertTrue(pkg.isEmpty, "leftColumn already lists related sessions")
    }

    // MARK: - Kept categories

    func testKeepsCurrentPhase() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.currentPhase)])
        )
        XCTAssertEqual(pkg.items.map(\.category), [.currentPhase])
    }

    func testKeepsLatestProgress() {
        let pkg = EvidencePanel.expandedTileFiltered(
            EvidencePackage(items: [item(.latestProgress)])
        )
        XCTAssertEqual(pkg.items.map(\.category), [.latestProgress])
    }

    // MARK: - Mixed input

    func testFullPackageReducesToCurrentPhasePlusLatestProgress() {
        // §9-ordered full emission with all 7 categories present.
        let input = EvidencePackage(items: [
            item(.recentFiles),
            item(.timeAnchors),
            item(.branchCwd),
            item(.relatedSessions),
            item(.projectName),
            item(.currentPhase),
            item(.latestProgress)
        ])
        let pkg = EvidencePanel.expandedTileFiltered(input)
        XCTAssertEqual(
            pkg.items.map(\.category),
            [.currentPhase, .latestProgress],
            "expanded-tile filter keeps only the two non-duplicated categories"
        )
    }

    func testAllDuplicateCategoriesCollapseToEmpty() {
        // No `.currentPhase` / `.latestProgress` → after filtering, package
        // is empty → view renders nothing (no header, no DisclosureGroup).
        let input = EvidencePackage(items: [
            item(.recentFiles),
            item(.timeAnchors),
            item(.branchCwd),
            item(.relatedSessions),
            item(.projectName)
        ])
        let pkg = EvidencePanel.expandedTileFiltered(input)
        XCTAssertTrue(
            pkg.isEmpty,
            "all-duplicate input must collapse to empty so the panel hides entirely"
        )
    }

    // MARK: - Order preservation

    func testOrderPreservedForKeptCategoriesInComposerOrder() {
        // currentPhase precedes latestProgress in §9 listing order.
        let input = EvidencePackage(items: [
            item(.currentPhase),
            item(.latestProgress)
        ])
        let pkg = EvidencePanel.expandedTileFiltered(input)
        XCTAssertEqual(pkg.items.map(\.category), [.currentPhase, .latestProgress])
    }
}
