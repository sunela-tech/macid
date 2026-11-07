import SwiftUI

/// The full-screen Mac ID lock. Starts a face scan as soon as it appears on the main display.
struct LockScreenView: View {
  let isPrimary: Bool
  @Environment(AppModel.self) private var model
  @State private var started = false

  private var busy: Bool {
    switch model.scanStatus {
    case .scanning, .cloud: true
    default: false
    }
  }

  private var quotaOut: Bool { !model.unlimited && model.quota.isExhausted }

  private var statusText: String {
    switch model.scanStatus {
    case .idle: "Look at your Mac to unlock"
    case let .scanning(text): text
    case let .cloud(progress): "Meshy 6 Lite depth scan… \(progress)%"
    case let .finished(outcome): outcome.message
    }
  }

  var body: some View {
    ZStack {
      StudioBackground()
      VStack(spacing: 0) {
        TimelineView(.everyMinute) { context in
          VStack(spacing: 2) {
            Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
              .font(.system(size: 26, weight: .semibold))
            Text(context.date, format: .dateTime.hour().minute())
              .font(.system(size: 118, weight: .semibold))
              .monospacedDigit()
          }
          .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.top, 80)

        Spacer(minLength: 40)

        if isPrimary {
          controls
        } else {
          Image(systemName: "lock.fill")
            .font(.system(size: 44))
            .foregroundStyle(.white.opacity(0.7))
        }

        Spacer(minLength: 40)

        Label("Mac ID", systemImage: "faceid")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.white.opacity(0.5))
          .padding(.bottom, 28)
      }
    }
    .preferredColorScheme(.dark)
    .task {
      guard isPrimary, !started else { return }
      started = true
      await attempt()
    }
  }

  private var controls: some View {
    VStack(spacing: 18) {
      ScanRing(diameter: 210)
      Text(statusText)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
      Text(model.quotaLine)
        .font(.callout)
        .foregroundStyle(.white.opacity(0.65))

      HStack(spacing: 12) {
        Button {
          Task { await attempt() }
        } label: {
          Label("Try Face Again", systemImage: "faceid")
        }
        .disabled(busy || quotaOut)

        Button {
          Task { await model.lock.unlockWithDevice() }
        } label: {
          Label("Use \(DeviceAuth.fallbackName)", systemImage: DeviceAuth.hasTouchID ? "touchid" : "key.fill")
        }
        .keyboardShortcut(.defaultAction)
      }
      .controlSize(.large)
      .buttonStyle(.borderedProminent)
      .tint(.white.opacity(0.18))

      if quotaOut {
        Text("Free includes \(AppConfig.freeDailyUnlocks) face unlocks a day. Pro (\(AppConfig.proPriceLabel)) makes them unlimited. Face unlock comes back at midnight.")
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.6))
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
      }
    }
  }

  private func attempt() async {
    let outcome = await model.runUnlockScan()
    switch outcome {
    case .matched:
      try? await Task.sleep(for: .milliseconds(450))
      model.lock.unlock()
    case .quotaExhausted:
      // Out of free face unlocks: go straight to Touch ID / password.
      await model.lock.unlockWithDevice()
    default:
      break
    }
  }
}
