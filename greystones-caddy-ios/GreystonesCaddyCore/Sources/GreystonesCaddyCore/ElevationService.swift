import Foundation

/// Fetches elevation data from free APIs for 3D green rendering
public actor ElevationService {
  public static let shared = ElevationService()
  
  private var cache: [String: [ElevationPoint]] = [:]
  private let cacheValidity: TimeInterval = 86400 * 7 // 7 days
  
  private init() {}
  
  /// Fetch elevation data for a grid around a green
  public func fetchGreenElevation(
    holeNumber: Int,
    centerLat: Double,
    centerLng: Double,
    gridSize: Int = 16,
    spacingMeters: Double = 3
  ) async throws -> GreenElevationGrid {
    
    // Check if we have high-precision XYZ data for this hole
    if let highPrecisionGrid = try? await fetchHighPrecisionXYZ(holeNumber: holeNumber) {
        print("DEBUG: Using high-precision XYZ data for Hole \(holeNumber)")
        return highPrecisionGrid
    }

    print("DEBUG: No XYZ file found, checking database for tilt...")
    let cacheKey = "\(centerLat)_\(centerLng)_\(gridSize)"
    
    // Check cache
    if let cached = cache[cacheKey] {
      return createGrid(from: cached, rows: gridSize, cols: gridSize, holeNumber: holeNumber)
    }
    
    // Generate grid coordinates
    var points: [ElevationPoint] = []
    let halfSize = Double(gridSize) / 2.0
    
    for row in 0..<gridSize {
      for col in 0..<gridSize {
        let offsetX = (Double(col) - halfSize) * spacingMeters
        let offsetY = (Double(row) - halfSize) * spacingMeters
        
        let lat = centerLat + (offsetY / 111320.0)
        let lng = centerLng + (offsetX / (111320.0 * cos(centerLat * .pi / 180)))
        
        points.append(ElevationPoint(lat: lat, lng: lng, elevationMeters: 0))
      }
    }
    
    // Try to fetch from API, fall back to synthetic data
    do {
      var elevations: [Double] = []
      let batchSize = 50
      
      for i in stride(from: 0, to: points.count, by: batchSize) {
        let batch = points[i..<min(i + batchSize, points.count)]
        let batchElevations = try await fetchElevationsBatch(locations: Array(batch))
        elevations.append(contentsOf: batchElevations)
        
        if i + batchSize < points.count {
          try await Task.sleep(nanoseconds: 100_000_000)
        }
      }
      
      var elevatedPoints: [ElevationPoint] = []
      for (index, var point) in points.enumerated() {
        point.elevationMeters = elevations[index]
        elevatedPoints.append(point)
      }
      
      cache[cacheKey] = elevatedPoints
      
      return createGrid(from: elevatedPoints, rows: gridSize, cols: gridSize, holeNumber: holeNumber)
    } catch {
      print("API failed, using synthetic data: \(error)")
      
      var tiltProfile: (frontAlt: Double, centerAlt: Double, backAlt: Double)? = nil
      if let greenRec = try? GCDB.shared.fetchGreenCenter(holeNumber: holeNumber) {
          if let c = greenRec.centerAlt, let f = greenRec.frontAlt, let b = greenRec.backAlt {
              tiltProfile = (frontAlt: f, centerAlt: c, backAlt: b)
          }
      }
      
      return generateSyntheticGrid(points: points, rows: gridSize, cols: gridSize, cacheKey: cacheKey, holeNumber: holeNumber, tilt: tiltProfile)
    }
  }
  
  /// Generate synthetic elevation data when API fails
  private func generateSyntheticGrid(points: [ElevationPoint], rows: Int, cols: Int, cacheKey: String, holeNumber: Int, tilt: (frontAlt: Double, centerAlt: Double, backAlt: Double)? = nil) -> GreenElevationGrid {
    var elevatedPoints: [ElevationPoint] = []
    
    for (index, var point) in points.enumerated() {
      let row = index / cols
      let col = index % cols
      
      var baseElevation: Double = 0
      if let tilt = tilt {
          let progress = Double(row) / Double(rows - 1)
          baseElevation = tilt.backAlt + (tilt.frontAlt - tilt.backAlt) * progress
      } else {
          let progress = Double(row) / Double(rows - 1)
          baseElevation = 2.0 - (progress * 2.0)
      }

      let centerCol = Double(cols) / 2.0
      let distFromWidthCenter = abs(Double(col) - centerCol) / centerCol
      let crown = 0.5 * (1.0 - pow(distFromWidthCenter, 2))
      
      point.elevationMeters = baseElevation + crown + Double.random(in: -0.02...0.02)
      elevatedPoints.append(point)
    }
    
    cache[cacheKey] = elevatedPoints
    
    return createGrid(from: elevatedPoints, rows: rows, cols: cols, holeNumber: holeNumber)
  }
  
  private func fetchElevationsBatch(locations: [ElevationPoint]) async throws -> [Double] {
    // Build API URL for OpenTopoData
    let locationsParam = locations.map { "\($0.lat),\($0.lng)" }.joined(separator: "|")
    guard let url = URL(string: "https://api.opentopodata.org/v1/srtm90m?locations=\(locationsParam)") else {
      throw NSError(domain: "ElevationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }
    
    let (data, response) = try await URLSession.shared.data(from: url)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw NSError(domain: "ElevationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }
    
    guard httpResponse.statusCode == 200 else {
      throw NSError(domain: "ElevationService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(httpResponse.statusCode)"])
    }
    
    let decodedResponse = try JSONDecoder().decode(OpenTopoResponse.self, from: data)
    return decodedResponse.results.map { $0.elevation }
  }

  /// Parses high-precision XYZ data from QGIS exports
  private func fetchHighPrecisionXYZ(holeNumber: Int) async throws -> GreenElevationGrid? {
    let baseName = "H\(String(format: "%02d", holeNumber))_green"
    let extensions = ["xyz", "xyz.txt", "txt"]
    
    let bundle = Bundle.main
    var path: String? = nil
    
    for ext in extensions {
        if let foundPath = bundle.path(forResource: baseName, ofType: ext) {
            path = foundPath
            break
        }
    }
    
    // Fallback to module bundle
    if path == nil {
        for ext in extensions {
            if let foundPath = Bundle.module.path(forResource: baseName, ofType: ext) {
                path = foundPath
                break
            }
        }
    }

    guard let foundPath = path else {
        print("DEBUG: FAILED to find \(baseName) with any extension (xyz, txt) in any bundle.")
        return nil
    }

    print("DEBUG: FOUND XYZ file at: \(foundPath)")
    let data = try String(contentsOfFile: foundPath)
    let lines = data.components(separatedBy: .newlines)
    
    var rawPoints: [(x: Double, y: Double, z: Double)] = []
    for line in lines {
        let parts = line.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count == 3, let x = Double(parts[0]), let y = Double(parts[1]), let z = Double(parts[2]) {
            // CRITICAL: QGIS NoData value is often -9999 or -32767. 
            // Also, ITM elevations at Greystones should be around 40-45m.
            if z > 0 && z < 100 { 
                rawPoints.append((x: x, y: y, z: z))
            }
        }
    }

    guard !rawPoints.isEmpty else { return nil }

    // CRITICAL FIX: Zero-Base the data so the green is anchored to Y=0
    let minZ = rawPoints.map { $0.z }.min() ?? 0
    let normalizedPoints = rawPoints.map { (x: $0.x, y: $0.y, z: $0.z - minZ) }

    // Normalize to grid (assuming sorted by gdal_translate)
    // For 122x104, we need to find the bounds
    let xCoords = Set(normalizedPoints.map { $0.x }).sorted()
    let yCoords = Set(normalizedPoints.map { $0.y }).sorted(by: >) // Northing decreases in grid
    
    let cols = xCoords.count
    let rows = yCoords.count
    
    var gridPoints: [[GreenContourPoint]] = Array(repeating: Array(repeating: GreenContourPoint(lat: 0, lng: 0, elevationMeters: 0), count: cols), count: rows)
    
    for pt in normalizedPoints {
        if let colIdx = xCoords.firstIndex(of: pt.x), let rowIdx = yCoords.firstIndex(of: pt.y) {
            // Note: We'd ideally convert ITM back to Lat/Lng for consistency, 
            // but for a local 3D mesh, the raw meters work fine.
            gridPoints[rowIdx][colIdx] = GreenContourPoint(lat: pt.y, lng: pt.x, elevationMeters: pt.z)
        }
    }

    return GreenElevationGrid(
      holeNumber: holeNumber,
      rows: rows,
      cols: cols,
      points: gridPoints
    )
  }
  
  private func createGrid(from points: [ElevationPoint], rows: Int, cols: Int, holeNumber: Int) -> GreenElevationGrid {
    var gridPoints: [[GreenContourPoint]] = []
    
    for row in 0..<rows {
      var rowPoints: [GreenContourPoint] = []
      for col in 0..<cols {
        let index = row * cols + col
        if index < points.count {
          let point = points[index]
          rowPoints.append(GreenContourPoint(
            lat: point.lat,
            lng: point.lng,
            elevationMeters: point.elevationMeters
          ))
        }
      }
      gridPoints.append(rowPoints)
    }
    
    return GreenElevationGrid(
      holeNumber: holeNumber,
      rows: rows,
      cols: cols,
      points: gridPoints
    )
  }
}

// MARK: - API Response Models

private struct OpenTopoResponse: Codable {
  let results: [OpenTopoResult]
}

private struct OpenTopoResult: Codable {
  let elevation: Double
  let location: OpenTopoLocation
}

private struct OpenTopoLocation: Codable {
  let lat: Double
  let lng: Double
}

// MARK: - Greystones Green Coordinates

public enum GreystonesGreenCoordinates {
  // Approximate green centers from course data
  public static let greens: [Int: (lat: Double, lng: Double)] = [
    1: (53.13425, -6.06350),
    2: (53.13400, -6.06400),
    3: (53.13330, -6.06420),
    4: (53.13380, -6.06500),
    5: (53.13440, -6.06480),
    6: (53.13470, -6.06410),
    7: (53.13500, -6.06340),
    8: (53.13540, -6.06280),
    9: (53.13440, -6.06190),
    10: (53.13400, -6.06200),
    11: (53.13450, -6.06250),
    12: (53.13500, -6.06350),
    13: (53.13480, -6.06450),
    14: (53.13420, -6.06500),
    15: (53.13380, -6.06450),
    16: (53.13420, -6.06350),
    17: (53.13450, -6.06250),
    18: (53.13480, -6.06180),
  ]
  
  public static func center(forHole holeNumber: Int) -> (lat: Double, lng: Double)? {
    greens[holeNumber]
  }
}
