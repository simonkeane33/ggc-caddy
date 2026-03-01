import Foundation

// MARK: - Green Contour Models

/// Represents a point on the green with elevation data.
public struct GreenContourPoint: Sendable {
  public var lat: Double
  public var lng: Double
  public var elevationMeters: Double
  
  public init(lat: Double, lng: Double, elevationMeters: Double) {
    self.lat = lat
    self.lng = lng
    self.elevationMeters = elevationMeters
  }
}

/// A grid of elevation data covering a green.
public struct GreenElevationGrid: Sendable {
  public var holeNumber: Int
  public var rows: Int
  public var cols: Int
  public var points: [[GreenContourPoint]]
  
  /// The highest point on the green
  public var maxElevation: Double {
    points.flatMap { $0 }.map { $0.elevationMeters }.max() ?? 0
  }
  
  /// The lowest point on the green
  public var minElevation: Double {
    points.flatMap { $0 }.map { $0.elevationMeters }.min() ?? 0
  }
  
  /// Total elevation range
  public var elevationRange: Double {
    maxElevation - minElevation
  }
  
  /// Get the elevation at a specific grid coordinate
  public func elevationAt(row: Int, col: Int) -> Double {
    guard row >= 0, row < rows, col >= 0, col < cols else { return 0 }
    return points[row][col].elevationMeters
  }
  
  /// Calculate slope at a point (returns direction in degrees and steepness)
  public func slopeAt(row: Int, col: Int) -> (direction: Double, steepness: Double)? {
    guard row > 0, row < rows - 1, col > 0, col < cols - 1 else { return nil }
    
    // Calculate gradient using central differences
    let dzdx = (elevationAt(row: row, col: col + 1) - elevationAt(row: row, col: col - 1)) / 2.0
    let dzdy = (elevationAt(row: row + 1, col: col) - elevationAt(row: row - 1, col: col)) / 2.0
    
    // Slope direction (ball rolls downhill, so opposite of gradient)
    let direction = atan2(dzdx, dzdy) * 180.0 / .pi
    
    // Slope steepness (percentage)
    let steepness = sqrt(dzdx * dzdx + dzdy * dzdy) * 100.0
    
    return (direction, steepness)
  }

  /// Returns a smoothed version of the grid using a Gaussian blur.
  public func smoothed(radius: Int = 1) -> GreenElevationGrid {
    var newPoints = points
    let kernelSize = radius * 2 + 1
    
    for r in 0..<rows {
      for c in 0..<cols {
        var sum = 0.0
        var count = 0.0
        
        for dr in -radius...radius {
          for dc in -radius...radius {
            let nr = r + dr
            let nc = c + dc
            
            if nr >= 0 && nr < rows && nc >= 0 && nc < cols {
              // Simple box blur for now, but better than 3x3 hardcoded
              sum += points[nr][nc].elevationMeters
              count += 1.0
            }
          }
        }
        newPoints[r][c].elevationMeters = sum / count
      }
    }
    return GreenElevationGrid(holeNumber: holeNumber, rows: rows, cols: cols, points: newPoints)
  }

