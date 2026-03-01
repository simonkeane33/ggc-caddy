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
  @State private var dragTarget: CLLocationCoordinate2D? = nil
  @State private var selectedDistance: (meters: Double, label: String)? = nil
  @State private var isZoomedOnTarget: Bool = false

  var body: some View {
    MapReader { proxy in
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

        // Draw line from Tee -> Target -> Green
        if let tee = teeLocation, let g = greenCenter {
            let activeTarget = dragTarget ?? target ?? midPoint(tee, g)
            
            MapPolyline(coordinates: [tee, activeTarget, g])
                .stroke(.white.opacity(0.8), lineWidth: 2)
            
            // Distance Arc Rings around Target (18Birdies Style)
            if isZoomedOnTarget {
                ForEach([20.0, 40.0, 60.0], id: \.self) { radiusMeters in
                    MapCircle(center: activeTarget, radius: radiusMeters)
                        .foregroundStyle(.clear)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                }
            }
            
            // Current User/Tee Marker
            Annotation("Start", coordinate: tee) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.white)
                    .overlay(Circle().stroke(.black, lineWidth: 1))
            }
            
            // Movable Target (Crosshair)
            Annotation("Target", coordinate: activeTarget) {
                TargetCrosshair(isZoomed: isZoomedOnTarget)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if let coord = proxy.convert(value.location, from: .local) {
                                dragTarget = coord
                                recomputeDistances()
                                if !isZoomedOnTarget {
                                    withAnimation { isZoomedOnTarget = true }
                                }
                                updateCameraForTarget(coord)
                            }
                        }
                        .onEnded { value in
                            if let coord = proxy.convert(value.location, from: .local) {
                                target = coord
                                dragTarget = nil
                                recomputeDistances()
                                withAnimation { isZoomedOnTarget = false }
                                // Return to overview after a delay or keep focus?
                                // Let's snap back to overview.
                                snapToUser()
                            }
                        }
                )
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

        if let t = target {
          Annotation("Target", coordinate: t) {
            VStack(spacing: 4) {
              Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
              if let d = targetDistanceYd {
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
      }
      .mapStyle(.imagery)
      .ignoresSafeArea(edges: .bottom)
      .navigationTitle("Hole view")
      .navigationBarTitleDisplayMode(.inline)
      .overlay(alignment: .top) {
          if let tee = teeLocation, let g = greenCenter {
              let t = dragTarget ?? target ?? midPoint(tee, g)
              let distToTarget = distanceYards(from: tee, to: t)
              let distTargetToGreen = distanceYards(from: t, to: g)
              
              HStack(spacing: 20) {
                  Button {
                      selectedDistance = (meters: Double(distToTarget) / 1.09361, label: "TO TARGET")
                  } label: {
                      distancePill(label: "TO TARGET", value: "\(distToTarget)", color: .white)
                  }
                  .buttonStyle(.plain)
                  
                  Button {
                      selectedDistance = (meters: Double(distTargetToGreen) / 1.09361, label: "TO GREEN")
                  } label: {
                      distancePill(label: "TO GREEN", value: "\(distTargetToGreen)", color: .yellow)
                  }
                  .buttonStyle(.plain)
              }
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
      .safeAreaInset(edge: .bottom) {
        if let g = greenCenter, let tee = teeLocation {
            let activeTarget = dragTarget ?? target ?? midPoint(tee, g)
            let distToTarget = distanceYards(from: tee, to: activeTarget)
            let distTargetToGreen = distanceYards(from: activeTarget, to: g)
            
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack {
                        Text("Current Shot").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(distToTarget)y").font(.title2).bold().foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider().background(.white.opacity(0.3)).padding(.vertical, 10)
                    
                    VStack {
                        Text("To Green").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(distTargetToGreen)y").font(.title3).bold().foregroundStyle(.yellow)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 5)
                .padding(.bottom, 30) // Extra padding for home indicator
                .background(.black.opacity(0.8))
                
                // Bottom Action Row (Floating above the dark bar)
                HStack {
                    Button(action: { isZoomedOnTarget.toggle() }) {
                        Image(systemName: isZoomedOnTarget ? "minus.magnifyingglass" : "plus.magnifyingglass")
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Button("Set green") {
                      setGreenMode.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .offset(y: -75) // Move buttons up so they don't block the bar
            }
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(setGreenMode ? "Done" : "Set green") {
            setGreenMode.toggle()
          }
        }
      }
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

  private func updateCameraForTarget(_ coord: CLLocationCoordinate2D) {
      if isZoomedOnTarget {
          camera = .region(MKCoordinateRegion(
              center: coord,
              span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
          ))
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

private struct TargetCrosshair: View {
    let isZoomed: Bool
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: isZoomed ? 3 : 2)
                .background(Circle().fill(.black.opacity(0.3)))
                .frame(width: isZoomed ? 60 : 44, height: isZoomed ? 60 : 44)
            
            Rectangle().fill(.white).frame(width: isZoomed ? 30 : 20, height: 1)
            Rectangle().fill(.white).frame(width: 1, height: isZoomed ? 30 : 20)
            Circle().fill(.white).frame(width: 4, height: 4)
        }
    }
}

private struct DistanceSelection: Identifiable {
    let id = UUID()
    let val: (meters: Double, label: String)
}
