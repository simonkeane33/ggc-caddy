import SwiftUI
import Combine
import MapKit
import CoreLocation
import GreystonesCaddyCore

/// Satellite view for the current hole. Tap to set a target and see distance from your current GPS position.
struct HoleAerialView: View {
  @EnvironmentObject var state: AppState
  @StateObject private var loc = LocationProvider()

  @State private var camera: MapCameraPosition = .automatic
  @State private var greenCenter: CLLocationCoordinate2D? = nil
  @State private var greenFront: CLLocationCoordinate2D? = nil
  @State private var greenBack: CLLocationCoordinate2D? = nil
  @State private var teeLocation: CLLocationCoordinate2D? = nil
  @State private var greenPerimeter: [CLLocationCoordinate2D] = []
  @State private var target: CLLocationCoordinate2D? = nil

  @State private var greenDistanceYd: Int? = nil
  @State private var greenFrontDistanceYd: Int? = nil
  @State private var greenBackDistanceYd: Int? = nil
  @State private var targetDistanceYd: Int? = nil

  @State private var setGreenMode: Bool = false
  @State private var selectedDistance: (meters: Double, label: String)? = nil
  @State private var isZoomedOnTarget: Bool = false
  /// Live drag position. Held in `@State` rather than `@StateObject` on purpose:
  /// `@State` stores the reference without subscribing this view to the object's
  /// `objectWillChange`, so a drag frame re-renders only the two children that
  /// observe it — the guide overlay and the distance panel — and never rebuilds
  /// the `Map`. See `TargetDragState`.
  @State private var drag = TargetDragState()

  var body: some View {
    ZStack {
      MapReader { proxy in
        ZStack {
          Map(position: $camera) {
          UserAnnotation()

          if let g = greenCenter {
            Annotation("Green Center", coordinate: g) {
              VStack(spacing: 4) {
                Image(systemName: "flag.circle.fill")
                  .font(.title2)
                  .foregroundStyle(.green)
                if let d = greenDistanceYd {
                  Text("\(d) yd")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                }
              }
            }
          }

          if let f = greenFront {
            Annotation("Front", coordinate: f) {
              Circle()
                .fill(.green.opacity(0.6))
                .frame(width: 12, height: 12)
            }
          }

          if let b = greenBack {
            Annotation("Back", coordinate: b) {
              Circle()
                .fill(.green.opacity(0.6))
                .frame(width: 12, height: 12)
            }
          }

          if !greenPerimeter.isEmpty {
            MapPolygon(coordinates: greenPerimeter)
              .stroke(.green.opacity(0.8), lineWidth: 2)
              .foregroundStyle(.green.opacity(0.2))
          }

          if let tee = teeLocation {
            Annotation("Tee", coordinate: tee) {
              Image(systemName: "circle.circle.fill")
                .foregroundStyle(state.tee == .blue ? .blue : (state.tee == .green ? .green : .red))
                .background(Circle().fill(.white))
            }
          }
        }
        .mapStyle(.imagery)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Hole view")
        .navigationBarTitleDisplayMode(.inline)
        .onMapCameraChange(frequency: .continuous) { _ in
          // Re-projects the overlay only; deliberately does not touch this
          // view's state, so the Map is not rebuilt while the camera animates.
          drag.cameraDidChange()
        }

        if let tee = teeLocation, let g = greenCenter {
          TargetGuideOverlay(
            proxy: proxy,
            drag: drag,
            tee: tee,
            green: g,
            committedTarget: target ?? midPoint(tee, g),
            isZoomed: isZoomedOnTarget,
            ringYardages: [20, 40, 60],
            crosshairIdentifier: "aerialTargetCrosshair",
            onCommit: { coord in
              target = coord
              recomputeDistances()
            }
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom) {
        if let g = greenCenter, let tee = teeLocation {
          DistancePanel(
            drag: drag,
            tee: tee,
            green: g,
            committedTarget: target ?? midPoint(tee, g),
            onSelect: { yards, label in
              selectedDistance = (meters: Double(yards) / 1.09361, label: label)
            }
          )
        }
      }
      .overlay(alignment: .bottom) {
          if let g = greenCenter, let tee = teeLocation {
              HStack {
                  Button(action: { isZoomedOnTarget.toggle() }) {
                      Image(systemName: isZoomedOnTarget ? "minus.magnifyingglass" : "plus.magnifyingglass")
                          .padding(10)
                          .background(.ultraThinMaterial)
                          .clipShape(Circle())
                  }

                  Spacer()
              }
              .padding(.horizontal)
              .padding(.bottom, 86)
          }
      }
      .sheet(item: Binding(
          get: { selectedDistance != nil ? DistanceSelection(val: selectedDistance!) : nil },
          set: { if $0 == nil { selectedDistance = nil } }
      )) { selection in
          PlaysLikeDetailSheet(
              actualDistance: selection.val.meters,
              holeNumber: state.holeNumber,
              targetLocation: nil
          )
          .presentationDetents([.large])
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(setGreenMode ? "Done" : "Set green") {
            setGreenMode.toggle()
          }
        }
      }
      // Tapping the map sets a target (or the green centre in setGreenMode).
      // Touches that land on the crosshair's catch area are consumed there instead,
      // so a tap never fights with a drag.
      .onTapGesture { point in
        guard let coord = proxy.convert(point, from: .local) else { return }

        if setGreenMode {
          // Save green center for this hole.
          let hn = state.holeNumber
          try? GCDB.shared.upsertGreenCenter(
            holeNumber: hn,
            centerLat: coord.latitude,
            centerLng: coord.longitude
          )
          greenCenter = coord
          setGreenMode = false
          recomputeDistances()
        } else {
          target = coord
          recomputeDistances()
        }
      }
      .onAppear {
        if loc.authorization == .notDetermined {
          loc.requestWhenInUse()
        }
        loc.refreshOnce()
        loadGreenCenterIfAny()
        snapToUser()
        recomputeDistances()
      }
      .onChange(of: loc.lastLocation) { _, _ in
        snapToUser()
        recomputeDistances()
      }
    }
  }
}

  private func snapToUser() {
    if let g = greenCenter, let tee = teeLocation {
        // Calculate heading from Tee to Green
        let lat1 = tee.latitude * .pi / 180
        let lon1 = tee.longitude * .pi / 180
        let lat2 = g.latitude * .pi / 180
        let lon2 = g.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let heading = atan2(y, x) * 180 / .pi
        
        // Calculate region
        let centerLat = (g.latitude + tee.latitude) / 2
        let centerLng = (g.longitude + tee.longitude) / 2
        let spanLat = abs(g.latitude - tee.latitude) * 1.3
        let spanLng = abs(g.longitude - tee.longitude) * 1.3
        
        camera = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            distance: 800, // Adjust for zoom level
            heading: heading,
            pitch: 0
        ))
        return
    }

