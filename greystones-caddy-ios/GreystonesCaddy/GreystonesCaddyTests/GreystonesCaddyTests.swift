//
//  GreystonesCaddyTests.swift
//  GreystonesCaddyTests
//
//  Created by Albie on 20/02/2026.
//

import XCTest
@testable import GreystonesCaddy
import GreystonesCaddyCore

final class GreystonesCaddyTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    /// Completing an 18-hole round should write a round_stats_cache entry that
    /// fetchAggregatedStats can find on a fresh query.
    func testFullRoundStatsAreAggregated() throws {
        let db = GCDB.shared
        let bundle = try CourseLoader.loadGreystonesCourse()

        let roundId = try db.createRound(tee: .blue, distanceUnit: .yards, course: "Greystones")
        for hole in bundle.holes {
            try db.upsertHoleScore(roundId: roundId, holeNumber: hole.number, gross: 4, putts: 2)
        }

        _ = try db.computeAndStoreRoundStats(roundId: roundId, course: bundle)
        try db.completeRound(roundId: roundId)

        let stats = try db.fetchAggregatedStats(limit: 20)
        XCTAssertEqual(stats.roundsAnalyzed, 1, "fetchAggregatedStats should find the completed round")
        XCTAssertEqual(stats.avgScoreToPar, 3.0, "Score to par should be +3 for 72 strokes on par 69")
    }

}
