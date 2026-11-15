import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if FIRSTROW_PORTABLE
@testable import FirstRow
#else
@testable import First_Row
#endif

private final class PlexFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    static func recordedRequests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let path = request.url!.path
        let start = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "X-Plex-Container-Start" }?.value ?? "0"
        let body: String
        switch path {
        case "/library/sections":
            body = #"{"Directory":[{"key":"1","title":"Cinema","type":"movie"},{"key":"2","title":"Series","type":"show"},{"key":"3","title":"Music","type":"artist"}]}"#
        case "/library/sections/1/all":
            if start == "0" {
                body = #"{"totalSize":2,"Metadata":[{"ratingKey":"10","type":"movie","title":"Same Title","summary":"A movie","year":2001,"duration":120000,"viewOffset":30000,"viewCount":0,"guid":"plex://movie/10","thumb":"/art/10"}]}"#
            } else {
                body = #"{"totalSize":2,"Metadata":[{"ratingKey":"11","type":"movie","title":"Same Title","year":2020,"viewCount":1}]}"#
            }
        case "/library/sections/2/all":
            body = #"{"Metadata":[{"ratingKey":"20","type":"show","title":"Series","leafCount":2,"viewedLeafCount":1}]}"#
        case "/library/metadata/10":
            body = #"{"Metadata":[{"ratingKey":"10","Media":[{"Part":[{"key":"/library/parts/10/file.mkv","Stream":[{"streamType":2,"languageTag":"en"},{"streamType":3,"key":"/library/streams/30","languageTag":"el","title":"Greek"}]}]}]}]}"#
        case "/library/metadata/20/children":
            body = #"{"Metadata":[{"ratingKey":"21","type":"season","title":"Season 1"}]}"#
        case "/library/metadata/21/children":
            body = #"{"Metadata":[{"ratingKey":"22","type":"episode","title":"Pilot","grandparentTitle":"Series","parentIndex":1,"index":1,"duration":60000,"viewOffset":10000,"thumb":"/art/22"}]}"#
        default: body = #"{"Metadata":[]}"#
        }
        let data = Data(("{\"MediaContainer\":" + body + "}").utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PlexLibraryTests: XCTestCase {
    private func api() -> PlexClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlexFixtureProtocol.self]
        var client = PlexClient(baseURL: URL(string: "https://fixture.invalid")!, token: "fixture", caller: PlexCaller(clientID: "test", deviceName: "Tests"))
        client.session = URLSession(configuration: configuration)
        return client
    }
    private func record(_ id: String) -> MediaServerRecord {
        MediaServerRecord(id: id, kind: .plex, name: id, address: "https://fixture.invalid")
    }

    func testMoviesPreserveMetadataAndPaginateWithoutTitleDeduplication() async throws {
        let client = api()
        let result = await PlexLibraryIndex.load(servers: [record("a")]) { _ in client }
        XCTAssertEqual(result.failures, 0)
        XCTAssertEqual(result.entries.filter { $0.item.kind == .movie }.count, 2)
        let movie = try XCTUnwrap(result.entries.first { $0.item.id == "plex:10" })
        XCTAssertEqual(movie.libraryID, "plex:section:1")
        XCTAssertEqual(movie.item.overview, "A movie")
        XCTAssertEqual(movie.item.year, 2001)
        XCTAssertEqual(movie.item.durationSeconds, 120)
        XCTAssertEqual(movie.item.resumeSeconds, 30)
        XCTAssertNotNil(movie.item.imageURL)
        XCTAssertFalse(movie.item.isUnwatched)
        XCTAssertFalse(try XCTUnwrap(result.entries.first { $0.item.id == "plex:11" }).item.isUnwatched)
    }

    func testShowsNavigateThroughSeasonsToEpisodes() async throws {
        let client = api()
        let result = await PlexLibraryIndex.load(servers: [record("a")]) { _ in client }
        let show = try XCTUnwrap(result.entries.first { $0.item.kind == .show })
        XCTAssertEqual(show.libraryID, "plex:section:2")
        XCTAssertTrue(show.item.isUnwatched)
        let seasons = try await client.children(of: show.item)
        XCTAssertEqual(seasons.map(\.kind), [.season])
        let episodes = try await client.children(of: seasons[0])
        XCTAssertEqual(episodes.map(\.kind), [.episode])
        XCTAssertEqual(episodes[0].title, "1. Pilot")
        XCTAssertEqual(episodes[0].showTitle, "Series")
        XCTAssertEqual(episodes[0].resumeSeconds, 10)
    }

    func testMultipleServersKeepScopedIdentityAndDeduplicateOnlyKnownIdentifiers() async {
        let client = api()
        let result = await PlexLibraryIndex.load(servers: [record("a"), record("b")]) { _ in client }
        // Shared Plex GUID is one movie; unknown same-title movies/shows remain separate.
        XCTAssertEqual(result.entries.count, 5)
        XCTAssertEqual(Set(result.entries.map(\.id)).count, 5)
        XCTAssertEqual(Set(result.entries.filter { $0.item.id == "plex:11" }.map(\.serverID)), ["a", "b"])
    }

    func testFailureDoesNotHideReachableLibraries() async {
        struct Offline: MediaServerClient {
            func top() async throws -> [ServerItem] { throw MediaServerError.unreachable }
            func children(of item: ServerItem) async throws -> [ServerItem] { [] }
            func video(for item: ServerItem) async throws -> ServerVideo { throw MediaServerError.nothingPlayable }
        }
        let client = api()
        let result = await PlexLibraryIndex.load(servers: [record("a"), record("offline")]) { record in
            if record.id == "offline" { return Offline() }
            return client
        }
        XCTAssertEqual(result.failures, 1)
        XCTAssertEqual(result.entries.count, 3)
    }

    func testCancelledIndexDoesNotPublishPartialResults() async {
        struct WaitingServer: MediaServerClient {
            let started: XCTestExpectation
            func top() async throws -> [ServerItem] {
                started.fulfill()
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return []
            }
            func children(of item: ServerItem) async throws -> [ServerItem] { [] }
            func video(for item: ServerItem) async throws -> ServerVideo { throw MediaServerError.nothingPlayable }
        }
        let started = expectation(description: "Server request started")
        let task = Task {
            await PlexLibraryIndex.load(servers: [record("a")]) { _ in WaitingServer(started: started) }
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.failures, 0)
    }
}

