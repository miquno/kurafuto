import Foundation

/// A Crafty installation the user added (several are possible: homelab, a friend's server, ...).
/// The token is NOT stored here but in the Keychain (see KeychainStore).
struct Instance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var baseURL: URL                       // e.g. https://192.168.1.20:8443
    var username: String
    var authMethod: AuthMethod
    /// SHA-256 of the certificate for self-signed installations (trust on first use).
    var pinnedCertificateSHA256: String?
    var accentColorHex: String = "#3FB950"

    enum AuthMethod: String, Codable { case password, apiToken }
}
