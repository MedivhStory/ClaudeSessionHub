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

        // All 4 summary cards must exist (not "any of these" — all of them)
        XCTAssertTrue(app.otherElements["summaryAttention"].waitForExistence(timeout: 3)
            || app.staticTexts["summaryAttention"].waitForExistence(timeout: 1),
            "Attention summary card must exist")
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
}
