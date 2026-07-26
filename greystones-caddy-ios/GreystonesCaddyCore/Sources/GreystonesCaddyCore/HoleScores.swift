import Foundation
import GRDB

public struct HoleScore: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "hole_scores"

  public var roundId: Int64
  public var holeNumber: Int
  public var gross: Int
  public var putts: Int?
  public var updatedAt: Date
}

public extension GCDB {
  func fetchHoleScores(roundId: Int64) throws -> [Int: HoleScore] {
    try dbQueue.read { db in
      let rows = try HoleScore.filter(Column("roundId") == roundId).fetchAll(db)
      return Dictionary(uniqueKeysWithValues: rows.map { ($0.holeNumber, $0) })
    }
  }

  func upsertHoleScore(roundId: Int64, holeNumber: Int, gross: Int, putts: Int?) throws {
    try dbQueue.write { db in
      var rec = HoleScore(roundId: roundId, holeNumber: holeNumber, gross: gross, putts: putts, updatedAt: Date())
      try rec.save(db)
    }
  }

  func deleteHoleScore(roundId: Int64, holeNumber: Int) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM hole_scores WHERE roundId = ? AND holeNumber = ?",
        arguments: [roundId, holeNumber]
      )
    }
  }

  /// Total score (strokes) from hole_scores for a round.
  func totalScoreFromHoleScores(roundId: Int64) throws -> Int {
    try dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COALESCE(SUM(gross), 0) FROM hole_scores WHERE roundId = ? AND gross > 0",
        arguments: [roundId]
      ) ?? 0
    }
  }

  /// Total putts from hole_scores for a round.
  func totalPuttsFromHoleScores(roundId: Int64) throws -> Int {
    try dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COALESCE(SUM(putts), 0) FROM hole_scores WHERE roundId = ?",
        arguments: [roundId]
      ) ?? 0
    }
  }

  /// Holes that have scores (gross > 0) for a round.
  func holesWithScores(roundId: Int64) throws -> Set<Int> {
    try dbQueue.read { db in
      let rows = try Int.fetchAll(
        db,
        sql: "SELECT holeNumber FROM hole_scores WHERE roundId = ? AND gross > 0",
        arguments: [roundId]
      )
      return Set(rows)
    }
  }
}
