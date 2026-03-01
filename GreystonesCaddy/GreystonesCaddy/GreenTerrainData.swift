import Foundation

struct GreenTerrainData {
    let hole: Int
    let cols: Int
    let rows: Int
    let cellSize: Float
    let gridOriginX: Float
    let gridOriginY: Float
    let originLat: Double?
    let originLng: Double?
    let nodata: Float
    let heights: [[Float]]
    let perimeter: [CGPoint]
    let minRawElevation: Float
    let maxRawElevation: Float
    let elevationRange: Float

    func isValid(row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < cols else { return false }
        return heights[row][col] != nodata
    }

    func height(row: Int, col: Int) -> Float {
        guard isValid(row: row, col: col) else { return 0 }
        return heights[row][col]
    }

    /// Precomputed filled heights: valid cells use real height; invalid use nearest valid (BFS).
    /// O(rows*cols) computed once, avoids per-vertex search. Use for mesh building.
    lazy var filledHeights: [[Float]] = makeFilledHeights()

    private func makeFilledHeights() -> [[Float]] {
        var result = heights
        var queue: [(Int, Int)] = []
        for r in 0..<rows {
            for c in 0..<cols {
                if isValid(row: r, col: c) { queue.append((r, c)) }
            }
        }
        let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var idx = 0
        while idx < queue.count {
            let (r, c) = queue[idx]
            idx += 1
            let h = result[r][c]
            for (dr, dc) in dirs {
                let nr = r + dr, nc = c + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                guard !isValid(row: nr, col: nc), result[nr][nc] == nodata else { continue }
                result[nr][nc] = h
                queue.append((nr, nc))
            }
        }
        for r in 0..<rows {
            for c in 0..<cols {
                if result[r][c] == nodata { result[r][c] = 0 }
            }
        }
        return result
    }

    func worldX(col: Int) -> Float {
        gridOriginX + Float(col) * cellSize
    }

    func worldZ(row: Int) -> Float {
        gridOriginY - Float(row) * cellSize
    }

    func worldXf(col: Float) -> Float {
        gridOriginX + col * cellSize
    }

    func worldZf(row: Float) -> Float {
        gridOriginY - row * cellSize
    }

    func interpolatedHeight(atX x: Float, z: Float) -> Float? {
        let colF = (x - gridOriginX) / cellSize
        let rowF = (gridOriginY - z) / cellSize

        let c0 = Int(floor(colF))
        let r0 = Int(floor(rowF))
        let c1 = c0 + 1
        let r1 = r0 + 1

        guard isValid(row: r0, col: c0), isValid(row: r0, col: c1),
              isValid(row: r1, col: c0), isValid(row: r1, col: c1) else {
            let cr = max(0, min(r0, rows - 1))
            let cc = max(0, min(c0, cols - 1))
            if isValid(row: cr, col: cc) { return height(row: cr, col: cc) }
            return nil
        }

        let dc = colF - Float(c0)
        let dr = rowF - Float(r0)
        let top = height(row: r0, col: c0) + dc * (height(row: r0, col: c1) - height(row: r0, col: c0))
        let bot = height(row: r1, col: c0) + dc * (height(row: r1, col: c1) - height(row: r1, col: c0))
        return top + dr * (bot - top)
    }

    func interpolatedHeightGrid(atRow rowF: Float, col colF: Float) -> Float? {
        let r0 = Int(floor(rowF))
        let c0 = Int(floor(colF))
        let r1 = r0 + 1
        let c1 = c0 + 1

        guard isValid(row: r0, col: c0), isValid(row: r0, col: c1),
              isValid(row: r1, col: c0), isValid(row: r1, col: c1) else {
            let cr = max(0, min(r0, rows - 1))
            let cc = max(0, min(c0, cols - 1))
            if isValid(row: cr, col: cc) { return height(row: cr, col: cc) }
            return nil
        }

        let dc = colF - Float(c0)
        let dr = rowF - Float(r0)
        let top = height(row: r0, col: c0) + dc * (height(row: r0, col: c1) - height(row: r0, col: c0))
        let bot = height(row: r1, col: c0) + dc * (height(row: r1, col: c1) - height(row: r1, col: c0))
        return top + dr * (bot - top)
    }

