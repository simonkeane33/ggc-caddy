import SwiftUI
import CoreLocation
import UIKit
import GreystonesCaddyCore

// MARK: - Heatmap Color (blue low → red high)

private func heatmapColor(_ v: Double) -> Color {
    Color(uiColor: heatmapUIColor(v))
}

private func heatmapUIColor(_ v: Double) -> UIColor {
    let clamped = min(1, max(0, v))
    // blue → cyan → green → yellow → orange → red
    if clamped < 0.2 {
        let t = clamped / 0.2
        return UIColor(red: 0, green: CGFloat(t * 0.5), blue: CGFloat(0.85 + (1 - t) * 0.15), alpha: 1)
    } else if clamped < 0.4 {
        let t = (clamped - 0.2) / 0.2
        return UIColor(red: 0, green: CGFloat(0.5 + t * 0.5), blue: CGFloat(1 - t * 0.5), alpha: 1)
    } else if clamped < 0.6 {
        let t = (clamped - 0.4) / 0.2
        return UIColor(red: CGFloat(t * 0.45), green: 1, blue: 0, alpha: 1)
    } else if clamped < 0.8 {
        let t = (clamped - 0.6) / 0.2
        return UIColor(red: CGFloat(0.45 + t * 0.55), green: 1, blue: 0, alpha: 1)
    } else {
        let t = (clamped - 0.8) / 0.2
        return UIColor(red: 1, green: CGFloat(1 - t * 0.25), blue: 0, alpha: 1)
    }
}

// MARK: - Slope Data (computed once)

private typealias ContourSegment = (start: CGPoint, end: CGPoint)

private struct SlopeData {
    var averageSlopePercent: Double
    var downhillDirection: String
    var smoothedHeights: [[Float]]
    var smoothedMin: Float
    var smoothedMax: Float
    var contourLevels: [Float]
    var contourSegmentsByLevel: [[ContourSegment]]
}

// MARK: - GreenMapView

/// Consolidated 2D top-down green view: heatmap, slope arrows, draggable pin.
struct GreenMapView: View {
    let holeNumber: Int

    @State private var terrain: GreenTerrainData? = nil
    @State private var filledHeights: [[Float]]? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var pinPosition: CGPoint = .zero
    @State private var layoutSize: CGSize = .zero
    @State private var isEditingPin = false

    @State private var showHeatmap = true
    @State private var showContours = true
    @State private var slopeData: SlopeData? = nil
    @State private var heatmapImage: UIImage? = nil
    @State private var mapScale: CGFloat = 1.0
    @State private var mapOffset: CGSize = .zero
    @State private var lastMapScale: CGFloat = 1.0
    @State private var lastMapOffset: CGSize = .zero

    private let darkGray = Color(white: 0.12)

