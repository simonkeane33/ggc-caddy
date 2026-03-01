import Foundation
import CoreLocation

/// Simple triangulation for convex-ish shapes
public struct Triangulator {
    /// Ear clipping for the green mesh (handles concave shapes)
    public static func triangulate(points: [CGPoint]) -> [Int32] {
        // Remove duplicate adjacent points
        var uniquePoints = [CGPoint]()
        for p in points {
            if let last = uniquePoints.last {
                if abs(p.x - last.x) < 0.0001 && abs(p.y - last.y) < 0.0001 {
                    continue
                }
            }
            uniquePoints.append(p)
        }
        if uniquePoints.count > 1, abs(uniquePoints.first!.x - uniquePoints.last!.x) < 0.0001, abs(uniquePoints.first!.y - uniquePoints.last!.y) < 0.0001 {
            uniquePoints.removeLast()
        }

        guard uniquePoints.count >= 3 else { return [] }
        
        var indices = [Int32]()
        var vertices = uniquePoints
        var vertexIndices = Array(0..<Int32(uniquePoints.count))
        
        // Counter-clockwise check using signed area (Shoelace formula)
        // Area > 0 is CCW in standard Cartesian, but in UIKit/SceneKit Y is often flipped.
        // For SceneKit, CCW winding is usually front-facing.
        var area: CGFloat = 0
        for i in 0..<vertices.count {
            let p1 = vertices[i]
            let p2 = vertices[(i + 1) % vertices.count]
            area += (p1.x * p2.y) - (p2.x * p1.y)
        }
        
        // Ensure CCW winding (area > 0)
        if area < 0 {
            vertices.reverse()
            vertexIndices.reverse()
        }

        var i = 0
        while vertexIndices.count > 3 {
            let count = vertexIndices.count
            let prev = (i + count - 1) % count
            let curr = i % count
            let next = (i + 1) % count
            
            let pPrev = vertices[Int(vertexIndices[prev])]
            let pCurr = vertices[Int(vertexIndices[curr])]
            let pNext = vertices[Int(vertexIndices[next])]
            
            if isEar(pPrev, pCurr, pNext, vertices: vertices, vertexIndices: vertexIndices, ignore: [prev, curr, next]) {
                indices.append(vertexIndices[prev])
                indices.append(vertexIndices[curr])
                indices.append(vertexIndices[next])
                vertexIndices.remove(at: curr)
                i = 0 // Reset to find next ear
            } else {
                i += 1
                if i > count { break } // Should not happen for simple polygons
            }
        }
        
        if vertexIndices.count == 3 {
            indices.append(vertexIndices[0])
            indices.append(vertexIndices[1])
            indices.append(vertexIndices[2])
        }
        
        return indices
    }
    
    private static func isEar(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, vertices: [CGPoint], vertexIndices: [Int32], ignore: [Int]) -> Bool {
        // Must be convex
        let crossProduct = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        if crossProduct <= 0 { return false }
        
        // No other points inside
        for i in 0..<vertexIndices.count {
            if ignore.contains(i) { continue }
            let p = vertices[Int(vertexIndices[i])]
            if isPointInTriangle(p, a, b, c) { return false }
        }
        return true
    }
    
    private static func isPointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let det = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        let alpha = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / det
        let beta = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / det
        let gamma = 1.0 - alpha - beta
        return alpha >= 0 && beta >= 0 && gamma >= 0
    }
}
