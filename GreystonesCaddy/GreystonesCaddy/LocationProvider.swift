import Foundation
import Combine
import CoreLocation

@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var authorization: CLAuthorizationStatus
  @Published var lastLocation: CLLocation?
  @Published var lastError: String?

  private let manager = CLLocationManager()

  override init() {
    self.authorization = manager.authorizationStatus
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 5
    manager.startUpdatingLocation()
  }

  func requestWhenInUse() {
    manager.requestWhenInUseAuthorization()
  }

  func refreshOnce() {
    lastError = nil
    manager.requestLocation()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorization = manager.authorizationStatus
    if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
      manager.startUpdatingLocation()
      refreshOnce()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    lastLocation = locations.last
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    lastError = error.localizedDescription
  }
}
