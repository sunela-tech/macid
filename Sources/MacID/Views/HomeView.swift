import SwiftUI

struct HomeView: View {
  @Environment(AppModel.self) private var model
  @Binding var selection: SidebarItem?
  @State private var testing = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header
        tiles
        actions
        if let note = testNote {
          Label(note.text, systemImage: note.symbol)
            .foregroundStyle(note.color)
            .font(.callout.weight(.medium))
        }
        howItWorks
      }
      .padding(28)
      .frame(maxWidth: 900, alignment: .leading)
    }
    .navigationTitle("Mac ID")
  }

  private var header: some View {
    HStack(spacing: 18) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.23, blue: 0.32), Color(red: 0.05, green: 0.06, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
        Image(systemName: "faceid")
          .font(.system(size: 40, weight: .medium))
          .foregroundStyle(.white)
      }
      .frame(width: 76, height: 76)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.enrollment.isEnrolled ? "Mac ID is ready" : "Set up Mac ID")
          .font(.largeTitle.weight(.bold))
        Text(model.enrollment.isEnrolled
             ? "Your Mac locks when it wakes and unlocks when it sees you."
             : "Scan your face once. Meshy 7.1 builds your 3D head from the photo.")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var tiles: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
      StatTile(symbol: "faceid", title: "Face unlocks today",
               value: model.unlimited ? "Unlimited" : "\(model.quota.remaining) of \(model.quota.dailyLimit) left",
               tint: model.unlimited ? Palette.amber : (model.quota.isExhausted ? Palette.ir : .primary)) {
        if !model.unlimited {
          ProgressView(value: Double(model.quota.remaining), total: Double(model.quota.dailyLimit))
            .tint(model.quota.isExhausted ? Palette.ir : Palette.ok)
        }
      }
      StatTile(symbol: model.unlimited ? "infinity" : "creditcard", title: "Plan",
               value: model.unlimited ? "Pro" : "Free", tint: model.unlimited ? Palette.amber : .primary)
      StatTile(symbol: "cube.transparent", title: "3D head (Meshy 7.1)", value: headSummary)
      StatTile(symbol: DeviceAuth.hasTouchID ? "touchid" : "key.fill", title: "Fallback",
               value: DeviceAuth.hasTouchID ? "Touch ID or password" : "Login password")
    }
  }

  private var headSummary: String {
    switch model.headBuilder.phase {
    case .uploading: return "Uploading photo…"
    case .generating: return "Building… \(model.headBuilder.headProgress)%"
    case .comparing: return "Matching scan…"
    case let .failed(message): return message
    default:
      if let match = model.enrollment.head.meshMatch { return "Ready · scan match \(Int(match * 100))%" }
      return model.enrollment.headOBJURL != nil ? "Ready" : "Not built yet"
    }
  }

  private var actions: some View {
    HStack(spacing: 12) {
      if model.enrollment.isEnrolled {
        Button {
          model.lock.lock()
        } label: {
          Label("Lock Now", systemImage: "lock.fill")
        }
        .buttonStyle(.borderedProminent)

        Button {
          testing = true
          Task {
            _ = await model.runUnlockScan()
            testing = false
          }
        } label: {
          Label(testing ? "Scanning…" : "Test Face Unlock", systemImage: "viewfinder")
        }
        .disabled(testing)
      } else {
        Button {
          selection = .face
        } label: {
          Label("Scan My Face", systemImage: "faceid")
        }
        .buttonStyle(.borderedProminent)
      }
      if !model.unlimited {
        Button {
          model.plan.openCheckout()
        } label: {
          Label("Get Pro · \(AppConfig.proPriceLabel)", systemImage: "infinity")
        }
      }
    }
    .controlSize(.large)
  }

  private var testNote: (text: String, symbol: String, color: Color)? {
    guard case let .finished(outcome) = model.scanStatus else { return nil }
    if case let .matched(score) = outcome {
      return ("Matched (confidence \(Int(score * 100))%)", "checkmark.seal.fill", Palette.ok)
    }
    return (outcome.message, "exclamationmark.triangle.fill", Palette.ir)
  }

  private var howItWorks: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("How Mac ID works").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          Image(systemName: "camera.fill").foregroundStyle(Palette.ir)
          Text("Your Mac's camera reads your face like a depth sensor: Vision maps landmarks and dots across it.")
        }
        GridRow {
          Image(systemName: "cube.transparent").foregroundStyle(Palette.ir)
          Text("At setup, Meshy 7.1 builds your whole head from one photo, and a Meshy 6 Lite scan must match it.")
        }
        GridRow {
          Image(systemName: "lock.open.fill").foregroundStyle(Palette.ok)
          Text("Each unlock runs on-device in about a second. Free: \(AppConfig.freeDailyUnlocks) a day, then Touch ID or your password.")
        }
        GridRow {
          Image(systemName: "exclamationmark.shield").foregroundStyle(.secondary)
          Text("A regular webcam has no real depth sensor, so this is a convenience lock, not a security boundary. macOS keeps its own password lock.")
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)
    }
    .padding(.top, 8)
  }
}
