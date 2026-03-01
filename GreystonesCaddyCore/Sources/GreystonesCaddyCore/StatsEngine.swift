import Foundation
import GRDB

// MARK: - Hole Stats Model

/// Computed statistics for a single hole in a round.
/// These are auto-calculated from event data (shots + penalties).
public struct HoleStats: Sendable, Identifiable {
  public var id: Int64 { holeEventId }
  public var holeEventId: Int64  // Links to the hole_scores table
  public var roundId: Int64
  public var holeNumber: Int
  
  // Core stats
  public var strokes: Int
  public var putts: Int
  public var penalties: Int
  
  // Computed stats
  public var gir: Bool?        // Greens in Regulation
  public var fairwayHit: Bool? // FIR - only for par 4/5 tee shots
  public var scramble: Bool?   // Up-and-down from missed green
  
  // Derived metrics
  public var scoreToPar: Int { strokes - par }
  public var par: Int
  
  public init(
    holeEventId: Int64,
    roundId: Int64,
    holeNumber: Int,
    par: Int,
    strokes: Int,
    putts: Int,
    penalties: Int,
    gir: Bool? = nil,
    fairwayHit: Bool? = nil,
    scramble: Bool? = nil
  ) {
    self.holeEventId = holeEventId
    self.roundId = roundId
    self.holeNumber = holeNumber
    self.par = par
    self.strokes = strokes
    self.putts = putts
    self.penalties = penalties
    self.gir = gir
    self.fairwayHit = fairwayHit
    self.scramble = scramble
  }
}

// MARK: - Round Stats Summary

/// Aggregated stats for an entire round.
public struct RoundStatsSummary: Sendable {
  public var roundId: Int64
  public var totalStrokes: Int
  public var totalPutts: Int
  public var totalPenalties: Int
  public var scoreToPar: Int
  
  // Percentages
  public var girPercentage: Double?        // Greens in Regulation
  public var fairwayPercentage: Double?    // Fairways hit (par 4/5 only)
  public var scramblePercentage: Double?   // Up-and-down success rate
  public var puttsPerRound: Double
  
  // Counts
  public var girCount: Int
  public var girOpportunities: Int
  public var fairwayCount: Int
  public var fairwayOpportunities: Int
  public var scrambleCount: Int
  public var scrambleOpportunities: Int
  
  public init(
    roundId: Int64,
    totalStrokes: Int,
    totalPutts: Int,
    totalPenalties: Int,
    scoreToPar: Int,
    girPercentage: Double? = nil,
    fairwayPercentage: Double? = nil,
    scramblePercentage: Double? = nil,
    puttsPerRound: Double = 0,
    girCount: Int = 0,
    girOpportunities: Int = 0,
    fairwayCount: Int = 0,
    fairwayOpportunities: Int = 0,
    scrambleCount: Int = 0,
    scrambleOpportunities: Int = 0
  ) {
    self.roundId = roundId
    self.totalStrokes = totalStrokes
    self.totalPutts = totalPutts
    self.totalPenalties = totalPenalties
    self.scoreToPar = scoreToPar
    self.girPercentage = girPercentage
    self.fairwayPercentage = fairwayPercentage
    self.scramblePercentage = scramblePercentage
    self.puttsPerRound = puttsPerRound
    self.girCount = girCount
    self.girOpportunities = girOpportunities
    self.fairwayCount = fairwayCount
    self.fairwayOpportunities = fairwayOpportunities
    self.scrambleCount = scrambleCount
    self.scrambleOpportunities = scrambleOpportunities
  }
}

// MARK: - Stats Calculator

/// Calculates golf statistics from round event data.
/// This is the core "Stats Automation" engine.
public enum StatsCalculator {
  
