import XCTest
@testable import Kurafuto

/// Responses captured from a local Crafty Controller 4.11.0 test panel (Paper 1.21.4 server).
/// They pin the quirks the live service has to handle.
final class CraftyResponseTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let envelope = try JSONDecoder().decode(APIClient.Envelope<T>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.status, "ok")
        return try XCTUnwrap(envelope.data)
    }

    func testServerListDecodes() throws {
        let servers = try decode([Server].self, Self.servers)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].serverName, "Kurafuto Test")
        XCTAssertEqual(servers[0].type, .minecraftJava)
        XCTAssertEqual(servers[0].serverPort, 25565)
    }

    func testStoppedStatsTreatPythonFalseAsMissing() throws {
        let s = try decode(ServerStats.self, Self.statsStopped)
        XCTAssertFalse(s.running)
        XCTAssertEqual(s.status, .offline)
        XCTAssertNil(s.started)
        XCTAssertNil(s.version)
        XCTAssertNil(s.desc)
        XCTAssertEqual(s.players, [])
        XCTAssertEqual(s.mem, "0MB")
    }

    func testRunningStatsFormatMemoryBytes() throws {
        let s = try decode(ServerStats.self, Self.statsRunning)
        XCTAssertTrue(s.running)
        XCTAssertEqual(s.status, .online)
        XCTAssertEqual(s.version, "Paper 1.21.4")
        XCTAssertEqual(s.max, 20)
        XCTAssertNil(s.icon, "an empty icon string means no icon")
        XCTAssertNotEqual(s.mem, "0MB")
        XCTAssertTrue(s.mem.contains("GB") || s.mem.contains("MB"), s.mem)
        XCTAssertNotNil(s.started.flatMap(ServerStats.startTime))
    }

    /// The first three lines are captured; the last is constructed to cover all five escaped characters.
    func testLogLinesAreUnescaped() throws {
        let lines = try decode([String].self, Self.logs).map(\.unescapingCraftyLogHTML)
        XCTAssertEqual(lines.last, "[20:21:02 INFO]: <miquno> it's \"fine\" & ok")
        XCTAssertFalse(lines.contains { $0.contains("&quot;") })
        XCTAssertEqual(LogLine(lines.last ?? "").level, .chat)
    }

    func testLoginOmitsEmptyTOTP() throws {
        // Crafty 4.11 answers `"totp": null` with INCORRECT_CREDENTIALS.
        let body = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(LoginRequest(username: "admin", password: "test", totp: nil))) as? [String: Any]
        XCTAssertEqual(body?.keys.sorted(), ["password", "username"])
    }

    private static let servers = #"""
{
  "status": "ok",
  "data": [
    {
      "server_id": "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84",
      "created": "2026-10-14T20:17:00.893086",
      "server_name": "Kurafuto Test",
      "path": "/crafty/servers/7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84",
      "executable": "paper.jar",
      "log_path": "./logs/latest.log",
      "execution_command": "java -Xms1000M -Xmx2000M -jar paper.jar nogui",
      "auto_start": false,
      "auto_start_delay": 10,
      "crash_detection": false,
      "stop_command": "stop",
      "executable_update_url": "https://jars.arcadiatech.org/paper/1.21.4/paper.jar",
      "server_ip": "127.0.0.1",
      "server_port": 25565,
      "logs_delete_after": 0,
      "type": "minecraft-java",
      "show_status": true,
      "created_by": 1,
      "shutdown_timeout": 60,
      "ignored_exits": "0",
      "app_id": null,
      "count_players": true,
      "update_watcher": false
    }
  ]
}
"""#

    private static let statsStopped = #"""
{
  "status": "ok",
  "data": {
    "stats_id": 7,
    "created": "2026-10-14T20:19:25.135469",
    "server_id": {
      "server_id": "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84",
      "created": "2026-10-14T20:17:00.893086",
      "server_name": "Kurafuto Test",
      "path": "/crafty/servers/7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84",
      "executable": "paper.jar",
      "log_path": "./logs/latest.log",
      "execution_command": "java -Xms1000M -Xmx2000M -jar paper.jar nogui",
      "auto_start": false,
      "auto_start_delay": 10,
      "crash_detection": false,
      "stop_command": "stop",
      "executable_update_url": "https://jars.arcadiatech.org/paper/1.21.4/paper.jar",
      "server_ip": "127.0.0.1",
      "server_port": 25565,
      "logs_delete_after": 0,
      "type": "minecraft-java",
      "show_status": true,
      "created_by": 1,
      "shutdown_timeout": 60,
      "ignored_exits": "0",
      "app_id": null,
      "count_players": true,
      "update_watcher": false
    },
    "started": "False",
    "running": false,
    "cpu": 0.0,
    "mem": 0.0,
    "mem_percent": 0.0,
    "world_name": "Kurafuto Test",
    "world_size": "134.0B",
    "server_port": 25565,
    "int_ping_results": "False",
    "online": 0,
    "max": 0,
    "players": "False",
    "desc": "False",
    "icon": null,
    "version": "False",
    "updating": false,
    "waiting_start": false,
    "crashed": false,
    "importing": false
  }
}
"""#

    private static let statsRunning = #"""
{
  "status": "ok",
  "data": {
    "stats_id": 9,
    "created": "2026-10-14T20:20:55.406465",
    "server_id": {
      "server_id": "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84",
      "created": "2026-10-14T20:17:00.893086",
      "server_name": "Kurafuto Test",
      "path": "/crafty/servers/7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84",
      "executable": "paper.jar",
      "log_path": "./logs/latest.log",
      "execution_command": "java -Xms1000M -Xmx2000M -jar paper.jar nogui",
      "auto_start": false,
      "auto_start_delay": 10,
      "crash_detection": false,
      "stop_command": "stop",
      "executable_update_url": "https://jars.arcadiatech.org/paper/1.21.4/paper.jar",
      "server_ip": "127.0.0.1",
      "server_port": 25565,
      "logs_delete_after": 0,
      "type": "minecraft-java",
      "show_status": true,
      "created_by": 1,
      "shutdown_timeout": 60,
      "ignored_exits": "0",
      "app_id": null,
      "count_players": true,
      "update_watcher": false
    },
    "started": "2026-10-14 18:20:24",
    "running": true,
    "cpu": 0.33,
    "mem": 1401933824.0,
    "mem_percent": 11.0,
    "world_name": "Kurafuto Test",
    "world_size": "134.0B",
    "server_port": 25565,
    "int_ping_results": "True",
    "online": 0,
    "max": 20,
    "players": "[]",
    "desc": "A Minecraft Server",
    "icon": "",
    "version": "Paper 1.21.4",
    "updating": false,
    "waiting_start": false,
    "crashed": false,
    "importing": false
  }
}
"""#

    private static let logs = #"""
{
  "status": "ok",
  "data": [
    "[20:20:28 INFO]: Done preparing level &quot;world&quot; (0.666s)",
    "[20:20:28 INFO]: Running delayed init tasks",
    "[20:20:28 INFO]: Done (3.637s)! For help, type &quot;help&quot;",
    "[20:21:02 INFO]: &lt;miquno&gt; it&#x27;s &quot;fine&quot; &amp; ok"
  ]
}
"""#
}
