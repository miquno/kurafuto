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

    func testNewJavaServerNeedsEULABeforeStart() async throws {
        let s = MockCraftyService(latency: .zero)
        let id = try await s.createServer(CreateServerRequest(name: "Fresh", kind: .java, jarType: "paper", version: "1.21.4",
                                                              memMinGB: 1, memMaxGB: 2, port: 25570))
        do {
            try await s.send(.start, serverID: id)
            XCTFail("start must ask for the EULA first")
        } catch CraftyError.eulaRequired {}
        try await s.acceptEULA(serverID: id)
        let starting = try await s.stats(serverID: id)
        XCTAssertEqual(starting.status, .starting, "accepting the EULA also starts the server")
        try await s.send(.start, serverID: id)
    }

    func testEULAAcceptedAtCreationStartsDirectly() async throws {
        let s = MockCraftyService(latency: .zero)
        let id = try await s.createServer(CreateServerRequest(name: "Fresh", kind: .java, agreeToEULA: true))
        try await s.send(.start, serverID: id)
    }

    func testJavaCreateBodyCarriesEULAChoice() throws {
        let body = try JSONEncoder().encode(CreateServerRequest(name: "Fresh", kind: .java, agreeToEULA: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let java = try XCTUnwrap(json["minecraft_java_create_data"] as? [String: Any])
        let download = try XCTUnwrap(java["download_jar_create_data"] as? [String: Any])
        XCTAssertEqual(download["agree_to_eula"] as? Bool, true)
    }

    func testExistingDemoServersStartWithoutEULA() async throws {
        let s = MockCraftyService(latency: .zero)
        try await s.send(.start, serverID: MockData.creativeID)
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
