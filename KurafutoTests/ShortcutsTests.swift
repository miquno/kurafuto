import XCTest
@testable import Kurafuto

/// Siri and Shortcuts actions: they act on the active panel only and keep the confirmations of the app.
@MainActor
final class ShortcutsTests: XCTestCase {
    private final class FakeAuthenticator: DeviceAuthenticating, @unchecked Sendable {
        var answer = false
        private(set) var reasons: [String] = []
        func kind() -> DeviceAuthKind { .faceID }
        func authenticate(reason: String) async -> Bool {
            reasons.append(reason)
            return answer
        }
    }

    private func app(lockedWith auth: FakeAuthenticator? = nil) throws -> (AppState, MockCraftyService) {
        let service = MockCraftyService(latency: .zero)
        var lock = AppLock(defaults: nil)
        if let auth {
            let suite = "ShortcutsTests-\(UUID().uuidString)"
            addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(true, forKey: AppLock.defaultsKey)
            lock = AppLock(authenticator: auth, defaults: defaults)
        }
        let state = AppState(instanceStore: InstanceStore(preview: [MockData.instance]), service: service,
                             activeInstance: MockData.instance, isMock: true, lock: lock)
        return (state, service)
    }

    func testNeedsAPanel() async throws {
        let empty = AppState(instanceStore: InstanceStore(preview: []), service: MockCraftyService(latency: .zero),
                             activeInstance: nil, isMock: true, lock: AppLock(defaults: nil))
        XCTAssertThrowsError(try ServerShortcuts.service(empty)) { XCTAssertEqual($0 as? ServerShortcuts.Failure, .noPanel) }
        XCTAssertThrowsError(try ServerShortcuts.service(nil)) { XCTAssertEqual($0 as? ServerShortcuts.Failure, .noPanel) }
    }

    func testStartsAServer() async throws {
        let (state, service) = try app()
        try await ServerShortcuts.start(serverID: MockData.creativeID, name: "Creative World", app: state)
        let stats = try await service.stats(serverID: MockData.creativeID)
        XCTAssertEqual(stats.status, .starting)
    }

    func testStartWithoutEULANamesTheServer() async throws {
        let (state, service) = try app()
        let id = try await service.createServer(CreateServerRequest(name: "Fresh", kind: .java))
        do {
            try await ServerShortcuts.start(serverID: id, name: "Fresh", app: state)
            XCTFail("the panel refuses to start without the EULA")
        } catch {
            XCTAssertEqual(error as? ServerShortcuts.Failure, .eulaRequired("Fresh"))
        }
    }

    func testStopsWithoutAppLock() async throws {
        let (state, service) = try app()
        try await ServerShortcuts.stop(serverID: MockData.survivalID, name: "Survival SMP", app: state)
        let stats = try await service.stats(serverID: MockData.survivalID)
        XCTAssertFalse(stats.running)
    }

    func testAppLockMustConfirmAStop() async throws {
        let auth = FakeAuthenticator()
        let (state, service) = try app(lockedWith: auth)

        do {
            try await ServerShortcuts.stop(serverID: MockData.survivalID, name: "Survival SMP", app: state)
            XCTFail("a refused Face ID check must not stop the server")
        } catch {
            XCTAssertEqual(error as? ServerShortcuts.Failure, .notConfirmed)
        }
        let stillRunning = try await service.stats(serverID: MockData.survivalID)
        XCTAssertTrue(stillRunning.running)

        auth.answer = true
        try await ServerShortcuts.stop(serverID: MockData.survivalID, name: "Survival SMP", app: state)
        let stopped = try await service.stats(serverID: MockData.survivalID)
        XCTAssertFalse(stopped.running)
        XCTAssertEqual(auth.reasons, ["Stop Survival SMP?", "Stop Survival SMP?"])
    }

    func testCountsPlayersLive() async throws {
        let (state, _) = try app()
        let survival = try await ServerShortcuts.players(serverID: MockData.survivalID, app: state)
        XCTAssertEqual(survival?.online, MockData.stats[MockData.survivalID]?.online)
        XCTAssertEqual(survival?.max, MockData.stats[MockData.survivalID]?.max)
        let stopped = try await ServerShortcuts.players(serverID: MockData.creativeID, app: state)
        XCTAssertNil(stopped, "a stopped server has no player count")
    }

    func testServerQueryListsAndMatchesTheActivePanelsServers() async throws {
        let (state, _) = try app()
        ServerShortcuts.app = state
        addTeardownBlock { @MainActor in ServerShortcuts.app = nil }

        let query = PanelServerQuery()
        let all = try await query.suggestedEntities()
        XCTAssertEqual(all.map(\.id), MockData.servers.map(\.id))
        let matched = try await query.entities(matching: "survival")
        XCTAssertEqual(matched.map(\.id), [MockData.survivalID])
        let byID = try await query.entities(for: [MockData.creativeID, "unknown"])
        XCTAssertEqual(byID.map(\.name), ["Creative World"])
    }
}
