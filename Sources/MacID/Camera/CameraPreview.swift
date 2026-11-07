import AVFoundation
import SwiftUI

/// Mirrored live camera preview (what the user expects to see of themselves).
struct CameraPreview: NSViewRepresentable {
  let session: AVCaptureSession

  func makeNSView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.previewLayer.session = session
    return view
  }

  func updateNSView(_ nsView: PreviewView, context: Context) {
    if nsView.previewLayer.session !== session { nsView.previewLayer.session = session }
  }

  final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      layer = CALayer()
      wantsLayer = true
      previewLayer.videoGravity = .resizeAspectFill
      layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
      super.layout()
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previewLayer.frame = bounds
      CATransaction.commit()
      if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
      }
    }
  }
}
