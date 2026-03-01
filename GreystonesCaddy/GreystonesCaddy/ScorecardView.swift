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

  @State private var holeStrokes: [Int: Int] = [:]
  @State private var holePutts: [Int: Int] = [:]

  var body: some View {
    List {
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
          let strokes = holeStrokes[h.number] ?? 0
          let putts = holePutts[h.number] ?? 0
          let tee = teeOverride ?? state.tee
          let par = h.par[tee]
          let toPar = strokes == 0 ? nil : (strokes - par)

          HStack {
            Text("\(h.number)")
              .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
              Text(h.name)
                .lineLimit(1)
              Text("Par \(par) • SI \(h.si[state.tee])")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
              Text(strokes == 0 ? "—" : "\(strokes)")
                .font(.headline)
              Text(putts == 0 ? "" : "\(putts) putts")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let toPar {
              Text(toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            }
          }
        }
      }

      Section("Totals") {
        let tee = teeOverride ?? state.tee
        let totalStrokes = holeStrokes.values.reduce(0, +)
        let totalPutts = holePutts.values.reduce(0, +)
        let parTotal = state.course.holes.map { $0.par[tee] }.reduce(0, +)

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
              .font(.headline)
          } else {
            let toPar = totalStrokes - parTotal
            Text(toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)"))
              .font(.headline)
          }
        }
      }
    }
    .navigationTitle("Scorecard")
    .onAppear { refresh() }
  }

  private func refresh() {
    guard let roundId = roundId ?? state.activeRoundId else { return }

    var strokes: [Int: Int] = [:]
    var putts: [Int: Int] = [:]

    for h in 1...18 {
      strokes[h] = (try? GCDB.shared.strokesForHole(roundId: roundId, holeNumber: h)) ?? 0
      putts[h] = (try? GCDB.shared.puttsForHole(roundId: roundId, holeNumber: h)) ?? 0
    }

    holeStrokes = strokes
    holePutts = putts
  }
}
