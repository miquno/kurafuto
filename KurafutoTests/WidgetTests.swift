import XCTest
@testable import Kurafuto

final class WidgetTests: XCTestCase {
    private func row(_ id: String, _ status: ServerStatus, _ online: Int = 0, _ max: Int = 20) -> WidgetSnapshot.Server {
        WidgetSnapshot.Server(id: id, name: id, status: status, online: online, max: max)
    }

    private func snapshot(_ servers: [WidgetSnapshot.Server], at date: Date = Date(timeIntervalSince1970: 1_000)) -> WidgetSnapshot {
        WidgetSnapshot(panelName: "Homelab", servers: servers, updated: date, isPrivate: false, mode: .dark, accent: .cyan)
    }

    func testSnapshotListsCrashedServersFirstWithLoadPlayersAndBackups() throws {
        let servers = MockData.servers
        let survivalID = MockData.survivalID
        let history = [survivalID: (0..<120).map { StatSample(date: Date(timeIntervalSince1970: Double($0) * 30), cpu: Double($0), memBytes: 1) }]
        let backup = WidgetSnapshot.Backup(date: Date(timeIntervalSince1970: 1_000), configName: "Default Backup")
        let s = WidgetSync.snapshot(panelName: "Homelab", servers: servers, stats: MockData.stats, history: history,
                                    backups: [survivalID: backup], isPrivate: true, mode: .light, accent: .pink)
        XCTAssertEqual(s.servers.count, servers.count)
        XCTAssertEqual(s.servers.first?.status, .crashed)
        XCTAssertEqual(Set(s.servers.map(\.id)), Set(servers.map(\.id)))
        let survival = try XCTUnwrap(s.servers.first { $0.id == survivalID })
        let stats = try XCTUnwrap(MockData.stats[survivalID])
        XCTAssertEqual(survival.online, stats.online)
        XCTAssertEqual(survival.cpu, stats.cpu)
        XCTAssertEqual(survival.memBytes, stats.memBytes)
        XCTAssertEqual(survival.memLimitBytes, servers.first { $0.id == survivalID }?.maxMemoryBytes)
        XCTAssertEqual(survival.version, stats.version)
        XCTAssertEqual(survival.players, stats.players)
        XCTAssertEqual(survival.cpuTrend.count, WidgetSnapshot.trendPoints)
        XCTAssertEqual(survival.lastBackup, backup)
        XCTAssertTrue(s.isPrivate)
        XCTAssertEqual(s.mode, .light)

        let stopped = try XCTUnwrap(s.servers.first { MockData.stats[$0.id]?.running == false })
        XCTAssertNil(stopped.cpu, "a stopped server has no load")
        XCTAssertNil(stopped.memBytes)

        let unknown = WidgetSync.snapshot(panelName: "P", servers: [servers[0]], stats: [:], history: [:], backups: [:],
                                          isPrivate: false, mode: .dark, accent: .cyan)
        XCTAssertEqual(unknown.servers.first?.status, .offline, "without stats a server counts as offline")
        XCTAssertEqual(unknown.servers.first?.max, 0)
    }

    func testPlayerNamesAreCapped() throws {
        var stats = MockData.stats
        stats[MockData.survivalID]?.players = (1...20).map { "player\($0)" } + [String(repeating: "x", count: 100)]
        let s = WidgetSync.snapshot(panelName: "P", servers: MockData.servers, stats: stats, history: [:], backups: [:],
                                    isPrivate: false, mode: .dark, accent: .cyan)
        let names = try XCTUnwrap(s.servers.first { $0.id == MockData.survivalID }?.players)
        XCTAssertEqual(names.count, WidgetSnapshot.maxPlayers)
        XCTAssertTrue(names.allSatisfy { $0.count <= 32 })
    }

