import SwiftUI
import MapKit
import CoreLocation
import UIKit
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
  /// Live camera heading — the compass direction pointing up the screen. The
  /// aerial map rotates (tee→green points up), so the wind arrow must subtract
  /// this to read correctly against the rotated map.
  @State private var cameraHeading: Double = 0
  /// True while the camera should re-centre on the player as they walk.
  /// Off by default — the resting view frames the hole (tee→green), and
  /// follow-me is a toggle the golfer switches on to track themselves. While
  /// following, the map holds the heading the user had when they enabled it
  /// (hole-up by default, but a compass reset to north-up is respected too),
  /// so the target overlay still reads correctly. Panning the map cancels
  /// follow so it stops fighting the user; rotating or zooming while staying
  /// centred is allowed and adopted into the follow state.
  @State private var followingUser: Bool = false
  /// The heading held while `followingUser` is on. Captured from
  /// `cameraHeading` when follow is enabled and updated if the user rotates
  /// during follow (their rotation is respected, only a pan cancels follow).
  @State private var followHeading: Double = 0
  /// Shown when the golfer taps follow-me with location access denied, to
  /// route them to Settings. (`UserAnnotation` and follow both need auth;
  /// `MainGameView` otherwise relies on the round/shot-logging flow having
  /// already obtained it, so this is the explicit denial surface.)
  @State private var showLocationDeniedAlert = false
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
  /// The distance pill the user tapped. Carries the shot's compass bearing as
  /// well as its length — the plays-like engine can't apply any wind adjustment
  /// without knowing which way the shot is being hit.
  @State private var selectedDistance: (meters: Double, label: String, bearing: Double?)? = nil
  @State private var showAbandonConfirm = false
  @State private var greenCenter: CLLocationCoordinate2D? = nil
  /// Live conditions for the wind read-out. Nil until the first fetch lands, or
  /// if it fails — the button shows "—" rather than inventing a figure.
  @State private var weather: WeatherConditions? = nil

  /// The direction the wind blows from, then the speed.
  private var windLabel: String {
    guard let weather else { return "—" }
    let speed = Int(weather.windSpeedKph.rounded())
    guard speed > 0 else { return "Calm" }
    let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    let normalised = (weather.windDirectionDegrees.truncatingRemainder(dividingBy: 360) + 360)
      .truncatingRemainder(dividingBy: 360)
    return "\(points[Int((normalised / 45).rounded()) % 8]) \(speed)"
  }

  /// Screen-space rotation (degrees, clockwise from up) for a wind-direction
  /// arrow that points the way the wind is blowing. `windDirectionDegrees` is
  /// the meteorological "from" direction, so the blow-toward bearing is +180.
  /// Subtracting the map's live heading keeps the arrow aligned with the
  /// rotated aerial map. Nil when there's no wind to point (calm / no data).
  private var windArrowRotation: Double? {
    guard let weather else { return nil }
    let speed = Int(weather.windSpeedKph.rounded())
    guard speed > 0 else { return nil }
    let toward = weather.windDirectionDegrees + 180
    let raw = toward - cameraHeading
    return (raw.truncatingRemainder(dividingBy: 360) + 360)
      .truncatingRemainder(dividingBy: 360)
  }

  /// Conditions read-out. Deliberately a capsule rather than one of the circular
  /// tool buttons, and not wrapped in a Button, so it doesn't read as tappable.
  private var windStatusChip: some View {
    HStack(spacing: 5) {
      Image(systemName: "wind").font(.system(size: 12, weight: .semibold))
      // Arrow pointing the way the wind is blowing, rotated to match the map.
      // No arrow when calm or before the first weather fetch lands.
      if let rotation = windArrowRotation {
        Image(systemName: "arrow.up")
          .font(.system(size: 11, weight: .black))
          .rotationEffect(.degrees(rotation))
      }
      Text(windLabel)
        .font(.system(size: 12, weight: .bold))
        .lineLimit(1)
    }
    .foregroundColor(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Wind \(windLabel)")
  }

  /// Custom compass dial for the header. A two-tone diamond needle (red
  /// north / light south) with "N" at the north tip rotates by the negative of
  /// the map's live heading so it always points to true north on the rotated
  /// map; tapping resets the map to north-up. Always visible — unlike
  /// MapCompass, which hides itself when the map is already north-up.
  private var compassControl: some View {
    Button {
      resetMapToNorth()
    } label: {
      ZStack {
        Circle().fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
        Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        // Compass rose — sized to the dial so it rotates about the dial centre.
        ZStack {
          CompassSouthHalf().fill(Color.white.opacity(0.55)).frame(width: 22, height: 22)
          CompassNorthHalf().fill(Color.red).frame(width: 22, height: 22)
          // N sits at the north tip; the offset is inside the rotating frame so
          // it orbits with the needle.
          Text("N")
            .font(.system(size: 8, weight: .heavy))
            .foregroundColor(.white)
            .offset(y: -16)
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(-cameraHeading))
        Circle().fill(Color.white).frame(width: 3, height: 3)
      }
      .frame(width: 44, height: 44)
      .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Compass")
    .accessibilityHint("Reset map to north up")
  }

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
          // Suppress the map's default controls — notably the compass, which
          // sits top-right under the status bar / dynamic island. An explicit
          // empty mapControls builder replaces the defaults. A custom compass
          // dial is rendered in the header instead.
          .mapControls {}
          .onMapCameraChange(frequency: .continuous) { context in
            drag.cameraDidChange()
            cameraDistance = context.camera.distance
            cameraHeading = context.camera.heading
            // Follow-me bookkeeping. Our own re-centre writes the user's
            // coordinate back as the camera centre, so it reads as ~0 m away
            // here; a real user pan moves the centre off the user and cancels
            // follow so we stop fighting them. While they stay centred, their
            // rotation and zoom are adopted into the follow state.
            if followingUser, let user = loc.lastLocation?.coordinate {
              let metresAway = distanceMeters(from: context.camera.centerCoordinate, to: user)
              if metresAway > 20 {
                followingUser = false
              } else {
                followHeading = context.camera.heading
              }
            }
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
              // Driven by the live camera distance alone, not the zoom button's
              // flag: pinching back out after pressing the button left that flag
              // set, so the rings lingered at wide zoom where they mean nothing.
              isZoomed: isZoomedIn,
              ringYardages: [5, 10, 15, 20, 30, 40],
              crosshairIdentifier: "mainTargetCrosshair",
              onCommit: { coord in
                var updated = targetByHole
                updated[state.holeNumber] = coord
                targetByHole = updated
              },
              accessory: { activeTarget, crosshairX, viewportWidth in
                // Default the pills to the LEFT of the target. The right edge
                // is occupied by the action-button column, so a right-side
                // placement often hides them behind those buttons; the left is
                // usually empty. Only fall back to the right when the target
                // is far enough left that a right placement clears the button
                // column — otherwise keep them left, even if that tucks them
                // near the left edge, which reads better than sitting behind
                // the buttons.
                let pillOffset: CGFloat = 100
                let pillHalfWidth: CGFloat = 80
                let rightButtonZone: CGFloat = 70
                let margin: CGFloat = 8
                let rightIsClean = crosshairX + pillOffset + pillHalfWidth + margin
                  <= viewportWidth - rightButtonZone
                VStack(spacing: 80) {
                  // Each pill's bearing matches the leg it measures, so the wind
                  // adjustment is computed for the shot actually being described.
                  distanceTag(meters: distanceMeters(from: activeTarget, to: g), label: "To Green", color: .white, identifier: "mainToGreenDistance",
                              bearing: bearing(from: activeTarget, to: g))
                  distanceTag(meters: distanceMeters(from: tee, to: activeTarget), label: "Current Shot", color: .black, identifier: "mainCurrentShotDistance",
                              bearing: bearing(from: tee, to: activeTarget))
                }
                .offset(x: rightIsClean ? pillOffset : -pillOffset, y: 0)
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
        // Trailing alignment keeps the circular buttons pinned to the right
        // edge. Centred, they would shift left to centre within the wider wind
        // capsule and overlap the distance pills.
        VStack(alignment: .trailing, spacing: 22) {
          // Read-out, not a control. It used to be a circular tool button with
          // an empty action, which sat in the action cluster and looked
          // tappable. Capsule shape and a wider gap separate it from the
          // buttons below.
          windStatusChip

          VStack(spacing: 12) {

          // Green Intelligence Button
          Menu {
            NavigationLink("Green View") {
              GreenMapView(holeNumber: state.holeNumber)
            }
            NavigationLink("3D Green View") {
              Green3DView(holeNumber: state.holeNumber, greenCenter: greenCenter)
            }
          } label: {
            toolButtonLabel(icon: "circle.circle.fill", label: "Green", background: Color.green.opacity(0.95))
          }

          toolButton(icon: isTargetZoomActive ? "minus.magnifyingglass" : "plus.magnifyingglass", label: "", action: toggleTargetZoom)

          // Follow-me / locate. Tapping enables follow: the map re-centres on
          // the player and tracks them as they walk, holding the current
          // heading. Tapping again (or panning the map) cancels follow. The
          // filled location glyph + accent background signal the active state.
          Button(action: toggleFollowUser) {
            toolButtonLabel(
              icon: followingUser ? "location.fill" : "location",
              label: followingUser ? "Following" : "Locate",
              background: followingUser
                ? Color.accentColor.opacity(0.9)
                : Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95)
            )
          }
          .accessibilityIdentifier("mainFollowButton")
          // Opens the per-hole note editor. HoleNotesView was already complete
          // and reads/writes through GCDB — it just had no entry point.
          NavigationLink {
            HoleNotesView(holeNumber: state.holeNumber)
          } label: {
            toolButtonLabel(icon: "doc.text.fill", label: "")
          }
          
          // Scorecard — moved up from the bottom wing so every action button
          // lives in the right-side group and the hole selector can span the
          // full width.
          NavigationLink {
            ScorecardView()
          } label: {
            toolButtonLabel(icon: "list.bullet.rectangle", label: "Scorecard")
          }
          .accessibilityIdentifier("mainScorecardButton")

          // Tools — a single merged menu. This replaces both the old ellipsis
          // menu that lived here (Scorecard, Complete round, Hole Insights,
          // Settings) and the wrench wing that sat at the bottom (Settings,
          // Course Intelligence, Complete round, Abandon round). Scorecard has
          // its own button above, so it isn't duplicated inside.
          Menu {
            if let rid = state.activeRoundId {
              NavigationLink("Complete round") {
                RoundStatsView(roundId: rid, course: state.course)
              }
            }
            NavigationLink("Hole Insights") { HoleInsightsView(holeNumber: state.holeNumber, course: state.course) }
            NavigationLink("Course Intelligence") { CourseIntelligenceView(course: state.course) }
            if state.activeRoundId != nil {
              Button("Abandon round", role: .destructive) { showAbandonConfirm = true }
            }
            NavigationLink("Settings") { SettingsView() }
          } label: {
            toolButtonLabel(icon: "wrench.and.screwdriver.fill", label: "Tools")
          }
          .accessibilityIdentifier("mainToolsMenu")
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
      // UserAnnotation and follow-me both need location auth. The round /
      // shot-logging flow usually obtained it already, but request here too
      // so the blue dot shows on a fresh entry to this screen.
      if loc.authorization == .notDetermined { loc.requestWhenInUse() }
      refreshStats()
      loadGreenCenter()
      applyHoleFramingIfNeeded()
    }
    .task {
      // WeatherService caches for 5 minutes, so re-entering this screen is cheap.
      weather = try? await WeatherService.shared.fetchCurrentWeather(
        lat: GreystonesElevationData.courseCenter.lat,
        lng: GreystonesElevationData.courseCenter.lng
      )
    }
    .onReceive(NotificationCenter.default.publisher(for: .greenCenterDidUpdate)) { _ in
      loadGreenCenter()
    }
    .onChange(of: state.holeNumber) { _, _ in
      // Framing takes over on a hole change — stop following so the camera
      // can re-frame tee→green without being pulled back to the player.
      followingUser = false
      loadGreenCenter()
      applyHoleFramingIfNeeded()
    }
    // While following, every new fix re-centres the map on the player. Not
    // animated: a per-step animation on each 5 m update reads as lag; the
    // initial enable is animated via `recenterOnUser` for a smooth pan.
    .onChange(of: loc.lastLocation) { _, newLocation in
      guard followingUser, let c = newLocation?.coordinate else { return }
      camera = .camera(MapCamera(
        centerCoordinate: c,
        distance: cameraDistance > 0 ? cameraDistance : framingDistance,
        heading: followHeading,
        pitch: 0
      ))
    }
    .alert("Location needed", isPresented: $showLocationDeniedAlert) {
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      Button("Not now", role: .cancel) {}
    } message: {
      Text("Follow-me needs location access to show your position on the map. Enable it in Settings.")
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
            shotBearing: selection.val.bearing
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
  
  /// One caption-over-value column of the header pill. Both lines are pinned to
  /// a single line and allowed to scale down, so the pill degrades by shrinking
  /// text rather than wrapping it.
  private func headerStat(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(value)
        .font(.title3.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func headerOverlay(_ hole: CourseBundle.Hole?) -> some View {
    // The pill is centred in the viewport with the back button overlaid at the
    // leading edge, rather than laid out in a row after it — in a plain HStack
    // the button's width pushed the pill permanently off-centre. The horizontal
    // padding on the pill keeps it clear of the button; if the content ever
    // needs more room than that leaves, the columns scale down instead.
    ZStack {
      if let hole {
        // Every label here is single-line and allowed to scale down. The
        // distance column previously used .fixedSize(), so an unexpectedly long
        // value (a GPS fix far from the course yields seven-figure yardages)
        // refused to shrink and squeezed the remaining columns until their text
        // wrapped one character per line.
        HStack(spacing: 14) {
          VStack(alignment: .leading) {
            Text("\(hole.number)").font(.title2.bold())
            Image(systemName: "arrowtriangle.down.fill").font(.caption2)
          }
          .onTapGesture { showHolePicker = true }

          headerStat("Mid Green", "\(Int(Distance.metresToYards(greenDistanceMeters)))Yds")
          headerStat("Par", "\(hole.par[state.tee])")
          headerStat(state.tee.rawValue.capitalized, "\(hole.distance_m[state.tee])")
          headerStat("HC", "\(Int(state.course.holes[hole.number-1].si[state.tee]))")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 52)
      }

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
        Spacer()
      }

      // Custom compass dial on the trailing edge of the header, level with the
      // info pill (the pill's 52pt side padding keeps it clear). Built by hand
      // rather than using MapCompass — the standalone control proved unreliable
      // to reposition (wouldn't rotate / stay visible outside the map's default
      // control set). The needle rotates with the live camera heading and taps
      // to reset the map to north-up.
      HStack {
        Spacer()
        compassControl
      }
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
  
  private func distanceTag(meters: Double, label: String, color: Color, identifier: String? = nil, bearing: Double? = nil) -> some View {
      Button {
          selectedDistance = (meters: meters, label: label, bearing: bearing)
      } label: {
          HStack(spacing: 0) {
              Text("\(Int(Distance.metresToYards(meters)))y")
                  .font(.system(size: 16, weight: .heavy))
                  .padding(.horizontal, 12)
                  .padding(.vertical, 8)
                  .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                  .foregroundColor(.white)
                  .accessibilityIdentifier(identifier ?? "")
              
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
          // Stronger outline than the rest of the overlays — the material pill
          // would otherwise bleed into the aerial imagery, and this is the
          // primary action on the screen.
          .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
          .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
      }
      
      // Primary Hole Selector — spans the full width now that the Scorecard
      // and Tools wings have moved into the right-side button group.
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
      .padding(.horizontal)
      .padding(.bottom, 8) // Anchor to bottom edge
    }
  }

  private func toolButton(icon: String, label: String, action: (() -> Void)? = nil) -> some View {
      Button(action: { action?() }) {
          toolButtonLabel(icon: icon, label: label)
      }
  }

  /// The tool-button visual on its own, so it can back either a `Button` or a
  /// `NavigationLink`. Rectangular with a small corner radius rather than
  /// circular, so a caption (e.g. "Scorecard") fits without being clipped by
  /// the curve.
  private func toolButtonLabel(
    icon: String,
    label: String,
    background: Color = Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95)
  ) -> some View {
      VStack(spacing: 4) {
          Image(systemName: icon).font(.title3)
          if !label.isEmpty {
              Text(label).font(.system(size: 8, weight: .bold))
          }
      }
      .frame(width: 56, height: 48)
      .background(background)
      .foregroundColor(.white)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
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
  
  private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
      Geo.bearingDegrees(lat1: from.latitude, lng1: from.longitude, lat2: to.latitude, lng2: to.longitude)
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

  /// Resets the map heading to north-up while keeping the current centre and
  /// distance. Bound to the header compass tap.
  private func resetMapToNorth() {
      guard let cam = camera.camera else { return }
      withAnimation(.easeInOut(duration: Self.framingAnimationDuration)) {
          camera = .camera(MapCamera(
              centerCoordinate: cam.centerCoordinate,
              distance: cam.distance,
              heading: 0,
              pitch: 0
          ))
      }
  }

  /// Toggles follow-me. Enabling captures the current heading (so the map
  /// stays oriented the way it is — hole-up, or north-up after a compass reset)
  /// and re-centres on the player once for a smooth pan; subsequent fixes
  /// re-centre via `onChange(loc.lastLocation)`. Disabling just flips the flag.
  /// Handles the auth states explicitly: not-determined prompts, denied routes
  /// to Settings via `showLocationDeniedAlert`.
  private func toggleFollowUser() {
      if followingUser {
          followingUser = false
          return
      }
      switch loc.authorization {
      case .notDetermined:
          loc.requestWhenInUse()
      case .denied, .restricted:
          showLocationDeniedAlert = true
      default:
          followingUser = true
          followHeading = cameraHeading
          recenterOnUser()
      }
  }

  /// Centres the map on the player's current fix, keeping the follow heading
  /// and the live zoom. Animated so the initial enable reads as a smooth pan
  /// rather than a jump.
  private func recenterOnUser() {
      guard let c = loc.lastLocation?.coordinate else { return }
      withAnimation(.easeInOut(duration: Self.framingAnimationDuration)) {
          camera = .camera(MapCamera(
              centerCoordinate: c,
              distance: cameraDistance > 0 ? cameraDistance : framingDistance,
              heading: followHeading,
              pitch: 0
          ))
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
        .foregroundStyle(.white.opacity(0.8))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(events.enumerated()), id: \.element.id) { idx, e in
            // Solid dark fill with white content, matching the other map
            // overlays. These chips previously used .ultraThinMaterial with
            // .secondary text, which over bright satellite imagery rendered as
            // grey-on-grey and failed contrast badly.
            HStack(spacing: 6) {
              Text(e.kind == .shot ? "#\(idx + 1)" : "P")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
              Text(e.kind == .shot ? e.club.rawValue : "+\(e.penaltyStrokes ?? 1)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
              Button {
                editEvent = e
              } label: {
                Image(systemName: "pencil")
                  .font(.caption)
                  .foregroundStyle(.white)
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
            .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
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
    let val: (meters: Double, label: String, bearing: Double?)
}

/// Top (north) half of the compass needle: a triangle with its apex at the top
/// of the rect and its base across the middle.
private struct CompassNorthHalf: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.midX, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX, y: r.midY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
    p.closeSubpath()
    return p
  }
}

/// Bottom (south) half of the compass needle: apex at the bottom, base across
/// the middle. Combined with `CompassNorthHalf` it forms a diamond.
private struct CompassSouthHalf: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.midX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.midY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
    p.closeSubpath()
    return p
  }
}
