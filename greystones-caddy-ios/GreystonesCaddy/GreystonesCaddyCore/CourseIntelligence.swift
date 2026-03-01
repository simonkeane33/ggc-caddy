import Foundation
import GRDB

// MARK: - Community Benchmark Models

/// Aggregated statistics from all golfers on a specific hole.
public struct HoleCommunityStats: Sendable {
  public var holeNumber: Int
  public var totalRounds: Int
  public var avgScore: Double
  public var bestScore: Int
  public var medianScore: Double
  
  // Percentiles
  public var p10Score: Double // Scratch golfers
  public var p25Score: Double // Low handicaps
  public var p50Score: Double // Mid handicaps
  public var p75Score: Double // High handicaps
  
  // Difficulty ranking across all holes
  public var difficultyRank: Int // 1 = hardest on course
  
  // Performance metrics
  public var avgGIRPercentage: Double
  public var avgFairwayPercentage: Double
  
  public init(
    holeNumber: Int,
    totalRounds: Int,
    avgScore: Double,
    bestScore: Int,
    medianScore: Double,
    p10Score: Double,
    p25Score: Double,
    p50Score: Double,
    p75Score: Double,
    difficultyRank: Int,
    avgGIRPercentage: Double,
    avgFairwayPercentage: Double
  ) {
    self.holeNumber = holeNumber
    self.totalRounds = totalRounds
    self.avgScore = avgScore
    self.bestScore = bestScore
    self.medianScore = medianScore
    self.p10Score = p10Score
    self.p25Score = p25Score
    self.p50Score = p50Score
    self.p75Score = p75Score
    self.difficultyRank = difficultyRank
    self.avgGIRPercentage = avgGIRPercentage
    self.avgFairwayPercentage = avgFairwayPercentage
  }
}

/// User's performance compared to community benchmarks.
public struct UserVsCommunityComparison: Sendable, Identifiable {
  public var id: Int { holeNumber }
  public var holeNumber: Int
  
  // User stats
  public var userAvg: Double
  public var userBest: Int
  
  // Community stats
  public var communityAvg: Double
  public var communityBest: Int
  
  // Percentile (0-100)
  public var userPercentile: Double
  
  // Interpretation
  public var comparisonDescription: String {
    if userPercentile >= 90 {
      return "Elite — you play this better than 90% of golfers"
    } else if userPercentile >= 75 {
      return "Strong — you play this better than most"
    } else if userPercentile >= 50 {
      return "Solid — above average on this hole"
    } else if userPercentile >= 25 {
      return "Average — room for improvement"
    } else {
      return "Work in progress — this hole is challenging for you"
    }
  }
  
  public var comparisonColor: String {
    if userPercentile >= 75 { return "green" }
    if userPercentile >= 50 { return "blue" }
    if userPercentile >= 25 { return "yellow" }
    return "orange"
  }
  
  /// Difference from community average (+ means worse, - means better)
  public var strokesVsCommunity: Double {
    userAvg - communityAvg
  }
  
  public init(
    holeNumber: Int,
    userAvg: Double,
    userBest: Int,
    communityAvg: Double,
    communityBest: Int,
    userPercentile: Double
  ) {
    self.holeNumber = holeNumber
    self.userAvg = userAvg
    self.userBest = userBest
    self.communityAvg = communityAvg
    self.communityBest = communityBest
    self.userPercentile = userPercentile
  }
}

/// Course-wide intelligence summary.
public struct CourseIntelligence: Sendable {
  public var courseName: String
  public var totalRoundsAnalyzed: Int
  public var uniqueGolfers: Int
  
  // Course difficulty
  public var courseDifficultyRating: Double // 1-10 scale
  public var courseDifficultyPercentile: Int // vs all courses in database
  
  // Hole rankings
  public var hardestHoles: [Int] // Top 3
  public var easiestHoles: [Int] // Bottom 3
  
  // Benchmark scores
  public var scratchGolferAvgScore: Double
  public var bogeyGolferAvgScore: Double
  public var midHandicapAvgScore: Double
}

// MARK: - Course Intelligence Engine

public enum CourseIntelligenceEngine {
  
