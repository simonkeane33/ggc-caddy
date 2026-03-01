import Foundation

public enum ShotType: String, Codable, CaseIterable, Sendable {
  case full
  case threeQuarter = "threeQuarter"
  case half
  case chip
  case putt

  public var label: String {
    switch self {
    case .full: return "Full"
    case .threeQuarter: return "3/4"
    case .half: return "Half"
    case .chip: return "Chip"
    case .putt: return "Putt"
    }
  }
}
