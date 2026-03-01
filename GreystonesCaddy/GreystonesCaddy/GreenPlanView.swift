import SwiftUI
import CoreLocation
import GreystonesCaddyCore

// MARK: - Heatmap Color (matches Green3DView)

private func heatmapColor(_ v: Double) -> Color {
    let stops: [(pos: Double, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.00, 0.05, 0.05, 0.85),
        (0.12, 0.05, 0.35, 1.00),
        (0.25, 0.00, 0.70, 0.90),
        (0.38, 0.00, 0.90, 0.25),
        (0.50, 0.45, 1.00, 0.00),
        (0.62, 1.00, 0.95, 0.00),
        (0.75, 1.00, 0.55, 0.00),
        (0.88, 0.95, 0.20, 0.00),
        (1.00, 0.75, 0.00, 0.00),
    ]

    let clamped = min(1, max(0, v))
    var lo = stops.first!, hi = stops.last!
    for i in 0..<(stops.count - 1) {
        if clamped >= stops[i].pos && clamped <= stops[i + 1].pos {
            lo = stops[i]
            hi = stops[i + 1]
            break
        }
    }

    let f = hi.pos > lo.pos ? CGFloat((clamped - lo.pos) / (hi.pos - lo.pos)) : 0
    return Color(
        red: lo.r + (hi.r - lo.r) * f,
        green: lo.g + (hi.g - lo.g) * f,
        blue: lo.b + (hi.b - lo.b) * f,
        opacity: 1
    )
}

// MARK: - GreenPlanView

/// Top-down interactive pin-placement view for a golf green.
struct GreenPlanView: View {
    let holeNumber: Int

    @State private var terrain: GreenTerrainData? = nil
    @State private var filledHeights: [[Float]]? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var pinPosition: CGPoint = .zero
    @State private var layoutSize: CGSize = .zero
    @State private var savedMessage: String? = nil
    @State private var saveTask: Task<Void, Never>? = nil

    private let darkGray = Color(white: 0.12)

