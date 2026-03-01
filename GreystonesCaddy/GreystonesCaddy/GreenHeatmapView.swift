import SwiftUI
import MapKit
import CoreLocation
import GreystonesCaddyCore

/// Visual representation of green slope and fall lines.
struct GreenHeatmapView: View {
  let holeNumber: Int
  let greenCenter: CLLocationCoordinate2D?
  
  @State private var profile: GreenSlopeProfile?
  @State private var perimeter: [CLLocationCoordinate2D] = []
  @State private var isLoading = true
  
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        if isLoading {
          ProgressView("Loading green data...")
            .padding()
        } else if let profile = profile {
          // Visual green representation
          greenVisualization(profile: profile)
          
          // Slope info
          slopeInfoSection(profile: profile)
          
          // Fall line visualization
          fallLineSection(profile: profile)
          
          // Break points
          if !profile.breakPoints.isEmpty {
            breakPointsSection(profile: profile)
          }
          
          // Putting tip
          puttingTipSection(profile: profile)
        } else {
          ContentUnavailableView(
            "No Green Data",
            systemImage: "circle.dashed",
            description: Text("Green slope data not available for this hole")
          )
        }
      }
      .padding()
    }
    .navigationTitle("Hole \(holeNumber) Green")
    .task {
      await loadGreenData()
    }
  }
  
  // MARK: - Sections
  
  private func greenVisualization(profile: GreenSlopeProfile) -> some View {
    VStack(spacing: 0) {
      ZStack {
        // Black background for the "Pro" look in the reference
        Color.black
        
        if !perimeter.isEmpty {
            let region = regionForPerimeter(perimeter)
            Map(initialPosition: .region(region), interactionModes: []) {
                MapPolygon(coordinates: perimeter)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .red,
                                .orange,
                                .yellow,
                                .green,
                                .cyan,
                                .blue
                            ],
                            startPoint: highPointUnit(profile: profile),
                            endPoint: lowPointUnit(profile: profile)
                        )
                    )
            }
            .mapStyle(.standard(pointsOfInterest: [], showsTraffic: false))
            .colorScheme(.dark) // Force dark map to blend with black background
        }
        
        // Multi-arrow Fall Line Grid overlay
        FallLineGridOverlay(profile: profile)
            .blendMode(.multiply) // Makes arrows look like they are "on" the green
        
        // Front/Back markers like the reference
        if !perimeter.isEmpty {
            Canvas { context, size in
                // Draw "Front" and "Back" labels at the extreme points
                let highUnit = highPointUnit(profile: profile)
                let lowUnit = lowPointUnit(profile: profile)
                
                let backPos = CGPoint(x: size.width * highUnit.x, y: size.height * highUnit.y)
                let frontPos = CGPoint(x: size.width * lowUnit.x, y: size.height * lowUnit.y)
                
                context.draw(Text("● Back").font(.caption2).bold().foregroundColor(.white), at: CGPoint(x: backPos.x + 35, y: backPos.y))
                context.draw(Text("● Front").font(.caption2).bold().foregroundColor(.white), at: CGPoint(x: frontPos.x + 35, y: frontPos.y))
            }
        }
        
        // Compass
        VStack {
          HStack {
            Spacer()
            CompassRose(direction: 0)
              .padding(16)
          }
          Spacer()
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 450) // Taller, full-width focus
      
      // Heatmap Color Scale Legend
      HStack(spacing: 2) {
          Text("High").font(.caption2).foregroundColor(.secondary).padding(.trailing, 4)
          ForEach([Color.red, .orange, .yellow, .green, .cyan, .blue], id: \.self) { color in
              Rectangle().fill(color).frame(height: 8)
          }
          Text("Low").font(.caption2).foregroundColor(.secondary).padding(.leading, 4)
      }
      .padding(.horizontal, 40)
      .padding(.vertical, 12)
      .background(Color.black.opacity(0.9))
    }
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .shadow(color: .black.opacity(0.3), radius: 10)
    .padding(.horizontal, -16) // Bleed to edges (counteract parent padding)
  }

  private func slopeInfoSection(profile: GreenSlopeProfile) -> some View {
    VStack(spacing: 16) {
        VStack(spacing: 12) {
          HStack {
            Text("Slope Information")
              .font(.headline)
            Spacer()
          }
          
          HStack(spacing: 16) {
            SlopeStatBox(
              value: String(format: "%.1f%%", profile.averageSlopePercent),
              label: "Average Slope",
              color: slopeColor(profile.averageSlopePercent)
            )
            
            SlopeStatBox(
              value: cardinalDirection(profile.primarySlopeDirection),
              label: "Downhill To",
              color: .blue
            )
          }
          
          Text(GreenReadingHelper.slopeDescription(profile: profile))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        
        // Detailed Measurement Section
        if let greenRec = try? GCDB.shared.fetchGreenCenter(holeNumber: holeNumber),
           let cAlt = greenRec.centerAlt {
            VStack(alignment: .leading, spacing: 10) {
                Text("Field Measurements").font(.headline)
                HStack {
                    VStack(alignment: .leading) {
                        Text("Green Center").font(.caption).foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", cAlt))m Elevation").font(.subheadline).bold()
                    }
                    Spacer()
                    if let fAlt = greenRec.frontAlt, let bAlt = greenRec.backAlt {
                        VStack(alignment: .trailing) {
                            Text("Rise (Back-Front)").font(.caption).foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", bAlt - fAlt))m").font(.subheadline).bold().foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
  }
  
  private func fallLineSection(profile: GreenSlopeProfile) -> some View {
    VStack(spacing: 12) {
      HStack {
        Text("Fall Line")
          .font(.headline)
        Spacer()
      }
      
      HStack(spacing: 20) {
        // Fall line diagram
        ZStack {
          Circle()
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            .frame(width: 100, height: 100)
          
          // Direction indicator
          ArrowShape()
            .stroke(Color.blue, lineWidth: 3)
            .frame(width: 60, height: 60)
            .rotationEffect(.degrees(profile.fallLineDirection))
          
          // Center dot
          Circle()
            .fill(Color.blue)
            .frame(width: 8, height: 8)
        }
        .frame(width: 100, height: 100)
        
        VStack(alignment: .leading, spacing: 8) {
          Text("The fall line is the straight uphill-downhill path through the green.")
            .font(.caption)
            .foregroundColor(.secondary)
          
          HStack(spacing: 4) {
            Text("Uphill:")
              .font(.caption)
              .fontWeight(.medium)
            Text(cardinalDirection(profile.fallLineDirection + 180))
              .font(.caption)
              .foregroundColor(.secondary)
          }
          
          HStack(spacing: 4) {
            Text("Downhill:")
              .font(.caption)
              .fontWeight(.medium)
            Text(cardinalDirection(profile.fallLineDirection))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private func breakPointsSection(profile: GreenSlopeProfile) -> some View {
    VStack(spacing: 12) {
      HStack {
        Text("Green Features")
          .font(.headline)
        Spacer()
      }
      
      ForEach(profile.breakPoints, id: \.description) { point in
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
          Text(point.description)
            .font(.subheadline)
          Spacer()
        }
        .padding(.vertical, 4)
      }
    }
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
  
  private func puttingTipSection(profile: GreenSlopeProfile) -> some View {
    VStack(spacing: 12) {
      HStack {
        Image(systemName: "lightbulb.fill")
          .foregroundColor(.yellow)
        Text("Putting Guidance")
          .font(.headline)
        Spacer()
      }
      
      // Example tips for different positions
      VStack(alignment: .leading, spacing: 12) {
        PuttingTipRow(
          scenario: "Below the hole",
          tip: "Uphill putt — aggressive line, firm speed"
        )
        
        PuttingTipRow(
          scenario: "Above the hole",
          tip: "Downhill putt — cautious speed, die it in"
        )
        
        PuttingTipRow(
          scenario: "Side hill",
          tip: "Plays \(Int(profile.averageSlopePercent * 2)) feet break toward \(cardinalDirection(profile.breakDirection).lowercased())"
        )
      }
    }
    .padding()
    .background(Color.yellow.opacity(0.1))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
    )
  }
  
  // MARK: - Helpers
  
  private func loadGreenData() async {
    isLoading = true
    
    // Get profile from hardcoded data
    if let data = GreystonesGreenData.profile(forHole: holeNumber) {
      let p = (try? GCDB.shared.fetchGreenPerimeter(holeNumber: holeNumber)) ?? []
      
      // Calculate dynamic average slope if we have center/front/back altitude data
      var updatedData = data
      if let greenRec = try? GCDB.shared.fetchGreenCenter(holeNumber: holeNumber),
         let cAlt = greenRec.centerAlt, let fAlt = greenRec.frontAlt, let bAlt = greenRec.backAlt {
          
          let frontDist = distanceYards(lat1: greenRec.centerLat, lng1: greenRec.centerLng, lat2: greenRec.frontLat ?? 0, lng2: greenRec.frontLng ?? 0)
          let backDist = distanceYards(lat1: greenRec.centerLat, lng1: greenRec.centerLng, lat2: greenRec.backLat ?? 0, lng2: greenRec.backLng ?? 0)
          let totalDepth = (frontDist + backDist) * 0.9144 // to meters
          
          let rise = bAlt - fAlt
          if totalDepth > 0 {
              updatedData.averageSlopePercent = (abs(rise) / totalDepth) * 100
              updatedData.primarySlopeDirection = rise > 0 ? 135 : 315 // Simple directional logic for now
          }
      }

      await MainActor.run {
        self.profile = updatedData
        self.perimeter = p
        self.isLoading = false
      }
    } else {
      await MainActor.run {
        self.isLoading = false
      }
    }
  }

  private func distanceYards(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
    let dM = CLLocation(latitude: lat1, longitude: lng1)
      .distance(from: CLLocation(latitude: lat2, longitude: lng2))
    return dM * 1.09361
  }
  
  private func slopeColor(_ slope: Double) -> Color {
    if slope < 2.5 { return .green }
    if slope < 4.5 { return .yellow }
    return .orange
  }
  
  private func cardinalDirection(_ degrees: Double) -> String {
    let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    let index = Int((degrees + 11.25) / 22.5) % 16
    return directions[index]
  }
  
  private func highPointUnit(profile: GreenSlopeProfile) -> UnitPoint {
    unitPointForCoordinate(profile.highPoint.lat, profile.highPoint.lng)
  }
  
  private func lowPointUnit(profile: GreenSlopeProfile) -> UnitPoint {
    unitPointForCoordinate(profile.lowPoint.lat, profile.lowPoint.lng)
  }

  private func unitPointForCoordinate(_ lat: Double, _ lng: Double) -> UnitPoint {
    guard !perimeter.isEmpty else { return .center }
    
    let lats = perimeter.map { $0.latitude }
    let lngs = perimeter.map { $0.longitude }
    let minLat = lats.min() ?? 0
    let maxLat = lats.max() ?? 0
    let minLng = lngs.min() ?? 0
    let maxLng = lngs.max() ?? 0
    
    let x = (lng - minLng) / (maxLng - minLng)
    let y = 1.0 - (lat - minLat) / (maxLat - minLat) // Flip Y for screen coordinates
    
    return UnitPoint(x: x, y: y)
  }
  
  private func highPointPosition(profile: GreenSlopeProfile, in size: CGSize) -> CGPoint {
    let unit = highPointUnit(profile: profile)
    return CGPoint(x: size.width * unit.x, y: size.height * unit.y)
  }
  
  private func lowPointPosition(profile: GreenSlopeProfile, in size: CGSize) -> CGPoint {
    let unit = lowPointUnit(profile: profile)
    return CGPoint(x: size.width * unit.x, y: size.height * unit.y)
  }

  private func regionForPerimeter(_ perimeter: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
    let lats = perimeter.map { $0.latitude }
    let lngs = perimeter.map { $0.longitude }
    let minLat = lats.min() ?? 0
    let maxLat = lats.max() ?? 0
    let minLng = lngs.min() ?? 0
    let maxLng = lngs.max() ?? 0
    
    let center = CLLocationCoordinate2D(
        latitude: (minLat + maxLat) / 2,
        longitude: (minLng + maxLng) / 2
    )
    
    // Calculate span and apply padding
    let spanLat = maxLat - minLat
    let spanLng = maxLng - minLng
    
    // Zoom in more tightly (smaller delta = higher zoom)
    return MKCoordinateRegion(
        center: center,
        span: MKCoordinateSpan(latitudeDelta: spanLat * 1.5, longitudeDelta: spanLng * 1.5)
    )
  }
}

// MARK: - Supporting Views

struct FallLineArrows: View {
  let profile: GreenSlopeProfile
  
  var body: some View {
    Canvas { context, size in
      let centerX: CGFloat = size.width / 2
      let centerY: CGFloat = size.height / 2
      
      // Convert direction to radians
      let degrees: Double = profile.fallLineDirection
      let pi: Double = Double.pi
      let angle: Double = degrees * pi / 180
      
      // Pre-calculate trig values
      let cosAngle: Double = cos(angle)
      let sinAngle: Double = sin(angle)
      let cosPlus30: Double = cos(angle + pi/6)
      let sinPlus30: Double = sin(angle + pi/6)
      let cosMinus30: Double = cos(angle - pi/6)
      let sinMinus30: Double = sin(angle - pi/6)
      
      // Draw arrows along fall line
      for offset in stride(from: -40.0, through: 40.0, by: 20.0) {
        let x: CGFloat = centerX + CGFloat(cosAngle * offset)
        let y: CGFloat = centerY + CGFloat(sinAngle * offset)
        
        // Calculate line endpoints
        let lineStartX: CGFloat = x - CGFloat(cosAngle * 8)
        let lineStartY: CGFloat = y - CGFloat(sinAngle * 8)
        let lineEndX: CGFloat = x + CGFloat(cosAngle * 8)
        let lineEndY: CGFloat = y + CGFloat(sinAngle * 8)
        
        // Arrowhead calculations
        let arrowX: CGFloat = lineEndX
        let arrowY: CGFloat = lineEndY
        let arrowLeftX: CGFloat = arrowX - CGFloat(cosPlus30 * 5)
        let arrowLeftY: CGFloat = arrowY - CGFloat(sinPlus30 * 5)
        let arrowRightX: CGFloat = arrowX - CGFloat(cosMinus30 * 5)
        let arrowRightY: CGFloat = arrowY - CGFloat(sinMinus30 * 5)
        
        var path = Path()
        path.move(to: CGPoint(x: lineStartX, y: lineStartY))
        path.addLine(to: CGPoint(x: lineEndX, y: lineEndY))
        
        // Arrowhead pointing downhill
        path.move(to: CGPoint(x: arrowX, y: arrowY))
        path.addLine(to: CGPoint(x: arrowLeftX, y: arrowLeftY))
        path.move(to: CGPoint(x: arrowX, y: arrowY))
        path.addLine(to: CGPoint(x: arrowRightX, y: arrowRightY))
        
        context.stroke(path, with: .color(.blue.opacity(0.6)), lineWidth: 2)
      }
    }
  }
}

struct HighPointMarker: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white)
        .frame(width: 20, height: 20)
      Text("H")
        .font(.caption)
        .fontWeight(.bold)
        .foregroundColor(.green)
    }
  }
}

struct LowPointMarker: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white)
        .frame(width: 20, height: 20)
      Text("L")
        .font(.caption)
        .fontWeight(.bold)
        .foregroundColor(.blue)
    }
  }
}