extension PlexLibraryTests {
    @MainActor
    func testIntegratedRowsAndPreviewUseExistingMenus() async throws {
        let client = api()
        let result = await PlexLibraryIndex.load(servers: [record("a")]) { _ in client }
        let menu = MenuView()
        menu.plexLibraryEntries = result.entries
        menu.activeRootItemID = "movies"
        menu.isInSubmenu = true
        let movieRows = menu.currentSubmenuItems()
        XCTAssertTrue(movieRows.contains { $0.id == "movies_folder" })
        let movie = try XCTUnwrap(result.entries.first { $0.item.id == "plex:10" })
        menu.selectedSubIndex = try XCTUnwrap(movieRows.firstIndex { $0.id == movie.id })
        XCTAssertEqual(menu.selectedServerItem, movie.item)
        XCTAssertTrue(movieRows[menu.selectedSubIndex].trailingText?.contains("Cinema") == true)
        XCTAssertFalse(movieRows.contains { $0.id == result.entries.first { $0.item.kind == .show }?.id })
        menu.activeRootItemID = "tv_shows"
        menu.tvLibrary = TVShowLibrary(episodes: [TVEpisode(url: URL(fileURLWithPath: "/fixture/Local.S01E01.mp4"), show: "Local Show", showKey: "local", season: 1, episode: 1, title: "Local Pilot")])
        let showRows = menu.currentSubmenuItems()
        XCTAssertTrue(showRows.contains { $0.id == "tv_itunestopepisodes" })
        XCTAssertTrue(showRows.contains { $0.id == "tvshow|local" })
        XCTAssertEqual(showRows.filter { $0.id.hasPrefix("plex-library|") }.count, 1)
        let show = try XCTUnwrap(result.entries.first { $0.item.kind == .show })
        let seasons = try await client.children(of: show.item)
        menu.thirdMenuMode = .server
        menu.isInThirdMenu = true
        menu.servers.pages = [ServerPageState(page: .list(serverID: show.serverID, show.item), items: seasons, isLoaded: true)]
        XCTAssertTrue(menu.serverMenuListItems().contains { $0.title == "Season 1" && $0.leadsToMenu })
        menu.selectedThirdIndex = 0
        XCTAssertEqual(menu.selectedServerItem?.kind, .season)
    }
}


