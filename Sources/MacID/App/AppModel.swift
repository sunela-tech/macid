import Foundation
import Observation

/// User preferences (shared keys with @AppStorage in SettingsView).
enum Prefs {
  static let lockOnWakeKey = "lockOnWake"
  static let lockOnScreensaverKey = "lockOnScreensaverStop"
  static let unlockModeKey = "unlockMode"
  static let strictnessKey = "strictness"
  static let requireLivenessKey = "requireLiveness"
  static let buildHeadKey = "buildHeadWithMeshy"

  private static func bool(_ key: String, _ fallback: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
  }

  static var lockOnWake: Bool { bool(lockOnWakeKey, true) }
  static var lockOnScreensaver: Bool { bool(lockOnScreensaverKey, true) }
  static var requireLiveness: Bool { bool(requireLivenessKey, true) }
  static var buildHead: Bool { bool(buildHeadKey, true) }
  static var strictness: Double { UserDefaults.standard.object(forKey: strictnessKey) as? Double ?? 0.5 }
  static var unlockMode: UnlockMode { UnlockMode(rawValue: UserDefaults.standard.string(forKey: unlockModeKey) ?? "") ?? .onDevice }
}

enum UnlockMode: String, CaseIterable, Identifiable {
  case onDevice
  case meshyCloud

  var id: String { rawValue }
  var title: String {
    switch self {
    case .onDevice: "On-device (about 1 second)"
    case .meshyCloud: "On-device + Meshy 6 Lite scan (about 1 minute, \(AppConfig.scanModelCredits) credits)"
    }
  }
}

enum ScanOutcome: Equatable {
  case matched(Double)
  case noMatch
  case noFace
  case notLive
  case notEnrolled
  case quotaExhausted
  case cameraUnavailable(String)
  case cloudFailed(String)

  var message: String {
    switch self {
    case .matched: "Unlocked"
    case .noMatch: "Face not recognized"
    case .noFace: "No face found. Look at the camera."
    case .notLive: "Blink or turn your head slightly, then try again."
    case .notEnrolled: "Set up Mac ID first."
    case .quotaExhausted: "You've used today's \(AppConfig.freeDailyUnlocks) face unlocks."
    case let .cameraUnavailable(reason): reason
    case let .cloudFailed(reason): reason
    }
  }
}

enum ScanStatus: Equatable {
  case idle
  case scanning(String)
  case cloud(Int)
  case finished(ScanOutcome)
}

enum EnrollStep: Equatable {
  case idle
  case starting
  case capturing(Int)
  case done
  case failed(String)
}

