import Foundation

public enum GameType: String, Codable, CaseIterable, Sendable, Identifiable {
  public var id: String { rawValue }

  case stroke
  case stableford

  public var label: String {
    switch self {
    case .stroke: return "Stroke play"
    case .stableford: return "Stableford"
    }
  }

  public var defaultAllowancePct: Double {
    switch self {
    case .stroke: return 100
    case .stableford: return 90
    }
  }
}

public enum WHS {
  /// WHS Course Handicap (approx): HandicapIndex × (Slope / 113) + (CourseRating − Par)
  /// Rounded to nearest whole number.
  public static func courseHandicap(handicapIndex: Double, slope: Int, courseRating: Double, par: Int) -> Int {
    let ch = handicapIndex * (Double(slope) / 113.0) + (courseRating - Double(par))
    return Int(ch.rounded())
  }

  /// Playing handicap is Course Handicap × allowance%. Rounded to nearest whole number.
  public static func playingHandicap(courseHandicap: Int, allowancePct: Double) -> Int {
    let ph = Double(courseHandicap) * (allowancePct / 100.0)
    return Int(ph.rounded())
  }

  /// Distribute handicap strokes across holes by stroke index.
  /// Returns strokes received on that hole.
  public static func strokesReceived(playingHandicap: Int, holeSI: Int) -> Int {
    // Example: 20 handicap => 1 stroke on all holes + extra on SI 1-2.
    let base = playingHandicap / 18
    let rem = playingHandicap % 18
    return base + ((holeSI <= rem) ? 1 : 0)
  }
}

public enum Stableford {
  /// Irish/standard Stableford: net double bogey or worse = 0, net bogey=1, net par=2, net birdie=3, etc.
  public static func points(par: Int, grossStrokes: Int, strokesReceived: Int) -> Int {
    let net = grossStrokes - strokesReceived
    let diff = par - net // +1 means net birdie, 0 net par, -1 net bogey, etc.
    // net eagle (diff=2) => 4, etc.
    let pts = diff + 2
    return max(0, pts)
  }
}
