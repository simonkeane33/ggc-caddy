import SwiftUI
import GreystonesCaddyCore

/// Overview of all holes showing strengths, weaknesses, and performance summary.
struct CourseInsightsView: View {
  let course: CourseBundle
  
  @State private var performances: [HolePerformance] = []
  @State private var strengths: [HolePerformance] = []
  @State private var weaknesses: [HolePerformance] = []
  @State private var isLoading = true
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          if isLoading {
            ProgressView("Analyzing your game...")
              .padding()
          } else if performances.isEmpty {
            ContentUnavailableView(
              "No Data Yet",
              systemImage: "chart.bar",
              description: Text("Complete a few rounds to see course insights")
            )
          } else {
            // Summary Header
            summaryHeader
            
            // Weaknesses (holes to improve)
            if !weaknesses.isEmpty {
              weaknessesSection
            }
            
            // Strengths (holes you own)
            if !strengths.isEmpty {
              strengthsSection
            }
            
            // All holes grid
            allHolesSection
          }
        }
        .padding()
      }
      .navigationTitle("Course Insights")
      .task {
        await loadInsights()
      }
    }
  }
  
  // MARK: - Sections
  
  private var summaryHeader: some View {
    VStack(spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(course.course.name)
            .font(.title2)
            .fontWeight(.bold)
          Text("Based on your last \(totalRoundsPlayed) rounds")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        
        Spacer()
      }
      
      HStack(spacing: 16) {
        SummaryStatBox(
          label: "Avg Score",
          value: String(format: "%.1f", overallAvgScore),
          color: .blue
        )
        
        SummaryStatBox(
          label: "Avg To Par",
          value: String(format: "+%.1f", overallAvgToPar),
          color: overallAvgToPar > 10 ? .orange : .green
        )
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var weaknessesSection: some View {
    VStack(spacing: 12) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
        Text("Work On These Holes")
          .font(.headline)
        Spacer()
      }
      
      VStack(spacing: 8) {
        ForEach(weaknesses) { perf in
          HoleRow(performance: perf, showDifficultyRank: true)
        }
      }
    }
    .padding()
    .background(Color.orange.opacity(0.05))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
    )
  }
  
  private var strengthsSection: some View {
    VStack(spacing: 12) {
      HStack {
        Image(systemName: "star.fill")
          .foregroundColor(.green)
        Text("Your Best Holes")
          .font(.headline)
        Spacer()
      }
      
      VStack(spacing: 8) {
        ForEach(strengths) { perf in
          HoleRow(performance: perf, showDifficultyRank: false)
        }
      }
    }
    .padding()
    .background(Color.green.opacity(0.05))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.green.opacity(0.2), lineWidth: 1)
    )
  }
  
  private var allHolesSection: some View {
    VStack(spacing: 12) {
      Text("All Holes")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
        ForEach(performances) { perf in
          NavigationLink {
            HoleInsightsView(holeNumber: perf.holeNumber, course: course)
          } label: {
            HoleGridCell(performance: perf)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  // MARK: - Computed Properties
  
  private var totalRoundsPlayed: Int {
    performances.map { $0.roundsPlayed }.max() ?? 0
  }
  
  private var overallAvgScore: Double {
    let totalScore = performances.reduce(0.0) { $0 + ($1.avgScore * Double($1.roundsPlayed)) }
    let totalRounds = performances.reduce(0) { $0 + $1.roundsPlayed }
    return totalRounds > 0 ? totalScore / Double(totalRounds) : 0
  }
  
  private var overallAvgToPar: Double {
    let totalPar = performances.reduce(0) { $0 + ($1.par * $1.roundsPlayed) }
    let totalRounds = performances.reduce(0) { $0 + $1.roundsPlayed }
    return totalRounds > 0 ? overallAvgScore - (Double(totalPar) / Double(totalRounds)) : 0
  }
  
  // MARK: - Helpers
  
  private func loadInsights() async {
    isLoading = true
    
    do {
      // Fetch all hole stats for all rounds
      let allStats = try fetchAllHoleStats()
      
      // Calculate performances
      let perfs = HoleInsightsEngine.calculateHolePerformances(
        holeStats: allStats,
        course: course
      )
      
      // Identify strengths and weaknesses
      let (str, weak) = HoleInsightsEngine.identifyStrengthsAndWeaknesses(performances: perfs)
      
      await MainActor.run {
        self.performances = perfs
        self.strengths = str
        self.weaknesses = weak
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
    }
  }
  
  private func fetchAllHoleStats() throws -> [HoleStats] {
    let rounds = try GCDB.shared.listRounds(limit: 100)
    
    var allStats: [HoleStats] = []
    for round in rounds {
      if let stats = try? GCDB.shared.fetchHoleStatsForRound(roundId: round.id) {
        allStats.append(contentsOf: stats)
      }
    }
    
    return allStats
  }
}

// MARK: - Supporting Views

struct SummaryStatBox: View {
  let label: String
  let value: String
  let color: Color
  
  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.system(.title2, design: .rounded, weight: .bold))
        .foregroundColor(color)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(8)
  }
}

struct HoleRow: View {
  let performance: HolePerformance
  let showDifficultyRank: Bool
  
  var body: some View {
    HStack {
      // Hole number circle
      Text("\(performance.holeNumber)")
        .font(.system(.body, design: .rounded, weight: .bold))
        .frame(width: 32, height: 32)
        .background(scoreColor)
        .foregroundColor(.white)
        .clipShape(Circle())
      
      VStack(alignment: .leading, spacing: 2) {
        Text(performance.holeName)
          .font(.subheadline)
          .fontWeight(.medium)
        
        HStack(spacing: 8) {
          Text("Par \(performance.par)")
            .font(.caption)
            .foregroundColor(.secondary)
          
          if showDifficultyRank, let rank = performance.difficultyRank {
            Text("#\(rank) Hardest")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }
      }
      
      Spacer()
      
      VStack(alignment: .trailing, spacing: 2) {
        Text("\(performance.bestScore)-\(Int(performance.avgScore))-\(performance.worstScore)")
          .font(.system(.body, design: .rounded, weight: .medium))
        
        if performance.avgStrokesOverPar > 0 {
          Text("+\(String(format: "%.1f", performance.avgStrokesOverPar))")
            .font(.caption)
            .foregroundColor(.orange)
        }
      }
    }
    .padding(.vertical, 4)
  }
  
  private var scoreColor: Color {
    if performance.avgStrokesOverPar <= 0 { return .green }
    if performance.avgStrokesOverPar <= 1 { return .blue }
    if performance.avgStrokesOverPar <= 2 { return .orange }
    return .red
  }
}

struct HoleGridCell: View {
  let performance: HolePerformance
  
  var body: some View {
    VStack(spacing: 8) {
      Text("\(performance.holeNumber)")
        .font(.system(.title2, design: .rounded, weight: .bold))
        .foregroundColor(.primary)
      
      Text("\(Int(performance.avgScore))")
        .font(.system(.body, design: .rounded, weight: .medium))
        .foregroundColor(avgScoreColor)
      
      if let rank = performance.difficultyRank {
        Text("#\(rank)")
          .font(.caption2)
          .foregroundColor(rankColor(rank))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(rankColor(rank).opacity(0.1))
          .cornerRadius(4)
      }
    }
    .frame(width: 60, height: 80)
    .background(Color(.systemBackground))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(.systemGray4), lineWidth: 1)
    )
  }
  
  private var avgScoreColor: Color {
    if performance.avgStrokesOverPar <= 0 { return .green }
    if performance.avgStrokesOverPar <= 1 { return .blue }
    if performance.avgStrokesOverPar <= 2 { return .orange }
    return .red
  }
  
  private func rankColor(_ rank: Int) -> Color {
    if rank <= 3 { return .red }
    if rank <= 6 { return .orange }
    if rank >= 16 { return .green }
    return .blue
  }
}

// MARK: - Preview

#Preview {
  CourseInsightsView(course: try! CourseLoader.loadGreystonesCourse())
}
