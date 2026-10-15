import XCTest
@testable import Kurafuto

/// Backup routes as the Crafty 4.7.0 and 4.11.0 source defines them (`routes/api/servers/server/backups`).
/// Requests go to a stub, never to the network; the responses are captured from local test panels.
final class BackupTests: XCTestCase {
    private static let serverID = "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84"
    private static let configID = "b46651a3-9793-4c5a-9b16-2a3ecdcaa9a7"

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

    private func config(_ kind: BackupConfig.Kind = .zip) -> BackupConfig {
        BackupConfig(id: Self.configID, name: "Default Backup", location: "/crafty/backups/x", isDefault: true, kind: kind)
    }

    // MARK: Configurations

    func testConfigsArriveWithoutEnvelopeAndDefaultComesFirst() async throws {
        StubPanel.respond(200, Self.configs)
        let list = try await live().backupConfigs(serverID: Self.serverID)
        XCTAssertEqual(StubPanel.requests.first?.line, "GET /api/v2/servers/\(Self.serverID)/backups")
        XCTAssertEqual(list.map(\.name), ["Default Backup", "Nightly"])
        XCTAssertEqual(list[0].id, Self.configID)
        XCTAssertEqual(list[0].maxBackups, 0)
        XCTAssertEqual(list[0].kind, .zip)
        XCTAssertEqual(list[1].excludedPaths, ["logs", "cache"])
        XCTAssertEqual(list[1].beforeCommand, "save-off")
    }

    func testConfigBodyOnlyCarriesKeysThePanelAccepts() throws {
        let allowed: Set<String> = ["backup_name", "backup_location", "max_backups", "compress", "shutdown", "before", "after",
                                    "excluded_dirs", "backup_type"]
        for includeLocation in [true, false] {
            let data = try JSONEncoder().encode(BackupConfigBody(config: config(), includeLocation: includeLocation))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertTrue(Set(body.keys).isSubset(of: allowed), "unknown keys: \(Set(body.keys).subtracting(allowed))")
            XCTAssertEqual(body["backup_location"] != nil, includeLocation, "only superusers may send a location")
            XCTAssertEqual(body["backup_name"] as? String, "Default Backup")
        }
    }

