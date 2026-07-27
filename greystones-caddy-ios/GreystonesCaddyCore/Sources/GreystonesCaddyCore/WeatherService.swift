import Foundation

/// Fetches current weather conditions from Open-Meteo API (free, no API key required)
public actor WeatherService {
  public static let shared = WeatherService()
  
  private var lastFetch: Date?
  private var cachedConditions: WeatherConditions?
  private let cacheValidity: TimeInterval = 300 // 5 minutes
  
  private init() {}
  
  /// Fetch current weather for a location
  /// - Parameters:
  ///   - lat: Latitude
  ///   - lng: Longitude
  /// - Returns: Current weather conditions
  public func fetchCurrentWeather(lat: Double, lng: Double) async throws -> WeatherConditions {
    // Check cache
    if let cached = cachedConditions,
       let lastFetch = lastFetch,
       Date().timeIntervalSince(lastFetch) < cacheValidity {
      return cached
    }
    
    // Open-Meteo API (free, no key required)
    // Note the unit is `kmh`, not `kph` — Open-Meteo rejects `kph` outright with
    // "Cannot initialize WindspeedUnit from invalid String value", which made
    // every fetch throw and silently fall back to placeholder conditions.
    let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)&current=temperature_2m,relative_humidity_2m,pressure_msl,wind_speed_10m,wind_direction_10m&wind_speed_unit=kmh&temperature_unit=celsius")!
    
    let (data, _) = try await URLSession.shared.data(from: url)
    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    
    let conditions = WeatherConditions(
      temperatureC: response.current.temperature_2m,
      windSpeedKph: response.current.wind_speed_10m,
      windDirectionDegrees: response.current.wind_direction_10m,
      humidity: Double(response.current.relative_humidity_2m),
      pressure: response.current.pressure_msl
    )
    
    // Cache result
    cachedConditions = conditions
    lastFetch = Date()
    
    return conditions
  }
  
  /// Clear cached weather data
  public func clearCache() {
    cachedConditions = nil
    lastFetch = nil
  }
}

// MARK: - Open-Meteo API Models

private struct OpenMeteoResponse: Codable {
  let current: CurrentWeather
}

private struct CurrentWeather: Codable {
  let temperature_2m: Double
  let relative_humidity_2m: Int
  let pressure_msl: Double
  let wind_speed_10m: Double
  let wind_direction_10m: Double
}

// MARK: - Greystones Course Elevation Data

/// Hardcoded elevation data for Greystones Golf Club.
/// In production, this would come from a LiDAR survey or elevation API.
public enum GreystonesElevationData {
  
