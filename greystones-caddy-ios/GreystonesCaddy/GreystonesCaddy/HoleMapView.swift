import SwiftUI
import MapKit
import GreystonesCaddyCore

struct HoleMapView: View {
  @EnvironmentObject var state: AppState
  @StateObject private var loc = LocationProvider()

  let roundId: Int64?
  let holeNumberOverride: Int?

  init(roundId: Int64? = nil, holeNumber: Int? = nil) {
    self.roundId = roundId
    self.holeNumberOverride = holeNumber
  }

  @State private var camera: MapCameraPosition = .automatic
  @State private var shotPins: [ShotPin] = []
  @State private var polyline: [CLLocationCoordinate2D] = []

  struct ShotPin: Identifiable {
    let id: Int64
    let title: String
    let coordinate: CLLocationCoordinate2D
  }

  var body: some View {
    Map(position: $camera) {
      // Show user location (blue dot) when available.
      UserAnnotation()

      if polyline.count >= 2 {
        MapPolyline(coordinates: polyline)
          .stroke(.blue.opacity(0.6), lineWidth: 3)
      }

      ForEach(shotPins) { p in
        Annotation(p.title, coordinate: p.coordinate) {
          Text(p.title)
            .font(.caption2)
            .padding(6)
            .background(.thinMaterial)
            .clipShape(Capsule())
        }
      }
    }
    .mapStyle(.standard)
    .navigationTitle("Hole \(holeNumberOverride ?? state.holeNumber) map")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if loc.authorization == .notDetermined {
        loc.requestWhenInUse()
      }
      loc.refreshOnce()
      refresh()
      snapToUserIfNoShots()
    }
    .onChange(of: loc.lastLocation) { _, _ in
      snapToUserIfNoShots()
    }
  }

  private func snapToUserIfNoShots() {
    guard shotPins.isEmpty else { return }
    guard let l = loc.lastLocation else { return }
    camera = .region(
      MKCoordinateRegion(
        center: l.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
      )
    )
  }

  private func refresh() {
    guard let rid = roundId ?? state.activeRoundId else { return }
    let hn = holeNumberOverride ?? state.holeNumber
    let ev = (try? GCDB.shared.fetchHoleEvents(roundId: rid, holeNumber: hn)) ?? []

    // Number shots only (ignore penalties for numbering).
    var shotIndex = 0
    var pins: [ShotPin] = []
    var coords: [CLLocationCoordinate2D] = []

    for e in ev {
      if e.kind == .shot {
        shotIndex += 1
        let c = CLLocationCoordinate2D(latitude: e.lat, longitude: e.lng)
        coords.append(c)
        pins.append(ShotPin(id: e.id, title: "#\(shotIndex)", coordinate: c))
      }
    }

    shotPins = pins
    polyline = coords

    // Set camera to last shot if available.
    if let last = pins.last {
      camera = .region(
        MKCoordinateRegion(
          center: last.coordinate,
          span: MKCoordinateSpan(latitudeDelta: 0.0025, longitudeDelta: 0.0025)
        )
      )
    }
  }
}
