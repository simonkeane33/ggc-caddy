import Foundation
import CoreLocation

// MARK: - Elevation Models

/// Elevation data for a point on the course.
public struct ElevationPoint: Sendable {
  public var lat: Double
  public var lng: Double
  public var elevationMeters: Double
  
  public init(lat: Double, lng: Double, elevationMeters: Double) {
    self.lat = lat
    self.lng = lng
    self.elevationMeters = elevationMeters
  }
}

/// Elevation profile for a hole.
public struct HoleElevationProfile: Sendable {
  public var holeNumber: Int
  public var teeElevation: Double
  public var greenElevation: Double
  public var fairwayPoints: [ElevationPoint]
  
  /// Total elevation change from tee to green (positive = uphill, negative = downhill)
  public var elevationChange: Double {
    greenElevation - teeElevation
  }
  
  /// Whether the hole plays significantly uphill
  public var isUphill: Bool {
    elevationChange > 5 // More than 5m uphill
  }
  
  /// Whether the hole plays significantly downhill
  public var isDownhill: Bool {
    elevationChange < -5 // More than 5m downhill
  }
  
  /// Elevation-adjusted distance multiplier
  /// Rule of thumb: +10m elevation ≈ +10% effective distance
  public var distanceMultiplier: Double {
    let change = elevationChange
    if abs(change) < 3 { return 1.0 } // Negligible
    
    // For every 10m of elevation change, add/subtract ~10% effective distance
    let adjustment = change / 100.0 // 10m = 0.1 = 10%
    return 1.0 + adjustment
  }
}

// MARK: - Weather Models

/// Current weather conditions affecting golf shots.
public struct WeatherConditions: Sendable {
  public var temperatureC: Double
  public var windSpeedKph: Double
  public var windDirectionDegrees: Double // 0 = North, 90 = East, etc.
  public var humidity: Double
  public var pressure: Double
  
  /// Temperature-adjusted distance multiplier
  /// Cold weather = less distance, warm = more distance
  public var temperatureMultiplier: Double {
    // Baseline: 20°C
    // Every 10°C below 20°C = -2% distance
    // Every 10°C above 20°C = +1% distance
    let diff = temperatureC - 20.0
    if diff < 0 {
      return 1.0 + (diff / 10.0 * 0.02)
    } else {
      return 1.0 + (diff / 10.0 * 0.01)
    }
  }
  
  /// Wind effect description for UI
  public var windEffectDescription: String {
    if windSpeedKph < 5 { return "Calm" }
    if windSpeedKph < 15 { return "Light breeze" }
    if windSpeedKph < 25 { return "Windy" }
    if windSpeedKph < 35 { return "Strong wind" }
    return "Very strong wind"
  }
  
  /// Wind speed category
  public var windCategory: WindCategory {
    if windSpeedKph < 5 { return .calm }
    if windSpeedKph < 15 { return .light }
    if windSpeedKph < 25 { return .moderate }
    if windSpeedKph < 35 { return .strong }
    return .severe
  }
}

public enum WindCategory: String, Sendable {
  case calm = "Calm"
  case light = "Light"
  case moderate = "Moderate"
  case strong = "Strong"
  case severe = "Severe"
}

// MARK: - Distance Adjustment Engine

/// Calculates adjusted ("plays like") distances based on conditions.
public enum DistanceAdjustmentEngine {
  
  /// Factors that affect shot distance
  public struct AdjustmentFactors: Sendable {
    public var elevationMultiplier: Double = 1.0
    public var temperatureMultiplier: Double = 1.0
    public var windMultiplier: Double = 1.0
    public var lieMultiplier: Double = 1.0 // For future: rough, fairway, etc.
    
    public var totalMultiplier: Double {
      elevationMultiplier * temperatureMultiplier * windMultiplier * lieMultiplier
    }
  }
  
