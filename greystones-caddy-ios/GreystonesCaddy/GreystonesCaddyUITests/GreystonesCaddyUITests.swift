//
//  GreystonesCaddyUITests.swift
//  GreystonesCaddyUITests
//
//  Created by Albie on 20/02/2026.
//

import XCTest

final class GreystonesCaddyUITests: XCTestCase {

    private var locationPermissionMonitor: NSObjectProtocol?

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Automatically grant location permission whenever the system alert appears.
        locationPermissionMonitor = addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            let allowButton = alert.buttons["Allow While Using App"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        if let monitor = locationPermissionMonitor {
            removeUIInterruptionMonitor(monitor)
        }
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
    func testStatsDashboardExcludesInProgressAndAbandoned() throws {
        // We create three rounds across fresh launches. The first launch resets the
        // database; subsequent launches preserve state so rounds accumulate.

        // 1. Completed round with a non-zero score (hole 1 = 6 strokes).
        let completedApp = launchApp(resetDatabase: true)
        XCTAssertTrue(completedApp.buttons["startRoundButton"].waitForExistence(timeout: 5))
        completedApp.buttons["startRoundButton"].tap()
        XCTAssertTrue(completedApp.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(completedApp.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        completedApp.buttons["roundSetupStartButton"].tap()
        XCTAssertTrue(completedApp.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        completedApp.buttons["mainScorecardButton"].tap()
        XCTAssertTrue(completedApp.navigationBars["Scorecard"].waitForExistence(timeout: 5))
        let strokesPlusCompleted = completedApp.buttons["hole1StrokesPlus"]
        XCTAssertTrue(strokesPlusCompleted.waitForExistence(timeout: 5))
        for _ in 0..<6 { strokesPlusCompleted.tap() }
        completedApp.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(completedApp.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        completedApp.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(completedApp.buttons["Complete round"].waitForExistence(timeout: 5))
        completedApp.buttons["Complete round"].tap()
        XCTAssertTrue(completedApp.navigationBars["Complete Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(completedApp.buttons["completeRoundButton"].waitForExistence(timeout: 5))
        completedApp.buttons["completeRoundButton"].tap()
        let missingScoresAlert = completedApp.alerts["Missing scores"]
        XCTAssertTrue(missingScoresAlert.waitForExistence(timeout: 5))
        missingScoresAlert.buttons["Complete anyway"].tap()
        XCTAssertTrue(completedApp.navigationBars["Round"].waitForExistence(timeout: 5))
        completedApp.terminate()

        // 2. Abandoned round.
        let abandonedApp = XCUIApplication()
        abandonedApp.launch()
        XCTAssertTrue(abandonedApp.buttons["startRoundButton"].waitForExistence(timeout: 5))
        abandonedApp.buttons["startRoundButton"].tap()
        XCTAssertTrue(abandonedApp.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(abandonedApp.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        abandonedApp.buttons["roundSetupStartButton"].tap()
        XCTAssertTrue(abandonedApp.buttons["mainToolsMenu"].waitForExistence(timeout: 5))

        abandonedApp.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(abandonedApp.buttons["Abandon round"].waitForExistence(timeout: 5))
        abandonedApp.buttons["Abandon round"].tap()
        let abandonAlert = abandonedApp.alerts["Abandon round?"]
        XCTAssertTrue(abandonAlert.waitForExistence(timeout: 5))
        abandonAlert.buttons["Abandon round"].tap()
        XCTAssertTrue(abandonedApp.buttons["startRoundButton"].waitForExistence(timeout: 5))
        abandonedApp.terminate()

        // 3. In-progress round.
        let inProgressApp = XCUIApplication()
        inProgressApp.launch()
        XCTAssertTrue(inProgressApp.buttons["startRoundButton"].waitForExistence(timeout: 5))
        inProgressApp.buttons["startRoundButton"].tap()
        XCTAssertTrue(inProgressApp.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(inProgressApp.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        inProgressApp.buttons["roundSetupStartButton"].tap()
        XCTAssertTrue(inProgressApp.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        inProgressApp.buttons["mainScorecardButton"].tap()
        XCTAssertTrue(inProgressApp.navigationBars["Scorecard"].waitForExistence(timeout: 5))
        let strokesPlusInProgress = inProgressApp.buttons["hole1StrokesPlus"]
        XCTAssertTrue(strokesPlusInProgress.waitForExistence(timeout: 5))
        for _ in 0..<3 { strokesPlusInProgress.tap() }
        inProgressApp.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(inProgressApp.buttons["mainScorecardButton"].waitForExistence(timeout: 5))
        inProgressApp.terminate()

        // Open Stats Dashboard on a fresh launch.
        let statsApp = XCUIApplication()
        statsApp.launch()
        XCTAssertTrue(statsApp.buttons["statsLink"].waitForExistence(timeout: 5))
        statsApp.buttons["statsLink"].tap()
        XCTAssertTrue(statsApp.navigationBars["Stats Dashboard"].waitForExistence(timeout: 5))

        // Only the completed round should be analyzed.
        let roundsAnalyzed = statsApp.staticTexts["statsRoundsAnalyzed"]
        XCTAssertTrue(roundsAnalyzed.waitForExistence(timeout: 5))
        XCTAssertEqual(roundsAnalyzed.label, "Based on 1 rounds")

        // Avg Score should reflect the single completed round (not "--").
        let avgScore = statsApp.staticTexts["statsAvgScore"]
        XCTAssertTrue(avgScore.waitForExistence(timeout: 5))
        XCTAssertNotEqual(avgScore.label, "--")
    }

    @MainActor
    func testHistoryShowsCompletedRoundDetail() throws {
        let app = launchApp(resetDatabase: true)

        // Start and complete a round with a known score on hole 1.
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
        for _ in 0..<5 { strokesPlus.tap() }
        app.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        app.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(app.buttons["Complete round"].waitForExistence(timeout: 5))
        app.buttons["Complete round"].tap()
        XCTAssertTrue(app.navigationBars["Complete Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["completeRoundButton"].waitForExistence(timeout: 5))
        app.buttons["completeRoundButton"].tap()
        let missingScoresAlert = app.alerts["Missing scores"]
        XCTAssertTrue(missingScoresAlert.waitForExistence(timeout: 5))
        missingScoresAlert.buttons["Complete anyway"].tap()
        XCTAssertTrue(app.navigationBars["Round"].waitForExistence(timeout: 5))
        app.terminate()

        // Relaunch and open History.
        let historyApp = XCUIApplication()
        historyApp.launch()
        XCTAssertTrue(historyApp.buttons["historyLink"].waitForExistence(timeout: 5))
        historyApp.buttons["historyLink"].tap()
        XCTAssertTrue(historyApp.navigationBars["Round History"].waitForExistence(timeout: 5))

        // The completed round row should be present and tappable.
        XCTAssertTrue(historyApp.cells.firstMatch.waitForExistence(timeout: 5))
        historyApp.cells.firstMatch.tap()

        // Round detail should show the recorded total score.
        XCTAssertTrue(historyApp.navigationBars["Round"].waitForExistence(timeout: 5))
        let totalScore = historyApp.staticTexts["roundDetailTotalScore"]
        XCTAssertTrue(totalScore.waitForExistence(timeout: 5))
        XCTAssertEqual(totalScore.label, "5")
    }

    @MainActor
    func testSettingsBagFlow() throws {
        let app = launchApp(resetDatabase: true)

        // Open Settings from Home.
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Tap My Bag.
        XCTAssertTrue(app.buttons["settingsMyBagLink"].waitForExistence(timeout: 5))
        app.buttons["settingsMyBagLink"].tap()
        XCTAssertTrue(app.navigationBars["My Bag"].waitForExistence(timeout: 5))

        // Toggle a club off and back on.
        let driverToggle = app.switches["clubToggle_Driver"]
        XCTAssertTrue(driverToggle.waitForExistence(timeout: 5))
        driverToggle.tap()
        driverToggle.tap()

        // Save the bag.
        XCTAssertTrue(app.buttons["bagSaveButton"].waitForExistence(timeout: 5))
        app.buttons["bagSaveButton"].tap()

        // Navigate back to Settings.
        app.navigationBars["My Bag"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsYardagesFlow() throws {
        let app = launchApp(resetDatabase: true)

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["settingsYardagesLink"].waitForExistence(timeout: 5))
        app.buttons["settingsYardagesLink"].tap()
        XCTAssertTrue(app.navigationBars["Typical yardages"].waitForExistence(timeout: 5))

        // Open the first club baseline edit screen.
        let firstRow = app.buttons["baselineRow_Driver"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        XCTAssertTrue(app.navigationBars["Driver"].waitForExistence(timeout: 5))

        // Enter carry and total yardages.
        let carryField = app.textFields["baselineCarryTextField"]
        let totalField = app.textFields["baselineTotalTextField"]
        XCTAssertTrue(carryField.waitForExistence(timeout: 5))
        XCTAssertTrue(totalField.waitForExistence(timeout: 5))
        carryField.tap()
        carryField.typeText("240")

        // Move to the next field by tapping it directly; the number pad has no Return key.
        totalField.tap()
        totalField.typeText("265")

        // Save and return.
        XCTAssertTrue(app.buttons["baselineSaveButton"].waitForExistence(timeout: 5))
        app.buttons["baselineSaveButton"].tap()
        XCTAssertTrue(app.navigationBars["Typical yardages"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFull18HoleRoundCompletion() throws {
        let app = launchApp(resetDatabase: true)

        // Start a new round.
        XCTAssertTrue(app.buttons["startRoundButton"].waitForExistence(timeout: 5))
        app.buttons["startRoundButton"].tap()
        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        app.buttons["roundSetupStartButton"].tap()
        XCTAssertTrue(app.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        // Open the scorecard and score every hole.
        app.buttons["mainScorecardButton"].tap()
        XCTAssertTrue(app.navigationBars["Scorecard"].waitForExistence(timeout: 5))

        let strokesPerHole = 4  // 1 over par on every hole
        let puttsPerHole = 2
        var expectedTotalStrokes = 0
        var expectedTotalPutts = 0
        for hole in 1...18 {
            let strokesPlus = app.buttons["hole\(hole)StrokesPlus"]
            let puttsPlus = app.buttons["hole\(hole)PuttsPlus"]
            XCTAssertTrue(strokesPlus.waitForExistence(timeout: 5), "Missing strokes plus for hole \(hole)")
            XCTAssertTrue(puttsPlus.waitForExistence(timeout: 5), "Missing putts plus for hole \(hole)")
            for _ in 0..<strokesPerHole { strokesPlus.tap() }
            for _ in 0..<puttsPerHole { puttsPlus.tap() }
            expectedTotalStrokes += strokesPerHole
            expectedTotalPutts += puttsPerHole
        }

        // Scroll the totals section into view; the last hole may push it off-screen.
        app.swipeUp()

        // Verify the scorecard totals before leaving.
        let totalStrokes = app.staticTexts["scorecardTotalStrokes"]
        let totalPutts = app.staticTexts["scorecardTotalPutts"]
        let totalToPar = app.staticTexts["scorecardTotalToPar"]
        XCTAssertTrue(totalStrokes.waitForExistence(timeout: 5))
        XCTAssertTrue(totalPutts.waitForExistence(timeout: 5))
        XCTAssertTrue(totalToPar.waitForExistence(timeout: 5))

        // The totals list may need a moment to update after the last hole score is persisted.
        let predicate = NSPredicate(format: "label == %@", "\(expectedTotalStrokes)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: totalStrokes)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)

        XCTAssertEqual(totalPutts.label, "\(expectedTotalPutts)")
        XCTAssertEqual(totalToPar.label, "+3")

        app.navigationBars["Scorecard"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        // Complete the round; no missing-scores alert should appear.
        XCTAssertTrue(app.buttons["mainToolsMenu"].waitForExistence(timeout: 5))
        app.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(app.buttons["Complete round"].waitForExistence(timeout: 5))
        app.buttons["Complete round"].tap()
        XCTAssertTrue(app.navigationBars["Complete Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["completeRoundButton"].waitForExistence(timeout: 5))
        app.buttons["completeRoundButton"].tap()

        // With all holes scored, the missing-scores alert should NOT appear.
        XCTAssertFalse(app.alerts["Missing scores"].waitForExistence(timeout: 3))

        // Round detail appears after completion.
        XCTAssertTrue(app.navigationBars["Round"].waitForExistence(timeout: 5))
        let roundDetailTotalScore = app.staticTexts["roundDetailTotalScore"]
        let roundDetailTotalPutts = app.staticTexts["roundDetailTotalPutts"]
        XCTAssertTrue(roundDetailTotalScore.waitForExistence(timeout: 5))
        XCTAssertTrue(roundDetailTotalPutts.waitForExistence(timeout: 5))
        XCTAssertEqual(roundDetailTotalScore.label, "\(expectedTotalStrokes)")
        XCTAssertEqual(roundDetailTotalPutts.label, "\(expectedTotalPutts)")

        app.terminate()

        // Relaunch and verify the completed round is counted in stats.
        let statsApp = XCUIApplication()
        statsApp.launch()
        XCTAssertTrue(statsApp.buttons["statsLink"].waitForExistence(timeout: 5))
        statsApp.buttons["statsLink"].tap()
        XCTAssertTrue(statsApp.navigationBars["Stats Dashboard"].waitForExistence(timeout: 5))

        let roundsAnalyzed = statsApp.staticTexts["statsRoundsAnalyzed"]
        let avgScore = statsApp.staticTexts["statsAvgScore"]
        XCTAssertTrue(roundsAnalyzed.waitForExistence(timeout: 5))
        XCTAssertTrue(avgScore.waitForExistence(timeout: 5))
        XCTAssertEqual(roundsAnalyzed.label, "Based on 1 rounds")
        XCTAssertEqual(avgScore.label, "3.0")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch the application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testAerialViewTargetDraggable() throws {
        let app = launchApp(resetDatabase: true)

        // Start a round.
        XCTAssertTrue(app.buttons["startRoundButton"].waitForExistence(timeout: 5))
        app.buttons["startRoundButton"].tap()
        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roundSetupStartButton"].waitForExistence(timeout: 5))
        app.buttons["roundSetupStartButton"].tap()
        XCTAssertTrue(app.buttons["mainScorecardButton"].waitForExistence(timeout: 5))

        // Open Aerial View from the tools menu.
        XCTAssertTrue(app.buttons["mainToolsMenu"].waitForExistence(timeout: 5))
        app.buttons["mainToolsMenu"].tap()
        XCTAssertTrue(app.buttons["Aerial View"].waitForExistence(timeout: 5))
        app.buttons["Aerial View"].tap()

        // Trigger the location-permission interruption monitor if the system
        // alert is present. Tapping the navigation title is harmless once the
        // alert is dismissed.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()

        // Wait for the hole view, crosshair, and distance read-out to render.
        XCTAssertTrue(app.navigationBars["Hole view"].waitForExistence(timeout: 5))
        let crosshair = app.otherElements["aerialTargetCrosshair"]
        XCTAssertTrue(crosshair.waitForExistence(timeout: 5), "Target crosshair should appear")
        XCTAssertTrue(crosshair.isHittable, "Target crosshair should be on-screen and hittable")

        let currentShotLabel = app.staticTexts["currentShotDistance"]
        XCTAssertTrue(currentShotLabel.waitForExistence(timeout: 5), "Current-shot distance label should appear")
        let beforeValue = currentShotLabel.label
        XCTAssertFalse(beforeValue.isEmpty, "Current-shot distance should be loaded")

        let beforeAttachment = XCTAttachment(screenshot: app.screenshot())
        beforeAttachment.name = "Aerial View Before Drag"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        // The tee marker anchors the map. If the map pans while the target is
        // dragged, this moves — which is the failure the old interaction-mode
        // gating existed to prevent.
        let teeMarker = app.descendants(matching: .any).matching(identifier: "Tee").firstMatch
        XCTAssertTrue(teeMarker.waitForExistence(timeout: 5), "Tee marker should be on screen")
        let teeBefore = teeMarker.frame

        // Drag the crosshair upward to move the target toward the tee.
        let beforeFrame = crosshair.frame
        let crosshairCenter = crosshair.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let dragEndPoint = dragEnd.screenPoint
        crosshairCenter.press(forDuration: 0.2, thenDragTo: dragEnd)

        // After the drag the current-shot distance should have changed.
        sleep(1)
        let afterValue = currentShotLabel.label

        let afterAttachment = XCTAttachment(screenshot: app.screenshot())
        afterAttachment.name = "Aerial View After Drag"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)

        XCTAssertNotEqual(afterValue, beforeValue, "Dragging the target should change the current-shot distance. Before: \(beforeValue), After: \(afterValue)")

        // The crosshair must actually follow the finger: after release it should be
        // centred on the release point, not offset by a coordinate-space mismatch
        // between the drag surface and the rendered crosshair.
        let afterFrame = crosshair.frame
        let afterCenter = CGPoint(x: afterFrame.midX, y: afterFrame.midY)
        XCTAssertNotEqual(beforeFrame.midY, afterFrame.midY, accuracy: 0.5,
                          "Crosshair should have moved on screen")
        XCTAssertEqual(afterCenter.x, dragEndPoint.x, accuracy: 12,
                       "Crosshair should land horizontally on the release point. Landed \(afterCenter), released \(dragEndPoint)")
        XCTAssertEqual(afterCenter.y, dragEndPoint.y, accuracy: 12,
                       "Crosshair should land vertically on the release point. Landed \(afterCenter), released \(dragEndPoint)")

        // The drag must move the target, not the map.
        let teeAfter = teeMarker.frame
        XCTAssertEqual(teeAfter.midX, teeBefore.midX, accuracy: 2, "Map panned horizontally during the target drag")
        XCTAssertEqual(teeAfter.midY, teeBefore.midY, accuracy: 2, "Map panned vertically during the target drag")
    }
}
