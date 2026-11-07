import Foundation
import Observation

/// What Meshy produced for this Mac's enrolled user.
struct HeadState: Codable, Equatable {
  var headTaskId: String?
  var liteTaskId: String?
  /// File names inside `AppConfig.supportDirectory`.
  var headUSDZ: String?
  var headOBJ: String?
  var liteOBJ: String?
  var thumbnailURL: String?
  /// Meshy 6 Lite scan vs Meshy 7.1 head, 0...1.
  var meshMatch: Double?
  var lastError: String?

  var isComplete: Bool { headOBJ != nil && (liteTaskId == nil || meshMatch != nil) }
}

/// The enrolled face and head, encrypted at rest (AES-GCM, key in the Keychain).
@MainActor
@Observable
final class EnrollmentStore {
  private(set) var face: EnrolledFace?
  var head = HeadState()
  @ObservationIgnored private(set) var matcher: FaceMatcher?

  private struct Record: Codable {
    var face: EnrolledFace?
    var head: HeadState
  }

  private var fileURL: URL { AppConfig.supportDirectory.appendingPathComponent("enrollment.bin") }

  init() { load() }

  var isEnrolled: Bool { face != nil }

  func file(_ name: String?) -> URL? {
    guard let name else { return nil }
    let url = AppConfig.supportDirectory.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  var headModelURL: URL? { file(head.headUSDZ) }
  var headOBJURL: URL? { file(head.headOBJ) }

  func saveFace(_ face: EnrolledFace) {
    self.face = face
    matcher = FaceMatcher(face)
    persist()
  }

  func persist() {
    do {
      let data = try JSONEncoder().encode(Record(face: face, head: head))
      try SecureFile.write(data, to: fileURL)
    } catch {
      NSLog("Mac ID: could not save enrollment: \(error.localizedDescription)")
    }
  }

  func reset() {
    for name in [head.headUSDZ, head.headOBJ, head.liteOBJ].compactMap({ $0 }) {
      try? FileManager.default.removeItem(at: AppConfig.supportDirectory.appendingPathComponent(name))
    }
    face = nil
    matcher = nil
    head = HeadState()
    try? FileManager.default.removeItem(at: fileURL)
  }

  private func load() {
    guard
      let data = try? SecureFile.read(fileURL),
      let record = try? JSONDecoder().decode(Record.self, from: data)
    else { return }
    face = record.face
    head = record.head
    matcher = record.face.map(FaceMatcher.init)
  }
}
