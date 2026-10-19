import Foundation
import Security

protocol CredentialStore {
    /// Nil when no credentials are stored for `account`. Throws when they exist but cannot be
    /// read (locked keychain, access denied, corrupt data), so callers never mistake a read
    /// failure for "not configured".
    func load(account: String) throws -> AWSCredentials?
    func save(_ credentials: AWSCredentials, account: String) throws
    func delete(account: String) throws
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Generic-password items in the login keychain, one per destination account, holding the
/// credentials as JSON. Works inside the App Sandbox with no extra entitlement.
///
/// Deliberately not using `kSecUseDataProtectionKeychain`: that keychain needs a signed
/// application identifier, which ad-hoc builds do not have (SecItemAdd fails with -34018).
final class KeychainCredentialStore: CredentialStore {
    static let defaultAccount = "default"

    let service: String

    init(service: String = "io.tky.tidyshot.s3") {
        self.service = service
    }

    func load(account: String) throws -> AWSCredentials? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(AWSCredentials.self, from: data)
    }

    func save(_ credentials: AWSCredentials, account: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery(account: account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrLabel] = "TidyShot S3 credentials"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}

/// For tests and previews.
final class InMemoryCredentialStore: CredentialStore {
    private var items: [String: AWSCredentials] = [:]

    func load(account: String) throws -> AWSCredentials? { items[account] }
    func save(_ credentials: AWSCredentials, account: String) throws { items[account] = credentials }
    func delete(account: String) throws { items[account] = nil }
}
