//
//  PurchasePolicy.swift
//  PurchasePolicy
//
//  The money rules, as pure functions. Everything here decides who pays, so it lives in a package
//  the app does not need to run: `cd Packages/PurchasePolicy && swift test`. The StoreKit plumbing
//  and the persistence live in the app target and call into this.
//

/// Marker for the PurchasePolicy module.
public enum PurchasePolicy {
    public static let version = "1.0.0"
}

/// The metered free tier: N completed downloads, then a purchase is required.
public enum FreeTier {
    public static let limit = 10

    /// Grow-only merge of the counted-job-ID sets read from the several stores behind this.
    ///
    /// Every store the app has (iCloud KVS, UserDefaults, the synchronizable Keychain) is
    /// last-writer-wins on a whole blob. A union can only ever *lose* increments — never invent
    /// them — so a stale device that syncs late hands the user free slots back rather than
    /// charging them twice. That is the direction to fail in.
    public static func merge(_ sets: Set<String>...) -> Set<String> {
        sets.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// Committed completions plus everything still in flight.
    ///
    /// The reservations matter because a slot is only spent on completion: without them a user at
    /// 9/10 could import fifty NZBs and every one would finish for free.
    public static func remaining(counted: Int, reserved: Int, limit: Int = limit) -> Int {
        max(0, limit - counted - reserved)
    }

    /// Idempotent and self-bounding. Membership is what makes double-counting impossible — a torn
    /// write, a re-entered post-processing pass or a pruned history cannot spend a slot twice —
    /// and the `limit` check is what keeps the set small enough to live in a keychain item forever.
    public static func shouldRecord(_ id: String, in counted: Set<String>, limit: Int = limit) -> Bool {
        counted.count < limit && !counted.contains(id)
    }
}

/// Deciding whether a customer installed the app before it had a paywall, and therefore keeps
/// unlimited downloads at no charge.
public enum Grandfathering {
    /// Builds below this keep Pro for good. This is the CFBundleVersion of the paywall build
    /// itself, and the boundary is exclusive, so everything released before it is grandfathered.
    ///
    /// Read off App Store Connect rather than inferred from the plists, because inferring it got
    /// this wrong once and locked out every paying customer. The three released builds are:
    ///
    ///     1.0     202607020045   (released 2026-08-20, paid app)
    ///     1.0.1   202608220021   (paid app)
    ///     1.1.0   202609072335   (released 2026-09-08, the paywall)
    ///
    /// The committed Info.plists pinned CFBundleVersion to the literal `1` until the 1.1.0 fix,
    /// which is where the earlier cutoff of `2` came from — but `agvtool new-version -all`, which
    /// `update_build_number` drives, rewrites those plists on disk during the lane, so the literal
    /// never reached an uploaded binary. Every build the App Store ever served carried a 12-digit
    /// fastlane timestamp, `originalAppVersion` is one of the two above for every pre-paywall
    /// customer, and a cutoff of `2` therefore grandfathered nobody.
    ///
    /// Still safe against future uploads: every later build carries a larger timestamp, so no
    /// future build can grandfather its own installers.
    public static let paywallCutoffBuild = 202609072335

    /// The leading run of digits in `AppTransaction.originalAppVersion`, as a number.
    ///
    /// On iOS that property is the original **CFBundleVersion**, not the marketing version. Two
    /// shapes reach here in practice: a 12-digit fastlane upload timestamp (`%Y%m%d%H%M`), which is
    /// what every build the App Store has ever served carried, and `"1.0"` (what the sandbox,
    /// TestFlight and Xcode environments always report). `"1"` is handled but has never been seen:
    /// the literal the plists once pinned never survived `agvtool` into an upload.
    ///
    /// Deliberately not `Int(v)` — that rejects `"1.0"` outright — and deliberately not
    /// `Int(v.filter(\.isNumber))`, which turns `"1.0"` into 10 and would sneak under any cutoff.
    public static func buildNumber(fromOriginalAppVersion version: String) -> Int? {
        let digits = version.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// True only for a real App Store install predating the paywall build.
    ///
    /// `isProduction` is not optional. Sandbox, TestFlight and Xcode all report `"1.0"`, which
    /// parses to 1 and sits below every plausible cutoff — so without the environment check every
    /// beta tester and every App Review reviewer would look grandfathered, the in-app purchases
    /// would be untestable, and the app would be rejected for it.
    ///
    /// A value that carries no ordering information at all (`""`, `"abc"`) is **not**
    /// grandfathered: handing out a permanent free Lifetime on a parse failure is the one mistake
    /// here that cannot be taken back.
    public static func isGrandfathered(
        originalAppVersion: String,
        cutoffBuild: Int,
        isProduction: Bool
    ) -> Bool {
        guard isProduction,
              let build = buildNumber(fromOriginalAppVersion: originalAppVersion) else { return false }
        return build < cutoffBuild
    }
}
