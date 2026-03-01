import Foundation
import GRDB

// MARK: - Hole Performance Models

/// Historical performance data for a specific hole.
public struct HolePerformance: Sendable, Identifiable {
  public var id: Int { holeNumber }
  public var holeNumber: Int
  public var holeName: String
  public var par: Int
  
  // Statistics
  public var roundsPlayed: Int
  public var bestScore: Int
  public var avgScore: Double
  public var worstScore: Int
  
  // Key metrics
  public var girPercentage: Double?
  public var fairwayPercentage: Double?
  public var scramblePercentage: Double?
  public var avgPutts: Double
  
  // Difficulty (for this golfer)
  public var avgStrokesOverPar: Double
  public var difficultyRank: Int? // 1 = hardest for this golfer
  
  // Trends
  public var last5Avg: Double?
  public var trend: HoleTrend
  
  public init(
    holeNumber: Int,
    holeName: String,
    par: Int,
    roundsPlayed: Int,
    bestScore: Int,
    avgScore: Double,
    worstScore: Int,
    girPercentage: Double? = nil,
    fairwayPercentage: Double? = nil,
    scramblePercentage: Double? = nil,
    avgPutts: Double = 0,
    avgStrokesOverPar: Double = 0,
    difficultyRank: Int? = nil,
    last5Avg: Double? = nil,
    trend: HoleTrend = .stable
  ) {
    self.holeNumber = holeNumber
    self.holeName = holeName
    self.par = par
    self.roundsPlayed = roundsPlayed
    self.bestScore = bestScore
    self.avgScore = avgScore
    self.worstScore = worstScore
    self.girPercentage = girPercentage
    self.fairwayPercentage = fairwayPercentage
    self.scramblePercentage = scramblePercentage
    self.avgPutts = avgPutts
    self.avgStrokesOverPar = avgStrokesOverPar
    self.difficultyRank = difficultyRank
    self.last5Avg = last5Avg
    self.trend = trend
  }
}

public enum HoleTrend: String, Sendable {
  case improving = "Improving"
  case stable = "Stable"
  case worsening = "Worsening"
  
  public var icon: String {
    switch self {
    case .improving: return "arrow.down" // Lower scores = better
    case .stable: return "minus"
    case .worsening: return "arrow.up"
    }
  }
  
  public var color: String {
    switch self {
    case .improving: return "green"
    case .stable: return "gray"
    case .worsening: return "orange"
    }
  }
}

/// Comparison of user's performance vs course/community averages.
public struct HoleBenchmark: Sendable {
  public var holeNumber: Int
  
  // User stats
  public var userAvg: Double
  public var userBest: Int
  
  // Benchmarks (placeholder for when we have community data)
  public var courseAvg: Double? // Will be populated from aggregated data
  public var scratchGolferAvg: Double? // Estimated
  
  public var userVsCourseDiff: Double? {
    guard let courseAvg = courseAvg else { return nil }
    return userAvg - courseAvg
  }
}

// MARK: - Hole Insights Engine

public enum HoleInsightsEngine {
  
