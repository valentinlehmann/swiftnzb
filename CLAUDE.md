# CLAUDE.md — SwiftNZB

Guidance for AI agents (and humans) working in this repo. Read this before making changes.

## What this is

**SwiftNZB** is a native SwiftUI app for **iPhone + iPad** that downloads **NZB files from
Usenet (NNTP)**: it parses an NZB, downloads article segments over many parallel TLS
connections, decodes **yEnc**, reassembles files, **verifies/repairs with PAR2**, **extracts
RAR** archives, and saves the result to the Files app. It shows a **Live Activity** (Lock
Screen + Dynamic Island) for the active download. Built with **XcodeGen + Fastlane**,
mirroring the author's **iobs** / Pagrr conventions.

- Min OS: **iOS 26**. Swift 6, SwiftUI, `@Observable` (Observation).
- Bundle IDs: app `de.valentinlehmann.swiftnzb`, widget `…swiftnzb.widgets`.
- Team `68BLC88PQ9`. Apple ID `info@valentinlehmann.de`.
- Distribution target: **public App Store** → no GPL code (PAR2 is clean-room, see below).

## Build / run / verify

The Xcode project is **generated** — never edit `SwiftNZB.xcodeproj` directly; edit
`project.yml`, then:

```bash
xcodegen generate
xcodebuild -project SwiftNZB.xcodeproj -scheme SwiftNZB \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

- After adding/removing/renaming **files**, run `xcodegen generate` before building (sources
  are globbed by path in `project.yml`).
- Engine logic lives in **local SPM packages** (`Packages/DownloadEngine`, `Packages/PAR2Kit`)
  — pure, deterministic, and unit-tested without the app: `cd Packages/DownloadEngine &&
  swift test` (likewise PAR2Kit). This is a deliberate deviation from iobs (which has no
  packages); the protocol/decoder/Reed-Solomon math demands isolated tests.
- Treat `** BUILD SUCCEEDED **` as success.

## Architecture

MVVM + `@Observable` singletons. UI/services live in the app target (`SwiftNZB/`); all NNTP +
decode + PAR2 specifics are isolated in the two local packages and surfaced to the UI through
the `DownloadManager` facade (the app's seam). Views/VMs use only the plain `Types/`.

```
project.yml                 XcodeGen config (2 targets: SwiftNZB, SwiftNZBWidgets)
Localizable.xcstrings        String catalog (auto-extracted; en + de) — don't hand-edit
fastlane/{Fastfile,Appfile,Matchfile}
Packages/DownloadEngine/     NNTP transport, yEnc, CRC32, scheduler, pool, assembler, checkpoint
Packages/PAR2Kit/            Clean-room PAR2 parse / verify / Reed-Solomon repair (no GPL)
SwiftNZB/
  Types/                     Plain Codable models (no logic); DownloadActivityAttributes is shared
  Services/                  @Observable @MainActor singletons (DownloadManager, ServerStore, …)
  ViewModels/                One @Observable VM per screen
  Views/                     Screens + Views/Components/ (reusable)
  Intents/                   App Intents: DownloadIntents (shared into widget), QueueIntents
                             (app-only: Siri/Shortcuts actions + AppShortcutsProvider)
