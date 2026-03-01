import SwiftUI
import GreystonesCaddyCore

struct RoundSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var state: AppState
  @State private var goLive: Bool = false

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
      }

      Section("Units") {
        Picker("Distance", selection: $state.unit) {
          Text("Yards").tag(DistanceUnit.yards)
          Text("Metres").tag(DistanceUnit.metres)
        }
        .pickerStyle(.segmented)
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
            // Ensure caddy layer templates exist for all holes.
            try seedHolePlansIfNeeded()
            try seedHoleGuidesIfNeeded()

            let roundId = try GCDB.shared.createRound(tee: state.tee, distanceUnit: state.unit)

            // Persist round settings.
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

            // Save preferences for next round
            if let handicap = hi {
              UserDefaults.standard.set(handicap, forKey: handicapIndexKey)
              print("DEBUG: Saved handicap: \(handicap)")
            }
            UserDefaults.standard.set(gameType.rawValue, forKey: gameTypeKey)
            UserDefaults.standard.set(allowancePct, forKey: allowancePctKey)
            UserDefaults.standard.synchronize() // Force immediate save
            print("DEBUG: Saved game type: \(gameType.rawValue), allowance: \(allowancePct)")

            state.activeRoundId = roundId
            state.resetToNewRoundDefaults()
            goLive = true
          } catch {
            // For MVP: crash with context rather than fail silently.
            fatalError("Failed to create round: \(error)")
          }
        } label: {
          Text("Start Round")
            .frame(maxWidth: .infinity, alignment: .center)
        }
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
      // Load saved preferences
      let savedHandicap = UserDefaults.standard.double(forKey: handicapIndexKey)
      print("DEBUG: Loading saved handicap: \(savedHandicap)")
      if savedHandicap > 0 {
        handicapIndexText = String(format: "%.1f", savedHandicap)
        print("DEBUG: Set handicapIndexText to: \(handicapIndexText)")
      }
      
      if let savedGameTypeRaw = UserDefaults.standard.string(forKey: gameTypeKey),
         let savedGameType = GameType(rawValue: savedGameTypeRaw) {
        gameType = savedGameType
        print("DEBUG: Loaded game type: \(savedGameType)")
      }
      
      let savedAllowance = UserDefaults.standard.double(forKey: allowancePctKey)
      print("DEBUG: Loading saved allowance: \(savedAllowance)")
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