  /// Generate simulated community stats for Greystones.
  /// In production, this would aggregate from all users' uploaded rounds.
  public static func generateSimulatedCommunityStats(
    course: CourseBundle
  ) -> [Int: HoleCommunityStats] {
    var stats: [Int: HoleCommunityStats] = [:]
    
    for hole in course.holes {
      let par = hole.par[.blue]
      let si = hole.si[.blue]
      
      // Simulate realistic score distributions based on hole characteristics
      // Higher SI = harder hole = higher scores
      let difficultyFactor = Double(si) / 9.0 // Normalize to ~1.0
      
      // Base averages
      let scratchAvg = Double(par) + 0.2 + (difficultyFactor * 0.1)
      let midHandicapAvg = Double(par) + 0.8 + (difficultyFactor * 0.4)
      let bogeyAvg = Double(par) + 1.5 + (difficultyFactor * 0.7)
      
      // Simulate percentiles
      let p10 = scratchAvg
      let p25 = scratchAvg + 0.3
      let p50 = midHandicapAvg
      let p75 = bogeyAvg
      
      // GIR and FIR percentages (simulated based on hole type)
      let avgGIR = par == 3 ? 45.0 : (par == 4 ? 38.0 : 42.0)
      let avgFIR = par >= 4 ? 52.0 : 0.0
      
      stats[hole.number] = HoleCommunityStats(
        holeNumber: hole.number,
        totalRounds: 127 + (hole.number * 3), // Simulated round counts
        avgScore: midHandicapAvg,
        bestScore: par - 1,
        medianScore: midHandicapAvg,
        p10Score: p10,
        p25Score: p25,
        p50Score: p50,
        p75Score: p75,
        difficultyRank: 0, // Calculated later
        avgGIRPercentage: avgGIR,
        avgFairwayPercentage: avgFIR
      )
    }
    
    // Calculate difficulty rankings based on average scores
    let sortedByAvg = stats.values.sorted { $0.avgScore < $1.avgScore }
    for (rank, stat) in sortedByAvg.enumerated() {
      stats[stat.holeNumber]?.difficultyRank = rank + 1
    }
    
    return stats
  }
  
  /// Compare user's performance to community benchmarks.
  public static func compareUserToCommunity(
    userPerformance: HolePerformance,
    communityStats: HoleCommunityStats
  ) -> UserVsCommunityComparison {
    
    // Calculate percentile based on where user average falls in distribution
    let userAvg = userPerformance.avgScore
    
    // Simple percentile calculation based on position between p10 and p75
    let range = communityStats.p75Score - communityStats.p10Score
    let position = userAvg - communityStats.p10Score
    var percentile = 90.0 - (position / range * 65.0) // 90 at p10, 25 at p75
    percentile = max(0, min(100, percentile)) // Clamp to 0-100
    
    return UserVsCommunityComparison(
      holeNumber: userPerformance.holeNumber,
      userAvg: userAvg,
      userBest: userPerformance.bestScore,
      communityAvg: communityStats.avgScore,
      communityBest: communityStats.bestScore,
      userPercentile: percentile
    )
  }
  
  /// Generate course-wide intelligence summary.
  public static func generateCourseIntelligence(
    course: CourseBundle,
    communityStats: [Int: HoleCommunityStats]
  ) -> CourseIntelligence {
    let totalRounds = communityStats.values.reduce(0) { $0 + $1.totalRounds }
    let sortedByDifficulty = communityStats.values.sorted { $0.difficultyRank < $1.difficultyRank }
    
    return CourseIntelligence(
      courseName: course.course.name,
      totalRoundsAnalyzed: totalRounds,
      uniqueGolfers: totalRounds / 3, // Estimate
      courseDifficultyRating: 6.5, // Simulated
      courseDifficultyPercentile: 65, // Simulated — harder than 65% of courses
      hardestHoles: sortedByDifficulty.prefix(3).map { $0.holeNumber },
      easiestHoles: sortedByDifficulty.suffix(3).map { $0.holeNumber },
      scratchGolferAvgScore: communityStats.values.reduce(0.0) { $0 + $1.p10Score } / Double(communityStats.count),
      bogeyGolferAvgScore: communityStats.values.reduce(0.0) { $0 + $1.p75Score } / Double(communityStats.count),
      midHandicapAvgScore: communityStats.values.reduce(0.0) { $0 + $1.p50Score } / Double(communityStats.count)
    )
  }
  
  /// Generate personalized insights based on user's strengths/weaknesses vs community.
  public static func generatePersonalizedInsights(
    comparisons: [UserVsCommunityComparison]
  ) -> [String] {
    var insights: [String] = []
    
    // Find strongest holes
    let strongest = comparisons.filter { $0.userPercentile >= 75 }.sorted { $0.userPercentile > $1.userPercentile }
    if let best = strongest.first {
      insights.append("🏆 Your best hole vs the field: Hole \(best.holeNumber) — you play it better than \(Int(best.userPercentile))% of golfers")
    }
    
    // Find weakest holes
    let weakest = comparisons.filter { $0.userPercentile <= 40 }.sorted { $0.userPercentile < $1.userPercentile }
    if let worst = weakest.first {
      insights.append("📈 Biggest opportunity: Hole \(worst.holeNumber) — average golfers score \(String(format: "%.1f", worst.communityAvg)) here")
    }
    
    // Consistency insight
    let percentileRange = (comparisons.map { $0.userPercentile }.max() ?? 50) - (comparisons.map { $0.userPercentile }.min() ?? 50)
    if percentileRange < 20 {
      insights.append("🎯 Consistent across all holes — no major weaknesses")
    } else if percentileRange > 50 {
      insights.append("⚡ High variance player — some holes you own, others need work")
    }
    
    return insights
  }
}