  /// Returns a high-resolution upsampled version of the grid using bilinear interpolation.
  public func upsampled(targetRows: Int = 256, targetCols: Int = 256) -> GreenElevationGrid {
    var newPoints: [[GreenContourPoint]] = []
    
    for r in 0..<targetRows {
      var rowPoints: [GreenContourPoint] = []
      let r_orig = Double(r) / Double(targetRows - 1) * Double(rows - 1)
      
      for c in 0..<targetCols {
        let c_orig = Double(c) / Double(targetCols - 1) * Double(cols - 1)
        
        // Use bilinear interpolation for elevation
        let elev = interpolatedElevation(atRow: r_orig, col: c_orig)
        
        // Interpolate Lat/Lng for consistency (though less critical for local mesh)
        let r1 = Int(floor(r_orig))
        let r2 = min(r1 + 1, rows - 1)
        let c1 = Int(floor(c_orig))
        let c2 = min(c1 + 1, cols - 1)
        
        let dr = r_orig - Double(r1)
        let dc = c_orig - Double(c1)
        
        let lat11 = points[r1][c1].lat
        let lat12 = points[r1][c2].lat
        let lat21 = points[r2][c1].lat
        let lat22 = points[r2][c2].lat
        let lat = lat11 + dc * (lat12 - lat11) + dr * (lat21 - lat11 + dc * (lat22 - lat21 - lat12 + lat11))
        
        let lng11 = points[r1][c1].lng
        let lng12 = points[r1][c2].lng
        let lng21 = points[r2][c1].lng
        let lng22 = points[r2][c2].lng
        let lng = lng11 + dc * (lng12 - lng11) + dr * (lng21 - lng11 + dc * (lng22 - lng21 - lng12 + lng11))
        
        rowPoints.append(GreenContourPoint(lat: lat, lng: lng, elevationMeters: elev))
      }
      newPoints.append(rowPoints)
    }
    
    return GreenElevationGrid(holeNumber: holeNumber, rows: targetRows, cols: targetCols, points: newPoints)
  }

  /// Returns elevation using bilinear interpolation for a continuous surface
  public func interpolatedElevation(atLat lat: Double, lng: Double) -> Double {
    // 1. Convert Lat/Lng back to Grid Row/Col
    // Assumes grid is centered at centerLat/centerLng (from center grid point)
    let centerLat = points[rows/2][cols/2].lat
    let centerLng = points[rows/2][cols/2].lng
    
    // Reverse the math from ElevationService
    let dy = (lat - centerLat) * 111320.0
    let dx = (lng - centerLng) * (111320.0 * cos(centerLat * .pi / 180))
    
    // Spacing is 3m as per fetchGreenElevation
    let col = dx / 3.0 + Double(cols) / 2.0
    let row = dy / 3.0 + Double(rows) / 2.0
    
    return interpolatedElevation(atRow: row, col: col)
  }

  /// Returns elevation using bilinear interpolation for a continuous surface
  public func interpolatedElevation(atRow row: Double, col: Double) -> Double {
    let r1 = max(0, min(Int(floor(row)), rows - 1))
    let r2 = min(r1 + 1, rows - 1)
    let c1 = max(0, min(Int(floor(col)), cols - 1))
    let c2 = min(c1 + 1, cols - 1)
    
    let dr = row - Double(r1)
    let dc = col - Double(c1)
    
    let v11 = elevationAt(row: r1, col: c1)
    let v12 = elevationAt(row: r1, col: c2)
    let v21 = elevationAt(row: r2, col: c1)
    let v22 = elevationAt(row: r2, col: c2)
    
    let top = v11 + dc * (v12 - v11)
    let bottom = v21 + dc * (v22 - v21)
    
    return top + dr * (bottom - top)
  }
}

// MARK: - Simplified Green Data

/// Simplified green structure for basic slope visualization.
/// Instead of full LiDAR grids, use key points: high point, low point, and break lines.
public struct GreenSlopeProfile: Sendable {
  public var holeNumber: Int
  
  /// Highest point on green (where putts break from)
  public var highPoint: GreenContourPoint
  
  /// Lowest point on green (where putts break toward)
  public var lowPoint: GreenContourPoint
  
  /// General slope direction (degrees, 0 = North, 90 = East)
  public var primarySlopeDirection: Double
  
  /// Average slope percentage
  public var averageSlopePercent: Double
  
  /// Key break points (where slope changes significantly)
  public var breakPoints: [BreakPoint]
  
  /// Front, middle, back relative to primary slope
  public var frontIsUphill: Bool
  
  public struct BreakPoint: Sendable {
    public var lat: Double
    public var lng: Double
    public var description: String // e.g., "Ridge", "Valley", "Tiers"
    
    public init(lat: Double, lng: Double, description: String) {
      self.lat = lat
      self.lng = lng
      self.description = description
    }
  }
  
