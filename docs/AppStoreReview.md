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
- [ ] Age rating questionnaire: answer truthfully — the app displays no content itself; all
      questions "No" ⇒ **4+**. Do **not** preemptively pick 17+; if App Review asks for
      "Unrestricted Web Access" or a higher rating, accept 17+ without argument.
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

Appeals: keep to verifiable facts about capabilities, never intent ("we don't intend…" is
weaker than "the app cannot…").

## 7. Privacy questionnaire (App Store Connect)

- Data collection: **No** for every category ⇒ "Data Not Collected".
- The iCloud KVS sync of server settings and iCloud Keychain password sync are Apple-provided
  user-controlled sync, not developer collection — answer remains No.
- Privacy policy URL is still mandatory: a short static page ("SwiftNZB stores your server
  settings on your device and in your personal iCloud; we collect nothing.") — e.g.
  `https://valentinlehmann.de/swiftnzb/privacy` or a GitHub Pages page in this repo.

## 8. Ongoing hygiene

- Keep listing/keywords free of other apps' names and content vocabulary permanently — 
  metadata is re-reviewed on every update.
- Never add: NZB-by-URL fetching, an indexer/search integration, or an in-app browser. Any of
  these converts the app from "protocol client" to "discovery tool" and torpedoes the 5.2.1
  defense (and would require re-adding ATS exceptions).
- If Apple ever asks about the GitHub repo: it demonstrates the clean-room PAR2 implementation
  (no GPL) — a licensing plus, not a liability.
