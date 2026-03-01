import Foundation
import GRDB

public struct BagClub: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "bag_clubs"

  public var club: ClubID
  public var sortOrder: Int
}

public struct ClubBaseline: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "club_baselines"

  public var club: ClubID
  public var updatedAt: Date
  public var carryYd: Int?
  public var totalYd: Int?
}

public extension GCDB {
  func fetchBagClubs() throws -> [ClubID] {
    try dbQueue.read { db in
      let rows = try BagClub
        .order(Column("sortOrder").asc)
        .fetchAll(db)
      return rows.map(\.club)
    }
  }

  /// Replaces the current bag contents. Clubs are stored in the given order.
  func setBagClubs(_ clubs: [ClubID]) throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM bag_clubs")
      for (idx, c) in clubs.enumerated() {
        try BagClub(club: c, sortOrder: idx).insert(db)
      }
    }
  }

  func fetchBaseline(club: ClubID) throws -> ClubBaseline? {
    try dbQueue.read { db in
      try ClubBaseline.filter(Column("club") == club.rawValue).fetchOne(db)
    }
  }

  func upsertBaseline(club: ClubID, carryYd: Int?, totalYd: Int?) throws {
    try dbQueue.write { db in
      var rec = ClubBaseline(club: club, updatedAt: Date(), carryYd: carryYd, totalYd: totalYd)
      try rec.save(db)
    }
  }

  func listBaselines() throws -> [ClubBaseline] {
    try dbQueue.read { db in
      try ClubBaseline.fetchAll(db)
    }
  }
}
