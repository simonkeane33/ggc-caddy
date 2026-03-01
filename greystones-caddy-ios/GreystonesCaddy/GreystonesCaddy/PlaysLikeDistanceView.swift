import SwiftUI
import GreystonesCaddyCore

/// Displays "plays like" distance with adjustments for elevation and weather.
struct PlaysLikeDistanceView: View {
  let actualDistance: Double // meters
  let holeNumber: Int
  let unit: DistanceUnit
  
  @State private var playsLikeResult: PlaysLikeResult?
  @State private var weather: WeatherConditions?
  @State private var isLoading = false
  @State private var showingDetail = false
  
  /// Course center coordinates for weather lookup
  private let courseLat = 53.1345
  private let courseLng = -6.0635
  
  var body: some View {
    VStack(spacing: 12) {
      if let result = playsLikeResult {
        mainDisplay(result: result)
        
        if !result.adjustmentDescription.isEmpty {
          adjustmentLabel(description: result.adjustmentDescription)
        }
        
        if showingDetail {
          detailBreakdown(result: result)
        }
        
        Button(showingDetail ? "Hide Details" : "Show Details") {
          showingDetail.toggle()
        }
        .font(.caption)
        .foregroundColor(.blue)
      } else {
        actualDistanceOnly
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
    .task(id: holeNumber) {
      await calculatePlaysLike()
    }
  }
  
  // MARK: - Sections
  
  private func mainDisplay(result: PlaysLikeResult) -> some View {
    HStack(spacing: 20) {
      // Actual distance
      VStack(spacing: 4) {
        Text(formattedDistance(actualDistance))
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundColor(.secondary)
        
        Text("Actual")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      
      // Arrow
      Image(systemName: result.playsLonger ? "arrow.right" : "arrow.left")
        .font(.title2)
        .foregroundColor(adjustmentColor(result))
        .rotationEffect(.degrees(result.playsLonger ? 0 : 180))
      
      // Plays like
      VStack(spacing: 4) {
        Text(formattedDistance(result.playsLikeDistance))
          .font(.system(size: 36, weight: .bold, design: .rounded))
          .foregroundColor(adjustmentColor(result))
        
        Text("Plays Like")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(adjustmentColor(result))
      }
    }
  }
  
  private func adjustmentLabel(description: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "info.circle.fill")
        .font(.caption)
      Text(description)
        .font(.caption)
    }
    .foregroundColor(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(.systemBackground))
    .cornerRadius(16)
  }
  
  private func detailBreakdown(result: PlaysLikeResult) -> some View {
    VStack(spacing: 8) {
      Divider()
      
      Text("Adjustment Breakdown")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
      
      VStack(spacing: 6) {
        AdjustmentRow(
          label: "Elevation",
          multiplier: result.adjustmentFactors.elevationMultiplier,
          icon: "arrow.up.arrow.down"
        )
        
        AdjustmentRow(
          label: "Temperature",
          multiplier: result.adjustmentFactors.temperatureMultiplier,
          icon: "thermometer"
        )
        
        AdjustmentRow(
          label: "Wind",
          multiplier: result.adjustmentFactors.windMultiplier,
          icon: "wind"
        )
        
        HStack {
          Text("Total Adjustment")
            .font(.caption)
            .fontWeight(.medium)
          Spacer()
          let pct = (result.adjustmentFactors.totalMultiplier - 1.0) * 100
          let sign = pct >= 0 ? "+" : ""
          Text("\(sign)\(Int(pct))%")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(pct > 0 ? .red : (pct < 0 ? .green : .secondary))
        }
      }
      
      if let weather = weather {
        Divider()
        
        HStack(spacing: 12) {
          WeatherIcon(speed: weather.windSpeedKph)
          
          VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(weather.temperatureC))°C • \(Int(weather.windSpeedKph)) kph \(weather.windEffectDescription.lowercased())")
              .font(.caption)
            
            Text("Wind from \(windDirectionText(weather.windDirectionDegrees))")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          
          Spacer()
        }
      }
    }
    .padding(.top, 8)
  }
  
  private var actualDistanceOnly: some View {
    VStack(spacing: 4) {
      Text(formattedDistance(actualDistance))
        .font(.system(size: 36, weight: .bold, design: .rounded))
      
      Text(displayUnit)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
  
  // MARK: - Helpers
  
  private func formattedDistance(_ meters: Double) -> String {
    let value = unit == .yards ? Distance.metresToYards(meters) : meters
    return "\(Int(value))"
  }
  
  private var displayUnit: String {
    unit == .yards ? "yards" : "meters"
  }
  
  private func adjustmentColor(_ result: PlaysLikeResult) -> Color {
    let pct = abs(result.adjustmentPercentage)
    if pct < 5 { return .blue }
    if pct < 10 { return .orange }
    return .red
  }
  
  private func windDirectionText(_ degrees: Double) -> String {
    let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    let index = Int((degrees + 11.25) / 22.5) % 16
    return directions[index]
  }
  
  private func calculatePlaysLike() async {
    isLoading = true
    
    // Get elevation profile
    let elevationProfile = GreystonesElevationData.profile(forHole: holeNumber)
    
    // Fetch weather
    do {
      let conditions = try await WeatherService.shared.fetchCurrentWeather(
        lat: courseLat,
        lng: courseLng
      )
      
      await MainActor.run {
        self.weather = conditions
      }
      
      // Calculate shot direction (simplified: from current location to green center)
      // In real implementation, would use actual GPS position
      let shotDirection: Double? = nil // nil = ignore wind direction for now
      
      let result = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
        actualDistanceMeters: actualDistance,
        elevationProfile: elevationProfile,
        weather: conditions,
        shotDirection: shotDirection
      )
      
      await MainActor.run {
        self.playsLikeResult = result
        self.isLoading = false
      }
    } catch {
      // Fall back to just elevation if weather fails
      let result = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
        actualDistanceMeters: actualDistance,
        elevationProfile: elevationProfile,
        weather: nil,
        shotDirection: nil
      )
      
      await MainActor.run {
        self.playsLikeResult = result
        self.isLoading = false
      }
    }
  }
}

// MARK: - Supporting Views

struct AdjustmentRow: View {
  let label: String
  let multiplier: Double
  let icon: String
  
  var body: some View {
    HStack {
      Image(systemName: icon)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 20)
      
      Text(label)
        .font(.caption)
      
      Spacer()
      
      let pct = (multiplier - 1.0) * 100
      if abs(pct) < 1 {
        Text("No effect")
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        let sign = pct >= 0 ? "+" : ""
        Text("\(sign)\(Int(pct))%")
          .font(.caption)
          .foregroundColor(pct > 0 ? .orange : .green)
      }
    }
  }
}

struct WeatherIcon: View {
  let speed: Double
  
  var body: some View {
    Image(systemName: iconName)
      .font(.title3)
      .foregroundColor(color)
  }
  
  private var iconName: String {
    if speed < 5 { return "wind" }
    if speed < 15 { return "wind.circle" }
    if speed < 25 { return "wind.circle.fill" }
    return "tornado"
  }
  
  private var color: Color {
    if speed < 15 { return .green }
    if speed < 25 { return .orange }
    return .red
  }
}

// MARK: - Preview

#Preview {
  VStack {
    PlaysLikeDistanceView(
      actualDistance: 145, // meters
      holeNumber: 3, // Uphill hole
      unit: .yards
    )
    
    PlaysLikeDistanceView(
      actualDistance: 160,
      holeNumber: 4, // Downhill hole
      unit: .yards
    )
  }
  .padding()
}
