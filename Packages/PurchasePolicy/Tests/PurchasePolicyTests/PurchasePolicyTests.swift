import Testing
@testable import PurchasePolicy

@Test func purchasePolicyVersionIsSet() {
    #expect(PurchasePolicy.version == "1.0.0")
}

struct FreeTierTests {
    @Test func remainingSpendsCommittedAndReserved() {
        #expect(FreeTier.remaining(counted: 0, reserved: 0) == 10)
        #expect(FreeTier.remaining(counted: 3, reserved: 0) == 7)
        // The hole reservations exist to close: nine spent plus one in flight leaves nothing, so
        // importing a tenth NZB is refused rather than completing for free.
        #expect(FreeTier.remaining(counted: 9, reserved: 1) == 0)
        #expect(FreeTier.remaining(counted: 10, reserved: 0) == 0)
        // Never negative, however many jobs are queued.
        #expect(FreeTier.remaining(counted: 4, reserved: 50) == 0)
    }

    @Test func mergeIsGrowOnly() {
        let a: Set<String> = ["a", "b"]
        let b: Set<String> = ["b", "c"]
        #expect(FreeTier.merge(a, b) == ["a", "b", "c"])
        // A store that comes back empty must not erase what another one knows. This is the whole
        // reason the counter is a union of sets rather than a last-writer-wins integer.
        #expect(FreeTier.merge(a, []) == a)
        #expect(FreeTier.merge([], a) == a)
        #expect(FreeTier.merge(a, b) == FreeTier.merge(b, a))
        #expect(FreeTier.merge(a, a) == a)
        #expect(FreeTier.merge(a, b).count >= max(a.count, b.count))
        // Three stores at once, which is how the app actually reads.
        #expect(FreeTier.merge(a, b, ["d"]) == ["a", "b", "c", "d"])
    }

    @Test func recordIsIdempotentAndBounded() {
        #expect(FreeTier.shouldRecord("x", in: []))
        // The double-count guard: the same job completing twice spends one slot.
        #expect(!FreeTier.shouldRecord("x", in: ["x"]))
        let full = Set((1...10).map(String.init))
        #expect(full.count == FreeTier.limit)
        #expect(!FreeTier.shouldRecord("new", in: full))
    }
}

struct GrandfatheringTests {
    /// A generic value for the boundary tests below. The tests that pin the *shipping* constant
    /// use `Grandfathering.paywallCutoffBuild` directly.
    private let cutoff = 202610010000

    /// The one that decides whether every existing customer keeps Pro or gets billed.
    ///
    /// These are the real CFBundleVersions the App Store served, read off App Store Connect. A
    /// cutoff derived from the committed Info.plists instead was `2`, which grandfathered nobody:
    /// `agvtool new-version -all` rewrites those plists during the fastlane lane, so every
    /// uploaded build carried a timestamp and no customer has ever reported `originalAppVersion`
    /// "1". That is what these literals are here to stop happening again.
    @Test func theShippingCutoffGrandfathersEveryReleasedBuildAndNothingElse() {
        let real = Grandfathering.paywallCutoffBuild
        // 1.0 and 1.0.1 — the two paid-app builds. Every customer owed a grant reports one of them.
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "202607020045", cutoffBuild: real, isProduction: true))
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "202608220021", cutoffBuild: real, isProduction: true))
        // The boundary is exclusive, so the paywall build itself buys nothing: someone whose first
        // download was 1.1.0 never paid for the app and is not grandfathered.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202609072335", cutoffBuild: real, isProduction: true))
        #expect(real == 202609072335)
        // Every later upload carries a larger timestamp, so no future build grandfathers its own
        // installers. A 12-digit build also has to survive being an Int — it overflows Int32.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202612251200", cutoffBuild: real, isProduction: true))
        #expect(real > Int(Int32.max))
        // ...and no released build counts outside production.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202607020045", cutoffBuild: real, isProduction: false))
    }

    @Test func timestampBuildsCompareAgainstTheCutoff() {
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "202609011200", cutoffBuild: cutoff, isProduction: true))
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202612251200", cutoffBuild: cutoff, isProduction: true))
        // The boundary is exclusive: the paywall build itself is not grandfathered.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202610010000", cutoffBuild: cutoff, isProduction: true))
    }

    @Test func nonProductionEnvironmentsAreNeverGrandfathered() {
        // Sandbox, TestFlight and Xcode all report "1.0". Without this gate every tester and every
        // App Review reviewer would look grandfathered and the purchases would be untestable.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "1.0", cutoffBuild: cutoff, isProduction: false))
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "1", cutoffBuild: cutoff, isProduction: false))
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202609011200", cutoffBuild: cutoff, isProduction: false))
        // ...but the same string in production is a genuine pre-paywall install.
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "1.0", cutoffBuild: cutoff, isProduction: true))
    }

    @Test func unparseableVersionsAreNotGrandfathered() {
        for version in ["", "abc", "v1", " 1", "+202609011200"] {
            #expect(!Grandfathering.isGrandfathered(
                originalAppVersion: version, cutoffBuild: cutoff, isProduction: true),
                "\(version) must not hand out a permanent free Lifetime")
        }
    }

    @Test func parsesTheLeadingIntegerRun() {
        #expect(Grandfathering.buildNumber(fromOriginalAppVersion: "1") == 1)
        // Not 10 — which is what Int(v.filter(\.isNumber)) would give, sneaking under any cutoff
        // for a reason nobody would spot in review.
        #expect(Grandfathering.buildNumber(fromOriginalAppVersion: "1.0") == 1)
        #expect(Grandfathering.buildNumber(fromOriginalAppVersion: "1.1.0") == 1)
        #expect(Grandfathering.buildNumber(fromOriginalAppVersion: "202610010000") == 202610010000)
        #expect(Grandfathering.buildNumber(fromOriginalAppVersion: "") == nil)
        #expect(Grandfathering.buildNumber(fromOriginalAppVersion: "abc") == nil)
    }

    @Test func comparisonIsNumericNotLexicographic() {
        // Apple's own sample code compares originalAppVersion with String `<`, where "9" > "10".
        // Build 9 predates build 10, so both must be grandfathered against a cutoff of 11.
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "9", cutoffBuild: 11, isProduction: true))
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "10", cutoffBuild: 11, isProduction: true))
        #expect("9" > "10")   // the trap this guards against, pinned so the reason stays visible
    }
}
