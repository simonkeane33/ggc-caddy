import Foundation
import GRDB

// MARK: - Database Extension for Stats

public extension GCDB {
  
  // MARK: Schema
  
  /// Call this during database setup to create the stats tables.
  func createStatsTables() throws {
    try dbQueue.write { db in
      // Table to store computed hole stats
      try db.create(table: "hole_stats", ifNotExists: true) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("holeEventId", .integer).notNull().unique()
        t.column("roundId", .integer).notNull().indexed()
        t.column("holeNumber", .integer).notNull()
        t.column("par", .integer).notNull()
        t.column("strokes", .integer).notNull()
        t.column("putts", .integer).notNull()
        t.column("penalties", .integer).notNull()
        t.column("gir", .boolean)
        t.column("fairwayHit", .boolean)
        t.column("scramble", .boolean)
        t.column("computedAt", .datetime).notNull()
        
        t.foreignKey(["holeEventId"], references: "hole_scores", onDelete: .cascade)
        t.foreignKey(["roundId"], references: "rounds", onDelete: .cascade)
      }
      
      // Table to store cached round summaries
      try db.create(table: "round_stats_cache", ifNotExists: true) { t in
        t.column("roundId", .integer).primaryKey()
        t.column("totalStrokes", .integer).notNull()
        t.column("totalPutts", .integer).notNull()
        t.column("totalPenalties", .integer).notNull()
        t.column("scoreToPar", .integer).notNull()
        t.column("girPercentage", .double)
        t.column("fairwayPercentage", .double)
        t.column("scramblePercentage", .double)
        t.column("puttsPerRound", .double).notNull()
        t.column("girCount", .integer).notNull()
        t.column("girOpportunities", .integer).notNull()
        t.column("fairwayCount", .integer).notNull()
        t.column("fairwayOpportunities", .integer).notNull()
        t.column("scrambleCount", .integer).notNull()
        t.column("scrambleOpportunities", .integer).notNull()
        t.column("computedAt", .datetime).notNull()
        
        t.foreignKey(["roundId"], references: "rounds", onDelete: .cascade)
      }
    }
  }
  
  // MARK: Compute and Store Stats
  
  /// Compute and store stats for a specific hole.
  /// Call this after events are recorded for a hole.
  func computeAndStoreHoleStats(
    roundId: Int64,
    holeNumber: Int,
    par: Int
  ) throws -> HoleStats {
    let events = try fetchHoleEvents(roundId: roundId, holeNumber: holeNumber)
    let components = StatsCalculator.calculateHoleStats(events: events, par: par)
    
    // Get or create hole_event_id from hole_scores table
    let holeEventId = try getOrCreateHoleScoreId(roundId: roundId, holeNumber: holeNumber)
    
    let stats = HoleStats(
      holeEventId: holeEventId,
      roundId: roundId,
      holeNumber: holeNumber,
      par: par,
      strokes: components.strokes,
      putts: components.putts,
      penalties: components.penalties,
      gir: components.gir,
      fairwayHit: components.fairwayHit,
      scramble: components.scramble
    )
    
    try storeHoleStats(stats)
    return stats
  }
  
  /// Compute and store stats for an entire round.
  /// Call this when a round is completed or when viewing round stats.
  func computeAndStoreRoundStats(
    roundId: Int64,
    course: CourseBundle
  ) throws -> RoundStatsSummary {
    // Get all holes for this round from hole_scores
    let holeNumbers = try fetchHoleNumbersWithScores(roundId: roundId)

    // Resolve the tee used for this round so par/SI are correct.
    let tee = (try? GCDB.shared.fetchRound(roundId: roundId))?.tee ?? .blue

    var holeStats: [HoleStats] = []
    for holeNum in holeNumbers {
      guard let hole = course.holes.first(where: { $0.number == holeNum }) else { continue }
      let par = hole.par[tee]
      let stats = try computeAndStoreHoleStats(roundId: roundId, holeNumber: holeNum, par: par)
      holeStats.append(stats)
    }

    let summary = StatsCalculator.calculateRoundSummary(roundId: roundId, holeStats: holeStats)
    try storeRoundStatsCache(summary)
    return summary
  }
  
  /// Recalculate all stats for a round (useful after editing events).
  func recalculateRoundStats(
    roundId: Int64,
    course: CourseBundle
  ) throws -> RoundStatsSummary {
    // Delete existing stats
    try deleteRoundStats(roundId: roundId)
    // Recompute
    return try computeAndStoreRoundStats(roundId: roundId, course: course)
  }
  
  // MARK: Fetch Stats
  
  /// Fetch cached round stats (returns nil if not computed yet).
  func fetchRoundStats(roundId: Int64) throws -> RoundStatsSummary? {
    try dbQueue.read { db in
      let row = try Row.fetchOne(
        db,
        sql: """
        SELECT roundId, totalStrokes, totalPutts, totalPenalties, scoreToPar,
               girPercentage, fairwayPercentage, scramblePercentage, puttsPerRound,
               girCount, girOpportunities, fairwayCount, fairwayOpportunities,
               scrambleCount, scrambleOpportunities
        FROM round_stats_cache WHERE roundId = ?
        """,
        arguments: [roundId]
      )
      
      guard let row else { return nil }
      return RoundStatsSummary(
        roundId: row["roundId"],
        totalStrokes: row["totalStrokes"],
        totalPutts: row["totalPutts"],
        totalPenalties: row["totalPenalties"],
        scoreToPar: row["scoreToPar"],
        girPercentage: row["girPercentage"],
        fairwayPercentage: row["fairwayPercentage"],
        scramblePercentage: row["scramblePercentage"],
        puttsPerRound: row["puttsPerRound"],
        girCount: row["girCount"],
        girOpportunities: row["girOpportunities"],
        fairwayCount: row["fairwayCount"],
        fairwayOpportunities: row["fairwayOpportunities"],
        scrambleCount: row["scrambleCount"],
        scrambleOpportunities: row["scrambleOpportunities"]
      )
    }
  }
  
  /// Fetch stats for all holes in a round.
  func fetchHoleStatsForRound(roundId: Int64) throws -> [HoleStats] {
    try dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT holeEventId, roundId, holeNumber, par, strokes, putts, penalties,
               gir, fairwayHit, scramble
        FROM hole_stats WHERE roundId = ? ORDER BY holeNumber
        """,
        arguments: [roundId]
      )
      
      return rows.map { row in
        HoleStats(
          holeEventId: row["holeEventId"],
          roundId: row["roundId"],
          holeNumber: row["holeNumber"],
          par: row["par"],
          strokes: row["strokes"],
          putts: row["putts"],
          penalties: row["penalties"],
          gir: row["gir"],
          fairwayHit: row["fairwayHit"],
          scramble: row["scramble"]
        )
      }
    }
  }
  
  /// Fetch aggregated stats across completed rounds only (v1 stats eligibility).
  func fetchAggregatedStats(limit: Int = 20) throws -> AggregatedStats {
    try dbQueue.read { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      let hasState = cols.contains("completionState")
      let joinClause = hasState
        ? "INNER JOIN rounds ON round_stats_cache.roundId = rounds.id AND rounds.completionState = 'completed'"
        : "INNER JOIN rounds ON round_stats_cache.roundId = rounds.id AND rounds.endedAt IS NOT NULL"

      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT round_stats_cache.girPercentage, round_stats_cache.fairwayPercentage,
               round_stats_cache.scramblePercentage, round_stats_cache.puttsPerRound,
               round_stats_cache.scoreToPar, round_stats_cache.totalStrokes
        FROM round_stats_cache
        \(joinClause)
        ORDER BY round_stats_cache.computedAt DESC
        LIMIT ?
        """,
        arguments: [limit]
      )

      let girs = rows.compactMap { $0["girPercentage"] as Double? }
      let fairways = rows.compactMap { $0["fairwayPercentage"] as Double? }
      let scrambles = rows.compactMap { $0["scramblePercentage"] as Double? }
      let putts = rows.map { $0["puttsPerRound"] as Double }
      let scores = rows.map { $0["scoreToPar"] as Int }

      return AggregatedStats(
        roundsAnalyzed: rows.count,
        avgGIRPercentage: girs.isEmpty ? nil : girs.reduce(0, +) / Double(girs.count),
        avgFairwayPercentage: fairways.isEmpty ? nil : fairways.reduce(0, +) / Double(fairways.count),
        avgScramblePercentage: scrambles.isEmpty ? nil : scrambles.reduce(0, +) / Double(scrambles.count),
        avgPuttsPerRound: putts.isEmpty ? nil : putts.reduce(0, +) / Double(putts.count),
        avgScoreToPar: scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count),
        bestScoreToPar: scores.min()
      )
    }
  }
  
  // MARK: Private Helpers
  
  private func getOrCreateHoleScoreId(roundId: Int64, holeNumber: Int) throws -> Int64 {
    try dbQueue.write { db in
      // Try to get existing
      if let id = try Int64.fetchOne(
        db,
        sql: "SELECT id FROM hole_scores WHERE roundId = ? AND holeNumber = ?",
        arguments: [roundId, holeNumber]
      ) {
        return id
      }
      
      // Create new
      try db.execute(
        sql: "INSERT INTO hole_scores (roundId, holeNumber, strokes, putts) VALUES (?, ?, 0, 0)",
        arguments: [roundId, holeNumber]
      )
      return db.lastInsertedRowID
    }
  }
  
  private func fetchHoleNumbersWithScores(roundId: Int64) throws -> [Int] {
    try dbQueue.read { db in
      try Int.fetchAll(
        db,
        sql: """
        SELECT DISTINCT holeNumber FROM shots 
        WHERE roundId = ? 
        ORDER BY holeNumber
        """,
        arguments: [roundId]
      )
    }
  }
  
  private func storeHoleStats(_ stats: HoleStats) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
        INSERT INTO hole_stats (
          holeEventId, roundId, holeNumber, par, strokes, putts, penalties,
          gir, fairwayHit, scramble, computedAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(holeEventId) DO UPDATE SET
          strokes = excluded.strokes,
          putts = excluded.putts,
          penalties = excluded.penalties,
          gir = excluded.gir,
          fairwayHit = excluded.fairwayHit,
          scramble = excluded.scramble,
          computedAt = excluded.computedAt
        """,
        arguments: [
          stats.holeEventId, stats.roundId, stats.holeNumber, stats.par,
          stats.strokes, stats.putts, stats.penalties,
          stats.gir, stats.fairwayHit, stats.scramble,
          Date()
        ]
      )
    }
  }
  
  private func storeRoundStatsCache(_ summary: RoundStatsSummary) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
        INSERT INTO round_stats_cache (
          roundId, totalStrokes, totalPutts, totalPenalties, scoreToPar,
          girPercentage, fairwayPercentage, scramblePercentage, puttsPerRound,
          girCount, girOpportunities, fairwayCount, fairwayOpportunities,
          scrambleCount, scrambleOpportunities, computedAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(roundId) DO UPDATE SET
          totalStrokes = excluded.totalStrokes,
          totalPutts = excluded.totalPutts,
          totalPenalties = excluded.totalPenalties,
          scoreToPar = excluded.scoreToPar,
          girPercentage = excluded.girPercentage,
          fairwayPercentage = excluded.fairwayPercentage,
          scramblePercentage = excluded.scramblePercentage,
          puttsPerRound = excluded.puttsPerRound,
          girCount = excluded.girCount,
          girOpportunities = excluded.girOpportunities,
          fairwayCount = excluded.fairwayCount,
          fairwayOpportunities = excluded.fairwayOpportunities,
          scrambleCount = excluded.scrambleCount,
          scrambleOpportunities = excluded.scrambleOpportunities,
          computedAt = excluded.computedAt
        """,
        arguments: [
          summary.roundId, summary.totalStrokes, summary.totalPutts,
          summary.totalPenalties, summary.scoreToPar,
          summary.girPercentage, summary.fairwayPercentage,
          summary.scramblePercentage, summary.puttsPerRound,
          summary.girCount, summary.girOpportunities,
          summary.fairwayCount, summary.fairwayOpportunities,
          summary.scrambleCount, summary.scrambleOpportunities,
          Date()
        ]
      )
    }
  }
  
  private func deleteRoundStats(roundId: Int64) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM hole_stats WHERE roundId = ?",
        arguments: [roundId]
      )
      try db.execute(
        sql: "DELETE FROM round_stats_cache WHERE roundId = ?",
        arguments: [roundId]
      )
    }
  }
}

// MARK: - Aggregated Stats

public struct AggregatedStats: Sendable {
  public var roundsAnalyzed: Int
  public var avgGIRPercentage: Double?
  public var avgFairwayPercentage: Double?
  public var avgScramblePercentage: Double?
  public var avgPuttsPerRound: Double?
  public var avgScoreToPar: Double?
  public var bestScoreToPar: Int?
}
