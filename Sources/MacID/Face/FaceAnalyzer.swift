import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// One analyzed camera frame.
struct FaceSample {
  /// Face box in Vision-normalized image coordinates (origin bottom-left).
  let box: CGRect
  /// Every landmark point, normalized to the image (origin bottom-left).
  let points: [CGPoint]
  /// Nose tip estimate, normalized to the image. Drives the depth-dot overlay.
  let noseTip: CGPoint
  let yaw: Double
  let roll: Double
  /// Average eye height / width; drops sharply during a blink.
  let eyeOpenness: Double
  /// Roll-normalized landmark ratios (scale free).
  let geometry: [Float]
  /// Appearance embedding of the grayscale face crop. Only computed while scanning.
  let featurePrint: VNFeaturePrintObservation?
  let time: TimeInterval
}

enum FaceAnalyzer {
  static func analyze(_ buffer: CVPixelBuffer, wantPrint: Bool, time: TimeInterval) -> FaceSample? {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
    do { try handler.perform([request]) } catch { return nil }

    guard
      let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
      face.boundingBox.width > 0.08,
      let landmarks = face.landmarks,
      let all = landmarks.allPoints
    else { return nil }

    let box = face.boundingBox
    let width = Float(CVPixelBufferGetWidth(buffer))
    let height = Float(CVPixelBufferGetHeight(buffer))

    func toImage(_ p: CGPoint) -> CGPoint {
      CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
    }
    // Pixel-space points so x and y share one unit.
    func pixels(_ region: VNFaceLandmarkRegion2D?) -> [SIMD2<Float>] {
      guard let region, region.pointCount > 0 else { return [] }
      return region.normalizedPoints.map { p in
        let q = toImage(p)
        return SIMD2(Float(q.x) * width, Float(q.y) * height)
      }
    }
    func center(_ pts: [SIMD2<Float>]) -> SIMD2<Float>? {
      guard !pts.isEmpty else { return nil }
      return pts.reduce(SIMD2<Float>(0, 0), +) / Float(pts.count)
    }

    let leftEye = pixels(landmarks.leftEye), rightEye = pixels(landmarks.rightEye)
    let leftBrow = pixels(landmarks.leftEyebrow), rightBrow = pixels(landmarks.rightEyebrow)
    let nose = pixels(landmarks.nose), lips = pixels(landmarks.outerLips), contour = pixels(landmarks.faceContour)
    let crest = pixels(landmarks.noseCrest)

    guard
      let le = center(leftEye), let re = center(rightEye),
      let nc = center(nose), let mc = center(lips)
    else { return nil }

    let eyeVec = re - le
    let iod = (eyeVec * eyeVec).sum().squareRoot()
    guard iod > 8 else { return nil }
    let ex = eyeVec / iod
    let ey = SIMD2<Float>(-ex.y, ex.x)
    let mid = (le + re) / 2

    func along(_ v: SIMD2<Float>) -> Float { (v * ex).sum() / iod }
    func across(_ v: SIMD2<Float>) -> Float { (v * ey).sum() / iod }
    func extentAlong(_ pts: [SIMD2<Float>]) -> Float {
      let xs = pts.map { along($0 - mid) }
      return (xs.max() ?? 0) - (xs.min() ?? 0)
    }
    func extentAcross(_ pts: [SIMD2<Float>]) -> Float {
      let ys = pts.map { across($0 - mid) }
      return (ys.max() ?? 0) - (ys.min() ?? 0)
    }

    let chinDrop = contour.map { across($0 - mid) }.min() ?? 0
    let geometry: [Float] = [
      across(nc - mid),
      across(mc - mid),
      extentAlong(lips),
      extentAlong(nose),
      extentAlong(contour),
      chinDrop,
      center(leftBrow).map { across($0 - le) } ?? 0,
      center(rightBrow).map { across($0 - re) } ?? 0,
      (extentAlong(leftEye) + extentAlong(rightEye)) / 2,
      across(mc - nc),
    ]

    func openness(_ eye: [SIMD2<Float>]) -> Double {
      let w = extentAlong(eye)
      return w > 0 ? Double(extentAcross(eye) / w) : 0
    }

    // Nose tip: lowest point of the nose crest, else the nose center.
    let tipPixel = crest.min(by: { across($0 - mid) < across($1 - mid) }) ?? nc
    let noseTip = CGPoint(x: CGFloat(tipPixel.x / width), y: CGFloat(tipPixel.y / height))

    var featurePrint: VNFeaturePrintObservation?
    if wantPrint, let crop = CameraService.faceCrop(from: buffer, box: box) {
      let fp = VNGenerateImageFeaturePrintRequest()
      let cropHandler = VNImageRequestHandler(cgImage: crop, options: [:])
      if (try? cropHandler.perform([fp])) != nil { featurePrint = fp.results?.first }
    }

    return FaceSample(
      box: box,
      points: all.normalizedPoints.map(toImage),
      noseTip: noseTip,
      yaw: face.yaw?.doubleValue ?? 0,
      roll: face.roll?.doubleValue ?? 0,
      eyeOpenness: (openness(leftEye) + openness(rightEye)) / 2,
      geometry: geometry,
      featurePrint: featurePrint,
      time: time
    )
  }
}

/// Looks for signs of a live face across frames: a blink or a small head turn.
/// A printed photo held still shows neither. A screen playing a video of the user
/// can still pass, so this is a deterrent, not a guarantee.
struct LivenessTracker {
  private(set) var openness: [Double] = []
  private(set) var yaws: [Double] = []
  private(set) var rolls: [Double] = []

  mutating func add(_ s: FaceSample) {
    openness.append(s.eyeOpenness); yaws.append(s.yaw); rolls.append(s.roll)
  }

  var blinked: Bool {
    guard openness.count >= 4 else { return false }
    let sorted = openness.sorted()
    let median = sorted[sorted.count / 2]
    guard median > 0.12 else { return false }
    guard let low = openness.firstIndex(where: { $0 < median * 0.55 }) else { return false }
    return openness[(low + 1)...].contains(where: { $0 > median * 0.8 })
  }

  var moved: Bool {
    func range(_ a: [Double]) -> Double { (a.max() ?? 0) - (a.min() ?? 0) }
    return range(yaws) > 0.07 || range(rolls) > 0.07
  }

  var isLive: Bool { blinked || moved }
}