    var body: some View {
        ZStack {
            darkGray.edgesIgnoringSafeArea(.all)

            if isLoading {
                ProgressView("Loading green...")
                    .foregroundColor(.white)
            } else if let t = terrain {
                VStack(spacing: 0) {
                    // Top bar: heatmap toggle, contours toggle, compass
                    HStack {
                        Button {
                            showHeatmap.toggle()
                        } label: {
                            Image(systemName: "thermometer.medium")
                                .font(.title3)
                                .foregroundColor(showHeatmap ? .white : .gray)
                        }
                        .padding(12)

                        Button {
                            showContours.toggle()
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.title3)
                                .foregroundColor(showContours ? .white : .gray)
                        }
                        .padding(12)

                        Spacer()

                        Button {
                            isEditingPin.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                if isEditingPin {
                                    Text("Done")
                                        .font(.subheadline.weight(.semibold))
                                } else {
                                    Image(systemName: "mappin")
                                    Text("Edit Pin")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isEditingPin ? Color.green : Color.blue)
                            .clipShape(Capsule())
                        }
                        .padding(.trailing, 8)

                        CompassRose(direction: 0)
                            .padding(12)
                    }
                    .background(darkGray.opacity(0.9))

                    // Main content: heatmap + contours + pin
                    GeometryReader { geo in
                        ZStack {
                            // Background gesture layer for map pan/zoom/reset.
                            Color.clear
                                .contentShape(Rectangle())
                                .allowsHitTesting(!isEditingPin)
                                .gesture(
                                    DragGesture(minimumDistance: 20, coordinateSpace: .named("greenMap"))
                                        .onChanged { value in
                                            mapOffset = CGSize(
                                                width: lastMapOffset.width + value.translation.width,
                                                height: lastMapOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastMapOffset = mapOffset
                                        }
                                )
                                .simultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            mapScale = max(1.0, min(5.0, lastMapScale * value))
                                        }
                                        .onEnded { _ in
                                            lastMapScale = mapScale
                                        }
                                )
                                .simultaneousGesture(
                                    TapGesture(count: 2)
                                        .onEnded {
                                            mapScale = 1.0
                                            mapOffset = .zero
                                            lastMapScale = 1.0
                                            lastMapOffset = .zero
                                        }
                                )

                            ZStack {
                                // Heatmap layer (pre-rendered image for performance)
                                if showHeatmap {
                                    heatmapLayer(terrain: t, size: geo.size)
                                        .background(darkGray)
                                }

                                // Contour overlay (after heatmap)
                                if showContours, let sd = slopeData {
                                    contoursLayer(terrain: t, slopeData: sd, size: geo.size)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(PerimeterClipShape(perimeter: t.perimeter, bounds: terrainBounds(t)))
                            .scaleEffect(mapScale)
                            .offset(mapOffset)
                            .allowsHitTesting(false)

                            // Draggable pin (enabled only while editing).
                            if isEditingPin {
                                pinView()
                                    .position(pinPosition)
                                    .scaleEffect(mapScale)
                                    .offset(mapOffset)
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .named("greenMap"))
                                            .onChanged { value in
                                                let mapPoint = transformedToMapPoint(value.location, size: geo.size)
                                                pinPosition = clampPinToPerimeter(mapPoint, terrain: t, size: geo.size)
                                            }
                                            .onEnded { value in
                                                let mapPoint = transformedToMapPoint(value.location, size: geo.size)
                                                pinPosition = clampPinToPerimeter(mapPoint, terrain: t, size: geo.size)
                                                savePinPosition(terrain: t, size: geo.size)
                                            }
                                    )
                            } else {
                                pinView()
                                    .position(pinPosition)
                                    .scaleEffect(mapScale)
                                    .offset(mapOffset)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .coordinateSpace(name: "greenMap")
                        .onAppear {
                            layoutSize = geo.size
                            pinPosition = centerOfGreen(terrain: t, size: geo.size)
                            loadSavedPin(terrain: t, size: geo.size)
                            slopeData = computeSlopeData(terrain: t, filledHeights: filledHeights, size: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            layoutSize = newSize
                            if let sd = slopeData {
                                heatmapImage = renderHeatmapImage(
                                    terrain: t,
                                    smoothedHeights: sd.smoothedHeights,
                                    smoothedMin: sd.smoothedMin,
                                    smoothedMax: sd.smoothedMax,
                                    size: newSize
                                )
                            }
                        }
                    }

                    // Slope info panel
                    if let sd = slopeData {
                        slopeInfoPanel(slopeData: sd)
                    }

                    // Legend
                    HStack(spacing: 2) {
                        Text("Low").font(.caption2).foregroundColor(.secondary).padding(.trailing, 4)
                        ForEach([Color.blue, .cyan, .green, .yellow, .orange, .red], id: \.self) { color in
                            Rectangle().fill(color).frame(height: 8)
                        }
                        Text("High").font(.caption2).foregroundColor(.secondary).padding(.leading, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(darkGray.opacity(0.9))
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
        .navigationTitle("Hole \(holeNumber) Green")
        .onAppear { loadTerrain() }
    }

    // MARK: - Layers

    private func heatmapLayer(terrain t: GreenTerrainData, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard let img = heatmapImage else { return }
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.draw(Image(uiImage: img), in: rect)
        }
    }

    private func contoursLayer(terrain t: GreenTerrainData, slopeData sd: SlopeData, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let bounds = terrainBounds(t)
            let rangeX = bounds.maxX - bounds.minX
            let rangeZ = bounds.maxZ - bounds.minZ
            guard rangeX > 0, rangeZ > 0 else { return }

            for segments in sd.contourSegmentsByLevel {
                for seg in segments {
                    let u1 = (seg.start.x - bounds.minX) / rangeX
                    let v1 = 1.0 - (seg.start.y - bounds.minZ) / rangeZ
                    let u2 = (seg.end.x - bounds.minX) / rangeX
                    let v2 = 1.0 - (seg.end.y - bounds.minZ) / rangeZ
                    let p1 = CGPoint(x: u1 * canvasSize.width, y: v1 * canvasSize.height)
                    let p2 = CGPoint(x: u2 * canvasSize.width, y: v2 * canvasSize.height)

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: 1.2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func slopeInfoPanel(slopeData sd: SlopeData) -> some View {
        HStack(spacing: 24) {
            Text("Avg slope: \(String(format: "%.1f", sd.averageSlopePercent))%")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Downhill: \(sd.downhillDirection)")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(darkGray.opacity(0.9))
        .cornerRadius(10)
        .padding(.vertical, 6)
    }


    private func pinView() -> some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 32))
            .foregroundColor(.red)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }

    // MARK: - Helpers

    private func renderHeatmapImage(
        terrain t: GreenTerrainData,
        smoothedHeights: [[Float]],
        smoothedMin: Float,
        smoothedMax: Float,
        size: CGSize
    ) -> UIImage? {
        let bounds = terrainBounds(t)
        let rangeX = bounds.maxX - bounds.minX
        let rangeZ = bounds.maxZ - bounds.minZ
        guard rangeX > 0, rangeZ > 0 else { return nil }
        let elevRange = smoothedMax - smoothedMin

        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            let rows = t.rows
            let cols = t.cols

            for r in 0..<rows {
                for c in 0..<cols {
                    let wx = CGFloat(t.worldX(col: c))
                    let wz = CGFloat(t.worldZ(row: r))
                    let pt = CGPoint(x: wx, y: wz)
                    guard GreenTerrainData.pointInPolygon(pt, polygon: t.perimeter) else { continue }

                    let h = smoothedHeights[r][c]
                    let norm = elevRange > 0 ? min(1, max(0, Double((h - smoothedMin) / elevRange))) : 0.5

                    let u = (wx - bounds.minX) / rangeX
                    let v = 1.0 - (wz - bounds.minZ) / rangeZ
                    let rect = CGRect(
                        x: u * size.width - 0.5,
                        y: v * size.height - 0.5,
                        width: max(1, size.width / CGFloat(cols)) + 1.0,
                        height: max(1, size.height / CGFloat(rows)) + 1.0
                    )
                    heatmapUIColor(norm).setFill()
                    UIRectFill(rect)
                }
            }
        }
        return img
    }

    private func computeSlopeData(terrain t: GreenTerrainData, filledHeights: [[Float]]?, size: CGSize) -> SlopeData? {
        guard let filled = filledHeights, !filled.isEmpty else { return nil }
        let rows = t.rows
        let cols = t.cols
        let cellSize = Double(t.cellSize)
        guard cellSize > 0, rows >= 3, cols >= 3 else { return nil }
        let blurRadius = 10

        var smoothed = Array(repeating: Array(repeating: t.nodata, count: cols), count: rows)
        for r in 0..<rows {
            for c in 0..<cols {
                var sum: Double = 0
                var n: Int = 0
                let r0 = max(0, r - blurRadius)
                let r1 = min(rows - 1, r + blurRadius)
                let c0 = max(0, c - blurRadius)
                let c1 = min(cols - 1, c + blurRadius)
                for rr in r0...r1 {
                    for cc in c0...c1 {
                        let raw = t.heights[rr][cc]
                        guard raw != t.nodata else { continue }
                        sum += Double(raw)
                        n += 1
                    }
                }
                if n > 0 {
                    smoothed[r][c] = Float(sum / Double(n))
                } else {
                    smoothed[r][c] = filled[r][c]
                }
            }
        }

        var slopeSum: Double = 0
        var count: Int = 0
        var sumDzdx: Double = 0
        var sumDzdy: Double = 0
        var smoothedMin = Float.infinity
        var smoothedMax = -Float.infinity

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                let wx = CGFloat(t.worldX(col: c))
                let wz = CGFloat(t.worldZ(row: r))
                let pt = CGPoint(x: wx, y: wz)
                guard GreenTerrainData.pointInPolygon(pt, polygon: t.perimeter) else { continue }

                let h = smoothed[r][c]
                smoothedMin = min(smoothedMin, h)
                smoothedMax = max(smoothedMax, h)
                let hL = smoothed[r][c - 1]
                let hR = smoothed[r][c + 1]
                let hN = smoothed[r - 1][c]
                let hS = smoothed[r + 1][c]
                if hL == t.nodata || hR == t.nodata || hN == t.nodata || hS == t.nodata { continue }

                let dzdx = Double(hR - hL) / (2 * cellSize)
                let dzdy = Double(hS - hN) / (2 * cellSize)
                let mag = sqrt(dzdx * dzdx + dzdy * dzdy)
                let slopePercent: Double = mag * 100.0

                slopeSum += slopePercent
                sumDzdx += dzdx
                sumDzdy += dzdy
                count += 1
            }
        }

        guard count > 0, smoothedMin.isFinite, smoothedMax.isFinite else { return nil }

        let avgSlope = slopeSum / Double(count)
        let avgDzdx = sumDzdx / Double(count)
        let avgDzdy = sumDzdy / Double(count)
        let downhillDir = compassDirection(dzdx: avgDzdx, dzdy: avgDzdy)
        let contourLevels = contourLevels(min: smoothedMin, max: smoothedMax, count: 7)
        let contourSegmentsByLevel = contourLevels.map { level in
            marchingSquaresSegments(terrain: t, smoothedHeights: smoothed, level: level)
        }

        heatmapImage = renderHeatmapImage(
            terrain: t,
            smoothedHeights: smoothed,
            smoothedMin: smoothedMin,
            smoothedMax: smoothedMax,
            size: size
        )

        return SlopeData(
            averageSlopePercent: avgSlope,
            downhillDirection: downhillDir,
            smoothedHeights: smoothed,
            smoothedMin: smoothedMin,
            smoothedMax: smoothedMax,
            contourLevels: contourLevels,
            contourSegmentsByLevel: contourSegmentsByLevel
        )
    }

    private func transformedToMapPoint(_ point: CGPoint, size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let x = ((point.x - mapOffset.width) - center.x) / mapScale + center.x
        let y = ((point.y - mapOffset.height) - center.y) / mapScale + center.y
        return CGPoint(x: x, y: y)
    }

    private func contourLevels(min: Float, max: Float, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        let range = max - min
        if range <= 1e-6 { return Array(repeating: min, count: count) }
        let step = range / Float(count + 1)
        return (1...count).map { i in min + Float(i) * step }
    }

    private func marchingSquaresSegments(
        terrain t: GreenTerrainData,
        smoothedHeights: [[Float]],
        level: Float
    ) -> [ContourSegment] {
        var segments: [ContourSegment] = []
        let rows = t.rows
        let cols = t.cols
        guard rows >= 2, cols >= 2 else { return segments }

        func interpolate(_ p1: CGPoint, _ p2: CGPoint, _ v1: Float, _ v2: Float) -> CGPoint {
            let denom = v2 - v1
            if abs(denom) < 1e-6 {
                return CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
            }
            let tVal = CGFloat((level - v1) / denom)
            return CGPoint(
                x: p1.x + (p2.x - p1.x) * tVal,
                y: p1.y + (p2.y - p1.y) * tVal
            )
        }

        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let center = CGPoint(
                    x: CGFloat(t.worldXf(col: Float(c) + 0.5)),
                    y: CGFloat(t.worldZf(row: Float(r) + 0.5))
                )
                guard GreenTerrainData.pointInPolygon(center, polygon: t.perimeter) else { continue }

                let v00 = smoothedHeights[r][c]
                let v10 = smoothedHeights[r][c + 1]
                let v01 = smoothedHeights[r + 1][c]
                let v11 = smoothedHeights[r + 1][c + 1]
                if v00 == t.nodata || v10 == t.nodata || v01 == t.nodata || v11 == t.nodata { continue }

                let p00 = CGPoint(x: CGFloat(t.worldX(col: c)), y: CGFloat(t.worldZ(row: r)))
                let p10 = CGPoint(x: CGFloat(t.worldX(col: c + 1)), y: CGFloat(t.worldZ(row: r)))
                let p01 = CGPoint(x: CGFloat(t.worldX(col: c)), y: CGFloat(t.worldZ(row: r + 1)))
                let p11 = CGPoint(x: CGFloat(t.worldX(col: c + 1)), y: CGFloat(t.worldZ(row: r + 1)))

                var crossings: [CGPoint] = []
                if (v00 < level) != (v10 < level) { crossings.append(interpolate(p00, p10, v00, v10)) }
                if (v10 < level) != (v11 < level) { crossings.append(interpolate(p10, p11, v10, v11)) }
                if (v11 < level) != (v01 < level) { crossings.append(interpolate(p11, p01, v11, v01)) }
                if (v01 < level) != (v00 < level) { crossings.append(interpolate(p01, p00, v01, v00)) }

                if crossings.count == 2 {
                    segments.append((start: crossings[0], end: crossings[1]))
                } else if crossings.count == 4 {
                    segments.append((start: crossings[0], end: crossings[1]))
                    segments.append((start: crossings[2], end: crossings[3]))
                }
            }
        }

        return segments
    }

    private func compassDirection(dzdx: Double, dzdy: Double) -> String {
        let angle = atan2(-dzdy, -dzdx) * 180.0 / .pi
        let deg = (angle + 360.0).truncatingRemainder(dividingBy: 360.0)
        let labels = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
        let idx = Int((deg + 22.5) / 45.0) % 8
        return labels[idx]
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

    private func savePinPosition(terrain t: GreenTerrainData, size: CGSize) {
        guard let originLat = t.originLat, let originLng = t.originLng else {
            return
        }

        let (worldX, worldZ) = viewToWorld(terrain: t, viewX: pinPosition.x, viewY: pinPosition.y, size: size)

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
        } catch {
            print("Failed to save pin: \(error.localizedDescription)")
        }
    }
}

// MARK: - Perimeter Clip Shape

private struct PerimeterClipShape: Shape {
    let perimeter: [CGPoint]
    let bounds: (minX: CGFloat, maxX: CGFloat, minZ: CGFloat, maxZ: CGFloat)

    func path(in rect: CGRect) -> Path {
        guard perimeter.count >= 3 else { return Path(rect) }

        let rangeX = bounds.maxX - bounds.minX
        let rangeZ = bounds.maxZ - bounds.minZ
        guard rangeX > 0, rangeZ > 0 else { return Path(rect) }

        var points: [CGPoint] = []
        points.reserveCapacity(perimeter.count)
        for pt in perimeter {
            let u = (pt.x - bounds.minX) / rangeX
            let v = 1.0 - (pt.y - bounds.minZ) / rangeZ
            let x = rect.minX + u * rect.width
            let y = rect.minY + v * rect.height
            points.append(CGPoint(x: x, y: y))
        }
        guard points.count >= 3 else { return Path(rect) }

        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        }

        var path = Path()
        let firstMid = midpoint(points[0], points[1])
        path.move(to: firstMid)
        for i in 1..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            let nextMid = midpoint(current, next)
            path.addCurve(to: nextMid, control1: current, control2: current)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GreenMapView(holeNumber: 1)
    }
}
