import Foundation
import GRDB

public struct HoleGuideRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "hole_guides"

  public var holeNumber: Int
  public var updatedAt: Date

  public var target: String
  public var avoid: String
}

public extension GCDB {
  func upsertHoleGuide(holeNumber: Int, target: String, avoid: String) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
        INSERT INTO hole_guides (holeNumber, updatedAt, target, avoid)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(holeNumber) DO UPDATE SET
          updatedAt=excluded.updatedAt,
          target=excluded.target,
          avoid=excluded.avoid
        """,
        arguments: [holeNumber, Date(), target, avoid]
      )
    }
  }

  func fetchHoleGuide(holeNumber: Int) throws -> HoleGuideRecord? {
    try dbQueue.read { db in
      try HoleGuideRecord.fetchOne(db, key: holeNumber)
    }
  }
}