@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  let quota = UnlockQuota()
  let plan = PlanStore()
  let scanner = FaceScanner()
  let enrollment = EnrollmentStore()
  let headBuilder = HeadBuilder()
  let lock = LockController()

  private(set) var scanStatus: ScanStatus = .idle
  private(set) var enrollStep: EnrollStep = .idle

  private init() {
    lock.app = self
  }

  var unlimited: Bool { plan.isPro }

  /// "27 of 30 left today" or "Unlimited".
  var quotaLine: String {
    unlimited ? "Unlimited face unlocks (Pro)" : "\(quota.remaining) of \(quota.dailyLimit) face unlocks left today"
  }

  func start() {
    lock.startObserving()
    headBuilder.resumeIfNeeded(store: enrollment)
    Task {
      await plan.refresh()
      // Clerk restores the session asynchronously at launch; check again once it has.
      try? await Task.sleep(for: .seconds(4))
      await plan.refresh()
    }
  }

  // MARK: - Enrollment

  func enroll() async {
    guard enrollStep != .starting, !isCapturing else { return }
    enrollStep = .starting
    guard await scanner.acquire() else {
      enrollStep = .failed(scanner.cameraError ?? "The camera isn't available.")
      return
    }
    defer { scanner.release() }
    try? await Task.sleep(for: .milliseconds(500))

    let wanted = 12
    let samples = await scanner.collect(for: 8, withPrints: true) { [weak self] all in
      let usable = all.filter { $0.featurePrint != nil && abs($0.yaw) < 0.4 }.count
      self?.enrollStep = .capturing(min(100, usable * 100 / wanted))
      return usable >= wanted
    }
    guard let face = FaceMatcher.enroll(from: samples) else {
      enrollStep = .failed("Mac ID couldn't see your face clearly. Face the camera in even light and try again.")
      return
    }

    // Two photos a moment apart: one for the Meshy 7.1 head, one for the Meshy 6 Lite scan.
    let headPhoto = scanner.snapshotJPEG()
    try? await Task.sleep(for: .milliseconds(800))
    let scanPhoto = scanner.snapshotJPEG()

    headBuilder.cancel()
    enrollment.reset()
    enrollment.saveFace(face)
    if Prefs.buildHead, let headPhoto, let scanPhoto {
      headBuilder.build(headPhoto: headPhoto, scanPhoto: scanPhoto, store: enrollment)
    }
    enrollStep = .done
  }

  private var isCapturing: Bool {
    if case .capturing = enrollStep { return true }
    return false
  }

  func resetEnrollment() {
    headBuilder.cancel()
    enrollment.reset()
    enrollStep = .idle
  }

  // MARK: - Unlock scan

  /// One face-unlock attempt. Counts against the free daily quota.
  func runUnlockScan() async -> ScanOutcome {
    if case .scanning = scanStatus { return .noFace }
    if case .cloud = scanStatus { return .noFace }
    let outcome = await performScan()
    scanStatus = .finished(outcome)
    return outcome
  }

  private func performScan() async -> ScanOutcome {
    guard let matcher = enrollment.matcher else { return .notEnrolled }
    let countsAgainstQuota = !unlimited
    if countsAgainstQuota, !quota.consume() { return .quotaExhausted }

    scanStatus = .scanning("Looking for your face…")
    guard await scanner.acquire() else {
      if countsAgainstQuota { quota.refund() }
      return .cameraUnavailable(scanner.cameraError ?? "The camera isn't available.")
    }

    let strictness = Prefs.strictness
    let needLive = Prefs.requireLiveness
    var live = LivenessTracker()
    var processed = 0
    var passes = 0
    var best = 0.0
    var firstSeen: TimeInterval?

    let samples = await scanner.collect(for: 6, withPrints: true) { [weak self] all in
      while processed < all.count {
        let sample = all[processed]
        processed += 1
        firstSeen = firstSeen ?? sample.time
        live.add(sample)
        if let verdict = matcher.evaluate(sample, strictness: strictness), verdict.passed {
          passes += 1
          best = max(best, verdict.score)
        }
        if let start = firstSeen, sample.time - start > 2, needLive, !live.isLive {
          self?.scanStatus = .scanning("Blink to unlock")
        } else {
          self?.scanStatus = .scanning("Scanning…")
        }
      }
      return passes >= 2 && (!needLive || live.isLive)
    }

    let photo = Prefs.unlockMode == .meshyCloud ? scanner.snapshotJPEG() : nil
    scanner.release()

    if samples.isEmpty { return .noFace }
    if passes < 2 { return .noMatch }
    if needLive, !live.isLive { return .notLive }

    if Prefs.unlockMode == .meshyCloud, let photo, let headOBJ = enrollment.headOBJURL {
      scanStatus = .cloud(0)
      do {
        let score = try await headBuilder.cloudScanScore(photo: photo, headOBJ: headOBJ) { [weak self] p in
          self?.scanStatus = .cloud(p)
        }
        guard score >= AppConfig.meshMatchThreshold else { return .noMatch }
      } catch {
        return .cloudFailed(error.localizedDescription)
      }
    }
    return .matched(best)
  }

  func clearScanStatus() { scanStatus = .idle }
}
