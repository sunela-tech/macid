import Foundation
import simd

/// Compares two Meshy head meshes (OBJ) by shape.
///
/// Both models are centered, scaled to unit RMS radius, and compared with a symmetric
/// chamfer distance over a few small yaw offsets. Meshy outputs are Y-up and face +Z,
/// so no full alignment is needed. Generated heads of different people are still
/// fairly similar at this level, so treat the score as a consistency check.
enum MeshCompare {
  static func vertices(fromOBJ url: URL, maxPoints: Int = 2500) throws -> [SIMD3<Float>] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var points: [SIMD3<Float>] = []
    points.reserveCapacity(60_000)
    for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("v ") {
      let parts = line.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) else { continue }
      points.append(SIMD3(x, y, z))
    }
    guard points.count > maxPoints else { return points }
    let stride = Double(points.count) / Double(maxPoints)
    return (0 ..< maxPoints).map { points[min(points.count - 1, Int(Double($0) * stride))] }
  }

  static func normalized(_ pts: [SIMD3<Float>]) -> [SIMD3<Float>] {
    guard !pts.isEmpty else { return [] }
    let c = pts.reduce(SIMD3<Float>(repeating: 0), +) / Float(pts.count)
    let centered = pts.map { $0 - c }
    let rms = (centered.reduce(Float(0)) { $0 + simd_length_squared($1) } / Float(pts.count)).squareRoot()
    guard rms > 0 else { return centered }
    return centered.map { $0 / rms }
  }

  /// 0...1 similarity between two OBJ meshes (1 = identical shape).
  static func similarity(objA: URL, objB: URL) throws -> Double {
    let a = normalized(try vertices(fromOBJ: objA))
    let b = normalized(try vertices(fromOBJ: objB))
    guard a.count > 50, b.count > 50 else { return 0 }
    var best = Float.infinity
    for degrees in stride(from: -20.0, through: 20.0, by: 5.0) {
      let r = Float(degrees * .pi / 180)
      let rot = simd_float3x3(simd_quatf(angle: r, axis: SIMD3(0, 1, 0)))
      let ra = a.map { rot * $0 }
      best = min(best, (meanNearest(ra, b) + meanNearest(b, ra)) / 2)
    }
    // Chamfer distance of ~0.03 is a near-identical shape; ~0.25 is clearly different.
    return Double(exp(-best / 0.09))
  }

  private static func meanNearest(_ from: [SIMD3<Float>], _ to: [SIMD3<Float>]) -> Float {
    var total: Float = 0
    for p in from {
      var nearest = Float.infinity
      for q in to {
        let d = simd_distance_squared(p, q)
        if d < nearest { nearest = d }
      }
      total += nearest.squareRoot()
    }
    return total / Float(from.count)
  }
}
