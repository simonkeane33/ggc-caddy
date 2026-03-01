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
}