    // Fallback to user location if no hole data mapped yet
    guard let l = loc.lastLocation else { return }
    camera = .region(
      MKCoordinateRegion(
        center: l.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
      )
    )
  }

  private func loadGreenCenterIfAny() {
    let hn = state.holeNumber
    do {
      if let rec = try GCDB.shared.fetchGreenCenter(holeNumber: hn) {
        greenCenter = CLLocationCoordinate2D(latitude: rec.centerLat, longitude: rec.centerLng)
        if let fLat = rec.frontLat, let fLng = rec.frontLng {
          greenFront = CLLocationCoordinate2D(latitude: fLat, longitude: fLng)
        }
        if let bLat = rec.backLat, let bLng = rec.backLng {
          greenBack = CLLocationCoordinate2D(latitude: bLat, longitude: bLng)
        }
      }
      
      if let tee = try GCDB.shared.fetchTeeLocation(holeNumber: hn, tee: state.tee) {
        teeLocation = CLLocationCoordinate2D(latitude: tee.lat, longitude: tee.lng)
      }

      greenPerimeter = (try? GCDB.shared.fetchGreenPerimeter(holeNumber: hn)) ?? []
    } catch {
      // ignore for MVP
    }
  }

  private func distanceYards(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Int {
    yardsBetween(from, to)
  }

  private func recomputeDistances() {
    guard let l = loc.lastLocation else { return }

    if let g = greenCenter {
      greenDistanceYd = distanceYards(from: l.coordinate, to: g)
    }
    if let f = greenFront {
      greenFrontDistanceYd = distanceYards(from: l.coordinate, to: f)
    }
    if let b = greenBack {
      greenBackDistanceYd = distanceYards(from: l.coordinate, to: b)
    }
    if let t = target {
      targetDistanceYd = distanceYards(from: l.coordinate, to: t)
    }
  }

  private func midPoint(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
      CLLocationCoordinate2D(
          latitude: (c1.latitude + c2.latitude) / 2,
          longitude: (c1.longitude + c2.longitude) / 2
      )
  }

  private func distancePill(label: String, value: String, color: Color) -> some View {
      VStack(spacing: 2) {
          Text(label)
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.secondary)
          Text("\(value)y")
              .font(.system(size: 24, weight: .bold, design: .rounded))
              .foregroundStyle(color)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
  }
}

/// Where the target currently is while a drag is in flight.
///
/// `point` is in the guide overlay's local space and drives the crosshair and
/// the guide lines; `coordinate` is the same position on the globe and drives
/// the distance read-out. Both are published together so a drag frame emits a
/// single change.
private struct DistancePanel: View {
    @ObservedObject var drag: TargetDragState
    let tee: CLLocationCoordinate2D
    let green: CLLocationCoordinate2D
    let committedTarget: CLLocationCoordinate2D
    let onSelect: (Int, String) -> Void

    var body: some View {
        let activeTarget = drag.live?.coordinate ?? committedTarget
        let distToTarget = yardsBetween(tee, activeTarget)
        let distToGreen = yardsBetween(activeTarget, green)

        HStack(spacing: 0) {
            Button {
                onSelect(distToTarget, "Current Shot")
            } label: {
                readout("Current Shot", "\(distToTarget)y", .white, id: "currentShotDistance")
            }
            .buttonStyle(.plain)

            // A Divider inside an HStack is greedy vertically, and safeAreaInset
            // proposes the full container height to its content. Without an
            // explicit height the whole panel — and its material background —
            // expands to cover the entire map.
            Divider()
                .frame(height: 34)
                .background(.white.opacity(0.3))

            Button {
                onSelect(distToGreen, "To Green")
            } label: {
                readout("To Green", "\(distToGreen)y", .yellow, id: "toGreenDistance")
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.bottom, 18) // home indicator
        .background(.thinMaterial)
    }

    private func readout(_ label: String, _ value: String, _ colour: Color, id: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.title3).bold().foregroundStyle(colour)
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Great-circle distance in yards. Shared by the view and its children.
private struct DistanceSelection: Identifiable {
    let id = UUID()
    let val: (meters: Double, label: String)
}
