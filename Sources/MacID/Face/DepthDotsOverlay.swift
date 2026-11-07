import SwiftUI

/// Draws the "depth sensor" look over the camera preview: a field of dots projected
/// onto the face, sized and colored by estimated depth (nearest at the nose tip),
/// a sweeping scan line, and the Vision landmarks as brighter points.
struct DepthDotsOverlay: View {
  let sample: FaceSample?
  let imageSize: CGSize
  var mirrored = true
  var matched = false
  var scanning = true

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !scanning && !matched)) { context in
      Canvas { ctx, size in
        guard let sample else { return }
        let t = context.date.timeIntervalSinceReferenceDate
        draw(sample, in: &ctx, size: size, time: t)
      }
    }
    .allowsHitTesting(false)
  }

  private func point(_ p: CGPoint, _ view: CGSize) -> CGPoint {
    let scale = max(view.width / max(imageSize.width, 1), view.height / max(imageSize.height, 1))
    let w = imageSize.width * scale, h = imageSize.height * scale
    let ox = (view.width - w) / 2, oy = (view.height - h) / 2
    let x = mirrored ? (1 - p.x) : p.x
    return CGPoint(x: ox + x * w, y: oy + (1 - p.y) * h)
  }

  private func draw(_ s: FaceSample, in ctx: inout GraphicsContext, size: CGSize, time: Double) {
    let tl = point(CGPoint(x: s.box.minX, y: s.box.maxY), size)
    let br = point(CGPoint(x: s.box.maxX, y: s.box.minY), size)
    let rect = CGRect(x: min(tl.x, br.x), y: min(tl.y, br.y), width: abs(br.x - tl.x), height: abs(br.y - tl.y))
    guard rect.width > 10 else { return }
    let nose = point(s.noseTip, size)
    let ir = Color(red: 1.0, green: 0.30, blue: 0.43)
    let amber = Color(red: 1.0, green: 0.70, blue: 0.36)
    let ok = Color(red: 0.25, green: 0.85, blue: 0.65)
    let scanY = rect.minY + rect.height * CGFloat((sin(time * 1.8) + 1) / 2)

    // Dot grid inside the face ellipse (pseudo-random jitter like a dot projector pattern).
    let step = max(4.0, rect.width / 34)
    let cx = rect.midX, cy = rect.midY, rx = rect.width * 0.52, ry = rect.height * 0.62
    var row = 0
    var y = rect.minY - rect.height * 0.12
    while y < rect.maxY + rect.height * 0.05 {
      var x = rect.minX - rect.width * 0.05 + (row.isMultiple(of: 2) ? 0 : step / 2)
      while x < rect.maxX + rect.width * 0.05 {
        let jx = CGFloat(hash(row, Int(x))) * step * 0.35
        let jy = CGFloat(hash(Int(x), row)) * step * 0.35
        let p = CGPoint(x: x + jx, y: y + jy)
        let nx = (p.x - cx) / rx, ny = (p.y - cy) / ry
        let r2 = nx * nx + ny * ny
        if r2 < 1 {
          let dn = hypot(p.x - nose.x, p.y - nose.y) / max(rx, 1)
          let depth = max(0, 1 - dn * 0.9) * (1 - r2 * 0.5)          // 1 = nearest
          let near = abs(p.y - scanY) < step * 1.2
          let radius = (0.8 + depth * 1.6) * (near ? 1.6 : 1.0)
          let color: Color = matched ? ok : (depth > 0.65 ? amber : ir)
          let alpha = (0.35 + depth * 0.55) * (near ? 1.0 : 0.8)
          ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(color.opacity(alpha)))
        }
        x += step
      }
      y += step * 0.87
      row += 1
    }

    // Landmarks
    for lp in s.points {
      let p = point(lp, size)
      ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)), with: .color(.white.opacity(0.85)))
    }

    // Scan line
    if scanning && !matched {
      var line = Path()
      line.move(to: CGPoint(x: rect.minX - 8, y: scanY))
      line.addLine(to: CGPoint(x: rect.maxX + 8, y: scanY))
      ctx.stroke(line, with: .color(ir.opacity(0.85)), lineWidth: 1.5)
    }
  }

  /// Deterministic jitter in -0.5...0.5 so the pattern does not shimmer frame to frame.
  private func hash(_ a: Int, _ b: Int) -> Double {
    var h = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663))
    h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33
    return Double(h % 1000) / 1000.0 - 0.5
  }
}
