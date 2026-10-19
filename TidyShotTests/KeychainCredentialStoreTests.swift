import Foundation
import Testing
@testable import TidyShot

struct KeychainCredentialStoreTests {
    @Test func inMemoryStoreRoundTrips() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.load(account: "a") == nil)
        try store.save(AWSCredentials(accessKeyID: "id", secretAccessKey: "secret"), account: "a")
        #expect(try store.load(account: "a") == AWSCredentials(accessKeyID: "id", secretAccessKey: "secret"))
        try store.delete(account: "a")
        #expect(try store.load(account: "a") == nil)
    }

    /// Uses the real login keychain under a test-only service name and removes the item after.
    @Test func keychainStoreRoundTrips() throws {
        let store = KeychainCredentialStore(service: "io.tky.tidyshot.tests")
        let account = "roundtrip-\(UUID().uuidString)"
        defer { try? store.delete(account: account) }

        #expect(try store.load(account: account) == nil)
        let first = AWSCredentials(accessKeyID: "AKID1", secretAccessKey: "s1", sessionToken: "t")
        try store.save(first, account: account)
        #expect(try store.load(account: account) == first)

        let second = AWSCredentials(accessKeyID: "AKID2", secretAccessKey: "s2")
        try store.save(second, account: account)
        #expect(try store.load(account: account) == second)

        try store.delete(account: account)
        #expect(try store.load(account: account) == nil)
        try store.delete(account: account)
    }

    @Test func descriptionRedactsSecrets() {
        let credentials = AWSCredentials(accessKeyID: "AKIDEXAMPLE", secretAccessKey: "super-secret-value", sessionToken: "session-token-value")
        let text = "\(credentials)"
        #expect(text.contains("AKIDEXAMPLE"))
        #expect(!text.contains("super-secret-value"))
        #expect(!text.contains("session-token-value"))
    }
}
