import Foundation
import GRDB

public enum StrategyMode: String, Codable, CaseIterable, Sendable {
  case safer
  case aggressive
}

public struct HolePlanRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "hole_plans"

  public var holeNumber: Int
  public var updatedAt: Date

  /// One-liner shown on the live hole screen.
  public var saferTip: String
  public var aggressiveTip: String
}

public extension GCDB {
  func upsertHolePlan(holeNumber: Int, saferTip: String, aggressiveTip: String) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
        INSERT INTO hole_plans (holeNumber, updatedAt, saferTip, aggressiveTip)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(holeNumber) DO UPDATE SET
          updatedAt=excluded.updatedAt,
          saferTip=excluded.saferTip,
          aggressiveTip=excluded.aggressiveTip
        """,
        arguments: [holeNumber, Date(), saferTip, aggressiveTip]
      )
    }
  }

  func fetchHolePlan(holeNumber: Int) throws -> HolePlanRecord? {
    try dbQueue.read { db in
      try HolePlanRecord.fetchOne(db, key: holeNumber)
    }
  }
}
