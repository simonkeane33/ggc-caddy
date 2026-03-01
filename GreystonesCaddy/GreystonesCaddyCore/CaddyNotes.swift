import Foundation
import GRDB

public struct HoleNoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "hole_notes"

  // Primary key: holeNumber
  public var holeNumber: Int
  public var updatedAt: Date
  public var note: String
}

public extension GCDB {
  func upsertHoleNote(holeNumber: Int, note: String) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
        INSERT INTO hole_notes (holeNumber, updatedAt, note)
        VALUES (?, ?, ?)
        ON CONFLICT(holeNumber) DO UPDATE SET updatedAt=excluded.updatedAt, note=excluded.note
        """,
        arguments: [holeNumber, Date(), note]
      )
    }
  }

  func fetchHoleNote(holeNumber: Int) throws -> String? {
    try dbQueue.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT note FROM hole_notes WHERE holeNumber = ?",
        arguments: [holeNumber]
      )
    }
  }
}
