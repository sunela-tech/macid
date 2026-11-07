import ClerkKit
import SwiftUI

/// Plan & Billing: plans, subscription, payment methods, invoices and payments, all in the app.
/// Reading uses ClerkKit's native Billing APIs; buying, switching, cancelling and editing cards
/// open Clerk's checkout in an in-app sheet (CheckoutSheet).
struct PlanView: View {
  @Environment(AppModel.self) private var model

  private var plan: PlanStore { model.plan }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        header
        notices
        plansSection
        if plan.isSignedIn {
          subscriptionSection
          paymentMethodsSection
          historySection
        }
      }
      .padding(28)
      .frame(maxWidth: 880, alignment: .leading)
    }
    .navigationTitle("Plan & Billing")
    .task { await plan.refresh() }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Plan & Billing").font(.largeTitle.weight(.bold))
        Text(plan.detail).foregroundStyle(.secondary)
        if let renewal = plan.renewal {
          Text(renewal).font(.callout).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button {
        Task { await plan.refresh() }
      } label: {
        Label(plan.isRefreshing ? "Checking…" : "Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(plan.isRefreshing || !AppConfig.isClerkConfigured)
    }
  }

  @ViewBuilder private var notices: some View {
    if !AppConfig.isClerkConfigured {
      Label("Mac ID was built without a Clerk publishable key, so plans and payments are off.", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(Palette.ir)
    } else if !plan.isSignedIn {
      HStack {
        Label("Sign in to subscribe and see your billing.", systemImage: "person.crop.circle")
        Spacer()
        Button("Sign In") { plan.showAuth = true }
          .buttonStyle(.borderedProminent)
      }
      .padding(14)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    if let error = plan.lastError {
      Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(Palette.ir)
    }
  }

  // MARK: Plans

  private var plansSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Plans", symbol: "square.stack.3d.up")
      HStack(alignment: .top, spacing: 16) {
        planCard(
          title: "Free", price: "$0", period: nil, symbol: "faceid", tint: .primary, current: !plan.isPro,
          lines: [
            ("faceid", "\(AppConfig.freeDailyUnlocks) face unlocks every day"),
            (DeviceAuth.hasTouchID ? "touchid" : "key.fill", "Then Touch ID or your password"),
            ("cube.transparent", "Meshy 7.1 head at setup"),
          ],
          action: nil
        )
        planCard(
          title: proPlan?.name ?? "Pro",
          price: proPlan?.fee?.display ?? "$4.00",
          period: "/month",
          symbol: "infinity", tint: Palette.amber, current: plan.isPro,
          lines: proFeatureLines,
          action: plan.isPro
            ? ("Change or Cancel", "slider.horizontal.3", { plan.presentCheckout(.plans) })
            : ("Subscribe", "creditcard.fill", { plan.presentCheckout(.plans) })
        )
      }
    }
  }

  private var proPlan: BillingPlan? {
    plan.plans.first { $0.slug == AppConfig.proPlanSlug }
  }

  private var proFeatureLines: [(String, String)] {
    var lines: [(String, String)] = [("infinity", "Unlimited face unlocks")]
    for feature in proPlan?.features ?? [] where feature.slug != AppConfig.unlimitedFeatureSlug {
      lines.append(("checkmark", feature.name))
    }
    lines.append(("bolt.fill", "Never falls back to a password"))
    lines.append(("cube.transparent", "Meshy 7.1 head at setup"))
    return lines
  }

  private func planCard(
    title: String, price: String, period: String?, symbol: String, tint: Color, current: Bool,
    lines: [(String, String)], action: (String, String, () -> Void)?
  ) -> some View {
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
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(price).font(.system(size: 30, weight: .bold))
        if let period { Text(period).foregroundStyle(.secondary) }
      }
      ForEach(lines, id: \.1) { line in
        Label(line.1, systemImage: line.0).font(.callout)
      }
      if let action {
        Button(action: action.2) {
          Label(action.0, systemImage: action.1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(current ? .gray : Palette.amber)
        .controlSize(.large)
        .disabled(!AppConfig.isClerkConfigured)
        .padding(.top, 4)
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

  // MARK: Subscription

  @ViewBuilder private var subscriptionSection: some View {
    if let item = plan.proItem {
      VStack(alignment: .leading, spacing: 12) {
        sectionTitle("Subscription", symbol: "arrow.triangle.2.circlepath")
        VStack(spacing: 0) {
          row("Plan", "\(item.plan.name) · \(item.planPeriod == .annual ? "yearly" : "monthly")")
          Divider()
          row("Status", statusText(item))
          if let start = item.periodStart {
            Divider()
            row("Current period", periodText(start, item.periodEnd))
          }
          if let next = plan.subscription?.nextPayment, item.canceledAt == nil {
            Divider()
            row("Next payment", "\(next.amount.display) on \(next.date.formatted(date: .abbreviated, time: .omitted))")
          }
        }
        .card()
        HStack {
          Button {
            plan.presentCheckout(.plans)
          } label: {
            Label("Change or Cancel Plan", systemImage: "slider.horizontal.3")
          }
          Button {
            plan.presentCheckout(.account)
          } label: {
            Label("Billing Details", systemImage: "doc.text")
          }
        }
      }
    }
  }

  private func statusText(_ item: BillingSubscriptionItem) -> String {
    if item.isFreeTrial { return "Free trial" }
    if item.canceledAt != nil { return "Cancelled, active until the period ends" }
    switch item.status {
    case .active: return "Active"
    case .upcoming: return "Starts at the next billing date"
    case .pastDue: return "Payment past due. Update your card."
    case .ended: return "Ended"
    case let .unknown(value): return value.capitalized
    }
  }

  private func periodText(_ start: Date, _ end: Date?) -> String {
    let s = start.formatted(date: .abbreviated, time: .omitted)
    guard let end else { return "Since \(s)" }
    return "\(s) – \(end.formatted(date: .abbreviated, time: .omitted))"
  }

  // MARK: Payment methods

  private var paymentMethodsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        sectionTitle("Payment methods", symbol: "creditcard")
        Spacer()
        Button {
          plan.presentCheckout(.account)
        } label: {
          Label(plan.paymentMethods.isEmpty ? "Add Card" : "Manage", systemImage: "plus.circle")
        }
      }
      if plan.paymentMethods.isEmpty {
        Text("No saved cards. You'll add one at checkout.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(plan.paymentMethods.enumerated()), id: \.element.id) { index, method in
            if index > 0 { Divider() }
            HStack(spacing: 12) {
              Image(systemName: method.walletType == nil ? "creditcard.fill" : "wallet.pass.fill")
                .foregroundStyle(.secondary)
              Text(method.displayName).font(.body.monospacedDigit())
              if method.isDefault == true {
                Text("Default").font(.caption.weight(.semibold))
                  .padding(.horizontal, 6).padding(.vertical, 2)
                  .background(.quaternary, in: Capsule())
              }
              Spacer()
              if method.status == .expired {
                Text("Expired").foregroundStyle(Palette.ir)
              } else if let expiry = method.expiry {
                Text("Expires \(expiry)").foregroundStyle(.secondary).monospacedDigit()
              }
            }
            .padding(.vertical, 10)
          }
        }
        .card()
      }
    }
  }

  // MARK: Invoices and payments

  private var historySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Payment history", symbol: "list.bullet.rectangle")
      if plan.payments.isEmpty && plan.statements.isEmpty {
        Text("No payments yet.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(plan.payments.prefix(12).enumerated()), id: \.element.id) { index, payment in
            if index > 0 { Divider() }
            HStack(spacing: 12) {
              Text((payment.paidAt ?? payment.failedAt ?? payment.updatedAt).formatted(date: .abbreviated, time: .omitted))
                .frame(width: 110, alignment: .leading)
                .monospacedDigit()
              Text(payment.subscriptionItem.plan.name)
              if let card = payment.paymentMethod {
                Text(card.displayName).foregroundStyle(.secondary)
              }
              Spacer()
              Text(payment.amount.display).monospacedDigit()
              paymentStatus(payment.status)
            }
            .padding(.vertical, 9)
          }
        }
        .card()

        if !plan.statements.isEmpty {
          HStack {
            Text("\(plan.statements.count) statement\(plan.statements.count == 1 ? "" : "s") · latest \(plan.statements[0].totals.grandTotal.display) on \(plan.statements[0].timestamp.formatted(date: .abbreviated, time: .omitted))")
              .foregroundStyle(.secondary)
            Spacer()
            Button("View Statements") { plan.presentCheckout(.account) }
          }
          .font(.callout)
        }
      }
    }
  }

  private func paymentStatus(_ status: BillingPaymentStatus) -> some View {
    let (text, color): (String, Color) = switch status {
    case .paid: ("Paid", Palette.ok)
    case .pending: ("Pending", Palette.amber)
    case .failed: ("Failed", Palette.ir)
    case let .unknown(value): (value.capitalized, .secondary)
    }
    return Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .frame(width: 64, alignment: .trailing)
  }

  // MARK: Helpers

  private func sectionTitle(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol).font(.headline)
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      Text(value).multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 9)
  }
}

private extension View {
  func card() -> some View {
    padding(.horizontal, 16)
      .padding(.vertical, 6)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
