import Foundation
import GRDB

public enum RoundCompletionState: String, Codable, Sendable, Hashable {
  case inProgress = "in_progress"
  case completed = "completed"
  case abandoned = "abandoned"
}

public struct RoundSummary: Sendable, Identifiable, Hashable {
  public var id: Int64
  public var startedAt: Date
  public var endedAt: Date?
  public var tee: TeeID
  public var distanceUnit: DistanceUnit
  public var completionState: RoundCompletionState
  public var course: String?

  public var gameType: GameType
  public var handicapIndex: Double?
  public var allowancePct: Double?
  public var courseHandicap: Int?
  public var playingHandicap: Int?
}

public extension GCDB {
  func fetchRound(roundId: Int64) throws -> RoundSummary? {
    try dbQueue.read { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      let hasState = cols.contains("completionState")
      let hasCourse = cols.contains("course")
      let sql = """
        SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap
        \(hasState ? ", completionState" : "")
        \(hasCourse ? ", course" : "")
        FROM rounds WHERE id = ? LIMIT 1
        """
      let row = try Row.fetchOne(db, sql: sql, arguments: [roundId])
      guard let row else { return nil }
      return try parseRoundSummary(row: row, db: db, hasState: hasState, hasCourse: hasCourse)
    }
  }

  func fetchActiveRound() throws -> RoundSummary? {
    try dbQueue.read { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      let hasState = cols.contains("completionState")
      let hasCourse = cols.contains("course")
      let whereClause = hasState ? "completionState = 'in_progress'" : "endedAt IS NULL"
      let sql = """
        SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap
        \(hasState ? ", completionState" : "")
        \(hasCourse ? ", course" : "")
        FROM rounds WHERE \(whereClause) ORDER BY startedAt DESC LIMIT 1
        """
      let row = try Row.fetchOne(db, sql: sql)
      guard let row else { return nil }
      let summary = try parseRoundSummary(row: row, db: db, hasState: hasState, hasCourse: hasCourse)
      // Never return abandoned rounds, even if query matched (legacy/fallback edge case).
      guard summary?.completionState != .abandoned else { return nil }
      return summary
    }
  }

  /// Rounds with completionState == completed only. Use for stats eligibility.
  func listCompletedRounds(limit: Int = 30) throws -> [RoundSummary] {
    try dbQueue.read { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      let hasState = cols.contains("completionState")
      let hasCourse = cols.contains("course")
      let whereClause = hasState ? "completionState = 'completed'" : "endedAt IS NOT NULL"
      let sql = """
        SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap
        \(hasState ? ", completionState" : "")
        \(hasCourse ? ", course" : "")
        FROM rounds WHERE \(whereClause) ORDER BY startedAt DESC LIMIT ?
        """
      let rows = try Row.fetchAll(db, sql: sql, arguments: [limit])
      return rows.compactMap { try? parseRoundSummary(row: $0, db: db, hasState: hasState, hasCourse: hasCourse) }
    }
  }

  func listRounds(limit: Int = 30) throws -> [RoundSummary] {
    try dbQueue.read { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      let hasState = cols.contains("completionState")
      let hasCourse = cols.contains("course")
      let sql = """
        SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap
        \(hasState ? ", completionState" : "")
        \(hasCourse ? ", course" : "")
        FROM rounds ORDER BY startedAt DESC LIMIT ?
        """
      let rows = try Row.fetchAll(db, sql: sql, arguments: [limit])
      return rows.compactMap { try? parseRoundSummary(row: $0, db: db, hasState: hasState, hasCourse: hasCourse) }
    }
  }

  private func parseRoundSummary(row: Row, db: Database, hasState: Bool, hasCourse: Bool) throws -> RoundSummary? {
    guard
      let id: Int64 = row["id"],
      let startedAt: Date = row["startedAt"],
      let endedAt: Date? = row["endedAt"],
      let teeRaw: String = row["tee"],
      let tee = TeeID(rawValue: teeRaw),
      let unitRaw: String = row["distanceUnit"],
      let unit = DistanceUnit(rawValue: unitRaw),
      let gtRaw: String = row["gameType"],
      let gt = GameType(rawValue: gtRaw)
    else { return nil }

    let hi: Double? = row["handicapIndex"]
    let ap: Double? = row["allowancePct"]
    let ch: Int? = row["courseHandicap"]
    let ph: Int? = row["playingHandicap"]
    let state: RoundCompletionState = hasState ? (RoundCompletionState(rawValue: row["completionState"] ?? "in_progress") ?? .inProgress) : (endedAt == nil ? .inProgress : .completed)
    let course: String? = hasCourse ? row["course"] : nil

    return RoundSummary(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      tee: tee,
      distanceUnit: unit,
      completionState: state,
      course: course,
      gameType: gt,
      handicapIndex: hi,
      allowancePct: ap,
      courseHandicap: ch,
      playingHandicap: ph
    )
  }

  func completeRound(roundId: Int64) throws {
    try dbQueue.write { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      if cols.contains("completionState") {
        try db.execute(sql: "UPDATE rounds SET endedAt = ?, completionState = ? WHERE id = ?", arguments: [Date(), RoundCompletionState.completed.rawValue, roundId])
      } else {
        try db.execute(sql: "UPDATE rounds SET endedAt = ? WHERE id = ?", arguments: [Date(), roundId])
      }
    }
  }

  func abandonRound(roundId: Int64) throws {
    try dbQueue.write { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      if cols.contains("completionState") {
        // Set both so fetchActiveRound never returns this round (completionState or endedAt-based).
        try db.execute(sql: "UPDATE rounds SET endedAt = ?, completionState = ? WHERE id = ?", arguments: [Date(), RoundCompletionState.abandoned.rawValue, roundId])
      } else {
        // Legacy DB: set endedAt so fetchActiveRound (endedAt IS NULL) no longer returns this round
        try db.execute(sql: "UPDATE rounds SET endedAt = ? WHERE id = ?", arguments: [Date(), roundId])
      }
    }
  }

  func endRound(roundId: Int64) throws {
    try completeRound(roundId: roundId)
  }

  func updateRoundSettings(roundId: Int64, gameType: GameType, handicapIndex: Double?, allowancePct: Double?, courseHandicap: Int?, playingHandicap: Int?) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: "UPDATE rounds SET gameType = ?, handicapIndex = ?, allowancePct = ?, courseHandicap = ?, playingHandicap = ? WHERE id = ?",
        arguments: [gameType.rawValue, handicapIndex, allowancePct, courseHandicap, playingHandicap, roundId]
      )
    }
  }

  func lastHoleNumber(roundId: Int64) throws -> Int {
    try dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COALESCE(MAX(holeNumber), 1) FROM shots WHERE roundId = ?",
        arguments: [roundId]
      ) ?? 1
    }
  }
}
