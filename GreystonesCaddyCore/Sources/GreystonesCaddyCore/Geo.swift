import Foundation

public enum Geo {
  /// Haversine distance in metres.
  public static func distanceMetres(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
    let r = 6_371_000.0
    let φ1 = lat1 * .pi / 180
    let φ2 = lat2 * .pi / 180
    let Δφ = (lat2 - lat1) * .pi / 180
    let Δλ = (lng2 - lng1) * .pi / 180

    let a = sin(Δφ/2) * sin(Δφ/2) + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return r * c
  }
}
