//
//  PurchaseStore.swift
//  SwiftNZB
//
//  Everything StoreKit: the three products, the purchase, the restore, and the entitlement derived
//  from them. Also owns the grandfathering verdict, because that comes from `AppTransaction`, which
//  is StoreKit too. No developer server is involved at any point — StoreKit 2 verifies on device.
//
//  The free-download counter lives next door in `Entitlements`, which reads `isPro` from here.
//

import Foundation
import Observation
import StoreKit
import PurchasePolicy

@MainActor
@Observable
final class PurchaseStore {
    static let shared = PurchaseStore()

    /// Product identifiers, as configured in App Store Connect and in SwiftNZB.storekit. These are
    /// permanent — App Store Connect will not let an identifier be reused, so they are never renamed.
    enum ProductID: String, CaseIterable {
        case yearly = "de.valentinlehmann.swiftnzb.pro.yearly"
        case monthly = "de.valentinlehmann.swiftnzb.pro.monthly"
        case lifetime = "de.valentinlehmann.swiftnzb.pro.lifetime"

        /// The two auto-renewables. Lifetime is a non-consumable and has nothing to manage or cancel.
        var isSubscription: Bool { self != .lifetime }
    }

    /// Three states on purpose. `.unknown` means "we have not resolved this yet" and falls back to
    /// the free-download counter — it must never be read as Pro, or turning off Wi-Fi would unlock
    /// the app.
    enum Entitlement: Equatable { case unknown, free, pro }

    enum LoadState: Equatable { case idle, loading, loaded, failed }

    enum RestoreOutcome: Equatable { case restored, nothingFound, cancelled, failed(String) }

    private(set) var entitlement: Entitlement
    /// Ordered for display: yearly (the recommended one) first, then monthly, then the one-time buy.
    private(set) var products: [Product] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isPurchasing = false
    /// nil while free, and also while grandfathered — nothing was purchased in that case.
    private(set) var activeProductID: String?
    /// Renewal or expiry date of an active subscription, when there is one.
    private(set) var activeExpirationDate: Date?
    private(set) var isGrandfathered: Bool

    var isPro: Bool { entitlement == .pro }

    var activeProduct: ProductID? { activeProductID.flatMap(ProductID.init(rawValue:)) }

    func product(_ id: ProductID) -> Product? { products.first { $0.id == id.rawValue } }

    private var updatesTask: Task<Void, Never>?
    private var hasResolvedGrandfathering = false
    private let defaults = UserDefaults.standard
    private static let cachedProKey = "entitlement.cachedPro.v1"
    private static let grandfatheredKey = "entitlement.grandfathered.v1"
    private static let grandfatheredAccount = "entitlement.grandfathered.v1"

    private init() {
        // Read the last known answers synchronously, before any view renders. A cold launch through
        // .onOpenURL can reach the import gate before the async StoreKit read finishes, and an app
        // update must not flash a paywall at someone who already paid. A successful resolution
        // below overwrites both — this is a starting value, not an override.
        let granted = defaults.bool(forKey: Self.grandfatheredKey)
            || Keychain.password(for: Self.grandfatheredAccount,
                                 service: Keychain.entitlementService) == "1"
        isGrandfathered = granted
        entitlement = (granted || defaults.bool(forKey: Self.cachedProKey)) ? .pro : .unknown
    }

    // MARK: - Lifecycle

