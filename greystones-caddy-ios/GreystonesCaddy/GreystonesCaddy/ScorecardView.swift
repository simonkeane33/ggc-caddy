import SwiftUI
import GreystonesCaddyCore

struct ScorecardView: View {
  @EnvironmentObject var state: AppState

  let roundId: Int64?
  let teeOverride: TeeID?
  let unitOverride: DistanceUnit?

  init(roundId: Int64? = nil, tee: TeeID? = nil, unit: DistanceUnit? = nil) {
    self.roundId = roundId
    self.teeOverride = tee
    self.unitOverride = unit
  }

  @State private var scores: [Int: HoleScore] = [:]
  @State private var validationMessage: String? = nil

  private var effectiveRoundId: Int64? {
    roundId ?? state.activeRoundId
  }

  var body: some View {
    List {
      if effectiveRoundId == nil {
        Section {
          Text("Start a round to enter scores.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section {
          let tee = teeOverride ?? state.tee
          let unit = unitOverride ?? state.unit

          HStack {
            Text("Tee")
            Spacer()
            Text(tee.rawValue.capitalized)
              .foregroundStyle(.secondary)
          }
          HStack {
            Text("Units")
            Spacer()
            Text(unit == .yards ? "Yards" : "Metres")
              .foregroundStyle(.secondary)
          }
        }

        Section("Holes") {
          ForEach(state.course.holes) { h in
            holeRow(h)
          }
        }

        Section("Totals") {
          totalsSection
        }

        if let msg = validationMessage {
          Section {
            Text(msg)
              .font(.footnote)
              .foregroundStyle(.orange)
          }
        }
      }
    }
    .navigationTitle("Scorecard")
    .onAppear { refresh() }
  }

  @ViewBuilder
  private func holeRow(_ h: CourseBundle.Hole) -> some View {
    let tee = teeOverride ?? state.tee
    let par = h.par[tee]
    let gross = scores[h.number]?.gross ?? 0
    let putts = scores[h.number]?.putts ?? 0
    let toPar = gross == 0 ? nil : (gross - par)

    HStack {
      Text("\(h.number)")
        .frame(width: 24, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(h.name)
          .lineLimit(1)
        Text("Par \(par) • SI \(h.si[tee])")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 10) {
        compactStepper(
          value: gross == 0 ? "—" : "\(gross)",
          minusIdentifier: "hole\(h.number)StrokesMinus",
          plusIdentifier: "hole\(h.number)StrokesPlus",
          decrement: { setScore(hole: h.number, gross: max(0, gross - 1), putts: putts) },
          increment: { setScore(hole: h.number, gross: gross + 1, putts: putts) }
        )
        compactStepper(
          value: putts == 0 && gross == 0 ? "—" : "\(putts)",
          minusIdentifier: "hole\(h.number)PuttsMinus",
          plusIdentifier: "hole\(h.number)PuttsPlus",
          decrement: { setScore(hole: h.number, gross: gross, putts: max(0, putts - 1)) },
          increment: { setScore(hole: h.number, gross: gross, putts: putts + 1) }
        )
      }

      if let toPar {
        Text(toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)"))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .trailing)
      }
    }
    .swipeActions {
      Button(role: .destructive) {
        clear(hole: h.number)
      } label: {
        Label("Clear", systemImage: "trash")
      }
    }
  }

  private func compactStepper(
    value: String,
    minusIdentifier: String,
    plusIdentifier: String,
    decrement: @escaping () -> Void,
    increment: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 4) {
      Button(action: decrement) {
        Image(systemName: "minus")
          .font(.caption)
          .frame(width: 20, height: 20)
      }
      .accessibilityIdentifier(minusIdentifier)

      Text(value)
        .font(.headline)
        .monospacedDigit()
        .frame(width: 20, alignment: .center)

      Button(action: increment) {
        Image(systemName: "plus")
          .font(.caption)
          .frame(width: 20, height: 20)
      }
      .accessibilityIdentifier(plusIdentifier)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
  }

  private var totalsSection: some View {
    Group {
      let tee = teeOverride ?? state.tee
      let totalStrokes = scores.values.map(\.gross).filter { $0 > 0 }.reduce(0, +)
      let totalPutts = scores.values.compactMap(\.putts).reduce(0, +)
      let parTotal = state.course.holes.map { $0.par[tee] }.reduce(0, +)

      HStack {
        Text("Strokes")
        Spacer()
        Text(totalStrokes == 0 ? "—" : "\(totalStrokes)")
          .font(.headline)
          .accessibilityIdentifier("scorecardTotalStrokes")
      }

      HStack {
        Text("Putts")
        Spacer()
        Text(totalPutts == 0 ? "—" : "\(totalPutts)")
          .font(.headline)
          .accessibilityIdentifier("scorecardTotalPutts")
      }

      HStack {
        Text("To Par")
        Spacer()
        if totalStrokes == 0 {
          Text("—")
            .font(.headline)
        } else {
          let toPar = totalStrokes - parTotal
          Text(toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)"))
            .font(.headline)
            .accessibilityIdentifier("scorecardTotalToPar")
        }
      }
    }
  }

  private func refresh() {
    guard let rid = effectiveRoundId else {
      scores = [:]
      return
    }
    scores = (try? GCDB.shared.fetchHoleScores(roundId: rid)) ?? [:]
    validationMessage = nil
  }

  private func setScore(hole: Int, gross: Int, putts: Int) {
    guard let rid = effectiveRoundId else { return }

    if gross == 0 {
      clear(hole: hole)
      return
    }

    if gross < 1 || gross > 15 {
      validationMessage = "Strokes must be 1–15"
      return
    }

    if putts < 0 || putts > 10 {
      validationMessage = "Putts must be 0–10"
      return
    }

    do {
      try GCDB.shared.upsertHoleScore(roundId: rid, holeNumber: hole, gross: gross, putts: putts)
      scores = (try? GCDB.shared.fetchHoleScores(roundId: rid)) ?? [:]
      validationMessage = nil
    } catch {
      validationMessage = "Save failed: \(error.localizedDescription)"
    }
  }

  private func clear(hole: Int) {
    guard let rid = effectiveRoundId else { return }
    do {
      try GCDB.shared.deleteHoleScore(roundId: rid, holeNumber: hole)
      scores = (try? GCDB.shared.fetchHoleScores(roundId: rid)) ?? [:]
      validationMessage = nil
    } catch {
      validationMessage = "Clear failed: \(error.localizedDescription)"
    }
  }
}