    var body: some View {
        ZStack {
            darkGray.edgesIgnoringSafeArea(.all)

            if isLoading {
                ProgressView("Loading green...")
                    .foregroundColor(.white)
            } else if let t = terrain {
                VStack(spacing: 0) {
                    // Header with hole number and legend
                    HStack(alignment: .top) {
                        Text("# \(holeNumber)")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("High")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                            verticalLegend()
                                .frame(width: 14, height: 60)
                                .cornerRadius(4)
                            Text("Low")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Main heatmap + pin
                    GeometryReader { geo in
                        ZStack {
                            GreenHeatmapCanvas(terrain: t, filledHeights: filledHeights ?? [])
                                .background(darkGray)
                                .clipShape(GreenPerimeterShape(perimeter: t.perimeter, bounds: terrainBounds(t)))

                            // Front/Back labels
                            frontBackLabels(terrain: t, size: geo.size)

                            // Draggable pin
                            pinView(size: geo.size)
                                .position(pinPosition)
                                .gesture(
                                    DragGesture(minimumDistance: 0, coordinateSpace: .named("greenPlan"))
                                        .onChanged { value in
                                            pinPosition = clampPinToPerimeter(value.location, terrain: t, size: geo.size)
                                        }
                                        .onEnded { value in
                                            pinPosition = clampPinToPerimeter(value.location, terrain: t, size: geo.size)
                                        }
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .coordinateSpace(name: "greenPlan")
                        .onAppear {
                            layoutSize = geo.size
                            pinPosition = centerOfGreen(terrain: t, size: geo.size)
                            loadSavedPin(terrain: t, size: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            layoutSize = newSize
                        }
                    }

                    // Saved confirmation
                    if let msg = savedMessage {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                    }

                    // Confirm button
                    Button(action: confirmPinPosition) {
                        Text("Confirm Pin Position")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage ?? "Terrain data not available")
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .background(darkGray)
        .onAppear { loadTerrain() }
    }

    // MARK: - Helpers

    private func verticalLegend() -> some View {
        LinearGradient(
            colors: stride(from: 1.0, through: 0.0, by: -0.05).map { heatmapColor($0) },
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func loadTerrain() {
        isLoading = true
        if let data = GreenTerrainData.load(hole: holeNumber) {
            var mutableData = data
            let heights = mutableData.filledHeights
            terrain = data
            filledHeights = heights
            isLoading = false
        } else {
            terrain = nil
            filledHeights = nil
            errorMessage = "No terrain data for Hole \(holeNumber)"
            isLoading = false
        }
    }

    private func terrainBounds(_ t: GreenTerrainData) -> (minX: CGFloat, maxX: CGFloat, minZ: CGFloat, maxZ: CGFloat) {
        let px = t.perimeter.map(\.x)
        let pz = t.perimeter.map(\.y)
        return (
            px.min() ?? 0,
            px.max() ?? 0,
            pz.min() ?? 0,
            pz.max() ?? 0
        )
    }

    private func centerOfGreen(terrain: GreenTerrainData, size: CGSize) -> CGPoint {
        let bounds = terrainBounds(terrain)
        let cx = (bounds.minX + bounds.maxX) / 2
        let cz = (bounds.minZ + bounds.maxZ) / 2
        return worldToView(terrain: terrain, worldX: cx, worldZ: cz, size: size)
    }

    private func loadSavedPin(terrain t: GreenTerrainData, size: CGSize) {
        guard let originLat = t.originLat, let originLng = t.originLng,
              let g = try? GCDB.shared.fetchGreenCenter(holeNumber: holeNumber) else { return }
        let dZ = (g.centerLat - originLat) * 111320.0
        let dX = (g.centerLng - originLng) * 111320.0 * cos(originLat * .pi / 180)
        let worldX = CGFloat(Double(t.gridOriginX) + dX)
        let worldZ = CGFloat(Double(t.gridOriginY) + dZ)
        let candidate = worldToView(terrain: t, worldX: worldX, worldZ: worldZ, size: size)
        if candidate.x > 0 && candidate.y > 0 && candidate.x < size.width && candidate.y < size.height {
            pinPosition = candidate
        }
    }

    private func worldToView(terrain: GreenTerrainData, worldX: CGFloat, worldZ: CGFloat, size: CGSize) -> CGPoint {
        let bounds = terrainBounds(terrain)
        let rangeX = bounds.maxX - bounds.minX
        let rangeZ = bounds.maxZ - bounds.minZ
        guard rangeX > 0, rangeZ > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }

        let u = (worldX - bounds.minX) / rangeX
        let v = 1.0 - (worldZ - bounds.minZ) / rangeZ
        return CGPoint(x: u * size.width, y: v * size.height)
    }

    private func viewToWorld(terrain: GreenTerrainData, viewX: CGFloat, viewY: CGFloat, size: CGSize) -> (x: CGFloat, z: CGFloat) {
        let bounds = terrainBounds(terrain)
        let rangeX = bounds.maxX - bounds.minX
        let rangeZ = bounds.maxZ - bounds.minZ
        guard rangeX > 0, rangeZ > 0 else {
            return ((bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2)
        }

        let u = viewX / size.width
        let v = 1.0 - viewY / size.height
        let worldX = bounds.minX + u * rangeX
        let worldZ = bounds.minZ + v * rangeZ
        return (worldX, worldZ)
    }

    private func clampPinToPerimeter(_ point: CGPoint, terrain: GreenTerrainData, size: CGSize) -> CGPoint {
        let (worldX, worldZ) = viewToWorld(terrain: terrain, viewX: point.x, viewY: point.y, size: size)
        let pt = CGPoint(x: worldX, y: worldZ)
        if GreenTerrainData.pointInPolygon(pt, polygon: terrain.perimeter) {
            return point
        }
        return pinPosition
    }

    private func frontBackLabels(terrain: GreenTerrainData, size: CGSize) -> some View {
        let peri = terrain.perimeter
        guard peri.count >= 2 else { return AnyView(EmptyView()) }

        let minZpt = peri.min(by: { $0.y < $1.y })!
        let maxZpt = peri.max(by: { $0.y < $1.y })!
        let frontPos = worldToView(terrain: terrain, worldX: minZpt.x, worldZ: minZpt.y, size: size)
        let backPos = worldToView(terrain: terrain, worldX: maxZpt.x, worldZ: maxZpt.y, size: size)

        return AnyView(
            ZStack {
                Text("● Back")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .position(x: backPos.x + 35, y: backPos.y)
                Text("● Front")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .position(x: frontPos.x + 35, y: frontPos.y)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        )
    }

    private func pinView(size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)
            Image(systemName: "flag.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }

    private func confirmPinPosition() {
        guard let t = terrain else { return }
        guard let originLat = t.originLat, let originLng = t.originLng else {
            savedMessage = "Regenerate green data — origin missing"
            return
        }

        let (worldX, worldZ) = viewToWorld(terrain: t, viewX: pinPosition.x, viewY: pinPosition.y, size: layoutSize)

        let dX = Double(worldX - CGFloat(t.gridOriginX))
        let dZ = Double(worldZ - CGFloat(t.gridOriginY))
        let lat = originLat + dZ / 111320.0
        let lng = originLng + dX / (111320.0 * cos(originLat * .pi / 180))
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        do {
            try GCDB.shared.upsertGreenCenter(
                holeNumber: holeNumber,
                centerLat: coord.latitude,
                centerLng: coord.longitude
            )
            NotificationCenter.default.post(name: .greenCenterDidUpdate, object: nil)
            savedMessage = "Pin position saved"
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { savedMessage = nil }
            }
        } catch {
            savedMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Heatmap Canvas

private struct GreenHeatmapCanvas: View {
    let terrain: GreenTerrainData
    let filledHeights: [[Float]]

    var body: some View {
        Canvas { context, size in
            let bounds = terrainBounds(terrain)
            let rangeX = bounds.maxX - bounds.minX
            let rangeZ = bounds.maxZ - bounds.minZ
            guard rangeX > 0, rangeZ > 0 else { return }

            let filled = filledHeights
            let rows = terrain.rows
            let cols = terrain.cols

            for r in 0..<rows {
                for c in 0..<cols {
                    let wx = CGFloat(terrain.worldX(col: c))
                    let wz = CGFloat(terrain.worldZ(row: r))
                    let pt = CGPoint(x: wx, y: wz)
                    guard GreenTerrainData.pointInPolygon(pt, polygon: terrain.perimeter) else { continue }

                    let h = filled[r][c]
                    let norm = terrain.elevationRange > 0
                        ? min(1, max(0, Double(h / terrain.elevationRange)))
                        : 0.5

                    let u = (wx - bounds.minX) / rangeX
                    let v = 1.0 - (wz - bounds.minZ) / rangeZ
                    let rect = CGRect(
                        x: u * size.width,
                        y: v * size.height,
                        width: max(1, size.width / CGFloat(cols)),
                        height: max(1, size.height / CGFloat(rows))
                    )
                    context.fill(Path(rect), with: .color(heatmapColor(norm)))
                }
            }
        }
    }

    private func terrainBounds(_ t: GreenTerrainData) -> (minX: CGFloat, maxX: CGFloat, minZ: CGFloat, maxZ: CGFloat) {
        let px = t.perimeter.map(\.x)
        let pz = t.perimeter.map(\.y)
        return (
            px.min() ?? 0,
            px.max() ?? 0,
            pz.min() ?? 0,
            pz.max() ?? 0
        )
    }
}

// MARK: - Perimeter Mask Shape

private struct GreenPerimeterShape: Shape {
    let perimeter: [CGPoint]
    let bounds: (minX: CGFloat, maxX: CGFloat, minZ: CGFloat, maxZ: CGFloat)

    func path(in rect: CGRect) -> Path {
        guard perimeter.count >= 3 else {
            return Path(rect)
        }

        let rangeX = bounds.maxX - bounds.minX
        let rangeZ = bounds.maxZ - bounds.minZ
        guard rangeX > 0, rangeZ > 0 else { return Path(rect) }

        var path = Path()
        for (i, pt) in perimeter.enumerated() {
            let u = (pt.x - bounds.minX) / rangeX
            let v = 1.0 - (pt.y - bounds.minZ) / rangeZ
            let x = rect.minX + u * rect.width
            let y = rect.minY + v * rect.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GreenPlanView(holeNumber: 1)
    }
}
