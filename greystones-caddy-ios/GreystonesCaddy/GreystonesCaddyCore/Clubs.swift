import Foundation

public enum ClubID: String, Codable, CaseIterable, Sendable, Identifiable {
  public var id: String { rawValue }

  case driver = "Driver"
  case wood3 = "3W"
  case hybrid3 = "3H"
  case hybrid4 = "4H"
  case iron4 = "4i"
  case iron5 = "5i"
  case iron6 = "6i"
  case iron7 = "7i"
  case iron8 = "8i"
  case iron9 = "9i"
  case pw = "PW"
  case gw = "GW"
  case sw = "SW"
  case lw = "LW"
  case wedge50 = "50°"
  case wedge52 = "52°"
  case wedge54 = "54°"
  case wedge56 = "56°"
  case wedge58 = "58°"
  case wedge60 = "60°"
  case putter = "Putter"
}

public enum Club {
  /// Sensible default favourites for quick on-course tapping.
  public static let defaultFavourites: [ClubID] = [
    .driver, .wood3, .iron7, .iron9, .pw, .wedge56, .wedge60, .putter
  ]
}