SwiftNZBWidgets/             Live Activity (WidgetKit)
```

### Download engine (CRITICAL — read before touching networking)

- iOS **cannot** background raw-socket (NNTP) downloads — `URLSession` background mode is
  HTTP-only; `NWConnection` sockets suspend when the app backgrounds. Large downloads need the
  app foregrounded. Background support is best-effort: `beginBackgroundTask` wind-down +
  `BGProcessingTask` opportunistic resume, with checkpoint/resume making it safe.
- Concurrency: a fixed pool of `maxConnections` long-lived workers in one `withTaskGroup`,
  each owning one authenticated `NNTPConnection` actor, pulling `WorkItem`s from a shared
  `SegmentScheduler` actor. Reuses the auth handshake; structured cancellation.
- Assembly streams to disk: positional `FileHandle` writes into one sparse `.part` file per
  NZB file using each segment's `=ypart` byte offset. The scratch file IS the output; finalize
  renames. Idempotent → resume-safe.
- **Mobile network resilience is first-class**: `NWPathMonitor` parks/resumes on
  connectivity changes; per-request stall timeouts kill half-open cellular sockets; per-segment
  exponential backoff + jitter; adaptive active-connection count under degraded links; smoothed
  throughput/ETA. The segment is the atomic, idempotent, resumable unit — a flaky link degrades
  throughput but never corrupts state.

### PAR2 (CRITICAL — App Store licensing)

- PAR2 verify+repair is a **clean-room Swift implementation** in `Packages/PAR2Kit`. Do **not**
  introduce `par2cmdline`/`libpar2` or any GPL code — GPL is incompatible with App Store
  distribution. UnRAR (via the `Unrar.swift` SPM dependency) IS acceptable for the App Store.

### Purchases / Pro entitlement (CRITICAL — money path)

- **StoreKit 2 only, no server.** One entitlement ("Pro"), three products (monthly, yearly,
  lifetime) in `PurchaseStore`. Prices come from `product.displayPrice` — never hardcode a price,
  in the UI or in metadata. Nothing but StoreKit may unlock Pro: no licence keys, no codes of our
  own (Guideline 3.1.1). Coupons are Apple **offer codes**.
- **A free slot is consumed when a job reaches `.completed`**, on the one line beside the existing
  `ServerUsageStore.record(...)` call in `DownloadManager.runPostProcessing`. Never hook the
  counter to `startJob`/`startNextIfNeeded` (pause is cancel-then-rerun, so those fire many times
  per download) and never to `resume(_:)` (a `.failed` job resumed from History is a retry of the
  same download). Consumption is keyed by job id and idempotent.
- **The counter is not derivable from history.** `jobs.v1.json` is renamed and treated as empty
  when corrupt, and `pruneHistory()` drops old jobs. It lives in `Entitlements` as a grow-only set
  of job ids in iCloud KVS + UserDefaults + the synchronizable Keychain, read as the **union** of
  all three. Do NOT copy `ServerStore.load()`'s `kvs.data ?? defaults.data` shape — that is
  whole-blob last-writer-wins and silently discards local truth. An empty or failed read must
  never mean "limit reached".
- **The gate is asked once**, at the top of `ImportCoordinator.handle(url:)` — before
  `NZBImporter` copies the .nzb into Documents, and where all four ingress paths converge. Never
  gate resume, retry, pause, cancel, `extractAgain`, the App Intents, history or settings. The
  Lock Screen intents run where no paywall can present, so a gate there would silently do nothing.
- **Grandfathering** = leading integer of `AppTransaction.originalAppVersion` (the original
  **CFBundleVersion**) `< Grandfathering.paywallCutoffBuild`, and only when
  `AppTransaction.environment == .production`. Sandbox, TestFlight and Xcode all report `"1.0"`,
  which parses to 1 and sits below any cutoff, so without the environment gate every tester and
  reviewer looks grandfathered and the purchases are untestable.
  A parse failure is NOT grandfathered. An unavailable `AppTransaction` (offline first launch) is
  "unknown, retry next launch" — only positives are ever cached, and `AppTransaction.refresh()` is
  never called at launch (it prompts for Apple Account credentials).
- **`paywallCutoffBuild` is `202609072335` — the paywall build's own CFBundleVersion, read off App
  Store Connect.** Never infer it from the Info.plists. They pinned the literal `1` until the 1.1.0
  fix, but `agvtool new-version -all` (which `update_build_number` drives) rewrites them on disk
  during the lane, so every build the App Store served carried a fastlane timestamp: 1.0 was
  `202607020045`, 1.0.1 `202608220021`, the paywall `202609072335`. A cutoff of `2` derived from
  those plists shipped in 1.1.0 and grandfathered **nobody** — every paying customer was locked out
  until 1.1.1. The boundary is exclusive, so the paywall build itself grants nothing, and future
  builds carry larger timestamps. Confirm released build numbers with
  `scripts/lookup_order.py --builds`; a test in `Packages/PurchasePolicy` pins the three literals.
- **An unresolved purchase state is not Pro.** `Entitlement.unknown` falls back to the free
  counter; treating it as Pro would unlock the app by turning off Wi-Fi. The cached-positive bool
  read synchronously in `PurchaseStore.init` exists so a cold launch via `.onOpenURL` and an app
  update do not flash a paywall at someone who already paid.
- **`Transaction.updates` is started from `AppDelegate`,** not a `.task`: unfinished transactions
  arrive once shortly after launch and are lost otherwise, and `.task` re-fires per iPad window.
  It is also the only way an offer code redeemed outside the app reaches us — the redemption sheet
  hands back no transaction.
- **The paywall must stay reachable from Settings at all times** (Guideline 2.1(b) — App Review
  has to find the purchases), and from `OnboardingView`'s toolbar before a server exists, since
  that screen has no tab bar.
- The widget must never learn about any of this: `DownloadActivityAttributes` stays
  dependency-free, and `SwiftNZBWidgets` links neither `PurchasePolicy` nor StoreKit.
- Pure policy (slot arithmetic, the cutoff comparison) lives in `Packages/PurchasePolicy` so
  `swift test` covers it. See `docs/AppStoreReview.md` § 9 Monetization.

## Conventions (carried from iobs)

- One `@Observable` view model per screen, created `@State private var viewModel = …()`.
  Services are `static let shared` singletons, mostly `@MainActor`.
- User-facing strings use `String(localized:)` / `LocalizedStringKey`; `Localizable.xcstrings`
  is auto-extracted at build — don't hand-edit it.
- **Numbers in SwiftUI `Text("\(int)")` get a locale thousands separator.** For ports, byte
  counts, speeds, connection counts, IDs use `Text(verbatim:)`.
- `.glassProminent` adds its own padding — size icon controls with a fixed tinted circle
  (`CircleActionButton`), not frame+padding alone.
- Adding a field to any Codable model / payload → use `decodeIfPresent` defaults
  (migration + cross-version safety).
- `@Observable` + a `didSet` on a stored property is safe: the macro moves the observer onto the
  private backing store and still emits the observation accessors (verified via
  `-dump-macro-expansions`). `DownloadManager.activeJobID` relies on this.
- **Downloads only progress in the foreground**, so `DownloadManager.refreshIdleTimer()` holds
  `isIdleTimerDisabled` while a job is active (auto-lock would background the app and suspend the
  sockets). It is driven by `activeJobID`'s `didSet` — don't set `activeJobID` behind its back.
- Dropping a job from history must go through `DownloadManager.forget(where:)`: a failed job keeps
  its partial `.part` files for resume, so removing the record without the working directory
  strands those bytes where no screen can reach them.
- Files added under a target's source path are picked up on the next `xcodegen generate`. Files
  shared across targets are listed explicitly in `project.yml` (currently
  `DownloadActivityAttributes.swift`; `DownloadIntents.swift` will join it).
- The Live Activity's `DownloadActivityAttributes` is shared into the widget and **must stay
  dependency-free**. The Live Activity intent file gates its `DownloadManager` calls behind the
  **`SWIFTNZB_APP`** compilation condition (set only on the app target).

## Provisioning (device / TestFlight)

- Code signing uses Fastlane **match** for both bundle IDs. One-time: `bundle exec fastlane
  register_ids` (creates the App IDs incl. widget), then `match development` / `match appstore`.
- **Appfile `app_identifier` must stay a single String** (`upload_to_testflight`/`produce`
  require it). The list of both bundle IDs for **match** lives in the **Matchfile**.
- The **Gemfile** must declare `multi_json` (and `abbrev`) — Bundler 4 / Ruby 3.3+ won't
  auto-load these transitive fastlane deps. No `Gemfile.lock` committed.
- **Build numbers** are a timestamp set per upload by the `update_build_number` lane, which runs
  `agvtool new-version -all` — that writes CFBundleVersion into the Info.plists *and*
  CURRENT_PROJECT_VERSION. Both plists reference `$(CURRENT_PROJECT_VERSION)` and `project.yml`
  sets `VERSIONING_SYSTEM: apple-generic`, so a build made without fastlane (Xcode, or a local
  `xcodebuild`) gets the same number the project setting carries instead of a stale literal.
- iPad **must** declare all four orientations (`…~ipad` incl. `PortraitUpsideDown`) or
  `upload_to_testflight` validation fails (409). iPhone keeps three.
- **iCloud KVS capability** must be enabled on the App ID (entitlement
  `com.apple.developer.ubiquity-kvstore-identifier`) or server/settings sync degrades to
  local-only (no crash).
- **App Transport Security**: the app declares **no** ATS exception. ATS governs only the URL
  Loading System (URLSession/CFNetwork); all Usenet traffic uses `NWConnection`
  (Network.framework), which ATS does not police — so plain NNTP / self-signed TLS already work
  without `NSAllowsArbitraryLoads`. Omitting a global exception avoids unnecessary review
  scrutiny. Re-add a *scoped* exception only if HTTP URL loading (e.g. NZB-by-URL) is introduced.
- **App Store review notes**: the app bundles no indexers or content — bring-your-own server +
  NZB. PAR2/unrar are generic file utilities. NZB/Usenet apps draw heightened scrutiny; keep the
  framing as a generic NNTP protocol client (see `docs/AppStoreReview.md` for the full strategy,
  demo-account/demo-NZB plan, and rejection playbook, plus listing texts in `fastlane/metadata/`).
- **In-app purchase needs no entitlement** and no App ID capability change, so adding it does not
  mean re-running `match`. IAP products are configured by hand in App Store Connect (fastlane has
  no action for them) and the **first** IAP submission must ride an app version —
  `precheck_include_in_app_purchases` stays `false` because precheck cannot read IAPs under
  API-key auth. `SwiftNZB.storekit` at the repo root is wired to the scheme declaratively via
  `scheme: storeKitConfiguration:` in `project.yml`; doing it in Xcode's scheme editor does not
  survive `xcodegen generate`.
- **Privacy manifests**: both targets ship a `PrivacyInfo.xcprivacy` (app: UserDefaults CA92.1,
  file timestamps C617.1, disk space E174.1; widget: none). Data-not-collected, no tracking.

## Gotchas recap

- Edit `project.yml`, not the xcodeproj. Regenerate after file changes.
- Don't add GPL code (no par2cmdline) — App Store + clean-room PAR2 is intentional.
- Local-package SOURCES under `Packages/` are committed; `.gitignore` deliberately does NOT
  ignore `Packages/` (only `.build/`, `.swiftpm/`, `Package.resolved`).
- App icon is `AppIcon.icon` (Icon Composer) at the repo root, referenced as a resource in
  `project.yml` with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` +
  `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES` (as iobs does). Don't add an
  `AppIcon.appiconset` alongside it — two "AppIcon" sources conflict, and a set referencing a
  missing file crashes `actool`. A missing/empty icon also fails TestFlight upload with a 409
  (missing 120/152px icons + `CFBundleIconName`).
