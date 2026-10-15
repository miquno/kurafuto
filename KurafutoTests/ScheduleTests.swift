import XCTest
@testable import Kurafuto

/// Schedule bodies must pass the panel's `new_task_schema` / `task_patch_schema` (Crafty 4.7.0 and 4.11.0),
/// which reject unknown keys, and must carry the `command` the panel's task runner executes.
final class ScheduleTests: XCTestCase {
    private static let allowedKeys: Set<String> = ["name", "enabled", "action", "action_id", "interval", "interval_type",
                                                   "start_time", "command", "one_time", "cron_string", "parent", "delay"]

    private func body(_ schedule: Schedule) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schedule)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func schedule(_ action: ScheduleAction, _ type: IntervalType, command: String? = nil, cron: String? = nil,
                          parent: Int? = nil) -> Schedule {
        Schedule(id: 7, name: "Test", enabled: true, action: action, interval: 2, intervalType: type, startTime: "04:30",
                 command: command, parent: parent, oneTime: false, cronString: cron, delay: 90, nextRun: .now)
    }

    func testDailyRestartQueuesRestartServer() throws {
        let b = try body(schedule(.restart, .days))
        XCTAssertTrue(Set(b.keys).isSubset(of: Self.allowedKeys), "unknown keys: \(Set(b.keys).subtracting(Self.allowedKeys))")
        XCTAssertNil(b["schedule_id"])
        XCTAssertNil(b["next_run"])
        XCTAssertEqual(b["action"] as? String, "restart")
        XCTAssertEqual(b["command"] as? String, "restart_server")
        XCTAssertEqual(b["interval"] as? Int, 2)
        XCTAssertEqual(b["interval_type"] as? String, "days")
        XCTAssertEqual(b["start_time"] as? String, "04:30")
        XCTAssertEqual(b["cron_string"] as? String, "")
        XCTAssertTrue(b["parent"] is NSNull)
        XCTAssertEqual(b["delay"] as? Int, 0, "only chained schedules have a delay")
    }

    func testCustomCommandIsSentAsIs() throws {
        let b = try body(schedule(.command, .minutes, command: "say hi"))
        XCTAssertEqual(b["action"] as? String, "command")
        XCTAssertEqual(b["command"] as? String, "say hi")
        XCTAssertEqual(b["interval_type"] as? String, "minutes")
    }

    func testCronScheduleSendsEmptyIntervalType() throws {
        let b = try body(schedule(.stop, .cron, cron: "0 4 * * *"))
        XCTAssertEqual(b["interval_type"] as? String, "")
        XCTAssertEqual(b["cron_string"] as? String, "0 4 * * *")
        XCTAssertEqual(b["command"] as? String, "stop_server")
    }

    func testChainedScheduleSendsParentAndDelay() throws {
        let b = try body(schedule(.start, .reaction, cron: "* * * * *", parent: 3))
        XCTAssertEqual(b["interval_type"] as? String, "reaction")
        XCTAssertEqual(b["parent"] as? Int, 3)
        XCTAssertEqual(b["delay"] as? Int, 90)
        XCTAssertEqual(b["cron_string"] as? String, "", "a stale cron string must not turn the task into a cron task")
    }

    func testLiveServiceReportsThatSchedulesCannotBeListed() async throws {
        // No request is made: the panel has no list endpoint, so an unreachable address is fine.
        let live = LiveCraftyService(client: APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.invalid"))))
        let list = try await live.schedules(serverID: "x")
        XCTAssertNil(list)
    }

    func testMockListsCreatedSchedule() async throws {
        let s = MockCraftyService(latency: .zero)
        let id = MockData.servers[0].id
        try await s.createSchedule(schedule(.command, .hours, command: "save-all"), serverID: id)
        let listed = try await s.schedules(serverID: id)
        let list = try XCTUnwrap(listed)
        XCTAssertEqual(list.count, MockData.schedules.count + 1)
        XCTAssertEqual(list.last?.command, "save-all")
    }
}
