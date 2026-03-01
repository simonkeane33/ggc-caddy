import Foundation
import GRDB

public struct HoleEvent: Sendable, Identifiable {
  public var id: Int64
  public var ts: Date
  public var kind: ShotKind
  public var club: ClubID
  public var shotType: ShotType
  public var penaltyStrokes: Int?

  public var lat: Double
  public var lng: Double
  public var hAcc: Double?
}

public extension GCDB {
  func fetchHoleEvents(roundId: Int64, holeNumber: Int, limit: Int = 200) throws -> [HoleEvent] {
    try dbQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT id, ts, kind, club, shotType, penaltyStrokes, lat, lng, hAcc
        FROM shots
        WHERE roundId = ? AND holeNumber = ?
        ORDER BY ts ASC, id ASC
        LIMIT ?
        """,
        arguments: [roundId, holeNumber, limit]
      )

      return rows.compactMap { r in
        guard
          let id: Int64 = r["id"],
          let ts: Date = r["ts"],
          let kindRaw: String = r["kind"],
          let kind = ShotKind(rawValue: kindRaw),
          let clubRaw: String = r["club"],
          let club = ClubID(rawValue: clubRaw),
          let stRaw: String = r["shotType"],
          let lat: Double = r["lat"],
          let lng: Double = r["lng"]
        else { return nil }

        let st = ShotType(rawValue: stRaw) ?? .full
        let p: Int? = r["penaltyStrokes"]
        let h: Double? = r["hAcc"]
        return HoleEvent(id: id, ts: ts, kind: kind, club: club, shotType: st, penaltyStrokes: p, lat: lat, lng: lng, hAcc: h)
      }
    }
  }

  func deleteEvent(id: Int64) throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM shots WHERE id = ?", arguments: [id])
    }
  }

  func updateShotClub(id: Int64, club: ClubID) throws {
    try dbQueue.write { db in
      // If changing to putter, force shotType=putt.
      if club == .putter {
        try db.execute(sql: "UPDATE shots SET club = ?, shotType = ? WHERE id = ?", arguments: [club.rawValue, ShotType.putt.rawValue, id])
      } else {
        try db.execute(sql: "UPDATE shots SET club = ? WHERE id = ?", arguments: [club.rawValue, id])
      }
    }
  }

  func updateShotType(id: Int64, shotType: ShotType) throws {
    try dbQueue.write { db in
      try db.execute(sql: "UPDATE shots SET shotType = ? WHERE id = ?", arguments: [shotType.rawValue, id])
    }
  }

  func updatePenalty(id: Int64, strokes: Int) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: "UPDATE shots SET kind = 'penalty', penaltyStrokes = ? WHERE id = ?",
        arguments: [strokes, id]
      )
    }
  }
}
