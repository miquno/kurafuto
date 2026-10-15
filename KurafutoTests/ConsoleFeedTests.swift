import XCTest
@testable import Kurafuto

/// Live console parsing. Socket messages mirror what Crafty 4.11.0 broadcasts for a Paper 1.21.4 server.
final class ConsoleFeedTests: XCTestCase {
    func testNewLineMessageBecomesPlainText() {
        let message = #"{"event": "vterm_new_line", "data": {"line": "<span class=\"mc-log-time\">[07:41:02]</span> <span class=\"mc-log-info\">[Server thread/INFO]</span>: Done (4.215s)! For help, type &quot;help&quot;<br />"}}"#
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: message),
                       [#"[07:41:02] [Server thread/INFO]: Done (4.215s)! For help, type "help""#])
    }

    func testBatchedMessageSplitsIntoLines() {
        // 4.11 batches up to 20 stdout lines into one message, separated by newlines.
        let message = #"{"event":"vterm_new_line","data":{"line":"[07:41:03 INFO]: a\n[07:41:03 INFO]: b\n<br />"}}"#
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: message), ["[07:41:03 INFO]: a", "[07:41:03 INFO]: b"])
    }

    func testEscapedMarkupFromPlayersStaysText() {
        let message = #"{"event":"vterm_new_line","data":{"line":"[INFO]: &lt;Steve&gt; &lt;b&gt;hi&lt;/b&gt; &amp; bye<br />"}}"#
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: message), ["[INFO]: <Steve> <b>hi</b> & bye"])
    }

    func testIndentationIsKeptAndBlankLinesDropped() {
        XCTAssertEqual(CraftyConsoleFeed.plainLines(fromHTML: "java.lang.Error: x  \n\tat a.b(C.java:1)\n   \n<br />"),
                       ["java.lang.Error: x", "\tat a.b(C.java:1)"])
    }

    func testOtherEventsAndMalformedMessagesAreIgnored() {
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: #"{"event":"update_server_details","data":{"id":"1"}}"#), [])
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: #"{"event":"notification","data":"Not authenticated"}"#), [])
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: #"{"event":"vterm_new_line","data":"oops"}"#), [])
        XCTAssertEqual(CraftyConsoleFeed.lines(fromSocketMessage: "not json"), [])
    }

    func testSocketQuerySubscribesToServerPage() throws {
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.example:8443")), token: "t.o.k")
        let task = try client.webSocket("/ws", query: CraftyConsoleFeed.socketQuery(serverID: "abc-123"))
        defer { task.cancel() }
        let request = try XCTUnwrap(task.originalRequest)
        XCTAssertEqual(request.url?.absoluteString,
                       "wss://panel.example:8443/ws?page=%2Fpanel%2Fserver%5Fdetail&page_query_params=%3Fid%3Dabc%2D123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "token=t.o.k")
        XCTAssertFalse(request.url?.absoluteString.contains("t.o.k") ?? true, "the token never goes into the URL")
    }

    func testPollingDiffFollowsSlidingWindow() {
        XCTAssertEqual(CraftyConsoleFeed.newLines(after: ["a", "b", "c"], in: ["b", "c", "d", "e"]), ["d", "e"])
        XCTAssertEqual(CraftyConsoleFeed.newLines(after: ["a", "b"], in: ["a", "b"]), [])
        XCTAssertEqual(CraftyConsoleFeed.newLines(after: [], in: ["a"]), ["a"])
    }

    func testPollingDiffWhenBufferIsFull() {
        // The old count-based diff showed nothing once the panel's 70-line buffer was full.
        let before = (0..<70).map { "line \($0)" }
        let after = Array(before.dropFirst(3)) + ["new 1", "new 2", "new 3"]
        XCTAssertEqual(CraftyConsoleFeed.newLines(after: before, in: after), ["new 1", "new 2", "new 3"])
    }

    func testPollingDiffWithRepeatedLinesAndRestart() {
        XCTAssertEqual(CraftyConsoleFeed.newLines(after: ["a", "tick", "tick"], in: ["tick", "tick", "tick"]), ["tick"])
        XCTAssertEqual(CraftyConsoleFeed.newLines(after: ["x", "y"], in: ["Starting server"]), ["Starting server"])
    }

    func testRememberIsBounded() {
        let shown = CraftyConsoleFeed.remember((0..<1500).map(String.init), after: ["old"])
        XCTAssertEqual(shown.count, CraftyConsoleFeed.memory)
        XCTAssertEqual(shown.last, "1499")
    }
}
