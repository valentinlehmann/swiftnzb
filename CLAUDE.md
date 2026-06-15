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
  Intents/                   App Intents (DownloadIntents shared into widget) + AppShortcuts
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
- iPad **must** declare all four orientations (`…~ipad` incl. `PortraitUpsideDown`) or
  `upload_to_testflight` validation fails (409). iPhone keeps three.
- **iCloud KVS capability** must be enabled on the App ID (entitlement
  `com.apple.developer.ubiquity-kvstore-identifier`) or server/settings sync degrades to
  local-only (no crash).
- **App Store review notes**: ATS `NSAllowsArbitraryLoads` is justified by "connects to
  user-configured Usenet (NNTP) servers" (arbitrary hosts, plain NNTP/self-signed TLS). The app
  bundles no indexers or content — bring-your-own server + NZB. PAR2/unrar are generic file
  utilities. NZB/Usenet apps draw heightened scrutiny; keep the framing clean.

## Gotchas recap

- Edit `project.yml`, not the xcodeproj. Regenerate after file changes.
- Don't add GPL code (no par2cmdline) — App Store + clean-room PAR2 is intentional.
- Local-package SOURCES under `Packages/` are committed; `.gitignore` deliberately does NOT
  ignore `Packages/` (only `.build/`, `.swiftpm/`, `Package.resolved`).
- App icon is a placeholder `AppIcon.appiconset` for now; swap in an Icon Composer `.icon`
  (as iobs does) when artwork exists, and update `project.yml` accordingly. Don't reference a
  missing icon file — `actool` crashes.