    /// Call once, from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// The `Transaction.updates` listener has to exist as soon as the app launches: unfinished
    /// transactions are delivered exactly once shortly afterwards and are lost if nothing is
    /// listening. That covers an Ask-to-Buy approval, a purchase made on another device, and — the
    /// one that matters here — an offer code redeemed in the App Store or through a link, which
    /// hands the app no transaction of its own.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.apply(update)
            }
        }
        Task {
            await resolveGrandfathering()
            await refreshEntitlement()
            await loadProducts()
        }
    }

    // MARK: - Products

    func loadProducts() async {
        guard products.isEmpty else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            // Keep the declared order rather than whatever the App Store returns.
            products = ProductID.allCases.compactMap { id in loaded.first { $0.id == id.rawValue } }
            // An empty array with no error is the classic symptom of the Paid Applications
            // agreement not being active yet, so it is a failure for display purposes.
            loadState = products.isEmpty ? .failed : .loaded
        } catch {
            products = []
            loadState = .failed
        }
    }

    // MARK: - Entitlement

    /// Re-derives the entitlement from StoreKit's on-device records.
    ///
    /// Also the only cover for a subscription simply lapsing: a renewal produces a transaction, so
    /// the updates listener sees it, but an expiry produces none. Called on every return to
    /// foreground for that reason.
    func refreshEntitlement() async {
        var found: Transaction?
        // currentEntitlements emits every non-consumable plus the latest transaction for each
        // auto-renewable that is subscribed or in a billing grace period, and omits anything
        // refunded or revoked — so one pass covers monthly, yearly and lifetime alike. A
        // family-shared entitlement arrives here like any other and is deliberately treated as
        // plain Pro.
        for await result in Transaction.currentEntitlements {
            // Only verified transactions grant anything. Matching on product id alone would let an
            // unverified transaction unlock the app.
            guard case let .verified(transaction) = result,
                  ProductID(rawValue: transaction.productID) != nil else { continue }
            // Prefer a lifetime purchase if the customer somehow holds both.
            if found == nil || transaction.productID == ProductID.lifetime.rawValue {
                found = transaction
            }
        }

        if let found {
            activeProductID = found.productID
            activeExpirationDate = found.expirationDate
            setPro(true)
        } else if isGrandfathered {
            activeProductID = nil
            activeExpirationDate = nil
            setPro(true)
        } else {
            activeProductID = nil
            activeExpirationDate = nil
            setPro(false)
        }
    }

    private func setPro(_ pro: Bool) {
        entitlement = pro ? .pro : .free
        // Cache positives only. Clearing on a resolved negative is what makes a refund or an
        // expiry actually re-lock the app.
        defaults.set(pro, forKey: Self.cachedProKey)
    }

    private func apply(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else { return }
        // Finish it either way: an unfinished transaction is redelivered forever.
        await transaction.finish()
        guard ProductID(rawValue: transaction.productID) != nil else { return }
        await refreshEntitlement()
    }

    // MARK: - Purchase

    /// The caller performs the purchase and this handles the outcome. `perform` exists so the
    /// paywall can pass its `@Environment(\.purchase)` action, which binds the confirmation sheet to
    /// the scene the tap came from — something `product.purchase()` cannot do on iPad. Keeping it a
    /// closure is also what keeps SwiftUI out of this file, as in every other service here.
    ///
    /// Returns a message to show, or nil when there is nothing to say (a success and a user
    /// cancellation are both silent).
    func buy(_ product: Product,
             perform: (Product) async throws -> Product.PurchaseResult) async -> String? {
        guard !isPurchasing else { return nil }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await perform(product) {
            case .success(let result):
                await apply(result)
                return nil
            case .userCancelled:
                return nil
            case .pending:
                // Ask to Buy, or a bank confirmation. The transaction arrives through the updates
                // listener whenever it is approved, possibly days later.
                return String(localized: "This purchase needs approval. SwiftNZB Pro unlocks as soon as it goes through.")
            @unknown default:
                return nil
            }
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Restore

    /// `AppStore.sync()` is the StoreKit 2 restore. It prompts for Apple Account credentials, so it
    /// runs only from an explicit tap — never at launch.
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch is CancellationError {
            return .cancelled
        } catch {
            // A cancelled credential prompt surfaces as a plain error; re-reading below is still
            // worth doing, since the entitlement may already be on the device.
            await refreshEntitlement()
            if isPro { return .restored }
            return .failed(error.localizedDescription)
        }
        // Re-resolve grandfathering too: on a new device this is how a customer who never paid
        // anything gets their grant back, and telling them "no purchase found" would be both
        // alarming and untrue.
        hasResolvedGrandfathering = false
        await resolveGrandfathering()
        await refreshEntitlement()
        return isPro ? .restored : .nothingFound
    }

    // MARK: - Grandfathering

    /// Grants Pro permanently to anyone whose Apple Account first downloaded SwiftNZB before the
    /// paywall existed.
    ///
    /// Nothing is cached on failure. `AppTransaction.shared` throws when the device is offline or
    /// not signed in to the App Store, and a customer updating from a pre-paywall build starts with
    /// all ten free downloads in hand — so the check has many launches to succeed before anything
    /// is ever refused. `AppTransaction.refresh()` is deliberately not called here: it presents an
    /// Apple Account sign-in sheet, which is only acceptable behind the Restore button.
    private func resolveGrandfathering() async {
        guard !isGrandfathered, !hasResolvedGrandfathering else { return }
        guard let result = try? await AppTransaction.shared,
              case let .verified(appTransaction) = result else { return }
        hasResolvedGrandfathering = true
        guard Grandfathering.isGrandfathered(
            originalAppVersion: appTransaction.originalAppVersion,
            cutoffBuild: Grandfathering.paywallCutoffBuild,
            isProduction: appTransaction.environment == .production
        ) else { return }
        grant()
    }

    private func grant() {
        isGrandfathered = true
        defaults.set(true, forKey: Self.grandfatheredKey)
        // Mirrored into the synchronizable keychain so the grant follows the customer to a new
        // device without a round trip to the App Store.
        Keychain.setPassword("1", for: Self.grandfatheredAccount,
                             service: Keychain.entitlementService)
        setPro(true)
    }

    #if DEBUG
    func debugSetGrandfathered(_ on: Bool) {
        if on {
            grant()
        } else {
            isGrandfathered = false
            hasResolvedGrandfathering = false
            defaults.removeObject(forKey: Self.grandfatheredKey)
            Keychain.deletePassword(for: Self.grandfatheredAccount,
                                    service: Keychain.entitlementService)
            Task { await refreshEntitlement() }
        }
    }

    /// What `AppTransaction` actually reports on this device. The sandbox, TestFlight and Xcode all
    /// hardcode `originalAppVersion` to "1.0", so these are values to read rather than assume.
    static func debugAppTransactionSummary() async -> String {
        guard let result = try? await AppTransaction.shared else { return "unavailable" }
        guard case let .verified(app) = result else { return "unverified" }
        let build = Grandfathering.buildNumber(fromOriginalAppVersion: app.originalAppVersion)
        return """
        originalAppVersion \(app.originalAppVersion)
        parsed \(build.map(String.init) ?? "nil") · cutoff \(Grandfathering.paywallCutoffBuild)
        environment \(app.environment.rawValue)
        """
    }
    #endif
}
