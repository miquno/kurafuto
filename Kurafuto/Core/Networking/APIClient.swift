import Foundation
import CryptoKit

/// Thin HTTP client for the Crafty API v2.
/// Response format per spec:  { "status": "ok", "data": ... }  or
///                            { "status": "error", "error": "CODE", "error_data": "..." }
final class APIClient: NSObject, @unchecked Sendable {
    let baseURL: URL
    var token: String?
    private let pinnedSHA256: String?
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    /// Set when an unknown self-signed certificate shows up → the UI asks the user.
    private(set) var lastSeenCertificateSHA256: String?

    init(baseURL: URL, token: String? = nil, pinnedSHA256: String? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.pinnedSHA256 = pinnedSHA256
    }

    struct Envelope<T: Decodable>: Decodable {
        let status: String
        let data: T?
        let error: String?
        let errorData: String?
        enum CodingKeys: String, CodingKey { case status, data, error; case errorData = "error_data" }
    }
    /// Accepts any `data` payload (object, string, number) when the caller doesn't need it.
    struct Empty: Decodable {
        init() {}
        init(from decoder: Decoder) throws {}
    }

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    enum Body {
        case none
        case json(Encodable)
        case text(String)
    }

    func request<T: Decodable>(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: Body = .none,
                               as type: T.Type = T.self) async throws -> T {
        guard var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw CraftyError.invalidURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw CraftyError.invalidURL }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method.rawValue
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        switch body {
        case .none: break
        case .json(let value):
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(value))
        case .text(let s):
            req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(s.utf8)
        }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch {
            if let sha = lastSeenCertificateSHA256, pinnedSHA256 == nil {
                throw CraftyError.untrustedCertificate(sha256: sha)
            }
            throw CraftyError.transport(error)
        }

        let http = response as? HTTPURLResponse
        if http?.statusCode == 401 { throw CraftyError.unauthorized }

        let decoder = JSONDecoder()
        let envelope: Envelope<T>
        do { envelope = try decoder.decode(Envelope<T>.self, from: data) }
        catch { throw CraftyError.decoding(error) }

        guard envelope.status == "ok" else {
            if http?.statusCode == 403 { throw CraftyError.forbidden(envelope.errorData ?? path) }
            throw CraftyError.server(code: envelope.error ?? "\(http?.statusCode ?? 0)", detail: envelope.errorData)
        }
        if let d = envelope.data { return d }
        if let e = Empty() as? T { return e }
        throw CraftyError.decoding(URLError(.cannotParseResponse))
    }

    /// For `/metrics/*` (OpenMetrics text, no JSON envelope).
    func rawText(_ path: String) async throws -> String {
        var req = URLRequest(url: baseURL.appending(path: path))
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await session.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Self-signed certificates (Crafty default) – trust on first use with pinning
extension APIClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        // 1. Valid CA certificate (e.g. Let's Encrypt behind a reverse proxy) → continue normally.
        if SecTrustEvaluateWithError(trust, nil) { return (.performDefaultHandling, nil) }

        // 2. Self-signed: only accept if the user has confirmed the fingerprint.
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let der = SecCertificateCopyData(leaf) as Data
        let sha = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
        lastSeenCertificateSHA256 = sha
        if let pinned = pinnedSHA256, pinned == sha {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.cancelAuthenticationChallenge, nil)
    }
}
