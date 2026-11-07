@_spi(FrameworkIntegration) import ClerkKit
import AppKit
import SwiftUI
import WebKit

/// What the in-app billing sheet shows.
enum CheckoutMode: String, Identifiable {
  /// Clerk PricingTable: subscribe, switch plan, cancel (checkout drawer with Stripe's card form).
  case plans
  /// Clerk UserProfile billing page: payment methods, statements, subscription.
  case account

  var id: String { rawValue }

  var title: String {
    switch self {
    case .plans: "Mac ID Pro"
    case .account: "Billing & Payment Methods"
    }
  }

  var symbol: String {
    switch self {
    case .plans: "infinity"
    case .account: "creditcard"
    }
  }
}

enum CheckoutEvent {
  case ready
  case changed
  case subscribed
  case failed(String)
  case deviceToken(String)
}

/// Clerk's billing UI in a WKWebView, signed in as the app's own Clerk session.
///
/// The page (Resources/checkout.html) loads clerk-js from this app's Clerk Frontend API and
/// sends ClerkKit's device token on each request, so the web view acts as the same Clerk
/// client as the native app (the approach Clerk's Expo SDK uses). Card details go straight
/// from Stripe's form to Stripe; Mac ID never sees them. Nothing is stored on disk
/// (non-persistent website data store).
struct CheckoutWebView: NSViewRepresentable {
  let mode: CheckoutMode
  var onEvent: (CheckoutEvent) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let controller = WKUserContentController()
    controller.add(WeakScriptHandler(target: context.coordinator), name: "macid")
    controller.addUserScript(WKUserScript(source: Self.bootstrap(mode: mode), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    configuration.userContentController = controller

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.underPageBackgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.105, alpha: 1)

    if let url = Bundle.main.url(forResource: "checkout", withExtension: "html"),
       let html = try? String(contentsOf: url, encoding: .utf8) {
      webView.loadHTMLString(html, baseURL: AppConfig.checkoutOrigin)
    } else {
      let report = onEvent
      DispatchQueue.main.async { report(.failed("The checkout page is missing from the app bundle.")) }
    }
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    context.coordinator.onEvent = onEvent
  }

  static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
    nsView.configuration.userContentController.removeScriptMessageHandler(forName: "macid")
    nsView.stopLoading()
  }

  /// `window.__MACID__` for the page, JSON-encoded so every value is escaped.
  private static func bootstrap(mode: CheckoutMode) -> String {
    let config: [String: String] = [
      "publishableKey": AppConfig.clerkPublishableKey,
      "deviceToken": AppConfig.isClerkConfigured ? (Clerk.shared.deviceToken ?? "") : "",
      "mode": mode.rawValue,
    ]
    let json = (try? JSONSerialization.data(withJSONObject: config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return "window.__MACID__ = \(json);"
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var onEvent: (CheckoutEvent) -> Void

    init(onEvent: @escaping (CheckoutEvent) -> Void) {
      self.onEvent = onEvent
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
      switch type {
      case "ready": onEvent(.ready)
      case "changed": onEvent(.changed)
      case "error": onEvent(.failed(body["message"] as? String ?? "Checkout couldn't load."))
      case "deviceToken":
        if let value = body["value"] as? String, !value.isEmpty { onEvent(.deviceToken(value)) }
      default: break
      }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
      guard let url = navigationAction.request.url else { return .allow }
      // PricingTable's newSubscriptionRedirectUrl: the purchase went through.
      if url.scheme == "macid-checkout" {
        onEvent(.subscribed)
        return .cancel
      }
      // Links that leave the checkout (terms, receipts, bank pages) open in the browser.
      let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
      if navigationAction.navigationType == .linkActivated, isMainFrame,
         let host = url.host, host != AppConfig.checkoutOrigin.host {
        NSWorkspace.shared.open(url)
        return .cancel
      }
      return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
      if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
      return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      onEvent(.failed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      // Cancelled navigations (our own redirect interception) report NSURLErrorCancelled; ignore those.
      if (error as NSError).code == NSURLErrorCancelled { return }
      onEvent(.failed(error.localizedDescription))
    }
  }
}

/// Breaks the WKUserContentController → handler retain cycle.
@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?

  init(target: WKScriptMessageHandler) {
    self.target = target
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