  /// Fall line direction (the straight uphill-downhill line)
  public var fallLineDirection: Double {
    primarySlopeDirection
  }
  
  /// Direction putts will break (90° from fall line, toward low point)
  public var breakDirection: Double {
    (primarySlopeDirection + 90).truncatingRemainder(dividingBy: 360)
  }
}

// MARK: - Greystones Green Data

/// Hardcoded green slope data for Greystones Golf Club.
/// Based on typical links course characteristics and green contours.
public enum GreystonesGreenData {
  
  public static let greenProfiles: [Int: GreenSlopeProfile] = [
    1: GreenSlopeProfile(
      holeNumber: 1,
      highPoint: GreenContourPoint(lat: 53.14047772450267, lng: -6.076614670843671, elevationMeters: 42.53),
      lowPoint: GreenContourPoint(lat: 53.14035665306354, lng: -6.076295552319087, elevationMeters: 41.98),
      primarySlopeDirection: 135, // SE - from back-left to front-right
      averageSlopePercent: 3.5,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.14041, lng: -6.07645, description: "Back-to-front tier")
      ],
      frontIsUphill: true
    ),
    
    2: GreenSlopeProfile(
      holeNumber: 2,
      highPoint: GreenContourPoint(lat: 53.13405, lng: -6.06405, elevationMeters: 38.5),
      lowPoint: GreenContourPoint(lat: 53.13395, lng: -6.06395, elevationMeters: 37.5),
      primarySlopeDirection: 45, // NE
      averageSlopePercent: 3.0,
      breakPoints: [],
      frontIsUphill: true
    ),
    
    3: GreenSlopeProfile(
      holeNumber: 3,
      highPoint: GreenContourPoint(lat: 53.13335, lng: -6.06425, elevationMeters: 55.5),
      lowPoint: GreenContourPoint(lat: 53.13325, lng: -6.06415, elevationMeters: 54.5),
      primarySlopeDirection: 135, // SE
      averageSlopePercent: 2.0,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13330, lng: -6.06420, description: "Two-tiered green")
      ],
      frontIsUphill: true
    ),
    
    4: GreenSlopeProfile(
      holeNumber: 4,
      highPoint: GreenContourPoint(lat: 53.13385, lng: -6.06505, elevationMeters: 36.0),
      lowPoint: GreenContourPoint(lat: 53.13375, lng: -6.06495, elevationMeters: 34.0),
      primarySlopeDirection: 315, // NW - significant slope downhill to green
      averageSlopePercent: 4.5,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13380, lng: -6.06500, description: "False front")
      ],
      frontIsUphill: false
    ),
    
    5: GreenSlopeProfile(
      holeNumber: 5,
      highPoint: GreenContourPoint(lat: 53.13445, lng: -6.06485, elevationMeters: 43.0),
      lowPoint: GreenContourPoint(lat: 53.13435, lng: -6.06475, elevationMeters: 41.0),
      primarySlopeDirection: 45, // NE
      averageSlopePercent: 3.5,
      breakPoints: [],
      frontIsUphill: true
    ),
    
    6: GreenSlopeProfile(
      holeNumber: 6,
      highPoint: GreenContourPoint(lat: 53.13475, lng: -6.06415, elevationMeters: 38.5),
      lowPoint: GreenContourPoint(lat: 53.13465, lng: -6.06405, elevationMeters: 37.5),
      primarySlopeDirection: 135, // SE
      averageSlopePercent: 2.0,
      breakPoints: [],
      frontIsUphill: false
    ),
    
    7: GreenSlopeProfile(
      holeNumber: 7,
      highPoint: GreenContourPoint(lat: 53.13505, lng: -6.06345, elevationMeters: 48.5),
      lowPoint: GreenContourPoint(lat: 53.13495, lng: -6.06335, elevationMeters: 47.5),
      primarySlopeDirection: 45, // NE
      averageSlopePercent: 2.5,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13500, lng: -6.06340, description: "Crown in center")
      ],
      frontIsUphill: false
    ),
    
    8: GreenSlopeProfile(
      holeNumber: 8,
      highPoint: GreenContourPoint(lat: 53.13545, lng: -6.06285, elevationMeters: 35.5),
      lowPoint: GreenContourPoint(lat: 53.13535, lng: -6.06275, elevationMeters: 34.5),
      primarySlopeDirection: 135, // SE
      averageSlopePercent: 2.0,
      breakPoints: [],
      frontIsUphill: true
    ),
    
    9: GreenSlopeProfile(
      holeNumber: 9,
      highPoint: GreenContourPoint(lat: 53.13445, lng: -6.06195, elevationMeters: 45.5),
      lowPoint: GreenContourPoint(lat: 53.13435, lng: -6.06185, elevationMeters: 44.5),
      primarySlopeDirection: 315, // NW
      averageSlopePercent: 3.0,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13440, lng: -6.06190, description: "Back to front slope")
      ],
      frontIsUphill: false
    ),
    
    // Back nine - typical links characteristics
    10: GreenSlopeProfile(
      holeNumber: 10,
      highPoint: GreenContourPoint(lat: 53.1340, lng: -6.0620, elevationMeters: 40.5),
      lowPoint: GreenContourPoint(lat: 53.1339, lng: -6.0619, elevationMeters: 39.5),
      primarySlopeDirection: 135,
      averageSlopePercent: 2.5,
      breakPoints: [],
      frontIsUphill: true
    ),
    
    11: GreenSlopeProfile(
      holeNumber: 11,
      highPoint: GreenContourPoint(lat: 53.1345, lng: -6.0625, elevationMeters: 46.0),
      lowPoint: GreenContourPoint(lat: 53.1344, lng: -6.0624, elevationMeters: 44.0),
      primarySlopeDirection: 45,
      averageSlopePercent: 3.5,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13445, lng: -6.06245, description: "Three-tiered")
      ],
      frontIsUphill: true
    ),
    
    12: GreenSlopeProfile(
      holeNumber: 12,
      highPoint: GreenContourPoint(lat: 53.1350, lng: -6.0635, elevationMeters: 42.5),
      lowPoint: GreenContourPoint(lat: 53.1349, lng: -6.0634, elevationMeters: 41.5),
      primarySlopeDirection: 315,
      averageSlopePercent: 2.0,
      breakPoints: [],
      frontIsUphill: false
    ),
    
    13: GreenSlopeProfile(
      holeNumber: 13,
      highPoint: GreenContourPoint(lat: 53.1348, lng: -6.0645, elevationMeters: 38.5),
      lowPoint: GreenContourPoint(lat: 53.1347, lng: -6.0644, elevationMeters: 37.5),
      primarySlopeDirection: 135,
      averageSlopePercent: 2.5,
      breakPoints: [],
      frontIsUphill: true
    ),
    
    14: GreenSlopeProfile(
      holeNumber: 14,
      highPoint: GreenContourPoint(lat: 53.1342, lng: -6.0650, elevationMeters: 40.5),
      lowPoint: GreenContourPoint(lat: 53.1341, lng: -6.0649, elevationMeters: 39.5),
      primarySlopeDirection: 45,
      averageSlopePercent: 2.5,
      breakPoints: [],
      frontIsUphill: false
    ),
    
    15: GreenSlopeProfile(
      holeNumber: 15,
      highPoint: GreenContourPoint(lat: 53.1338, lng: -6.0645, elevationMeters: 36.0),
      lowPoint: GreenContourPoint(lat: 53.1337, lng: -6.0644, elevationMeters: 35.0),
      primarySlopeDirection: 315,
      averageSlopePercent: 4.0,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13375, lng: -6.06445, description: "False front")
      ],
      frontIsUphill: false
    ),
    
    16: GreenSlopeProfile(
      holeNumber: 16,
      highPoint: GreenContourPoint(lat: 53.1342, lng: -6.0635, elevationMeters: 42.5),
      lowPoint: GreenContourPoint(lat: 53.1341, lng: -6.0634, elevationMeters: 41.5),
      primarySlopeDirection: 135,
      averageSlopePercent: 2.5,
      breakPoints: [],
      frontIsUphill: true
    ),
    
    17: GreenSlopeProfile(
      holeNumber: 17,
      highPoint: GreenContourPoint(lat: 53.1345, lng: -6.0625, elevationMeters: 38.5),
      lowPoint: GreenContourPoint(lat: 53.1344, lng: -6.0624, elevationMeters: 37.5),
      primarySlopeDirection: 45,
      averageSlopePercent: 2.0,
      breakPoints: [],
      frontIsUphill: false
    ),
    
    18: GreenSlopeProfile(
      holeNumber: 18,
      highPoint: GreenContourPoint(lat: 53.1348, lng: -6.0618, elevationMeters: 48.5),
      lowPoint: GreenContourPoint(lat: 53.1347, lng: -6.0617, elevationMeters: 47.5),
      primarySlopeDirection: 135,
      averageSlopePercent: 3.0,
      breakPoints: [
        GreenSlopeProfile.BreakPoint(lat: 53.13475, lng: -6.06175, description: "Finishing green")
      ],
      frontIsUphill: true
    ),
  ]
  
  public static func profile(forHole holeNumber: Int) -> GreenSlopeProfile? {
    greenProfiles[holeNumber]
  }
}