extension PlexLibraryTests {
    func testIntegratedMovieUsesExistingPlaybackSubtitlesAndProgressAPI() async throws {
        let client = api()
        let result = await PlexLibraryIndex.load(servers: [record("a")]) { _ in client }
        let movie = try XCTUnwrap(result.entries.first { $0.item.id == "plex:10" }).item
        let video = try await client.video(for: movie)
        XCTAssertEqual(video.url.path, "/library/parts/10/file.mkv")
        XCTAssertTrue(video.url.absoluteString.contains("X-Plex-Token=fixture"))
        XCTAssertEqual(video.subtitleFiles.count, 1)
        XCTAssertEqual(video.subtitleFiles[0].language, "el")
        await client.note(.paused, of: movie, seconds: movie.resumeSeconds)
        await client.note(.ended, of: movie, seconds: movie.durationSeconds)
        let requests = PlexFixtureProtocol.recordedRequests()
        XCTAssertTrue(requests.contains {
            $0.url?.path == "/:/timeline" && $0.url!.absoluteString.contains("time=30000") && $0.url!.absoluteString.contains("state=paused")
        })
        XCTAssertTrue(requests.contains { $0.url?.path == "/:/scrobble" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Plex-Token") == "fixture" })
    }

    func testRepeatedItemInTwoLibrariesIsOneEntryWithoutTitleMatching() {
        let item = ServerItem(id: "plex:1", kind: .movie, title: "One")
        let first = PlexLibraryEntry(serverID: "a", libraryID: "1", sourceTitle: "A", item: item)
        var second = first
        second.libraryID = "2"
        XCTAssertEqual(PlexLibraryIndex.unique([first, second]).count, 1)
        second.item.id = "plex:2"
        XCTAssertEqual(PlexLibraryIndex.unique([first, second]).count, 2)
        second.serverID = "b"
        second.item.id = item.id
        XCTAssertEqual(PlexLibraryIndex.unique([first, second]).count, 2)
    }
}

extension PlexLibraryTests {
    func testSameShowAcrossLibrariesKeepsAllSeasonsAndRoutesEpisodesToTheirServer() async throws {
        struct ShowFixture: MediaServerClient {
            let server: String
            func top() async throws -> [ServerItem] { [] }
            func video(for item: ServerItem) async throws -> ServerVideo { throw MediaServerError.nothingPlayable }
            func children(of item: ServerItem) async throws -> [ServerItem] {
                if item.details["path"] == "/show" {
                    return [ServerItem(id: "season-" + server, kind: .season, title: "Season 1", details: ["path": "/season", "plexSeasonIndex": "1"])]
                }
                return [ServerItem(id: "episode-" + server, kind: .episode, title: "Episode " + server, details: ["ratingKey": server])]
            }
        }
        let show = ServerItem(id: "show", kind: .show, title: "Shared Show", details: ["path": "/show", "guid": "plex://show/shared"])
        let rows = PlexLibraryIndex.unique([
            PlexLibraryEntry(serverID: "a", libraryID: "1", sourceTitle: "A", item: show),
            PlexLibraryEntry(serverID: "b", libraryID: "2", sourceTitle: "B", item: show),
        ])
        XCTAssertEqual(rows.count, 1)
        let seasons = try await PlexLibraryIndex.children(of: rows[0].item) { ShowFixture(server: $0) }
        XCTAssertEqual(seasons.count, 1)
        let episodes = try await PlexLibraryIndex.children(of: seasons[0]) { ShowFixture(server: $0) }
        XCTAssertEqual(Set(episodes.map { $0.details["plexIntegratedServerID"]! }), ["a", "b"])
        XCTAssertEqual(episodes.count, 2)
    }
}


extension PlexLibraryTests {
    func testFailedLibraryDoesNotDiscardOtherLibrariesOnSameServer() async {
        struct PartialServer: MediaServerClient {
            func top() async throws -> [ServerItem] {
                [ServerItem(id: "good", kind: .folder, title: "Good", details: ["type": "1"]),
                 ServerItem(id: "bad", kind: .folder, title: "Bad", details: ["type": "2"])]
            }
            func children(of item: ServerItem) async throws -> [ServerItem] {
                if item.id == "bad" { throw MediaServerError.unreachable }
                return [ServerItem(id: "movie", kind: .movie, title: "Kept")]
            }
            func video(for item: ServerItem) async throws -> ServerVideo { throw MediaServerError.nothingPlayable }
        }
        let result = await PlexLibraryIndex.load(servers: [record("a")]) { _ in PartialServer() }
        XCTAssertEqual(result.failures, 1)
        XCTAssertEqual(result.entries.map(\.item.title), ["Kept"])
    }
}
