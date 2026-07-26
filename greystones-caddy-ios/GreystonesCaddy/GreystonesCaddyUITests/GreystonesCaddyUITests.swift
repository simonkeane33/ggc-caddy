//
//  GreystonesCaddyUITests.swift
//  GreystonesCaddyUITests
//
//  Created by Albie on 20/02/2026.
//

import XCTest

final class GreystonesCaddyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func launchApp(resetDatabase: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if resetDatabase {
            app.launchArguments = ["-UITestResetDatabase"]
        }
        app.launch()
        return app
    }

    @MainActor
    func testHomeHistoryAndStatsLinks() throws {
        let app = launchApp(resetDatabase: true)

        // History link navigates to Round History.
        XCTAssertTrue(app.buttons["historyLink"].waitForExistence(timeout: 5))
        app.buttons["historyLink"].tap()

        XCTAssertTrue(app.navigationBars["Round History"].waitForExistence(timeout: 5))

        // Go back and verify Stats link navigates to Stats Dashboard.
        app.navigationBars["Round History"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["statsLink"].waitForExistence(timeout: 5))
        app.buttons["statsLink"].tap()

        XCTAssertTrue(app.navigationBars["Stats Dashboard"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartRoundAndCompleteWithMissingHolesOverride() throws {
        let app = launchApp(resetDatabase: true)

        // Start a new round from Home.
        XCTAssertTrue(app.buttons["startRoundButton"].waitForExistence(timeout: 5))
        app.buttons["startRoundButton"].tap()

        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        app.buttons["roundSetupStartButton"].tap()

        // Main game view appears.
        XCTAssertTrue(app.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        // Open scorecard and enter strokes / putts for hole 1.
        app.buttons["mainScorecardButton"].tap()
        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 5))

        let strokesPlus = app.buttons["hole1StrokesPlus"]
        let puttsPlus = app.buttons["hole1PuttsPlus"]
        XCTAssertTrue(strokesPlus.waitForExistence(timeout: 5))
        XCTAssertTrue(puttsPlus.waitForExistence(timeout: 5))

        for _ in 0..<4 { strokesPlus.tap() }
        for _ in 0..<2 { puttsPlus.tap() }

        // Return to main game view and trigger completion via the tools menu.
        app.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["mainToolsMenu"].waitForExistence(timeout: 5))

        app.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(app.buttons["Complete round"].waitForExistence(timeout: 5))
        app.buttons["Complete round"].tap()

        // RoundStatsView completion flow.
        XCTAssertTrue(app.navigationBars["Complete Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["completeRoundButton"].waitForExistence(timeout: 5))
        app.buttons["completeRoundButton"].tap()

        // Missing-score override alert.
        let missingScoresAlert = app.alerts["Missing scores"]
        XCTAssertTrue(missingScoresAlert.waitForExistence(timeout: 5))
        missingScoresAlert.buttons["Complete anyway"].tap()

        // Round detail shows the completed round total.
        XCTAssertTrue(app.navigationBars["Round"].waitForExistence(timeout: 5))
        let totalScore = app.staticTexts["roundDetailTotalScore"]
        XCTAssertTrue(totalScore.waitForExistence(timeout: 5))
        XCTAssertEqual(totalScore.label, "4")
    }

    @MainActor
    func testAbandonRound() throws {
        let app = launchApp(resetDatabase: true)

        // Start a new round from Home.
        XCTAssertTrue(app.buttons["startRoundButton"].waitForExistence(timeout: 5))
        app.buttons["startRoundButton"].tap()

        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        app.buttons["roundSetupStartButton"].tap()

        // Main game view appears.
        XCTAssertTrue(app.buttons["mainToolsMenu"].waitForExistence(timeout: 5))

        // Open tools menu and choose Abandon round.
        app.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(app.buttons["Abandon round"].waitForExistence(timeout: 5))
        app.buttons["Abandon round"].tap()

        // Confirm abandon alert.
        let abandonAlert = app.alerts["Abandon round?"]
        XCTAssertTrue(abandonAlert.waitForExistence(timeout: 5))
        abandonAlert.buttons["Abandon round"].tap()

        // Home reappears.
        XCTAssertTrue(app.buttons["startRoundButton"].waitForExistence(timeout: 5))

        // Round history shows the abandoned round.
        XCTAssertTrue(app.buttons["historyLink"].waitForExistence(timeout: 5))
        app.buttons["historyLink"].tap()

        XCTAssertTrue(app.navigationBars["Round History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Abandoned"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testResumeInProgressRound() throws {
        // Start a round with a clean database.
        let setupApp = launchApp(resetDatabase: true)

        XCTAssertTrue(setupApp.buttons["startRoundButton"].waitForExistence(timeout: 5))
        setupApp.buttons["startRoundButton"].tap()

        XCTAssertTrue(setupApp.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(setupApp.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        setupApp.buttons["roundSetupStartButton"].tap()

        XCTAssertTrue(setupApp.buttons["mainScorecardButton"].waitForExistence(timeout: 5))
        setupApp.buttons["mainScorecardButton"].tap()

        XCTAssertTrue(setupApp.navigationBars["Scorecard"].waitForExistence(timeout: 5))
        let strokesPlus = setupApp.buttons["hole1StrokesPlus"]
        XCTAssertTrue(strokesPlus.waitForExistence(timeout: 5))
        strokesPlus.tap()

        setupApp.terminate()

        // Relaunch without the database-reset argument so the in-progress round survives.
        let resumedApp = XCUIApplication()
        resumedApp.launch()

        // Home should now show Resume round instead of Start round.
        XCTAssertTrue(resumedApp.buttons["resumeRoundButton"].waitForExistence(timeout: 5))
        resumedApp.buttons["resumeRoundButton"].tap()

        // Back in the main game view for the active round.
        XCTAssertTrue(resumedApp.buttons["mainScorecardButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditAfterCompletionRefreshesTotals() throws {
        let app = launchApp(resetDatabase: true)

        // Start and complete a round with one hole scored.
        XCTAssertTrue(app.buttons["startRoundButton"].waitForExistence(timeout: 5))
        app.buttons["startRoundButton"].tap()

        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        app.buttons["roundSetupStartButton"].tap()

        XCTAssertTrue(app.buttons["mainScorecardButton"].waitForExistence(timeout: 5))
        app.buttons["mainScorecardButton"].tap()

        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 5))
        let strokesPlus = app.buttons["hole1StrokesPlus"]
        XCTAssertTrue(strokesPlus.waitForExistence(timeout: 5))
        for _ in 0..<4 { strokesPlus.tap() }

        app.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["mainToolsMenu"].waitForExistence(timeout: 5))

        app.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(app.buttons["Complete round"].waitForExistence(timeout: 5))
        app.buttons["Complete round"].tap()

        XCTAssertTrue(app.navigationBars["Complete Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["completeRoundButton"].waitForExistence(timeout: 5))
        app.buttons["completeRoundButton"].tap()

        // Missing-score override alert (only hole 1 is scored).
        let missingScoresAlert = app.alerts["Missing scores"]
        XCTAssertTrue(missingScoresAlert.waitForExistence(timeout: 5))
        missingScoresAlert.buttons["Complete anyway"].tap()

        // Round detail shows initial total.
        XCTAssertTrue(app.navigationBars["Round"].waitForExistence(timeout: 5))
        let totalScore = app.staticTexts["roundDetailTotalScore"]
        XCTAssertTrue(totalScore.waitForExistence(timeout: 5))
        XCTAssertEqual(totalScore.label, "4")

        // Open scorecard from detail and change hole 1 score from 4 to 5.
        XCTAssertTrue(app.buttons["Scorecard"].waitForExistence(timeout: 5))
        app.buttons["Scorecard"].tap()
        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 5))

        let strokesPlusAgain = app.buttons["hole1StrokesPlus"]
        XCTAssertTrue(strokesPlusAgain.waitForExistence(timeout: 5))
        strokesPlusAgain.tap()

        // Updated total should reflect on return.
        app.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()

        let updatedTotalScore = app.staticTexts["roundDetailTotalScore"]
        XCTAssertTrue(updatedTotalScore.waitForExistence(timeout: 5))
        XCTAssertEqual(updatedTotalScore.label, "5")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch the application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
