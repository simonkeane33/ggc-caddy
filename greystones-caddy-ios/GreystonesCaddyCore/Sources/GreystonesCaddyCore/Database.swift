import Foundation
import GRDB

public final class GCDB: @unchecked Sendable {
  public static let shared = GCDB()

  public let dbQueue: DatabaseQueue

  private init() {
    do {
      let fm = FileManager.default
      let appSupport = try fm.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ).appendingPathComponent("GreystonesCaddy", isDirectory: true)

      try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

      let dbURL = appSupport.appendingPathComponent("gc.sqlite")
      var config = Configuration()
      config.prepareDatabase { db in
        db.trace { event in
          // Uncomment while debugging.
          // print("SQL:", event)
        }
      }

      self.dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
      try Self.migrate(dbQueue)
    } catch {
      fatalError("Failed to initialize database: \(error)")
    }
  }

  private static func migrate(_ dbQueue: DatabaseQueue) throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("init") { db in
      try db.create(table: "rounds") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("startedAt", .datetime).notNull()
        t.column("endedAt", .datetime)
        t.column("tee", .text).notNull()
        t.column("distanceUnit", .text).notNull()

        // Round settings
        t.column("gameType", .text).notNull().defaults(to: "stroke")
        t.column("handicapIndex", .double)
        t.column("allowancePct", .double)
        t.column("courseHandicap", .integer)
        t.column("playingHandicap", .integer)
      }

      try db.create(table: "shots") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("roundId", .integer).notNull().indexed().references("rounds", onDelete: .cascade)
        t.column("holeNumber", .integer).notNull().indexed()
        t.column("ts", .datetime).notNull().indexed()
        t.column("lat", .double).notNull()
        t.column("lng", .double).notNull()
        t.column("hAcc", .double)
        t.column("club", .text).notNull()
        t.column("shotType", .text).notNull().defaults(to: ShotType.full.rawValue)
        t.column("kind", .text).notNull() // shot | penalty
        t.column("penaltyStrokes", .integer)
      }

      try db.create(table: "hole_notes") { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("note", .text).notNull()
      }

      try db.create(table: "hole_plans") { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("saferTip", .text).notNull().defaults(to: "")
        t.column("aggressiveTip", .text).notNull().defaults(to: "")
      }

      try db.create(table: "hole_guides") { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("target", .text).notNull().defaults(to: "")
        t.column("avoid", .text).notNull().defaults(to: "")
      }
    }

    // Backwards compat for DBs created before endedAt / guides.
    migrator.registerMigration("v2") { db in
      if try !db.tableExists("rounds") { return }

      // Add endedAt if missing.
      let cols = try db.columns(in: "rounds").map(\.name)
      if !cols.contains("endedAt") {
        try db.alter(table: "rounds") { t in
          t.add(column: "endedAt", .datetime)
        }
      }

      // Create guides table if missing.
      try db.create(table: "hole_guides", ifNotExists: true) { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("target", .text).notNull().defaults(to: "")
        t.column("avoid", .text).notNull().defaults(to: "")
      }
    }

    // Add shotType to shots for older DBs.
    migrator.registerMigration("v3") { db in
      if try !db.tableExists("shots") { return }
      let cols = try db.columns(in: "shots").map(\.name)
      if !cols.contains("shotType") {
        try db.alter(table: "shots") { t in
          t.add(column: "shotType", .text).notNull().defaults(to: ShotType.full.rawValue)
        }
      }
    }

    // Ensure hole_plans exists for DBs created before we introduced it.
    migrator.registerMigration("v4") { db in
      try db.create(table: "hole_plans", ifNotExists: true) { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("saferTip", .text).notNull().defaults(to: "")
        t.column("aggressiveTip", .text).notNull().defaults(to: "")
      }

      // (Paranoia) Ensure hole_guides exists too.
      try db.create(table: "hole_guides", ifNotExists: true) { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("target", .text).notNull().defaults(to: "")
        t.column("avoid", .text).notNull().defaults(to: "")
      }
    }

    // Bag + baseline yardages.
    migrator.registerMigration("v5") { db in
      try db.create(table: "bag_clubs", ifNotExists: true) { t in
        t.primaryKey(["club"], onConflict: .replace)
        t.column("club", .text).notNull()
        t.column("sortOrder", .integer).notNull()
      }

      try db.create(table: "club_baselines", ifNotExists: true) { t in
        t.primaryKey(["club"], onConflict: .replace)
        t.column("club", .text).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("carryYd", .integer)
        t.column("totalYd", .integer)
      }
    }

    // Round settings: game type + WHS handicap.
    migrator.registerMigration("v6") { db in
      if try !db.tableExists("rounds") { return }
      let cols = try db.columns(in: "rounds").map(\.name)

      if !cols.contains("gameType") {
        try db.alter(table: "rounds") { t in
          t.add(column: "gameType", .text).notNull().defaults(to: "stroke")
        }
      }
      if !cols.contains("handicapIndex") {
        try db.alter(table: "rounds") { t in
          t.add(column: "handicapIndex", .double)
        }
      }
      if !cols.contains("allowancePct") {
        try db.alter(table: "rounds") { t in
          t.add(column: "allowancePct", .double)
        }
      }
      if !cols.contains("courseHandicap") {
        try db.alter(table: "rounds") { t in
          t.add(column: "courseHandicap", .integer)
        }
      }
      if !cols.contains("playingHandicap") {
        try db.alter(table: "rounds") { t in
          t.add(column: "playingHandicap", .integer)
        }
      }
    }

    // Shot tags.
    migrator.registerMigration("v7") { db in
      try db.create(table: "shot_tags", ifNotExists: true) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("eventId", .integer).notNull().indexed().references("shots", onDelete: .cascade)
        t.column("tag", .text).notNull().indexed()
      }
    }

    // Office scorecard overrides (gross strokes per hole, optional putts).
    migrator.registerMigration("v8") { db in
      try db.create(table: "hole_scores", ifNotExists: true) { t in
        t.primaryKey(["roundId", "holeNumber"], onConflict: .replace)
        t.column("roundId", .integer).notNull().indexed().references("rounds", onDelete: .cascade)
        t.column("holeNumber", .integer).notNull()
        t.column("gross", .integer).notNull()
        t.column("putts", .integer)
        t.column("updatedAt", .datetime).notNull()
      }
    }

    // Green center points (one per hole).
    migrator.registerMigration("v9") { db in
      try db.create(table: "hole_green_centers", ifNotExists: true) { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("centerLat", .double).notNull()
        t.column("centerLng", .double).notNull()
        t.column("centerAlt", .double) // Altitude
        t.column("frontLat", .double)
        t.column("frontLng", .double)
        t.column("frontAlt", .double)
        t.column("backLat", .double)
        t.column("backLng", .double)
        t.column("backAlt", .double)
      }
      
      try db.create(table: "hole_tee_locations", ifNotExists: true) { t in
        t.primaryKey(["holeNumber", "tee"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("tee", .text).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("lat", .double).notNull()
        t.column("lng", .double).notNull()
        t.column("alt", .double)
      }
    }

    // Stats Automation: hole_stats and round_stats_cache tables.
    migrator.registerMigration("v10") { db in
      // Table to store computed hole stats
      try db.create(table: "hole_stats", ifNotExists: true) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("holeEventId", .integer).notNull().unique()
        t.column("roundId", .integer).notNull().indexed()
        t.column("holeNumber", .integer).notNull()
        t.column("par", .integer).notNull()
        t.column("strokes", .integer).notNull()
        t.column("putts", .integer).notNull()
        t.column("penalties", .integer).notNull()
        t.column("gir", .boolean)
        t.column("fairwayHit", .boolean)
        t.column("scramble", .boolean)
        t.column("computedAt", .datetime).notNull()
        
        // Note: holeEventId doesn't reference hole_scores directly due to composite PK
        // We maintain referential integrity via roundId foreign key
        t.foreignKey(["roundId"], references: "rounds", onDelete: .cascade)
      }
      
      // Table to store cached round summaries
      try db.create(table: "round_stats_cache", ifNotExists: true) { t in
        t.column("roundId", .integer).primaryKey()
        t.column("totalStrokes", .integer).notNull()
        t.column("totalPutts", .integer).notNull()
        t.column("totalPenalties", .integer).notNull()
        t.column("scoreToPar", .integer).notNull()
        t.column("girPercentage", .double)
        t.column("fairwayPercentage", .double)
        t.column("scramblePercentage", .double)
        t.column("puttsPerRound", .double).notNull()
        t.column("girCount", .integer).notNull()
        t.column("girOpportunities", .integer).notNull()
        t.column("fairwayCount", .integer).notNull()
        t.column("fairwayOpportunities", .integer).notNull()
        t.column("scrambleCount", .integer).notNull()
        t.column("scrambleOpportunities", .integer).notNull()
        t.column("computedAt", .datetime).notNull()
        
        t.foreignKey(["roundId"], references: "rounds", onDelete: .cascade)
      }
    }

    // v1 canonical: shots need alt, isPutt, sequence; rounds need course
    migrator.registerMigration("v12") { db in
      if try db.tableExists("shots") {
        let cols = try db.columns(in: "shots").map(\.name)
        if !cols.contains("alt") {
          try db.alter(table: "shots") { t in
            t.add(column: "alt", .double)
          }
        }
        if !cols.contains("isPutt") {
          try db.alter(table: "shots") { t in
            t.add(column: "isPutt", .boolean).notNull().defaults(to: false)
          }
          try db.execute(sql: "UPDATE shots SET isPutt = 1 WHERE club = 'Putter' OR shotType = 'putt'")
        }
        if !cols.contains("sequence") {
          try db.alter(table: "shots") { t in
            t.add(column: "sequence", .integer)
          }
          try db.execute(sql: """
            UPDATE shots SET sequence = (
              SELECT COUNT(*) FROM shots s2
              WHERE s2.roundId = shots.roundId AND s2.holeNumber = shots.holeNumber
                AND (s2.ts < shots.ts OR (s2.ts = shots.ts AND s2.id <= shots.id))
            )
            """)
        }
      }
      if try db.tableExists("rounds") {
        let cols = try db.columns(in: "rounds").map(\.name)
        if !cols.contains("course") {
          try db.alter(table: "rounds") { t in
            t.add(column: "course", .text).notNull().defaults(to: "Greystones")
          }
        }
      }
    }

    // v1 canonical: completionState (in_progress, completed, abandoned)
    migrator.registerMigration("v13") { db in
      if try db.tableExists("rounds") {
        let cols = try db.columns(in: "rounds").map(\.name)
        if !cols.contains("completionState") {
          try db.alter(table: "rounds") { t in
            t.add(column: "completionState", .text).notNull().defaults(to: "in_progress")
          }
          try db.execute(sql: "UPDATE rounds SET completionState = CASE WHEN endedAt IS NULL THEN 'in_progress' ELSE 'completed' END")
        }
      }
    }

    migrator.registerMigration("v11") { db in
      try db.execute(sql: "DROP TABLE IF EXISTS hole_green_centers")
      try db.execute(sql: "DROP TABLE IF EXISTS hole_tee_locations")

      try db.create(table: "hole_green_centers") { t in
        t.primaryKey(["holeNumber"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("centerLat", .double).notNull()
        t.column("centerLng", .double).notNull()
        t.column("centerAlt", .double)
        t.column("frontLat", .double)
        t.column("frontLng", .double)
        t.column("frontAlt", .double)
        t.column("backLat", .double)
        t.column("backLng", .double)
        t.column("backAlt", .double)
      }

      try db.create(table: "hole_tee_locations") { t in
        t.primaryKey(["holeNumber", "tee"], onConflict: .replace)
        t.column("holeNumber", .integer).notNull()
        t.column("tee", .text).notNull()
        t.column("updatedAt", .datetime).notNull()
        t.column("lat", .double).notNull()
        t.column("lng", .double).notNull()
        t.column("alt", .double)
      }

      try db.create(table: "green_perimeters", ifNotExists: true) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("holeNumber", .integer).notNull().indexed()
        t.column("lat", .double).notNull()
        t.column("lng", .double).notNull()
        t.column("sortOrder", .integer).notNull()
      }
    }

    try migrator.migrate(dbQueue)
  }
}

