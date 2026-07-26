import SwiftUI
import CoreLocation
import GreystonesCaddyCore

struct LiveHoleView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var state: AppState
  @StateObject var loc = LocationProvider()

  @State private var info: String? = nil
  @State private var events: [HoleEvent] = []
  @State private var strokes: Int = 0
  @State private var putts: Int = 0
  @State private var penalties: Int = 0
  @State private var caddyTip: String? = nil
  @State private var holePlanTip: String? = nil
  @State private var holeTarget: String? = nil
  @State private var holeAvoid: String? = nil

  @State private var scoreGross: Int = 0
  @State private var scoreNet: Int = 0
  @State private var scoreNetToPar: Int = 0
  @State private var scorePts: Int? = nil

  @State private var showAbandonConfirm: Bool = false

  @State private var showShotConfirm: Bool = false
  @State private var pendingFix: (lat: Double, lng: Double, alt: Double?, hAcc: Double?)? = nil
  @State private var pendingClub: ClubID = .driver
  @State private var pendingShotType: ShotType = .full

  @State private var toastText: String? = nil
  @State private var toastEvent: HoleEvent? = nil
  @State private var showToast: Bool = false
  @State private var editEvent: HoleEvent? = nil
  @State private var showHolePicker = false
  
  // Hole summary before navigating
  @State private var showHoleSummary = false
  @State private var pendingHoleNavigation: Int? = nil

  var body: some View {
    let hole = state.currentHole

    ScrollView {
      VStack(spacing: 16) {
        header(hole)

        // Edit links moved into the toolbar menu to reduce on-course clutter.

        clubPicker

        shotTypePicker

        statusStrip

        eventsList

        if let info {
          Text(info)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
      }
      .padding(.vertical, 12)
    }
    .transaction { $0.animation = nil }
    .navigationTitle("Hole \(state.holeNumber)")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      bottomActionBar
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        HStack {
          Menu {
            NavigationLink("Aerial View") { HoleAerialView() }
            NavigationLink("Map") { HoleMapView() }
            NavigationLink("Scorecard") { ScorecardView() }
            NavigationLink("Clubs") { ClubStatsView() }
            NavigationLink("Hole insights") {
              HoleInsightsView(holeNumber: state.holeNumber, course: state.course)
            }
            if let hole = state.currentHole,
               let url = URL(string: hole.flyover),
               !hole.flyover.isEmpty {
              Link("Flyover", destination: url)
            }
            Divider()
            NavigationLink("Edit caddy note") {
              HoleNotesView(holeNumber: state.holeNumber)
            }
            NavigationLink("Edit hole plan") {
              HolePlanView(holeNumber: state.holeNumber)
                .onDisappear { refreshStats() }
            }
            NavigationLink("Edit guide") {
              HoleGuideView(holeNumber: state.holeNumber)
                .onDisappear { refreshStats() }
            }
            Divider()
            NavigationLink("Settings") { SettingsView() }
            Divider()
            if let rid = state.activeRoundId {
              NavigationLink("Complete round") {
                RoundStatsView(roundId: rid, course: state.course)
              }
              Button("Abandon round", role: .destructive) { showAbandonConfirm = true }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
    }
    .onAppear {
      if loc.authorization == .notDetermined {
        loc.requestWhenInUse()
      }
      loc.refreshOnce()
      refreshStats()
    }
    .onChange(of: loc.authorization) { _, newValue in
      if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
        loc.refreshOnce()
      }
    }
    .alert("Abandon round?", isPresented: $showAbandonConfirm) {
      Button("Abandon round", role: .destructive) { performAbandon() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This round will be marked abandoned and kept in history. You can view it later in round history.")
    }
    .sheet(isPresented: $showShotConfirm) {
      ShotConfirmSheet(
        club: $pendingClub,
        shotType: $pendingShotType,
        holeNumber: state.holeNumber,
        accuracy: pendingFix?.hAcc,
        onCancel: {
          showShotConfirm = false
        },
        onConfirm: {
          confirmLogShot()
        }
      )
      .presentationDetents([.medium, .large])
    }
    .sheet(item: $editEvent) { ev in
      EventEditView(event: ev)
        .onDisappear { refreshStats() }
    }
    .sheet(isPresented: $showHolePicker) {
      HolePickerSheet(
        currentHole: state.holeNumber,
        course: state.course,
        onSelect: { holeNumber in
          jumpToHole(holeNumber)
        }
      )
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $showHoleSummary) {
      HoleSummarySheet(
        holeNumber: state.holeNumber,
        course: state.course,
        strokes: strokes,
        putts: putts,
        penalties: penalties,
        onContinue: {
          confirmHoleNavigation()
        },
        onStay: {
          showHoleSummary = false
          pendingHoleNavigation = nil
        }
      )
      .presentationDetents([.medium, .large])
    }
    .overlay(alignment: .bottom) {
      if showToast, let toastText {
        toastView(text: toastText)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .padding(.bottom, 10)
      }
    }
  }

  @ViewBuilder
  private func header(_ hole: CourseBundle.Hole?) -> some View {
    if let hole {
      let par = hole.par[state.tee]
      let si = hole.si[state.tee]
      let metres = Double(hole.distance_m[state.tee])

      VStack(spacing: 0) {
        // Top Info Row: Hole Selector + Name + SI
        HStack(alignment: .firstTextBaseline) {
          Button {
            showHolePicker = true
          } label: {
            HStack(spacing: 4) {
              Text("\(state.holeNumber)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
              Image(systemName: "chevron.down")
                .font(.subheadline)
                .fontWeight(.bold)
            }
            .foregroundColor(.primary)
          }

          VStack(alignment: .leading, spacing: 0) {
            Text(hole.name)
              .font(.headline)
              .fontWeight(.bold)
            Text("Par \(par) • SI \(si)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          
          Spacer()
          
          // Green button
          Menu {
            NavigationLink("Green View") {
              GreenMapView(holeNumber: state.holeNumber)
            }
            NavigationLink("3D Green View") {
              Green3DView(holeNumber: state.holeNumber, greenCenter: nil)
            }
            Divider()
            NavigationLink("Aerial View") {
              HoleAerialView()
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "circle.circle.fill")
              Text("Green")
            }
            .font(.subheadline)
            .fontWeight(.bold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
          }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)

        // Plays Like Card
        PlaysLikeDistanceView(
          actualDistance: metres,
          holeNumber: hole.number,
          unit: state.unit
        )
        .padding(.horizontal)

        scoreStrip
          .padding(.horizontal)

        if let plan = holePlanTip, !plan.isEmpty {
          Text(plan)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal)
        } else if let tip = caddyTip, !tip.isEmpty {
          Text(tip)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal)
        }
      }
    } else {
      Text("Hole not found")
        .foregroundStyle(.secondary)
    }
  }

  private var shotTypePicker: some View {
    HStack {
      Text("Shot")
        .font(.headline)
      Spacer()
      Picker("Shot type", selection: $state.shotType) {
        Text("Full").tag(ShotType.full)
        Text("3/4").tag(ShotType.threeQuarter)
        Text("Half").tag(ShotType.half)
        Text("Chip").tag(ShotType.chip)
      }
      .pickerStyle(.menu)
    }
    .padding(.horizontal)
  }

  private var statusStrip: some View {
    HStack(spacing: 12) {
      statPill(title: "Strokes", value: "\(strokes)")
      statPill(title: "Putts", value: "\(putts)")
      statPill(title: "Pens", value: "\(penalties)")
      Spacer(minLength: 0)
    }
    .padding(.horizontal)
  }

  private var scoreStrip: some View {
    HStack(spacing: 10) {
      statPill(title: "Gross", value: "\(scoreGross)")
      statPill(title: "Net", value: "\(scoreNet)")

      let tp = scoreNetToPar
      statPill(title: "Net", value: tp == 0 ? "E" : (tp > 0 ? "+\(tp)" : "\(tp)"))

      if let pts = scorePts {
        statPill(title: "Pts", value: "\(pts)")
      }

      Spacer(minLength: 0)
    }
    .padding(.top, 8)
  }

  private func statPill(title: String, value: String) -> some View {
    VStack(spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var clubPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Club")
          .font(.headline)
        
        Spacer()
        
        Text("Selected: \(state.selectedClub.rawValue)")
          .font(.subheadline)
          .foregroundStyle(Color.accentColor)
      }
      .padding(.horizontal)

      let cols: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
      ]

      LazyVGrid(columns: cols, spacing: 10) {
        ForEach(state.favouriteClubs) { club in
          Button {
            state.selectedClub = club
          } label: {
            Text(club.rawValue)
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .background(state.selectedClub == club ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
              .overlay(
                RoundedRectangle(cornerRadius: 12)
                  .stroke(state.selectedClub == club ? Color.accentColor : Color.clear, lineWidth: 2)
              )
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal)
    }
  }

  private var bottomActionBar: some View {
    VStack(spacing: 10) {
      // Hole navigation row
      HStack(spacing: 12) {
        Button {
          previousHole()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
            Text("Previous hole")
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .disabled(state.holeNumber <= 1)
        
        // Hole indicator
        Text("\(state.holeNumber) / 18")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
          .frame(minWidth: 60)
        
        Button {
          nextHole()
        } label: {
          HStack(spacing: 4) {
            Text("Next hole")
            Image(systemName: "chevron.right")
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .disabled(state.holeNumber >= 18)
      }
      
      Button {
        beginLogShot()
      } label: {
        Text("Log Shot #\(strokes + 1)")
          .font(.title3)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.borderedProminent)

      HStack(spacing: 12) {
        Button {
          logPenalty()
        } label: {
          Text("Penalty +1")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)

        Button {
          undoLast()
        } label: {
          Text("Undo")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(.horizontal)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .background(.thinMaterial)
  }

  private var eventsList: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("This hole")
          .font(.headline)
        Spacer()
        Button("Refresh") { refreshStats() }
          .font(.footnote)
      }
      .padding(.horizontal)

      if events.isEmpty {
        Text("No shots logged yet")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.horizontal)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, e in
              HStack {
                Button {
                  editEvent = e
                } label: {
                  HStack {
                    Text(e.kind == .shot ? "#\(idx + 1)" : "")
                      .frame(width: 40, alignment: .leading)
                      .foregroundStyle(.secondary)

                    Text(e.kind == .shot ? e.club.rawValue : "Penalty +\(e.penaltyStrokes ?? 1)")
                      .font(.headline)

                    Spacer()

                    Text(e.ts, style: .time)
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                  }
                }
                .buttonStyle(.plain)

                Button {
                  try? GCDB.shared.deleteEvent(id: e.id)
                  refreshStats()
                } label: {
                  Image(systemName: "trash")
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
              }
              .padding(.horizontal)
              .padding(.vertical, 10)

              Divider()
            }
          }
        }
        .frame(height: 220)
      }

      Text("Tip: tap an entry to edit. Use the trash icon to delete.")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }
  }

  private func currentFix() -> (lat: Double, lng: Double, alt: Double?, hAcc: Double?)? {
    guard let l = loc.lastLocation else { return nil }
    let alt: Double? = (l.altitude >= 0) ? l.altitude : nil
    return (l.coordinate.latitude, l.coordinate.longitude, alt, l.horizontalAccuracy)
  }

  private func beginLogShot() {
    guard state.activeRoundId != nil else { return }

    // Avoid layout jitter from transient info messages while the sheet presents.
    info = nil

    // We now keep location updates running continuously; no need to force-refresh here.
    guard let fix = currentFix() else {
      if let e = loc.lastError {
        info = "GPS error: \(e)"
      } else if loc.authorization == .denied || loc.authorization == .restricted {
        info = "Location disabled — enable While Using in Settings"
      } else {
        info = "Waiting for GPS… (try again in a second)"
      }
      return
    }

    pendingFix = fix
    pendingClub = state.selectedClub
    pendingShotType = state.shotType
    showShotConfirm = true
  }

  private func confirmLogShot() {
    guard let roundId = state.activeRoundId else { return }
    guard let fix = pendingFix else { return }

    showShotConfirm = false

    do {
      try GCDB.shared.addShot(
        roundId: roundId,
        holeNumber: state.holeNumber,
        location: (fix.lat, fix.lng, fix.alt, fix.hAcc),
        club: pendingClub,
        shotType: pendingShotType
      )

      refreshStats()

      let ev = (try? GCDB.shared.fetchHoleEvents(roundId: roundId, holeNumber: state.holeNumber)) ?? []
      toastEvent = ev.last

      toastText = "Logged \(pendingClub.rawValue)"
      showToast = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        showToast = false
      }
    } catch {
      info = "Failed to log shot: \(error.localizedDescription)"
    }
  }

  private func logPenalty() {
    guard let roundId = state.activeRoundId else { return }
    loc.refreshOnce()

    guard let fix = currentFix() else {
      info = "Waiting for GPS…"
      return
    }

    do {
      try GCDB.shared.addPenalty(roundId: roundId, holeNumber: state.holeNumber, location: (fix.lat, fix.lng, fix.alt, fix.hAcc), strokes: 1)
      refreshStats()
      info = "Logged penalty (+1)"
    } catch {
      info = "Failed to log penalty: \(error.localizedDescription)"
    }
  }

  private func undoLast() {
    guard let roundId = state.activeRoundId else { return }
    do {
      try GCDB.shared.deleteLastEvent(roundId: roundId, holeNumber: state.holeNumber)
      refreshStats()
      info = "Undid last event"
    } catch {
      info = "Undo failed: \(error.localizedDescription)"
    }
  }

  private func nextHole() {
    guard let roundId = state.activeRoundId else { return }
    
    // Compute stats for current hole before showing summary
    if let hole = state.currentHole {
      try? GCDB.shared.computeAndStoreHoleStats(
        roundId: roundId,
        holeNumber: state.holeNumber,
        par: hole.par[state.tee]
      )
    }
    
    if state.holeNumber < 18 {
      pendingHoleNavigation = state.holeNumber + 1
      showHoleSummary = true
    }
  }

  private func previousHole() {
    guard let roundId = state.activeRoundId else { return }
    
    // Compute stats for current hole before showing summary
    if let hole = state.currentHole {
      try? GCDB.shared.computeAndStoreHoleStats(
        roundId: roundId,
        holeNumber: state.holeNumber,
        par: hole.par[state.tee]
      )
    }
    
    if state.holeNumber > 1 {
      pendingHoleNavigation = state.holeNumber - 1
      showHoleSummary = true
    }
  }
  
  private func confirmHoleNavigation() {
    guard let targetHole = pendingHoleNavigation else { return }
    
    state.holeNumber = targetHole
    info = nil
    loc.refreshOnce()
    refreshStats()
    showHoleSummary = false
    pendingHoleNavigation = nil
  }

  private func jumpToHole(_ holeNumber: Int) {
    guard let roundId = state.activeRoundId else { return }
    
    // Compute stats for current hole before jumping
    if let hole = state.currentHole {
      try? GCDB.shared.computeAndStoreHoleStats(
        roundId: roundId,
        holeNumber: state.holeNumber,
        par: hole.par[state.tee]
      )
    }
    
    state.holeNumber = holeNumber
    info = nil
    loc.refreshOnce()
    refreshStats()
    showHolePicker = false
  }

  private func refreshStats() {
    guard let roundId = state.activeRoundId else { return }
    strokes = (try? GCDB.shared.strokesForHole(roundId: roundId, holeNumber: state.holeNumber)) ?? 0
    putts = (try? GCDB.shared.puttsForHole(roundId: roundId, holeNumber: state.holeNumber)) ?? 0

    // Caddy tip (first line of note).
    if let note = (try? GCDB.shared.fetchHoleNote(holeNumber: state.holeNumber)) ?? nil {
      caddyTip = note.split(separator: "\n").first.map(String.init)
    } else {
      caddyTip = nil
    }

    // Hole plan (single one-liner). Prefer saferTip for now.
    if let plan = try? GCDB.shared.fetchHolePlan(holeNumber: state.holeNumber) {
      holePlanTip = plan.saferTip
      if holePlanTip?.isEmpty == true { holePlanTip = nil }
    } else {
      holePlanTip = nil
    }

    // Hole guide (target/avoid).
    if let g = try? GCDB.shared.fetchHoleGuide(holeNumber: state.holeNumber) {
      holeTarget = g.target.isEmpty ? nil : g.target
      holeAvoid = g.avoid.isEmpty ? nil : g.avoid
    } else {
      holeTarget = nil
      holeAvoid = nil
    }

    // Sum penalty strokes + event list.
    let ev = (try? GCDB.shared.fetchHoleEvents(roundId: roundId, holeNumber: state.holeNumber)) ?? []
    events = ev
    penalties = ev.reduce(0) { acc, e in
      acc + (e.kind == .penalty ? (e.penaltyStrokes ?? 0) : 0)
    }

    refreshScoreTotals(roundId: roundId)
  }

  private func refreshScoreTotals(roundId: Int64) {
    guard let round = try? GCDB.shared.fetchRound(roundId: roundId) else {
      scoreGross = 0
      scoreNet = 0
      scoreNetToPar = 0
      scorePts = nil
      return
    }

    let overrides = (try? GCDB.shared.fetchHoleScores(roundId: roundId)) ?? [:]

    var grossTotal = 0
    var netTotal = 0
    var parTotal = 0
    var ptsTotal = 0
    var holesCounted = 0

    for h in state.course.holes {
      let gross = overrides[h.number]?.gross ?? ((try? GCDB.shared.strokesForHole(roundId: roundId, holeNumber: h.number)) ?? 0)
      if gross == 0 { continue }

      holesCounted += 1
      grossTotal += gross

      let par = h.par[round.tee]
      let si = h.si[round.tee]
      parTotal += par

      let rec = (round.playingHandicap != nil)
        ? WHS.strokesReceived(playingHandicap: round.playingHandicap ?? 0, holeSI: si)
        : 0

      let net = gross - rec
      netTotal += net

      if round.gameType == .stableford {
        ptsTotal += Stableford.points(par: par, grossStrokes: gross, strokesReceived: rec)
      }
    }

    scoreGross = grossTotal
    scoreNet = netTotal
    scoreNetToPar = netTotal - parTotal
    scorePts = (round.gameType == .stableford && holesCounted > 0) ? ptsTotal : (round.gameType == .stableford ? 0 : nil)
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

  private func toastView(text: String) -> some View {
    HStack(spacing: 12) {
      Text(text)
        .font(.footnote)
        .foregroundStyle(.primary)

      Spacer(minLength: 0)

      if toastEvent != nil {
        Button("Edit") {
          if let e = toastEvent { editEvent = e }
          showToast = false
        }
        .font(.footnote)

        Button("Undo") {
          undoLast()
          showToast = false
        }
        .font(.footnote)
        .foregroundStyle(.red)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .padding(.horizontal)
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

// MARK: - Hole Summary Sheet

private struct HoleSummarySheet: View {
  let holeNumber: Int
  let course: CourseBundle
  let strokes: Int
  let putts: Int
  let penalties: Int
  let onContinue: () -> Void
  let onStay: () -> Void
  
  @State private var holeStats: HoleStats? = nil
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          // Hole info header
          if let hole = course.holes.first(where: { $0.number == holeNumber }) {
            VStack(spacing: 8) {
              Text("Hole \(holeNumber) Complete")
                .font(.title2)
                .fontWeight(.bold)
              
              Text(hole.name)
                .font(.headline)
              
              HStack(spacing: 16) {
                Label("Par \(hole.par[.blue])", systemImage: "flag.fill")
                Label("SI \(hole.si[.blue])", systemImage: "number.circle.fill")
              }
              .font(.subheadline)
              .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
          }
          
          // Score display
          VStack(spacing: 12) {
            Text("Your Score")
              .font(.headline)
            
            HStack(spacing: 24) {
              ScoreBadge(value: strokes, label: "Strokes", color: .blue)
              ScoreBadge(value: putts, label: "Putts", color: .green)
              if penalties > 0 {
                ScoreBadge(value: penalties, label: "Penalties", color: .orange)
              }
            }
            
            // Score to par
            if let hole = course.holes.first(where: { $0.number == holeNumber }) {
              let scoreToPar = strokes - hole.par[.blue]
              HStack {
                Text("Score to par:")
                  .font(.subheadline)
                Text(scoreToPar == 0 ? "Even" : (scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"))
                  .font(.title3)
                  .fontWeight(.bold)
                  .foregroundColor(scoreToPar <= 0 ? .green : (scoreToPar <= 1 ? .orange : .red))
              }
              .padding(.top, 4)
            }
          }
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(12)
          
          // Stats (if available)
          if let stats = holeStats {
            VStack(spacing: 12) {
              Text("Hole Stats")
                .font(.headline)
              
              HStack(spacing: 16) {
                if let gir = stats.gir {
                  StatBadge(
                    label: "GIR",
                    value: gir ? "Yes" : "No",
                    color: gir ? .green : .red,
                    icon: "flag.fill"
                  )
                }
                
                if let fir = stats.fairwayHit {
                  StatBadge(
                    label: "Fairway",
                    value: fir ? "Hit" : "Miss",
                    color: fir ? .green : .orange,
                    icon: "arrow.up"
                  )
                }
              }
              
              if let scramble = stats.scramble {
                StatBadge(
                  label: "Scramble",
                  value: scramble ? "Success" : "Failed",
                  color: scramble ? .green : .orange,
                  icon: "arrow.2.squarepath"
                )
              }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
          }
          
          // Action buttons
          VStack(spacing: 12) {
            Button {
              onContinue()
            } label: {
              HStack {
                Image(systemName: "arrow.right.circle.fill")
                Text("Continue to Next Hole")
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            
            Button {
              onStay()
            } label: {
              Text("Stay on This Hole")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
          }
          .padding(.top, 8)
        }
        .padding()
      }
      .navigationTitle("Hole Summary")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        await loadHoleStats()
      }
    }
  }
  
  private func loadHoleStats() async {
    guard let roundId = try? GCDB.shared.fetchActiveRound()?.id else { return }
    
    do {
      let stats = try GCDB.shared.fetchHoleStatsForRound(roundId: roundId)
      if let holeStat = stats.first(where: { $0.holeNumber == holeNumber }) {
        await MainActor.run {
          self.holeStats = holeStat
        }
      }
    } catch {
      print("Failed to load hole stats: \(error)")
    }
  }
}

private struct ScoreBadge: View {
  let value: Int
  let label: String
  let color: Color
  
  var body: some View {
    VStack(spacing: 4) {
      Text("\(value)")
        .font(.system(.title2, design: .rounded, weight: .bold))
        .foregroundColor(color)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(minWidth: 60)
  }
}

private struct StatBadge: View {
  let label: String
  let value: String
  let color: Color
  let icon: String
  
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundColor(color)
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
        Text(value)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(color)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(color.opacity(0.1))
    .cornerRadius(8)
  }
}

