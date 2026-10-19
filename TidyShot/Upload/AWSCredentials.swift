import Foundation

/// An access key pair, with an optional session token for temporary credentials.
/// Stored only in the Keychain; see `KeychainCredentialStore`.
nonisolated struct AWSCredentials: Codable, Equatable, Sendable {
    var accessKeyID: String
    var secretAccessKey: String
    var sessionToken: String?

    init(accessKeyID: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}
