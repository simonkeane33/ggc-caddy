import Foundation
import CoreLocation
import GreystonesCaddyCore

/// Per-hole course features captured from Google Earth via the QGIS pipeline —
/// the fairway perimeter and any bunker perimeters. Loaded from a bundled
/// GeoJSON asset (`H{NN}_features.geojson`, EPSG:4326) the same way green
/// terrain loads from `H{NN}_green_data.json` — see `GreenTerrainData.load`.
///
/// v1 uses this geometry for two things: defaulting the drag target onto the
/// fairway, and surfacing bunker carry distances in the map UI. The polygons
/// are **not** drawn over the imagery. Holes without an asset return `nil` and
/// the app falls back to its existing tee↔green midpoint behaviour.
struct HoleFeatures {
    let hole: Int
    let fairway: HolePolygon?
    let bunkers: [HolePolygon]

    static func load(hole: Int) -> HoleFeatures? {
        let name = String(format: "H%02d_features", hole)
        guard let url = Bundle.main.url(forResource: name, withExtension: "geojson") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = json["features"] as? [[String: Any]] else {
                return nil
            }
            return parse(hole: hole, features: features)
        } catch {
            print("[HoleFeatures] Failed to load \(name).geojson: \(error)")
            return nil
        }
    }

    private static func parse(hole: Int, features: [[String: Any]]) -> HoleFeatures? {
        var fairway: HolePolygon? = nil
        var bunkers: [HolePolygon] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  type == "Polygon",
                  let rings = geometry["coordinates"] as? [[[Double]]],
                  let ring = rings.first else { continue }

            let coords = ring.compactMap { pos -> CLLocationCoordinate2D? in
                guard pos.count >= 2 else { return nil }
                // GeoJSON positions are [longitude, latitude].
                return CLLocationCoordinate2D(latitude: pos[1], longitude: pos[0])
            }
            guard coords.count >= 3 else { continue }
            let polygon = HolePolygon(ring: coords)

            // Identify the feature. A `featureType` property wins; otherwise
            // derive from the `name` so the user's Google Earth layer naming
            // flows through with no extra attribute authoring.
            let properties = (feature["properties"] as? [String: Any]) ?? [:]
            let featureType = (properties["featureType"] as? String) ?? ""
            let nameStr = ((properties["name"] as? String) ?? "").lowercased()
            let kind = featureType.lowercased()
            let isFairway = kind.contains("fairway") || nameStr.contains("fairway")
            let isBunker = kind.contains("bunker") || nameStr.contains("bunker")

            if isFairway {
                fairway = polygon
            } else if isBunker {
                bunkers.append(polygon)
            }
        }
        guard fairway != nil || !bunkers.isEmpty else { return nil }
        return HoleFeatures(hole: hole, fairway: fairway, bunkers: bunkers)
    }

    // MARK: - Fairway default target

    /// A sensible default target on the fairway, replacing the bare tee↔green
    /// midpoint. Strategy: walk the tee→green line in fine steps and pick the
    /// point **inside** the fairway that is farthest toward the green — i.e.
    /// the far edge of the landing zone ("aim to the end of the fairway"). If
    /// the line misses the fairway entirely, fall back to the fairway centroid.
    /// Returns `nil` when there is no fairway data (caller keeps today's
    /// midpoint behaviour).
    func defaultTarget(tee: CLLocationCoordinate2D, green: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        guard let fairway else { return nil }
        let steps = 60
        var best: CLLocationCoordinate2D? = nil
        var bestT = -1.0
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let p = CLLocationCoordinate2D(
                latitude: tee.latitude + (green.latitude - tee.latitude) * t,
                longitude: tee.longitude + (green.longitude - tee.longitude) * t
            )
            if fairway.contains(p), t > bestT {
                bestT = t
                best = p
            }
        }
        return best ?? fairway.centroid
    }

    // MARK: - Bunkers

    /// The bunker whose front edge is reached first along the line of play —
    /// the one a carry read-out is most useful for. Returns `nil` when there
    /// are no bunkers ahead of the tee.
    func nearestBunkerFront(tee: CLLocationCoordinate2D, green: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        guard !bunkers.isEmpty else { return nil }
        var best: CLLocationCoordinate2D? = nil
        var bestTrack = Double.infinity
        for bunker in bunkers {
            let edges = bunkerEdges(bunker, tee: tee, green: green)
            let track = alongTrack(from: tee, to: edges.front, bearingTeeToGreen: bearing(tee, green))
            if track > 0 && track < bestTrack {
                bestTrack = track
                best = edges.front
            }
        }
        return best
    }
}

