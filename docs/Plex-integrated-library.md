# Plex in Movies and TV Shows

Connected Plex movie and television libraries now populate the existing Movies and TV Shows menus. Sources continues to manage servers and offer the original library browser. No Plex account or server setting changes are required.

`PlexLibraryIndex` uses the existing media server client interface, with `PlexClient` in production. Servers load concurrently; individual library failures do not discard reachable content. Entering either menu refreshes the index. Refresh retries failed servers and updates metadata; leaving the menu cancels the index request. Season and episode pages support refresh and cancel their requests on Back. Request identifiers also reject obsolete responses.

Rows keep their server, library and item identities. Shared Plex/provider GUIDs identify duplicate content; titles never do. Without a shared identifier, separate items remain visible, including unrelated same-title movies and local files without comparable Plex identifiers. Duplicate shows retain all child sources, combining identified seasons and routing each episode's playback and progress reports to its original server. Local libraries continue through their existing paths.

Movie selections use the existing server video session, subtitle discovery, media engine, resume prompt and Plex timeline/scrobble reporting. Artwork and metadata use the existing server preview in both appearances. No additional dependencies are needed.

## Validation

The credential-free `firstrowTests/PlexLibraryTests.swift` suite is included in both the Xcode test target and the Swift package. It uses a custom URL protocol and mock media server clients to test movie pagination and metadata, show/season/episode navigation, cross-server identity, merged shows, partial failures, cancellation, local menu preservation, subtitle URLs and playback reporting.

On Linux, run `swift test -j 4` and `swift build -c debug --product FirstRow -j 4` with the portable dependencies described in `Portable/README.md`.

The implementation was validated with 10 passing Linux tests and a successful Linux debug build. A local HTTP Plex fixture also exercised Movies previews, TV Shows → show → season → episode, and Classic/Modern rendering using the offscreen keyboard harness. No personal Plex credentials were used. Actual network media playback, physical remote input, and Apple platform compilation were not validated here. The existing Xcode test suite and macOS build require macOS with Xcode; they have not run in this Linux environment.
