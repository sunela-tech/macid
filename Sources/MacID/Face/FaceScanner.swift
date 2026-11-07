import CoreVideo
import Foundation
import Observation

/// Thread-safe throttle shared with the camera queue.
final class FrameGate: @unchecked Sendable {
  private let lock = NSLock()
  private var last: TimeInterval = 0
  private var printRequests = 0

  func shouldProcess(now: TimeInterval, interval: TimeInterval) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard now - last >= interval else { return false }
    last = now
    return true
  }

  var wantPrints: Bool {
    lock.lock(); defer { lock.unlock() }
    return printRequests > 0
  }

  func requestPrints(_ on: Bool) {
    lock.lock()
    printRequests = max(0, printRequests + (on ? 1 : -1))
    lock.unlock()
  }
}

/// Runs the camera, analyzes ~10 frames a second with Vision and publishes the latest face.
@MainActor
@Observable
final class FaceScanner {
  let camera = CameraService()
  private(set) var latest: FaceSample?
  private(set) var imageSize = CGSize(width: 1280, height: 720)
  private(set) var isRunning = false
  private(set) var cameraError: String?

  private let gate = FrameGate()
  @ObservationIgnored private var users = 0
  @ObservationIgnored private var collectors: [UUID: SampleBox] = [:]

  final class SampleBox { var items: [FaceSample] = [] }

  /// Starts the camera (reference counted: every `acquire` needs a matching `release`).
  @discardableResult
  func acquire() async -> Bool {
    users += 1
    if isRunning { return true }
    let gate = self.gate
    camera.setFrameHandler { [weak self] buffer in
      let now = ProcessInfo.processInfo.systemUptime
      let wantPrint = gate.wantPrints
      guard gate.shouldProcess(now: now, interval: wantPrint ? 0.12 : 0.09) else { return }
      let sample = FaceAnalyzer.analyze(buffer, wantPrint: wantPrint, time: now)
      let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
      Task { @MainActor [weak self] in self?.receive(sample, size: size) }
    }
    do {
      try await camera.start()
      isRunning = true
      cameraError = nil
      return true
    } catch {
      users = max(0, users - 1)
      cameraError = error.localizedDescription
      return false
    }
  }

  func release() {
    users = max(0, users - 1)
    guard users == 0 else { return }
    camera.stop()
    camera.setFrameHandler(nil)
    isRunning = false
    latest = nil
  }

  /// Collects analyzed frames for up to `seconds`, stopping early when `stopWhen` returns true.
  func collect(
    for seconds: Double,
    withPrints: Bool,
    stopWhen: (([FaceSample]) -> Bool)? = nil
  ) async -> [FaceSample] {
    if withPrints { gate.requestPrints(true) }
    defer { if withPrints { gate.requestPrints(false) } }
    let id = UUID()
    let box = SampleBox()
    collectors[id] = box
    defer { collectors[id] = nil }
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(100))
      if let stopWhen, stopWhen(box.items) { break }
    }
    return box.items
  }

  /// JPEG of the current camera frame (unmirrored), for Meshy.
  func snapshotJPEG() -> Data? {
    guard let frame = camera.latestFrame() else { return nil }
    return CameraService.jpeg(from: frame)
  }

  private func receive(_ sample: FaceSample?, size: CGSize) {
    imageSize = size
    latest = sample
    guard let sample else { return }
    for box in collectors.values { box.items.append(sample) }
  }
}