  /// Calculate stats for a single hole from its events.
  /// - Parameters:
  ///   - events: All events for this hole (shots + penalties)
  ///   - par: The par for this hole
  /// - Returns: Computed HoleStats
  public static func calculateHoleStats(
    events: [HoleEvent],
    par: Int
  ) -> HoleStatsComponents {
    var strokes = 0
    var putts = 0
    var penalties = 0
    var firstShotClub: ClubID? = nil
    var reachedGreen = false
    var shotSequence: [ShotSequenceItem] = []
    
    for event in events {
      switch event.kind {
      case .shot:
        strokes += 1
        if event.shotType == .putt {
          putts += 1
          reachedGreen = true
        }
        if firstShotClub == nil {
          firstShotClub = event.club
        }
        shotSequence.append(ShotSequenceItem(
          club: event.club,
          shotType: event.shotType,
          isOnGreen: event.shotType == .putt
        ))
        
      case .penalty:
        let penaltyStrokes = event.penaltyStrokes ?? 1
        penalties += penaltyStrokes
        strokes += penaltyStrokes
      }
    }
    
    // Calculate GIR: (strokes - putts) <= (par - 2)
    // e.g., Par 4: reach green in 2 shots or less
    // Par 3: reach green in 1 shot (tee shot on green)
    let strokesToReachGreen = strokes - putts
    let gir = strokesToReachGreen <= (par - 2)
    
    // Calculate FIR: Only for par 4 and 5
    // First shot not a penalty, and we have a shot recorded
    var fairwayHit: Bool? = nil
    if par >= 4 && firstShotClub != nil {
      // For now, assume fairway hit if first shot exists and isn't OB/penalty
      // In future: could use GPS to determine if in fairway vs rough
      // For simplicity: if no penalty on first shot = fairway hit
      let firstShotPenalized = events.first { $0.kind == .penalty } != nil
      fairwayHit = !firstShotPenalized
    }
    
    // Calculate Scramble: Missed green but still made par or better
    // Scramble = !GIR && score <= par
    var scramble: Bool? = nil
    if !gir && strokes > 0 {
      scramble = strokes <= par
    }
    
    return HoleStatsComponents(
      strokes: strokes,
      putts: putts,
      penalties: penalties,
      gir: gir,
      fairwayHit: fairwayHit,
      scramble: scramble
    )
  }
  
  /// Calculate aggregated stats for an entire round.
  public static func calculateRoundSummary(
    roundId: Int64,
    holeStats: [HoleStats]
  ) -> RoundStatsSummary {
    let totalStrokes = holeStats.reduce(0) { $0 + $1.strokes }
    let totalPutts = holeStats.reduce(0) { $0 + $1.putts }
    let totalPenalties = holeStats.reduce(0) { $0 + $1.penalties }
    let totalPar = holeStats.reduce(0) { $0 + $1.par }
    let scoreToPar = totalStrokes - totalPar
    
    // GIR stats
    let girOpportunities = holeStats.filter { $0.gir != nil }.count
    let girCount = holeStats.filter { $0.gir == true }.count
    let girPercentage = girOpportunities > 0 
      ? Double(girCount) / Double(girOpportunities) * 100 
      : nil
    
    // FIR stats (only par 4+5)
    let fairwayOpportunities = holeStats.filter { $0.fairwayHit != nil }.count
    let fairwayCount = holeStats.filter { $0.fairwayHit == true }.count
    let fairwayPercentage = fairwayOpportunities > 0
      ? Double(fairwayCount) / Double(fairwayOpportunities) * 100
      : nil
    
    // Scramble stats
    let scrambleOpportunities = holeStats.filter { $0.scramble != nil }.count
    let scrambleCount = holeStats.filter { $0.scramble == true }.count
    let scramblePercentage = scrambleOpportunities > 0
      ? Double(scrambleCount) / Double(scrambleOpportunities) * 100
      : nil
    
    let puttsPerRound = holeStats.isEmpty ? 0 : Double(totalPutts) / Double(holeStats.count) * 18
    
    return RoundStatsSummary(
      roundId: roundId,
      totalStrokes: totalStrokes,
      totalPutts: totalPutts,
      totalPenalties: totalPenalties,
      scoreToPar: scoreToPar,
      girPercentage: girPercentage,
      fairwayPercentage: fairwayPercentage,
      scramblePercentage: scramblePercentage,
      puttsPerRound: puttsPerRound,
      girCount: girCount,
      girOpportunities: girOpportunities,
      fairwayCount: fairwayCount,
      fairwayOpportunities: fairwayOpportunities,
      scrambleCount: scrambleCount,
      scrambleOpportunities: scrambleOpportunities
    )
  }
}

// MARK: - Supporting Types

public struct HoleStatsComponents: Sendable {
  public var strokes: Int
  public var putts: Int
  public var penalties: Int
  public var gir: Bool
  public var fairwayHit: Bool?
  public var scramble: Bool?
}

private struct ShotSequenceItem: Sendable {
  var club: ClubID
  var shotType: ShotType
  var isOnGreen: Bool
}
