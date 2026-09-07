# App Store Review Guide — SwiftNZB

How to get SwiftNZB through App Review, and what to say (and not say) at every step.
Store listing texts live in `fastlane/metadata/` (standard `fastlane deliver` layout) — this
document is the strategy and the process.

## 1. Why this app is approvable

NZB/Usenet apps get heightened scrutiny because of the piracy association, but there is solid
precedent for **protocol clients**: Apple ships and approves mail clients (SMTP/IMAP), FTP/SFTP
clients, torrent-*remote* controllers, and generic Usenet newsreaders. What gets NZB apps
rejected under **Guideline 5.2.1 (Intellectual Property)** or 4.x is *facilitating discovery of
infringing content* — bundled indexers, search engines, "browse releases" features, or store
screenshots showing movies/TV releases.

SwiftNZB deliberately has none of that:

- **No content discovery of any kind.** No indexer, no search, no browsing, no featured
  content, no URL fetching of NZBs. The only way anything enters the app is the user handing
  it an `.nzb` file through the system file picker / share sheet.
- **Bring-your-own server.** The app is useless without a paid account at a third-party Usenet
  provider that the user configures manually — exactly like a mail client without a mail
  account.
- **Generic file utilities.** PAR2 (error-correcting verification/repair) and RAR extraction
  are content-neutral data-integrity tools, the same category as a zip utility.
- **Nothing leaves the device.** No analytics, no tracking, no developer server. Privacy label
  is "Data Not Collected".

**Framing rule for every text (listing, review notes, replies): SwiftNZB is a client for the
open NNTP protocol, comparable to an email or FTP client.** State what it does factually.
Never mention piracy — not even to deny it (defensive language reads as a red flag). Never use
scene/release vocabulary ("releases", "retention search", "automation", indexer names,
*arr-stack names, "SABnzbd"/"NZBGet" comparisons — competitor names in metadata also violate
Guideline 2.3.7).

## 2. Pre-submission checklist

Technical (all handled in the repo — verify before each submission):

- [ ] `PrivacyInfo.xcprivacy` present in **both** the app and the widget target (required-reason
      APIs: UserDefaults CA92.1, file timestamps C617.1, disk space E174.1).
- [ ] `ITSAppUsesNonExemptEncryption` = `false` (Boolean) in Info.plist → no export-compliance
      questions per build. The app uses only Apple's TLS (exempt).
- [ ] **No ATS exception.** The app performs no URL loading; NNTP over `NWConnection` is not
      governed by ATS. `NSAllowsArbitraryLoads` must stay deleted — a global ATS exception is
      a documented review-friction trigger and the app never needed it.
- [ ] Background modes match reality: only `processing` (+ BGTask identifier). Don't declare
      modes the app can't demonstrate.
- [ ] iPad orientations: all four (`…~ipad` incl. `PortraitUpsideDown`) — TestFlight
      validation 409s otherwise.
- [ ] App icon present (Icon Composer `AppIcon.icon`); missing 120/152 px icons also 409.
- [ ] Age rating questionnaire: answer truthfully — the app displays no content itself, so it
      lands in the lowest tier. Selling in-app purchases does not change the rating; the App
      Store adds the "In-App Purchases" badge automatically from the product configuration. Do
      **not** preemptively pick a higher rating; if App Review asks for one, accept it without
      argument. (Note the 2025 overhaul: the tiers are now 4+, 9+, 13+, 16+ and 18+ — 12+ and
      17+ no longer exist — and there is an additional questionnaire covering in-app controls,
      capabilities, medical/wellness topics and violent themes.)
- [ ] **Paid Applications agreement is Active** in Agreements, Tax and Banking (full one-time
      setup sequence: § 9 Monetization). Until it is,
      in-app purchases cannot be created or submitted **and products do not load in sandbox** —
      an empty product list is almost always this.
- [ ] All three in-app purchases are **Ready to Submit** *and attached to this version's
      submission*. Missing Metadata is usually a missing subscription-group localization or a
      missing review screenshot.
- [ ] The purchase screen is reachable **without spending free downloads**: Settings → SwiftNZB
      Pro, and from the welcome screen's top-right button before a server exists. Guideline
      2.1(b) — a reviewer who cannot find the purchases rejects the build.
- [ ] **Demo credentials and the demo NZB are added by hand in App Store Connect, last.**
      `fastlane/metadata/review_information/notes.txt` carries only the framing, because deliver
      cannot supply a provider password or attach a file. Deliver **overwrites** the review notes
      on every `metadata` or `release` run, so add the how-to-test steps *after* the final upload.
      Run the metadata lane again and your credentials are gone.
