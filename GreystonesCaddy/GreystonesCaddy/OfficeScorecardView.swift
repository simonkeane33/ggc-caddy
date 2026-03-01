import SwiftUI
import GreystonesCaddyCore

/// Simple hole-by-hole gross entry to mirror the physical office scorecard.
struct OfficeScorecardView: View {
  @EnvironmentObject var state: AppState

  let round: RoundSummary

  @State private var scores: [Int: HoleScore] = [:]

  var body: some View {
    List {
      Section {
        Text("Enter gross score per hole. This is useful at the end of the round when you need to fill in the office card.")
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

          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Hole \(holeNo)")
                .font(.headline)
              Text("Par \(par) • SI \(si)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Stepper(value: Binding(
              get: { gross },
              set: { v in setGross(hole: holeNo, gross: v) }
            ), in: 0...20) {
              Text(gross == 0 ? "—" : "\(gross)")
                .font(.headline)
                .frame(width: 34, alignment: .trailing)
            }
            .labelsHidden()
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
    }
    .navigationTitle("Office scorecard")
    .onAppear { load() }
  }

  private func load() {
    scores = (try? GCDB.shared.fetchHoleScores(roundId: round.id)) ?? [:]
  }

  private func setGross(hole: Int, gross: Int) {
    if gross == 0 {
      clear(hole: hole)
      return
    }

    do {
      try GCDB.shared.upsertHoleScore(roundId: round.id, holeNumber: hole, gross: gross, putts: scores[hole]?.putts)
      scores = (try? GCDB.shared.fetchHoleScores(roundId: round.id)) ?? [:]
    } catch {
      // ignore for MVP
    }
  }

  private func clear(hole: Int) {
    do {
      try GCDB.shared.deleteHoleScore(roundId: round.id, holeNumber: hole)
      scores.removeValue(forKey: hole)
    } catch {
      // ignore for MVP
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