  /// Calculate performance metrics for all holes based on historical data.
  public static func calculateHolePerformances(
    holeStats: [HoleStats],
    course: CourseBundle
  ) -> [HolePerformance] {
    // Group by hole
    let grouped = Dictionary(grouping: holeStats) { $0.holeNumber }
    
    var performances: [HolePerformance] = []
    
    for (holeNumber, stats) in grouped {
      guard let hole = course.holes.first(where: { $0.number == holeNumber }) else { continue }
      
      let roundsPlayed = stats.count
      let scores = stats.map { $0.strokes }
      let bestScore = scores.min() ?? 0
      let worstScore = scores.max() ?? 0
      let avgScore = Double(scores.reduce(0, +)) / Double(roundsPlayed)
      
      // GIR
      let girs = stats.compactMap { $0.gir }
      let girPercentage = girs.isEmpty ? nil : Double(girs.filter { $0 }.count) / Double(girs.count) * 100
      
      // FIR (only par 4/5)
      let firs = stats.compactMap { $0.fairwayHit }
      let fairwayPercentage = firs.isEmpty ? nil : Double(firs.filter { $0 }.count) / Double(firs.count) * 100
      
      // Scrambling
      let scrambles = stats.compactMap { $0.scramble }
      let scramblePercentage = scrambles.isEmpty ? nil : Double(scrambles.filter { $0 }.count) / Double(scrambles.count) * 100
      
      // Putts
      let putts = stats.map { $0.putts }
      let avgPutts = Double(putts.reduce(0, +)) / Double(roundsPlayed)
      
      // Difficulty for this golfer
      let avgStrokesOverPar = avgScore - Double(hole.par[.blue]) // TODO: Use actual tee
      
      // Last 5 trend
      let last5 = stats.suffix(5)
      let last5Avg = last5.isEmpty ? nil : Double(last5.map { $0.strokes }.reduce(0, +)) / Double(last5.count)
      
      // Trend direction
      let trend: HoleTrend = {
        guard let last5Avg = last5Avg else { return .stable }
        let diff = last5Avg - avgScore
        if abs(diff) < 0.5 { return .stable }
        return diff < 0 ? .improving : .worsening
      }()
      
      performances.append(HolePerformance(
        holeNumber: holeNumber,
        holeName: hole.name,
        par: hole.par[.blue], // TODO: Use actual tee
        roundsPlayed: roundsPlayed,
        bestScore: bestScore,
        avgScore: avgScore,
        worstScore: worstScore,
        girPercentage: girPercentage,
        fairwayPercentage: fairwayPercentage,
        scramblePercentage: scramblePercentage,
        avgPutts: avgPutts,
        avgStrokesOverPar: avgStrokesOverPar,
        last5Avg: last5Avg,
        trend: trend
      ))
    }
    
    // Calculate difficulty rankings
    let ranked = performances.sorted { $0.avgStrokesOverPar > $1.avgStrokesOverPar }
    for (index, var perf) in ranked.enumerated() {
      perf.difficultyRank = index + 1
      if let originalIndex = performances.firstIndex(where: { $0.holeNumber == perf.holeNumber }) {
        performances[originalIndex] = perf
      }
    }
    
    return performances.sorted { $0.holeNumber < $1.holeNumber }
  }
  
  /// Identify the strongest and weakest parts of the user's game.
  public static func identifyStrengthsAndWeaknesses(
    performances: [HolePerformance]
  ) -> (strengths: [HolePerformance], weaknesses: [HolePerformance]) {
    let sortedByDifficulty = performances.sorted { $0.avgStrokesOverPar > $1.avgStrokesOverPar }
    
    let weaknesses = Array(sortedByDifficulty.prefix(3))
    let strengths = Array(sortedByDifficulty.suffix(3).reversed())
    
    return (strengths, weaknesses)
  }
  
  /// Generate personalized tips based on hole performance.
  public static func generateHoleTip(performance: HolePerformance) -> String? {
    // Scrambling struggles
    if let scramblePct = performance.scramblePercentage, scramblePct < 30 && performance.roundsPlayed >= 5 {
      return "Work on chipping/pitching — you're missing greens but not getting up-and-down"
    }
    
    // GIR issues on par 3s
    if performance.par == 3, let girPct = performance.girPercentage, girPct < 40 {
      return "Practice tee shots on par 3s — missing greens leads to bogeys"
    }
    
    // FIR issues on par 4/5
    if performance.par >= 4, let firPct = performance.fairwayPercentage, firPct < 40 {
      return "Consider a safer club off the tee — accuracy is costing you strokes"
    }
    
    // Putting issues
    if performance.avgPutts > 2.0 {
      return "Focus on lag putting — averaging \(String(format: "%.1f", performance.avgPutts)) putts here"
    }
    
    // Trending well
    if performance.trend == .improving && performance.roundsPlayed >= 5 {
      return "You're trending well here! Trust your strategy"
    }
    
    return nil
  }
}
