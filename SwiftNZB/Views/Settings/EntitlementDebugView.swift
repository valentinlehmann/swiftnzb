//
//  EntitlementDebugView.swift
//  SwiftNZB
//
//  Debug-only. The whole file compiles to nothing in Release — and TestFlight is Release — so the
//  reset controls provably cannot ship. To reset a device that has a TestFlight build on it,
//  install the Debug build over the top: same bundle id, same keychain item, same counter.
//
//  The App Transaction rows exist because the values that decide grandfathering cannot be guessed:
//  the sandbox, TestFlight and Xcode all report originalAppVersion "1.0". Read them here.
//

#if DEBUG
import SwiftUI

struct EntitlementDebugView: View {
    @State private var entitlements = Entitlements.shared
    @State private var purchases = PurchaseStore.shared
    @State private var appTransaction = "…"

    var body: some View {
        Form {
            Section("Entitlement") {
                StatRow("Pro", entitlements.isPro ? "yes" : "no")
                StatRow("Grandfathered", purchases.isGrandfathered ? "yes" : "no")
                StatRow("Source", purchases.activeProductID ?? "none")
                StatRow("Products loaded", "\(purchases.products.count)")
            }
            Section("Free tier") {
                StatRow("Used", "\(entitlements.freeDownloadsUsed)")
                StatRow("Reserved", "\(entitlements.reservedSlots)")
                StatRow("Remaining", "\(entitlements.freeDownloadsRemaining)")
            }
            Section {
                Text(verbatim: appTransaction)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } header: {
                Text("App Transaction")
            } footer: {
                Text("What this device actually reports. Grandfathering needs a production environment, so the paywall is what a simulator, TestFlight build or reviewer should see.")
            }
            Section {
                Button("Spend One Free Slot") { entitlements.debugSpendFreeSlot() }
                Button("Reset Free Downloads", role: .destructive) { entitlements.debugResetFreeTier() }
                Button("Force Grandfathered") { purchases.debugSetGrandfathered(true) }
                Button("Revoke Grandfather Grant", role: .destructive) {
                    purchases.debugSetGrandfathered(false)
                }
            }
        }
        .navigationTitle("Entitlement")
        .navigationBarTitleDisplayMode(.inline)
        .task { appTransaction = await PurchaseStore.debugAppTransactionSummary() }
    }
}
#endif
