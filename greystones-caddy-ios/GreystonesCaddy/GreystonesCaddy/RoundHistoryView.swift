import SwiftUI
import GreystonesCaddyCore

/// Round history list: date, course, total score, completion state; newest first; in-progress resumable.
struct RoundHistoryView: View {
  @EnvironmentObject var state: AppState

  @State private var rounds: [RoundSummary] = []
  @State private var totals: [Int64: Int] = [:]

  var body: some View {
    List {
      if rounds.isEmpty {
        Text("No rounds yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(rounds) { r in
          NavigationLink {
            if r.completionState == .inProgress {
              ResumeRoundView(roundId: r.id)
            } else {
              RoundDetailView(round: r)
            }
          } label: {
            row(for: r)
          }
        }
      }
    }
    .navigationTitle("Round History")
    .onAppear { refresh() }
  }

  private func row(for r: RoundSummary) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(r.startedAt, style: .date)
          .font(.headline)
        Spacer()
        Text(totals[r.id].map(String.init) ?? "—")
          .font(.headline)
      }
      Text(r.course ?? "Greystones")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Text(stateLabel(r.completionState))
        .font(.footnote)
        .foregroundStyle(stateColor(r.completionState))
    }
  }

  private func stateLabel(_ s: RoundCompletionState) -> String {
    switch s {
    case .inProgress: return "In progress"
    case .completed: return "Completed"
    case .abandoned: return "Abandoned"
    }
  }

  private func stateColor(_ s: RoundCompletionState) -> Color {
    switch s {
    case .inProgress: return .blue
    case .completed: return .secondary
    case .abandoned: return .orange
    }
  }

  private func refresh() {
    let list = (try? GCDB.shared.listRounds(limit: 50)) ?? []
    rounds = list
    totals = Dictionary(uniqueKeysWithValues: list.map { r in
      (r.id, (try? GCDB.shared.totalScoreFromHoleScores(roundId: r.id)) ?? 0)
    })
  }
}
