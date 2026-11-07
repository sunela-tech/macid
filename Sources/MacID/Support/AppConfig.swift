import Foundation

/// Central configuration for Mac ID.
enum AppConfig {
  // MARK: Meshy

  /// Meshy API key. Embedded at the owner's request. Anyone who downloads the app can
  /// extract it from the binary, so rotate it in the Meshy dashboard if it leaks or is abused.
  static let meshyAPIKey = "msy_KeseGY5NTf0vKQDJG5GEoYZV2bJTn47aZ3of"
  static let meshyBaseURL = URL(string: "https://api.meshy.ai")!

  /// Builds the full textured head from one photo during setup (Meshy 7.1).
  static let headModel = "meshy-7.1"
  /// Fast, low-cost scan that must match the 7.1 head (Meshy 6 Lite, mesh only).
  static let scanModel = "meshy-6-lite"
  /// Credit costs from Meshy's pricing table (image-to-3D).
  static let headModelCredits = 30   // meshy-7.1 + 2K texture
  static let scanModelCredits = 5    // meshy-6-lite, mesh only

  /// Similarity (0...1) the Meshy 6 Lite scan must reach against the Meshy 7.1 head.
  static let meshMatchThreshold = 0.62

  // MARK: Plans (Clerk Billing)

  static let freeDailyUnlocks = 30
  /// Plan slug created in Clerk Dashboard → Billing → Plans → User Plans.
  static let proPlanSlug = "pro"
  /// Feature slug attached to the Pro plan. Checked first, per Clerk's guidance to gate capabilities by feature.
  static let unlimitedFeatureSlug = "unlimited_unlocks"
  static let proPriceLabel = "$4/month"

  // MARK: Clerk

  /// Read from Info.plist (`ClerkPublishableKey`, injected by scripts/build-app.sh) or the
  /// `CLERK_PUBLISHABLE_KEY` environment variable when running from Xcode.
  static var clerkPublishableKey: String {
    if let env = ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
      return env
    }
    let plist = (Bundle.main.object(forInfoDictionaryKey: "ClerkPublishableKey") as? String) ?? ""
    return plist.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static var isClerkConfigured: Bool {
    let key = clerkPublishableKey
    return key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_")
  }

  /// Web page that renders Clerk's PricingTable and checkout (see web/pricing/index.html).
  static var pricingURL: URL {
    let fallback = "https://macid.app/pricing"
    let value = (Bundle.main.object(forInfoDictionaryKey: "MacIDPricingURL") as? String) ?? fallback
    return URL(string: value) ?? URL(string: fallback)!
  }

  // MARK: Storage

  static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("Mac ID", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
