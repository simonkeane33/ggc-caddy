import SwiftUI
import GreystonesCaddyCore

struct RoundDetailView: View {
  @EnvironmentObject var state: AppState

  let round: RoundSummary

  @State private var holeStrokes: [Int: Int] = [:]
  @State private var holePutts: [Int: Int] = [:]
  @State private var holePens: [Int: Int] = [:]
  @State private var holeScoreOverrides: [Int: HoleScore] = [:]

  var body: some View {
    List {
      Section("Round") {
        HStack {
          Text("Date")
          Spacer()
          Text(round.startedAt, style: .date)
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Game")
          Spacer()
          Text(round.gameType.label)
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Tee")
          Spacer()
          Text(round.tee.rawValue.capitalized)
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Units")
          Spacer()
          Text(round.distanceUnit == .yards ? "Yards" : "Metres")
            .foregroundStyle(.secondary)
        }

        if let hi = round.handicapIndex {
          HStack {
            Text("Handicap index")
            Spacer()
            Text(String(format: "%.1f", hi))
              .foregroundStyle(.secondary)
          }
        }
        if let ap = round.allowancePct {
          HStack {
            Text("Allowance")
            Spacer()
            Text("\(Int(ap))%")
              .foregroundStyle(.secondary)
          }
        }
        if let ph = round.playingHandicap {
          HStack {
            Text("Playing handicap")
            Spacer()
            Text("\(ph)")
              .foregroundStyle(.secondary)
          }
        }

        if let ended = round.endedAt {
          HStack {
            Text("Ended")
            Spacer()
            Text(ended, style: .time)
              .foregroundStyle(.secondary)
          }
        }
      }

      if round.gameType == .stableford, let ph = round.playingHandicap {
        Section("Stableford") {
          let totals = stablefordTotals(playingHandicap: ph)
          HStack {
            Text("Points")
            Spacer()
            Text("\(totals.points)")
              .font(.headline)
          }
          HStack {
            Text("Strokes")
            Spacer()
            Text("\(totals.gross)")
              .foregroundStyle(.secondary)
          }
        }
      }

      Section {
        NavigationLink("Scorecard") {
          ScorecardView(roundId: round.id, tee: round.tee, unit: round.distanceUnit)
        }
        NavigationLink("Office scorecard") {
          OfficeScorecardView(round: round)
            .onDisappear { refresh() }
        }
        NavigationLink("Round stats") {
          RoundStatsView(roundId: round.id, course: state.course)
        }
        NavigationLink("Club distances") {
          ClubStatsView(roundId: round.id, unit: round.distanceUnit)
        }
        NavigationLink("Round map") {
          RoundMapView(roundId: round.id)
        }
      }

      Section("Holes") {
        ForEach(state.course.holes) { h in
          let override = holeScoreOverrides[h.number]
          let strokes = override?.gross ?? (holeStrokes[h.number] ?? 0)
          let putts = override?.putts ?? (holePutts[h.number] ?? 0)
          let pens = holePens[h.number] ?? 0

          let par = h.par[round.tee]
          let si = h.si[round.tee]
          let rec = (round.playingHandicap != nil) ? WHS.strokesReceived(playingHandicap: round.playingHandicap ?? 0, holeSI: si) : 0
          let pts = (round.gameType == .stableford && round.playingHandicap != nil && strokes > 0)
            ? Stableford.points(par: par, grossStrokes: strokes, strokesReceived: rec)
            : nil

          NavigationLink {
            HoleMapView(roundId: round.id, holeNumber: h.number)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("\(h.number)")
                  .frame(width: 24, alignment: .leading)
                Text(h.name)
                  .lineLimit(1)
                Spacer()

                if let pts {
                  Text("\(pts) pts")
                    .font(.headline)
                } else {
                  Text(strokes == 0 ? "—" : "\(strokes)")
                    .font(.headline)
                }
              }

              HStack(spacing: 10) {
                Text("Par \(par) • SI \(si)")
                if round.playingHandicap != nil {
                  Text("Rec \(rec)")
                }
                if putts > 0 { Text("\(putts)p") }
                if pens > 0 { Text("+\(pens)") }
              }
              .font(.footnote)
              .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Round")
    .onAppear { refresh() }
  }

  private func refresh() {
    var strokes: [Int: Int] = [:]
    var putts: [Int: Int] = [:]
    var pens: [Int: Int] = [:]

    for h in 1...18 {
      strokes[h] = (try? GCDB.shared.strokesForHole(roundId: round.id, holeNumber: h)) ?? 0
      putts[h] = (try? GCDB.shared.puttsForHole(roundId: round.id, holeNumber: h)) ?? 0

      let ev = (try? GCDB.shared.fetchHoleEvents(roundId: round.id, holeNumber: h)) ?? []
      pens[h] = ev.reduce(0) { acc, e in acc + (e.kind == .penalty ? (e.penaltyStrokes ?? 0) : 0) }
    }

    holeStrokes = strokes
    holePutts = putts
    holePens = pens
    holeScoreOverrides = (try? GCDB.shared.fetchHoleScores(roundId: round.id)) ?? [:]
  }

  private func stablefordTotals(playingHandicap: Int) -> (points: Int, gross: Int) {
    var pts = 0
    var gross = 0

    for h in state.course.holes {
      let s = holeStrokes[h.number] ?? 0
      if s == 0 { continue }
      gross += s

      let par = h.par[round.tee]
      let si = h.si[round.tee]
      let rec = WHS.strokesReceived(playingHandicap: playingHandicap, holeSI: si)
      pts += Stableford.points(par: par, grossStrokes: s, strokesReceived: rec)
    }

    return (pts, gross)
  }
}
