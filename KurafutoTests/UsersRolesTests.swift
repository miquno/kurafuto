import XCTest
@testable import Kurafuto

/// User and role routes as Crafty 4.7.0 and 4.11.0 define them (`routes/api/users`, `routes/api/roles`).
/// Requests go to `StubPanel`, never to the network; the responses are captured from local test panels.
final class UsersRolesTests: XCTestCase {
    override func tearDown() {
        StubPanel.reset()
        super.tearDown()
    }

    private func live() throws -> LiveCraftyService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubPanel.self]
        return LiveCraftyService(client: APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.test:8443")),
                                                   token: "t", configuration: configuration))
    }

    // MARK: Permission bits

    /// `EnumPermissionsServer` in 4.7.0 and 4.11.0; checked on both panels by granting one bit at a time.
    func testServerPermissionBitOrderMatchesCrafty() {
        XCTAssertEqual(ServerPermission.allCases.map(\.rawValue), Array(0...7))
        XCTAssertEqual(ServerPermission.allCases, [.commands, .terminal, .logs, .schedule, .backup, .files, .config, .players])
        let mask = RoleServerPermission(serverID: "s", permissions: "10100110")
        XCTAssertEqual(ServerPermission.allCases.filter(mask.has), [.commands, .logs, .files, .config])
        var edited = RoleServerPermission(serverID: "s", permissions: "")
        edited.set(.players, true)
        XCTAssertEqual(edited.permissions, "00000001")
    }

    func testMaskValidationMatchesRoleSchema() {
        XCTAssertTrue(RoleServerPermission.isValidMask("00100000"))
        for bad in ["", "0010000", "001000000", "0010000x"] { XCTAssertFalse(RoleServerPermission.isValidMask(bad), bad) }
    }

    // MARK: Users

    private static let usersList = #"""
    {"status":"ok","data":[{"user_id":1,"created":"10/14/2026, 20:15:55","username":"admin","enabled":true,"superuser":true,"lang":"en_EN"},
    {"user_id":4,"created":"10/15/2026, 15:41:27","username":"kfprobe","enabled":true,"superuser":false,"lang":"de_DE"}]}
    """#
    private static let adminDetail = #"""
    {"status":"ok","data":{"user_id":1,"created":"10/14/2026, 20:15:55","last_login":"10/15/2026, 15:40:02","last_update":"10/14/2026, 20:15:55","last_ip":"192.168.215.1","username":"admin","email":"default@example.com","enabled":true,"superuser":true,"lang":"en_EN","manager":null,"roles":[]}}
    """#
    private static let probeDetail = #"""
    {"status":"ok","data":{"user_id":4,"created":"10/15/2026, 15:41:27","last_login":"","last_update":"10/15/2026, 15:41:27","last_ip":"","username":"kfprobe","email":"default@example.com","enabled":true,"superuser":false,"lang":"de_DE","manager":null,"roles":[{"role_id":1,"created":"10/15/2026, 15:41:19","last_update":"2026-10-15T15:41:19.668465","role_name":"kf probe","manager":null,"mfa_required":false}]}}
    """#

    func testUsersComeWithRolesFromTheirDetail() async throws {
        StubPanel.respond(200, Self.usersList)
        StubPanel.respond(200, Self.adminDetail)
        StubPanel.respond(200, Self.probeDetail)
        let users = try await live().users()
        XCTAssertEqual(StubPanel.requests.first?.line, "GET /api/v2/users")
        XCTAssertEqual(Set(StubPanel.requests.dropFirst().map(\.line)), ["GET /api/v2/users/1", "GET /api/v2/users/4"])
        XCTAssertEqual(users.map(\.username), ["admin", "kfprobe"])
        XCTAssertEqual(users[1].roleIDs, [1])
        XCTAssertNil(users[1].lastLogin, "the panel sends an empty string before the first login")
        XCTAssertEqual(users[0].lastIP, "192.168.215.1")
    }

    func testNewUserIsPostedWithExactlyTheAcceptedKeys() async throws {
        var user = CraftyUser.new()
        user.username = "steve"; user.roleIDs = [2, 1]
        let changes = UserChanges(from: nil, to: user, password: "probe-pass-123")
        StubPanel.respond(201, #"{"status":"ok","data":{"user_id":"5"}}"#)
        try await live().saveUser(id: 0, changes: changes)
        XCTAssertEqual(StubPanel.requests.first?.line, "POST /api/v2/users")
        let body = try XCTUnwrap(StubPanel.requests.first?.json)
        XCTAssertEqual(Set(body.keys), ["username", "password", "enabled", "lang", "roles"], "superuser only when granted")
        XCTAssertEqual(body["roles"] as? [Int], [1, 2])
        XCTAssertEqual(body["password"] as? String, "probe-pass-123")
    }

    func testEditSendsOnlyWhatChanged() async throws {
        let old = MockData.users[1]
        var new = old
        new.enabled = false; new.roleIDs = []
        let changes = UserChanges(from: old, to: new, password: "")
        StubPanel.respond(200, #"{"status":"ok"}"#)
        try await live().saveUser(id: old.userID, changes: changes)
        XCTAssertEqual(StubPanel.requests.first?.line, "PATCH /api/v2/users/\(old.userID)")
        let body = try XCTUnwrap(StubPanel.requests.first?.json)
        XCTAssertEqual(Set(body.keys), ["enabled", "roles"])
        XCTAssertNil(body["password"], "an empty password field keeps the password")
    }

    func testUnchangedUserSendsNothing() async throws {
        let changes = UserChanges(from: MockData.users[1], to: MockData.users[1], password: "")
        XCTAssertTrue(changes.isEmpty)
        try await live().saveUser(id: MockData.users[1].userID, changes: changes)
        XCTAssertTrue(StubPanel.requests.isEmpty)
    }

    func testUserValidationMirrorsTheSchema() {
        var user = CraftyUser.new()
        for good in ["steve", "kf_probe_2", "abc"] {
            user.username = good
            XCTAssertNil(UserChanges.problem(for: user, password: "probe-pass", isNew: true), good)
        }
        for bad in ["", "ab", "Steve", "steve smith", "system", String(repeating: "a", count: 21)] {
            user.username = bad
            XCTAssertNotNil(UserChanges.problem(for: user, password: "probe-pass", isNew: true), bad)
        }
        user.username = "steve"
        XCTAssertNotNil(UserChanges.problem(for: user, password: "", isNew: true), "new users need a password")
        XCTAssertNotNil(UserChanges.problem(for: user, password: "short", isNew: false))
        XCTAssertNil(UserChanges.problem(for: user, password: "", isNew: false))
    }

    func testDuplicateUsernameErrorIsShown() async throws {
        StubPanel.respond(400, #"{"status":"error","error":"USER_EXISTS","error_data":"UNIQUE VALUE ERROR"}"#)
        var user = CraftyUser.new(); user.username = "admin"
        do {
            try await live().saveUser(id: 0, changes: UserChanges(from: nil, to: user, password: "probe-pass-123"))
            XCTFail("expected an error")
        } catch CraftyError.server(let code, _) {
            XCTAssertEqual(code, "USER_EXISTS")
        }
    }

    func testPanelAccessKnowsTheSignedInUser() async throws {
        StubPanel.respond(200, #"{"status":"ok","data":{"user_id":3,"username":"kftlimited","superuser":false}}"#)
        let service = try live()
        // Both requests get the same canned answer; `permissions` decodes leniently to an empty mask.
        let access = try await service.panelAccess()
        XCTAssertEqual(access.userID, 3)
        XCTAssertFalse(access.isSuperuser)
    }

    // MARK: Roles

    func testRolesComeWithTheirServers() async throws {
        StubPanel.respond(200, #"{"status":"ok","data":[{"role_id":1,"created":"10/15/2026, 15:41:19","last_update":"2026-10-15T15:41:19.668465","role_name":"kf probe","manager":null,"mfa_required":false}]}"#)
        StubPanel.respond(200, #"{"status":"ok","data":[{"server_id":"7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84","permissions":"10100110"}]}"#)
        let roles = try await live().roles()
        XCTAssertEqual(StubPanel.requests.map(\.line), ["GET /api/v2/roles", "GET /api/v2/roles/1/servers"])
        XCTAssertEqual(roles.first?.roleName, "kf probe")
        XCTAssertEqual(roles.first?.servers, [RoleServerPermission(serverID: "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84", permissions: "10100110")])
    }

    func testRoleServersStayUnknownForNonSuperusers() async throws {
        StubPanel.respond(200, #"{"status":"ok","data":[{"role_id":1,"role_name":"mods","manager":3,"mfa_required":true}]}"#)
        StubPanel.respond(400, #"{"status":"error","error":"NOT_AUTHORIZED","error_data":"Permission Error"}"#)
        let roles = try await live().roles()
        XCTAssertEqual(roles.map(\.roleName), ["mods"])
        XCTAssertNil(roles.first?.servers)
        XCTAssertEqual(roles.first?.manager, 3)
    }

    func testRoleBodies() async throws {
        let service = try live()
        StubPanel.respond(200, #"{"status":"ok","data":{"role_id":2}}"#)
        var new = Role.new()
        new.roleName = " Mods "
        new.servers = [RoleServerPermission(serverID: "a", permissions: "00100000"), RoleServerPermission(serverID: "b", permissions: "1")]
        try await service.saveRole(new)
        var unknown = Role(roleID: 2, roleName: "mods", manager: 3, mfaRequired: true, servers: nil)
        try await service.saveRole(unknown)
        unknown.roleID = 0
        try await service.saveRole(unknown)

        XCTAssertEqual(StubPanel.requests.map(\.line), ["POST /api/v2/roles", "PATCH /api/v2/roles/2", "POST /api/v2/roles"])
        let created = try XCTUnwrap(StubPanel.requests[0].json)
        XCTAssertEqual(Set(created.keys), ["name", "servers", "mfa_required"], "no manager: only superusers may set it")
        XCTAssertEqual(created["name"] as? String, "Mods")
        XCTAssertEqual((created["servers"] as? [[String: String]])?.map { $0["server_id"] }, ["a"], "invalid masks never go out")
        XCTAssertEqual(Set(try XCTUnwrap(StubPanel.requests[1].json).keys), ["name", "mfa_required"],
                       "unknown servers stay out of a patch so the panel keeps them")
        XCTAssertEqual(StubPanel.requests[2].json?["servers"] as? [[String: String]], [], "creating needs the servers key")
    }

    func testRoleNameRule() {
        XCTAssertTrue(Role.isValidName("Moderators"))
        for bad in ["", "  ", "a,b", "[x]"] { XCTAssertFalse(Role.isValidName(bad), bad) }
    }

    // MARK: Mock

    func testMockAppliesUserChangesAndKeepsUnknownRoleServers() async throws {
        let mock = MockCraftyService(latency: .zero)
        var user = CraftyUser.new(); user.username = "newbie"
        try await mock.saveUser(id: 0, changes: UserChanges(from: nil, to: user, password: "probe-pass-123"))
        let added = try await mock.users().last
        XCTAssertEqual(added?.username, "newbie")
        XCTAssertNotEqual(added?.userID, 0)

        let roles = try await mock.roles()
        var role = try XCTUnwrap(roles.first)
        let servers = role.servers
        role.servers = nil; role.roleName = "Mods"
        try await mock.saveRole(role)
        let saved = try await mock.roles().first
        XCTAssertEqual(saved?.roleName, "Mods")
        XCTAssertEqual(saved?.servers, servers)
    }
}
