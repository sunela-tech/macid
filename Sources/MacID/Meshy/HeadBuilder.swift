import Foundation
import Observation

/// Runs the Meshy side of setup:
/// 1. Meshy 7.1 builds the full textured head from the setup photo.
/// 2. Meshy 6 Lite makes a quick mesh from a second photo.
/// 3. The two meshes are compared; the Lite scan has to match the 7.1 head.
@MainActor
@Observable
final class HeadBuilder {
  enum Phase: Equatable {
    case idle
    case uploading
    case generating
    case comparing
    case done
    case failed(String)
  }

  private(set) var phase: Phase = .idle
  private(set) var headProgress = 0
  private(set) var liteProgress = 0
  private(set) var credits: Int?

  @ObservationIgnored private let client = MeshyClient()
  @ObservationIgnored private var job: Task<Void, Never>?

  var isBusy: Bool { [.uploading, .generating, .comparing].contains(phase) }

  func refreshCredits() async {
    credits = try? await client.balance()
  }

  func build(headPhoto: Data, scanPhoto: Data, store: EnrollmentStore) {
    job?.cancel()
    job = Task { [weak self] in
      await self?.run(headPhoto: headPhoto, scanPhoto: scanPhoto, store: store)
    }
  }

  /// Picks up tasks that were still running when the app quit.
  func resumeIfNeeded(store: EnrollmentStore) {
    guard job == nil, let headId = store.head.headTaskId, !store.head.isComplete else { return }
    let liteId = store.head.liteTaskId
    job = Task { [weak self] in
      await self?.finish(headId: headId, liteId: liteId, store: store)
    }
  }

  func cancel() {
    job?.cancel()
    job = nil
    phase = .idle
  }

  private func run(headPhoto: Data, scanPhoto: Data, store: EnrollmentStore) async {
    phase = .uploading
    headProgress = 0
    liteProgress = 0
    do {
      let client = self.client
      async let headId = client.createImageTo3D(jpeg: headPhoto, model: AppConfig.headModel, textured: true)
      async let liteId = client.createImageTo3D(jpeg: scanPhoto, model: AppConfig.scanModel, textured: false)
      let ids = try await (headId, liteId)
      store.head = HeadState(headTaskId: ids.0, liteTaskId: ids.1)
      store.persist()
      await finish(headId: ids.0, liteId: ids.1, store: store)
    } catch is CancellationError {
      phase = .idle
    } catch {
      fail(error, store: store)
    }
  }

  private func finish(headId: String, liteId: String?, store: EnrollmentStore) async {
    phase = .generating
    let client = self.client
    do {
      async let head = client.waitForTask(headId) { [weak self] p in self?.headProgress = p }
      async let lite = waitOptional(liteId)
      let (headTask, liteTask) = try await (head, lite)

      let dir = AppConfig.supportDirectory
      try await client.download(headTask.modelUrls?.obj, to: dir.appendingPathComponent("head-meshy-7.1.obj"))
      store.head.headOBJ = "head-meshy-7.1.obj"
      if (try? await client.download(headTask.modelUrls?.usdz, to: dir.appendingPathComponent("head-meshy-7.1.usdz"))) != nil {
        store.head.headUSDZ = "head-meshy-7.1.usdz"
      }
      store.head.thumbnailURL = headTask.thumbnailUrl
      if let liteTask {
        try await client.download(liteTask.modelUrls?.obj, to: dir.appendingPathComponent("scan-meshy-6-lite.obj"))
        store.head.liteOBJ = "scan-meshy-6-lite.obj"
      }
      store.persist()

      if let a = store.headOBJURL, let b = store.file(store.head.liteOBJ) {
        phase = .comparing
        let score = try await Task.detached(priority: .userInitiated) {
          try MeshCompare.similarity(objA: a, objB: b)
        }.value
        store.head.meshMatch = score
      }
      store.head.lastError = nil
      store.persist()
      phase = .done
      await refreshCredits()
    } catch is CancellationError {
      phase = .idle
    } catch {
      fail(error, store: store)
    }
    job = nil
  }

  private func waitOptional(_ id: String?) async throws -> MeshyTask? {
    guard let id else { return nil }
    return try await client.waitForTask(id) { [weak self] p in self?.liteProgress = p }
  }

  private func fail(_ error: Error, store: EnrollmentStore) {
    let message = error.localizedDescription
    phase = .failed(message)
    store.head.lastError = message
    store.persist()
    job = nil
  }

  /// One Meshy 6 Lite scan compared against the enrolled Meshy 7.1 head.
  /// Used by the optional "Meshy cloud scan" unlock mode. Returns 0...1.
  func cloudScanScore(photo: Data, headOBJ: URL, progress: @MainActor @escaping (Int) -> Void) async throws -> Double {
    let id = try await client.createImageTo3D(jpeg: photo, model: AppConfig.scanModel, textured: false)
    let task = try await client.waitForTask(id, progress: progress)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("macid-scan-\(id).obj")
    try await client.download(task.modelUrls?.obj, to: temp)
    defer { try? FileManager.default.removeItem(at: temp) }
    return try await Task.detached(priority: .userInitiated) {
      try MeshCompare.similarity(objA: headOBJ, objB: temp)
    }.value
  }
}
