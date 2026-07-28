import Foundation

public enum TeeID: String, Codable, CaseIterable, Sendable {
  case blue, green, red
}

public struct CourseBundle: Codable, Sendable {
  public struct Course: Codable, Sendable {
    public var id: String
    public var name: String
    public var units: String
    public var source: String
  }

  public struct Tee: Codable, Sendable {
    public struct WHSRatings: Codable, Sendable {
      public var courseRating: Double
      public var slopeRating: Int
    }

    public var id: TeeID
    public var name: String

    /// Optional WHS ratings (used to compute course/playing handicap from handicap index).
    public var men: WHSRatings?
    public var ladies: WHSRatings?
  }

  /// Fixed-key per-tee values (avoids Codable dictionary key limitations).
  public struct PerTeeInt: Codable, Sendable {
    public var blue: Int
    public var green: Int
    public var red: Int

    public subscript(_ tee: TeeID) -> Int {
      switch tee {
      case .blue: blue
      case .green: green
      case .red: red
      }
    }
  }

  public struct Hole: Codable, Sendable, Identifiable {
    public var id: Int { number }
    public var number: Int
    public var name: String
    public var par: PerTeeInt
    public var si: PerTeeInt
    public var distance_m: PerTeeInt
    public var flyover: String
  }

  public var course: Course
  public var tees: [Tee]
  public var holes: [Hole]
  public var totals: Totals

  public struct Totals: Codable, Sendable {
    public var distance_m: PerTeeInt
  }
}

public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
  case metres
  case yards

  /// Format a distance stored in metres in this unit, with a unit suffix —
  /// e.g. `389y` (yards) or `356m` (metres). Truncated to whole units.
  public func format(_ metres: Double) -> String {
    switch self {
    case .yards: return "\(Int(Distance.metresToYards(metres)))y"
    case .metres: return "\(Int(metres))m"
    }
  }
}

public enum Distance {
  /// Convert metres → yards.
  public static func metresToYards(_ metres: Double) -> Double {
    metres * 1.0936132983377078
  }
}
