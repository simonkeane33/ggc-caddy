import SwiftUI
import GreystonesCaddyCore

/// Displays comprehensive stats for a round. Supports completion flow when showing active round.
struct RoundStatsView: View {
  let roundId: Int64
  let course: CourseBundle

  @EnvironmentObject var state: AppState
  @Environment(\.dismiss) private var dismiss

  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var totalScoreFromHoleScores: Int = 0
  @State private var totalPuttsFromHoleScores: Int = 0
  @State private var holesWithScores: Set<Int> = []
  @State private var tee: TeeID = .blue
  @State private var showMissingScoresAlert = false
  @State private var showCompleteSuccess = false
  @State private var completedRound: RoundSummary?

  /// Score-to-par computed from canonical hole_scores, for only the holes actually scored.
  private var scoreToPar: Int? {
    guard !holesWithScores.isEmpty else { return nil }
    let parTotal = holesWithScores.reduce(0) { sum, holeNum in
      sum + (course.holes.first(where: { $0.number == holeNum })?.par[tee] ?? 0)
    }
    return totalScoreFromHoleScores - parTotal
  }

  private var isCompletionFlow: Bool {
    state.activeRoundId == roundId
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        if isLoading {
          ProgressView("Calculating stats...")
            .padding()
        } else {
          if let error = errorMessage {
            Text("Error: \(error)")
              .foregroundColor(.red)
              .padding()
          } else {
            v1StatsSection
          }

          if isCompletionFlow {
            completeRoundSection
          }
        }
      }
      .padding()
    }
    .navigationTitle(isCompletionFlow ? "Complete Round" : "Round Stats")
    .task {
      await loadStats()
    }
    .alert("Missing scores", isPresented: $showMissingScoresAlert) {
      Button("Complete anyway", role: .destructive) {
        performComplete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      let missing = (1...18).filter { !holesWithScores.contains($0) }
      Text("Holes \(missing.map(\.description).joined(separator: ", ")) have no scores. Complete anyway?")
    }
    .navigationDestination(item: $completedRound) { r in
      RoundDetailView(round: r)
    }
  }

  private var completeRoundSection: some View {
    VStack(spacing: 12) {
      Button {
        attemptComplete()
      } label: {
        Text("Complete round")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(.top, 8)
  }
  
  // MARK: - Sections (v1 canonical: total score, total putts only)

  private var v1StatsSection: some View {
    HStack(spacing: 16) {
      StatCard(
        title: "Score",
        value: totalScoreFromHoleScores == 0 ? "—" : "\(totalScoreFromHoleScores)",
        subtitle: scoreToPar.map(scoreToParText) ?? "From scorecard",
        color: scoreToPar.map(scoreColor) ?? .primary
      )

      StatCard(
        title: "Putts",
        value: totalPuttsFromHoleScores == 0 ? "—" : "\(totalPuttsFromHoleScores)",
        subtitle: "From scorecard",
        color: .blue
      )
    }
  }
  
  // MARK: - Helpers
  
  private func scoreToParText(_ scoreToPar: Int) -> String {
    if scoreToPar == 0 { return "Even Par" }
    if scoreToPar > 0 { return "+\(scoreToPar)" }
    return "\(scoreToPar)"
  }
  
  private func scoreColor(_ scoreToPar: Int) -> Color {
    if scoreToPar <= 0 { return .green }
    if scoreToPar <= 5 { return .yellow }
    return .orange
  }
  
  private func loadStats() async {
    isLoading = true
    errorMessage = nil

    do {
      let totalScore = try GCDB.shared.totalScoreFromHoleScores(roundId: roundId)
      let totalPutts = try GCDB.shared.totalPuttsFromHoleScores(roundId: roundId)
      let scored = try GCDB.shared.holesWithScores(roundId: roundId)
      let round = try GCDB.shared.fetchRound(roundId: roundId)

      await MainActor.run {
        self.totalScoreFromHoleScores = totalScore
        self.totalPuttsFromHoleScores = totalPutts
        self.holesWithScores = scored
        self.tee = round?.tee ?? .blue
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.errorMessage = error.localizedDescription
        self.isLoading = false
      }
    }
  }

  private func attemptComplete() {
    let missing = (1...18).filter { !holesWithScores.contains($0) }
    if !missing.isEmpty {
      showMissingScoresAlert = true
    } else {
      performComplete()
    }
  }

  private func performComplete() {
    do {
      try GCDB.shared.completeRound(roundId: roundId)
      state.activeRoundId = nil
      state.holeNumber = 1
      if let r = try? GCDB.shared.fetchRound(roundId: roundId) {
        completedRound = r
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - Supporting Views

struct StatCard: View {
  let title: String
  let value: String
  let subtitle: String
  let color: Color
  
  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
        .textCase(.uppercase)
      
      Text(value)
        .font(.system(size: 36, weight: .bold, design: .rounded))
        .foregroundColor(color)
      
      Text(subtitle)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    RoundStatsView(
      roundId: 1,
      course: try! CourseLoader.loadGreystonesCourse()
    )
  }
}
