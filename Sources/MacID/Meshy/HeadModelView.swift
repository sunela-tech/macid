import SceneKit
import SwiftUI

/// Shows the Meshy 7.1 head (USDZ) slowly turning; drag to orbit.
struct HeadModelView: NSViewRepresentable {
  let url: URL?

  final class Coordinator { var url: URL? }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> SCNView {
    let view = SCNView()
    view.backgroundColor = .clear
    view.allowsCameraControl = true
    view.autoenablesDefaultLighting = true
    view.antialiasingMode = .multisampling4X
    Self.show(url, in: view)
    context.coordinator.url = url
    return view
  }

  func updateNSView(_ view: SCNView, context: Context) {
    guard context.coordinator.url != url else { return }
    context.coordinator.url = url
    Self.show(url, in: view)
  }

  private static func show(_ url: URL?, in view: SCNView) {
    let built = Self.scene(for: url)
    view.scene = built
    view.pointOfView = built.rootNode.childNode(withName: "macid.camera", recursively: false)
  }

  private static func scene(for url: URL?) -> SCNScene {
    guard let url, let loaded = try? SCNScene(url: url, options: nil) else { return SCNScene() }
    let pivot = SCNNode()
    for child in loaded.rootNode.childNodes { pivot.addChildNode(child) }
    loaded.rootNode.addChildNode(pivot)

    let (minV, maxV) = pivot.boundingBox
    let center = SCNVector3((minV.x + maxV.x) / 2, (minV.y + maxV.y) / 2, (minV.z + maxV.z) / 2)
    let size = max(maxV.x - minV.x, maxV.y - minV.y, maxV.z - minV.z)
    if size > 0 {
      let s = 2 / size
      pivot.scale = SCNVector3(s, s, s)
      pivot.position = SCNVector3(-center.x * s, -center.y * s, -center.z * s)
    }
    let spinner = SCNNode()
    loaded.rootNode.addChildNode(spinner)
    spinner.addChildNode(pivot)
    spinner.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 16)))

    let camera = SCNNode()
    camera.name = "macid.camera"
    camera.camera = SCNCamera()
    camera.camera?.fieldOfView = 30
    camera.position = SCNVector3(0, 0.1, 4.2)
    loaded.rootNode.addChildNode(camera)
    return loaded
  }
}
