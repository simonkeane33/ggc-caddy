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

    // MARK: - Plays-like wind adjustment

    /// Bearings must use the same convention as the weather API's wind direction
    /// (0 = north, 90 = east) or the two can't be compared to work out whether a
    /// shot is into or down wind.
    func testBearingDegreesUsesCompassConvention() {
        // Due north: same longitude, higher latitude.
        XCTAssertEqual(Geo.bearingDegrees(lat1: 53.0, lng1: -6.0, lat2: 53.1, lng2: -6.0), 0, accuracy: 0.5)
        // Due east: same latitude, higher longitude.
        XCTAssertEqual(Geo.bearingDegrees(lat1: 53.0, lng1: -6.0, lat2: 53.0, lng2: -5.9), 90, accuracy: 0.5)
        // Due south and due west, confirming the 0..<360 normalisation.
        XCTAssertEqual(Geo.bearingDegrees(lat1: 53.0, lng1: -6.0, lat2: 52.9, lng2: -6.0), 180, accuracy: 0.5)
        XCTAssertEqual(Geo.bearingDegrees(lat1: 53.0, lng1: -6.0, lat2: 53.0, lng2: -6.1), 270, accuracy: 0.5)
    }

    /// A shot hit straight at the direction the wind blows from is a headwind and
    /// must play longer; the reciprocal must play shorter.
    func testWindMultiplierRespondsToShotDirection() {
        let intoWind = DistanceAdjustmentEngine.calculateWindMultiplier(
            windSpeedKph: 20, windDirection: 270, shotDirection: 270)
        let downWind = DistanceAdjustmentEngine.calculateWindMultiplier(
            windSpeedKph: 20, windDirection: 270, shotDirection: 90)
        let crossWind = DistanceAdjustmentEngine.calculateWindMultiplier(
            windSpeedKph: 20, windDirection: 270, shotDirection: 0)

        XCTAssertGreaterThan(intoWind, 1.0, "Into the wind should play longer")
        XCTAssertLessThan(downWind, 1.0, "Downwind should play shorter")
        XCTAssertEqual(crossWind, 1.0, accuracy: 0.001, "A pure crosswind should not change carry distance")
    }

    /// Regression test for the wind row reading "0 Yds" no matter the conditions:
    /// the engine only applies a wind multiplier when it is told which way the
    /// shot is being hit, and the caller was passing nil.
    func testPlaysLikeAppliesWindOnlyWhenShotDirectionKnown() {
        let weather = WeatherConditions(
            temperatureC: 20,        // neutral, so temperature contributes nothing
            windSpeedKph: 25,
            windDirectionDegrees: 270,
            humidity: 70,
            pressure: 1013
        )
        // Flat hole so elevation contributes nothing either, isolating wind.
        let flatProfile = HoleElevationProfile(
            holeNumber: 1, teeElevation: 40, greenElevation: 40, fairwayPoints: [])

        let withoutDirection = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
            actualDistanceMeters: 150, elevationProfile: flatProfile,
            weather: weather, shotDirection: nil)
        let withDirection = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
            actualDistanceMeters: 150, elevationProfile: flatProfile,
            weather: weather, shotDirection: 270)

        XCTAssertEqual(withoutDirection.adjustmentFactors.windMultiplier, 1.0, accuracy: 0.001,
                       "Without a shot direction there is no basis for a wind adjustment")
        XCTAssertGreaterThan(withDirection.adjustmentFactors.windMultiplier, 1.0,
                             "A 25 kph headwind should make the shot play longer")
        XCTAssertGreaterThan(withDirection.playsLikeDistance, withoutDirection.playsLikeDistance,
                             "Supplying the shot direction should change the plays-like distance")
    }

    /// The compass label must wrap correctly at both ends of the range — 350°
    /// is north, not an out-of-bounds index.
    func testCompassPointWrapsAtNorth() {
        func compassPoint(_ degrees: Double) -> String {
            let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let normalised = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return points[Int((normalised / 45).rounded()) % 8]
        }

        XCTAssertEqual(compassPoint(0), "N")
        XCTAssertEqual(compassPoint(350), "N", "Just west of north should still round to N, not overflow")
        XCTAssertEqual(compassPoint(360), "N")
        XCTAssertEqual(compassPoint(45), "NE")
        XCTAssertEqual(compassPoint(90), "E")
        XCTAssertEqual(compassPoint(180), "S")
        XCTAssertEqual(compassPoint(270), "W")
        XCTAssertEqual(compassPoint(315), "NW")
        XCTAssertEqual(compassPoint(-90), "W", "Negative bearings should normalise rather than crash")
    }

    /// The elevation row's label and its yardage adjustment come from the same
    /// profile, so anything the engine treats as flat must not be shown as a
    /// slope, and vice versa.
    func testElevationDeadZoneMatchesMultiplier() {
        let flat = HoleElevationProfile(
            holeNumber: 1, teeElevation: 40, greenElevation: 42, fairwayPoints: [])
        XCTAssertEqual(flat.distanceMultiplier, 1.0, accuracy: 0.0001,
                       "A 2m change is inside the dead zone and should not adjust distance")

        let downhill = HoleElevationProfile(
            holeNumber: 1, teeElevation: 60, greenElevation: 40, fairwayPoints: [])
        XCTAssertLessThan(downhill.distanceMultiplier, 1.0, "A 20m drop should play shorter")
    }

}
