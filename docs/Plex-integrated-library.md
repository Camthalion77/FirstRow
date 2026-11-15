# Plex in Movies and TV Shows

Connected Plex movie and television libraries now populate the existing Movies and TV Shows menus. Sources continues to manage servers and offer the original library browser. No Plex account or server setting changes are required.

`PlexLibraryIndex` uses the existing media server client interface, with `PlexClient` in production. Servers load concurrently; individual library failures do not discard reachable content. Entering either menu refreshes the index. Refresh retries failed servers and updates metadata; leaving the menu cancels the index request. Season and episode pages support refresh and cancel their requests on Back. Request identifiers also reject obsolete responses.

Rows keep their server, library and item identities. Shared Plex/provider GUIDs identify duplicate content; titles never do. Without a shared identifier, separate items remain visible, including unrelated same-title movies and local files without comparable Plex identifiers. Duplicate shows retain all child sources, combining identified seasons and routing each episode's playback and progress reports to its original server. Local libraries continue through their existing paths.

Movie selections use the existing server video session, subtitle discovery, media engine, resume prompt and Plex timeline/scrobble reporting. Artwork and metadata use the existing server preview in both appearances. No additional dependencies are needed.

## Validation

The credential-free `firstrowTests/PlexLibraryTests.swift` suite is included in both the Xcode test target and the Swift package. It uses a custom URL protocol and mock media server clients to test movie pagination and metadata, show/season/episode navigation, cross-server identity, merged shows, partial failures, cancellation, local menu preservation, subtitle URLs and playback reporting.

On Linux, run `swift test -j 4` and `swift build -c debug --product FirstRow -j 4` with the portable dependencies described in `Portable/README.md`.

Initial local validation used 10 passing Linux tests and a successful Linux debug build. A local HTTP Plex fixture also exercised Movies previews, TV Shows → show → season → episode, and Classic/Modern rendering using the offscreen keyboard harness. No personal Plex credentials were used. Actual network media playback and physical remote input were not validated locally. This workspace is Linux; Apple compilation and Xcode test execution use the Intel macOS CI described below.

## Intel macOS CI

`.github/workflows/macos-intel.yml` builds pull requests and supports manual dispatch. It uses GitHub's `macos-15-intel` runner with Xcode 26.2 (macOS Tahoe 26.2 SDK), explicitly targets `x86_64`, and sets a macOS 15.2 minimum to match the existing Xcode test host. The shared `First Row` scheme includes both unit and UI test targets; the unit target includes the Plex fixtures.

After tests pass, CI builds the Release application, verifies that its executable contains only Intel code, checks its ad-hoc signature, and packages `First Row.app` with `ditto` to preserve bundle metadata. Download `FirstRow-macOS-x86_64` from the workflow's artifacts for the ZIP and SHA-256 checksum. A separate diagnostics artifact retains Xcode logs and the `.xcresult` bundle, including on failures.

This is an ad-hoc signed CI build, without Developer ID signing or notarization. It uses the existing optional media-engine embedding behavior; no media engine is built by this workflow. Tests run on the runner's macOS 15 system, so building with the Tahoe SDK does not establish runtime validation on macOS Tahoe itself. The workflow does not create a GitHub Release or merge pull requests.
