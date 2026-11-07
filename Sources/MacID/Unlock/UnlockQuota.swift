import Foundation
import Observation

/// Counts face-unlock scans per calendar day. The free plan gets 30 a day;
/// Pro skips the counter entirely. The count lives in the Keychain so deleting
/// the app's preferences does not reset it.
@MainActor
@Observable
final class UnlockQuota {
  private(set) var usedToday = 0
  private var day = ""
  let dailyLimit: Int
  private let account = "unlock-quota"

  init(dailyLimit: Int = AppConfig.freeDailyUnlocks) {
    self.dailyLimit = dailyLimit
    load()
  }

  /// Read-only on purpose (views call it while rendering).
  var remaining: Int {
    let used = day == Self.dayKey() ? usedToday : 0
    return max(0, dailyLimit - used)
  }

  var usedTodayDisplay: Int { dailyLimit - remaining }

  var isExhausted: Bool { remaining == 0 }

  /// Uses one scan. Returns `false` when today's scans are gone.
  func consume() -> Bool {
    rollOverIfNeeded()
    guard usedToday < dailyLimit else { return false }
    usedToday += 1
    save()
    return true
  }

  /// Gives a scan back (used when a scan never started, e.g. the camera was busy).
  func refund() {
    rollOverIfNeeded()
    usedToday = max(0, usedToday - 1)
    save()
  }

  /// Time until the counter resets (local midnight).
  var resetsAt: Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
  }

  private func rollOverIfNeeded() {
    let today = Self.dayKey()
    if today != day {
      day = today
      usedToday = 0
      save()
    }
  }

  private static func dayKey(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private struct Stored: Codable { var day: String; var used: Int }

  private func load() {
    if let data = Keychain.get(account), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
      day = stored.day
      usedToday = stored.used
    }
    rollOverIfNeeded()
  }

  private func save() {
    if let data = try? JSONEncoder().encode(Stored(day: day, used: usedToday)) {
      Keychain.set(data, for: account)
    }
  }
}
