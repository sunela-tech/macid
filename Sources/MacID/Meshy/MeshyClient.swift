import Foundation

/// A Meshy Image-to-3D task (`GET /openapi/v1/image-to-3d/{id}`).
struct MeshyTask: Decodable {
  let id: String
  let status: String           // PENDING, IN_PROGRESS, SUCCEEDED, FAILED, CANCELED
  let progress: Int?
  let modelUrls: ModelURLs?
  let thumbnailUrl: String?
  let taskError: TaskError?

  struct ModelURLs: Decodable {
    let glb: String?
    let obj: String?
    let usdz: String?
    let fbx: String?
  }

  struct TaskError: Decodable {
    let message: String?
  }

  var isFinished: Bool { ["SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"].contains(status) }
}

enum MeshyError: LocalizedError {
  case http(Int, String)
  case taskFailed(String)
  case missingModel

  var errorDescription: String? {
    switch self {
    case let .http(code, message):
      switch code {
      case 401: "Meshy rejected the API key (401). Check AppConfig.meshyAPIKey."
      case 402: "The Meshy account is out of credits (402)."
      case 429: "Meshy is rate limiting requests (429). Try again in a minute."
      default: "Meshy error \(code): \(message)"
      }
    case let .taskFailed(message): "Meshy could not build the model: \(message)"
    case .missingModel: "Meshy finished but returned no model file."
    }
  }
}

/// Small client for the parts of the Meshy API that Mac ID uses.
struct MeshyClient {
  var apiKey = AppConfig.meshyAPIKey
  var baseURL = AppConfig.meshyBaseURL
  var session = URLSession.shared

  private var decoder: JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
  }

  private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
    var req = URLRequest(url: baseURL.appendingPathComponent(path))
    req.httpMethod = method
    req.timeoutInterval = 60
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return req
  }

  private func send(_ req: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200 ..< 300).contains(code) else {
      let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
      throw MeshyError.http(code, message ?? String(decoding: data.prefix(300), as: UTF8.self))
    }
    return data
  }

  /// Starts an Image-to-3D task from a JPEG and returns its task id.
  /// - Parameters:
  ///   - model: `meshy-7.1` for the full head, `meshy-6-lite` for quick scans.
  ///   - textured: false makes a mesh-only model (cheaper and faster).
  func createImageTo3D(jpeg: Data, model: String, textured: Bool) async throws -> String {
    let body: [String: Any] = [
      "image_url": "data:image/jpeg;base64," + jpeg.base64EncodedString(),
      "ai_model": model,
      "should_texture": textured,
      "target_formats": textured ? ["glb", "obj", "usdz"] : ["obj"],
    ]
    let data = try await send(try request("openapi/v1/image-to-3d", method: "POST", body: body))
    struct Created: Decodable { let result: String }
    return try decoder.decode(Created.self, from: data).result
  }

  func task(_ id: String) async throws -> MeshyTask {
    let data = try await send(try request("openapi/v1/image-to-3d/\(id)"))
    return try decoder.decode(MeshyTask.self, from: data)
  }

  /// Polls until the task finishes. Calls `progress` with 0...100 along the way.
  func waitForTask(_ id: String, progress: @MainActor @escaping (Int) -> Void) async throws -> MeshyTask {
    while true {
      try Task.checkCancellation()
      let current = try await task(id)
      await progress(current.progress ?? 0)
      switch current.status {
      case "SUCCEEDED": return current
      case "FAILED", "CANCELED", "EXPIRED":
        throw MeshyError.taskFailed(current.taskError?.message ?? current.status.lowercased())
      default:
        try await Task.sleep(for: .seconds(4))
      }
    }
  }

  /// Downloads a model file to `destination`, replacing anything already there.
  func download(_ urlString: String?, to destination: URL) async throws {
    guard let urlString, let url = URL(string: urlString) else { throw MeshyError.missingModel }
    let (temp, response) = try await session.download(from: url)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200 ..< 300).contains(code) else { throw MeshyError.http(code, "download failed") }
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: temp, to: destination)
  }

  /// Remaining Meshy credits (free call).
  func balance() async throws -> Int {
    let data = try await send(try request("openapi/v1/balance"))
    struct Balance: Decodable { let balance: Int }
    return try decoder.decode(Balance.self, from: data).balance
  }
}