/// A closed polygon ring in WGS84 lat/lng.
struct HolePolygon {
    let ring: [CLLocationCoordinate2D]

    /// Area-weighted centroid (shoelace). Falls back to the vertex mean for
    /// degenerate (near-zero-area) rings.
    var centroid: CLLocationCoordinate2D {
        let pts = openRing
        guard pts.count >= 3 else {
            return mean(pts)
        }
        var area = 0.0
        var cx = 0.0
        var cy = 0.0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            let cross = a.longitude * b.latitude - b.longitude * a.latitude
            area += cross
            cx += (a.longitude + b.longitude) * cross
            cy += (a.latitude + b.latitude) * cross
        }
        area *= 0.5
        if abs(area) < 1e-12 {
            return mean(pts)
        }
        return CLLocationCoordinate2D(latitude: cy / (6.0 * area), longitude: cx / (6.0 * area))
    }

    /// Point-in-polygon via ray casting in the lat/lng plane. Safe for the
    /// small areas a golf hole spans (no antimeridian / pole concerns).
    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        let pts = openRing
        guard pts.count >= 3 else { return false }
        var inside = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let pi = pts[i]
            let pj = pts[j]
            if ((pi.latitude > c.latitude) != (pj.latitude > c.latitude)) {
                let xIntersect = (pj.longitude - pi.longitude) * (c.latitude - pi.latitude)
                    / (pj.latitude - pi.latitude) + pi.longitude
                if c.longitude < xIntersect {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }

    /// The ring with a repeated closing vertex dropped, if present.
    private var openRing: [CLLocationCoordinate2D] {
        guard let first = ring.first, let last = ring.last,
              first.latitude == last.latitude, first.longitude == last.longitude,
              ring.count > 3 else { return ring }
        return Array(ring.dropLast())
    }

    private func mean(_ pts: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !pts.isEmpty else { return .init(latitude: 0, longitude: 0) }
        let lat = pts.reduce(0.0) { $0 + $1.latitude } / Double(pts.count)
        let lng = pts.reduce(0.0) { $0 + $1.longitude } / Double(pts.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// Derived reference points on a bunker relative to the line of play.
struct BunkerEdges {
    let front: CLLocationCoordinate2D   // near edge along tee→green
    let middle: CLLocationCoordinate2D  // centroid
    let back: CLLocationCoordinate2D    // far edge along tee→green
}

/// Bunker front/middle/back from its perimeter: project each vertex onto the
/// tee→green bearing; the min/max along-track distances are the near/far edges
/// the ball reaches first/last, and the centroid is the middle. This avoids
/// manual 3-point authoring in Google Earth.
func bunkerEdges(_ bunker: HolePolygon, tee: CLLocationCoordinate2D, green: CLLocationCoordinate2D) -> BunkerEdges {
    let bearingTeeToGreen = bearing(tee, green)
    var front = bunker.ring[0]
    var back = bunker.ring[0]
    var minTrack = Double.infinity
    var maxTrack = -Double.infinity
    for v in bunker.ring {
        let track = alongTrack(from: tee, to: v, bearingTeeToGreen: bearingTeeToGreen)
        if track < minTrack { minTrack = track; front = v }
        if track > maxTrack { maxTrack = track; back = v }
    }
    return BunkerEdges(front: front, middle: bunker.centroid, back: back)
}

// MARK: - Local flat-earth projection helpers

private func bearing(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
    Geo.bearingDegrees(lat1: from.latitude, lng1: from.longitude, lat2: to.latitude, lng2: to.longitude)
}

/// Signed distance from `from` toward `to`, projected onto the tee→green
/// bearing. Negative = behind the tee (down the line away from the green).
private func alongTrack(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, bearingTeeToGreen: Double) -> Double {
    let metersPerDegreeLat = 111_320.0
    let metersPerDegreeLon = metersPerDegreeLat * cos(from.latitude * .pi / 180)
    let east = (to.longitude - from.longitude) * metersPerDegreeLon
    let north = (to.latitude - from.latitude) * metersPerDegreeLat
    let theta = bearingTeeToGreen * .pi / 180
    let unitEast = sin(theta)
    let unitNorth = cos(theta)
    return east * unitEast + north * unitNorth
}