    /// The widgets must never learn the panel address, the username, a token, console output or files.
    func testSnapshotStoresOnlyTheAgreedFields() throws {
        var server = row("a", .online, 3)
        server.lastBackup = WidgetSnapshot.Backup(date: .now, configName: "Default")
        let data = try JSONEncoder().encode(snapshot([server]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["panelName", "servers", "updated", "isPrivate", "mode", "accent"])
        let first = try XCTUnwrap((json["servers"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["id", "name", "status", "online", "max", "cpuTrend", "memTrend", "players", "lastBackup"],
                       "nil values are left out; see WidgetSnapshot.Server for the full list")
        XCTAssertEqual(Set(((first["lastBackup"] as? [String: Any]) ?? [:]).keys), ["date", "configName"])
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

        var busier = row("a", .online, 3)
        busier.cpu = 80
        busier.cpuTrend = [1, 2, 3]
        XCTAssertFalse(WidgetSync.needsWrite(old: base, new: snapshot([busier], at: base.updated + 60)),
                       "live load alone waits for the refresh interval")
        var joined = row("a", .online, 3)
        joined.players = ["Lena"]
        XCTAssertTrue(WidgetSync.needsWrite(old: base, new: snapshot([joined], at: base.updated + 5)))
    }

    func testTrendKeepsShapeInFewPoints() {
        XCTAssertEqual(WidgetSnapshot.trend([1, 2, 3]), [1, 2, 3])
        let long = WidgetSnapshot.trend((0..<120).map(Double.init))
        XCTAssertEqual(long.count, WidgetSnapshot.trendPoints)
        XCTAssertEqual(long.first ?? -1, 2, accuracy: 0.001)
        XCTAssertEqual(long.last ?? -1, 117, accuracy: 0.001)
        XCTAssertEqual(long, long.sorted())
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

    func testServerLinksCarryOnlyAServerAndAScreen() throws {
        let id = MockData.survivalID
        let url = try XCTUnwrap(ServerLink.url(serverID: id))
        XCTAssertEqual(url.absoluteString, "kurafuto://server/\(id)")
        XCTAssertEqual(ServerLink.target(from: url), ServerLink.Target(serverID: id))
        let console = try XCTUnwrap(ServerLink.url(serverID: id, screen: .console))
        XCTAssertEqual(console.absoluteString, "kurafuto://server/\(id)/console")
        XCTAssertEqual(ServerLink.target(from: console), ServerLink.Target(serverID: id, screen: .console))
        XCTAssertEqual(ServerLink.target(from: try XCTUnwrap(ServerLink.url(serverID: id, screen: .details)))?.screen, .details)

        for bad in ["https://server/\(id)", "kurafuto://stop/\(id)", "kurafuto://server/", "kurafuto://server/a/b",
                    "kurafuto://server/a/console/x", "kurafuto://server/a/stop", "kurafuto://server/..",
                    "kurafuto://server/a%2Fb", "kurafuto://server/a%20b"] {
            XCTAssertNil(URL(string: bad).flatMap(ServerLink.target(from:)), bad)
        }
        XCTAssertEqual(URL(string: "kurafuto://server/abc?x=1#y").flatMap(ServerLink.target(from:)), ServerLink.Target(serverID: "abc"),
                       "query and fragment are ignored, never acted on")
        XCTAssertNil(ServerLink.url(serverID: "../etc"))
        XCTAssertNil(ServerLink.url(serverID: String(repeating: "a", count: 65)))
    }

    /// History and backups are only loaded for placed widgets, and backups only for a backup widget.
    @MainActor
    func testDashboardLoadsWidgetDetailsOnlyForPlacedWidgets() async {
        let none = DashboardModel()
        none.installedWidgets = { [] }
        none.attach(MockCraftyService(latency: .zero))
        await none.load()
        XCTAssertTrue(none.lastBackups.isEmpty)
        XCTAssertEqual(none.history.count, 1, "only the selected server's hour, as before")

        let server = DashboardModel()
        server.installedWidgets = { [WidgetKind.server] }
        server.attach(MockCraftyService(latency: .zero))
        await server.load()
        XCTAssertEqual(Set(server.history.keys), Set(MockData.servers.map(\.id)))
        XCTAssertTrue(server.lastBackups.isEmpty)

        let backup = DashboardModel()
        backup.installedWidgets = { [WidgetKind.backup] }
        backup.attach(MockCraftyService(latency: .zero))
        await backup.load()
        XCTAssertNotNil(backup.lastBackups[MockData.survivalID])
        XCTAssertEqual(backup.lastBackups[MockData.survivalID]?.configName, MockData.backupConfigs.first?.name)
    }
}
