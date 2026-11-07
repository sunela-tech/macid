import AppKit
import ClerkKit
import ClerkKitUI
import SwiftUI

@main
struct MacIDApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var model = AppModel.shared

  init() {
    if AppConfig.isClerkConfigured {
      Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
    }
  }

  var body: some Scene {
    WindowGroup("Mac ID", id: "main") {
      RootView()
        .environment(model)
        .modifier(ClerkEnvironment())
        .frame(minWidth: 860, minHeight: 600)
    }
    .defaultSize(width: 1040, height: 720)
    .handlesExternalEvents(matching: ["*"])

    MenuBarExtra {
      MenuBarContent()
        .environment(model)
    } label: {
      Image(systemName: model.lock.isLocked ? "lock.fill" : "faceid")
    }

    Settings {
      SettingsView()
        .environment(model)
    }
  }
}

/// Injects `Clerk.shared` for ClerkKitUI views, only once Clerk is configured.
struct ClerkEnvironment: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if AppConfig.isClerkConfigured {
      content.environment(Clerk.shared)
    } else {
      content
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated {
      AppModel.shared.start()
    }
  }

  /// Keep running in the menu bar when the window closes; the lock needs to stay armed.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
