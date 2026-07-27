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

  /// Starting carry/total yardages for a mid-range amateur, so the app has
  /// something usable before the player has measured anything. These are a
  /// starting point to be edited, not a claim about any individual — the
  /// Typical Yardages screen exists to correct them.
  ///
  /// The putter is deliberately absent: a carry distance for it is meaningless.
  public static let defaultYardages: [ClubID: (carry: Int, total: Int)] = [
    .driver:   (220, 240),
    .wood3:    (200, 215),
    .hybrid3:  (190, 200),
    .hybrid4:  (180, 190),
    .iron4:    (170, 178),
    .iron5:    (160, 168),
    .iron6:    (150, 157),
    .iron7:    (140, 146),
    .iron8:    (130, 135),
    .iron9:    (120, 124),
    .pw:       (110, 113),
    .gw:       (100, 102),
    .sw:       (85, 87),
    .lw:       (70, 71),
    .wedge50:  (100, 102),
    .wedge52:  (95, 97),
    .wedge54:  (88, 90),
    .wedge56:  (82, 84),
    .wedge58:  (75, 77),
    .wedge60:  (68, 70)
  ]
}