    func smoothedHeights(radius: Int = 3) -> [[Float]] {
        var result = heights
        for r in 0..<rows {
            for c in 0..<cols {
                guard isValid(row: r, col: c) else { continue }
                var sum: Float = 0
                var weight: Float = 0
                for dr in -radius...radius {
                    for dc in -radius...radius {
                        let nr = r + dr
                        let nc = c + dc
                        guard isValid(row: nr, col: nc) else { continue }
                        let w = exp(-Float(dr * dr + dc * dc) / Float(2 * radius * radius))
                        sum += heights[nr][nc] * w
                        weight += w
                    }
                }
                if weight > 0 { result[r][c] = sum / weight }
            }
        }
        return result
    }

    /// Check that a cell AND all neighbors within `margin` cells are valid.
    /// Prevents arrows from appearing near the raster boundary.
    func isInterior(row: Int, col: Int, margin: Int = 3) -> Bool {
        for dr in -margin...margin {
            for dc in -margin...margin {
                if !isValid(row: row + dr, col: col + dc) { return false }
            }
        }
        return true
    }

    /// Extracts the ordered boundary of valid raster cells as world-space points.
    /// Uses marching-squares-style edge tracing for a clean outline.
    func computeRasterBoundary() -> [CGPoint] {
        var edgePoints = [(x: Float, z: Float)]()

        for r in 0..<rows {
            for c in 0..<cols {
                guard isValid(row: r, col: c) else { continue }
                let isBorder = !isValid(row: r - 1, col: c) ||
                               !isValid(row: r + 1, col: c) ||
                               !isValid(row: r, col: c - 1) ||
                               !isValid(row: r, col: c + 1)
                if isBorder {
                    edgePoints.append((x: worldX(col: c), z: worldZ(row: r)))
                }
            }
        }

        guard edgePoints.count > 2 else {
            return edgePoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) }
        }

        // Order boundary points by angle from centroid
        let cx = edgePoints.map(\.x).reduce(0, +) / Float(edgePoints.count)
        let cz = edgePoints.map(\.z).reduce(0, +) / Float(edgePoints.count)
        edgePoints.sort { a, b in
            atan2(a.z - cz, a.x - cx) < atan2(b.z - cz, b.x - cx)
        }

        return edgePoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.z)) }
    }

    // MARK: - Polygon Mask

    func computePerimeterMask() -> [[Bool]] {
        var mask = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let pt = CGPoint(x: CGFloat(worldX(col: c)), y: CGFloat(worldZ(row: r)))
                mask[r][c] = Self.pointInPolygon(pt, polygon: perimeter)
            }
        }
        return mask
    }

    func isInsidePerimeter(worldX x: Float, worldZ z: Float) -> Bool {
        Self.pointInPolygon(CGPoint(x: CGFloat(x), y: CGFloat(z)), polygon: perimeter)
    }

    static func pointInPolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if (pi.y > p.y) != (pj.y > p.y) &&
               p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Loading

    static func load(hole: Int) -> GreenTerrainData? {
        let name = String(format: "H%02d_green_data", hole)
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("[GreenTerrainData] \(name).json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return parse(json: json)
        } catch {
            print("[GreenTerrainData] Failed to load \(name): \(error)")
            return nil
        }
    }

    private static func parse(json: [String: Any]?) -> GreenTerrainData? {
        guard let json = json,
              let hole = json["hole"] as? Int,
              let gridDict = json["grid"] as? [String: Any],
              let cols = gridDict["cols"] as? Int,
              let rows = gridDict["rows"] as? Int,
              let cellSize = gridDict["cellSize"] as? Double,
              let originX = gridDict["originX"] as? Double,
              let originY = gridDict["originY"] as? Double,
              let nodataVal = gridDict["nodata"] as? Double,
              let heightRows = gridDict["heights"] as? [[Double]],
              let perimeterArr = json["perimeter"] as? [[String: Double]],
              let elevDict = json["elevation"] as? [String: Double],
              let minRaw = elevDict["minRaw"],
              let maxRaw = elevDict["maxRaw"],
              let range = elevDict["range"]
        else { return nil }

        let heights = heightRows.map { row in row.map { Float($0) } }
        let perimeter = perimeterArr.compactMap { dict -> CGPoint? in
            guard let x = dict["x"], let y = dict["y"] else { return nil }
            return CGPoint(x: x, y: y)
        }

        return GreenTerrainData(
            hole: hole, cols: cols, rows: rows,
            cellSize: Float(cellSize),
            gridOriginX: Float(originX), gridOriginY: Float(originY),
            originLat: gridDict["originLat"] as? Double,
            originLng: gridDict["originLng"] as? Double,
            nodata: Float(nodataVal), heights: heights,
            perimeter: perimeter,
            minRawElevation: Float(minRaw),
            maxRawElevation: Float(maxRaw),
            elevationRange: Float(range)
        )
    }
}
