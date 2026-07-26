import SwiftUI
import GreystonesCaddyCore

/// Simple hole-by-hole gross and putts entry to mirror the physical office scorecard.
struct OfficeScorecardView: View {
  @EnvironmentObject var state: AppState

  let round: RoundSummary

  @State private var scores: [Int: HoleScore] = [:]
  @State private var validationMessage: String? = nil

  var body: some View {
    List {
      Section {
        Text("Enter strokes and putts per hole. Strokes 1–15, putts required.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("Holes") {
        ForEach(0..<state.course.holes.count, id: \.self) { i in
          let h = state.course.holes[i]
          let holeNo = h.number
          let par = h.par[round.tee]
          let si = h.si[round.tee]

          let current = scores[holeNo]
          let gross = current?.gross ?? 0
          let putts = current?.putts ?? 0

          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Hole \(holeNo)")
                .font(.headline)
              Text("Par \(par) • SI \(si)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
              Stepper(value: Binding(
                get: { gross },
                set: { v in setScore(hole: holeNo, gross: v, putts: putts) }
              ), in: 0...15) {
                Text(gross == 0 ? "—" : "\(gross)")
                  .font(.headline)
                  .frame(width: 34, alignment: .trailing)
              }
              .labelsHidden()

              Stepper(value: Binding(
                get: { putts },
                set: { v in setScore(hole: holeNo, gross: gross, putts: v) }
              ), in: 0...10) {
                Text(putts == 0 && gross == 0 ? "—" : "\(putts)P")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .frame(width: 32, alignment: .trailing)
              }
              .labelsHidden()
            }
          }
          .swipeActions {
            Button(role: .destructive) {
              clear(hole: holeNo)
            } label: {
              Label("Clear", systemImage: "trash")
            }
          }
        }
      }

      Section("Totals") {
        let totalStrokes = scores.values.map(\.gross).filter { $0 > 0 }.reduce(0, +)
        let totalPutts = scores.values.compactMap(\.putts).reduce(0, +)
        let parTotal = state.course.holes.map { $0.par[round.tee] }.reduce(0, +)

        HStack {
          Text("Strokes")
          Spacer()
          Text(totalStrokes == 0 ? "—" : "\(totalStrokes)")
            .font(.headline)
        }
        HStack {
          Text("Putts")
          Spacer()
          Text(totalPutts == 0 ? "—" : "\(totalPutts)")
            .font(.headline)
        }
        HStack {
          Text("To Par")
          Spacer()
          if totalStrokes == 0 {
            Text("—")
          } else {
            let toPar = totalStrokes - parTotal
            Text(toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)"))
              .font(.headline)
          }
        }
      }

      if round.gameType == .stableford, let ph = round.playingHandicap {
        Section("Stableford preview") {
          let pts = totalStablefordPoints(playingHandicap: ph)
          HStack {
            Text("Total points")
            Spacer()
            Text("\(pts)")
              .font(.headline)
          }
        }
      }

      if let msg = validationMessage {
        Section {
          Text(msg)
            .font(.footnote)
            .foregroundStyle(.orange)
        }
      }
    }
    .navigationTitle("Office scorecard")
    .onAppear { load() }
  }

  private func load() {
    scores = (try? GCDB.shared.fetchHoleScores(roundId: round.id)) ?? [:]
    validationMessage = nil
  }

  private func setScore(hole: Int, gross: Int, putts: Int) {
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
      try GCDB.shared.upsertHoleScore(roundId: round.id, holeNumber: hole, gross: gross, putts: putts)
      scores = (try? GCDB.shared.fetchHoleScores(roundId: round.id)) ?? [:]
      validationMessage = nil
    } catch {
      validationMessage = "Save failed: \(error.localizedDescription)"
    }
  }

  private func clear(hole: Int) {
    do {
      try GCDB.shared.deleteHoleScore(roundId: round.id, holeNumber: hole)
      scores = (try? GCDB.shared.fetchHoleScores(roundId: round.id)) ?? [:]
      validationMessage = nil
    } catch {
      validationMessage = "Clear failed: \(error.localizedDescription)"
    }
  }

  private func totalStablefordPoints(playingHandicap: Int) -> Int {
    var total = 0
    for h in state.course.holes {
      guard let s = scores[h.number]?.gross, s > 0 else { continue }
      let par = h.par[round.tee]
      let si = h.si[round.tee]
      let rec = WHS.strokesReceived(playingHandicap: playingHandicap, holeSI: si)
      total += Stableford.points(par: par, grossStrokes: s, strokesReceived: rec)
    }
    return total
  }
}
