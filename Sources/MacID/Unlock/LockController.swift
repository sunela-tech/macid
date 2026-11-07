import AppKit
import CoreGraphics
import Observation
import SwiftUI

/// Borderless full-screen window that can take keyboard focus.
final class LockWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

/// Puts the Mac ID lock screen over every display and removes it after a face match,
/// Touch ID or the login password.
///
/// Mac ID cannot replace the macOS login window (Apple offers no public API for that).
/// It covers the gap instead: when the Mac wakes or the screen saver stops and macOS
/// itself did not ask for a password, Mac ID locks the screen and unlocks with your face.
@MainActor
@Observable
final class LockController {
  private(set) var isLocked = false
  @ObservationIgnored weak var app: AppModel?
  @ObservationIgnored private var windows: [NSWindow] = []
  @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

  enum Trigger { case wake, screensaver, manual }

  func startObserving() {
    guard observers.isEmpty else { return }
    let workspace = NSWorkspace.shared.notificationCenter
    let distributed = DistributedNotificationCenter.default()

    func watch(_ center: NotificationCenter, _ name: Notification.Name, _ trigger: Trigger) {
      let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.handle(trigger) }
      }
      observers.append((center, token))
    }
    watch(workspace, NSWorkspace.screensDidWakeNotification, .wake)
    watch(workspace, NSWorkspace.didWakeNotification, .wake)
    watch(distributed, Notification.Name("com.apple.screensaver.didstop"), .screensaver)
  }

  private func handle(_ trigger: Trigger) {
    switch trigger {
    case .wake: guard Prefs.lockOnWake else { return }
    case .screensaver: guard Prefs.lockOnScreensaver else { return }
    case .manual: break
    }
    // Give macOS a moment to show its own lock screen; if it did, the user already
    // authenticated with macOS and Mac ID stays out of the way.
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(900))
      if !Self.macOSScreenIsLocked() { self.lock() }
    }
  }

  static func macOSScreenIsLocked() -> Bool {
    guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    if let flag = info["CGSSessionScreenIsLocked"] as? Bool { return flag }
    if let flag = info["CGSSessionScreenIsLocked"] as? NSNumber { return flag.boolValue }
    return false
  }

  func lock() {
    guard !isLocked, let app, app.enrollment.isEnrolled else { return }
    isLocked = true
    NSApp.activate()
    NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]

    let mainScreen = NSScreen.main
    for screen in NSScreen.screens {
      let window = LockWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      window.isOpaque = true
      window.backgroundColor = .black
      window.hasShadow = false
      window.isReleasedWhenClosed = false
      let primary = screen == mainScreen
      window.contentView = NSHostingView(rootView: AnyView(LockScreenView(isPrimary: primary).environment(app)))
      window.setFrame(screen.frame, display: true)
      if primary { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
      windows.append(window)
    }
  }

  func unlock() {
    guard isLocked else { return }
    isLocked = false
    for window in windows { window.orderOut(nil) }
    windows.removeAll()
    NSApp.presentationOptions = []
    app?.clearScanStatus()
  }

  /// Drops the lock windows below the system Touch ID / password sheet while it is up.
  func withSystemSheetVisible(_ body: () async -> Bool) async -> Bool {
    let shielding = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    for window in windows { window.level = .normal }
    let result = await body()
    if isLocked { for window in windows { window.level = shielding } }
    return result
  }

  /// Touch ID or password, always available (free plan out of scans, camera blocked, etc.).
  func unlockWithDevice() async {
    let ok = await withSystemSheetVisible {
      await DeviceAuth.authenticate(reason: "unlock your Mac")
    }
    if ok { unlock() }
  }
}
