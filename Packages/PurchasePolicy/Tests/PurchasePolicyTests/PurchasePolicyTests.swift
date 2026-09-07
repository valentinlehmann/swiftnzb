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
    @Test func theShippingCutoffGrandfathersTheReleasedBuildAndNothingElse() {
        let real = Grandfathering.paywallCutoffBuild
        // Every version released before the paywall shipped as CFBundleVersion "1".
        #expect(Grandfathering.isGrandfathered(
            originalAppVersion: "1", cutoffBuild: real, isProduction: true))
        // The boundary is exclusive, so a cutoff equal to the released build would grandfather
        // nobody. This is the off-by-one that pins the constant at 2 rather than 1.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "1", cutoffBuild: 1, isProduction: true))
        #expect(real > 1)
        // Every later upload carries a 12-digit fastlane timestamp, far above the cutoff, so no
        // future build can grandfather its installers.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "202610010000", cutoffBuild: real, isProduction: true))
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "2", cutoffBuild: real, isProduction: true))
        // ...and not even the released build counts outside production.
        #expect(!Grandfathering.isGrandfathered(
            originalAppVersion: "1", cutoffBuild: real, isProduction: false))
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
