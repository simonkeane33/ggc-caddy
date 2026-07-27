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

  /// Initial great-circle bearing in degrees, normalised to 0..<360.
  /// 0 = due north, 90 = due east — the same convention the weather API uses
  /// for wind direction, so the two can be compared directly.
  public static func bearingDegrees(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
    let φ1 = lat1 * .pi / 180
    let φ2 = lat2 * .pi / 180
    let Δλ = (lng2 - lng1) * .pi / 180

    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    let θ = atan2(y, x) * 180 / .pi
    return (θ + 360).truncatingRemainder(dividingBy: 360)
  }
}
