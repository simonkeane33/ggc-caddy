import SwiftUI
import MapKit
import CoreLocation
import GreystonesCaddyCore

struct MainGameView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var state: AppState
  @StateObject var loc = LocationProvider()

  // Map state
  @State private var camera: MapCameraPosition = .automatic
  /// Live target position while a drag is in flight. `@State` rather than
  /// `@StateObject` on purpose — see `TargetDragState`.
  @State private var drag = TargetDragState()
  /// Per-hole target; nil = use default (midpoint tee↔green). Never persists across holes.
  @State private var targetByHole: [Int: CLLocationCoordinate2D] = [:]
  /// Last hole we applied framing for; avoids re-framing when returning from Scorecard etc.
  @State private var lastFramedHole: Int? = nil
  /// The camera distance (metres of altitude) `applyHoleFramingIfNeeded` set for
  /// the current hole. Compared against the live camera distance to tell
  /// whether the user has pinched in past the initial framing.
  @State private var framingDistance: Double = 0
  /// Live camera distance, updated continuously as the user pans/pinches.
  @State private var cameraDistance: Double = 0
  /// True once the user has pinched in noticeably closer than the initial
  /// hole-framing shot. Drives the finer distance rings and the enlarged
  /// crosshair, matching the aerial view's manual zoom toggle but driven by
  /// the actual map zoom instead.
  private var isZoomedIn: Bool {
    framingDistance > 0 && cameraDistance < framingDistance * 0.6
  }
  /// True while `toggleTargetZoom` has driven the camera in. ORed into the
  /// rings/crosshair condition below so they appear the instant the button is
  /// pressed rather than waiting for `cameraDistance` to catch up with the
  /// in-flight camera animation.
  @State private var isTargetZoomActive: Bool = false
  
  // Scoring state
  @State private var strokes: Int = 0
  @State private var putts: Int = 0
  @State private var penalties: Int = 0
  @State private var events: [HoleEvent] = []
  
  // UI state
  @State private var showShotConfirm: Bool = false
  @State private var pendingFix: (lat: Double, lng: Double, alt: Double?, hAcc: Double?)? = nil
  @State private var editEvent: HoleEvent? = nil
  @State private var showHolePicker = false
  @State private var selectedDistance: (meters: Double, label: String)? = nil
  @State private var showAbandonConfirm = false
  @State private var greenCenter: CLLocationCoordinate2D? = nil

  var body: some View {
    let hole = state.currentHole
    
    ZStack {
      // 1. PRIMARY MAP LAYER
      MapReader { proxy in
        ZStack {
          // `bounds:` is a `Map` initializer parameter, not a view modifier.
          // MapKit's default minimum camera distance is much further out than
          // it needs to be for a short-game/putting view — this lets a pinch
          // zoom in close enough to place the target with real precision.
          Map(position: $camera, bounds: MapCameraBounds(minimumDistance: 15, maximumDistance: nil)) {
            UserAnnotation()

            // Green points
            if let g = greenCenter {
              Annotation("Green", coordinate: g) {
                Image(systemName: "flag.circle.fill").font(.title2).foregroundStyle(.green)
              }
            }
          }
          .mapStyle(.imagery)
          .onMapCameraChange(frequency: .continuous) { context in
            drag.cameraDidChange()
            cameraDistance = context.camera.distance
          }

          // The target line and crosshair are drawn in SwiftUI screen space
          // rather than as a MapPolyline and an Annotation. Re-coordinating
          // those on every drag frame made the target trail the finger and the
          // line trail the target: MapKit animates annotation moves internally
          // and draws overlays on a separate thread. Here a drag only re-renders
          // this overlay, so the line stays pinned to the crosshair.
          if let tee = teeLocation, let g = greenCenter {
            TargetGuideOverlay(
              proxy: proxy,
              drag: drag,
              tee: tee,
              green: g,
              committedTarget: targetByHole[state.holeNumber] ?? midPoint(tee, g),
              isZoomed: isZoomedIn || isTargetZoomActive,
              ringYardages: [5, 10, 15, 20],
              crosshairIdentifier: "mainTargetCrosshair",
              onCommit: { coord in
                var updated = targetByHole
                updated[state.holeNumber] = coord
                targetByHole = updated
              },
              accessory: { activeTarget, isRightOfViewport in
                // Anchor the pills on the side of the crosshair away from
                // whichever screen edge it's nearest, so dragging the target
                // toward either edge doesn't push them off-screen.
                VStack(spacing: 80) {
                  distanceTag(meters: distanceMeters(from: activeTarget, to: g), label: "To Green", color: .white)
                  distanceTag(meters: distanceMeters(from: tee, to: activeTarget), label: "Current Shot", color: .black)
                }
                .offset(x: isRightOfViewport ? -100 : 100, y: 0)
              }
            )
          }
        }
        // Both the map and the overlay must span the same rect, otherwise the
        // overlay's local space is offset from the map's and the crosshair
        // renders away from the line.
        .ignoresSafeArea()
      }
      
      // 2. TOP OVERLAY: HOLE INFO PILL
      VStack {
        headerOverlay(hole)
        Spacer()
      }
      
      // 3. RIGHT SIDEBAR: TOOLS
      HStack {
        Spacer()
        VStack(spacing: 12) {
          toolButton(icon: "wind", label: "12 mph")
          
          // Green Intelligence Button
          Menu {
            NavigationLink("Green View") {
              GreenMapView(holeNumber: state.holeNumber)
            }
            NavigationLink("3D Green View") {
              Green3DView(holeNumber: state.holeNumber, greenCenter: greenCenter)
            }
          } label: {
            VStack(spacing: 4) {
              Image(systemName: "circle.circle.fill").font(.title3)
              Text("Green").font(.system(size: 8, weight: .bold))
            }
            .frame(width: 48, height: 48)
            .background(Color.green.opacity(0.95))
            .foregroundColor(.white)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
          }

          toolButton(icon: isTargetZoomActive ? "minus.magnifyingglass" : "plus.magnifyingglass", label: "", action: toggleTargetZoom)
          toolButton(icon: "doc.text.fill", label: "")
          
          Menu {
              NavigationLink("Scorecard") { ScorecardView() }
              if state.activeRoundId != nil {
                NavigationLink("Complete round") {
                  RoundStatsView(roundId: state.activeRoundId!, course: state.course)
                }
              }
              NavigationLink("Hole Insights") { HoleInsightsView(holeNumber: state.holeNumber, course: state.course) }
              NavigationLink("Settings") { SettingsView() }
          } label: {
              toolButton(icon: "ellipsis.circle", label: "Tools")
          }
        }
        .padding(.trailing, 12)
      }
      
      // 4. BOTTOM OVERLAY: CONTROLS
      VStack {
        Spacer()
        bottomControlsSection
      }
    }
    .navigationBarHidden(true)
    .onAppear {
      refreshStats()
      loadGreenCenter()
      applyHoleFramingIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .greenCenterDidUpdate)) { _ in
      loadGreenCenter()
    }
    .onChange(of: state.holeNumber) { _, _ in
      loadGreenCenter()
      applyHoleFramingIfNeeded()
    }
    .sheet(isPresented: $showHolePicker) {
      HolePickerSheet(currentHole: state.holeNumber, course: state.course) { hn in
        state.holeNumber = hn
        refreshStats()
        showHolePicker = false
      }
    }
    .sheet(isPresented: $showShotConfirm) {
        ShotConfirmSheet(club: $state.selectedClub, shotType: $state.shotType, holeNumber: state.holeNumber, accuracy: pendingFix?.hAcc, onCancel: { showShotConfirm = false }, onConfirm: { confirmLogShot() })
    }
    .sheet(item: $editEvent) { event in
      NavigationStack {
        EventEditView(event: event)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { editEvent = nil }
            }
          }
          .onDisappear { refreshStats() }
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
    .alert("Abandon round?", isPresented: $showAbandonConfirm) {
      Button("Abandon round", role: .destructive) { performAbandon() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This round will be marked abandoned and kept in history. You can view it later in round history.")
    }
  }

  private func performAbandon() {
    guard let rid = state.activeRoundId else { return }
    do {
      try GCDB.shared.abandonRound(roundId: rid)
    } catch {
      return
    }
    state.activeRoundId = nil
    state.holeNumber = 1
    state.abandonTriggered = true
    dismiss()
  }
  
  // MARK: - Components
  
  private func headerOverlay(_ hole: CourseBundle.Hole?) -> some View {
    HStack {
      Button { dismiss() } label: {
        Image(systemName: "chevron.left")
          .font(.title3).bold()
          .padding(10)
          .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
      }
      
      if let hole {
        HStack(spacing: 20) {
          VStack(alignment: .leading) {
            Text("\(hole.number)").font(.title.bold())
            Image(systemName: "arrowtriangle.down.fill").font(.caption)
          }
          .onTapGesture { showHolePicker = true }
          
          VStack(alignment: .leading, spacing: 2) {
            Text("Mid Green").font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Text("\(Int(Distance.metresToYards(greenDistanceMeters)))Yds")
                .font(.title2.bold())
                .lineLimit(1)
                .fixedSize()
          }
          
          VStack(alignment: .leading, spacing: 2) {
            Text("Par").font(.caption).foregroundStyle(.secondary)
            Text("\(hole.par[state.tee])").font(.title2.bold())
          }
          
          VStack(alignment: .leading, spacing: 2) {
            Text(state.tee.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            Text("\(hole.distance_m[state.tee])").font(.title2.bold())
          }
          
          VStack(alignment: .leading, spacing: 2) {
            Text("HC").font(.caption).foregroundStyle(.secondary)
            Text("\(Int(state.course.holes[hole.number-1].si[state.tee]))").font(.title2.bold())
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
      }
      
      Spacer()
    }
    .padding(.horizontal)
    .padding(.top, 8)
    .foregroundColor(.white)
  }

  private func targetDistanceTags(tee: CLLocationCoordinate2D, target: CLLocationCoordinate2D, green: CLLocationCoordinate2D) -> some View {
      VStack(spacing: 40) {
          distanceTag(meters: distanceMeters(from: target, to: green), label: "To Green", color: .white)
          distanceTag(meters: distanceMeters(from: tee, to: target), label: "Current Shot", color: .black)
      }
      .padding(.leading, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
  
  private func distanceTag(meters: Double, label: String, color: Color) -> some View {
      Button {
          selectedDistance = (meters: meters, label: label)
      } label: {
          HStack(spacing: 0) {
              Text("\(Int(Distance.metresToYards(meters)))y")
                  .font(.system(size: 16, weight: .heavy))
                  .padding(.horizontal, 12)
                  .padding(.vertical, 8)
                  .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                  .foregroundColor(.white)
              
              HStack(spacing: 4) {
                  VStack(alignment: .leading, spacing: 0) {
                      Text("PLAYS LIKE")
                          .font(.system(size: 8, weight: .regular))
                          .foregroundColor(Color(white: 0.4))
                      Text("\(Int(Distance.metresToYards(meters * 1.05)))y")
                          .font(.system(size: 16, weight: .bold))
                          .foregroundColor(.black)
                  }
                  Image(systemName: "chevron.right")
                      .font(.system(size: 10, weight: .light))
                      .foregroundColor(Color(white: 0.4))
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(.white)
          }
          .clipShape(Capsule())
          .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
      }
      .buttonStyle(.plain)
  }

  private var bottomControlsSection: some View {
    VStack(spacing: 16) {
      if !events.isEmpty {
        holeShotsList
      }

      Button(action: { beginLogShot() }) {
        Label("Track Shot", systemImage: "mappin.and.ellipse")
          .font(.headline)
          .padding(.horizontal, 40)
          .padding(.vertical, 12) // Low profile pill
          .background(.ultraThinMaterial)
          .foregroundColor(.white)
          .clipShape(Capsule())
          .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
      }
      
      HStack(alignment: .center, spacing: 12) {
        // Scorecard Wing
        VStack(spacing: 4) {
            NavigationLink(destination: ScorecardView()) {
                Image(systemName: "list.bullet.rectangle").font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .accessibilityIdentifier("mainScorecardButton")
            Text("Scorecard").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
        }
        
        // Primary Hole Selector
        HStack {
            Button(action: { 
                if state.holeNumber > 1 { state.holeNumber -= 1 }
            }) {
                Image(systemName: "chevron.left")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14) // Increased vertical padding
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Hole \(state.holeNumber)").bold()
                Text("Enter Score").font(.caption)
            }
            .padding(.vertical, 6) // Internal padding for content
            .onTapGesture { showHolePicker = true }
            
            Spacer()
            
            Button(action: { 
                if state.holeNumber < 18 { state.holeNumber += 1 }
            }) {
                Image(systemName: "chevron.right")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14) // Increased vertical padding
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.blue)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        
        // Tools Wing
        VStack(spacing: 4) {
            Menu {
                NavigationLink("Aerial View") { HoleAerialView() }
                NavigationLink("Settings") { SettingsView() }
                NavigationLink("Course Intelligence") { CourseIntelligenceView(course: state.course) }
                if let rid = state.activeRoundId {
                  NavigationLink("Complete round") {
                    RoundStatsView(roundId: rid, course: state.course)
                  }
                  Button("Abandon round", role: .destructive) { showAbandonConfirm = true }
                }
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill").font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .accessibilityIdentifier("mainToolsMenu")
            Text("Tools").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 8) // Anchor to bottom edge
    }
  }

  private func toolButton(icon: String, label: String, action: (() -> Void)? = nil) -> some View {
      Button(action: { action?() }) {
          VStack(spacing: 4) {
              Image(systemName: icon).font(.title3)
              if !label.isEmpty && icon == "wind" {
                  Text(label).font(.system(size: 8, weight: .bold))
              }
          }
          .frame(width: 48, height: 48)
          .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
          .foregroundColor(.white)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
      }
  }

  // MARK: - Helpers & Data
  
  private var teeLocation: CLLocationCoordinate2D? {
      if let tee = try? GCDB.shared.fetchTeeLocation(holeNumber: state.holeNumber, tee: state.tee) {
          return CLLocationCoordinate2D(latitude: tee.lat, longitude: tee.lng)
      }
      return loc.lastLocation?.coordinate
  }

  private func loadGreenCenter() {
      if let g = try? GCDB.shared.fetchGreenCenter(holeNumber: state.holeNumber) {
          greenCenter = CLLocationCoordinate2D(latitude: g.centerLat, longitude: g.centerLng)
      } else {
          greenCenter = nil
      }
  }
  
  private var greenDistanceMeters: Double {
      guard let l = loc.lastLocation, let g = greenCenter else { return 0 }
      return l.distance(from: CLLocation(latitude: g.latitude, longitude: g.longitude))
  }
  
  private func distanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
      CLLocation(latitude: from.latitude, longitude: from.longitude)
          .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
  }

  private func midPoint(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
      CLLocationCoordinate2D(latitude: (c1.latitude + c2.latitude) / 2, longitude: (c1.longitude + c2.longitude) / 2)
  }

  // MARK: - Hole framing (hole-map-framing-and-target-behaviour)
  // v1: Tee + green center anchors; MapCamera with heading; overlay-safe padding; animated.
  // Apply only on round start and hole change — not when returning to same hole.
  private static let framingAnimationDuration: Double = 0.4
  /// Overlay-safe: tee and green must stay clear of top/bottom overlays. Refined after live testing.
  private static let overlaySafeSpanMultiplier: Double = 2.0
  private static let cameraDistanceMultiplier: Double = 3.0

  /// The tee-green overview shot: computed independently of `lastFramedHole`
  /// so `toggleTargetZoom` can jump straight back to it without being blocked
  /// by the "already framed this hole" guard in `applyHoleFramingIfNeeded`.
  private func framedOverviewCamera(tee: CLLocationCoordinate2D, green g: CLLocationCoordinate2D) -> (position: MapCameraPosition, distance: Double) {
      let lat1 = tee.latitude * .pi / 180
      let lon1 = tee.longitude * .pi / 180
      let lat2 = g.latitude * .pi / 180
      let lon2 = g.longitude * .pi / 180
      let dLon = lon2 - lon1
      let y = sin(dLon) * cos(lat2)
      let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
      let heading = atan2(y, x) * 180 / .pi

      let centerLat = (g.latitude + tee.latitude) / 2
      let centerLng = (g.longitude + tee.longitude) / 2
      let spanMeters = max(Geo.distanceMetres(lat1: tee.latitude, lng1: tee.longitude, lat2: g.latitude, lng2: g.longitude), 100)
      let distance = spanMeters * Self.cameraDistanceMultiplier

      let position = MapCameraPosition.camera(MapCamera(
          centerCoordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
          distance: distance,
          heading: heading,
          pitch: 0
      ))
      return (position, distance)
  }

  private func applyHoleFramingIfNeeded() {
      guard lastFramedHole != state.holeNumber else { return }
      guard let g = greenCenter, let tee = teeLocation else { return }

      lastFramedHole = state.holeNumber

      let framed = framedOverviewCamera(tee: tee, green: g)
      framingDistance = framed.distance
      cameraDistance = framed.distance

      withAnimation(.easeInOut(duration: Self.framingAnimationDuration)) {
          camera = framed.position
      }
  }

  /// Jumps the camera straight to a tight shot on the current target, or back
  /// to the tee-green overview, instead of leaving zooming to a pinch gesture.
  private func toggleTargetZoom() {
      guard let tee = teeLocation, let g = greenCenter else { return }
      isTargetZoomActive.toggle()
      withAnimation(.easeInOut(duration: Self.framingAnimationDuration)) {
          if isTargetZoomActive {
              let activeTarget = targetByHole[state.holeNumber] ?? midPoint(tee, g)
              camera = .camera(MapCamera(
                  centerCoordinate: activeTarget,
                  distance: 40,
                  heading: camera.camera?.heading ?? 0,
                  pitch: 0
              ))
          } else {
              camera = framedOverviewCamera(tee: tee, green: g).position
          }
      }
  }

  private func refreshStats() {
      guard let rid = state.activeRoundId else { return }
      strokes = (try? GCDB.shared.strokesForHole(roundId: rid, holeNumber: state.holeNumber)) ?? 0
      events = (try? GCDB.shared.fetchHoleEvents(roundId: rid, holeNumber: state.holeNumber)) ?? []
  }
  
  private var holeShotsList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Hole \(state.holeNumber) shots")
        .font(.caption)
        .foregroundStyle(.secondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(events.enumerated()), id: \.element.id) { idx, e in
            HStack(spacing: 6) {
              Text(e.kind == .shot ? "#\(idx + 1)" : "P")
                .font(.caption2)
                .foregroundStyle(.secondary)
              Text(e.kind == .shot ? e.club.rawValue : "+\(e.penaltyStrokes ?? 1)")
                .font(.subheadline.bold())
              Button {
                editEvent = e
              } label: {
                Image(systemName: "pencil")
                  .font(.caption)
              }
              .buttonStyle(.plain)
              Button {
                try? GCDB.shared.deleteEvent(id: e.id)
                refreshStats()
              } label: {
                Image(systemName: "trash")
                  .font(.caption)
                  .foregroundStyle(.red)
              }
              .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
          }
        }
        .padding(.horizontal, 4)
      }
    }
    .padding(.horizontal)
  }

  private func beginLogShot() {
      if let l = loc.lastLocation {
          let alt: Double? = (l.altitude >= 0) ? l.altitude : nil
          pendingFix = (l.coordinate.latitude, l.coordinate.longitude, alt, l.horizontalAccuracy)
          showShotConfirm = true
      }
  }
  
  private func confirmLogShot() {
      guard let rid = state.activeRoundId, let fix = pendingFix else { return }
      try? GCDB.shared.addShot(roundId: rid, holeNumber: state.holeNumber, location: (fix.lat, fix.lng, fix.alt, fix.hAcc), club: state.selectedClub, shotType: state.shotType)
      refreshStats()
      showShotConfirm = false
  }
}

// MARK: - Hole Picker Sheet

private struct HolePickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  
  let currentHole: Int
  let course: CourseBundle
  let onSelect: (Int) -> Void
  
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
          ForEach(course.holes) { hole in
            Button {
              onSelect(hole.number)
            } label: {
              VStack(spacing: 4) {
                Text("\(hole.number)")
                  .font(.system(.title2, design: .rounded, weight: .bold))
                
                Text("Par \(hole.par[.blue])")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .frame(width: 60, height: 70)
              .background(hole.number == currentHole ? Color.blue.opacity(0.2) : Color(.systemGray6))
              .foregroundColor(hole.number == currentHole ? .blue : .primary)
              .cornerRadius(10)
              .overlay(
                RoundedRectangle(cornerRadius: 10)
                  .stroke(hole.number == currentHole ? Color.blue : Color.clear, lineWidth: 2)
              )
            }
            .buttonStyle(.plain)
          }
        }
        .padding()
      }
      .navigationTitle("Jump to Hole")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

private struct ShotConfirmSheet: View {
  @Binding var club: ClubID
  @Binding var shotType: ShotType

  let holeNumber: Int
  let accuracy: Double?
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            Text("Hole")
            Spacer()
            Text("\(holeNumber)")
              .foregroundStyle(.secondary)
          }

          HStack {
            Text("GPS")
            Spacer()
            if let a = accuracy {
              Text("±\(Int(a)) m")
                .foregroundStyle(.secondary)
            } else {
              Text("—")
                .foregroundStyle(.secondary)
            }
          }
        }

        Section("Shot") {
          Picker("Club", selection: $club) {
            ForEach(ClubID.allCases) { c in
              Text(c.rawValue).tag(c)
            }
          }

          Picker("Type", selection: $shotType) {
            Text("Full").tag(ShotType.full)
            Text("3/4").tag(ShotType.threeQuarter)
            Text("Half").tag(ShotType.half)
            Text("Chip").tag(ShotType.chip)
          }
        }

        Section {
          VStack(spacing: 12) {
            Button {
              onConfirm()
            } label: {
              Text("Confirm log")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
              onCancel()
            } label: {
              Text("Cancel")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .navigationTitle("Confirm shot")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

private struct DistanceSelection: Identifiable {
    let id = UUID()
    let val: (meters: Double, label: String)
}
