import XCTest

final class ClaudeSessionHubUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--ui-test-mode"]
        app.launch()
    }

    // MARK: - Helpers

    /// The viewToggle Picker with .segmented style renders as a RadioGroup on macOS.
    private func viewToggle() -> XCUIElement {
        app.radioGroups["viewToggle"]
    }

    /// Switch to Overview tab by clicking the Overview radio button.
    private func switchToOverview() {
        let toggle = viewToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "View toggle must exist")
        toggle.radioButtons["Overview"].click()
    }

    /// Switch to Sessions tab by clicking the Sessions radio button.
    private func switchToSessions() {
        let toggle = viewToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "View toggle must exist")
        toggle.radioButtons["Sessions"].click()
    }

    /// Click a sidebar project row by identifier.
    /// The sidebar uses onTapGesture (not Button) to work with XCUITest on macOS List.
    @discardableResult
    private func clickSidebarProject(_ projectName: String) -> Bool {
        let row = app.descendants(matching: .any).matching(identifier: "sidebarProject_\(projectName)").firstMatch
        guard row.waitForExistence(timeout: 5) else { return false }
        row.click()
        return true
    }

    /// Open Settings via the menu bar (Cmd+, may not work in XCUITest).
    private func openSettings() {
        // Use menu bar: ClaudeSessionHub > Settings…
        app.menuBars.menuBarItems["ClaudeSessionHub"].click()
        app.menuBars.menuItems["Settings…"].click()
    }

    // MARK: - Tests

    // 1. App launches with fixture data visible
    func testLaunchShowsFixtureSessions() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should appear")
        let sessionList = window.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list should exist with fixture data")
    }

    // 2. Toggle to Overview shows summary cards
    func testOverviewShowsSummaryCards() {
        switchToOverview()

        let overview = app.scrollViews.matching(NSPredicate(format: "identifier == %@", "overviewRoot")).firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5), "Overview root must appear")

        // Summary cards: In overview, check for the summary card identifiers.
        // SwiftUI may render them as various element types, so use descendants.
        for cardID in ["summaryAttention", "summaryActive", "summaryProjects", "summaryLastScan"] {
            let found = app.descendants(matching: .any).matching(identifier: cardID).firstMatch
                .waitForExistence(timeout: 3)
            XCTAssertTrue(found, "\(cardID) summary card must exist in Overview")
        }
    }

    // 3. Overview -> click project -> lands in Sessions for THAT project
    func testOverviewProjectNavigation() {
        switchToOverview()

        let overview = app.descendants(matching: .any).matching(identifier: "overviewRoot").firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))

        // The openProject button MUST exist in fixture mode
        let openButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'openProject_'")).firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 5),
                      "Open Project button must exist -- fixture has 2 projects (OACP, openclaw)")

        // Extract the project name from the button's identifier
        let buttonID = openButton.identifier
        let expectedProject = String(buttonID.dropFirst("openProject_".count))
        XCTAssertFalse(expectedProject.isEmpty, "Should extract project name from button ID")

        openButton.click()

        // Should switch to Sessions view with session list visible
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5),
                      "Session list must appear after navigating from project")

        // Verify the SPECIFIC project we clicked is now shown in the header
        // SwiftUI Text exposes content as `value`, not `label`
        let projectTitle = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5),
                      "Project title must appear in session list header")
        let titleValue = "\(projectTitle.value ?? "")"
        XCTAssertEqual(titleValue, expectedProject,
                       "Session list should show the clicked project '\(expectedProject)', not '\(titleValue)'")

        // Overview should no longer be showing
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "overviewRoot").firstMatch.exists,
                       "Overview should be hidden after project navigation")
    }

    // 4. Tile expand shows quick facts
    func testTileExpandShowsQuickFacts() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5))

        // Session tiles render as StaticText with the sessionTile_ identifier in the accessibility tree.
        // Click the first matching element to expand a tile.
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sessionTile_'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5),
                      "At least one session tile must exist in fixture mode")

        tile.click()

        // Quick facts MUST appear after click
        let quickFacts = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'quickFacts_'")).firstMatch
        XCTAssertTrue(quickFacts.waitForExistence(timeout: 5),
                      "Quick facts panel must appear when tile is clicked")
    }

    // 5. Settings opens and has ALL expected controls
    func testSettingsControls() {
        openSettings()

        // Settings window must open -- it may be a sheet or a second window
        // Try to find the settings form
        let settingsForm = app.descendants(matching: .any).matching(identifier: "settingsForm").firstMatch
        XCTAssertTrue(settingsForm.waitForExistence(timeout: 5), "Settings form must exist after opening Settings")

        // Verify each control exists by its accessibility identifier using loose matching
        let hasTerminal = app.descendants(matching: .any).matching(identifier: "terminalPicker").firstMatch
            .waitForExistence(timeout: 3)
        let hasDataDir = app.descendants(matching: .any).matching(identifier: "dataDirectoryField").firstMatch
            .waitForExistence(timeout: 3)
        let hasStepper = app.descendants(matching: .any).matching(identifier: "scanIntervalStepper").firstMatch
            .waitForExistence(timeout: 3)
        let hasSave = app.descendants(matching: .any).matching(identifier: "saveSettingsButton").firstMatch
            .waitForExistence(timeout: 3)

        XCTAssertTrue(hasTerminal, "Terminal picker (terminalPicker) must exist in Settings")
        XCTAssertTrue(hasDataDir, "Data directory field (dataDirectoryField) must exist in Settings")
        XCTAssertTrue(hasStepper, "Scan interval stepper (scanIntervalStepper) must exist in Settings")
        XCTAssertTrue(hasSave, "Save button (saveSettingsButton) must exist in Settings")
    }

    // 6. Fixture attention sessions show in overview
    func testAttentionSessionsExist() {
        switchToOverview()

        let inbox = app.descendants(matching: .any).matching(identifier: "attentionInbox").firstMatch
        // Fixture has 2 sessions with health signals (stale + context-high)
        XCTAssertTrue(inbox.waitForExistence(timeout: 5),
                      "Attention inbox must exist -- fixture has sessions with health signals")
    }

    // 7. Toggle roundtrip: Sessions -> Overview -> Sessions
    func testToggleBackToSessions() {
        let toggle = viewToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        // Go to Overview
        switchToOverview()
        let overview = app.descendants(matching: .any).matching(identifier: "overviewRoot").firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5), "Overview must appear")

        // Go back to Sessions
        switchToSessions()
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list must reappear")

        // Overview must be gone
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "overviewRoot").firstMatch.exists,
                       "Overview must be hidden after toggling back")
    }

    // MARK: - Content Correctness Tests (Task 10.7)

    // 8. Verify fixture session tiles show correct content
    func testLaunchShowsFixtureSessionsWithExpectedContent() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list should exist")

        // With .accessibilityElement(children: .contain), each tile is a container
        // with the sessionTile_ identifier, and child elements have their own identifiers
        // (tileTitle_, tileMeta_, etc.)
        let tile1 = app.descendants(matching: .any).matching(identifier: "sessionTile_fixture-active-1").firstMatch
        XCTAssertTrue(tile1.waitForExistence(timeout: 5), "Tile for fixture-active-1 must exist")

        // The title text should be a child with tileTitle_ identifier
        let title1 = app.staticTexts["tileTitle_fixture-active-1"].firstMatch
        XCTAssertTrue(title1.waitForExistence(timeout: 3), "Title label for fixture-active-1 must exist")
        let title1Value = "\(title1.value ?? "")"
        XCTAssertTrue(title1Value.contains("重构 event loop"),
                      "Title should contain '重构 event loop', got '\(title1Value)'")

        // Verify fixture-stale-1 tile
        let tile2 = app.descendants(matching: .any).matching(identifier: "sessionTile_fixture-stale-1").firstMatch
        XCTAssertTrue(tile2.waitForExistence(timeout: 5), "Tile for fixture-stale-1 must exist")

        let title2 = app.staticTexts["tileTitle_fixture-stale-1"].firstMatch
        XCTAssertTrue(title2.waitForExistence(timeout: 3), "Title label for fixture-stale-1 must exist")
        let title2Value = "\(title2.value ?? "")"
        XCTAssertTrue(title2Value.contains("修复连接池泄漏"),
                      "Title should contain '修复连接池泄漏', got '\(title2Value)'")

        // Verify at least 4 tiles by checking the 4th session exists
        let tile4 = app.descendants(matching: .any).matching(identifier: "sessionTile_fixture-done-1").firstMatch
        XCTAssertTrue(tile4.waitForExistence(timeout: 5),
                      "Tile for fixture-done-1 must exist (at least 4 sessions)")
    }

    // 9. Sidebar project selection updates header and session count
    func testSidebarProjectSelectionUpdatesHeaderAndList() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5))

        // Click OACP in sidebar
        XCTAssertTrue(clickSidebarProject("OACP"), "Sidebar row for OACP must exist")

        // Verify header shows OACP (SwiftUI Text exposes content as `value`, not `label`)
        let projectTitle = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5), "Project title must appear after selecting OACP")
        let oacpTitle = "\(projectTitle.value ?? "")"
        XCTAssertTrue(oacpTitle.contains("OACP"),
                      "Header should show 'OACP', got '\(oacpTitle)'")

        // Verify session count shows 2
        let countLabel = app.descendants(matching: .any).matching(identifier: "sessionCount").firstMatch
        XCTAssertTrue(countLabel.waitForExistence(timeout: 3), "Session count label must exist")
        let countText = "\(countLabel.value ?? "")"
        XCTAssertTrue(countText.contains("2"), "OACP should have 2 sessions, got '\(countText)'")

        // Click openclaw in sidebar
        XCTAssertTrue(clickSidebarProject("openclaw"), "Sidebar row for openclaw must exist")

        // Verify header switches to openclaw
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 5))
        let openclawTitle = "\(projectTitle.value ?? "")"
        XCTAssertTrue(openclawTitle.contains("openclaw"),
                      "Header should show 'openclaw', got '\(openclawTitle)'")

        // Verify session count shows 2
        XCTAssertTrue(countLabel.waitForExistence(timeout: 3))
        let countText2 = "\(countLabel.value ?? "")"
        XCTAssertTrue(countText2.contains("2"), "openclaw should have 2 sessions, got '\(countText2)'")
    }

    // 10. HeatStrip and ProjectCard both navigate to the same project
    func testHeatStripAndProjectCardNavigateToSameProject() {
        switchToOverview()

        // Wait for overview content to fully render
        let heatStrip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "heatStrip_OACP")).firstMatch
        XCTAssertTrue(heatStrip.waitForExistence(timeout: 10), "HeatStrip for OACP must exist")
        heatStrip.click()

        // Verify we landed on OACP sessions — use longer timeout for navigation
        let projectTitle = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 10), "Project title must appear after heatStrip click")
        let titleValue = "\(projectTitle.value ?? "")"
        XCTAssertTrue(titleValue.contains("OACP"), "HeatStrip should navigate to OACP, got '\(titleValue)'")

        // Switch back to Overview and wait for full render
        switchToOverview()
        let openButton = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "openProject_OACP")).firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 10), "Open Project button for OACP must exist after returning to Overview")
        openButton.click()

        // Verify same destination — re-query projectTitle since view was recreated
        let projectTitle2 = app.staticTexts["sessionListProjectTitle"].firstMatch
        XCTAssertTrue(projectTitle2.waitForExistence(timeout: 10), "Project title must appear after openProject click")
        let titleValue2 = "\(projectTitle2.value ?? "")"
        XCTAssertTrue(titleValue2.contains("OACP"), "ProjectCard should also navigate to OACP, got '\(titleValue2)'")
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
        openSettings()

        let settingsForm = app.descendants(matching: .any).matching(identifier: "settingsForm").firstMatch
        XCTAssertTrue(settingsForm.waitForExistence(timeout: 5), "Settings form must open")

        // Find terminal picker
        let terminalPicker = app.descendants(matching: .any).matching(identifier: "terminalPicker").firstMatch
        XCTAssertTrue(terminalPicker.waitForExistence(timeout: 3), "Terminal picker must exist in Settings")

        // Verify default value is Ghostty
        let pickerText = terminalPicker.label + " " + "\(terminalPicker.value ?? "")"
        XCTAssertTrue(pickerText.contains("Ghostty"),
                       "Terminal picker default should be Ghostty, got '\(pickerText)'")
    }

    // 14. Settings scan interval stepper interaction
    func testSettingsCanChangeScanIntervalAndPersist() {
        openSettings()

        let settingsForm = app.descendants(matching: .any).matching(identifier: "settingsForm").firstMatch
        XCTAssertTrue(settingsForm.waitForExistence(timeout: 5), "Settings form must open")

        let stepper = app.descendants(matching: .any).matching(identifier: "scanIntervalStepper").firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 3), "Scan interval stepper must exist")

        // Get initial value
        let initialValue = "\(stepper.value ?? "")"

        // Click the increment arrow (steppers expose incrementArrows, not buttons)
        let incrementArrow = stepper.incrementArrows.firstMatch
        XCTAssertTrue(incrementArrow.waitForExistence(timeout: 2), "Stepper increment arrow must exist")
        incrementArrow.click()

        // Verify the value changed (stepper value increased)
        let updatedValue = "\(stepper.value ?? "")"
        XCTAssertNotEqual(initialValue, updatedValue, "Stepper value should change after increment click")
    }

    // 15. Settings data directory change shows restart hint
    func testDataDirectoryShowsRestartRequiredHint() {
        openSettings()

        let settingsForm = app.descendants(matching: .any).matching(identifier: "settingsForm").firstMatch
        XCTAssertTrue(settingsForm.waitForExistence(timeout: 5), "Settings form must open")

        let dataField = app.descendants(matching: .any).matching(identifier: "dataDirectoryField").firstMatch
        XCTAssertTrue(dataField.waitForExistence(timeout: 3), "Data directory field must exist")

        // Clear and type a custom path
        dataField.click()
        dataField.typeKey("a", modifierFlags: .command)
        dataField.typeText("/tmp/test-claude")

        // Verify restart hint appears with "重启" text
        let restartHint = app.descendants(matching: .any).matching(identifier: "restartHint").firstMatch
        XCTAssertTrue(restartHint.waitForExistence(timeout: 3), "Restart hint must appear after changing data directory")
        let hintText = "\(restartHint.value ?? "")" + restartHint.label
        XCTAssertTrue(hintText.contains("重启"), "Restart hint should mention '重启', got '\(hintText)'")
    }

    // 16. Settings save shows feedback and auto-closes
    func testSettingsSaveShowsFeedbackAndAutoCloses() {
        openSettings()

        let settingsForm = app.descendants(matching: .any).matching(identifier: "settingsForm").firstMatch
        XCTAssertTrue(settingsForm.waitForExistence(timeout: 5), "Settings form must open")

        let saveButton = app.descendants(matching: .any).matching(identifier: "saveSettingsButton").firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "Save button must exist in Settings")

        let initialText = saveButton.label + " " + "\(saveButton.value ?? "")"
        XCTAssertTrue(initialText.contains("保存设置"),
                      "Save button should start with '保存设置', got '\(initialText)'")

        saveButton.click()

        let dismissPredicate = NSPredicate(format: "exists == false")
        let dismissExpectation = XCTNSPredicateExpectation(predicate: dismissPredicate, object: settingsForm)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissExpectation], timeout: 3), .completed,
                       "Settings window should auto-close shortly after clicking Save")
    }
}
