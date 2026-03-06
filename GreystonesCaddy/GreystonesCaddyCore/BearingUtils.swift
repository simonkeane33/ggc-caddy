import CoreLocation

/// Returns the clockwise bearing in degrees [0, 360) from `from` to `to`.
/// Uses the flat-earth approximation; accurate enough for a single golf hole.
public func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
    let dLat = to.latitude - from.latitude
    let dLng = to.longitude - from.longitude
    let angle = atan2(dLng, dLat) * (180 / .pi)
    return (angle + 360).truncatingRemainder(dividingBy: 360)
}
