import Foundation
import LocalAuthentication

/// Touch ID or the Mac's login password, through the system sheet.
enum DeviceAuth {
  /// "Touch ID" on Macs with a sensor, otherwise "your password".
  static var fallbackName: String {
    let context = LAContext()
    var error: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .touchID {
      return "Touch ID"
    }
    return "your password"
  }

  static var hasTouchID: Bool { fallbackName == "Touch ID" }

  /// Shows the system Touch ID sheet, which falls back to the login password.
  static func authenticate(reason: String) async -> Bool {
    let context = LAContext()
    context.localizedFallbackTitle = "Use Password…"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
    do {
      return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    } catch {
      return false
    }
  }
}
