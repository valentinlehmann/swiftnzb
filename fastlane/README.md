fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### register_ids

```sh
[bundle exec] fastlane register_ids
```

Register the app + widget App IDs on the Apple Developer portal (one-time, before match)

### load_api_key

```sh
[bundle exec] fastlane load_api_key
```

Load App Store Connect API key

### update_build_number

```sh
[bundle exec] fastlane update_build_number
```

Set build number to current date/time

----


## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Push a new beta build to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