struct CompassRose: View {
  let direction: Double
  
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white.opacity(0.9))
        .frame(width: 32, height: 32)
      
      Image(systemName: "arrow.up")
        .font(.caption)
        .fontWeight(.bold)
        .foregroundColor(.primary)
        .rotationEffect(.degrees(direction))
      
      Text("N")
        .font(.system(size: 8, weight: .bold))
        .foregroundColor(.red)
        .offset(y: -10)
    }
  }
}

struct LegendItem: View {
  let color: Color
  let label: String
  var isArrow: Bool = false
  
  var body: some View {
    HStack(spacing: 4) {
      if isArrow {
        Image(systemName: "arrow.right")
          .font(.caption)
          .foregroundColor(color)
      } else {
        Circle()
          .fill(color)
          .frame(width: 10, height: 10)
      }
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

struct SlopeStatBox: View {
  let value: String
  let label: String
  let color: Color
  
  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundColor(color)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(8)
  }
}

struct PuttingTipRow: View {
  let scenario: String
  let tip: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(scenario)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
      Text(tip)
        .font(.subheadline)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ArrowShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    
    path.move(to: CGPoint(x: center.x, y: center.y - 25))
    path.addLine(to: CGPoint(x: center.x, y: center.y + 15))
    
    // Arrowhead
    path.move(to: CGPoint(x: center.x, y: center.y - 25))
    path.addLine(to: CGPoint(x: center.x - 10, y: center.y - 10))
    path.move(to: CGPoint(x: center.x, y: center.y - 25))
    path.addLine(to: CGPoint(x: center.x + 10, y: center.y - 10))
    
    return path
  }
}

struct FallLineGridOverlay: View {
    let profile: GreenSlopeProfile
    