  /// Elevation profile for each hole at Greystones
  /// Values in meters above sea level
  public static let holeProfiles: [Int: HoleElevationProfile] = [
    1: HoleElevationProfile(
      holeNumber: 1,
      teeElevation: 45.0,
      greenElevation: 42.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1339, lng: -6.0630, elevationMeters: 45.0),
        ElevationPoint(lat: 53.1340, lng: -6.0632, elevationMeters: 44.0),
        ElevationPoint(lat: 53.1341, lng: -6.0634, elevationMeters: 43.0),
        ElevationPoint(lat: 53.1342, lng: -6.0635, elevationMeters: 42.0),
      ]
    ),
    2: HoleElevationProfile(
      holeNumber: 2,
      teeElevation: 42.0,
      greenElevation: 38.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1342, lng: -6.0635, elevationMeters: 42.0),
        ElevationPoint(lat: 53.1341, lng: -6.0638, elevationMeters: 40.0),
        ElevationPoint(lat: 53.1340, lng: -6.0640, elevationMeters: 38.0),
      ]
    ),
    3: HoleElevationProfile(
      holeNumber: 3,
      teeElevation: 52.0,
      greenElevation: 55.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1335, lng: -6.0638, elevationMeters: 52.0),
        ElevationPoint(lat: 53.1334, lng: -6.0640, elevationMeters: 53.0),
        ElevationPoint(lat: 53.1333, lng: -6.0642, elevationMeters: 55.0),
      ]
    ),
    4: HoleElevationProfile(
      holeNumber: 4,
      teeElevation: 48.0,
      greenElevation: 35.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1335, lng: -6.0645, elevationMeters: 48.0),
        ElevationPoint(lat: 53.1336, lng: -6.0648, elevationMeters: 42.0),
        ElevationPoint(lat: 53.1338, lng: -6.0650, elevationMeters: 35.0),
      ]
    ),
    5: HoleElevationProfile(
      holeNumber: 5,
      teeElevation: 35.0,
      greenElevation: 42.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1340, lng: -6.0652, elevationMeters: 35.0),
        ElevationPoint(lat: 53.1342, lng: -6.0650, elevationMeters: 38.0),
        ElevationPoint(lat: 53.1344, lng: -6.0648, elevationMeters: 42.0),
      ]
    ),
    6: HoleElevationProfile(
      holeNumber: 6,
      teeElevation: 40.0,
      greenElevation: 38.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1345, lng: -6.0645, elevationMeters: 40.0),
        ElevationPoint(lat: 53.1346, lng: -6.0643, elevationMeters: 39.0),
        ElevationPoint(lat: 53.1347, lng: -6.0641, elevationMeters: 38.0),
      ]
    ),
    7: HoleElevationProfile(
      holeNumber: 7,
      teeElevation: 45.0,
      greenElevation: 48.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1348, lng: -6.0638, elevationMeters: 45.0),
        ElevationPoint(lat: 53.1349, lng: -6.0636, elevationMeters: 46.0),
        ElevationPoint(lat: 53.1350, lng: -6.0634, elevationMeters: 48.0),
      ]
    ),
    8: HoleElevationProfile(
      holeNumber: 8,
      teeElevation: 38.0,
      greenElevation: 35.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1352, lng: -6.0632, elevationMeters: 38.0),
        ElevationPoint(lat: 53.1353, lng: -6.0630, elevationMeters: 36.0),
        ElevationPoint(lat: 53.1354, lng: -6.0628, elevationMeters: 35.0),
      ]
    ),
    9: HoleElevationProfile(
      holeNumber: 9,
      teeElevation: 35.0,
      greenElevation: 45.0,
      fairwayPoints: [
        ElevationPoint(lat: 53.1350, lng: -6.0625, elevationMeters: 35.0),
        ElevationPoint(lat: 53.1348, lng: -6.0623, elevationMeters: 38.0),
        ElevationPoint(lat: 53.1346, lng: -6.0621, elevationMeters: 42.0),
        ElevationPoint(lat: 53.1344, lng: -6.0619, elevationMeters: 45.0),
      ]
    ),
    10: HoleElevationProfile(
      holeNumber: 10,
      teeElevation: 42.0,
      greenElevation: 40.0,
      fairwayPoints: []
    ),
    11: HoleElevationProfile(
      holeNumber: 11,
      teeElevation: 38.0,
      greenElevation: 45.0,
      fairwayPoints: []
    ),
    12: HoleElevationProfile(
      holeNumber: 12,
      teeElevation: 45.0,
      greenElevation: 42.0,
      fairwayPoints: []
    ),
    13: HoleElevationProfile(
      holeNumber: 13,
      teeElevation: 40.0,
      greenElevation: 38.0,
      fairwayPoints: []
    ),
    14: HoleElevationProfile(
      holeNumber: 14,
      teeElevation: 35.0,
      greenElevation: 40.0,
      fairwayPoints: []
    ),
    15: HoleElevationProfile(
      holeNumber: 15,
      teeElevation: 42.0,
      greenElevation: 35.0,
      fairwayPoints: []
    ),
    16: HoleElevationProfile(
      holeNumber: 16,
      teeElevation: 38.0,
      greenElevation: 42.0,
      fairwayPoints: []
    ),
    17: HoleElevationProfile(
      holeNumber: 17,
      teeElevation: 40.0,
      greenElevation: 38.0,
      fairwayPoints: []
    ),
    18: HoleElevationProfile(
      holeNumber: 18,
      teeElevation: 45.0,
      greenElevation: 48.0,
      fairwayPoints: []
    ),
  ]
  
  /// Get elevation profile for a hole
  public static func profile(forHole holeNumber: Int) -> HoleElevationProfile? {
    if let dbProfile = try? GCDB.shared.fetchHoleElevationProfile(holeNumber: holeNumber) {
        return dbProfile
    }
    return holeProfiles[holeNumber]
  }
  
  /// Approximate course center coordinates for weather lookup
  public static let courseCenter = (lat: 53.1345, lng: -6.0635)
}
