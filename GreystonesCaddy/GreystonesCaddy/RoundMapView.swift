import SwiftUI
import MapKit
import GreystonesCaddyCore

struct RoundMapView: View {
  let roundId: Int64

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
    .navigationTitle("Round map")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { refresh() }
  }

  private func refresh() {
    // Gather all shot events for the round.
    var pins: [ShotPin] = []
    var coords: [CLLocationCoordinate2D] = []

    for h in 1...18 {
      let ev = (try? GCDB.shared.fetchHoleEvents(roundId: roundId, holeNumber: h)) ?? []
      for e in ev where e.kind == .shot {
        let c = CLLocationCoordinate2D(latitude: e.lat, longitude: e.lng)
        coords.append(c)
        pins.append(ShotPin(id: e.id, title: "H\(h)", coordinate: c))
      }
    }

    shotPins = pins
    polyline = coords

    if let last = coords.last {
      camera = .region(
        MKCoordinateRegion(
          center: last,
          span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
      )
    }
  }
}