public struct RoundRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "rounds"

  public var id: Int64?
  public var startedAt: Date
  public var tee: TeeID
  public var distanceUnit: DistanceUnit
}

public enum ShotKind: String, Codable, Sendable {
  case shot
  case penalty
}

public struct ShotRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "shots"

  public var id: Int64?
  public var roundId: Int64
  public var holeNumber: Int
  public var ts: Date
  public var lat: Double
  public var lng: Double
  public var alt: Double?
  public var hAcc: Double?
  public var club: ClubID
  public var shotType: ShotType
  public var kind: ShotKind
  public var penaltyStrokes: Int?
  public var isPutt: Bool
  public var sequence: Int?
}

public extension GCDB {
  func createRound(tee: TeeID, distanceUnit: DistanceUnit, course: String = "Greystones") throws -> Int64 {
    try dbQueue.write { db in
      let cols = try db.columns(in: "rounds").map(\.name)
      let hasCourse = cols.contains("course")
      let hasState = cols.contains("completionState")
      if hasCourse && hasState {
        try db.execute(
          sql: "INSERT INTO rounds (startedAt, tee, distanceUnit, gameType, course, completionState) VALUES (?, ?, ?, ?, ?, ?)",
          arguments: [Date(), tee.rawValue, distanceUnit.rawValue, GameType.stroke.rawValue, course, RoundCompletionState.inProgress.rawValue]
        )
      } else if hasCourse {
        try db.execute(
          sql: "INSERT INTO rounds (startedAt, tee, distanceUnit, gameType, course) VALUES (?, ?, ?, ?, ?)",
          arguments: [Date(), tee.rawValue, distanceUnit.rawValue, GameType.stroke.rawValue, course]
        )
      } else {
        try db.execute(
          sql: "INSERT INTO rounds (startedAt, tee, distanceUnit, gameType) VALUES (?, ?, ?, ?)",
          arguments: [Date(), tee.rawValue, distanceUnit.rawValue, GameType.stroke.rawValue]
        )
      }
      return db.lastInsertedRowID
    }
  }

