@_spi(FrameworkIntegration) import ClerkKit
import AppKit
import Foundation
import Observation

/// Free vs Pro, plus everything on the Plan & Billing screen, from Clerk Billing.
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

  // Billing details (read with ClerkKit's native Billing APIs).
  private(set) var plans: [BillingPlan] = []
  private(set) var subscription: BillingSubscription?
  private(set) var paymentMethods: [BillingPaymentMethod] = []
  private(set) var statements: [BillingStatement] = []
  private(set) var payments: [BillingPayment] = []

  /// In-app checkout / billing sheet currently shown, if any.
  var checkoutMode: CheckoutMode?
  /// Ask RootView to show Clerk's sign-in sheet.
  var showAuth = false

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

  var isTestMode: Bool { AppConfig.clerkPublishableKey.hasPrefix("pk_test_") }

  /// The Pro subscription item, when the user has one (active, upcoming or past due).
  var proItem: BillingSubscriptionItem? {
    subscription?.subscriptionItems.first { $0.plan.slug == AppConfig.proPlanSlug && $0.status != .ended }
  }

  // MARK: - Refresh

  func refresh() async {
    guard AppConfig.isClerkConfigured, !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let clerk = Clerk.shared
    plans = (try? await clerk.billing.getPlans(for: .user).data.filter(\.publiclyVisible)) ?? plans

    guard let user = clerk.user else {
      apply(pro: false, renewal: nil)
      subscription = nil
      paymentMethods = []
      statements = []
      payments = []
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
    subscription = try? await clerk.billing.getSubscription()
    paymentMethods = (try? await user.getPaymentMethods().data) ?? []
    statements = (try? await clerk.billing.getStatements().data) ?? []
    payments = (try? await clerk.billing.getPaymentAttempts().data) ?? []

    var renewalText: String?
    if let item = proItem {
      if item.canceledAt != nil, let end = item.periodEnd {
        renewalText = "Cancelled · Pro until \(end.formatted(date: .abbreviated, time: .omitted))"
      } else if let next = subscription?.nextPayment {
        renewalText = "Renews \(next.date.formatted(date: .abbreviated, time: .omitted)) · \(next.amount.display)"
      }
    }
    apply(pro: pro, renewal: renewalText)
  }

  // MARK: - Checkout inside the app

  /// Shows Clerk's billing UI in a sheet inside Mac ID (or sign-in first).
  func presentCheckout(_ mode: CheckoutMode = .plans) {
    guard AppConfig.isClerkConfigured else {
      lastError = "Mac ID was built without a Clerk publishable key."
      return
    }
    guard isSignedIn, Clerk.shared.deviceToken != nil else {
      showAuth = true
      return
    }
    checkoutMode = mode
  }

  /// Fallback: the same PricingTable in the default browser (web/pricing).
  func openCheckoutInBrowser() {
    NSWorkspace.shared.open(AppConfig.pricingURL)
  }

  /// clerk-js in the checkout sheet received a rotated client token; hand it back to ClerkKit
  /// so the native app and the sheet stay one Clerk client.
  func adoptDeviceToken(_ token: String) async {
    guard AppConfig.isClerkConfigured, token != Clerk.shared.deviceToken else { return }
    _ = try? await Clerk.shared.updateDeviceToken(token)
  }

  /// Called when the sheet reports a finished purchase or plan change.
  func checkoutFinished() async {
    checkoutMode = nil
    await refresh()
    // Clerk can take a moment to put the new plan into the session token.
    if !isPro {
      try? await Task.sleep(for: .seconds(3))
      await refresh()
    }
  }

  private func apply(pro: Bool, renewal: String?) {
    isPro = pro
    detail = pro ? "Pro plan · unlimited face unlocks" : "Free plan · \(AppConfig.freeDailyUnlocks) face unlocks a day"
    self.renewal = renewal
    if let data = try? JSONEncoder().encode(Cache(isPro: pro, checked: Date())) {
      UserDefaults.standard.set(data, forKey: cacheKey)
    }
  }
}

extension BillingMoneyAmount {
  /// "$4.00" (Clerk's `amountFormatted` has no currency symbol).
  var display: String { currencySymbol + amountFormatted }
}

extension BillingPaymentMethod {
  var displayName: String {
    let brand = (cardType ?? walletType ?? paymentType ?? "Card").capitalized
    if let last4 { return "\(brand) •••• \(last4)" }
    return brand
  }

  var expiry: String? {
    guard let month = expiryMonth, let year = expiryYear else { return nil }
    return String(format: "%02d/%02d", month, year % 100)
  }
}
