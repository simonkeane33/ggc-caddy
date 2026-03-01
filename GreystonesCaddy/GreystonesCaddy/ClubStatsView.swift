import SwiftUI
import GreystonesCaddyCore

struct ClubStatsView: View {
  @EnvironmentObject var state: AppState

  let roundId: Int64?
  let unitOverride: DistanceUnit?

  init(roundId: Int64? = nil, unit: DistanceUnit? = nil) {
    self.roundId = roundId
    self.unitOverride = unit
  }

  @State private var stats: [ClubDistanceStat] = []

  var body: some View {
    List {
      if stats.isEmpty {
        Text("Not enough data yet. Log a few non-putter shots and you’ll start seeing medians.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(stats) { s in
          HStack {
            Text(s.club.rawValue)
              .font(.headline)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
              Text(formatDistance(metres: s.medianMetres))
                .font(.headline)
              Text("\(formatDistance(metres: s.p25Metres)) – \(formatDistance(metres: s.p75Metres))")
                .font(.footnote)
                .foregroundStyle(.secondary)
              Text("n=\(s.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Club distances")
    .onAppear { refresh() }
  }

  private func refresh() {
    guard let roundId = roundId ?? state.activeRoundId else { return }

    // Pull all hole events and compute stats across the whole round.
    var all: [HoleEvent] = []
    for h in 1...18 {
      let ev = (try? GCDB.shared.fetchHoleEvents(roundId: roundId, holeNumber: h)) ?? []
      all.append(contentsOf: ev)
    }

    stats = Analytics.clubDistanceStats(events: all)
  }

  private func formatDistance(metres: Double) -> String {
    let unit = unitOverride ?? state.unit
    switch unit {
    case .metres:
      return "\(Int(metres.rounded())) m"
    case .yards:
      let yd = Distance.metresToYards(metres)
      return "\(Int(yd.rounded())) yd"
    }
  }
}
