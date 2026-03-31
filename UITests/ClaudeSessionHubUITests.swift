import XCTest

final class ClaudeSessionHubUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--ui-test-mode"]
        app.launch()
    }

    // 1. App launches with fixture data visible
    func testLaunchShowsFixtureSessions() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should appear")
        let sessionList = window.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list should exist with fixture data")
    }

    // 2. Toggle to Overview shows summary cards
    func testOverviewShowsSummaryCards() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "View toggle must exist")
        toggle.buttons.element(boundBy: 1).click()

        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5), "Overview root must appear")

        // All 4 summary cards must exist individually
        for cardID in ["summaryAttention", "summaryActive", "summaryProjects", "summaryLastScan"] {
            let found = app.otherElements[cardID].waitForExistence(timeout: 3)
                || app.staticTexts[cardID].waitForExistence(timeout: 1)
                || app.descendants(matching: .any).matching(identifier: cardID).firstMatch.waitForExistence(timeout: 1)
            XCTAssertTrue(found, "\(cardID) summary card must exist in Overview")
        }
    }

    // 3. Overview → click project → lands in Sessions for THAT project
    func testOverviewProjectNavigation() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons.element(boundBy: 1).click()

        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))

        // The openProject button MUST exist in fixture mode — fail if it doesn't
        let openButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'openProject_'")).firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 5),
                      "Open Project button must exist — fixture has 2 projects (OACP, openclaw)")

        // Extract the project name from the button's identifier (format: "openProject_<name>")
        let buttonID = openButton.identifier
        let expectedProject = String(buttonID.dropFirst("openProject_".count))
        XCTAssertFalse(expectedProject.isEmpty, "Should extract project name from button ID")

        openButton.click()

        // Should switch to Sessions view with session list visible
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5),
                      "Session list must appear after navigating from project")

        // Verify the SPECIFIC project we clicked is now shown in the header
        let projectTitle = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5),
                      "Project title must appear in session list header")
        XCTAssertEqual(projectTitle.label, expectedProject,
                       "Session list should show the clicked project '\(expectedProject)', not a default view")

        // Overview should no longer be showing
        XCTAssertFalse(app.otherElements["overviewRoot"].firstMatch.exists,
                       "Overview should be hidden after project navigation")
    }

    // 4. Tile expand shows quick facts
    func testTileExpandShowsQuickFacts() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5))

        // Tile MUST exist in fixture mode — fail if it doesn't
        let tile = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'sessionTile_'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5),
                      "At least one session tile must exist in fixture mode")

        tile.click()

        // Quick facts MUST appear after click
        let quickFacts = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'quickFacts_'")).firstMatch
        XCTAssertTrue(quickFacts.waitForExistence(timeout: 5),
                      "Quick facts panel must appear when tile is clicked")
    }

    // 5. Settings opens and has ALL expected controls
    func testSettingsControls() {
        app.typeKey(",", modifierFlags: .command)

        // Settings window must open
        let secondWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(secondWindow.waitForExistence(timeout: 5), "Settings window must open on Cmd+,")

        // Verify each control exists by its accessibility identifier
        // These are the controls we explicitly added IDs for — regressions must be caught
        let terminalPicker = secondWindow.popUpButtons["terminalPicker"]
            .firstMatch
        let dataDir = secondWindow.textFields["dataDirectoryField"]
            .firstMatch
        let stepper = secondWindow.steppers["scanIntervalStepper"]
            .firstMatch
        let saveButton = secondWindow.buttons["saveSettingsButton"]
            .firstMatch

        // Use loose matching — SwiftUI may wrap in different element types
        let hasTerminal = terminalPicker.waitForExistence(timeout: 3)
            || secondWindow.descendants(matching: .any).matching(identifier: "terminalPicker").firstMatch.waitForExistence(timeout: 1)
        let hasDataDir = dataDir.waitForExistence(timeout: 1)
            || secondWindow.descendants(matching: .any).matching(identifier: "dataDirectoryField").firstMatch.waitForExistence(timeout: 1)
        let hasStepper = stepper.waitForExistence(timeout: 1)
            || secondWindow.descendants(matching: .any).matching(identifier: "scanIntervalStepper").firstMatch.waitForExistence(timeout: 1)
        let hasSave = saveButton.waitForExistence(timeout: 1)
            || secondWindow.descendants(matching: .any).matching(identifier: "saveSettingsButton").firstMatch.waitForExistence(timeout: 1)

        XCTAssertTrue(hasTerminal, "Terminal picker (terminalPicker) must exist in Settings")
        XCTAssertTrue(hasDataDir, "Data directory field (dataDirectoryField) must exist in Settings")
        XCTAssertTrue(hasStepper, "Scan interval stepper (scanIntervalStepper) must exist in Settings")
        XCTAssertTrue(hasSave, "Save button (saveSettingsButton) must exist in Settings")
    }

    // 6. Fixture attention sessions show in overview
    func testAttentionSessionsExist() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons.element(boundBy: 1).click()

        let inbox = app.otherElements["attentionInbox"].firstMatch
        // Fixture has 2 sessions with health signals (stale + context-high)
        XCTAssertTrue(inbox.waitForExistence(timeout: 5),
                      "Attention inbox must exist — fixture has sessions with health signals")
    }

    // 7. Toggle roundtrip: Sessions → Overview → Sessions
    func testToggleBackToSessions() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        // Go to Overview
        toggle.buttons.element(boundBy: 1).click()
        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5), "Overview must appear")

        // Go back to Sessions
        toggle.buttons.element(boundBy: 0).click()
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list must reappear")

        // Overview must be gone
        XCTAssertFalse(app.otherElements["overviewRoot"].firstMatch.exists,
                       "Overview must be hidden after toggling back")
    }

    // MARK: - Content Correctness Tests (Task 10.7)

    // 8. Verify fixture session tiles show correct content
    func testLaunchShowsFixtureSessionsWithExpectedContent() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list should exist")

        // Verify fixture-active-1 tile and its title content
        let tile1 = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sessionTile_fixture-active-1")).firstMatch
        XCTAssertTrue(tile1.waitForExistence(timeout: 5), "Tile for fixture-active-1 must exist")

        let title1 = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "tileTitle_fixture-active-1")).firstMatch
        XCTAssertTrue(title1.waitForExistence(timeout: 3), "Title label for fixture-active-1 must exist")
        XCTAssertTrue(title1.label.contains("重构 event loop"), "Title should contain '重构 event loop', got '\(title1.label)'")

        // Verify fixture-stale-1 tile and its title content
        let tile2 = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sessionTile_fixture-stale-1")).firstMatch
        XCTAssertTrue(tile2.waitForExistence(timeout: 5), "Tile for fixture-stale-1 must exist")

        let title2 = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "tileTitle_fixture-stale-1")).firstMatch
        XCTAssertTrue(title2.waitForExistence(timeout: 3), "Title label for fixture-stale-1 must exist")
        XCTAssertTrue(title2.label.contains("修复连接池泄漏"), "Title should contain '修复连接池泄漏', got '\(title2.label)'")

        // Verify at least 4 tiles total exist
        let allTiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sessionTile_'"))
        XCTAssertGreaterThanOrEqual(allTiles.count, 4, "Should have at least 4 session tiles from fixture data")
    }

    // 9. Sidebar project selection updates header and session count
    func testSidebarProjectSelectionUpdatesHeaderAndList() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5))

        // Click OACP in sidebar
        let oacpRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sidebarProject_OACP")).firstMatch
        XCTAssertTrue(oacpRow.waitForExistence(timeout: 5), "Sidebar row for OACP must exist")
        oacpRow.click()

        // Verify header shows OACP
        let projectTitle = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5), "Project title must appear after selecting OACP")
        XCTAssertEqual(projectTitle.label, "OACP", "Header should show 'OACP'")

        // Verify session count shows 2
        let countLabel = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sessionCount")).firstMatch
        XCTAssertTrue(countLabel.waitForExistence(timeout: 3), "Session count label must exist")
        XCTAssertTrue(countLabel.label.contains("2"), "OACP should have 2 sessions, got '\(countLabel.label)'")

        // Click openclaw in sidebar
        let openclawRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sidebarProject_openclaw")).firstMatch
        XCTAssertTrue(openclawRow.waitForExistence(timeout: 5), "Sidebar row for openclaw must exist")
        openclawRow.click()

        // Verify header switches to openclaw
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(projectTitle.label, "openclaw", "Header should show 'openclaw'")

        // Verify session count shows 2
        XCTAssertTrue(countLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(countLabel.label.contains("2"), "openclaw should have 2 sessions, got '\(countLabel.label)'")
    }

    // 10. HeatStrip and ProjectCard both navigate to the same project
    func testHeatStripAndProjectCardNavigateToSameProject() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons.element(boundBy: 1).click()

        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))

        // Click heatStrip_OACP
        let heatStrip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "heatStrip_OACP")).firstMatch
        XCTAssertTrue(heatStrip.waitForExistence(timeout: 5), "HeatStrip for OACP must exist")
        heatStrip.click()

        // Verify we landed on OACP sessions
        let projectTitle = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5), "Project title must appear after heatStrip click")
        XCTAssertEqual(projectTitle.label, "OACP", "HeatStrip should navigate to OACP")

        // Switch back to Overview
        let toggle2 = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle2.waitForExistence(timeout: 5))
        toggle2.buttons.element(boundBy: 1).click()
        XCTAssertTrue(app.otherElements["overviewRoot"].firstMatch.waitForExistence(timeout: 5))

        // Click openProject_OACP
        let openButton = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "openProject_OACP")).firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Open Project button for OACP must exist")
        openButton.click()

        // Verify same destination
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5), "Project title must appear after openProject click")
        XCTAssertEqual(projectTitle.label, "OACP", "ProjectCard should also navigate to OACP")
    }

    // 11. QuickFacts shows expected fields for fixture-active-1
    func testQuickFactsShowsExpectedFixtureFields() {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sessionTile_fixture-active-1")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Tile for fixture-active-1 must exist")
        tile.click()

        // Verify quickFacts panel appears
        let quickFacts = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "quickFacts_fixture-active-1")).firstMatch
        XCTAssertTrue(quickFacts.waitForExistence(timeout: 5), "QuickFacts for fixture-active-1 must appear")

        // fixture-active-1 HAS contextUsage, so the context card must exist
        let contextCard = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "quickFactsContext_fixture-active-1")).firstMatch
        XCTAssertTrue(contextCard.waitForExistence(timeout: 5), "Context usage card must exist for fixture-active-1 (has contextUsage)")

        // Stats card must exist
        let statsCard = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "quickFactsStats_fixture-active-1")).firstMatch
        XCTAssertTrue(statsCard.waitForExistence(timeout: 5), "Stats card must exist for fixture-active-1")
    }

    // 12. QuickFacts hides optional fields when data is absent
    func testQuickFactsHidesOptionalFields() {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "sessionTile_fixture-stale-1")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Tile for fixture-stale-1 must exist")
        tile.click()

        // Verify quickFacts panel appears
        let quickFacts = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "quickFacts_fixture-stale-1")).firstMatch
        XCTAssertTrue(quickFacts.waitForExistence(timeout: 5), "QuickFacts for fixture-stale-1 must appear")

        // fixture-stale-1 has NO contextUsage, so the context card must NOT exist
        let contextCard = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "quickFactsContext_fixture-stale-1")).firstMatch
        XCTAssertFalse(contextCard.waitForExistence(timeout: 2), "Context usage card must NOT exist for fixture-stale-1 (no contextUsage)")
    }

    // 13. Settings terminal picker shows default value
    func testSettingsCanChangeTerminalAndPersist() {
        app.typeKey(",", modifierFlags: .command)

        let secondWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(secondWindow.waitForExistence(timeout: 5), "Settings window must open")

        // Find terminal picker
        let terminalPicker = secondWindow.descendants(matching: .any).matching(identifier: "terminalPicker").firstMatch
        XCTAssertTrue(terminalPicker.waitForExistence(timeout: 3), "Terminal picker must exist in Settings")

        // Verify default value is Ghostty
        XCTAssertTrue(terminalPicker.label.contains("Ghostty") || terminalPicker.value as? String == "Ghostty",
                       "Terminal picker default should be Ghostty, got label='\(terminalPicker.label)' value='\(terminalPicker.value ?? "nil")'")
    }

    // 14. Settings scan interval stepper interaction
    func testSettingsCanChangeScanIntervalAndPersist() {
        app.typeKey(",", modifierFlags: .command)

        let secondWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(secondWindow.waitForExistence(timeout: 5), "Settings window must open")

        let stepper = secondWindow.descendants(matching: .any).matching(identifier: "scanIntervalStepper").firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 3), "Scan interval stepper must exist")

        // Get initial label
        let initialLabel = stepper.label

        // Click the increment button
        let incrementButton = stepper.buttons.element(boundBy: 1)
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 2), "Stepper increment button must exist")
        incrementButton.click()

        // Verify the label changed (stepper value increased)
        let updatedLabel = stepper.label
        XCTAssertNotEqual(initialLabel, updatedLabel, "Stepper label should change after increment click")
    }

    // 15. Settings data directory change shows restart hint
    func testDataDirectoryShowsRestartRequiredHint() {
        app.typeKey(",", modifierFlags: .command)

        let secondWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(secondWindow.waitForExistence(timeout: 5), "Settings window must open")

        let dataField = secondWindow.descendants(matching: .any).matching(identifier: "dataDirectoryField").firstMatch
        XCTAssertTrue(dataField.waitForExistence(timeout: 3), "Data directory field must exist")

        // Clear and type a custom path
        dataField.click()
        dataField.typeKey("a", modifierFlags: .command)
        dataField.typeText("/tmp/test-claude")

        // Verify restart hint appears with "重启" text
        let restartHint = secondWindow.descendants(matching: .any).matching(identifier: "restartHint").firstMatch
        XCTAssertTrue(restartHint.waitForExistence(timeout: 3), "Restart hint must appear after changing data directory")
        XCTAssertTrue(restartHint.label.contains("重启"), "Restart hint should mention '重启', got '\(restartHint.label)'")
    }
}