    func testNewConfigIsPostedAndExistingOnePatched() async throws {
        let service = try live()
        StubPanel.respond(200, #"{"status":"ok"}"#)
        var new = config(); new.id = ""
        try await service.saveBackupConfig(new, includeLocation: false, serverID: Self.serverID)
        try await service.saveBackupConfig(config(), includeLocation: false, serverID: Self.serverID)
        XCTAssertEqual(StubPanel.requests.map(\.line), [
            "POST /api/v2/servers/\(Self.serverID)/backups",
            "PATCH /api/v2/servers/\(Self.serverID)/backups/backup/\(Self.configID)",
        ])
    }

    func testInvalidConfigIDNeverReachesTheURL() async throws {
        let service = try live()
        var bad = config(); bad.id = "../../users"
        do {
            try await service.startBackup(serverID: Self.serverID, configID: bad.id)
            XCTFail("expected an error")
        } catch CraftyError.invalidURL {}
        _ = try? await service.backupFiles(serverID: Self.serverID, config: bad)
        XCTAssertTrue(StubPanel.requests.isEmpty)
        XCTAssertEqual(BackupConfig.sorted([bad, config()]).map(\.id), [Self.configID])
    }

    // MARK: Archives

    func testArchivesAreListedFromPathsAndUnexpectedNamesAreDropped() async throws {
        StubPanel.respond(200, """
        {"total":5,"backups":["/crafty/backups/x/\(Self.configID)/2026-10-14_20-49-04.zip",
        "/crafty/backups/x/\(Self.configID)/2026-10-15_06-00-00.zip",
        "/crafty/backups/x/\(Self.configID)/../../etc/passwd",
        "/crafty/backups/x/\(Self.configID)/world.zip",
        "/crafty/backups/x/\(Self.configID)/2026-13-40_99-99-99.zip"]}
        """)
        let listed = try await live().backupFiles(serverID: Self.serverID, config: config())
        let files = try XCTUnwrap(listed)
        XCTAssertEqual(StubPanel.requests.first?.line,
                       "GET /api/v2/servers/\(Self.serverID)/backups/backup/\(Self.configID)/files")
        XCTAssertEqual(files.map(\.name), ["2026-10-15_06-00-00.zip", "2026-10-14_20-49-04.zip"])
        let shown = files[1].created.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
        XCTAssertEqual(shown, "20:49", "the panel's wall-clock time shows unchanged")
    }

    func testPanelWithoutListEndpointReportsArchivesAsNotListable() async throws {
        StubPanel.respond(405, #"{"status":"error","error":"METHOD_NOT_ALLOWED","error_data":"METHOD NOT ALLOWED"}"#)
        let files = try await live().backupFiles(serverID: Self.serverID, config: config())
        XCTAssertNil(files)
    }

    func testSnapshotArchivesAreNotListable() async throws {
        let files = try await live().backupFiles(serverID: Self.serverID, config: config(.snapshot))
        XCTAssertNil(files)
        XCTAssertTrue(StubPanel.requests.isEmpty)
    }

    func testMissingBackupRightIsReportedAsPermissionProblem() async throws {
        StubPanel.respond(400, #"{"status":"error","error":"NOT_AUTHORIZED","error_data":"Authorization Error"}"#)
        do {
            _ = try await live().backupConfigs(serverID: Self.serverID)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.panelProblem, .permissionDenied)
        }
    }

    func testRestoreAndDeleteSendOnlyTheArchiveName() async throws {
        let service = try live()
        let file = try XCTUnwrap(BackupFile(path: "/crafty/backups/x/\(Self.configID)/2026-10-14_20-49-04.zip"))
        StubPanel.respond(200, #"{"status":"ok"}"#)
        try await service.restoreBackup(file, configID: Self.configID, inPlace: false, serverID: Self.serverID)
        try await service.deleteBackup(file, configID: Self.configID, serverID: Self.serverID)
        XCTAssertEqual(StubPanel.requests.map(\.line), [
            "POST /api/v2/servers/\(Self.serverID)/backups/backup/\(Self.configID)",
            "DELETE /api/v2/servers/\(Self.serverID)/backups/backup/\(Self.configID)/files",
        ])
        let restore = try XCTUnwrap(StubPanel.requests[0].json)
        XCTAssertEqual(Set(restore.keys), ["filename", "inPlace"])
        XCTAssertEqual(restore["filename"] as? String, "2026-10-14_20-49-04.zip")
        XCTAssertEqual(restore["inPlace"] as? Bool, false)
        XCTAssertEqual(StubPanel.requests[1].json?.keys.sorted(), ["filename"])
    }

    func testBackUpNowNamesTheDefaultConfig() async throws {
        StubPanel.respond(200, Self.configs)
        StubPanel.respond(200, #"{"status":"ok"}"#)
        try await live().send(.backup, serverID: Self.serverID)
        XCTAssertEqual(StubPanel.requests.map(\.line), [
            "GET /api/v2/servers/\(Self.serverID)/backups",
            "POST /api/v2/servers/\(Self.serverID)/action/backup_server/\(Self.configID)",
        ], "4.7.0 fails backups that do not name a config")
    }

    // MARK: Schedules and mock

    func testBackupScheduleNamesItsConfig() throws {
        var s = Schedule(id: 0, name: "Nightly", enabled: true, action: .backup, interval: 1, intervalType: .days,
                         command: nil, parent: nil, oneTime: false, cronString: nil, delay: 0, nextRun: nil)
        s.backupID = Self.configID
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        XCTAssertEqual(body["action_id"] as? String, Self.configID)
        XCTAssertEqual(body["command"] as? String, "backup_server")
        s.action = .restart
        body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        XCTAssertNil(body["action_id"], "the panel only accepts a string here")
    }

    func testMockManagesConfigsAndArchives() async throws {
        let mock = MockCraftyService(latency: .zero)
        let id = MockData.servers[0].id
        let configs = try await mock.backupConfigs(serverID: id)
        let main = try XCTUnwrap(configs.first)
        XCTAssertTrue(main.isDefault)

        do {
            try await mock.deleteBackupConfig(id: main.id, serverID: id)
            XCTFail("the default config cannot be deleted")
        } catch {}

        try await mock.saveBackupConfig(BackupConfig(id: "", name: "Weekly", location: ""), includeLocation: false, serverID: id)
        let created = try await mock.backupConfigs(serverID: id).first { $0.name == "Weekly" }
        let weekly = try XCTUnwrap(created)
        XCTAssertTrue(BackupConfig.isValidID(weekly.id))
        let empty = try await mock.backupFiles(serverID: id, config: weekly)
        XCTAssertEqual(empty?.count, 0)

        try await mock.startBackup(serverID: id, configID: weekly.id)
        let archives = try await mock.backupFiles(serverID: id, config: weekly)
        let archive = try XCTUnwrap(archives?.first)
        try await mock.deleteBackup(archive, configID: weekly.id, serverID: id)
        let afterDelete = try await mock.backupFiles(serverID: id, config: weekly)
        XCTAssertEqual(afterDelete?.count, 0)
        try await mock.deleteBackupConfig(id: weekly.id, serverID: id)
        let remaining = try await mock.backupConfigs(serverID: id)
        XCTAssertEqual(remaining.count, configs.count)
    }

    // 4.11.0 answer of GET /api/v2/servers/{id}/backups, plus a second config.
    private static let configs = """
    {"9d8e7f6a-5b4c-4d3e-9f2a-1b0c9d8e7f6a":{"backup_id":"9d8e7f6a-5b4c-4d3e-9f2a-1b0c9d8e7f6a","backup_name":"Nightly",\
    "backup_location":"/crafty/backups/\(serverID)","excluded_dirs":"logs,cache","max_backups":7,"server_id":"\(serverID)",\
    "compress":true,"shutdown":false,"before":"save-off","after":"save-on","default":false,"enabled":true,"backup_type":"zip_vault"},\
    "\(configID)":{"backup_id":"\(configID)","backup_name":"Default Backup","backup_location":"/crafty/backups/\(serverID)",\
    "excluded_dirs":"","max_backups":0,"server_id":"\(serverID)","compress":false,"shutdown":false,"before":"","after":"",\
    "default":true,"enabled":true,"backup_type":"zip_vault"}}
    """
}

/// Answers requests with queued responses (the last one repeats) and records what was sent.
final class StubPanel: URLProtocol {
    struct Recorded {
        let line: String
        let json: [String: Any]?
        var headers: [String: String] = [:]
        var body: Data?

        /// HTTP header names are case-insensitive; URLSession writes some in canonical form ("Location").
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    nonisolated(unsafe) static var requests: [Recorded] = []
    nonisolated(unsafe) private static var responses: [(Int, String)] = []
    private static let lock = NSLock()

    static func respond(_ status: Int, _ body: String) { lock.withLock { responses.append((status, body)) } }
    static func reset() { lock.withLock { requests = []; responses = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let (status, text) = Self.lock.withLock {
            Self.requests.append(Recorded(line: "\(request.httpMethod ?? "?") \(request.url?.path ?? "")", json: json,
                                          headers: request.allHTTPHeaderFields ?? [:], body: body))
            return Self.responses.count > 1 ? Self.responses.removeFirst() : Self.responses.first ?? (500, "")
        }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                                    headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
