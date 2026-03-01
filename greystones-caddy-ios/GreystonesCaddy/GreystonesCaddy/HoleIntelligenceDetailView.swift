import SwiftUI
import GreystonesCaddyCore

/// Detailed view showing user's performance vs community on a specific hole.
struct HoleIntelligenceDetailView: View {
  let comparison: UserVsCommunityComparison
  let course: CourseBundle
  
  @State private var showPercentileChart = true
  
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        // Header with hole info
        headerSection
        
        // Main comparison
        comparisonSection
        
        // Percentile visualization
        percentileChartSection
        
        // Score distribution
        scoreDistributionSection
        
        // Tips based on performance
        tipsSection
      }
      .padding()
    }
    .navigationTitle("Hole \(comparison.holeNumber) Intelligence")
  }
  
  // MARK: - Sections
  
  private var headerSection: some View {
    let hole = course.holes.first { $0.number == comparison.holeNumber }
    
    return VStack(spacing: 12) {
      HStack {
        Text(hole?.name ?? "Hole \(comparison.holeNumber)")
          .font(.title2)
          .fontWeight(.bold)
        
        Spacer()
        
        // Par badge
        if let par = hole?.par[.blue] {
          Text("Par \(par)")
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
      }
      
      if let si = hole?.si[.blue] {
        HStack {
          Text("Stroke Index \(si)")
            .font(.subheadline)
            .foregroundColor(.secondary)
          Spacer()
        }
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var comparisonSection: some View {
    VStack(spacing: 16) {
      HStack {
        Text("Performance Comparison")
          .font(.headline)
        Spacer()
      }
      
      // Big percentile display
      VStack(spacing: 8) {
        ZStack {
          Circle()
            .stroke(percentileColor(comparison.userPercentile).opacity(0.2), lineWidth: 12)
            .frame(width: 120, height: 120)
          
          Circle()
            .trim(from: 0, to: comparison.userPercentile / 100)
            .stroke(
              percentileColor(comparison.userPercentile),
              style: StrokeStyle(lineWidth: 12, lineCap: .round)
            )
            .frame(width: 120, height: 120)
            .rotationEffect(.degrees(-90))
          
          VStack(spacing: 2) {
            Text("\(Int(comparison.userPercentile))%")
              .font(.system(size: 32, weight: .bold, design: .rounded))
              .foregroundColor(percentileColor(comparison.userPercentile))
            Text("Percentile")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        
        Text(comparison.comparisonDescription)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(percentileColor(comparison.userPercentile))
          .multilineTextAlignment(.center)
      }
      .padding(.vertical, 8)
      
      // Stats comparison
      HStack(spacing: 16) {
        StatComparisonBox(
          label: "Your Average",
          value: String(format: "%.1f", comparison.userAvg),
          highlight: true,
          color: percentileColor(comparison.userPercentile)
        )
        
        StatComparisonBox(
          label: "Field Average",
          value: String(format: "%.1f", comparison.communityAvg),
          highlight: false,
          color: .secondary
        )
      }
      
      // Difference indicator
      HStack {
        let diff = comparison.strokesVsCommunity
        let sign = diff > 0 ? "+" : ""
        let color: Color = diff > 0 ? .orange : (diff < 0 ? .green : .secondary)
        let text = diff > 0 ? "worse than" : (diff < 0 ? "better than" : "same as")
        
        Image(systemName: diff > 0 ? "arrow.up" : (diff < 0 ? "arrow.down" : "equal"))
          .foregroundColor(color)
        
        Text("\(sign)\(String(format: "%.1f", abs(diff))) strokes \(text) average")
          .font(.subheadline)
          .foregroundColor(color)
        
        Spacer()
      }
      .padding(.top, 8)
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var percentileChartSection: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Where You Stand")
          .font(.headline)
        Spacer()
      }
      
      // Percentile bar
      VStack(spacing: 8) {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            // Background
            RoundedRectangle(cornerRadius: 4)
              .fill(Color(.systemGray5))
              .frame(height: 24)
            
            // Percentile zones
            HStack(spacing: 0) {
              Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: geo.size.width * 0.25)
              Rectangle()
                .fill(Color.yellow.opacity(0.3))
                .frame(width: geo.size.width * 0.25)
              Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: geo.size.width * 0.25)
              Rectangle()
                .fill(Color.green.opacity(0.3))
                .frame(width: geo.size.width * 0.25)
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // User marker
            Circle()
              .fill(percentileColor(comparison.userPercentile))
              .frame(width: 16, height: 16)
              .shadow(radius: 2)
              .offset(x: geo.size.width * (comparison.userPercentile / 100) - 8)
          }
        }
        .frame(height: 24)
        
        // Legend
        HStack {
          LegendDot(color: .orange, label: "Bottom 25%")
          Spacer()
          LegendDot(color: .yellow, label: "25-50%")
          Spacer()
          LegendDot(color: .blue, label: "50-75%")
          Spacer()
          LegendDot(color: .green, label: "Top 25%")
        }
        .font(.caption)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var scoreDistributionSection: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Score Comparison")
          .font(.headline)
        Spacer()
      }
      
      VStack(spacing: 12) {
        ScoreBar(
          label: "Your Best",
          score: comparison.userBest,
          highlight: true,
          color: .green
        )
        
        ScoreBar(
          label: "Your Average",
          score: Int(round(comparison.userAvg)),
          highlight: true,
          color: percentileColor(comparison.userPercentile)
        )
        
        Divider()
        
        ScoreBar(
          label: "Field Best",
          score: comparison.communityBest,
          highlight: false,
          color: .secondary
        )
        
        ScoreBar(
          label: "Field Average",
          score: Int(round(comparison.communityAvg)),
          highlight: false,
          color: .secondary
        )
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private var tipsSection: some View {
    let tips = generateTips()
    
    return VStack(spacing: 12) {
      HStack {
        Image(systemName: "lightbulb.fill")
          .foregroundColor(.yellow)
        Text("Personalized Tips")
          .font(.headline)
        Spacer()
      }
      
      VStack(alignment: .leading, spacing: 12) {
        ForEach(tips, id: \.self) { tip in
          HStack(alignment: .top, spacing: 8) {
            Text("•")
              .font(.title3)
              .foregroundColor(.blue)
            Text(tip)
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
  
  // MARK: - Helpers
  
  private func percentileColor(_ percentile: Double) -> Color {
    if percentile >= 75 { return .green }
    if percentile >= 50 { return .blue }
    if percentile >= 25 { return .yellow }
    return .orange
  }
  
  private func generateTips() -> [String] {
    var tips: [String] = []
    
    if comparison.userPercentile >= 80 {
      tips.append("🏆 You own this hole! Your strategy is working — stick with it.")
    } else if comparison.userPercentile >= 60 {
      tips.append("📈 Solid performance — minor tweaks could get you to elite level.")
    } else if comparison.userPercentile >= 40 {
      tips.append("⚖️ Average on this hole — study the hole insights for tips.")
    } else {
      tips.append("🎯 Focus area — check the green slope and caddy notes for this hole.")
    }
    
    if comparison.strokesVsCommunity > 1.0 {
      tips.append("You're losing \(String(format: "%.1f", comparison.strokesVsCommunity)) strokes to the field here — biggest opportunity for improvement.")
    } else if comparison.strokesVsCommunity < -0.5 {
      tips.append("You're gaining \(String(format: "%.1f", abs(comparison.strokesVsCommunity))) strokes on the field here — strength to leverage!")
    }
    
    return tips
  }
}

// MARK: - Supporting Views

struct StatComparisonBox: View {
  let label: String
  let value: String
  let highlight: Bool
  let color: Color
  
  var body: some View {
    VStack(spacing: 6) {
      Text(value)
        .font(.system(.title2, design: .rounded, weight: .bold))
        .foregroundColor(color)
      
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(highlight ? color.opacity(0.1) : Color(.systemBackground))
    .cornerRadius(8)
  }
}

struct LegendDot: View {
  let color: Color
  let label: String
  
  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(label)
        .foregroundColor(.secondary)
    }
  }
}

struct ScoreBar: View {
  let label: String
  let score: Int
  let highlight: Bool
  let color: Color
  
  var body: some View {
    HStack {
      Text(label)
        .font(.subheadline)
        .foregroundColor(.secondary)
      
      Spacer()
      
      Text("\(score)")
        .font(.system(.body, design: .rounded, weight: highlight ? .bold : .medium))
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(highlight ? color.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    HoleIntelligenceDetailView(
      comparison: UserVsCommunityComparison(
        holeNumber: 4,
        userAvg: 5.2,
        userBest: 4,
        communityAvg: 4.8,
        communityBest: 3,
        userPercentile: 35
      ),
      course: try! CourseLoader.loadGreystonesCourse()
    )
  }
}
