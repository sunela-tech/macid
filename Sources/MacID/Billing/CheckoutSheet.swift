import SwiftUI

/// In-app payment sheet: Clerk's PricingTable / billing page in a web view, framed natively.
struct CheckoutSheet: View {
  let mode: CheckoutMode
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var loading = true
  @State private var failure: String?
  @State private var reloadID = UUID()

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Label(mode.title, systemImage: mode.symbol)
          .font(.headline)
        if model.plan.isTestMode {
          Text("Test mode")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Palette.amber.opacity(0.2), in: Capsule())
            .foregroundStyle(Palette.amber)
        }
        Spacer()
        if loading && failure == nil { ProgressView().controlSize(.small) }
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      ZStack {
        CheckoutWebView(mode: mode) { event in handle(event) }
          .id(reloadID)
        if let failure {
          VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundStyle(Palette.ir)
            Text(failure)
              .multilineTextAlignment(.center)
              .frame(maxWidth: 420)
            HStack {
              Button("Try Again") {
                self.failure = nil
                loading = true
                reloadID = UUID()
              }
              Button("Open in Browser") { model.plan.openCheckoutInBrowser() }
            }
          }
          .padding(30)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.background)
        }
      }

      Divider()

      HStack(spacing: 8) {
        Image(systemName: "lock.fill")
        Text(model.plan.isTestMode
             ? "Test mode: use card 4242 4242 4242 4242, any future date and any CVC. No real charge."
             : "Payments are processed by Clerk Billing and Stripe. Mac ID never sees your card number.")
        Spacer()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .frame(minWidth: 760, idealWidth: 860, minHeight: 640, idealHeight: 760)
    .onDisappear {
      Task { await model.plan.refresh() }
    }
  }

  private func handle(_ event: CheckoutEvent) {
    switch event {
    case .ready:
      loading = false
    case .changed:
      Task { await model.plan.refresh() }
    case .subscribed:
      Task { await model.plan.checkoutFinished() }
    case let .failed(message):
      loading = false
      failure = message
    case let .deviceToken(token):
      Task { await model.plan.adoptDeviceToken(token) }
    }
  }
}
