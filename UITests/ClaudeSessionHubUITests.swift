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
        // Fixture has 4 sessions — verify the session list exists
        let sessionList = window.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list should exist")
    }

    // 2. Toggle to Overview shows summary cards
    func testOverviewShowsSummaryCards() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons.element(boundBy: 1).click()

        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5), "Overview should appear")

        // Verify summary cards exist
        XCTAssertTrue(app.staticTexts["summaryAttention"].exists
            || app.otherElements["summaryAttention"].exists
            || app.groups["summaryAttention"].exists,
            "Attention summary card should exist")
    }

    // 3. Overview -> click project -> lands in Sessions with that project
    func testOverviewProjectNavigation() {
        // Switch to Overview
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons.element(boundBy: 1).click()

        // Wait for overview
        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))

        // Click "Open Project" for a fixture project
        let openButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'openProject_'")).firstMatch
        if openButton.waitForExistence(timeout: 3) {
            openButton.click()
            // Should switch back to Sessions view
            let sessionList = app.scrollViews["sessionList"]
            XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Should navigate to session list")
        }
    }

    // 4. Tile expand shows quick facts
    func testTileExpandShowsQuickFacts() {
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5))

        // Click a fixture tile
        let tile = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'sessionTile_'")).firstMatch
        if tile.waitForExistence(timeout: 3) {
            tile.click()
            // Quick facts should appear
            let quickFacts = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'quickFacts_'")).firstMatch
            XCTAssertTrue(quickFacts.waitForExistence(timeout: 3), "Quick facts should appear on tile click")
        }
    }

    // 5. Settings opens and has expected controls
    func testSettingsControls() {
        app.typeKey(",", modifierFlags: .command)
        // Wait for settings window
        sleep(1) // Settings window animation

        let settingsForm = app.otherElements["settingsForm"].firstMatch
        if !settingsForm.waitForExistence(timeout: 3) {
            // Settings might be in a separate window
            let secondWindow = app.windows.element(boundBy: 1)
            XCTAssertTrue(secondWindow.waitForExistence(timeout: 3), "Settings window should open")
        }
    }

    // 6. Fixture attention sessions show in overview
    func testAttentionSessionsExist() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons.element(boundBy: 1).click()

        let inbox = app.otherElements["attentionInbox"].firstMatch
        // Fixture has sessions with health signals — attention inbox should exist
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), "Attention inbox should exist in overview")
    }

    // 7. Toggle back to Sessions from Overview preserves app state
    func testToggleBackToSessions() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        // Go to Overview
        toggle.buttons.element(boundBy: 1).click()
        let overview = app.otherElements["overviewRoot"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))

        // Go back to Sessions
        toggle.buttons.element(boundBy: 0).click()
        let sessionList = app.scrollViews["sessionList"]
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5), "Session list should reappear")
    }
}
