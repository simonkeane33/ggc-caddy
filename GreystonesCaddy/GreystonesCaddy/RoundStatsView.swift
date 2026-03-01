import SwiftUI
import GreystonesCaddyCore

/// Displays comprehensive stats for a round.
struct RoundStatsView: View {
  let roundId: Int64
  let course: CourseBundle
  
  @State private var stats: RoundStatsSummary?
  @State private var holeStats: [HoleStats] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        if isLoading {
          ProgressView("Calculating stats...")
            .padding()
        } else if let error = errorMessage {
          Text("Error: \(error)")
            .foregroundColor(.red)
            .padding()
        } else if let stats = stats {
          // Summary Cards
          summarySection(stats: stats)
          
          // Detailed Stats Grid
          statsGrid(stats: stats)
          
          // Hole-by-Hole Breakdown
          holeBreakdownSection
        }
      }
      .padding()
    }
    .navigationTitle("Round Stats")
    .task {
      await loadStats()
    }
  }
  
  // MARK: - Sections
  
  private func summarySection(stats: RoundStatsSummary) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 16) {
        StatCard(
          title: "Score",
          value: "\(stats.totalStrokes)",
          subtitle: scoreToParText(stats.scoreToPar),
          color: scoreColor(stats.scoreToPar)
        )
        
        StatCard(
          title: "Putts",
          value: "\(stats.totalPutts)",
          subtitle: String(format: "%.1f per round", stats.puttsPerRound),
          color: .blue
        )
      }
      
      if stats.totalPenalties > 0 {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
          Text("\(stats.totalPenalties) penalty strokes")
            .font(.subheadline)
            .foregroundColor(.orange)
          Spacer()
        }
        .padding(.horizontal, 4)
      }
    }
  }
  
  private func statsGrid(stats: RoundStatsSummary) -> some View {
    VStack(spacing: 12) {
      Text("Key Statistics")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        PercentageStatCard(
          title: "Greens in Regulation",
          percentage: stats.girPercentage,
          count: stats.girCount,
          opportunities: stats.girOpportunities,
          icon: "flag.fill",
          color: .green
        )
        
        PercentageStatCard(
          title: "Fairways Hit",
          percentage: stats.fairwayPercentage,
          count: stats.fairwayCount,
          opportunities: stats.fairwayOpportunities,
          icon: "arrow.up",
          color: .blue
        )
        
        PercentageStatCard(
          title: "Scramble Success",
          percentage: stats.scramblePercentage,
          count: stats.scrambleCount,
          opportunities: stats.scrambleOpportunities,
          icon: "arrow.2.squarepath",
          color: .orange
        )
        
        StatCard(
          title: "Putts/Round",
          value: String(format: "%.1f", stats.puttsPerRound),
          subtitle: stats.puttsPerRound < 30 ? "Great!" : stats.puttsPerRound < 34 ? "Good" : "Work on putting",
          color: stats.puttsPerRound < 30 ? .green : stats.puttsPerRound < 34 ? .yellow : .orange
        )
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var holeBreakdownSection: some View {
    VStack(spacing: 12) {
      Text("Hole-by-Hole")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      ForEach(holeStats) { hole in
        HoleStatRow(hole: hole, course: course)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
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
      // Compute stats if needed
      let summary = try GCDB.shared.computeAndStoreRoundStats(roundId: roundId, course: course)
      let holes = try GCDB.shared.fetchHoleStatsForRound(roundId: roundId)
      
      await MainActor.run {
        self.stats = summary
        self.holeStats = holes
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.errorMessage = error.localizedDescription
        self.isLoading = false
      }
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

struct PercentageStatCard: View {
  let title: String
  let percentage: Double?
  let count: Int
  let opportunities: Int
  let icon: String
  let color: Color
  
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Image(systemName: icon)
          .foregroundColor(color)
        Text(title)
          .font(.caption)
          .foregroundColor(.secondary)
          .textCase(.uppercase)
      }
      
      if let pct = percentage {
        Text("\(Int(pct))%")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundColor(color)
        
        Text("\(count)/\(opportunities)")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        Text("--")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundColor(.secondary)
        
        Text("No data")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
  }
}

struct HoleStatRow: View {
  let hole: HoleStats
  let course: CourseBundle
  
  var body: some View {
    HStack(spacing: 12) {
      // Hole number
      Text("\(hole.holeNumber)")
        .font(.system(.body, design: .rounded, weight: .bold))
        .frame(width: 32, height: 32)
        .background(scoreBackgroundColor)
        .foregroundColor(scoreForegroundColor)
        .clipShape(Circle())
      
      // Hole info
      VStack(alignment: .leading, spacing: 2) {
        if let holeName = course.holes.first(where: { $0.number == hole.holeNumber })?.name {
          Text(holeName)
            .font(.subheadline)
            .fontWeight(.medium)
        }
        Text("Par \(hole.par)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      
      Spacer()
      
      // Stats indicators
      HStack(spacing: 8) {
        if hole.gir == true {
          GIRBadge()
        }
        if hole.fairwayHit == true {
          FairwayBadge()
        }
        if hole.scramble == true {
          ScrambleBadge()
        }
        
        // Score
        Text("\(hole.strokes)")
          .font(.system(.body, design: .rounded, weight: .semibold))
          .foregroundColor(scoreToParColor(hole.scoreToPar))
      }
    }
    .padding(.vertical, 4)
  }
  
  private var scoreBackgroundColor: Color {
    if hole.scoreToPar <= -1 { return .green }
    if hole.scoreToPar == 0 { return .blue }
    if hole.scoreToPar == 1 { return .yellow }
    return .orange
  }
  
  private var scoreForegroundColor: Color {
    if hole.scoreToPar <= 0 { return .white }
    return .black
  }
  
  private func scoreToParColor(_ diff: Int) -> Color {
    if diff <= 0 { return .green }
    if diff <= 1 { return .primary }
    return .orange
  }
}

struct GIRBadge: View {
  var body: some View {
    Text("GIR")
      .font(.caption2)
      .fontWeight(.bold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.green.opacity(0.2))
      .foregroundColor(.green)
      .cornerRadius(4)
  }
}

struct FairwayBadge: View {
  var body: some View {
    Image(systemName: "arrow.up")
      .font(.caption2)
      .fontWeight(.bold)
      .padding(4)
      .background(Color.blue.opacity(0.2))
      .foregroundColor(.blue)
      .clipShape(Circle())
  }
}

struct ScrambleBadge: View {
  var body: some View {
    Text("UP")
      .font(.caption2)
      .fontWeight(.bold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.orange.opacity(0.2))
      .foregroundColor(.orange)
      .cornerRadius(4)
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
