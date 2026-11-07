import SwiftUI

struct FaceSetupView: View {
  @Environment(AppModel.self) private var model
  @AppStorage(Prefs.buildHeadKey) private var buildHead = true
  @State private var confirmReset = false

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      cameraColumn
      headColumn
    }
    .padding(28)
    .navigationTitle("Face & Head")
    .task {
      await model.scanner.acquire()
      await model.headBuilder.refreshCredits()
    }
    .onDisappear { model.scanner.release() }
  }

  // MARK: Camera + enrollment

  private var capturing: Bool {
    switch model.enrollStep {
    case .starting, .capturing: true
    default: false
    }
  }

  private var cameraColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black)
        if model.scanner.isRunning {
          CameraPreview(session: model.scanner.camera.session)
          DepthDotsOverlay(sample: model.scanner.latest, imageSize: model.scanner.imageSize,
                           matched: model.enrollStep == .done, scanning: true)
        } else {
          VStack(spacing: 10) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text(model.scanner.cameraError ?? "Starting camera…").multilineTextAlignment(.center)
          }
          .foregroundStyle(.secondary)
          .padding()
        }
        VStack {
          Spacer()
          HStack {
            Label(model.scanner.latest == nil ? "No face" : "Face found", systemImage: model.scanner.latest == nil ? "eye.slash" : "faceid")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(.ultraThinMaterial, in: Capsule())
            Spacer()
          }
          .padding(12)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .aspectRatio(4 / 3, contentMode: .fit)
      .frame(minWidth: 360)

      enrollStatus

      Toggle(isOn: $buildHead) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Build my 3D head with Meshy")
          Text("Meshy 7.1 head + Meshy 6 Lite match · \(AppConfig.headModelCredits + AppConfig.scanModelCredits) credits")
            .font(.caption).foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 12) {
        Button {
          Task { await model.enroll() }
        } label: {
          Label(model.enrollment.isEnrolled ? "Scan Again" : "Scan My Face", systemImage: "faceid")
        }
        .buttonStyle(.borderedProminent)
        .disabled(capturing || !model.scanner.isRunning)

        if model.enrollment.isEnrolled {
          Button("Remove Face…", role: .destructive) { confirmReset = true }
        }
      }
      .controlSize(.large)
      .confirmationDialog("Remove your face and 3D head from this Mac?", isPresented: $confirmReset) {
        Button("Remove", role: .destructive) { model.resetEnrollment() }
      } message: {
        Text("Mac ID will stop unlocking with your face until you scan again.")
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder private var enrollStatus: some View {
    switch model.enrollStep {
    case .idle:
      Text(model.enrollment.isEnrolled ? "Your face is set up." : "Look straight at the camera in even light, then press Scan My Face.")
        .foregroundStyle(.secondary)
    case .starting:
      Label("Hold still…", systemImage: "viewfinder")
    case let .capturing(percent):
      VStack(alignment: .leading, spacing: 6) {
        Label("Mapping your face… move your head slightly", systemImage: "viewfinder")
        ProgressView(value: Double(percent), total: 100).tint(Palette.ir)
      }
    case .done:
      Label("Face saved. Mac ID can unlock this Mac.", systemImage: "checkmark.seal.fill").foregroundStyle(Palette.ok)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.ir)
    }
  }

  // MARK: Meshy head

  private var headColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.14), Color(red: 0.03, green: 0.03, blue: 0.05)], startPoint: .top, endPoint: .bottom))
        if let url = model.enrollment.headModelURL {
          HeadModelView(url: url)
        } else if let thumb = model.enrollment.head.thumbnailURL, let url = URL(string: thumb) {
          AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
            .padding(30)
        } else {
          VStack(spacing: 10) {
            Image(systemName: "cube.transparent").font(.system(size: 54, weight: .light))
            Text("Your 3D head appears here").foregroundStyle(.secondary)
          }
          .foregroundStyle(.white.opacity(0.8))
        }
      }
      .aspectRatio(4 / 3, contentMode: .fit)
      .frame(minWidth: 320)

      VStack(alignment: .leading, spacing: 10) {
        progressRow("Meshy 7.1 · full head", value: model.headBuilder.headProgress, done: model.enrollment.headOBJURL != nil)
        progressRow("Meshy 6 Lite · depth scan", value: model.headBuilder.liteProgress, done: model.enrollment.head.liteOBJ != nil)
        if let match = model.enrollment.head.meshMatch {
          let ok = match >= AppConfig.meshMatchThreshold
          Label("6 Lite scan matches the 7.1 head: \(Int(match * 100))%", systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Palette.ok : Palette.amber)
          if !ok {
            Text("The two models differ more than expected. Scan again facing the camera in even light.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if case let .failed(message) = model.headBuilder.phase {
          Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.ir).font(.callout)
        }
        if let credits = model.headBuilder.credits {
          Text("Meshy credits left: \(credits)").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func progressRow(_ title: String, value: Int, done: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title).font(.callout.weight(.medium))
        Spacer()
        Text(done ? "Done" : model.headBuilder.isBusy ? "\(value)%" : "–")
          .font(.callout.monospacedDigit())
          .foregroundStyle(done ? Palette.ok : .secondary)
      }
      ProgressView(value: Double(done ? 100 : value), total: 100)
        .tint(done ? Palette.ok : Palette.ir)
    }
  }
}
