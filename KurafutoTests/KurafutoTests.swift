import XCTest
@testable import Kurafuto

final class MockServiceTests: XCTestCase {
    func testStartTurnsServerOnline() async throws {
        let s = MockCraftyService(latency: .zero)
        let id = MockData.creativeID
        let before = try await s.stats(serverID: id)
        XCTAssertFalse(before.running)
        try await s.send(.start, serverID: id)
        let starting = try await s.stats(serverID: id)
        XCTAssertEqual(starting.status, .starting)
        try await Task.sleep(for: .seconds(3.5))
        let after = try await s.stats(serverID: id)
        XCTAssertTrue(after.running)
    }

    func testCommandAppearsInLogs() async throws {
        let s = MockCraftyService(latency: .zero)
        try await s.sendCommand("say hello", serverID: MockData.survivalID)
        let logs = try await s.logs(serverID: MockData.survivalID, fromFile: false)
        XCTAssertTrue(logs.contains("> say hello"))
    }

    func testStatsDecodesStringNumbersAndPlayerString() throws {
        // Real Crafty responses sometimes return numbers as strings and "players" as a string array literal.
        let json = #"""
        {"running": true, "cpu": "0.33", "mem": "42.2MB", "mem_percent": "5.0", "online": 2, "max": 20,
         "players": "['Steve', 'Alex']", "crashed": false, "updating": false, "waiting_start": false, "first_run": false}
        """#
        let stats = try JSONDecoder().decode(ServerStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.cpu, 0.33, accuracy: 0.001)
        XCTAssertEqual(stats.memPercent, 5.0)
        XCTAssertEqual(stats.players, ["Steve", "Alex"])
    }

    func testRolePermissionBits() {
        var p = RoleServerPermission(serverID: "x", permissions: "00000000")
        p.set(.backup, true)
        XCTAssertTrue(p.has(.backup))
        XCTAssertFalse(p.has(.files))
        XCTAssertEqual(p.permissions, "00001000")
    }

    func testOpenMetricsParser() {
        let text = "# HELP CPU_Usage x\nCPU_Usage 1.54\nMem_Usage{server_id=\"a\"} 63.8\n"
        let m = OpenMetricsParser.parse(text)
        XCTAssertEqual(m["CPU_Usage"], 1.54)
        XCTAssertEqual(m["Mem_Usage"], 63.8)
    }

    func testMotdFormattingIsStripped() {
        XCTAssertEqual("§aWelcome §lto the SMP".strippingMinecraftFormatting, "Welcome to the SMP")
    }

    func testSelectingActiveDemoPanelStaysInDemo() {
        let app = AppState.preview
        app.switchTo(MockData.instance)
        XCTAssertTrue(app.isMock)
        XCTAssertTrue(app.service is MockCraftyService)
    }
}
