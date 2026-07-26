import SwiftUI
import GreystonesCaddyCore

/// Shows detailed insights for a specific hole based on historical performance.
struct HoleInsightsView: View {
  let holeNumber: Int
  let course: CourseBundle
  
  @State private var performance: HolePerformance?
  @State private var isLoading = true
  
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        if isLoading {
          ProgressView("Loading insights...")
            .padding()
        } else if let perf = performance {
          headerSection(perf)
          keyStatsSection(perf)
          scoreDistributionSection(perf)
          tipSection(perf)
        } else {
          ContentUnavailableView(
            "No Data Yet",
            systemImage: "chart.bar",
            description: Text("Play this hole a few times to see insights")
          )
        }
      }
      .padding()
    }
    .navigationTitle("Hole \(holeNumber) Insights")
    .task {
      await loadInsights()
    }
  }
  
  // MARK: - Sections
  
  private func headerSection(_ perf: HolePerformance) -> some View {
    VStack(spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(perf.holeName)
            .font(.title2)
            .fontWeight(.bold)
          Text("Par \(perf.par) • Played \(perf.roundsPlayed) times")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        
        Spacer()
        
        if let rank = perf.difficultyRank {
          DifficultyBadge(rank: rank, totalHoles: 18)
        }
      }
      
      HStack(spacing: 16) {
        StatBox(
          label: "Best",
          value: "\(perf.bestScore)",
          color: .green
        )
        
        StatBox(
          label: "Average",
          value: String(format: "%.1f", perf.avgScore),
          color: .blue
        )
        
        StatBox(
          label: "Worst",
          value: "\(perf.worstScore)",
          color: perf.worstScore > perf.par + 2 ? .orange : .secondary
        )
      }
      
      if perf.avgStrokesOverPar > 1.0 {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
          Text("Averaging +\(String(format: "%.1f", perf.avgStrokesOverPar)) strokes over par")
            .font(.subheadline)
            .foregroundColor(.orange)
          Spacer()
        }
        .padding(.top, 4)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private func keyStatsSection(_ perf: HolePerformance) -> some View {
    VStack(spacing: 12) {
      Text("Your Performance")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      VStack(spacing: 16) {
        // GIR
        if let gir = perf.girPercentage {
          StatRow(
            icon: "flag.fill",
            title: "Greens in Regulation",
            value: "\(Int(gir))%",
            detail: "\(Int(gir * Double(perf.roundsPlayed) / 100))/\(perf.roundsPlayed)",
            progress: gir / 100,
            color: .green
          )
        }
        
        // FIR (only for par 4/5)
        if perf.par >= 4, let fir = perf.fairwayPercentage {
          StatRow(
            icon: "arrow.up",
            title: "Fairways Hit",
            value: "\(Int(fir))%",
            detail: nil,
            progress: fir / 100,
            color: .blue
          )
        }
        
        // Scrambling
        if let scramble = perf.scramblePercentage {
          StatRow(
            icon: "arrow.2.squarepath",
            title: "Scramble Success",
            value: "\(Int(scramble))%",
            detail: nil,
            progress: scramble / 100,
            color: .orange
          )
        }
        
        // Putts
        StatRow(
          icon: "circle.fill",
          title: "Avg Putts",
          value: String(format: "%.1f", perf.avgPutts),
          detail: nil,
          progress: min(perf.avgPutts / 3.0, 1.0), // 3 putts = max
          color: .purple
        )
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private func scoreDistributionSection(_ perf: HolePerformance) -> some View {
    VStack(spacing: 12) {
      Text("Recent Trend")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      HStack(spacing: 12) {
        Image(systemName: perf.trend.icon)
          .font(.title2)
          .foregroundColor(trendColor(perf.trend))
          .frame(width: 44, height: 44)
          .background(trendColor(perf.trend).opacity(0.1))
          .clipShape(Circle())
        
        VStack(alignment: .leading, spacing: 4) {
          Text("\(perf.trend.rawValue)")
            .font(.headline)
            .foregroundColor(trendColor(perf.trend))
          
          if let last5 = perf.last5Avg {
            Text("Last 5 rounds averaging \(String(format: "%.1f", last5))")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }
        
        Spacer()
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  @ViewBuilder
  private func tipSection(_ perf: HolePerformance) -> some View {
    if let tip = HoleInsightsEngine.generateHoleTip(performance: perf) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "lightbulb.fill")
            .foregroundColor(.yellow)
          Text("Caddy Tip")
            .font(.headline)
        }
        
        Text(tip)
          .font(.subheadline)
          .foregroundColor(.primary)
      }
      .padding()
      .background(Color.yellow.opacity(0.1))
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
      )
    }
  }
  
  // MARK: - Helpers
  
  private func trendColor(_ trend: HoleTrend) -> Color {
    switch trend {
    case .improving: return .green
    case .stable: return .gray
    case .worsening: return .orange
    }
  }
  
  private func loadInsights() async {
    isLoading = true
    
    do {
      // Fetch all hole stats for this hole across all rounds
      let allHoleStats = try fetchAllHoleStats(holeNumber: holeNumber)
      
      // Calculate performance
      let performances = HoleInsightsEngine.calculateHolePerformances(
        holeStats: allHoleStats,
        course: course
      )
      
      await MainActor.run {
        self.performance = performances.first { $0.holeNumber == holeNumber }
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
    }
  }
  
  private func fetchAllHoleStats(holeNumber: Int) throws -> [HoleStats] {
    // Get all round IDs first
    let rounds = try GCDB.shared.listCompletedRounds(limit: 100)
    
    var allStats: [HoleStats] = []
    for round in rounds {
      if let stats = try? GCDB.shared.fetchHoleStatsForRound(roundId: round.id) {
        allStats.append(contentsOf: stats.filter { $0.holeNumber == holeNumber })
      }
    }
    
    return allStats
  }
}

// MARK: - Supporting Views

struct DifficultyBadge: View {
  let rank: Int
  let totalHoles: Int
  
  var body: some View {
    VStack(spacing: 2) {
      Text("#\(rank)")
        .font(.title3)
        .fontWeight(.bold)
      Text("Hardest")
        .font(.caption2)
    }
    .foregroundColor(difficultyColor)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(difficultyColor.opacity(0.1))
    .cornerRadius(8)
  }
  
  private var difficultyColor: Color {
    if rank <= 3 { return .red }
    if rank <= 6 { return .orange }
    if rank >= totalHoles - 2 { return .green }
    return .blue
  }
}

struct StatBox: View {
  let label: String
  let value: String
  let color: Color
  
  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundColor(color)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }
}

struct StatRow: View {
  let icon: String
  let title: String
  let value: String
  let detail: String?
  let progress: Double
  let color: Color
  
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(color)
        .frame(width: 24)
      
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(title)
            .font(.subheadline)
          Spacer()
          Text(value)
            .font(.system(.body, design: .rounded, weight: .semibold))
        }
        
        GeometryReader { geo in
          RoundedRectangle(cornerRadius: 2)
            .fill(Color(.systemGray5))
            .overlay(
              RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: geo.size.width * min(progress, 1.0))
              , alignment: .leading
            )
        }
        .frame(height: 4)
        
        if let detail = detail {
          Text(detail)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    HoleInsightsView(
      holeNumber: 1,
      course: try! CourseLoader.loadGreystonesCourse()
    )
  }
}
