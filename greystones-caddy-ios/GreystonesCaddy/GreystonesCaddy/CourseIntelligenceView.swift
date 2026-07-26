import SwiftUI
import GreystonesCaddyCore

/// Course Intelligence dashboard showing user vs community comparisons.
struct CourseIntelligenceView: View {
  let course: CourseBundle
  
  @State private var communityStats: [Int: HoleCommunityStats] = [:]
  @State private var userComparisons: [UserVsCommunityComparison] = []
  @State private var courseIntel: CourseIntelligence?
  @State private var personalizedInsights: [String] = []
  @State private var isLoading = true
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          if isLoading {
            ProgressView("Analyzing course data...")
              .padding()
          } else if let intel = courseIntel {
            // Course Overview
            courseOverviewSection(intel: intel)
            
            // Personalized Insights
            if !personalizedInsights.isEmpty {
              insightsSection
            }
            
            // User vs Community Summary
            comparisonSummarySection
            
            // Hole Rankings
            holeRankingsSection
            
            // Benchmark Scores
            benchmarkSection(intel: intel)
          } else {
            ContentUnavailableView(
              "No Data Available",
              systemImage: "chart.bar.xaxis",
              description: Text("Course intelligence data not available")
            )
          }
        }
        .padding()
      }
      .navigationTitle("Course Intelligence")
      .task {
        await loadCourseIntelligence()
      }
    }
  }
  
  // MARK: - Sections
  
  private func courseOverviewSection(intel: CourseIntelligence) -> some View {
    VStack(spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(intel.courseName)
            .font(.title2)
            .fontWeight(.bold)
          
          Text("Based on \(intel.totalRoundsAnalyzed) rounds from \(intel.uniqueGolfers) golfers")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        
        Spacer()
      }
      
      HStack(spacing: 16) {
        DifficultyRatingCard(
          rating: intel.courseDifficultyRating,
          percentile: intel.courseDifficultyPercentile
        )
        
        VStack(alignment: .leading, spacing: 8) {
          Text("Relative Difficulty")
            .font(.caption)
            .foregroundColor(.secondary)
          
          Text("Harder than \(intel.courseDifficultyPercentile)% of courses")
            .font(.subheadline)
            .fontWeight(.medium)
          
          ProgressView(value: Double(intel.courseDifficultyPercentile), total: 100)
            .tint(difficultyColor(intel.courseDifficultyPercentile))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      
      HStack(spacing: 12) {
        HoleListCard(
          title: "Hardest Holes",
          holes: intel.hardestHoles,
          color: .red,
          icon: "exclamationmark.triangle.fill"
        )
        
        HoleListCard(
          title: "Easiest Holes",
          holes: intel.easiestHoles,
          color: .green,
          icon: "checkmark.circle.fill"
        )
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var insightsSection: some View {
    VStack(spacing: 12) {
      HStack {
        Image(systemName: "lightbulb.fill")
          .foregroundColor(.yellow)
        Text("Your Insights")
          .font(.headline)
        Spacer()
      }
      
      VStack(alignment: .leading, spacing: 12) {
        ForEach(personalizedInsights, id: \.self) { insight in
          HStack(alignment: .top, spacing: 8) {
            Text("•")
              .font(.title3)
              .foregroundColor(.blue)
            Text(insight)
              .font(.subheadline)
            Spacer()
          }
        }
      }
    }
    .padding()
    .background(Color.yellow.opacity(0.1))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
    )
  }
  
  private var comparisonSummarySection: some View {
    VStack(spacing: 12) {
      HStack {
        Text("You vs The Field")
          .font(.headline)
        Spacer()
      }
      
      let avgPercentile = userComparisons.isEmpty ? 0 : userComparisons.reduce(0.0) { $0 + $1.userPercentile } / Double(userComparisons.count)
      
      HStack(spacing: 16) {
        VStack(spacing: 8) {
          Text("\(Int(avgPercentile))%")
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .foregroundColor(percentileColor(avgPercentile))
          
          Text("Average Percentile")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        
        Divider()
        
        VStack(alignment: .leading, spacing: 8) {
          Text(percentileDescription(avgPercentile))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(percentileColor(avgPercentile))
          
          Text("You typically play this course better than \(Int(avgPercentile))% of golfers")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.vertical, 8)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var holeRankingsSection: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Hole-by-Hole Performance")
          .font(.headline)
        Spacer()
      }
      
      // Sort by user percentile (best first)
      let sortedComparisons = userComparisons.sorted { $0.userPercentile > $1.userPercentile }
      
      ForEach(sortedComparisons.prefix(9)) { comparison in
        NavigationLink {
          HoleIntelligenceDetailView(comparison: comparison, course: course)
        } label: {
          ComparisonRow(comparison: comparison)
        }
        .buttonStyle(.plain)
      }
      
      if sortedComparisons.count > 9 {
        Text("+ \(sortedComparisons.count - 9) more holes")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 8)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private func benchmarkSection(intel: CourseIntelligence) -> some View {
    VStack(spacing: 12) {
      HStack {
        Text("Score Benchmarks")
          .font(.headline)
        Spacer()
      }
      
      VStack(spacing: 16) {
        BenchmarkRow(
          label: "Scratch Golfer",
          avgScore: intel.scratchGolferAvgScore,
          description: "(0 handicap)",
          color: .green
        )
        
        BenchmarkRow(
          label: "Mid Handicap",
          avgScore: intel.midHandicapAvgScore,
          description: "(10-15 handicap)",
          color: .blue
        )
        
        BenchmarkRow(
          label: "Bogey Golfer",
          avgScore: intel.bogeyGolferAvgScore,
          description: "(18+ handicap)",
          color: .orange
        )
      }
      
      Text("Average 18-hole score")
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  // MARK: - Helpers
  
  private func difficultyColor(_ percentile: Int) -> Color {
    if percentile >= 70 { return .red }
    if percentile >= 50 { return .orange }
    if percentile >= 30 { return .yellow }
    return .green
  }
  
  private func percentileColor(_ percentile: Double) -> Color {
    if percentile >= 75 { return .green }
    if percentile >= 50 { return .blue }
    if percentile >= 25 { return .yellow }
    return .orange
  }
  
  private func percentileDescription(_ percentile: Double) -> String {
    if percentile >= 90 { return "Elite Performance" }
    if percentile >= 75 { return "Strong Player" }
    if percentile >= 50 { return "Above Average" }
    if percentile >= 25 { return "Average" }
    return "Developing"
  }
  
  private func loadCourseIntelligence() async {
    isLoading = true
    
    // Generate simulated community stats (in production, fetch from server)
    let community = CourseIntelligenceEngine.generateSimulatedCommunityStats(course: course)
    
    // Get user's performance data
    do {
      let allStats = try fetchAllHoleStats()
      let performances = HoleInsightsEngine.calculateHolePerformances(
        holeStats: allStats,
        course: course
      )
      
      // Compare user to community
      var comparisons: [UserVsCommunityComparison] = []
      for perf in performances {
        if let communityStat = community[perf.holeNumber] {
          let comparison = CourseIntelligenceEngine.compareUserToCommunity(
            userPerformance: perf,
            communityStats: communityStat
          )
          comparisons.append(comparison)
        }
      }
      
      // Generate course intelligence
      let intel = CourseIntelligenceEngine.generateCourseIntelligence(
        course: course,
        communityStats: community
      )
      
      // Generate personalized insights
      let insights = CourseIntelligenceEngine.generatePersonalizedInsights(
        comparisons: comparisons
      )
      
      await MainActor.run {
        self.communityStats = community
        self.userComparisons = comparisons
        self.courseIntel = intel
        self.personalizedInsights = insights
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
    }
  }
  
  private func fetchAllHoleStats() throws -> [HoleStats] {
    let rounds = try GCDB.shared.listCompletedRounds(limit: 100)
    
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

struct DifficultyRatingCard: View {
  let rating: Double
  let percentile: Int
  
  var body: some View {
    VStack(spacing: 8) {
      Text("\(String(format: "%.1f", rating))")
        .font(.system(size: 36, weight: .bold, design: .rounded))
        .foregroundColor(difficultyColor(percentile))
      
      Text("Difficulty")
        .font(.caption)
        .foregroundColor(.secondary)
      
      Text("/10")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .frame(width: 80)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(8)
  }
  
  private func difficultyColor(_ percentile: Int) -> Color {
    if percentile >= 70 { return .red }
    if percentile >= 50 { return .orange }
    if percentile >= 30 { return .yellow }
    return .green
  }
}

struct HoleListCard: View {
  let title: String
  let holes: [Int]
  let color: Color
  let icon: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .foregroundColor(color)
          .font(.caption)
        Text(title)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(.secondary)
      }
      
      HStack(spacing: 8) {
        ForEach(holes, id: \.self) { hole in
          Text("\(hole)")
            .font(.system(.body, design: .rounded, weight: .semibold))
            .frame(width: 32, height: 32)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(6)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(8)
  }
}

struct ComparisonRow: View {
  let comparison: UserVsCommunityComparison
  
  var body: some View {
    HStack(spacing: 12) {
      // Hole number
      Text("\(comparison.holeNumber)")
        .font(.system(.body, design: .rounded, weight: .bold))
        .frame(width: 36, height: 36)
        .background(percentileColor(comparison.userPercentile).opacity(0.1))
        .foregroundColor(percentileColor(comparison.userPercentile))
        .clipShape(Circle())
      
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text("You: \(String(format: "%.1f", comparison.userAvg))")
            .font(.subheadline)
            .fontWeight(.medium)
          
          Text("vs \(String(format: "%.1f", comparison.communityAvg))")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        
        Text(comparison.comparisonDescription)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }
      
      Spacer()
      
      // Percentile badge
      Text("\(Int(comparison.userPercentile))%")
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundColor(percentileColor(comparison.userPercentile))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(percentileColor(comparison.userPercentile).opacity(0.1))
        .cornerRadius(6)
    }
    .padding(.vertical, 4)
  }
  
  private func percentileColor(_ percentile: Double) -> Color {
    if percentile >= 75 { return .green }
    if percentile >= 50 { return .blue }
    if percentile >= 25 { return .yellow }
    return .orange
  }
}

struct BenchmarkRow: View {
  let label: String
  let avgScore: Double
  let description: String
  let color: Color
  
  var body: some View {
    HStack {
      HStack(spacing: 8) {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
        
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
            .font(.subheadline)
            .fontWeight(.medium)
          Text(description)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
      
      Spacer()
      
      Text("\(String(format: "%.1f", avgScore))")
        .font(.system(.body, design: .rounded, weight: .semibold))
    }
  }
}

// MARK: - Preview

#Preview {
  CourseIntelligenceView(course: try! CourseLoader.loadGreystonesCourse())
}
