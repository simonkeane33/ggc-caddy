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
  @State private var dragTarget: CLLocationCoordinate2D? = nil
  @State private var target: CLLocationCoordinate2D? = nil
  @State private var isZoomedOnTarget: Bool = false
  
  // Scoring state
  @State private var strokes: Int = 0
  @State private var putts: Int = 0
  @State private var penalties: Int = 0
  @State private var events: [HoleEvent] = []
  
  // UI state
  @State private var showShotConfirm: Bool = false
  @State private var pendingFix: (lat: Double, lng: Double, hAcc: Double?)? = nil
  @State private var showHolePicker = false
  @State private var selectedDistance: (meters: Double, label: String)? = nil
  @State private var showEndRoundConfirm = false
  @State private var summaryRound: RoundSummary? = nil
  @State private var greenCenter: CLLocationCoordinate2D? = nil

  var body: some View {
    let hole = state.currentHole
    
    ZStack {
      // 1. PRIMARY MAP LAYER
      MapReader { proxy in
        Map(position: $camera) {
          UserAnnotation()
          
          if let tee = teeLocation, let g = greenCenter {
            let activeTarget = dragTarget ?? target ?? midPoint(tee, g)
            
            // Smoother Line Logic
            MapPolyline(coordinates: [tee, activeTarget, g])
              .stroke(.white.opacity(0.8), lineWidth: 2)
            
            Annotation("Target", coordinate: activeTarget) {
              ZStack {
                TargetCrosshair(isZoomed: isZoomedOnTarget)
                
                // 18Birdies style: Fixed logic for pill positioning
                // Using longitude difference from green center to decide side
                let isRightOfGreen = activeTarget.longitude > (greenCenter?.longitude ?? 0)
                let xOffset: CGFloat = isRightOfGreen ? -100 : 100
                
                VStack(spacing: 80) { 
                    distanceTag(meters: distanceMeters(from: activeTarget, to: g), label: "To Green", color: .white)
                    distanceTag(meters: distanceMeters(from: tee, to: activeTarget), label: "Current Shot", color: .black)
                }
                .offset(x: xOffset, y: 0)
              }
              .contentShape(Circle())
              .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                  .onChanged { value in
                      if let coord = proxy.convert(value.location, from: .global) {
                          dragTarget = coord
                          if !isZoomedOnTarget {
                              withAnimation(.easeOut(duration: 0.2)) {
                                  isZoomedOnTarget = true
                              }
                          }
                      }
                  }
                  .onEnded { value in
                      if let coord = proxy.convert(value.location, from: .global) {
                          target = coord
                          dragTarget = nil
                          withAnimation(.easeIn(duration: 0.2)) {
                              isZoomedOnTarget = false
                          }
                      }
                  }
              )
            }
          }
          
          // Green points
          if let g = greenCenter {
            Annotation("Green", coordinate: g) {
              Image(systemName: "flag.circle.fill").font(.title2).foregroundStyle(.green)
            }
          }
        }
        .mapStyle(.imagery)
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

          toolButton(icon: "plus", label: "")
          toolButton(icon: "doc.text.fill", label: "")
          
          Menu {
              NavigationLink("Scorecard") { ScorecardView() }
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
      snapToUser()
      loadGreenCenter()
    }
    .onReceive(NotificationCenter.default.publisher(for: .greenCenterDidUpdate)) { _ in
      loadGreenCenter()
    }
    .onChange(of: state.holeNumber) { _, _ in
      loadGreenCenter()
      snapToUser()
    }
    .sheet(isPresented: $showHolePicker) {
      HolePickerSheet(currentHole: state.holeNumber, course: state.course) { hn in
        state.holeNumber = hn
        refreshStats()
        snapToUser()
        showHolePicker = false
      }
    }
    .sheet(isPresented: $showShotConfirm) {
        ShotConfirmSheet(club: $state.selectedClub, shotType: $state.shotType, holeNumber: state.holeNumber, accuracy: pendingFix?.hAcc, onCancel: { showShotConfirm = false }, onConfirm: { confirmLogShot() })
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
                NavigationLink("Settings") { SettingsView() }
                NavigationLink("Course Intelligence") { CourseIntelligenceView(course: state.course) }
                Button("End Round", role: .destructive) { showEndRoundConfirm = true }
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill").font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.95))
                    .foregroundColor(.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
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
  
  private func updateCameraForTarget(_ coord: CLLocationCoordinate2D) {
      if isZoomedOnTarget {
          camera = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)))
      }
  }
  
  private func snapToUser() {
      if let g = greenCenter, let tee = teeLocation {
          let centerLat = (g.latitude + tee.latitude) / 2
          let centerLng = (g.longitude + tee.longitude) / 2
          let spanLat = abs(g.latitude - tee.latitude) * 1.5
          let spanLng = abs(g.longitude - tee.longitude) * 1.5
          camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng), span: MKCoordinateSpan(latitudeDelta: max(spanLat, 0.005), longitudeDelta: max(spanLng, 0.005))))
      }
  }
  
  private func refreshStats() {
      guard let rid = state.activeRoundId else { return }
      strokes = (try? GCDB.shared.strokesForHole(roundId: rid, holeNumber: state.holeNumber)) ?? 0
      events = (try? GCDB.shared.fetchHoleEvents(roundId: rid, holeNumber: state.holeNumber)) ?? []
  }
  
  private func beginLogShot() {
      if let l = loc.lastLocation {
          pendingFix = (l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy)
          showShotConfirm = true
      }
  }
  
  private func confirmLogShot() {
      guard let rid = state.activeRoundId, let fix = pendingFix else { return }
      try? GCDB.shared.addShot(roundId: rid, holeNumber: state.holeNumber, location: fix, club: state.selectedClub, shotType: state.shotType)
      refreshStats()
      showShotConfirm = false
  }
}

private struct TargetCrosshair: View {
    let isZoomed: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: isZoomed ? 3 : 2).background(Circle().fill(.black.opacity(0.3))).frame(width: isZoomed ? 60 : 44, height: isZoomed ? 60 : 44)
            Rectangle().fill(.white).frame(width: isZoomed ? 30 : 20, height: 1)
            Rectangle().fill(.white).frame(width: 1, height: isZoomed ? 30 : 20)
            Circle().fill(.white).frame(width: 4, height: 4)
        }
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
