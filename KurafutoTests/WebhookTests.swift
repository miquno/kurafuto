import XCTest
@testable import Kurafuto

/// Webhook and server config routes as Crafty 4.7.0 and 4.11.0 define them (`routes/api/servers/server/`).
/// Requests go to `StubPanel`, never to the network; the responses are captured from local test panels.
final class WebhookTests: XCTestCase {
    private static let serverID = "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84"

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

    /// `GET …/webhook` on 4.11.0: keyed by id, triggers as one string with a trailing comma, no id inside.
    private static let list = #"""
    {"status":"ok","data":{
     "2":{"webhook_type":"Slack","name":"Ops","url":"https://hooks.slack.example.com/x","bot_name":"Bot","trigger":"","body":"","color":"#005cd1","enabled":false},
     "1":{"webhook_type":"Discord","name":"Probe","url":"http://hooks.example.com:8080/x","bot_name":"Bot","trigger":"start_server,crash_detected,future_event,","body":"{{server_name}} {{event_type}}","color":"#5865F2","enabled":true},
     "x":{"webhook_type":"Discord","name":"Broken"}}}
    """#

    func testListDecodesPanelShape() async throws {
        StubPanel.respond(200, Self.list)
        let hooks = try await live().webhooks(serverID: Self.serverID)
        XCTAssertEqual(StubPanel.requests.first?.line, "GET /api/v2/servers/\(Self.serverID)/webhook")
        XCTAssertEqual(hooks.map(\.id), [1, 2], "sorted by id, non-numeric keys dropped")
        XCTAssertEqual(hooks[0].triggers, ["start_server", "crash_detected", "future_event"], "unknown triggers are kept")
        XCTAssertEqual(hooks[0].url, "http://hooks.example.com:8080/x")
        XCTAssertEqual(hooks[0].color, "#5865F2")
        XCTAssertTrue(hooks[0].enabled)
        XCTAssertEqual(hooks[1].triggers, [])
        XCTAssertFalse(hooks[1].enabled)
    }

    func testBodyCarriesExactlyTheKeysThePanelAccepts() throws {
        let data = try JSONEncoder().encode(WebhookBody(webhook: MockData.webhooks[0]))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["webhook_type", "name", "url", "bot_name", "trigger", "body", "color", "enabled"],
                       "additionalProperties: false; color is required on create")
        XCTAssertEqual(body["trigger"] as? [String], ["start_server", "stop_server", "crash_detected"])
    }

    func testNewWebhookIsPostedAndSavedOnePatchedUnderServersPath() async throws {
        let service = try live()
        StubPanel.respond(200, #"{"status":"ok","data":{"webhook_id":3}}"#)
        var hook = Webhook.new()
        hook.name = "Status"; hook.url = "https://discord.com/api/webhooks/1/x"
        try await service.saveWebhook(hook, serverID: Self.serverID)
        hook.id = 3
        try await service.saveWebhook(hook, serverID: Self.serverID)
        try await service.testWebhook(id: 3, serverID: Self.serverID)
        try await service.deleteWebhook(id: 3, serverID: Self.serverID)
        XCTAssertEqual(StubPanel.requests.map(\.line), [
            "POST /api/v2/servers/\(Self.serverID)/webhook",
            "PATCH /api/v2/servers/\(Self.serverID)/webhook/3",
            "POST /api/v2/servers/\(Self.serverID)/webhook/3",
            "DELETE /api/v2/servers/\(Self.serverID)/webhook/3",
        ])
        XCTAssertNil(StubPanel.requests[1].json?["webhook_id"])
    }

    func testFailedTestDeliveryIsShown() async throws {
        StubPanel.respond(500, #"{"status":"error","error":"WEBHOOK ERROR","error_data":"Failed to dispatch notification: Name or service not known"}"#)
        do {
            try await live().testWebhook(id: 1, serverID: Self.serverID)
            XCTFail("expected an error")
        } catch CraftyError.server(let code, let detail) {
            XCTAssertEqual(code, "WEBHOOK ERROR")
            XCTAssertEqual(detail, "Failed to dispatch notification: Name or service not known")
        }
    }

    func testURLAllowsHTTPAndHTTPSLikeThePanel() {
        for ok in ["https://discord.com/api/webhooks/1/abc", "http://chat.home.example:8065/hooks/x",
                   "http://192.168.1.20:8065/hooks/x", "https://[fd00::1]:8443/x", "HTTPS://Example.COM"] {
            XCTAssertTrue(WebhookURL.isValid(ok), ok)
        }
        for bad in ["", "discord.com/api/webhooks", "ftp://example.com/x", "http://localhost:8065/x", "https://",
                    "javascript:alert(1)", "https://example.com:70000/x", "https://exa mple.com", "https://example.com/a b"] {
            XCTAssertFalse(WebhookURL.isValid(bad), bad)
        }
    }

    func testValidationMirrorsThePanel() {
        var hook = Webhook.new()
        hook.name = "Status"; hook.url = "https://discord.com/api/webhooks/1/x"
        XCTAssertNil(hook.problem)
        var unknown = hook; unknown.type = "Custom"
        XCTAssertNotNil(unknown.problem, "the panel only knows Discord, Mattermost, Slack and Teams")
        var long = hook; long.name = String(repeating: "a", count: 31)
        XCTAssertNotNil(long.problem)
        var color = hook; color.color = "blue"
        XCTAssertNotNil(color.problem)
    }

    func testMockKeepsChanges() async throws {
        let mock = MockCraftyService(latency: .zero)
        var hook = Webhook.new()
        hook.name = "New"; hook.url = "https://example.com/hook"
        try await mock.saveWebhook(hook, serverID: "s")
        let saved = try await mock.webhooks(serverID: "s")
        XCTAssertEqual(saved.last?.name, "New")
        XCTAssertNotEqual(saved.last?.id, 0)
        try await mock.deleteWebhook(id: try XCTUnwrap(saved.last?.id), serverID: "s")
        let left = try await mock.webhooks(serverID: "s")
        XCTAssertEqual(left.count, saved.count - 1)
    }
}

final class ServerConfigTests: XCTestCase {
    private static let serverID = "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84"

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

    func testPatchSendsOnlyChangedFields() async throws {
        let old = MockData.servers[0]
        var new = old
        new.serverName = "  Survival  "; new.crashDetection.toggle(); new.ignoredExits = "0, 130"
        let patch = ServerConfigPatch(from: old, to: new)
        StubPanel.respond(200, #"{"status":"ok"}"#)
        try await live().updateServer(id: Self.serverID, changes: patch)
        XCTAssertEqual(StubPanel.requests.first?.line, "PATCH /api/v2/servers/\(Self.serverID)")
        let body = try XCTUnwrap(StubPanel.requests.first?.json)
        XCTAssertEqual(Set(body.keys), ["server_name", "crash_detection", "ignored_exits"], "the whole server fails the schema")
        XCTAssertEqual(body["server_name"] as? String, "Survival")
        XCTAssertEqual(body["ignored_exits"] as? String, "0,130", "the panel compares exit codes without spaces")
        XCTAssertFalse(patch.touchesSuperuserFields)
    }

    func testUnchangedServerSendsNothing() async throws {
        let patch = ServerConfigPatch(from: MockData.servers[0], to: MockData.servers[0])
        XCTAssertTrue(patch.isEmpty)
        try await live().updateServer(id: Self.serverID, changes: patch)
        XCTAssertTrue(StubPanel.requests.isEmpty)
    }

    func testSuperuserFieldsAreFlagged() {
        var new = MockData.servers[0]
        new.serverPort = 25570
        XCTAssertTrue(ServerConfigPatch(from: MockData.servers[0], to: new).touchesSuperuserFields)
    }

    func testValidationMirrorsTheSchema() {
        let base = MockData.servers[0]
        XCTAssertNil(ServerConfigPatch.problem(for: base))
        var s = base; s.serverName = "a/b"
        XCTAssertNotNil(ServerConfigPatch.problem(for: s))
        s = base; s.serverName = "x"
        XCTAssertNotNil(ServerConfigPatch.problem(for: s))
        s = base; s.executionCommand = " "
        XCTAssertNotNil(ServerConfigPatch.problem(for: s))
        s = base; s.serverPort = 0
        XCTAssertNotNil(ServerConfigPatch.problem(for: s))
        s = base; s.ignoredExits = "0,abc"
        XCTAssertNotNil(ServerConfigPatch.problem(for: s))
        s = base; s.ignoredExits = "0, -1, 130"
        XCTAssertNil(ServerConfigPatch.problem(for: s))
    }

    func testDeleteKeepsFilesUnlessAsked() async throws {
        let service = try live()
        StubPanel.respond(200, #"{"status":"ok"}"#)
        try await service.deleteServer(id: Self.serverID, deleteFiles: false)
        try await service.deleteServer(id: Self.serverID, deleteFiles: true)
        XCTAssertEqual(StubPanel.requests.map(\.line), Array(repeating: "DELETE /api/v2/servers/\(Self.serverID)", count: 2))
        XCTAssertEqual(StubPanel.requests.map(\.query), [nil, "files=true"])
    }

    func testSchemaErrorIsShown() async throws {
        StubPanel.respond(400, #"{"status":"error","error":"INVALID_JSON_SCHEMA","error_data":" Additional Properties are not allowed to be passed "}"#)
        var new = MockData.servers[0]; new.autoStart.toggle()
        do {
            try await live().updateServer(id: Self.serverID, changes: ServerConfigPatch(from: MockData.servers[0], to: new))
            XCTFail("expected an error")
        } catch CraftyError.server(let code, _) {
            XCTAssertEqual(code, "INVALID_JSON_SCHEMA")
        }
    }

    func testMockAppliesPatch() async throws {
        let mock = MockCraftyService(latency: .zero)
        let old = try await mock.servers()[0]
        var new = old; new.logsDeleteAfter = 30
        try await mock.updateServer(id: old.id, changes: ServerConfigPatch(from: old, to: new))
        let updated = try await mock.servers()[0]
        XCTAssertEqual(updated.logsDeleteAfter, 30)
        XCTAssertEqual(updated.serverName, old.serverName)
    }
}
