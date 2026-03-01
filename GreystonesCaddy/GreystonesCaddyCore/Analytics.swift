import Foundation

public struct ClubDistanceStat: Sendable, Identifiable {
  public var id: String { club.rawValue }
  public var club: ClubID
  public var count: Int
  public var p25Metres: Double
  public var medianMetres: Double
  public var p75Metres: Double
}

public enum Analytics {
  /// Compute per-club distance stats from shot-to-next-shot GPS deltas.
  ///
  /// Notes:
  /// - Uses only events of kind `.shot`.
  /// - Attributes distance to the **club of the starting shot**.
  /// - Skips putter by default.
  /// - Filters out low-quality GPS points and implausible deltas.
  public static func clubDistanceStats(
    events: [HoleEvent],
    maxAccuracyMetres: Double = 20,
    minDistanceMetres: Double = 10,
    maxDistanceMetres: Double = 350
  ) -> [ClubDistanceStat] {
    // Filter to shots only (exclude chips + putts).
    let shots = events.filter { $0.kind == .shot && $0.shotType == .full }

    var samples: [ClubID: [Double]] = [:]

    for i in 0..<(max(0, shots.count - 1)) {
      let a = shots[i]
      let b = shots[i + 1]

      if a.club == .putter { continue }

      if let ha = a.hAcc, ha > maxAccuracyMetres { continue }
      if let hb = b.hAcc, hb > maxAccuracyMetres { continue }

      let d = Geo.distanceMetres(lat1: a.lat, lng1: a.lng, lat2: b.lat, lng2: b.lng)
      if d < minDistanceMetres || d > maxDistanceMetres { continue }

      samples[a.club, default: []].append(d)
    }

    func quantile(_ xs: [Double], q: Double) -> Double {
      let s = xs.sorted()
      guard !s.isEmpty else { return 0 }
      let pos = q * Double(s.count - 1)
      let lower = Int(floor(pos))
      let upper = Int(ceil(pos))
      if lower == upper { return s[lower] }
      let weight = pos - Double(lower)
      return s[lower] * (1 - weight) + s[upper] * weight
    }

    return samples
      .map { (club: $0.key, values: $0.value) }
      .map {
        ClubDistanceStat(
          club: $0.club,
          count: $0.values.count,
          p25Metres: quantile($0.values, q: 0.25),
          medianMetres: quantile($0.values, q: 0.5),
          p75Metres: quantile($0.values, q: 0.75)
        )
      }
      .sorted { $0.medianMetres > $1.medianMetres }
  }
}
