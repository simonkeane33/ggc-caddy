import SwiftUI
import GreystonesCaddyCore

struct PlaysLikeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let actualDistance: Double
    let holeNumber: Int
    let targetLocation: (lat: Double, lng: Double)?
    
    @State private var result: PlaysLikeResult?
    @State private var weather: WeatherConditions?
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
                                value: "\(Int(weather?.windSpeedKph ?? 0)) kph",
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
                                value: "\(Int(weather?.temperatureC ?? 20))°C",
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
    
    private func elevationText(_ result: PlaysLikeResult) -> String {
        // Placeholder until we use target location elevation
        return "Flat"
    }

    private func calculate() async {
        isLoading = true
        let elevationProfile = GreystonesElevationData.profile(forHole: holeNumber)
        
        do {
            let conditions = try await WeatherService.shared.fetchCurrentWeather(
                lat: GreystonesElevationData.courseCenter.lat,
                lng: GreystonesElevationData.courseCenter.lng
            )
            self.weather = conditions
            
            self.result = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
                actualDistanceMeters: actualDistance,
                elevationProfile: elevationProfile,
                weather: conditions,
                shotDirection: nil
            )
        } catch {
            self.result = DistanceAdjustmentEngine.calculatePlaysLikeDistance(
                actualDistanceMeters: actualDistance,
                elevationProfile: elevationProfile,
                weather: nil,
                shotDirection: nil
            )
        }
        isLoading = false
    }
}
