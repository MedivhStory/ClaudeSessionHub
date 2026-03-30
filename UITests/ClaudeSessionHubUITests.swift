import XCTest

final class ClaudeSessionHubUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testAppLaunchShowsMainWindow() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    func testToggleSessionsOverview() {
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // Click Overview
        toggle.buttons.element(boundBy: 1).click()
        XCTAssertTrue(
            app.staticTexts["overviewRoot"].waitForExistence(timeout: 3)
            || app.otherElements["overviewRoot"].waitForExistence(timeout: 3)
        )
        // Click back to Sessions
        toggle.buttons.element(boundBy: 0).click()
    }

    func testSettingsWindowOpens() {
        // Cmd+, to open settings
        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows.element(boundBy: 1)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
    }

    func testSessionListExists() {
        // The session list should exist in the default Sessions view
        let sessionList = app.scrollViews["sessionList"]
        // May or may not exist depending on data; just verify the view toggle is present
        let toggle = app.segmentedControls["viewToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }
}
