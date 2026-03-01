import Foundation
import GRDB

public struct RoundSummary: Sendable, Identifiable, Hashable {
  public var id: Int64
  public var startedAt: Date
  public var endedAt: Date?
  public var tee: TeeID
  public var distanceUnit: DistanceUnit

  public var gameType: GameType
  public var handicapIndex: Double?
  public var allowancePct: Double?
  public var courseHandicap: Int?
  public var playingHandicap: Int?
}

public extension GCDB {
  func fetchRound(roundId: Int64) throws -> RoundSummary? {
    try dbQueue.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap FROM rounds WHERE id = ? LIMIT 1",
        arguments: [roundId]
      )
      guard let row else { return nil }
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

      return RoundSummary(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        tee: tee,
        distanceUnit: unit,
        gameType: gt,
        handicapIndex: hi,
        allowancePct: ap,
        courseHandicap: ch,
        playingHandicap: ph
      )
    }
  }

  func fetchActiveRound() throws -> RoundSummary? {
    try dbQueue.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap FROM rounds WHERE endedAt IS NULL ORDER BY startedAt DESC LIMIT 1"
      )
      guard let row else { return nil }
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

      return RoundSummary(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        tee: tee,
        distanceUnit: unit,
        gameType: gt,
        handicapIndex: hi,
        allowancePct: ap,
        courseHandicap: ch,
        playingHandicap: ph
      )
    }
  }

  func listRounds(limit: Int = 30) throws -> [RoundSummary] {
    try dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT id, startedAt, endedAt, tee, distanceUnit, gameType, handicapIndex, allowancePct, courseHandicap, playingHandicap FROM rounds ORDER BY startedAt DESC LIMIT ?",
        arguments: [limit]
      )

      return rows.compactMap { row in
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

        return RoundSummary(
          id: id,
          startedAt: startedAt,
          endedAt: endedAt,
          tee: tee,
          distanceUnit: unit,
          gameType: gt,
          handicapIndex: hi,
          allowancePct: ap,
          courseHandicap: ch,
          playingHandicap: ph
        )
      }
    }
  }

  func endRound(roundId: Int64) throws {
    try dbQueue.write { db in
      try db.execute(sql: "UPDATE rounds SET endedAt = ? WHERE id = ?", arguments: [Date(), roundId])
    }
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