// MARK: - Green Reading Helper

public enum GreenReadingHelper {
  
  /// Generate a putting tip based on green slope profile and putt direction
  public static func puttingTip(
    profile: GreenSlopeProfile,
    puttDistance: Double, // meters
    puttDirection: Double // degrees from ball to hole
  ) -> String {
    let fallLine = profile.fallLineDirection
    
    // Calculate angle between putt direction and fall line
    var angleDiff = abs(puttDirection - fallLine)
    while angleDiff > 180 { angleDiff = 360 - angleDiff }
    
    // Determine if putt is generally uphill or downhill
    let isUphill = abs(puttDirection - fallLine) < 90
    
    var tips: [String] = []
    
    // Slope severity
    if profile.averageSlopePercent > 4 {
      tips.append("Significant slope — be cautious with speed")
    } else if profile.averageSlopePercent > 2 {
      tips.append("Moderate slope")
    }
    
    // Break direction
    if angleDiff < 15 {
      tips.append(isUphill ? "Straight uphill" : "Straight downhill")
    } else if angleDiff < 45 {
      let breakDir = profile.breakDirection
      let breakText = cardinalDirection(breakDir)
      tips.append("Slight break \(breakText.lowercased())")
    } else if angleDiff < 75 {
      let breakDir = profile.breakDirection
      let breakText = cardinalDirection(breakDir)
      tips.append("Breaks \(breakText.lowercased())")
    } else {
      tips.append("Maximum break — across the slope")
    }
    
    // Specific features
    if let breakPoint = profile.breakPoints.first {
      tips.append("Watch for \(breakPoint.description.lowercased())")
    }
    
    // Distance adjustment
    if isUphill && profile.averageSlopePercent > 3 {
      tips.append("Hit it harder — uphill")
    } else if !isUphill && profile.averageSlopePercent > 3 {
      tips.append("Deaden the stroke — downhill")
    }
    
    return tips.joined(separator: " • ")
  }
  
  private static func cardinalDirection(_ degrees: Double) -> String {
    let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    let index = Int((degrees + 11.25) / 22.5) % 16
    return directions[index]
  }
  
  /// Get a simple description of the green's general slope
  public static func slopeDescription(profile: GreenSlopeProfile) -> String {
    let slope = profile.averageSlopePercent
    let direction = cardinalDirection(profile.primarySlopeDirection)
    
    if slope < 1.5 {
      return "Relatively flat green"
    } else if slope < 3 {
      return "Gentle slope toward \(direction)"
    } else if slope < 4.5 {
      return "Moderate slope toward \(direction)"
    } else {
      return "Significant slope toward \(direction) — use caution"
    }
  }
}
