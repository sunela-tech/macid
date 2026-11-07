import SwiftUI

enum Palette {
  static let ir = Color(red: 1.0, green: 0.30, blue: 0.43)     // depth dots / scanning
  static let ok = Color(red: 0.25, green: 0.85, blue: 0.65)    // matched
  static let amber = Color(red: 1.0, green: 0.70, blue: 0.36)  // Pro
  static let ink = Color(red: 0.04, green: 0.05, blue: 0.07)
}

/// Studio backdrop shared by the lock screen and setup views.
struct StudioBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.19), Color(red: 0.13, green: 0.09, blue: 0.25)],
                     startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(Palette.ir.opacity(0.45)).frame(width: 900).blur(radius: 220).offset(x: 380, y: 260)
      Circle().fill(Palette.amber.opacity(0.28)).frame(width: 700).blur(radius: 200).offset(x: -460, y: 420)
      Circle().fill(Color(red: 0.48, green: 0.36, blue: 1.0).opacity(0.35)).frame(width: 800).blur(radius: 220).offset(x: 80, y: -320)
    }
    .ignoresSafeArea()
  }
}

/// Circular camera view with depth dots and a status ring (the "Face ID" moment).
struct ScanRing: View {
  @Environment(AppModel.self) private var model
  var diameter: CGFloat = 220
  var forceScanning = false

  private var status: ScanStatus { model.scanStatus }

  private var isScanning: Bool {
    if forceScanning { return true }
    switch status {
    case .scanning, .cloud: return true
    default: return false
    }
  }

  private var matched: Bool {
    if case .finished(.matched) = status { return true }
    return false
  }

  private var failed: Bool {
    if case let .finished(outcome) = status, outcome != .quotaExhausted { if case .matched = outcome { return false }; return true }
    return false
  }

  var body: some View {
    ZStack {
      Circle().fill(.black.opacity(0.55))
      if model.scanner.isRunning {
        CameraPreview(session: model.scanner.camera.session)
          .opacity(0.55)
          .clipShape(Circle())
        DepthDotsOverlay(sample: model.scanner.latest, imageSize: model.scanner.imageSize, matched: matched, scanning: isScanning)
          .clipShape(Circle())
      }
      if !isScanning || !model.scanner.isRunning {
        Image(systemName: matched ? "checkmark" : failed ? "xmark" : "faceid")
          .font(.system(size: diameter * 0.32, weight: .medium))
          .foregroundStyle(matched ? Palette.ok : failed ? Palette.ir : .white)
          .contentTransition(.symbolEffect(.replace))
      }
      Circle()
        .stroke(ringColor.opacity(0.3), lineWidth: 6)
      if isScanning {
        Circle()
          .trim(from: 0, to: 0.22)
          .stroke(Palette.ir, style: StrokeStyle(lineWidth: 6, lineCap: .round))
          .rotationEffect(.degrees(spin))
          .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = 360 } }
      } else {
        Circle().stroke(ringColor, lineWidth: 6)
      }
    }
    .frame(width: diameter, height: diameter)
    .animation(.easeInOut(duration: 0.25), value: matched)
  }

  @State private var spin = 0.0

  private var ringColor: Color { matched ? Palette.ok : failed ? Palette.ir : .white.opacity(0.6) }
}

/// Label + value tile used on the home screen.
struct StatTile<Accessory: View>: View {
  let symbol: String
  let title: String
  let value: String
  var tint: Color = .accentColor
  @ViewBuilder var accessory: Accessory

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: symbol)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title2.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
      accessory
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .padding(16)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

extension StatTile where Accessory == EmptyView {
  init(symbol: String, title: String, value: String, tint: Color = .accentColor) {
    self.init(symbol: symbol, title: title, value: value, tint: tint) { EmptyView() }
  }
}
