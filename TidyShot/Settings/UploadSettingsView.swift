import SwiftUI

/// Destination fields, credentials (saved to the Keychain), key naming, and Test Connection.
struct UploadSettingsView: View {
    private let coordinator = AppCoordinator.shared

    @State private var draft = S3DestinationConfig.empty
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var sessionToken = ""
    /// Set when the stored credentials exist but could not be read; shown under the fields.
    @State private var keychainError: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Destination") {
                TextField("Endpoint", text: $draft.endpoint, prompt: Text("https://s3.us-west-2.amazonaws.com"))
                TextField("Region", text: $draft.region, prompt: Text("us-west-2, or auto for R2"))
                TextField("Bucket", text: $draft.bucket)
                TextField("Key prefix (optional folder)", text: $draft.keyPrefix)
                Toggle("Use path-style URLs (MinIO, buckets with dots)", isOn: $draft.usePathStyle)
                Toggle("Send public-read ACL with each upload", isOn: $draft.sendPublicReadACL)
                TextField("Public URL", text: $draft.publicURLTemplate, prompt: Text("https://snap.tky.io/{key}"))
                Text("{key} is replaced with the object key, including the prefix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Credentials") {
                TextField("Access key ID", text: $accessKeyID)
                SecureField("Secret access key", text: $secretAccessKey)
                SecureField("Session token (optional)", text: $sessionToken)
                if let keychainError {
                    Text(keychainError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text("Stored in your login keychain, never in preferences. A session token is only needed for temporary credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Object keys") {
                Stepper("Random name length: \(draft.keyLength)", value: $draft.keyLength, in: ObjectKeyNamer.lengthRange)
                Text("Example: \(exampleKey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                    Button("Test Connection") { Task { await test() } }
                        .disabled(isTesting)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private var exampleKey: String {
        ObjectKeyNamer(prefix: draft.keyPrefix, length: draft.keyLength, randomString: { String(repeating: "x", count: $0) })
            .makeKey(ext: "png")
    }

    /// Fills the form. No stored item leaves the credential fields empty; a keychain error is
    /// shown under them so an unreadable item is not mistaken for "never set up".
    private func load() {
        draft = coordinator.settings.s3Config ?? .empty
        do {
            keychainError = nil
            if let credentials = try coordinator.credentialStore.load(account: KeychainCredentialStore.defaultAccount) {
                accessKeyID = credentials.accessKeyID
                secretAccessKey = credentials.secretAccessKey
                sessionToken = credentials.sessionToken ?? ""
            }
        } catch {
            keychainError = "Could not read S3 credentials from the keychain: \(error.localizedDescription)"
        }
    }

    /// Returns false (and shows why) when the form cannot be saved.
    @discardableResult
    private func save() -> Bool {
        if let error = draft.validationError {
            show(error.localizedDescription, isError: true)
            return false
        }
        draft = draft.normalized
        let trimmedID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else {
            show("Access key ID and secret access key are required.", isError: true)
            return false
        }
        do {
            try coordinator.credentialStore.save(AWSCredentials(accessKeyID: trimmedID, secretAccessKey: trimmedSecret,
                                                                sessionToken: trimmedToken.isEmpty ? nil : trimmedToken),
                                                 account: KeychainCredentialStore.defaultAccount)
        } catch {
            show(error.localizedDescription, isError: true)
            return false
        }
        keychainError = nil
        coordinator.settings.s3Config = draft
        coordinator.destinationDidChange()
        show("Saved.", isError: false)
        return true
    }

    private func test() async {
        guard save(), let destination = coordinator.makeDestination() else { return }
        isTesting = true
        defer { isTesting = false }
        let result = await ConnectionTester.run(destination: destination)
        // A leaked probe object is reported on its own line under the outcome.
        let message = [result.summary, result.warning].compactMap { $0 }.joined(separator: "\n")
        show(message, isError: result.outcome != .readable || result.warning != nil)
    }

    private func show(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
