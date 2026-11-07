import AppKit
import ClerkKit
import ClerkKitUI
import SwiftUI

enum SidebarItem: Hashable {
  case home, face, plan
}

struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var selection: SidebarItem? = .home
  @State private var authPresented = false

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        Label("Mac ID", systemImage: "faceid").tag(SidebarItem.home)
        Label("Face & Head", systemImage: "cube.transparent").tag(SidebarItem.face)
        Label("Plan", systemImage: model.plan.isPro ? "infinity" : "creditcard").tag(SidebarItem.plan)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    } detail: {
      switch selection ?? .home {
      case .home: HomeView(selection: $selection)
      case .face: FaceSetupView()
      case .plan: PlanView()
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if AppConfig.isClerkConfigured {
          ClerkAccountButton(authPresented: $authPresented)
        } else {
          Label("Clerk not configured", systemImage: "person.crop.circle.badge.exclamationmark")
            .help("Build with CLERK_PUBLISHABLE_KEY set. See README.")
        }
      }
    }
    .modifier(ClerkAuthHooks(authPresented: $authPresented))
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      // Back from the browser checkout: pick up the new plan.
      Task { await model.plan.refresh() }
    }
  }
}

/// Clerk's prebuilt UserButton, with a Sign In button while signed out.
private struct ClerkAccountButton: View {
  @Binding var authPresented: Bool

  var body: some View {
    UserButton(signedOutContent: {
      Button {
        authPresented = true
      } label: {
        Label("Sign In", systemImage: "person.crop.circle")
      }
    })
  }
}

/// Clerk's prebuilt AuthView in a sheet, OAuth callback handling and session tasks
/// (mirrors Clerk's native macOS example). No-op when Clerk is not configured.
private struct ClerkAuthHooks: ViewModifier {
  @Binding var authPresented: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if AppConfig.isClerkConfigured {
      content.modifier(ConfiguredHooks(authPresented: $authPresented))
    } else {
      content
    }
  }

  private struct ConfiguredHooks: ViewModifier {
    @Environment(Clerk.self) private var clerk
    @Environment(AppModel.self) private var model
    @Binding var authPresented: Bool

    func body(content: Content) -> some View {
      content
        .onOpenURL { url in
          Task { _ = try? await clerk.handle(url) }
        }
        .task {
          for await event in clerk.auth.events {
            switch event {
            case .signInNeedsContinuation, .signUpNeedsContinuation:
              authPresented = true
            default:
              break
            }
          }
        }
        .onChange(of: clerk.session?.tasks, initial: true) { _, tasks in
          if tasks?.isEmpty == false { authPresented = true }
        }
        .onChange(of: clerk.user?.id) { _, _ in
          Task { await model.plan.refresh() }
        }
        .sheet(isPresented: $authPresented) {
          AuthView()
            .frame(minWidth: 420, minHeight: 560)
        }
    }
  }
}