  func addShot(roundId: Int64, holeNumber: Int, location: (lat: Double, lng: Double, alt: Double?, hAcc: Double?), club: ClubID, shotType: ShotType) throws {
    let inferred: ShotType = (club == .putter) ? .putt : shotType
    let isPutt = (inferred == .putt)

    try dbQueue.write { db in
      let nextSeq: Int
      if try db.columns(in: "shots").map(\.name).contains("sequence") {
        nextSeq = (try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM shots WHERE roundId = ? AND holeNumber = ?",
          arguments: [roundId, holeNumber]
        ) ?? 0) + 1
      } else {
        nextSeq = 1
      }

      let s = ShotRecord(
        id: nil,
        roundId: roundId,
        holeNumber: holeNumber,
        ts: Date(),
        lat: location.lat,
        lng: location.lng,
        alt: location.alt,
        hAcc: location.hAcc,
        club: club,
        shotType: inferred,
        kind: .shot,
        penaltyStrokes: nil,
        isPutt: isPutt,
        sequence: nextSeq
      )

      try s.insert(db)
    }
  }

  func addPenalty(roundId: Int64, holeNumber: Int, location: (lat: Double, lng: Double, alt: Double?, hAcc: Double?), strokes: Int) throws {
    try dbQueue.write { db in
      let nextSeq: Int
      if try db.columns(in: "shots").map(\.name).contains("sequence") {
        nextSeq = (try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM shots WHERE roundId = ? AND holeNumber = ?",
          arguments: [roundId, holeNumber]
        ) ?? 0) + 1
      } else {
        nextSeq = 1
      }

      let s = ShotRecord(
        id: nil,
        roundId: roundId,
        holeNumber: holeNumber,
        ts: Date(),
        lat: location.lat,
        lng: location.lng,
        alt: location.alt,
        hAcc: location.hAcc,
        club: .putter,
        shotType: .full,
        kind: .penalty,
        penaltyStrokes: strokes,
        isPutt: false,
        sequence: nextSeq
      )

      try s.insert(db)
    }
  }

  func deleteLastEvent(roundId: Int64, holeNumber: Int) throws {
    try dbQueue.write { db in
      if let row = try Row.fetchOne(
        db,
        sql: "SELECT id FROM shots WHERE roundId = ? AND holeNumber = ? ORDER BY ts DESC, id DESC LIMIT 1",
        arguments: [roundId, holeNumber]
      ),
      let id: Int64 = row["id"] {
        try db.execute(sql: "DELETE FROM shots WHERE id = ?", arguments: [id])
      }
    }
  }

  func eventsCount(roundId: Int64, holeNumber: Int) throws -> Int {
    try dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM shots WHERE roundId = ? AND holeNumber = ?",
        arguments: [roundId, holeNumber]
      ) ?? 0
    }
  }

  func strokesForHole(roundId: Int64, holeNumber: Int) throws -> Int {
    try dbQueue.read { db in
      let shots = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM shots WHERE roundId = ? AND holeNumber = ? AND kind = 'shot'",
        arguments: [roundId, holeNumber]
      ) ?? 0

      let pen = try Int.fetchOne(
        db,
        sql: "SELECT COALESCE(SUM(penaltyStrokes),0) FROM shots WHERE roundId = ? AND holeNumber = ? AND kind = 'penalty'",
        arguments: [roundId, holeNumber]
      ) ?? 0

      return shots + pen
    }
  }

  func puttsForHole(roundId: Int64, holeNumber: Int) throws -> Int {
    try dbQueue.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM shots WHERE roundId = ? AND holeNumber = ? AND kind = 'shot' AND club = ?",
        arguments: [roundId, holeNumber, ClubID.putter.rawValue]
      ) ?? 0
    }
  }
}
