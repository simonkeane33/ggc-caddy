import Foundation
import Combine
import GreystonesCaddyCore

extension Notification.Name {
  static let greenCenterDidUpdate = Notification.Name("greenCenterDidUpdate")
}

@MainActor
final class AppState: ObservableObject {
  @Published var course: CourseBundle

  @Published var tee: TeeID = .blue
  @Published var unit: DistanceUnit = .yards

  @Published var activeRoundId: Int64? = nil
  @Published var holeNumber: Int = 1

  @Published var favouriteClubs: [ClubID] = Club.defaultFavourites
  @Published var selectedClub: ClubID = Club.defaultFavourites.last ?? .putter

  @Published var shotType: ShotType = .full

  // Strategy mode removed for MVP: keep UI simple on-course.
  // @Published var strategyMode: StrategyMode = .safer

  init() {
    do {
      self.course = try CourseLoader.loadGreystonesCourse()

      // One-time import of high-accuracy GPS coordinates if needed
      if let csvURL = CourseLoader.bundle.url(forResource: "default", withExtension: "csv"),
         let csvContent = try? String(contentsOf: csvURL) {
          try? CourseDataImporter.importCSV(csvContent)
          print("DEBUG: Successfully imported high-accuracy coordinates from default.csv")
      } else {
          print("ERROR: Could not load default.csv from bundle")
      }

      // One-time import of Green Perimeter for Hole 1 (Enhanced High-Density Mapping)
      let h1Points: [(lat: Double, lng: Double)] = [
          (53.14047772450267, -6.076614670843671),
          (53.1404587202619, -6.076617803197367),
          (53.14043867897433, -6.076616614686328),
          (53.14041880090131, -6.076616282525698),
          (53.14039997274202, -6.076604250207756),
          (53.14038548270456, -6.076583723474553),
          (53.14037970456781, -6.076559210275643),
          (53.14037448945543, -6.076527488173477),
          (53.14037527969552, -6.076502954029581),
          (53.1403747802303, -6.07646612198094),
          (53.14037428129053, -6.07643693368506),
          (53.14037114724916, -6.076408654170869),
          (53.14036297362551, -6.07638045666487),
          (53.14035248766614, -6.076349698308368),
          (53.14034465645732, -6.076326620302211),
          (53.14033692629791, -6.076299819925904),
          (53.14033536538914, -6.076275065015802),
          (53.1403363692088, -6.076250572389974),
          (53.14033955933014, -6.076225370759851),
          (53.14035024739758, -6.076197226606304),
          (53.14035657975946, -6.076189039841408),
          (53.14037280776305, -6.076174175937171),
          (53.1403863432867, -6.07616572398796),
          (53.14040067450015, -6.076162934537269),
          (53.14041253816607, -6.076162565183961),
          (53.14042584056068, -6.076165768169329),
          (53.14043938374358, -6.07617829663902),
          (53.14045296702239, -6.076190759015111),
          (53.14046537112955, -6.076205464440508),
          (53.14047621353696, -6.076226269126162),
          (53.14048460979711, -6.07625418828132),
          (53.14048813658007, -6.076279848709572),
          (53.14049178718494, -6.076303783043917),
          (53.14049735027514, -6.076326715232465),
          (53.14050890681965, -6.076351659047928),
          (53.14052531008061, -6.076377008565034),
          (53.14054183145114, -6.076395759316905),
          (53.14055358443521, -6.076412073177907),
          (53.14056324420712, -6.076435530825901),
          (53.14057159514143, -6.076461045166102),
          (53.14057466019577, -6.076494598456408),
          (53.14057304928281, -6.076524663095926),
          (53.14056895005137, -6.076548737331301),
          (53.14056188460616, -6.076573529883173),
          (53.14054984025198, -6.076594318560212),
          (53.14053942222608, -6.07660612503587),
          (53.14052368961913, -6.076614517883407),
          (53.14050963849397, -6.076616299698312),
          (53.14049709445914, -6.076615547169273)
      ]
      try? GCDB.shared.replaceGreenPerimeter(holeNumber: 1, points: h1Points)
      print("DEBUG: Replaced green perimeter for Hole 1 with \(h1Points.count) points")

      // Import accurate slope metadata for Hole 1
      try? GCDB.shared.upsertGreenCenter(
          holeNumber: 1,
          centerLat: 53.1404404,
          centerLng: -6.0764183,
          centerAlt: 42.47,
          frontLat: 53.140358,
          frontLng: -6.076184,
          frontAlt: 41.98,
          backLat: 53.1405413,
          backLng: -6.0765983,
          backAlt: 42.53
      )

      if let active = try? GCDB.shared.fetchActiveRound() {
        activeRoundId = active.id
        tee = active.tee
        unit = active.distanceUnit
        holeNumber = (try? GCDB.shared.lastHoleNumber(roundId: active.id)) ?? 1
      }

      // Load bag selection (one-off setting).
      if let bag = try? GCDB.shared.fetchBagClubs(), !bag.isEmpty {
        favouriteClubs = bag
      }

      // Ensure selectedClub is valid.
      if !favouriteClubs.contains(selectedClub) {
        selectedClub = favouriteClubs.first ?? .driver
      }
    } catch {
      fatalError("Failed to initialize app state: \(error)")
    }
  }

  func resetToNewRoundDefaults() {
    holeNumber = 1
    selectedClub = favouriteClubs.first ?? .driver
    shotType = .full
    // strategyMode = .safer
  }

  func reloadBagFromDB() {
    if let bag = try? GCDB.shared.fetchBagClubs(), !bag.isEmpty {
      favouriteClubs = bag
      if !favouriteClubs.contains(selectedClub) {
        selectedClub = favouriteClubs.first ?? .driver
      }
    }
  }

  var currentHole: CourseBundle.Hole? {
    course.holes.first(where: { $0.number == holeNumber })
  }
}
