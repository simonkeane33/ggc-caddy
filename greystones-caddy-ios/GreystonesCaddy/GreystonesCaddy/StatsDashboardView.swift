import SwiftUI
import GreystonesCaddyCore
import Charts

/// Dashboard showing aggregated stats and trends across all rounds.
struct StatsDashboardView: View {
  @State private var aggregatedStats: AggregatedStats?
  @State private var recentRounds: [RoundStatsSummary] = []
  @State private var isLoading = true
  @State private var selectedTimeRange: TimeRange = .last20
  
  enum TimeRange: String, CaseIterable {
    case last5 = "Last 5"
    case last10 = "Last 10"
    case last20 = "Last 20"
    case allTime = "All Time"
    
    var limit: Int {
      switch self {
      case .last5: return 5
      case .last10: return 10
      case .last20: return 20
      case .allTime: return 100
      }
    }
  }
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          if isLoading {
            ProgressView("Loading stats...")
              .padding()
          } else if let stats = aggregatedStats {
            // Time Range Picker
            timeRangePicker
            
            // Overview Cards
            overviewSection(stats: stats)
            
            // Trends Chart
            if !recentRounds.isEmpty {
              trendsChartSection
            }
            
            // Detailed Breakdown
            detailedStatsSection(stats: stats)
          } else {
            ContentUnavailableView(
              "No Stats Available",
              systemImage: "chart.bar",
              description: Text("Complete a round to see your statistics")
            )
          }
        }
        .padding()
      }
      .navigationTitle("Stats Dashboard")
      .task {
        await loadStats()
      }
    }
  }
  
  // MARK: - Sections
  
  private var timeRangePicker: some View {
    Picker("Time Range", selection: $selectedTimeRange) {
      ForEach(TimeRange.allCases, id: \.self) { range in
        Text(range.rawValue).tag(range)
      }
    }
    .pickerStyle(.segmented)
    .onChange(of: selectedTimeRange) { _, _ in
      Task {
        await loadStats()
      }
    }
  }
  
  private func overviewSection(stats: AggregatedStats) -> some View {
    VStack(spacing: 16) {
      HStack(spacing: 16) {
        OverviewCard(
          title: "Avg Score",
          value: stats.avgScoreToPar != nil ? String(format: "%.1f", stats.avgScoreToPar!) : "--",
          subtitle: "to par",
          trend: stats.avgScoreToPar,
          target: 0,
          lowerIsBetter: true,
          color: .blue
        )
        
        OverviewCard(
          title: "Best Round",
          value: stats.bestScoreToPar != nil ? "\(stats.bestScoreToPar!)" : "--",
          subtitle: "to par",
          trend: nil,
          target: nil,
          lowerIsBetter: true,
          color: .green
        )
      }
      
      Text("Based on \(stats.roundsAnalyzed) rounds")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
  
  private var trendsChartSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Score Trend")
        .font(.headline)
      
      Chart {
        ForEach(Array(recentRounds.enumerated()), id: \.element.roundId) { index, round in
          LineMark(
            x: .value("Round", index + 1),
            y: .value("Score", round.scoreToPar)
          )
          .foregroundStyle(round.scoreToPar <= 0 ? .green : .orange)
          
          PointMark(
            x: .value("Round", index + 1),
            y: .value("Score", round.scoreToPar)
          )
          .foregroundStyle(scoreColor(round.scoreToPar))
        }
        
        RuleMark(y: .value("Par", 0))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
          .foregroundStyle(.gray)
      }
      .frame(height: 200)
      .chartYAxis {
        AxisMarks(position: .leading)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private func detailedStatsSection(stats: AggregatedStats) -> some View {
    VStack(spacing: 16) {
      Text("Performance Breakdown")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      // GIR
      StatProgressRow(
        title: "Greens in Regulation",
        percentage: stats.avgGIRPercentage,
        icon: "flag.fill",
        color: .green,
        benchmark: 50 // PGA Tour avg ~65%, good amateurs ~50%
      )
      
      // Fairways
      StatProgressRow(
        title: "Fairways Hit",
        percentage: stats.avgFairwayPercentage,
        icon: "arrow.up",
        color: .blue,
        benchmark: 50 // PGA Tour avg ~60%
      )
      
      // Scrambling
      StatProgressRow(
        title: "Scramble Success",
        percentage: stats.avgScramblePercentage,
        icon: "arrow.2.squarepath",
        color: .orange,
        benchmark: 40 // PGA Tour avg ~58%, good amateurs ~40%
      )
      
      // Putts
      if let putts = stats.avgPuttsPerRound {
        HStack {
          HStack(spacing: 8) {
            Image(systemName: "circle.fill")
              .foregroundColor(.purple)
              .font(.caption)
            Text("Putts per Round")
              .font(.subheadline)
          }
          
          Spacer()
          
          Text(String(format: "%.1f", putts))
            .font(.system(.body, design: .rounded, weight: .semibold))
          
          // Benchmark indicator
          if putts < 30 {
            Text("Excellent")
              .font(.caption)
              .foregroundColor(.green)
          } else if putts < 34 {
            Text("Good")
              .font(.caption)
              .foregroundColor(.blue)
          } else {
            Text("Work on putting")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }
        .padding(.vertical, 4)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  // MARK: - Helpers
  
  private func scoreColor(_ scoreToPar: Int) -> Color {
    if scoreToPar <= 0 { return .green }
    if scoreToPar <= 3 { return .yellow }
    return .orange
  }
  
  private func loadStats() async {
    isLoading = true
    
    do {
      let stats = try GCDB.shared.fetchAggregatedStats(limit: selectedTimeRange.limit)
      
      // Fetch recent rounds for chart
      let rounds = try GCDB.shared.listRounds(limit: selectedTimeRange.limit)
      var roundStats: [RoundStatsSummary] = []
      for round in rounds {
        if let stats = try GCDB.shared.fetchRoundStats(roundId: round.id) {
          roundStats.append(stats)
        }
      }
      // Reverse to show oldest first for chart
      roundStats.reverse()
      
      await MainActor.run {
        self.aggregatedStats = stats
        self.recentRounds = roundStats
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
    }
  }
}

// MARK: - Supporting Views

struct OverviewCard: View {
  let title: String
  let value: String
  let subtitle: String
  let trend: Double?
  let target: Double?
  let lowerIsBetter: Bool
  let color: Color
  
  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
        .textCase(.uppercase)
      
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value)
          .font(.system(size: 32, weight: .bold, design: .rounded))
          .foregroundColor(color)
        
        Text(subtitle)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      
      if let trend = trend, let target = target {
        let diff = trend - target
        let isGood = lowerIsBetter ? diff <= 0 : diff >= 0
        
        HStack(spacing: 4) {
          Image(systemName: isGood ? "arrow.down" : "arrow.up")
          Text(String(format: "%.1f", abs(diff)))
        }
        .font(.caption)
        .foregroundColor(isGood ? .green : .orange)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
  }
}

struct StatProgressRow: View {
  let title: String
  let percentage: Double?
  let icon: String
  let color: Color
  let benchmark: Double
  
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        HStack(spacing: 8) {
          Image(systemName: icon)
            .foregroundColor(color)
          Text(title)
            .font(.subheadline)
        }
        
        Spacer()
        
        if let pct = percentage {
          Text("\(Int(pct))%")
            .font(.system(.body, design: .rounded, weight: .semibold))
        } else {
          Text("--")
            .foregroundColor(.secondary)
        }
      }
      
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          // Background
          RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemGray5))
            .frame(height: 8)
          
          // Progress
          if let pct = percentage {
            RoundedRectangle(cornerRadius: 4)
              .fill(color)
              .frame(width: geo.size.width * min(pct / 100, 1), height: 8)
          }
          
          // Benchmark marker
          Circle()
            .fill(.white)
            .frame(width: 10, height: 10)
            .shadow(radius: 2)
            .offset(x: geo.size.width * (benchmark / 100) - 5)
        }
      }
      .frame(height: 10)
      
      HStack {
        Text("0%")
          .font(.caption2)
          .foregroundColor(.secondary)
        Spacer()
        Text("Benchmark: \(Int(benchmark))%")
          .font(.caption2)
          .foregroundColor(.secondary)
        Spacer()
        Text("100%")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Preview

#Preview {
  StatsDashboardView()
}
