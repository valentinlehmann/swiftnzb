//
//  PaywallView.swift
//  SwiftNZB
//
//  The Pro offer, and what Pro looks like once it is on — one screen, two states. Reachable from
//  Settings at any time (App Review has to be able to find the purchases) and presented as a sheet
//  when a download is blocked.
//
//  Prices always come from StoreKit. A hardcoded price would be wrong in every currency but one,
//  and would eventually contradict App Store Connect.
//

import StoreKit
import SwiftUI
import PurchasePolicy

struct PaywallView: View {
    /// Changes the header only. `.limitReached` is what a blocked import shows.
    enum Reason { case offer, limitReached }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var purchases = PurchaseStore.shared
    @State private var entitlements = Entitlements.shared
    @State private var selected: PurchaseStore.ProductID = .yearly
    @State private var isRedeeming = false
    @State private var isManagingSubscription = false
    @State private var isRestoring = false
    @State private var message: String?

    private let reason: Reason
    /// True when presented as a sheet, so a Close button appears. Same split as `AddServerView`.
    private let isModal: Bool

    init(reason: Reason = .offer, isModal: Bool = false) {
        self.reason = reason
        self.isModal = isModal
    }

    /// Apple's standard EULA. The app ships no terms of its own, and because App Store Connect
    /// shows no licence link when the standard agreement applies, the app has to carry it.
    private static let termsOfUse = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Must match the Privacy Policy URL set in App Store Connect exactly — a dead link here is a
    /// rejection. Served from docs/privacy/ via GitHub Pages.
    private static let privacyPolicy = URL(
        string: "https://valentinlehmann.github.io/swiftnzb/privacy/")!

    var body: some View {
        List {
            if entitlements.isPro {
                activeSection
            } else {
                headerSection
                featureSection
                switch purchases.loadState {
                case .loaded: planSection; ctaSection
                case .failed: unavailableSection
                case .idle, .loading: loadingSection
                }
            }
            actionsSection
        }
        .navigationTitle("SwiftNZB Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await purchases.loadProducts() }
        .offerCodeRedemption(isPresented: $isRedeeming) { _ in
            // The sheet hands back no transaction — a redemption arrives through
            // PurchaseStore's Transaction.updates listener, which is why that listener is
            // started at launch rather than here.
        }
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .alert("SwiftNZB Pro", isPresented: .init(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button(entitlements.isPro ? "Done" : "Not Now") { dismiss() }
                }
            }
        }
    }

    // MARK: - Offer

