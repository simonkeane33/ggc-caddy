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

  /// Populates club yardages with mid-range defaults the first time the app
  /// runs, so recommendations and visuals have something to work with instead
  /// of every club reading "Not set".
  ///
  /// Only seeds when the table is completely empty — once the player has
  /// entered or edited anything, their numbers are never overwritten, including
  /// on later launches.
  @discardableResult
  func seedDefaultBaselinesIfEmpty() throws -> Bool {
    try dbQueue.write { db in
      guard try ClubBaseline.fetchCount(db) == 0 else { return false }
      let now = Date()
      for (club, yardage) in Club.defaultYardages {
        var rec = ClubBaseline(club: club, updatedAt: now, carryYd: yardage.carry, totalYd: yardage.total)
        try rec.insert(db)
      }
      return true
    }
  }
}
