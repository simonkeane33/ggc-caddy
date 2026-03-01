import SwiftUI
import SceneKit
import CoreLocation

/// Shared terrain→scene transform. Apply consistently to mesh, mask, and perimeter line.
private struct TerrainToScene {
    let zSign: Float
    func x(_ x: Double) -> Float { Float(x) }
    func z(_ z: Double) -> Float { zSign * Float(z) }
}

private extension SCNVector3 {
    func cross(_ b: SCNVector3) -> SCNVector3 {
        SCNVector3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }
    func normalized() -> SCNVector3 {
        let len = sqrt(x * x + y * y + z * z)
        guard len > 0 else { return self }
        return SCNVector3(x / len, y / len, z / len)
    }
}

// MARK: - SwiftUI View

struct Green3DView: View {
    let holeNumber: Int
    var greenCenter: CLLocationCoordinate2D? = nil

    @State private var terrain: GreenTerrainData? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var exaggeration: Double = 1.02

    var body: some View {
        ZStack {
            Color(white: 0.12).edgesIgnoringSafeArea(.all)

            if isLoading {
                ProgressView("Analyzing Terrain...").foregroundColor(.white)
            } else if let t = terrain {
                GreenSceneView(terrain: t, exaggeration: exaggeration)
                    .edgesIgnoringSafeArea(.all)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(errorMessage ?? "Terrain data not available")
                        .foregroundColor(.white).multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text("# \(holeNumber)")
                        .font(.title2.bold()).foregroundColor(.white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("High").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                        verticalLegend().frame(width: 14, height: 60).cornerRadius(4)
                        Text("Low").font(.system(size: 9, weight: .bold)).foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 8) {
                    Text("Adjust Magnification")
                        .foregroundColor(.white)
                    HStack {
                        Text("Low")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Slider(value: $exaggeration, in: 1.0...3.0)
                        Text("High")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(white: 0.18).opacity(0.9))
                .cornerRadius(8)
                .padding(.horizontal, 16)

                Text("Pinch to zoom · Drag to rotate")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .onAppear { loadTerrain() }
    }

    private func verticalLegend() -> some View {
        LinearGradient(
            colors: stride(from: 1.0, through: 0.0, by: -0.05).map {
                Color(GreenSceneView.heatmapColor($0))
            },
            startPoint: .top, endPoint: .bottom
        )
    }

    private func loadTerrain() {
        isLoading = true
        if let data = GreenTerrainData.load(hole: holeNumber) {
            terrain = data
            isLoading = false
        } else {
            errorMessage = "No terrain data for Hole \(holeNumber)"
            isLoading = false
        }
    }
}

// MARK: - UIViewRepresentable (persistent SCNView with full camera control)

private struct GreenSceneView: UIViewRepresentable {
    let terrain: GreenTerrainData
    let exaggeration: Double

    // Debug toggles
    private static let enableEdgeClip = true   // Perimeter mask drives silhouette (full grid + shader discard)
    private static let debugShowMask = false  // Set true to verify mask alignment as diffuse
    private static let maskVFlip = false      // Toggle to try v-flip if mask appears inverted
    private static let debugShowPerimeterLine = false  // Draw perimeter polyline overlay

    /// Terrain→scene: try zSign -1 if perimeter line is mirrored
    private static let T = TerrainToScene(zSign: -1)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 89

        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.12, alpha: 1)

        addLighting(to: scene)
        addCamera(to: scene, view: view)
        scene.rootNode.addChildNode(buildGridFloor())
        addTerrainGroup(to: scene, exag: Float(exaggeration))

        view.scene = scene
        context.coordinator.lastExag = exaggeration
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard abs(context.coordinator.lastExag - exaggeration) > 0.01,
              let scene = view.scene,
              let group = scene.rootNode.childNode(withName: "terrainGroup", recursively: false) else { return }
        context.coordinator.lastExag = exaggeration
        group.scale = SCNVector3(1, Float(exaggeration), 1)
    }

    final class Coordinator { var lastExag: Double = 0 }

    // MARK: - Scene Setup

    private func addLighting(to scene: SCNScene) {
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 700
        amb.light!.color = UIColor(white: 1, alpha: 1)
        scene.rootNode.addChildNode(amb)

        let dir = SCNNode()
        dir.light = SCNLight()
        dir.light!.type = .directional
        dir.light!.intensity = 1200
        dir.light!.castsShadow = true
        dir.light!.shadowRadius = 4
        dir.light!.shadowSampleCount = 8
        dir.position = SCNVector3(8, 50, 20)
        dir.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(dir)
    }

    private func addCamera(to scene: SCNScene, view: SCNView) {
        let cam = SCNNode()
        cam.name = "mainCamera"
        cam.camera = SCNCamera()
        cam.camera!.zNear = 0.05
        cam.camera!.zFar = 500
        cam.camera!.fieldOfView = 40
        cam.position = SCNVector3(0, 25, 22)
        cam.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam
    }

    private func addTerrainGroup(to scene: SCNScene, exag: Float) {
        let group = SCNNode()
        group.name = "terrainGroup"

        // Debug: prove what terrain.perimeter is (raster-derived vs vector)
        let peri = terrain.perimeter
        if !peri.isEmpty {
            var totalDist: CGFloat = 0
            for i in 0..<(peri.count - 1) {
                let dx = peri[i + 1].x - peri[i].x
                let dy = peri[i + 1].y - peri[i].y
                totalDist += sqrt(dx * dx + dy * dy)
            }
            let avgDist = totalDist / CGFloat(max(1, peri.count - 1))
            print("[perimeter] count: \(peri.count) | avg spacing: \(String(format: "%.4f", avgDist))m | cellSize: \(terrain.cellSize)m")
        }

        let buildExag: Float = 1.0
        let surface = SCNNode(geometry: buildGridMesh(exag: buildExag))
        group.addChildNode(surface)

        if Self.debugShowPerimeterLine, peri.count >= 2 {
            let lineNode = buildPerimeterLineNode(exag: buildExag)
            group.addChildNode(lineNode)
        }

        let wallsNode = SCNNode(geometry: buildCakeSides(exag: buildExag))
        group.addChildNode(wallsNode)

        // Arrows disabled for now; focusing on contour/grid-based read.

        group.scale = SCNVector3(1, exag, 1)
        scene.rootNode.addChildNode(group)
    }

    // MARK: - Perimeter Mask (smooth edge clipping)

    private static let fragmentMaskShader = """
    #pragma arguments
    texture2d<float, access::sample> edgeMask;
    sampler edgeMaskSampler;

    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float a = edgeMask.sample(edgeMaskSampler, uv).r;
    if (a < 0.5) discard_fragment();
    """

    private func buildPerimeterMaskImage(
        width W: Int, height H: Int,
        minX: Float, maxX: Float, minZ: Float, maxZ: Float,
        vFlip: Bool
    ) -> UIImage {
        let t = terrain
        guard t.perimeter.count >= 3 else {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
            return renderer.image { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: W, height: H))
            }
        }
        let rangeX = maxX - minX
        let rangeZ = maxZ - minZ
        guard rangeX > 0, rangeZ > 0 else {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
            return renderer.image { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: W, height: H))
            }
        }

        var pixelPoints = [CGPoint]()
        for pt in t.perimeter {
            let sx = CGFloat(Self.T.x(pt.x)), sz = CGFloat(Self.T.z(pt.y))
            let u = (sx - CGFloat(minX)) / CGFloat(rangeX)
            let vNorm = (sz - CGFloat(minZ)) / CGFloat(rangeZ)
            let v: CGFloat
            let py: CGFloat
            if vFlip {
                v = 1 - vNorm
                py = v * CGFloat(H - 1)
            } else {
                v = vNorm
                py = (1 - v) * CGFloat(H - 1)
            }
            let px = u * CGFloat(W - 1)
            pixelPoints.append(CGPoint(x: px, y: py))
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H))
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
            guard pixelPoints.count >= 3 else { return }
            let path = UIBezierPath()
            path.move(to: pixelPoints[0])
            for i in 1..<pixelPoints.count {
                path.addLine(to: pixelPoints[i])
            }
            path.close()
            path.usesEvenOddFillRule = true
            cg.setFillColor(UIColor.white.cgColor)
            path.fill()
        }
        return image
    }

    private func buildPerimeterLineNode(exag: Float) -> SCNNode {
        let t = terrain
        guard t.perimeter.count >= 2 else { return SCNNode() }

        var positions = [SCNVector3]()
        let yOffset: Float = 0.02  // Slightly above surface to avoid z-fighting
        for pt in t.perimeter {
            let h = (t.interpolatedHeight(atX: Float(pt.x), z: Float(pt.y)) ?? 0) * exag + yOffset
            positions.append(SCNVector3(Self.T.x(pt.x), h, Self.T.z(pt.y)))
        }

        var indices = [Int32]()
        for i in 0..<(positions.count - 1) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        if positions.count >= 3 {
            indices.append(Int32(positions.count - 1))
            indices.append(0)
        }

        let geo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
        )
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.cyan
        mat.emission.contents = UIColor.cyan
        mat.isDoubleSided = true
        geo.materials = [mat]

        let node = SCNNode(geometry: geo)
        node.name = "perimeterLine"
        return node
    }

    // MARK: - Grid Mesh (strict measured raster, fast vertex colors)

    private func buildGridMesh(exag: Float) -> SCNGeometry {
        var t = terrain
        let rows = t.rows, cols = t.cols

        var positions = [SCNVector3]()
        positions.reserveCapacity(rows * cols)
        var normals = [SCNVector3]()
        normals.reserveCapacity(rows * cols)
        var uvs = [CGPoint]()
        uvs.reserveCapacity(rows * cols)

        let filled = t.filledHeights
        for r in 0..<rows {
            for c in 0..<cols {
                let wx = t.worldX(col: c)
                let wz = t.worldZ(row: r)
                let rawH = filled[r][c]
                let h = rawH * exag
                positions.append(SCNVector3(Self.T.x(Double(wx)), h, Self.T.z(Double(wz))))
                uvs.append(CGPoint(x: CGFloat(c) / CGFloat(cols - 1),
                                   y: 1.0 - CGFloat(r) / CGFloat(rows - 1)))
                normals.append(computeNormal(row: r, col: c, exag: exag, filled: filled))
            }
        }

        var indices = [Int32]()
        indices.reserveCapacity((rows - 1) * (cols - 1) * 6)

        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let tl = Int32(r * cols + c)
                let tr = Int32(r * cols + c + 1)
                let bl = Int32((r + 1) * cols + c)
                let br = Int32((r + 1) * cols + c + 1)
                indices.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }

        guard !indices.isEmpty else {
            return SCNBox(width: 1, height: 0.1, length: 1, chamferRadius: 0)
        }

        let minX = positions.map(\.x).min() ?? 0
        let maxX = positions.map(\.x).max() ?? 0
        let minZ = positions.map(\.z).min() ?? 0
        let maxZ = positions.map(\.z).max() ?? 0

        if Self.debugShowMask, !t.perimeter.isEmpty {
            let px = t.perimeter.map(\.x)
            let pz = t.perimeter.map(\.y)
            let pMinX = px.min() ?? 0, pMaxX = px.max() ?? 0
            let pMinZ = pz.min() ?? 0, pMaxZ = pz.max() ?? 0
            print("[mask] perimeter bbox x:\(pMinX)..\(pMaxX) z:\(pMinZ)..\(pMaxZ) | mesh bbox x:\(minX)..\(maxX) z:\(minZ)..\(maxZ)")
        }

        let geo = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )

        let mat = SCNMaterial()
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.diffuse.mipFilter = .linear
        mat.diffuse.minificationFilter = .linear
        mat.diffuse.magnificationFilter = .linear
        mat.lightingModel = .physicallyBased
        mat.roughness.contents = 0.65
        mat.isDoubleSided = true
        mat.readsFromDepthBuffer = true

        // Perimeter mask: bounds from actual vertex positions (matches UVs)
        let maskRes = 512
        let edgeMask = buildPerimeterMaskImage(
            width: maskRes, height: maskRes,
            minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ,
            vFlip: Self.maskVFlip
        )

        if Self.debugShowMask {
            mat.diffuse.contents = edgeMask
            // No shader — mask as diffuse to verify alignment
        } else if Self.enableEdgeClip {
            mat.diffuse.contents = buildHeatmapTextureFast()
            mat.setValue(SCNMaterialProperty(contents: edgeMask), forKey: "edgeMask")
            mat.shaderModifiers = [.fragment: Self.fragmentMaskShader]
        } else {
            mat.diffuse.contents = buildHeatmapTextureFast()
        }

        geo.materials = [mat]
        return geo
    }

    private func computeNormal(row r: Int, col c: Int, exag: Float, filled: [[Float]]) -> SCNVector3 {
        let t = terrain
        let cs = t.cellSize
        let hC = filled[r][c]
        let hL = (c > 0) ? filled[r][c - 1] : hC
        let hR = (c < t.cols - 1) ? filled[r][c + 1] : hC
        let hU = (r > 0) ? filled[r - 1][c] : hC
        let hD = (r < t.rows - 1) ? filled[r + 1][c] : hC
        let dhdx = (hR - hL) / (2 * cs) * exag
        let dhdz = -(hD - hU) / (2 * cs) * exag
        return SCNVector3(-dhdx, 1, -dhdz).normalized()
    }

    private func buildHeatmapTextureFast() -> UIImage {
        let t = terrain
        // Moderate resolution for smoothness without heavy cost.
        let texW = 512
        let texH = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: texW, height: texH))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Never use transparent texels; transparency can make the mesh appear "missing".
            cg.setFillColor(Self.heatmapColor(0.0).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: texW, height: texH))
            // Surface grid spacing in texture pixels.
            let gridStep = 10

            for py in 0..<texH {
                // Map texture row -> grid row (float)
                let rowF = Float(py) / Float(texH - 1) * Float(t.rows - 1)
                let r0 = Int(rowF)
                for px in 0..<texW {
                    let colF = Float(px) / Float(texW - 1) * Float(t.cols - 1)
                    let c0 = Int(colF)
                    let color: UIColor
                    if t.isValid(row: r0, col: c0),
                       let h = t.interpolatedHeightGrid(atRow: rowF, col: colF) {
                        let norm = t.elevationRange > 0 ? min(1, max(0, Double(h / t.elevationRange))) : 0.5
                        color = Self.heatmapColor(norm)
                    } else {
                        color = UIColor(white: 0.25, alpha: 1)
                    }

                    // Subtle grid overlay: ~0.5px visual thickness (alternating pixels), 40% opacity.
                    let onGridLine = (px % gridStep == 0 || py % gridStep == 0)
                    let thinLine = (px + py) % 2 == 0
                    if onGridLine && thinLine {
                        let gridColor = Self.blendWhite(color, amount: 0.4)
                        cg.setFillColor(gridColor.cgColor)
                    } else {
                        cg.setFillColor(color.cgColor)
                    }
                    // Flip Y to match mesh UVs (V is inverted in geometry setup).
                    cg.fill(CGRect(x: px, y: (texH - 1 - py), width: 1, height: 1))
                }
            }
        }
    }

    private static func blendWhite(_ base: UIColor, amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: r + (1 - r) * amount,
            green: g + (1 - g) * amount,
            blue: b + (1 - b) * amount,
            alpha: a
        )
    }

    static func heatmapColor(_ v: Double) -> UIColor {
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
                lo = stops[i]; hi = stops[i + 1]; break
            }
        }

        let f = hi.pos > lo.pos ? CGFloat((clamped - lo.pos) / (hi.pos - lo.pos)) : 0
        return UIColor(
            red: lo.r + (hi.r - lo.r) * f,
            green: lo.g + (hi.g - lo.g) * f,
            blue: lo.b + (hi.b - lo.b) * f,
            alpha: 1
        )
    }

    // MARK: - Cake Sides (smooth GeoJSON perimeter, light gray)

    private func buildCakeSides(exag: Float) -> SCNGeometry {
        let peri = terrain.perimeter
        guard peri.count >= 3 else { return SCNGeometry() }

        let baseY: Float = -2.0
        var verts = [SCNVector3]()
        var norms = [SCNVector3]()

        for i in 0..<peri.count {
            let p1 = peri[i]
            let p2 = peri[(i + 1) % peri.count]
            let h1 = (terrain.interpolatedHeight(atX: Float(p1.x), z: Float(p1.y)) ?? 0) * exag
            let h2 = (terrain.interpolatedHeight(atX: Float(p2.x), z: Float(p2.y)) ?? 0) * exag

            let v1 = SCNVector3(Self.T.x(p1.x), h1, Self.T.z(p1.y))
            let v2 = SCNVector3(Self.T.x(p2.x), h2, Self.T.z(p2.y))
            let v3 = SCNVector3(Self.T.x(p1.x), baseY, Self.T.z(p1.y))
            let v4 = SCNVector3(Self.T.x(p2.x), baseY, Self.T.z(p2.y))
            verts.append(contentsOf: [v1, v3, v2, v2, v3, v4])

            let edge = SCNVector3(Self.T.x(p2.x) - Self.T.x(p1.x), 0, Self.T.z(p2.y) - Self.T.z(p1.y))
            let n = edge.cross(SCNVector3(0, 1, 0)).normalized()
            for _ in 0..<6 { norms.append(n) }
        }

        guard !verts.isEmpty else { return SCNGeometry() }

        let idx = (0..<Int32(verts.count)).map { $0 }
        let geo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)]
        )

        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.45, green: 0.32, blue: 0.18, alpha: 1.0)
        mat.lightingModel = .lambert
        mat.isDoubleSided = true
        geo.materials = [mat]
        return geo
    }

    // MARK: - Slope Arrows (black, interior cells only)

    private func buildArrows(parent: SCNNode, exag: Float) {
        let t = terrain
        // Heavier smoothing for macro slope, closer to 18Birdies look.
        let smoothed = t.smoothedHeights(radius: 4)
        let arrowTex = buildArrowTexture()
        let cs = t.cellSize
        let step = 5
        let margin = 4

        for r in stride(from: step, to: t.rows - step, by: step) {
            for c in stride(from: step, to: t.cols - step, by: step) {
                guard t.isInterior(row: r, col: c, margin: margin) else { continue }

                let dhdx = (smoothed[r][c + 1] - smoothed[r][c - 1]) / (2 * cs)
                let dhdr = (smoothed[r + 1][c] - smoothed[r - 1][c]) / (2 * cs)
                let dhdz = -dhdr

                let mag = sqrt(dhdx * dhdx + dhdz * dhdz)
                guard mag > 0.003 else { continue }

                let wx = t.worldX(col: c)
                let wz = t.worldZ(row: r)
                let wy = t.height(row: r, col: c) * exag + 0.03

                let arrow = SCNNode(geometry: SCNPlane(width: 0.6, height: 0.6))
                let mat = arrow.geometry!.firstMaterial!
                mat.diffuse.contents = arrowTex
                mat.lightingModel = .constant
                mat.isDoubleSided = true
                mat.writesToDepthBuffer = true
                arrow.position = SCNVector3(wx, wy, wz)
                // Arrow lies on horizontal plane: heading is yaw (Y-axis) along steepest descent.
                let downhillX = -dhdx
                let downhillZ = -dhdz
                let yaw = atan2(downhillX, downhillZ)
                arrow.eulerAngles = SCNVector3(-Float.pi / 2, yaw, 0)
                parent.addChildNode(arrow)
            }
        }
    }

    private func buildArrowTexture() -> UIImage {
        let s: CGFloat = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        return renderer.image { _ in
            UIColor.black.withAlphaComponent(0.8).setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 64, y: 16))
            path.addLine(to: CGPoint(x: 38, y: 60))
            path.addLine(to: CGPoint(x: 52, y: 60))
            path.addLine(to: CGPoint(x: 52, y: 104))
            path.addLine(to: CGPoint(x: 76, y: 104))
            path.addLine(to: CGPoint(x: 76, y: 60))
            path.addLine(to: CGPoint(x: 90, y: 60))
            path.close()
            path.fill()
        }
    }

    // MARK: - Grid Floor

    private func buildGridFloor() -> SCNNode {
        let floorSize: CGFloat = 120
        let plane = SCNPlane(width: floorSize, height: floorSize)

        let texSize: CGFloat = 512
        let gridStep: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: texSize, height: texSize))
        let gridTex = renderer.image { ctx in
            UIColor(white: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: texSize, height: texSize))
            UIColor(white: 0.24, alpha: 1).setStroke()
            for i in stride(from: CGFloat(0), through: texSize, by: gridStep) {
                let h = UIBezierPath()
                h.move(to: CGPoint(x: 0, y: i))
                h.addLine(to: CGPoint(x: texSize, y: i))
                h.lineWidth = 1
                h.stroke()
                let v = UIBezierPath()
                v.move(to: CGPoint(x: i, y: 0))
                v.addLine(to: CGPoint(x: i, y: texSize))
                v.lineWidth = 1
                v.stroke()
            }
        }

        let mat = SCNMaterial()
        mat.diffuse.contents = gridTex
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.lightingModel = .constant
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position.y = -2.0
        return node
    }

    // MARK: - Front / Back Labels

    private func buildLabels(parent: SCNNode, exag: Float) {
        let peri = terrain.perimeter
        guard !peri.isEmpty else { return }

        let minZpt = peri.min(by: { $0.y < $1.y })!
        let maxZpt = peri.max(by: { $0.y < $1.y })!

        let frontH = (terrain.interpolatedHeight(atX: Float(minZpt.x), z: Float(minZpt.y)) ?? 0) * exag
        let backH = (terrain.interpolatedHeight(atX: Float(maxZpt.x), z: Float(maxZpt.y)) ?? 0) * exag

        func makeLabel(_ text: String) -> SCNNode {
            let txt = SCNText(string: text, extrusionDepth: 0.05)
            txt.font = UIFont.systemFont(ofSize: 1.0, weight: .heavy)
            txt.flatness = 0.1
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.white.withAlphaComponent(0.9)
            mat.lightingModel = .constant
            txt.materials = [mat]

            let node = SCNNode(geometry: txt)
            let (mn, mx) = node.boundingBox
            let cx = (mx.x - mn.x) / 2 + mn.x
            let cz = (mx.z - mn.z) / 2 + mn.z
            node.pivot = SCNMatrix4MakeTranslation(cx, 0, cz)
            return node
        }

        let frontNode = makeLabel("Front")
        frontNode.position = SCNVector3(Float(minZpt.x), frontH + 0.12, Float(minZpt.y) - 1.8)
        frontNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        parent.addChildNode(frontNode)

        let backNode = makeLabel("Back")
        backNode.position = SCNVector3(Float(maxZpt.x), backH + 0.12, Float(maxZpt.y) + 1.8)
        backNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        parent.addChildNode(backNode)
    }
}
