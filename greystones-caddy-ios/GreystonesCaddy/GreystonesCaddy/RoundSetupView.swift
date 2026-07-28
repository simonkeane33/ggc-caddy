import SwiftUI
import GreystonesCaddyCore

struct RoundSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var state: AppState
  @State private var goLive: Bool = false
  @State private var showInProgressAlert: Bool = false
  @State private var pendingReplacementRound: RoundSummary? = nil

  @FocusState private var focusField: Field?
  enum Field { case handicapIndex }

  @State private var gameType: GameType = .stroke
  @State private var handicapIndexText: String = ""
  @State private var allowancePct: Double = 100
  
  // UserDefaults keys for persistence
  private let handicapIndexKey = "lastHandicapIndex"
  private let gameTypeKey = "lastGameType"
  private let allowancePctKey = "lastAllowancePct"
  @State private var computedCourseHandicap: Int? = nil
  @State private var computedPlayingHandicap: Int? = nil

  var body: some View {
    Form {
      Section("Course") {
        Text(state.course.course.name)
      }

      Section("Tees") {
        Picker("Tee", selection: $state.tee) {
          Text("Blue").tag(TeeID.blue)
          Text("Green").tag(TeeID.green)
          Text("Red").tag(TeeID.red)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
      }

      Section("Units") {
        Picker("Distance", selection: $state.unit) {
          Text("Yards").tag(DistanceUnit.yards)
          Text("Metres").tag(DistanceUnit.metres)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
      }

      Section("Format") {
        Picker("Game", selection: $gameType) {
          ForEach(GameType.allCases) { gt in
            Text(gt.label).tag(gt)
          }
        }

        TextField("Handicap Index (WHS)", text: $handicapIndexText)
          .keyboardType(.decimalPad)
          .focused($focusField, equals: .handicapIndex)

        HStack {
          Text("Allowance")
          Spacer()
          Text("\(Int(allowancePct))%")
            .foregroundStyle(.secondary)
        }
        Slider(value: $allowancePct, in: 50...100, step: 5)

        if let ch = computedCourseHandicap, let ph = computedPlayingHandicap {
          HStack {
            Text("Course handicap")
            Spacer()
            Text("\(ch)")
              .foregroundStyle(.secondary)
          }
          HStack {
            Text("Playing handicap")
            Spacer()
            Text("\(ph)")
              .foregroundStyle(.secondary)
          }
        } else {
          Text("Enter handicap index to compute playing handicap.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Button {
          do {
            if let existing = try? GCDB.shared.fetchActiveRound() {
              pendingReplacementRound = existing
              showInProgressAlert = true
              return
            }
            try startFreshRound()
          } catch {
            fatalError("Failed to create round: \(error)")
          }
        } label: {
          Text("Start Round")
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("roundSetupStartButton")
      }
    }
    .navigationTitle("New Round")
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { focusField = nil }
      }
    }
    .onAppear {
      let savedHandicap = UserDefaults.standard.double(forKey: handicapIndexKey)
      if savedHandicap > 0 {
        handicapIndexText = String(format: "%.1f", savedHandicap)
      }
      if let savedGameTypeRaw = UserDefaults.standard.string(forKey: gameTypeKey),
         let savedGameType = GameType(rawValue: savedGameTypeRaw) {
        gameType = savedGameType
      }
      let savedAllowance = UserDefaults.standard.double(forKey: allowancePctKey)
      if savedAllowance > 0 {
        allowancePct = savedAllowance
      } else {
        allowancePct = gameType.defaultAllowancePct
      }
      recompute()
    }
    .onChange(of: gameType) { _, newValue in
      allowancePct = newValue.defaultAllowancePct
      recompute()
    }
    .onChange(of: handicapIndexText) { _, _ in
      recompute()
    }
    .onChange(of: allowancePct) { _, _ in
      recompute()
    }
    .onChange(of: state.tee) { _, _ in
      recompute()
    }
    .navigationDestination(isPresented: $goLive) {
      MainGameView()
    }
    .onChange(of: state.abandonTriggered) { _, triggered in
      if triggered {
        state.abandonTriggered = false
        dismiss()
      }
    }
    .alert("Round in progress", isPresented: $showInProgressAlert) {
      Button("Cancel current round", role: .destructive) {
        guard let existing = pendingReplacementRound else { return }
        do {
          try GCDB.shared.abandonRound(roundId: existing.id)
          state.activeRoundId = nil
          state.holeNumber = 1
          pendingReplacementRound = nil
          try startFreshRound()
        } catch {
          fatalError("Failed to abandon and start new round: \(error)")
        }
      }
      Button("Keep current round", role: .cancel) {
        pendingReplacementRound = nil
      }
    } message: {
      Text("Round in progress. Cancel round in progress and start a new round?")
    }
  }

  private func startFreshRound() throws {
    try seedHolePlansIfNeeded()
    try seedHoleGuidesIfNeeded()

    let roundId = try GCDB.shared.createRound(tee: state.tee, distanceUnit: state.unit, course: state.course.course.name)

    let hi = Double(handicapIndexText.trimmingCharacters(in: .whitespacesAndNewlines))
    let parTotal = state.course.holes.reduce(0) { $0 + $1.par[state.tee] }
    let tee = state.course.tees.first(where: { $0.id == state.tee })
    let rating = tee?.men
    let ch = (hi != nil && rating != nil) ? WHS.courseHandicap(handicapIndex: hi!, slope: rating!.slopeRating, courseRating: rating!.courseRating, par: parTotal) : nil
    let ph = (ch != nil) ? WHS.playingHandicap(courseHandicap: ch!, allowancePct: allowancePct) : nil

    try? GCDB.shared.updateRoundSettings(
      roundId: roundId,
      gameType: gameType,
      handicapIndex: hi,
      allowancePct: allowancePct,
      courseHandicap: ch,
      playingHandicap: ph
    )

    if let handicap = hi {
      UserDefaults.standard.set(handicap, forKey: handicapIndexKey)
    }
    UserDefaults.standard.set(gameType.rawValue, forKey: gameTypeKey)
    UserDefaults.standard.set(allowancePct, forKey: allowancePctKey)

    state.activeRoundId = roundId
    state.resetToNewRoundDefaults()
    goLive = true
  }

  private func recompute() {
    let hi = Double(handicapIndexText.trimmingCharacters(in: .whitespacesAndNewlines))
    guard let hi else {
      computedCourseHandicap = nil
      computedPlayingHandicap = nil
      return
    }

    let parTotal = state.course.holes.reduce(0) { $0 + $1.par[state.tee] }
    let tee = state.course.tees.first(where: { $0.id == state.tee })
    guard let rating = tee?.men else {
      computedCourseHandicap = nil
      computedPlayingHandicap = nil
      return
    }

    let ch = WHS.courseHandicap(handicapIndex: hi, slope: rating.slopeRating, courseRating: rating.courseRating, par: parTotal)
    computedCourseHandicap = ch
    computedPlayingHandicap = WHS.playingHandicap(courseHandicap: ch, allowancePct: allowancePct)
  }

  private func seedHolePlansIfNeeded() throws {
    for h in 1...18 {
      if (try GCDB.shared.fetchHolePlan(holeNumber: h)) == nil {
        try GCDB.shared.upsertHolePlan(holeNumber: h, saferTip: "", aggressiveTip: "")
      }
    }
  }

  private func seedHoleGuidesIfNeeded() throws {
    for h in 1...18 {
      if (try GCDB.shared.fetchHoleGuide(holeNumber: h)) == nil {
        try GCDB.shared.upsertHoleGuide(holeNumber: h, target: "", avoid: "")
      }
    }
  }
}
