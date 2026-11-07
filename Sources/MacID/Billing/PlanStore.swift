import AppKit
import ClerkKit
import Foundation
import Observation

/// Free vs Pro, from Clerk Billing.
///
/// Gating follows Clerk's guidance: check the `unlimited_unlocks` feature first (so the
/// feature can move between plans without an app update), then the `pro` plan slug.
/// Clerk evaluates both from the session token claims, so after a checkout the token
/// is refreshed with `skipCache` before checking again.
@MainActor
@Observable
final class PlanStore {
  private(set) var isPro = false
  private(set) var detail = "Free plan"
  private(set) var renewal: String?
  private(set) var isRefreshing = false
  private(set) var lastError: String?

  private let cacheKey = "plan.cache"
  private struct Cache: Codable { var isPro: Bool; var checked: Date }

  init() {
    // Offline grace: trust a Pro result for up to 3 days without reaching Clerk.
    if let data = UserDefaults.standard.data(forKey: cacheKey),
       let cache = try? JSONDecoder().decode(Cache.self, from: data),
       cache.isPro, Date().timeIntervalSince(cache.checked) < 3 * 24 * 3600 {
      isPro = true
      detail = "Pro plan"
    }
  }

  var isSignedIn: Bool {
    AppConfig.isClerkConfigured && Clerk.shared.user != nil
  }

  func refresh() async {
    guard AppConfig.isClerkConfigured, !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let clerk = Clerk.shared
    guard clerk.user != nil else {
      apply(pro: false, detail: "Free plan", renewal: nil)
      return
    }
    do {
      _ = try await clerk.session?.getToken(.init(skipCache: true))
      lastError = nil
    } catch {
      lastError = "Couldn't reach Clerk. Showing your last known plan."
      return
    }

    let pro = clerk.has(feature: AppConfig.unlimitedFeatureSlug) || clerk.has(plan: AppConfig.proPlanSlug)
    var renewalText: String?
    if pro, let subscription = try? await clerk.billing.getSubscription(), let next = subscription.nextPayment {
      let date = next.date.formatted(date: .abbreviated, time: .omitted)
      renewalText = "Renews \(date) · \(next.amount.amountFormatted)"
    }
    apply(pro: pro, detail: pro ? "Pro plan · unlimited face unlocks" : "Free plan · \(AppConfig.freeDailyUnlocks) face unlocks a day", renewal: renewalText)
  }

  /// Opens the Clerk PricingTable page in the browser. The user signs in there with the
  /// same Clerk account and checks out; `refresh()` runs again when Mac ID is reactivated.
  func openCheckout() {
    NSWorkspace.shared.open(AppConfig.pricingURL)
  }

  private func apply(pro: Bool, detail: String, renewal: String?) {
    isPro = pro
    self.detail = detail
    self.renewal = renewal
    if let data = try? JSONEncoder().encode(Cache(isPro: pro, checked: Date())) {
      UserDefaults.standard.set(data, forKey: cacheKey)
    }
  }
}
