import SwiftUI
import GreystonesCaddyCore

struct PlaysLikeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let actualDistance: Double
    let holeNumber: Int
    /// Compass bearing of the shot, 0 = north. Without it no wind adjustment can
    /// be calculated — wind only helps or hurts relative to the shot direction.
    let shotBearing: Double?

    @State private var result: PlaysLikeResult?
    @State private var weather: WeatherConditions?
    @State private var elevationProfile: HoleElevationProfile?
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let result = result {
                    VStack(spacing: 24) {
                        // Header info
                        headerSection(result: result)
                        
                        // Detail Rows
                        VStack(spacing: 1) {
                            adjustmentRow(
                                label: "Wind",
                                value: windText(),
                                adjustment: result.adjustmentFactors.windMultiplier,
                                icon: "wind"
                            )
                            adjustmentRow(
                                label: "Elevation",
                                value: elevationText(result),
                                adjustment: result.adjustmentFactors.elevationMultiplier,
                                icon: "arrow.up.and.line.horizontal.and.arrow.down"
                            )
                            adjustmentRow(
                                label: "Temperature",
                                value: weather.map { "\(Int($0.temperatureC.rounded()))°C" } ?? "—",
                                adjustment: result.adjustmentFactors.temperatureMultiplier,
                                icon: "thermometer.medium"
                            )
                            adjustmentRow(
                                label: "Altitude Change",
                                value: "0m", // Specific to localized pressure change
                                adjustment: 1.0,
                                icon: "arrow.up.to.line"
                            )
                            adjustmentRow(
                                label: "Lie Angle",
                                value: "Flat",
                                adjustment: 1.0,
                                icon: "angle"
                            )
                        }
                        .background(Color(white: 0.15))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        Spacer()
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Back to GPS Page")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        // This screen paints its own black background, but `.secondary` and
        // friends are semantic colours that resolve against the *ambient*
        // scheme. In light mode they became dark greys intended for light
        // backgrounds — dark-grey-on-black, effectively unreadable. Pinning the
        // scheme makes every semantic colour resolve against the background
        // actually being drawn.
        .preferredColorScheme(.dark)
        .task {
            await calculate()
        }
    }
    
    private func headerSection(result: PlaysLikeResult) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Actual Distance")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(Int(Distance.metresToYards(result.actualDistance))) Yds")
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Plays Like")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Int(Distance.metresToYards(result.playsLikeDistance)))")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Yds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Club Recommendation")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Dr") // Placeholder for club logic
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 30)
    }
    
    private func adjustmentRow(label: String, value: String, adjustment: Double, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: icon)
                    .foregroundColor(.white)
            }
            .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            let yardageDiff = calculateYardageDiff(multiplier: adjustment)
            Text(yardageDiff == 0 ? "0Yds" : (yardageDiff > 0 ? "+\(yardageDiff)Yds" : "\(yardageDiff)Yds"))
                .font(.headline)
                .foregroundColor(.white)
            
            Button("Adjust") {}
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.leading, 10)
        }
        .padding()
        .background(Color(white: 0.1))
    }
    
    private func calculateYardageDiff(multiplier: Double) -> Int {
        let diff = (actualDistance * multiplier) - actualDistance
        return Int(Distance.metresToYards(diff))
    }
    
    /// Wind speed plus how it lies relative to this shot. "9 kph" alone doesn't
    /// tell you whether it helps or hurts — the head/tail/cross part does.
    private func windText() -> String {
        guard let weather else { return "—" }
        let speed = Int(weather.windSpeedKph.rounded())
        guard speed > 0, let bearing = shotBearing else { return "\(speed) Kmph" }
        return "\(speed) Kmph \(windRelativeDescription(windDirection: weather.windDirectionDegrees, shotBearing: bearing))"
    }

    /// Wind direction from the API is the direction the wind blows *from*, and
    /// `shotBearing` is the direction the ball travels *to*, so a shot aimed
    /// straight at the wind's origin is a headwind.
    private func windRelativeDescription(windDirection: Double, shotBearing: Double) -> String {
        var diff = shotBearing - windDirection
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        let magnitude = abs(diff)
        if magnitude < 45 { return "head" }
        if magnitude > 135 { return "tail" }
        return "cross"
    }

    private func elevationText(_ result: PlaysLikeResult) -> String {
        guard let profile = elevationProfile else { return "Unknown" }
        let change = profile.elevationChange
        // Matches the <3m dead zone in HoleElevationProfile.distanceMultiplier,
        // so the label never reads "Flat" while a yardage adjustment is applied.
        if abs(change) < 3 { return "Flat" }
        return change > 0 ? "\(Int(change.rounded()))m up" : "\(Int(abs(change).rounded()))m down"
    }

    private func calculate() async {
        isLoading = true
        let profile = GreystonesElevationData.profile(forHole: holeNumber)
        self.elevationProfile = profile

        var conditions: WeatherConditions?
        do {
            conditions = try await WeatherService.shared.fetchCurrentWeather(
                lat: GreystonesElevationData.courseCenter.lat,
                lng: GreystonesElevationData.courseCenter.lng
            )
        } catch {
            // Leave conditions nil; the engine falls back to elevation only and
            // the wind/temperature rows render as unavailable rather than as
            // fabricated calm-and-20°C readings.
            conditions = nil
        }
        self.weather = conditions

        self.result = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
            actualDistanceMeters: actualDistance,
            elevationProfile: profile,
            weather: conditions,
            shotDirection: shotBearing
        )
        isLoading = false
    }
}
