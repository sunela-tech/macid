import Foundation
import Vision

/// The enrolled face: appearance embeddings plus landmark geometry, with the spread
/// measured across the user's own enrollment frames so thresholds calibrate themselves.
struct EnrolledFace: Codable {
  var prints: [Data]
  var geometry: [[Float]]
  var printSelfMax: Float
  var geometrySelfMax: Float
  var createdAt: Date
}

struct MatchVerdict {
  let printDistance: Float
  let geometryDistance: Float
  let passed: Bool
  /// 0...1, for display.
  let score: Double
}

final class FaceMatcher {
  let enrolled: EnrolledFace
  private let prints: [VNFeaturePrintObservation]

  init(_ enrolled: EnrolledFace) {
    self.enrolled = enrolled
    self.prints = enrolled.prints.compactMap(Self.unarchive)
  }

  /// Higher strictness (0...1) means tighter thresholds.
  func evaluate(_ sample: FaceSample, strictness: Double) -> MatchVerdict? {
    guard let fp = sample.featurePrint, !prints.isEmpty else { return nil }
    let pDist = prints.compactMap { Self.distance(fp, $0) }.min() ?? .infinity
    let gDist = enrolled.geometry.map { Self.rms($0, sample.geometry) }.min() ?? .infinity
    let slack = Float(1.15 + 0.85 * (1 - min(max(strictness, 0), 1)))
    let pThreshold = max(enrolled.printSelfMax, 0.02) * slack
    let gThreshold = max(enrolled.geometrySelfMax, 0.01) * slack * 1.25
    let passed = pDist <= pThreshold && gDist <= gThreshold
    let score = Double(max(0, min(1, 1 - (pDist / (pThreshold * 2)))))
    return MatchVerdict(printDistance: pDist, geometryDistance: gDist, passed: passed, score: score)
  }

  // MARK: - Enrollment

  /// Builds an enrollment from near-frontal samples. Needs at least 5 usable frames.
  static func enroll(from samples: [FaceSample]) -> EnrolledFace? {
    let usable = samples.filter { $0.featurePrint != nil && abs($0.yaw) < 0.4 }
    guard usable.count >= 5 else { return nil }
    let picked = Array(usable.prefix(12))
    let fps = picked.compactMap(\.featurePrint)

    var printDists: [Float] = []
    var geoDists: [Float] = []
    for i in picked.indices {
      for j in picked.indices where j > i {
        if let d = distance(fps[i], fps[j]) { printDists.append(d) }
        geoDists.append(rms(picked[i].geometry, picked[j].geometry))
      }
    }
    return EnrolledFace(
      prints: fps.compactMap(archive),
      geometry: picked.map(\.geometry),
      printSelfMax: percentile(printDists, 0.9),
      geometrySelfMax: percentile(geoDists, 0.9),
      createdAt: Date()
    )
  }

  // MARK: - Helpers

  static func archive(_ p: VNFeaturePrintObservation) -> Data? {
    try? NSKeyedArchiver.archivedData(withRootObject: p, requiringSecureCoding: true)
  }

  static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
    try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
  }

  static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
    var d: Float = 0
    do {
      try a.computeDistance(&d, to: b)
      return d
    } catch {
      return nil
    }
  }

  static func rms(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return .infinity }
    var sum: Float = 0
    for i in a.indices { let d = a[i] - b[i]; sum += d * d }
    return (sum / Float(a.count)).squareRoot()
  }

  private static func percentile(_ values: [Float], _ p: Double) -> Float {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * p))
    return sorted[index]
  }
}
