import CryptoKit
import XCTest
@testable import Kurafuto

/// File routes as the Crafty 4.7.0 and 4.11.0 source defines them (`routes/api/servers/server/files.py`).
/// Panel answers are captured from local test panels; requests go to `StubPanel`, never to the network.
final class FileTests: XCTestCase {
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

    private func listing(_ json: String) throws -> [FileEntry] {
        let envelope = try JSONDecoder().decode(APIClient.Envelope<FolderListing>.self, from: Data(json.utf8))
        return try XCTUnwrap(envelope.data).entries
    }

    // MARK: Listing

    func testFolderListingDecodesDirectoriesFirst() throws {
        let entries = try listing(Self.logsFolder)
        XCTAssertEqual(entries.map(\.name), ["archive", "2026-10-14-1.log.gz", "latest.log"])
        XCTAssertEqual(entries[0].path, "logs/archive")
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].size, "1.6KB")
        XCTAssertEqual(entries[2].modified, "2026/10/15 10:13")
        XCTAssertFalse(entries[1].isEditableText, "the panel says it cannot open gzip files")
        XCTAssertTrue(entries[2].isEditableText)
    }

    func testNamesAreTakenAsTheyAre() throws {
        // 4.11.0 sends names unescaped. 4.7.0 cannot list a folder containing such names at all (500).
        let entries = try listing("""
        {"status":"ok","data":{"root_path":{"local_path":"","path":"/crafty/servers/x","top":true,"modified":1.0},
        "Tom & Jerry":{"path":"Tom & Jerry","dir":true,"excluded":false,"modified":"2026/10/15 10:14"},
        "a&amp;b.txt":{"path":"a&amp;b.txt","dir":false,"can_open":true,"size":"1.0B"}}}
        """)
        XCTAssertEqual(entries.map(\.path), ["Tom & Jerry", "a&amp;b.txt"])
    }

    func testEntriesOutsideTheListedFolderAreDropped() throws {
        let entries = try listing("""
        {"status":"ok","data":{"root_path":{"local_path":"plugins","path":"/crafty/servers/x/plugins","top":false,"modified":1.0},
        "ok.jar":{"path":"plugins/ok.jar","dir":false,"size":"2.0KB"},
        "..":{"path":"..","dir":true},
        "passwd":{"path":"/etc/passwd","dir":false},
        "elsewhere":{"path":"world/elsewhere","dir":false},
        "a/b":{"path":"plugins/a/b","dir":false}}}
        """)
        XCTAssertEqual(entries.map(\.path), ["plugins/ok.jar"])
    }

    func testLargeOrBinaryFilesAreNotOpened() {
        let big = FileEntry(name: "latest.log", path: "logs/latest.log", isDirectory: false, size: "2.0MB", canOpen: true)
        let small = FileEntry(name: "ops.json", path: "ops.json", isDirectory: false, size: "210.0B", canOpen: true)
        let jar = FileEntry(name: "paper.jar", path: "paper.jar", isDirectory: false, size: "48.8MB", canOpen: false)
        XCTAssertEqual(big.approximateBytes, 2_097_152)
        XCTAssertEqual(small.approximateBytes, 210)
        XCTAssertFalse(big.isEditableText)
        XCTAssertTrue(small.isEditableText)
        XCTAssertFalse(jar.isEditableText)
    }

    func testFolderNamesAreSingleNames() {
        for valid in ["mods", "world backup", "Tom & Jerry", ".config"] { XCTAssertTrue(ServerPath.isValidName(valid), valid) }
        for invalid in ["", ".", "..", "a/b", "../x", "a\\b", "line\nbreak", String(repeating: "x", count: 256)] {
            XCTAssertFalse(ServerPath.isValidName(invalid), invalid)
        }
    }

    // MARK: Requests

    func testListReadWriteCreateAndDeleteRequests() async throws {
        let service = try live()
        StubPanel.respond(200, Self.logsFolder)
        _ = try await service.listFiles(serverID: Self.serverID, path: "logs")
        StubPanel.reset()
        StubPanel.respond(200, Self.readProperties)
        let file = try await service.readFile(serverID: Self.serverID, path: "server.properties")
        XCTAssertEqual(file.modifiedEpoch, 1792052098.9447, accuracy: 0.001)
        XCTAssertTrue(file.content.hasPrefix("#Minecraft server properties"))
        StubPanel.reset()
        StubPanel.respond(200, #"{"status":"ok","data":{"attributes":{"mime":"text/plain","modified":"2026/10/15 10:40","size":"1.4KB","modified_epoch":1792053600.5}}}"#)
        let saved = try await service.writeFile(serverID: Self.serverID, path: "server.properties", content: "motd=Hi\n",
                                                modifiedEpoch: file.modifiedEpoch, overwrite: false)
        XCTAssertEqual(saved, 1792053600.5, accuracy: 0.001)
        StubPanel.respond(200, #"{"status":"ok"}"#)
        try await service.createFolder(serverID: Self.serverID, parent: "plugins", name: "Kurafuto")
        try await service.deleteFile(serverID: Self.serverID, path: "plugins/Kurafuto")

        XCTAssertEqual(StubPanel.requests.map(\.line), [
            "PATCH /api/v2/servers/\(Self.serverID)/files",
            "PUT /api/v2/servers/\(Self.serverID)/files/create",
            "DELETE /api/v2/servers/\(Self.serverID)/files",
        ])
        let write = try XCTUnwrap(StubPanel.requests[0].json)
        XCTAssertEqual(Set(write.keys), ["path", "contents", "modified_epoch", "overwrite"])
        XCTAssertEqual(write["modified_epoch"] as? Double ?? 0, 1792052098.9447, accuracy: 0.001)
        XCTAssertEqual(write["overwrite"] as? Bool, false)
        let create = try XCTUnwrap(StubPanel.requests[1].json)
        XCTAssertEqual(create["parent"] as? String, "plugins")
        XCTAssertEqual(create["name"] as? String, "Kurafuto")
        XCTAssertEqual(create["directory"] as? Bool, true)
        let delete = try XCTUnwrap(StubPanel.requests[2].json?["file_system_objects"] as? [[String: String]])
        XCTAssertEqual(delete, [["filename": "plugins/Kurafuto"]])
    }

    func testChangedFileIsReportedInsteadOfOverwritten() async throws {
        StubPanel.respond(409, "")
        do {
            _ = try await live().writeFile(serverID: Self.serverID, path: "ops.json", content: "[]", modifiedEpoch: 1, overwrite: false)
            XCTFail("expected a conflict")
        } catch CraftyError.fileChanged {}
    }

    func testInvalidFolderNameNeverReachesThePanel() async throws {
        do {
            try await live().createFolder(serverID: Self.serverID, parent: "", name: "../escape")
            XCTFail("expected an error")
        } catch CraftyError.invalidName {}
        XCTAssertTrue(StubPanel.requests.isEmpty)
    }

    // MARK: server.properties

    func testPropertiesKeepCommentsAndOrder() throws {
        let text = "#Minecraft server properties\n#Thu Oct 15 08:14:58 CEST 2026\nallow-flight=false\nmotd=A Minecraft Server\n\nlevel-seed=\n"
        var props = ServerProperties(text)
        XCTAssertEqual(props.text, text, "an untouched file is written back unchanged")
        XCTAssertEqual(props.entries.map(\.key), ["allow-flight", "motd", "level-seed"])
        props["allow-flight"] = "true"
        props["motd"] = "Hello\nwhite-list=false"
        props["not-there"] = "x"
        XCTAssertEqual(props.text, "#Minecraft server properties\n#Thu Oct 15 08:14:58 CEST 2026\nallow-flight=true\nmotd=Hello white-list=false\n\nlevel-seed=\n")
    }

    // MARK: Mock

    func testMockDetectsConcurrentEditsAndManagesFolders() async throws {
        let mock = MockCraftyService(latency: .zero)
        let id = MockData.servers[0].id
        let first = try await mock.readFile(serverID: id, path: "server.properties")
        _ = try await mock.writeFile(serverID: id, path: "server.properties", content: "a=1\n", modifiedEpoch: first.modifiedEpoch, overwrite: false)
        do {
            _ = try await mock.writeFile(serverID: id, path: "server.properties", content: "a=2\n", modifiedEpoch: first.modifiedEpoch, overwrite: false)
            XCTFail("a stale save must be refused")
        } catch CraftyError.fileChanged {}
        _ = try await mock.writeFile(serverID: id, path: "server.properties", content: "a=2\n", modifiedEpoch: first.modifiedEpoch, overwrite: true)
        let content = try await mock.readFile(serverID: id, path: "server.properties").content
        XCTAssertEqual(content, "a=2\n")

        try await mock.createFolder(serverID: id, parent: "plugins", name: "Kurafuto")
        var names = try await mock.listFiles(serverID: id, path: "plugins").map(\.name)
        XCTAssertTrue(names.contains("Kurafuto"))
        try await mock.deleteFile(serverID: id, path: "plugins/Kurafuto")
        names = try await mock.listFiles(serverID: id, path: "plugins").map(\.name)
        XCTAssertFalse(names.contains("Kurafuto"))
    }

    // 4.11.0 answer of POST /api/v2/servers/{id}/files {"path":"logs"}, plus a folder.
    private static let logsFolder = """
    {"status":"ok","data":{"root_path":{"local_path":"logs","path":"/crafty/servers/x/logs","top":false,"modified":1792044897.0331337},
    "latest.log":{"path":"logs/latest.log","dir":false,"excluded":false,"can_open":true,"permissions":{"can_read":true,"can_write":true,"can_execute":false},"mime":"text/x-log","modified":"2026/10/15 10:13","size":" 12.4KB"},
    "2026-10-14-1.log.gz":{"path":"logs/2026-10-14-1.log.gz","dir":false,"excluded":false,"can_open":false,"permissions":{"can_read":true,"can_write":true,"can_execute":false},"mime":"text/x-log","modified":"2026/10/15 10:13","size":"1.6KB"},
    "archive":{"path":"logs/archive","dir":true,"excluded":false,"permissions":{"can_read":true,"can_write":true,"can_execute":true},"modified":"2026/10/14 20:17"}}}
    """

    private static let readProperties = """
    {"status":"ok","data":{"content":"#Minecraft server properties\\nallow-flight=false\\n","attributes":{"mime":"text/plain","modified":"2026/10/15 10:14","size":"1.4KB","modified_epoch":1792052098.9447}}}
    """
}

/// Uploads follow the web panel's `upload.js`: an announcement, then chunks with index and SHA-256.
final class FileUploadTests: XCTestCase {
    private static let serverID = "7ffe0bd7-70f3-4f2c-8a9a-ad1a1e2dcb84"
    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("Upload-\(UUID().uuidString).jar")
        // Two full chunks and a short one, with a pattern so a misplaced chunk would change the hashes.
        let bytes = (0..<(2 * FileUpload.chunkBytes + 1234)).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        try Data(bytes).write(to: file)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
        StubPanel.reset()
        super.tearDown()
    }

    private func live() throws -> LiveCraftyService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubPanel.self]
        return LiveCraftyService(client: APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.test:8443")),
                                                   token: "t", configuration: configuration))
    }

    func testLimits() {
        XCTAssertNoThrow(try FileUpload.check(name: "EssentialsX-2.21.jar", folder: "plugins", size: 3_000_000))
        XCTAssertThrowsError(try FileUpload.check(name: "../escape.jar", folder: "plugins", size: 10))
        XCTAssertThrowsError(try FileUpload.check(name: "Größe.jar", folder: "plugins", size: 10), "header values are ASCII")
        XCTAssertThrowsError(try FileUpload.check(name: "a.jar", folder: "Welten/Über", size: 10))
        XCTAssertThrowsError(try FileUpload.check(name: "a.jar", folder: "", size: 0), "the panel cannot take empty chunks")
        XCTAssertThrowsError(try FileUpload.check(name: "a.zip", folder: "", size: FileUpload.maxBytes + 1))
        XCTAssertEqual(FileUpload.chunkCount(for: 1), 1)
        XCTAssertEqual(FileUpload.chunkCount(for: FileUpload.chunkBytes), 1)
        XCTAssertEqual(FileUpload.chunkCount(for: FileUpload.chunkBytes + 1), 2)
    }

    func testAnnouncementThenHashedChunks() async throws {
        StubPanel.respond(200, #"{"status":"ok","data":{"file-id":"x"}}"#)
        StubPanel.respond(200, #"{"status":"partial","data":{"message":"Chunk 0 received"}}"#)
        StubPanel.respond(200, #"{"status":"partial","data":{"message":"Chunk 1 received"}}"#)
        StubPanel.respond(200, #"{"status":"completed","data":{"message":"File uploaded successfully"}}"#)
        let progress = ProgressLog()
        try await live().uploadFile(serverID: Self.serverID, folder: "plugins", name: "Essentials.jar", from: file) {
            progress.append($0)
        }

        let requests = StubPanel.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.line == "POST /api/v2/servers/\(Self.serverID)/files/upload" })
        let data = try Data(contentsOf: file)
        let fileIDs = Set(requests.compactMap { $0.header("fileId") })
        XCTAssertEqual(fileIDs.count, 1, "one fileId for the whole upload")
        for request in requests {
            XCTAssertEqual(request.header("fileName"), "Essentials.jar")
            XCTAssertEqual(request.header("location"), "plugins")
            XCTAssertEqual(request.header("fileSize"), "\(data.count)")
            XCTAssertEqual(request.header("totalChunks"), "3")
            XCTAssertEqual(request.header("chunked"), "true")
        }
        XCTAssertNil(requests[0].header("chunkId"), "the announcement carries no chunk")
        XCTAssertTrue(requests[0].body?.isEmpty ?? true)
        for index in 0..<3 {
            let request = requests[index + 1]
            let start = index * FileUpload.chunkBytes
            let expected = data[start..<min(start + FileUpload.chunkBytes, data.count)]
            XCTAssertEqual(request.header("chunkId"), "\(index)")
            XCTAssertEqual(request.body, Data(expected))
            XCTAssertEqual(request.header("chunkHash"), SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined())
        }
        XCTAssertEqual(progress.values.last ?? 0, 1, accuracy: 0.0001)
    }

    func testPanelErrorsAreShown() async throws {
        StubPanel.respond(400, #"{"status":"error","error":"NOT_AUTHORIZED","data":{"message":"Insufficient permissions"}}"#)
        do {
            try await live().uploadFile(serverID: Self.serverID, folder: "", name: "a.jar", from: file) { _ in }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error.panelProblem, .permissionDenied)
        }
        StubPanel.reset()
        StubPanel.respond(200, #"{"status":"ok","data":{"file-id":"x"}}"#)
        StubPanel.respond(507, #"{"status":"error","error":"NO STORAGE SPACE","data":{"message":"Out Of Space!"}}"#)
        do {
            try await live().uploadFile(serverID: Self.serverID, folder: "", name: "a.jar", from: file) { _ in }
            XCTFail("expected an error")
        } catch CraftyError.server(let code, let detail) {
            XCTAssertEqual(code, "NO STORAGE SPACE")
            XCTAssertEqual(detail, "Out Of Space!")
        }
    }

    func testRefusedLocationFromCrafty47IsShown() async throws {
        // 4.7.0 answers a traversal in `location` with 500 and the reason in `error_data`.
        StubPanel.respond(500, #"{"status":"error","error":"TRAVERSAL_DETECTED","error_data":"Attempted traversal detected. Requested upload must go to server directory"}"#)
        do {
            try await live().uploadFile(serverID: Self.serverID, folder: "", name: "a.jar", from: file) { _ in }
            XCTFail("expected an error")
        } catch CraftyError.server(let code, let detail) {
            XCTAssertEqual(code, "TRAVERSAL_DETECTED")
            XCTAssertEqual(detail?.hasPrefix("Attempted traversal"), true)
        }
    }

    func testUnfinishedUploadIsReported() async throws {
        StubPanel.respond(200, #"{"status":"ok","data":{"file-id":"x"}}"#)
        StubPanel.respond(200, #"{"status":"partial","data":{"message":"Chunk received"}}"#)
        do {
            try await live().uploadFile(serverID: Self.serverID, folder: "", name: "a.jar", from: file) { _ in }
            XCTFail("the panel never said completed")
        } catch CraftyError.server(let code, _) {
            XCTAssertEqual(code, "UPLOAD_INCOMPLETE")
        }
    }

    func testRefusedFileNeverReachesThePanel() async throws {
        do {
            try await live().uploadFile(serverID: Self.serverID, folder: "", name: "../a.jar", from: file) { _ in }
            XCTFail("expected an error")
        } catch CraftyError.invalidName {}
        XCTAssertTrue(StubPanel.requests.isEmpty)
    }

    func testMockListsUploadedFile() async throws {
        let mock = MockCraftyService(latency: .zero)
        let id = MockData.servers[0].id
        try await mock.uploadFile(serverID: id, folder: "plugins", name: "Essentials.jar", from: file) { _ in }
        let entry = try await mock.listFiles(serverID: id, path: "plugins").first { $0.name == "Essentials.jar" }
        XCTAssertEqual(entry?.path, "plugins/Essentials.jar")
        XCTAssertEqual(entry?.size, "10.0MB")
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func append(_ value: Double) { lock.withLock { stored.append(value) } }
    var values: [Double] { lock.withLock { stored } }
}
