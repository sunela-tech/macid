import SwiftUI

struct PlanView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Plan").font(.largeTitle.weight(.bold))
          Text(model.plan.detail).foregroundStyle(.secondary)
          if let renewal = model.plan.renewal {
            Text(renewal).font(.callout).foregroundStyle(.secondary)
          }
        }

        HStack(alignment: .top, spacing: 16) {
          planCard(
            title: "Free", price: "$0", symbol: "faceid", tint: .primary, current: !model.plan.isPro,
            lines: [
              ("faceid", "\(AppConfig.freeDailyUnlocks) face unlocks every day"),
              (DeviceAuth.hasTouchID ? "touchid" : "key.fill", "Then Touch ID or your password"),
              ("cube.transparent", "Meshy 7.1 head at setup"),
            ]
          )
          planCard(
            title: "Pro", price: AppConfig.proPriceLabel, symbol: "infinity", tint: Palette.amber, current: model.plan.isPro,
            lines: [
              ("infinity", "Unlimited face unlocks"),
              ("bolt.fill", "Never falls back to a password"),
              ("cube.transparent", "Meshy 7.1 head at setup"),
            ]
          )
        }

        if !AppConfig.isClerkConfigured {
          Label("Clerk isn't configured. Set CLERK_PUBLISHABLE_KEY when building (see README).", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Palette.ir)
        } else if !model.plan.isSignedIn {
          Label("Sign in (top right) to upgrade and keep your plan across Macs.", systemImage: "person.crop.circle")
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 12) {
          if !model.plan.isPro {
            Button {
              model.plan.openCheckout()
            } label: {
              Label("Upgrade to Pro · \(AppConfig.proPriceLabel)", systemImage: "infinity")
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.amber)
          } else {
            Button {
              model.plan.openCheckout()
            } label: {
              Label("Manage Subscription", systemImage: "creditcard")
            }
          }
          Button {
            Task { await model.plan.refresh() }
          } label: {
            Label(model.plan.isRefreshing ? "Checking…" : "Refresh Plan", systemImage: "arrow.clockwise")
          }
          .disabled(model.plan.isRefreshing || !AppConfig.isClerkConfigured)
        }
        .controlSize(.large)

        if let error = model.plan.lastError {
          Text(error).font(.callout).foregroundStyle(Palette.ir)
        }
        Text("Checkout opens in your browser through Clerk Billing. When you come back, Mac ID refreshes your plan automatically.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .padding(28)
      .frame(maxWidth: 820, alignment: .leading)
    }
    .navigationTitle("Plan")
  }

  private func planCard(title: String, price: String, symbol: String, tint: Color, current: Bool, lines: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(title, systemImage: symbol).font(.title2.weight(.semibold)).foregroundStyle(tint)
        Spacer()
        if current {
          Text("Current").font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
        }
      }
      Text(price).font(.system(size: 30, weight: .bold))
      ForEach(lines, id: \.1) { line in
        Label(line.1, systemImage: line.0).font(.callout)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(current ? tint.opacity(0.6) : .clear, lineWidth: 1.5)
    )
  }
}
