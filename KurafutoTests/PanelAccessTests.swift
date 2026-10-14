import XCTest
@testable import Kurafuto

/// Panel-wide permissions as returned by a local Crafty 4.11.0 test panel (4.7.0 answers identically).
final class PanelAccessTests: XCTestCase {
    private func permissions(_ json: String) throws -> CraftyPermissions {
        let envelope = try JSONDecoder().decode(APIClient.Envelope<CraftyPermissions>.self, from: Data(json.utf8))
        return try XCTUnwrap(envelope.data)
    }

    func testSuperuserMayDoEverythingDespiteEmptyMask() throws {
        let access = PanelAccess(isSuperuser: true, permissions: try permissions(Self.admin))
        XCTAssertEqual(access.permissions.mask, "000")
        XCTAssertTrue(access.canCreateServers)
        XCTAssertTrue(access.canAddUsers)
        XCTAssertTrue(access.canAddRoles)
        XCTAssertTrue(access.showsAdmin)
    }

    func testUserWithoutPermissionsSeesNoAdminOrCreate() throws {
        let access = PanelAccess(isSuperuser: false, permissions: try permissions(Self.limited))
        XCTAssertFalse(access.canCreateServers)
        XCTAssertFalse(access.canManageUsers)
        XCTAssertFalse(access.canManageRoles)
        XCTAssertFalse(access.showsAdmin)
    }

    /// Mask "101": server creation (limit 2) and roles config (limit 0), no user config.
    func testGrantedBitsAndLimits() throws {
        let access = PanelAccess(isSuperuser: false, permissions: try permissions(Self.granted))
        XCTAssertTrue(access.canCreateServers)
        XCTAssertFalse(access.canManageUsers)
        XCTAssertTrue(access.canManageRoles)
        XCTAssertFalse(access.canAddRoles, "a limit of 0 blocks adding, like Crafty's can_add_in_crafty")
        XCTAssertTrue(access.showsAdmin)
    }

    func testCreationStopsAtLimitAndMinusOneIsUnlimited() {
        let atLimit = CraftyPermissions(mask: "100", counters: ["SERVER_CREATION": 2], limits: ["SERVER_CREATION": 2])
        XCTAssertFalse(atLimit.canAdd(.serverCreation))
        let unlimited = CraftyPermissions(mask: "100", counters: ["SERVER_CREATION": 50], limits: ["SERVER_CREATION": -1])
        XCTAssertTrue(unlimited.canAdd(.serverCreation))
        XCTAssertFalse(CraftyPermissions(mask: "").has(.serverCreation), "a short mask grants nothing")
    }

    func testMockReportsConfiguredAccess() async throws {
        let limited = PanelAccess(isSuperuser: false, permissions: CraftyPermissions(mask: "000"))
        let access = try await MockCraftyService(latency: .zero, access: limited).panelAccess()
        XCTAssertFalse(access.showsAdmin)
        let demo = try await MockCraftyService(latency: .zero).panelAccess()
        XCTAssertTrue(demo.isSuperuser)
    }

    private static let admin = #"""
{
  "status": "ok",
  "data": {
    "permissions": "000",
    "counters": {
      "SERVER_CREATION": 1,
      "USER_CONFIG": 0,
      "ROLES_CONFIG": 0
    },
    "limits": {
      "SERVER_CREATION": 0,
      "USER_CONFIG": 0,
      "ROLES_CONFIG": 0
    }
  }
}
"""#

    private static let limited = #"""
{
  "status": "ok",
  "data": {
    "permissions": "000",
    "counters": {
      "SERVER_CREATION": 0,
      "USER_CONFIG": 0,
      "ROLES_CONFIG": 0
    },
    "limits": {
      "SERVER_CREATION": 0,
      "USER_CONFIG": 0,
      "ROLES_CONFIG": 0
    }
  }
}
"""#

    private static let granted = #"""
{
  "status": "ok",
  "data": {
    "permissions": "101",
    "counters": {
      "SERVER_CREATION": 0,
      "USER_CONFIG": 0,
      "ROLES_CONFIG": 0
    },
    "limits": {
      "SERVER_CREATION": 2,
      "USER_CONFIG": 0,
      "ROLES_CONFIG": 0
    }
  }
}
"""#
}
