import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @AppStorage(Prefs.lockOnWakeKey) private var lockOnWake = true
  @AppStorage(Prefs.lockOnScreensaverKey) private var lockOnScreensaver = true
  @AppStorage(Prefs.requireLivenessKey) private var requireLiveness = true
  @AppStorage(Prefs.strictnessKey) private var strictness = 0.5
  @AppStorage(Prefs.unlockModeKey) private var unlockMode = UnlockMode.onDevice.rawValue
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    Form {
      Section("Locking") {
        Toggle("Lock when my Mac wakes", isOn: $lockOnWake)
        Toggle("Lock when the screen saver stops", isOn: $lockOnScreensaver)
        Text("Mac ID only locks when macOS didn't already ask for your password.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Open Mac ID at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
        if let loginError { Text(loginError).font(.caption).foregroundStyle(Palette.ir) }
      }

      Section("Face unlock") {
        Picker("Unlock scan", selection: $unlockMode) {
          ForEach(UnlockMode.allCases) { mode in
            Text(mode.title).tag(mode.rawValue)
          }
        }
        .pickerStyle(.radioGroup)
        VStack(alignment: .leading) {
          Slider(value: $strictness, in: 0 ... 1) {
            Text("Strictness")
          } minimumValueLabel: {
            Text("Relaxed")
          } maximumValueLabel: {
            Text("Strict")
          }
          Text("Stricter rejects more look-alikes but may ask you to retry in poor light.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Require a blink or head movement", isOn: $requireLiveness)
      }

      Section("Plan") {
        LabeledContent("Current plan", value: model.plan.isPro ? "Pro" : "Free")
        LabeledContent("Face unlocks left today", value: model.unlimited ? "Unlimited" : "\(model.quota.remaining) of \(model.quota.dailyLimit)")
        LabeledContent("Resets", value: model.quota.resetsAt.formatted(date: .omitted, time: .shortened))
      }
    }
    .formStyle(.grouped)
    .frame(width: 560)
    .frame(minHeight: 520)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      loginError = nil
    } catch {
      loginError = error.localizedDescription
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}

struct MenuBarContent: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(model.quotaLine)
    Divider()
    Button("Lock Now") { model.lock.lock() }
      .keyboardShortcut("l", modifiers: [.command, .control])
      .disabled(!model.enrollment.isEnrolled)
    Button("Open Mac ID…") {
      openWindow(id: "main")
      NSApp.activate()
    }
    if !model.unlimited {
      Button("Get Pro (\(AppConfig.proPriceLabel))…") { model.plan.openCheckout() }
    }
    Divider()
    Button("Quit Mac ID") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
