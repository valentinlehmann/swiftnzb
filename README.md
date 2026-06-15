# SwiftNZB

A native SwiftUI **Usenet NZB downloader** for iPhone and iPad. Bring your own Usenet server
and NZB files; SwiftNZB downloads the article segments over many parallel TLS connections,
decodes yEnc, reassembles files, verifies/repairs with PAR2, extracts RAR archives, and saves
the result to the Files app — with a Live Activity showing live progress on the Lock Screen and
Dynamic Island.

## Status

Early development. See [`CLAUDE.md`](CLAUDE.md) for architecture and conventions, and the
implementation plan for phasing.

## Requirements

- iOS 26+, Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Ruby + Bundler (for Fastlane)

## Build

```bash
xcodegen generate
xcodebuild -project SwiftNZB.xcodeproj -scheme SwiftNZB \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

Engine unit tests (no simulator needed):

```bash
( cd Packages/DownloadEngine && swift test )
( cd Packages/PAR2Kit && swift test )
```

## Deployment

Push to `main` → GitHub Actions runs `fastlane beta` → TestFlight. Signing via Fastlane
`match`. One-time setup: `bundle exec fastlane register_ids`, then `match development` /
`match appstore`.

## License / App Store note

PAR2 verify+repair is a clean-room implementation (no GPL) so the app is App-Store-safe; RAR
extraction uses the App-Store-acceptable UnRAR library. The app bundles no Usenet indexers or
content.