    private var headerSection: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: reason == .limitReached ? "checkmark.circle" : "infinity")
                    .font(.largeTitle)
                    .foregroundStyle(reason == .limitReached ? Color.green : Color.accentColor)
                Text(reason == .limitReached
                     ? "You have used your free downloads"
                     : "Unlimited downloads")
                    .font(.headline)
                Text(reason == .limitReached
                     ? "SwiftNZB Pro removes the limit. Everything you have already downloaded stays where it is."
                     : "SwiftNZB is free for the first 10 downloads. Pro removes the limit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var featureSection: some View {
        Section {
            feature("Unlimited downloads")
            feature("Everything else stays exactly as it is")
            feature("One purchase covers all your devices")
        }
    }

    private func feature(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            CheckboxView(isChecked: true)
        }
    }

    private var planSection: some View {
        Section {
            ForEach(PurchaseStore.ProductID.allCases, id: \.self) { id in
                if let product = purchases.product(id) {
                    planRow(id, product)
                }
            }
        } footer: {
            Text(legalText)
        }
    }

    @ViewBuilder
    private func planRow(_ id: PurchaseStore.ProductID, _ product: Product) -> some View {
        let isSelected = selected == id
        Button {
            selected = id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(Self.title(for: id))
                            .font(.headline)
                        if id == .yearly { bestValueChip }
                    }
                    if let secondary = Self.secondaryLine(for: id, product) {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // The full price is the prominent element; the per-month figure above is the
                // smaller one. App Review checks that ordering.
                Text(verbatim: product.displayPrice)
                    .font(.headline)
                    .monospacedDigit()
                CheckboxView(isChecked: isSelected)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.08) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// Same numbers as `StatusChip`, so the two capsules in the app look identical.
    private var bestValueChip: some View {
        Text("Best value")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private var ctaSection: some View {
        Section {
            Button {
                Task { await buy() }
            } label: {
                HStack {
                    Spacer()
                    if purchases.isPurchasing {
                        ProgressView()
                    } else {
                        Text(selected == .lifetime ? "Buy SwiftNZB Pro" : "Subscribe")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(purchases.isPurchasing || purchases.product(selected) == nil)
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var unavailableSection: some View {
        Section {
            Button("Try Again") {
                Task { await purchases.loadProducts() }
            }
        } footer: {
            Text("The App Store did not return the prices. Check your connection and try again.")
        }
    }

    // MARK: - Active

    private var activeSection: some View {
        Section {
            LabeledContent("Plan") { Text(Self.activeTitle(purchases)) }
            if let expires = purchases.activeExpirationDate {
                // Not "Renews": that would be wrong for a subscription whose auto-renew is off.
                // The end of the paid period is true in both cases; Manage Subscription has the
                // detail.
                StatRow("Valid Until", expires.formatted(date: .abbreviated, time: .omitted))
            }
        } footer: {
            Text(purchases.isGrandfathered
                 ? "You installed SwiftNZB before it had a purchase, so Pro is yours for good. There is nothing to renew and nothing to cancel."
                 : "Thanks. Downloads are unlimited on every device signed in to your Apple Account.")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            // Only a real subscription has anything to manage. A grandfathered customer has no
            // subscription, so the row would lead nowhere.
            if purchases.activeProduct?.isSubscription == true {
                Button {
                    isManagingSubscription = true
                } label: {
                    Label("Manage Subscription", systemImage: "creditcard")
                }
            }
            Button {
                isRedeeming = true
            } label: {
                Label("Redeem Code", systemImage: "gift")
            }
            Button {
                Task { await restore() }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                    if isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring)
            Link(destination: Self.termsOfUse) {
                Label("Terms of Use", systemImage: "doc.text")
            }
            Link(destination: Self.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        } footer: {
            if !entitlements.isPro {
                Text("^[\(entitlements.freeDownloadsRemaining) free download](inflect: true) left.")
            }
        }
    }

    // MARK: - Actions plumbing

    private func buy() async {
        guard let product = purchases.product(selected) else { return }
        if let problem = await purchases.buy(product, perform: { try await purchase($0) }) {
            message = problem
        } else if entitlements.isPro, isModal {
            dismiss()
        }
    }

    private func restore() async {
        isRestoring = true
        let outcome = await purchases.restore()
        isRestoring = false
        switch outcome {
        case .restored:
            if isModal { dismiss() }
        case .cancelled:
            break
        case .nothingFound:
            message = String(localized: "No purchase found for this Apple Account.")
        case .failed(let reason):
            message = reason
        }
    }

    // MARK: - Copy

    private static func title(for id: PurchaseStore.ProductID) -> LocalizedStringKey {
        switch id {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }

    /// The per-unit line. Interpolating a `String` into a `LocalizedStringKey` becomes `%@`, so no
    /// number formatter runs and the locale thousands separator that `Text("\(int)")` would add
    /// cannot appear — `displayPrice` is already formatted by StoreKit for the customer's storefront.
    private static func secondaryLine(for id: PurchaseStore.ProductID,
                                      _ product: Product) -> LocalizedStringKey? {
        switch id {
        case .yearly:
            let monthly = (product.price / 12).formatted(product.priceFormatStyle)
            return "\(monthly) per month, billed yearly"
        case .monthly:
            return "Billed monthly"
        case .lifetime:
            return "One-time purchase"
        }
    }

    private var legalText: LocalizedStringKey {
        switch selected {
        case .lifetime:
            return "Lifetime is a one-time purchase. Nothing renews."
        case .monthly, .yearly:
            let price = purchases.product(selected)?.displayPrice ?? ""
            return selected == .yearly
                ? "Renews automatically at \(price) per year until you cancel. Cancel any time in the App Store."
                : "Renews automatically at \(price) per month until you cancel. Cancel any time in the App Store."
        }
    }

    private static func activeTitle(_ purchases: PurchaseStore) -> LocalizedStringKey {
        if purchases.isGrandfathered { return "Lifetime, included" }
        switch purchases.activeProduct {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        case nil: return "Pro"
        }
    }
}
