import XCTest
@testable import Kurafuto

/// Error states: how panel answers and transport failures map to what the user sees.
/// Status codes and error names come from Crafty 4.7.0/4.11.0 (`base_handler.access_denied`,
/// `require_superuser`, `auth/login`).
final class ErrorStateTests: XCTestCase {
    private func failure(_ status: Int, _ error: String?, _ detail: String? = nil) -> CraftyError {
        APIClient.failure(status: status, error: error, detail: detail, path: "/api/v2/roles")
    }

    func testRejectedTokenMeansSessionExpired() {
        XCTAssertEqual(failure(403, "ACCESS_DENIED").panelProblem, .sessionExpired)
        XCTAssertEqual(failure(401, nil).panelProblem, .sessionExpired)
    }

    func testMissingRightsMeanPermissionDenied() {
        guard case .forbidden(let detail) = failure(400, "NOT_AUTHORIZED", "Insufficient permissions") else {
            return XCTFail("400 NOT_AUTHORIZED must be a permission error")
        }
        XCTAssertEqual(detail, "Insufficient permissions")
        XCTAssertEqual(failure(403, nil).panelProblem, .permissionDenied)
    }

    func testWrongLoginIsNotAnExpiredSession() {
        guard case .server(let code, _) = failure(401, "INCORRECT_CREDENTIALS", "Incorrect username or password") else {
            return XCTFail("wrong credentials must keep the panel's message")
        }
        XCTAssertEqual(code, "INCORRECT_CREDENTIALS")
        XCTAssertEqual(failure(403, "ACCOUNT_DISABLED").panelProblem, .other)
    }

    func testOtherPanelErrorsKeepTheirCode() {
        guard case .server(let code, let detail) = failure(500, nil) else { return XCTFail() }
        XCTAssertEqual(code, "500")
        XCTAssertNil(detail)
    }

    func testUnreachablePanelIsOffline() {
        for code in [URLError.Code.cannotConnectToHost, .timedOut, .notConnectedToInternet, .cannotFindHost, .networkConnectionLost] {
            XCTAssertEqual(CraftyError.transport(URLError(code)).panelProblem, .offline, "\(code)")
        }
        XCTAssertEqual(URLError(.timedOut).panelProblem, .offline)
        XCTAssertEqual(CraftyError.transport(URLError(.badServerResponse)).panelProblem, .other)
        XCTAssertEqual(CraftyError.decoding(URLError(.cannotParseResponse)).panelProblem, .other)
    }

    func testOnlyTheActivePanelClientCanExpireTheSession() throws {
        let client = APIClient(baseURL: try XCTUnwrap(URL(string: "https://panel.example:8443")), token: "t")
        let app = AppState(instanceStore: InstanceStore(preview: [MockData.instance]), service: LiveCraftyService(client: client),
                           activeInstance: MockData.instance, isMock: false, lock: AppLock(defaults: nil))
        XCTAssertTrue(app.isActiveClient(client))
        let onboardingClient = APIClient(baseURL: client.baseURL, token: "other")
        XCTAssertFalse(app.isActiveClient(onboardingClient), "a check during sign-in must not open the sign-in sheet")
        XCTAssertFalse(AppState.preview.isActiveClient(client), "demo mode has no live client")
    }
}
