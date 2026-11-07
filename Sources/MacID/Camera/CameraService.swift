import AVFoundation
import CoreImage
import Foundation
import ImageIO

enum CameraError: LocalizedError {
  case denied
  case noCamera

  var errorDescription: String? {
    switch self {
    case .denied: "Mac ID can't use the camera. Allow it in System Settings → Privacy & Security → Camera."
    case .noCamera: "No camera was found. Open the lid or connect a camera."
    }
  }
}

/// Owns the capture session and hands every frame to `onFrame` on a private queue.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
  let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let queue = DispatchQueue(label: "app.macid.camera")
  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  private var configured = false
  private var frameHandler: (@Sendable (CVPixelBuffer) -> Void)?

  /// Called on the camera queue for each frame.
  func setFrameHandler(_ handler: (@Sendable (CVPixelBuffer) -> Void)?) {
    lock.lock(); frameHandler = handler; lock.unlock()
  }

  static func requestAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
    default: return false
    }
  }

  var isRunning: Bool { session.isRunning }

  func start() async throws {
    guard await Self.requestAccess() else { throw CameraError.denied }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try self.configureIfNeeded()
          if !self.session.isRunning { self.session.startRunning() }
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func stop() {
    queue.async {
      if self.session.isRunning { self.session.stopRunning() }
    }
  }

  /// Most recent frame, or nil before the first one arrives.
  func latestFrame() -> CVPixelBuffer? {
    lock.lock(); defer { lock.unlock() }
    return latest
  }

  private func configureIfNeeded() throws {
    guard !configured else { return }
    let device = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
      mediaType: .video,
      position: .unspecified
    ).devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? AVCaptureDevice.default(for: .video)
    guard let device else { throw CameraError.noCamera }

    session.beginConfiguration()
    defer { session.commitConfiguration() }
    if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else { throw CameraError.noCamera }
    session.addInput(input)

    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(output) else { throw CameraError.noCamera }
    session.addOutput(output)
    configured = true
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lock.lock()
    latest = buffer
    let handler = frameHandler
    lock.unlock()
    handler?(buffer)
  }

  // MARK: - Still images

  private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

  /// JPEG of a frame, scaled so the long side is at most `maxDimension`. Not mirrored.
  static func jpeg(from buffer: CVPixelBuffer, maxDimension: CGFloat = 1024, quality: CGFloat = 0.88) -> Data? {
    var image = CIImage(cvPixelBuffer: buffer)
    let longSide = max(image.extent.width, image.extent.height)
    if longSide > maxDimension {
      let scale = maxDimension / longSide
      image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let options: [CIImageRepresentationOption: Any] = [
      CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
    ]
    return ciContext.jpegRepresentation(of: image, colorSpace: sRGB, options: options)
  }

  /// Grayscale crop around a face (Vision-normalized box, origin bottom-left), padded by `padding`.
  static func faceCrop(from buffer: CVPixelBuffer, box: CGRect, padding: CGFloat = 0.18) -> CGImage? {
    let image = CIImage(cvPixelBuffer: buffer)
    let w = image.extent.width, h = image.extent.height
    var rect = CGRect(x: box.minX * w, y: box.minY * h, width: box.width * w, height: box.height * h)
    rect = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding).intersection(image.extent)
    guard rect.width > 32, rect.height > 32 else { return nil }
    let gray = image.cropped(to: rect).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
    return ciContext.createCGImage(gray, from: gray.extent)
  }
}