- [ ] Category: **Utilities**.
- [ ] Support URL: the GitHub repo. Keep the README as clean as the listing — reviewers read
      the support URL. (Current README is fine.)

## 3. The demo problem — solve it or get rejected

A reviewer **cannot test this app without a Usenet account and an NZB file**. "We could not
review the app's features" is the most likely rejection if you skip this. Do this once before
submitting:

1. **Demo server account.** Create a dedicated account at a Usenet provider (a block account
   at e.g. UsenetExpress/Eweka-family resellers is a few euros and doesn't expire monthly).
   Put host/port/username/password in App Store Connect → App Review Information. Do **not**
   use your personal account credentials.
2. **Legal demo NZB.** Post a file you own (e.g. a few hundred MB of generated test data or
   your own photos, RAR-split + PAR2, via `nyuu`/provider posting tools) to a binaries group,
   generate the NZB, verify it downloads with the demo account. Attach the `.nzb` to the
   review notes (App Store Connect supports attachments) — do not host it on a public URL.
3. **Step-by-step instructions in the notes** (see §4) — assume the reviewer has never heard
   of Usenet.

Refresh the demo NZB before every submission (article retention/takedowns can silently break
it, and a broken demo equals a "could not review" rejection).

## 4. Review notes — paste-ready text

> SwiftNZB is a client for the open NNTP (Usenet) protocol — functionally comparable to an
> email client: the user supplies their own server account from a commercial Usenet provider,
> and the app downloads the specific file attachments described by an .nzb document the user
> imports themselves.
>
> The app contains no content, no search feature, no content index or catalog, and no way to
> discover or browse anything inside the app. It cannot fetch NZB files from the internet; the
> only input path is the iOS document picker / share sheet. PAR2 and RAR support are standard
> data-integrity utilities (Usenet transmissions are split and error-coded; the app verifies
> and reassembles them).
>
> Nothing is collected or transmitted to us; the app talks exclusively to the server the user
> configures. There are no third-party SDKs, no analytics, no ads.
>
> HOW TO TEST:
> 1. Launch the app → "Add Server". Enter the demo account below and tap Save (the app
>    verifies the connection).
>    Host: <HOST> — Port: 563 — SSL: on — Username: <USER> — Password: <PASS>
> 2. Open the attached demo file "swiftnzb-review-demo.nzb" (e.g. AirDrop/Files → share →
>    SwiftNZB, or the + button on the Queue tab) and tap "Add".
> 3. The download runs with a Live Activity on the Lock Screen / Dynamic Island; when it
>    finishes, the file is verified (PAR2), extracted (RAR), and appears in the Files app
>    under "On My iPhone → SwiftNZB". The demo file contains test data created by us.

## 5. Screenshots

- Show: Queue with the active download + Live Activity, the import sheet, Settings/server
  screen, History, the result in Files.
- Every visible job/file name must be unimpeachable: use the demo payload names, e.g.
  `project-backup-2026.rar`, `holiday-photos.zip`, `ubuntu-24.04-desktop-amd64.iso`,
  `openstreetmap-europe-extract.pbf`.
- Never show: anything shaped like a movie/TV/music/software release name, indexer web pages,
  or a browser.

## 6. If rejected — playbook

| Rejection | Response |
|---|---|
| 5.2.1 / "facilitates piracy" | Reply (don't just resubmit): the app is a protocol client with zero discovery capability; enumerate: no search, no index, no bundled content, BYO server, user-supplied files only. Compare to a mail/FTP client. Ask what specific feature facilitates infringement, since none exists. Escalate to App Review Board appeal if a generic rejection repeats. |
| 2.1 "could not review" | Demo account/NZB problem. Verify the demo still downloads, refresh the NZB, resubmit with clearer step-by-step notes. |
| 4.2 minimal functionality | Point to the full pipeline: multi-connection engine, PAR2 repair, RAR extraction, Live Activity, Files integration, iCloud sync. |
| 5.1.1 data collection | Privacy label is "Data Not Collected"; passwords stay in the user's Keychain (iCloud Keychain sync is user-controlled, not developer access). |
| Metadata rejection (2.3) | Usually a keyword or screenshot; fix the specific item, don't argue. |
| 3.1.1 own unlock mechanism | Only StoreKit unlocks Pro. Coupons are Apple offer codes, not licence keys or an in-app code field. Point to Restore Purchases and Redeem Code on the purchase screen. |
| 3.1.2 subscription information | The purchase screen shows each plan's name, duration, full renewal price from `product.displayPrice`, auto-renewal wording, Restore, and links to the privacy policy and Apple's standard EULA. Screenshot it in the reply; fix the one missing element rather than arguing. |
| 2.1(b) "in-app purchases could not be found" | The screen is Settings → SwiftNZB Pro and needs no free downloads spent; before a server exists it is the top-right button on the welcome screen. Verify all three products are attached to this version and none sits in Missing Metadata. |
| 3.1.2(a) bait-and-switch / removing paid functionality | 1.0 was free, so nothing purchased was removed. Pre-paywall installs keep unlimited downloads permanently, decided from the Apple-signed `AppTransaction.originalAppVersion`; everyone else gets 10 free downloads first. The release notes say so. |
| 2.3.2 metadata mismatch | The description states the free-download count and that Pro is a purchase. Keep that number identical to `FreeTier.limit` in `Packages/PurchasePolicy`. |
| 3.1.3(b) steering to other purchase paths | Nothing in the app or the metadata links to a purchase route outside in-app purchase; the only external links are the privacy policy and Apple's EULA. |

Appeals: keep to verifiable facts about capabilities, never intent ("we don't intend…" is
weaker than "the app cannot…").

## 7. Privacy questionnaire (App Store Connect)

- Data collection: **No** for every category ⇒ "Data Not Collected".
- The iCloud KVS sync of server settings and iCloud Keychain password sync are Apple-provided
  user-controlled sync, not developer collection — answer remains No.
- Privacy policy URL is still mandatory: a short static page ("SwiftNZB stores your server
  settings on your device and in your personal iCloud; we collect nothing.") — served from
  `docs/privacy/` in this repo via GitHub Pages. **The URL in App Store Connect, in both
  `description.txt` files, and in `PaywallView.privacyPolicy` must be the same string** — a dead
  link on the paywall is a rejection.
- **In-app purchase does not change any answer.** Do not tick Purchases → Purchase History.
  The questionnaire asks only about data *you or a third-party SDK in your app* collect;
  "collect" means transmitting off-device where you can access it; on-device processing is not
  collection; and Apple states "you are not responsible for disclosing data collected by Apple".
  StoreKit 2 is read on device and there is no developer server. Neither
  `PrivacyInfo.xcprivacy` changes either — StoreKit is not a required-reason API, and the
  existing `UserDefaults` CA92.1 declaration already covers the free-download counter.
  This answer flips the moment any of these appears: a paywall/analytics/receipt-validation SDK,
  a developer server or App Store Server Notifications, an `appAccountToken`, or entitlement
  state in a CloudKit database the developer can read.

## 8. Ongoing hygiene

- Keep listing/keywords free of other apps' names and content vocabulary permanently — 
  metadata is re-reviewed on every update.
- Never add: NZB-by-URL fetching, an indexer/search integration, or an in-app browser. Any of
  these converts the app from "protocol client" to "discovery tool" and torpedoes the 5.2.1
  defense (and would require re-adding ATS exceptions).
- Never unlock Pro with anything but StoreKit. A licence key, a code field, or a hidden gesture
  is a Guideline 3.1.1 violation as well as infrastructure this app does not want.
- Never distribute offer codes through content-adjacent channels (indexer forums, *arr
  communities). A screenshot of a SwiftNZB code URL on such a site is exactly the
  metadata-adjacent evidence that cannot be retracted, and it is the one genuinely new 5.2.1
  risk that commerce introduces.
- If Apple ever asks about the GitHub repo: it demonstrates the clean-room PAR2 implementation
  (no GPL) — a licensing plus, not a liability.

## 9. Monetization

### One-time App Store Connect setup, in order

Steps 1 and 2 are gating and slow — do them first, not last.

1. **Agreements, Tax and Banking → accept the Paid Applications schedule**, submit the tax form
   and bank details. Until it reads Active you cannot create or submit in-app purchases **and
   products do not load in sandbox** — an empty product list is almost always this. Budget days.
2. **Monetization → Subscriptions → create one subscription group**, reference name
   `SwiftNZB Pro`, and give **the group** a localization (display name) in en-US and de-DE. A
   missing *group* localization is the commonest reason subscriptions sit in Missing Metadata no
   matter how complete the products look.
3. In that group create `Pro Monthly` (`de.valentinlehmann.swiftnzb.pro.monthly`, 1 month,
   launch price $1.99) and `Pro Yearly` (`…pro.yearly`, 1 year, launch price $9.99). Put
   **Yearly at the higher subscription level** so monthly→yearly is an immediate prorated upgrade
   and yearly→monthly a deferred downgrade — that is what Guideline 3.1.2(b)'s "seamless
   upgrade/downgrade" means in practice.
4. **In-App Purchases → create `Pro Lifetime`** (`…pro.lifetime`), Non-Consumable, launch price
   $29.99.
5. For **each of the three**: price, availability (all countries), at least one localization
   (display name + description), and **a review screenshot + review notes**. Any product missing
   one of those four sits in Missing Metadata and cannot be attached to a submission. Add de-DE
   localizations too, since the listing is de-DE.
6. **Enable Billing Grace Period** on the subscription group (see below — it is off by default).
7. **Family Sharing on for all three.** One-way switch, so decide once. It costs no revenue, is
   the norm for a lifetime unlock, and prevents "I bought Lifetime and my iPad can't use it"
   support mail. A shared entitlement arrives as a normal `currentEntitlements` transaction with
   `ownershipType == .familyShared` and is treated as plain Pro.
8. **App Information → License Agreement: leave Apple's standard EULA.** Nothing to write.
9. On the version page, **"In-App Purchases and Subscriptions" → select all three**, then Submit.
   Apple requires an app's *first* in-app purchase to ride an app version, and `deliver` cannot
   attach them — which is why the `release` lane keeps `submit_for_review: false`.
10. **After approval**, set up offer codes for coupons.

### Per-product text and screenshot — paste-ready

Two different images, and only the first is required:

- **App Review Screenshot** (required in practice): *"A screenshot of the In-App Purchase that
  clearly shows the item or service being offered. This screenshot is used for review only and
  isn't displayed on the App Store."* Customers never see it.
- **In-App Purchase Image** (optional, customer-facing): 1024 × 1024 px, JPG or PNG, 72 dpi, RGB,
  flattened, no rounded corners. Only needed to promote a purchase on the product page or in the
  payment sheet. Skip it for now.

For the review screenshot, use the **pushed** purchase screen (Settings → SwiftNZB Pro), not the
sheet: the sheet is `.presentationSizing(.form)`, so a screenshot of it shows a dimmed queue
behind, while the pushed version fills the screen, lists all three plans with their prices, and is
exactly the path the review notes tell the reviewer to tap. The same screenshot is acceptable for
all three products, since all three appear on that one screen — take three with the relevant plan
row selected if you want to be thorough. If any queue content is visible, keep to the safe
filename palette in § 5.

Field limits, from App Store Connect: **Reference Name** ≤ 64 (internal only, shows in Sales and
Trends), **Display Name** 2–30 (customer-facing, appears in the payment sheet), **Description**
≤ 45 (customer-facing; shows under the name on the App Store if the purchase is promoted),
**Review Notes** ≤ 4000 (review only).

| Product | Reference Name | Display Name (en-US) | Description (en-US) |
|---|---|---|---|
| `…pro.monthly` | Pro Monthly | SwiftNZB Pro Monthly | Unlimited downloads, billed monthly. |
| `…pro.yearly` | Pro Yearly | SwiftNZB Pro Yearly | Unlimited downloads, billed yearly. |
| `…pro.lifetime` | Pro Lifetime | SwiftNZB Pro Lifetime | Unlimited downloads. One-time purchase. |

| Product | Display Name (de-DE) | Description (de-DE) |
|---|---|---|
| `…pro.monthly` | SwiftNZB Pro Monatlich | Unbegrenzte Downloads, monatlich. |
| `…pro.yearly` | SwiftNZB Pro Jährlich | Unbegrenzte Downloads, jährlich. |
| `…pro.lifetime` | SwiftNZB Pro Dauerhaft | Unbegrenzte Downloads. Einmalkauf. |

Subscription **group** display name, both locales: `SwiftNZB Pro`. (This is the one that is easy to
forget and the commonest cause of Missing Metadata.)

Review notes, same text for all three:

> SwiftNZB is free for the first 10 completed downloads; after that, adding a new download requires
> SwiftNZB Pro. All three products unlock the same thing, unlimited downloads. The purchase screen
> is the Settings tab, then SwiftNZB Pro, and it can be opened at any time without using up free
> downloads. Before a Usenet server is configured it is also reachable from the "SwiftNZB Pro"
> button at the top right of the welcome screen.

**Never put in the Display Name or Description**: a price (it varies by storefront and goes
stale — the app shows `displayPrice` at runtime), the word "trial" (no introductory offer exists),
a URL, another platform's name, placeholder text, or anything from the banned vocabulary in § 1.
Do not call Lifetime a subscription.

Product identifiers are permanent — App Store Connect will not let one be reused or renamed, so a
typo is a dead identifier forever. **Prices are typed here and nowhere else**: `SwiftNZB.storekit`
is a local test fixture that never uploads, and the app reads `product.displayPrice` at runtime,
so a price change needs neither a build nor a metadata push.

**Reviewers need nothing from you.** App Review transacts in the sandbox automatically for the
build under review — no charge, no sandbox account to supply, no code to hand over. What they need
is configuration: the agreement Active, the three products Ready to Submit *and attached to this
version*, and a reachable purchase screen.

### Policy

Free for the first **10 completed downloads**, then a purchase is required to add a new one.
Three products, one entitlement ("Pro"): `…pro.monthly`, `…pro.yearly` (auto-renewable, one
subscription group, yearly at the higher level) and `…pro.lifetime` (non-consumable). Prices are
always read from StoreKit — never hardcoded, in the app or in the listing.

**5.2.1 exposure is net neutral to slightly positive.** A paid bring-your-own-server protocol
client is even more clearly a tool: the revenue comes from the software, not from anything
content-shaped, and there is still no index, no search and no bundled content. Paid mail and FTP
clients are the precedent §1 already invokes. Keep price and marketing copy tied to the app's
limits ("unlimited downloads"), never to what can be obtained with it.

**Grandfathering.** Anyone whose Apple Account downloaded SwiftNZB before the paywall build keeps
Pro for good, decided on device from the Apple-signed app transaction — no server. The comparison
is the leading integer of `AppTransaction.originalAppVersion` (which on iOS is the original
**CFBundleVersion**) against `Grandfathering.paywallCutoffBuild`, and **only** when
`AppTransaction.environment == .production`. Every build shipped before this feature carried
CFBundleVersion `1`; sandbox, TestFlight and Xcode all report `"1.0"`, so without the environment
gate every tester and every reviewer would look grandfathered and the purchases would be
untestable — a 2.1(b) rejection.

`paywallCutoffBuild` is **`2`**, pinned to the build that is actually live rather than to a date.
Every version released before the paywall shipped as CFBundleVersion `1` — both Info.plists pinned
that literal until the 1.1.0 build-number fix, so as that commit puts it, "every upload arrived as
build 1". The comparison is exclusive, so `2` grandfathers build 1 and nothing later. Note the
off-by-one: setting the constant to `1`, the released build number itself, would grandfather
nobody.

Pinning it this way removes an operational rule rather than adding one. A date-based cutoff would
have meant no paywall-free build could ever be uploaded after that instant. With `2` there is
nothing to freeze: every future upload carries a 12-digit fastlane timestamp far above it, and
build `1` cannot be uploaded again because App Store Connect rejects a duplicate build number. The
constant lives in `Packages/PurchasePolicy` and a test pins it, so it cannot drift unnoticed.

**Required paywall disclosures** (Guideline 3.1.2(c), which points at Schedule 2 §3.8(b) of the
developer agreement, plus Apple's auto-renewable-subscriptions page): plan name, duration, what
Pro provides, the **full renewal price** as the most prominent pricing element, price per unit
where relevant, explicit auto-renewal wording, a Restore Purchases control, and working links to
the privacy policy and Terms of Use. Terms of Use is Apple's standard EULA at
`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` — no custom EULA is needed,
but because App Store Connect shows no licence link when the standard agreement applies, the app
has to carry the link itself. If review ever pushes back on that, the cheap fix is a one-page
Terms of Use on the same static host as the privacy policy.

**Coupons are Apple offer codes, and nothing else.** Since 29 October 2025 offer codes cover all
in-app purchase types, so one mechanism serves both the subscriptions and the Lifetime
non-consumable; promo codes for in-app purchases can no longer be created (Apple ended that on
26 March 2026). Use a **custom code** for a campaign — one-time-use batches have a 500-code
minimum. For a "free Pro forever" gift prefer a 100%-off code on the Lifetime product, so nothing
renews and nobody has to cancel later. Codes can only be generated once the app is Ready for
Distribution with the purchase Approved, offers cannot be edited after creation, and the
redemption link must be copied from the offer's detail page rather than hand-built.

**Enable Billing Grace Period** on the subscription group. It is off by default, and
`Transaction.currentEntitlements` excludes a subscription in billing retry — so without it a
declined card revokes Pro on the first failed charge, possibly mid-download.

**A determined customer can reset the free tier** by clearing app and iCloud data. Closing that
needs a server to hold the count, which this app does not have and is not getting; DeviceCheck is
not an alternative (it requires a developer server, and two bits cannot count to ten).
