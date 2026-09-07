//
//  Entitlements.swift
//  SwiftNZB
//
//  The free tier, and the one thing the UI and the import gate ask: may this customer add another
//  download? Purchases live in `PurchaseStore`; this composes them with a count of completed free
//  downloads.
//
//  The count is a grow-only set of job ids, held in three places at once and read as the union of
//  all of them. Every store available here is last-writer-wins on a whole blob, so a union can only
//  ever lose increments, never invent them — a stale device hands free slots back rather than
//  charging twice, which is the direction to fail in. It also makes recording idempotent by
//  construction: set membership cannot double-count a job whose post-processing re-runs, whose
//  write is torn, or whose history record has since been pruned.
//
//  A determined customer can still reset this by clearing app and iCloud data. Closing that needs a
//  server to hold the count, which this app does not have and is not getting.
//

import Foundation
import Observation
import PurchasePolicy

@MainActor
@Observable
final class Entitlements {
    static let shared = Entitlements()

    /// Job ids whose completion has already spent a free slot.
    private(set) var countedJobIDs: Set<String> = []

    private let countKey = "entitlement.freeDownloads.v1"
    private let defaults = UserDefaults.standard
    private let kvs = NSUbiquitousKeyValueStore.default

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }

    /// Call once at launch. Kicks iCloud so a reinstall on a signed-in device picks the count back
    /// up rather than starting from zero.
    func start() {
        kvs.synchronize()
        load()
    }

    // MARK: - Read model

    var isPro: Bool { PurchaseStore.shared.isPro }

    var freeDownloadsUsed: Int { min(countedJobIDs.count, FreeTier.limit) }

    /// Slots held by downloads that have not finished yet.
    ///
    /// A slot is only spent on completion, so without this a customer at 9 of 10 could import fifty
    /// NZBs and watch every one finish for free. Failed jobs deliberately release their reservation:
    /// a download that never arrived should not cost anything, and a job fails instantly when no
    /// server is configured — holding a slot for that would read as a bug.
    var reservedSlots: Int {
        DownloadManager.shared.jobs.filter {
            !$0.status.isTerminal && !countedJobIDs.contains($0.id.uuidString)
        }.count
    }

    var freeDownloadsRemaining: Int {
        FreeTier.remaining(counted: freeDownloadsUsed, reserved: reservedSlots)
    }

    /// The import gate. Note that an unresolved purchase state counts as *not* Pro and falls back
    /// to the free tier — never the other way round, or turning off Wi-Fi would unlock the app.
    var canAddDownload: Bool { isPro || freeDownloadsRemaining > 0 }

    // MARK: - Recording

    /// Spends a free slot for a finished download. Idempotent per job id.
    ///
    /// Called from `DownloadManager.runPostProcessing` the moment a job reaches `.completed`, beside
    /// the existing `ServerUsageStore.record` call. Recording happens whether or not the customer is
    /// Pro: the set self-bounds at the limit, so a subscriber's completions cost nothing, and
    /// someone whose subscription later lapses has genuinely already had their free downloads.
    func recordCompletedDownload(_ jobID: UUID) {
        // Re-read first: another device may have spent slots since this one last looked, and this is
        // the moment where being out of date actually matters.
        load()
        let id = jobID.uuidString
        guard FreeTier.shouldRecord(id, in: countedJobIDs) else { return }
        countedJobIDs.insert(id)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        let merged = FreeTier.merge(
            decode(kvs.data(forKey: countKey)),
            decode(defaults.data(forKey: countKey)),
            decode(Keychain.password(for: countKey, service: Keychain.entitlementService)?
                .data(using: .utf8))
        )
        countedJobIDs = merged
        // Heal whichever store was behind, so the union does not have to do this work forever.
        if decode(kvs.data(forKey: countKey)) != merged
            || decode(defaults.data(forKey: countKey)) != merged {
            persist()
        }
    }

    private func persist() {
        let sorted = countedJobIDs.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: countKey)
        kvs.set(data, forKey: countKey)
        kvs.synchronize()
        // The keychain copy is the one that has a chance of surviving a delete-and-reinstall. Apple
        // does not document that behaviour and has said not to rely on it, so it is belt-and-braces
        // behind iCloud rather than the primary store.
        if let json = String(data: data, encoding: .utf8) {
            Keychain.setPassword(json, for: countKey, service: Keychain.entitlementService)
        }
    }

    private func decode(_ data: Data?) -> Set<String> {
        guard let data, let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    #if DEBUG
    func debugResetFreeTier() {
        countedJobIDs = []
        defaults.removeObject(forKey: countKey)
        kvs.removeObject(forKey: countKey)
        kvs.synchronize()
        Keychain.deletePassword(for: countKey, service: Keychain.entitlementService)
    }

    func debugSpendFreeSlot() {
        countedJobIDs.insert(UUID().uuidString)
        persist()
    }
    #endif
}