    var body: some View {
        Canvas { context, size in
            let degrees = profile.fallLineDirection
            let angle = degrees * Double.pi / 180
            
            // Draw a grid of arrows
            let step: CGFloat = 40
            for x in stride(from: step, to: size.width, by: step) {
                for y in stride(from: step, to: size.height, by: step) {
                    var path = Path()
                    let length: CGFloat = 15
                    
                    let start = CGPoint(x: x, y: y)
                    let end = CGPoint(
                        x: x + CGFloat(cos(angle)) * length,
                        y: y + CGFloat(sin(angle)) * length
                    )
                    
                    path.move(to: start)
                    path.addLine(to: end)
                    
                    // Arrowhead
                    let arrowAngle = Double.pi / 6
                    let h: CGFloat = 5
                    let p1 = CGPoint(
                        x: end.x - h * CGFloat(cos(angle + arrowAngle)),
                        y: end.y - h * CGFloat(sin(angle + arrowAngle))
                    )
                    let p2 = CGPoint(
                        x: end.x - h * CGFloat(cos(angle - arrowAngle)),
                        y: end.y - h * CGFloat(sin(angle - arrowAngle))
                    )
                    
                    path.move(to: end)
                    path.addLine(to: p1)
                    path.move(to: end)
                    path.addLine(to: p2)
                    
                    context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    GreenHeatmapView(
      holeNumber: 4,
      greenCenter: nil
    )
  }
}
