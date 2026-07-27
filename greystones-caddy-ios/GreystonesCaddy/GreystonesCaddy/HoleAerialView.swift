import SwiftUI
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
  @State private var dragTarget: CLLocationCoordinate2D? = nil
  @State private var mapInteractionEnabled: Bool = true
  /// Bumped on every camera change so the guide lines and crosshair, which are
  /// projected through the MapProxy, re-render as the map pans and zooms.
  @State private var renderToken = UUID()

  var body: some View {
    ZStack {
      MapReader { proxy in
        ZStack {
          Map(position: $camera, interactionModes: mapInteractionEnabled ? .all : []) {
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
          renderToken = UUID()
        }

        if let tee = teeLocation, let g = greenCenter {
          let committedTarget = target ?? midPoint(tee, g)
          let activeTarget = dragTarget ?? committedTarget

          // Lines/rings: full-screen overlay that is purely visual and never blocks touches.
          LineGuideOverlay(
            proxy: proxy,
            tee: tee,
            target: activeTarget,
            green: g,
            isZoomed: isZoomedOnTarget
          )

          // Draggable target crosshair. This *must* be a sibling of the guide
          // overlay inside the same ZStack and positioned with the proxy's
          // `.local` space: `.position` resolves against the parent's local
          // coordinates, so positioning with `.global` points would render the
          // crosshair offset from the lines by the status/nav bar height.
          if let crosshairPoint = proxy.convert(activeTarget, to: .local) {
            // Clear catch area behind the crosshair visual. Map interactions are
            // disabled while dragging so the Map pan gesture does not compete.
            // The catch area is only 240×240 pts so the rest of the map stays
            // fully interactive.
            Color.clear
              .contentShape(Rectangle())
              .frame(width: 240, height: 240)
              .position(crosshairPoint)
              .gesture(
                // The drag reads `.global` points and converts them back through
                // the same proxy, so the committed coordinate lands exactly under
                // the finger regardless of where the overlay sits on screen.
                DragGesture(coordinateSpace: .global)
                  .onChanged { value in
                    mapInteractionEnabled = false
                    if let coord = proxy.convert(value.location, from: .global) {
                      dragTarget = coord
                    }
                  }
                  .onEnded { value in
                    if let coord = proxy.convert(value.location, from: .global) {
                      target = coord
                      recomputeDistances()
                    }
                    dragTarget = nil
                    mapInteractionEnabled = true
                  }
              )

            // Crosshair visual sits on top but does not intercept touches.
            TargetCrosshair(isZoomed: isZoomedOnTarget)
              .frame(width: 160, height: 160)
              .position(crosshairPoint)
              .accessibilityIdentifier("aerialTargetCrosshair")
              .allowsHitTesting(false)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom) {
        if let g = greenCenter, let tee = teeLocation {
            let activeTarget = dragTarget ?? target ?? midPoint(tee, g)
            let distToTarget = distanceYards(from: tee, to: activeTarget)
            let distTargetToGreen = distanceYards(from: activeTarget, to: g)

            HStack(spacing: 0) {
                Button {
                    selectedDistance = (meters: Double(distToTarget) / 1.09361, label: "Current Shot")
                } label: {
                    VStack(spacing: 2) {
                        Text("Current Shot").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(distToTarget)y").font(.title3).bold().foregroundStyle(.white)
                            .accessibilityIdentifier("currentShotDistance")
                    }
                    .frame(maxWidth: .infinity)
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
                    selectedDistance = (meters: Double(distTargetToGreen) / 1.09361, label: "To Green")
                } label: {
                    VStack(spacing: 2) {
                        Text("To Green").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(distTargetToGreen)y").font(.title3).bold().foregroundStyle(.yellow)
                            .accessibilityIdentifier("toGreenDistance")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
            .padding(.bottom, 18) // home indicator
            .background(.thinMaterial)
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
    let dM = CLLocation(latitude: from.latitude, longitude: from.longitude)
      .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    return Int((dM * 1.0936132983377078).rounded())
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

/// Synchronous "as the crow flies" guide lines and distance rings drawn as a
/// SwiftUI overlay directly on the map. MapKit's MapPolyline/MapCircle overlays
/// redraw on a separate thread and lag behind a moving target. Keeping these
/// lines in SwiftUI screen space avoids that lag. This overlay never intercepts
/// touches so the map underneath remains fully interactive.
private struct LineGuideOverlay: View {
    let proxy: MapProxy
    let tee: CLLocationCoordinate2D
    let target: CLLocationCoordinate2D
    let green: CLLocationCoordinate2D
    let isZoomed: Bool

    var body: some View {
        GeometryReader { geo in
            let teePoint = proxy.convert(tee, to: .local) ?? .zero
            let targetPoint = proxy.convert(target, to: .local) ?? .zero
            let greenPoint = proxy.convert(green, to: .local) ?? .zero

            ZStack {
                LineShape(from: teePoint, to: targetPoint)
                    .stroke(.white.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)

                LineShape(from: targetPoint, to: greenPoint)
                    .stroke(.white.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)

                if isZoomed {
                    ForEach([20.0, 40.0, 60.0], id: \.self) { yards in
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                            .frame(
                                width: ringDiameter(yards: yards, center: target),
                                height: ringDiameter(yards: yards, center: target)
                            )
                            .position(targetPoint)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(Color.clear)
            .allowsHitTesting(false)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func ringDiameter(yards: Double, center: CLLocationCoordinate2D) -> CGFloat {
        guard let edgeCoord = coordinate(at: yards, center: center, heading: 90) else { return 0 }
        guard let edgePoint = proxy.convert(edgeCoord, to: .local) else { return 0 }
        guard let centerPoint = proxy.convert(center, to: .local) else { return 0 }
        return abs(edgePoint.x - centerPoint.x) * 2
    }

    private func coordinate(at distanceYards: Double, center: CLLocationCoordinate2D, heading: Double) -> CLLocationCoordinate2D? {
        let distanceMeters = distanceYards * 0.9144
        let deltaLat = distanceMeters / 111320.0
        let deltaLon = distanceMeters / (111320.0 * cos(center.latitude * .pi / 180))
        return CLLocationCoordinate2D(
            latitude: center.latitude + deltaLat,
            longitude: center.longitude + deltaLon
        )
    }
}

/// The on-screen target crosshair. Kept as a separate reusable view so it can
/// live inside a SwiftUI overlay that sits *outside* the MapReader and is
/// therefore never clipped by it.
private struct TargetCrosshair: View {
    let isZoomed: Bool
    var body: some View {
        ZStack {
            // Dark backing so it stands out against both dark and light satellite imagery.
            Circle()
                .fill(.black.opacity(0.7))
                .frame(width: isZoomed ? 96 : 80, height: isZoomed ? 96 : 80)
                .shadow(color: .black.opacity(0.8), radius: 8, x: 0, y: 0)

            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: isZoomed ? 96 : 80, height: isZoomed ? 96 : 80)

            Circle()
                .stroke(.white, lineWidth: 1)
                .frame(width: isZoomed ? 56 : 48, height: isZoomed ? 56 : 48)

            Rectangle().fill(.white).frame(width: isZoomed ? 40 : 34, height: 2)
            Rectangle().fill(.white).frame(width: 2, height: isZoomed ? 40 : 34)
            Circle().fill(.white).frame(width: 8, height: 8)
        }
    }
}

private struct LineShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

private struct DistanceSelection: Identifiable {
    let id = UUID()
    let val: (meters: Double, label: String)
}
