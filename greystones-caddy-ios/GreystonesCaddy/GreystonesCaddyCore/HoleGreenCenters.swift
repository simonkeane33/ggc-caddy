import Foundation
import GRDB
import CoreLocation

public struct HoleGreenCenter: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "hole_green_centers"

  public var holeNumber: Int
  public var updatedAt: Date
  public var centerLat: Double
  public var centerLng: Double
  public var centerAlt: Double?
  public var frontLat: Double?
  public var frontLng: Double?
  public var frontAlt: Double?
  public var backLat: Double?
  public var backLng: Double?
  public var backAlt: Double?
}

public struct HoleTeeLocation: Codable, FetchableRecord, PersistableRecord, Sendable {
  public static let databaseTableName = "hole_tee_locations"

  public var holeNumber: Int
  public var tee: TeeID
  public var updatedAt: Date
  public var lat: Double
  public var lng: Double
  public var alt: Double?
}

public extension GCDB {
  func fetchGreenCenter(holeNumber: Int) throws -> HoleGreenCenter? {
    try dbQueue.read { db in
      try HoleGreenCenter.fetchOne(db, key: holeNumber)
    }
  }

  public func updateGreenCenter(holeNumber: Int, coordinate: CLLocationCoordinate2D) throws {
    try dbQueue.write { db in
      if var record = try HoleGreenCenter.filter(Column("holeNumber") == holeNumber).fetchOne(db) {
        record.centerLat = coordinate.latitude
        record.centerLng = coordinate.longitude
        record.updatedAt = Date()
        try record.save(db)
      }
    }
  }

  func upsertGreenCenter(
    holeNumber: Int,
    centerLat: Double,
    centerLng: Double,
    centerAlt: Double? = nil,
    frontLat: Double? = nil,
    frontLng: Double? = nil,
    frontAlt: Double? = nil,
    backLat: Double? = nil,
    backLng: Double? = nil,
    backAlt: Double? = nil
  ) throws {
    try dbQueue.write { db in
      var rec = HoleGreenCenter(
        holeNumber: holeNumber,
        updatedAt: Date(),
        centerLat: centerLat,
        centerLng: centerLng,
        centerAlt: centerAlt,
        frontLat: frontLat,
        frontLng: frontLng,
        frontAlt: frontAlt,
        backLat: backLat,
        backLng: backLng,
        backAlt: backAlt
      )
      try rec.save(db)
    }
  }

  func fetchTeeLocation(holeNumber: Int, tee: TeeID) throws -> HoleTeeLocation? {
    try dbQueue.read { db in
      try HoleTeeLocation
        .filter(Column("holeNumber") == holeNumber)
        .filter(Column("tee") == tee.rawValue)
        .fetchOne(db)
    }
  }

  func upsertTeeLocation(holeNumber: Int, tee: TeeID, lat: Double, lng: Double, alt: Double? = nil) throws {
    try dbQueue.write { db in
      var rec = HoleTeeLocation(holeNumber: holeNumber, tee: tee, updatedAt: Date(), lat: lat, lng: lng, alt: alt)
      try rec.save(db)
    }
  }

  func replaceGreenPerimeter(holeNumber: Int, points: [(lat: Double, lng: Double)]) throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM green_perimeters WHERE holeNumber = ?", arguments: [holeNumber])
      for (idx, pt) in points.enumerated() {
        try db.execute(
          sql: "INSERT INTO green_perimeters (holeNumber, lat, lng, sortOrder) VALUES (?, ?, ?, ?)",
          arguments: [holeNumber, pt.lat, pt.lng, idx]
        )
      }
    }
  }

  func fetchGreenPerimeter(holeNumber: Int) throws -> [CLLocationCoordinate2D] {
    try dbQueue.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT lat, lng FROM green_perimeters WHERE holeNumber = ? ORDER BY sortOrder", arguments: [holeNumber])
      return rows.map { CLLocationCoordinate2D(latitude: $0["lat"], longitude: $0["lng"]) }
    }
  }

  func fetchHoleElevationProfile(holeNumber: Int) throws -> HoleElevationProfile? {
    try dbQueue.read { db in
        guard let green = try HoleGreenCenter.fetchOne(db, key: holeNumber) else { return nil }
        
        // Use active round's tee if possible, otherwise default to blue
        let activeRoundTee = try Row.fetchOne(db, sql: "SELECT tee FROM rounds WHERE endedAt IS NULL ORDER BY startedAt DESC LIMIT 1")?["tee"] as String?
        let teeID = TeeID(rawValue: activeRoundTee ?? "blue") ?? .blue
        
        let tee = try HoleTeeLocation
            .filter(Column("holeNumber") == holeNumber)
            .filter(Column("tee") == teeID.rawValue)
            .fetchOne(db)
        
        return HoleElevationProfile(
            holeNumber: holeNumber,
            teeElevation: tee?.alt ?? green.centerAlt ?? 0,
            greenElevation: green.centerAlt ?? 0,
            fairwayPoints: []
        )
    }
  }
}