  /// Calculate wind effect on a shot
  /// - Parameters:
  ///   - windSpeedKph: Wind speed
  ///   - windDirection: Wind direction in degrees (0 = North)
  ///   - shotDirection: Shot direction in degrees (0 = North)
  /// - Returns: Multiplier (1.0 = no effect, 0.9 = 10% into wind, 1.1 = 10% downwind)
  public static func calculateWindMultiplier(
    windSpeedKph: Double,
    windDirection: Double,
    shotDirection: Double
  ) -> Double {
    // Calculate relative wind angle
    var angleDiff = shotDirection - windDirection
    // Normalize to -180 to 180
    while angleDiff > 180 { angleDiff -= 360 }
    while angleDiff < -180 { angleDiff += 360 }
    
    // Convert to radians
    let angleRad = abs(angleDiff) * .pi / 180.0
    
    // Cosine gives us the component of wind in shot direction
    // 0° = directly into wind (full effect)
    // 90° = cross wind (minimal distance effect)
    // 180° = directly downwind (negative effect = more distance)
    let windComponent = cos(angleRad)
    
    // Every 10 kph of headwind = ~10% distance loss
    // Every 10 kph of tailwind = ~5% distance gain (tailwind helps less than headwind hurts)
    let baseEffect = windSpeedKph / 100.0 // 10 kph = 0.1
    
    if windComponent > 0 {
      // Into wind (or partial headwind)
      return 1.0 + (baseEffect * windComponent)
    } else {
      // Downwind (or partial tailwind)
      // Tailwind is about half as effective as headwind
      return 1.0 + (baseEffect * windComponent * 0.5)
    }
  }
  
  /// Get "plays like" distance for a hole
  public static func calculatePlaysLikeDistance(
    actualDistanceMeters: Double,
    elevationProfile: HoleElevationProfile?,
    weather: WeatherConditions?,
    shotDirection: Double? = nil // From current position to green
  ) -> PlaysLikeResult {
    var factors = AdjustmentFactors()
    var breakdown: [String] = []
    
    // Elevation adjustment
    if let profile = elevationProfile {
      factors.elevationMultiplier = profile.distanceMultiplier
      if profile.isUphill {
        breakdown.append("Uphill (+\(Int(profile.elevationChange))m)")
      } else if profile.isDownhill {
        breakdown.append("Downhill (-\(Int(abs(profile.elevationChange)))m)")
      }
    }
    
    // Temperature adjustment
    if let weather = weather {
      factors.temperatureMultiplier = weather.temperatureMultiplier
      let tempDiff = weather.temperatureC - 20.0
      if abs(tempDiff) > 5 {
        let desc = tempDiff > 0 ? "Warm" : "Cold"
        breakdown.append("\(desc) (\(Int(weather.temperatureC))°C)")
      }
    }
    
    // Wind adjustment
    if let weather = weather, let shotDir = shotDirection {
      factors.windMultiplier = calculateWindMultiplier(
        windSpeedKph: weather.windSpeedKph,
        windDirection: weather.windDirectionDegrees,
        shotDirection: shotDir
      )
      
      if weather.windSpeedKph > 10 {
        let intoWind = factors.windMultiplier > 1.0
        let tailwind = factors.windMultiplier < 1.0
        if intoWind {
          breakdown.append("Into wind")
        } else if tailwind {
          breakdown.append("Downwind")
        } else {
          breakdown.append("Crosswind")
        }
      }
    }
    
    let adjustedDistance = actualDistanceMeters * factors.totalMultiplier
    
    return PlaysLikeResult(
      actualDistance: actualDistanceMeters,
      playsLikeDistance: adjustedDistance,
      adjustmentFactors: factors,
      adjustmentDescription: breakdown.joined(separator: " • ")
    )
  }
  
  /// Quick adjustment for just elevation
  public static func quickElevationAdjustment(
    distance: Double,
    elevationChange: Double
  ) -> Double {
    // Simple rule: 10m elevation = 10% distance adjustment
    let multiplier = 1.0 + (elevationChange / 100.0)
    return distance * multiplier
  }
}

// MARK: - Result Model

public struct PlaysLikeResult: Sendable {
  public var actualDistance: Double // meters
  public var playsLikeDistance: Double // meters
  public var adjustmentFactors: DistanceAdjustmentEngine.AdjustmentFactors
  public var adjustmentDescription: String
  
  /// The percentage adjustment
  public var adjustmentPercentage: Double {
    ((playsLikeDistance - actualDistance) / actualDistance) * 100
  }
  
  /// Whether the shot plays longer or shorter
  public var playsLonger: Bool {
    playsLikeDistance > actualDistance
  }
  
  /// Human-readable summary
  public var summary: String {
    let diff = abs(playsLikeDistance - actualDistance)
    let yards = Int(diff * 1.09361)
    
    if yards < 3 {
      return "Plays true"
    }
    
    let direction = playsLonger ? "longer" : "shorter"
    return "Plays \(yards) yards \(direction)"
  }
}
