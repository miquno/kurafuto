import XCTest
@testable import Kurafuto

final class WidgetTests: XCTestCase {
    private func row(_ id: String, _ status: ServerStatus, _ online: Int = 0, _ max: Int = 20) -> WidgetSnapshot.Server {
        WidgetSnapshot.Server(id: id, name: id, status: status, online: online, max: max)
    }

    private func snapshot(_ servers: [WidgetSnapshot.Server], at date: Date = Date(timeIntervalSince1970: 1_000)) -> WidgetSnapshot {
        WidgetSnapshot(panelName: "Homelab", servers: servers, updated: date, isPrivate: false, mode: .dark, accent: .cyan)
    }

    func testSnapshotListsCrashedServersFirstAndOnlyCounts() {
        let servers = MockData.servers
        let s = WidgetSync.snapshot(panelName: "Homelab", servers: servers, stats: MockData.stats, isPrivate: true,
                                    mode: .light, accent: .pink)
        XCTAssertEqual(s.servers.count, servers.count)
        XCTAssertEqual(s.servers.first?.status, .crashed)
        XCTAssertEqual(Set(s.servers.map(\.id)), Set(servers.map(\.id)))
        let survival = s.servers.first { $0.id == MockData.survivalID }
        XCTAssertEqual(survival?.online, MockData.stats[MockData.survivalID]?.online)
        XCTAssertTrue(s.isPrivate)
        XCTAssertEqual(s.mode, .light)

        let unknown = WidgetSync.snapshot(panelName: "P", servers: [servers[0]], stats: [:], isPrivate: false, mode: .dark, accent: .cyan)
        XCTAssertEqual(unknown.servers.first?.status, .offline, "without stats a server counts as offline")
        XCTAssertEqual(unknown.servers.first?.max, 0)
    }

    /// The widgets must never learn the panel address, the username, a token or player names.
    func testSnapshotStoresOnlyNamesStatusAndCounts() throws {
        let data = try JSONEncoder().encode(snapshot([row("a", .online, 3)]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["panelName", "servers", "updated", "isPrivate", "mode", "accent"])
        let server = try XCTUnwrap((json["servers"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(server.keys), ["id", "name", "status", "online", "max"])
    }

    func testWritesOnlyWhenSomethingChangedOrTheTimeIsOld() {
        let base = snapshot([row("a", .online, 3)])
        XCTAssertTrue(WidgetSync.needsWrite(old: nil, new: base))
        XCTAssertFalse(WidgetSync.needsWrite(old: base, new: snapshot([row("a", .online, 3)], at: base.updated + 60)))
        XCTAssertTrue(WidgetSync.needsWrite(old: base, new: snapshot([row("a", .online, 4)], at: base.updated + 60)))
        XCTAssertTrue(WidgetSync.needsWrite(old: base, new: snapshot([row("a", .crashed)], at: base.updated + 5)))
        XCTAssertTrue(WidgetSync.needsWrite(old: base, new: snapshot([row("a", .online, 3)], at: base.updated + WidgetSync.refreshInterval)))
        var privateNow = base
        privateNow.isPrivate = true
        XCTAssertTrue(WidgetSync.needsWrite(old: base, new: privateNow))
    }

    func testStoreSavesLoadsAndClears() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)

        XCTAssertNil(store.load())
        let s = snapshot([row("a", .online, 3), row("b", .offline)])
        try store.save(s)
        XCTAssertEqual(store.load(), s)
        store.clear()
        XCTAssertNil(store.load())

        try Data("not json".utf8).write(to: try XCTUnwrap(store.fileURL))
        XCTAssertNil(store.load(), "a damaged file shows the empty widget instead of failing")
        XCTAssertNil(WidgetSnapshotStore(directory: nil).load())
    }

    func testWidgetShowsChosenServerElseTheBusiestOne() {
        let s = snapshot([row("crashed", .crashed), row("quiet", .online, 1), row("busy", .online, 7), row("off", .offline)])
        XCTAssertEqual(s.server(id: "quiet")?.id, "quiet")
        XCTAssertEqual(s.server(id: "gone")?.id, "busy")
        XCTAssertEqual(s.server(id: nil)?.id, "busy")
        XCTAssertEqual(snapshot([row("x", .offline), row("y", .crashed)]).server(id: nil)?.id, "x")
        XCTAssertNil(snapshot([]).server(id: nil))
    }

    func testServerLinksCarryOnlyAServerID() throws {
        let id = MockData.survivalID
        let url = try XCTUnwrap(ServerLink.url(serverID: id))
        XCTAssertEqual(url.absoluteString, "kurafuto://server/\(id)")
        XCTAssertEqual(ServerLink.serverID(from: url), id)

        for bad in ["https://server/\(id)", "kurafuto://stop/\(id)", "kurafuto://server/", "kurafuto://server/a/b",
                    "kurafuto://server/..", "kurafuto://server/a%2Fb", "kurafuto://server/a%20b"] {
            XCTAssertNil(URL(string: bad).flatMap(ServerLink.serverID(from:)), bad)
        }
        XCTAssertEqual(URL(string: "kurafuto://server/abc?x=1#y").flatMap(ServerLink.serverID(from:)), "abc",
                       "query and fragment are ignored, never acted on")
        XCTAssertNil(ServerLink.url(serverID: "../etc"))
        XCTAssertNil(ServerLink.url(serverID: String(repeating: "a", count: 65)))
    }
}
