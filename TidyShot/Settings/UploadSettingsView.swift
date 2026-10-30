import SwiftUI

/// Destination fields, credentials (saved to the Keychain), the object key template, and Save and
/// Test Connection.
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
                // A prompt that looks like a value reads as filled in; the example goes underneath.
                // Verbatim, because a string literal is parsed as Markdown and the URL would become
                // a blue, clickable link instead of grey caption text.
                TextField("Endpoint", text: $draft.endpoint, prompt: Text("Required"))
                Text(verbatim: "Example: https://s3.us-west-2.amazonaws.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Region", text: $draft.region, prompt: Text("us-west-2, or auto for R2"))
                TextField("Bucket", text: $draft.bucket)
                Toggle("Use path-style URLs (MinIO)", isOn: $draft.usePathStyle)
                Text("Buckets whose name contains a dot always use path-style URLs; the provider's TLS certificate cannot cover them as a subdomain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Send public-read ACL with each upload", isOn: $draft.sendPublicReadACL)
                TextField("Public URL", text: $draft.publicURLTemplate, prompt: Text("Required"))
                Text(verbatim: "Example: https://snap.tky.io/{key}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("{key} is replaced with the full object key, including any folders from the key template.")
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
                Button("Forget Credentials", role: .destructive) { forgetCredentials() }
                    .disabled(isTesting)
            }
            Section("Object keys") {
                TextField("Key template", text: $draft.keyTemplate, prompt: Text(ObjectKeyNamer.defaultTemplate))
                    .font(.body.monospaced())
                Text("Tokens: \(TemplateExpander.tokenList). Letters, digits, . _ - and / between tokens; / makes folders. The file's extension (.png or .mp4) is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let problem = ObjectKeyNamer.validate(draft.keyTemplate) {
                    Text(problem.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Example: \(exampleKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let warning = ObjectKeyNamer.collisionWarning(for: draft.keyTemplate) {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isTesting)
                    Button("Save and Test Connection") { Task { await test() } }
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

    /// The template expanded for a capture taken right now, with `x` for every random character.
    private var exampleKey: String {
        let context = TemplateContext(counter: 42)
        return ObjectKeyNamer(template: draft.keyTemplate, randomString: { String(repeating: "x", count: $0) })
            .makeKey(ext: "png", context: context)
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

    /// Deletes the keychain item and clears the three fields. The destination fields stay, so
    /// entering a new key pair and saving is all it takes to upload again.
    private func forgetCredentials() {
        do {
            try coordinator.credentialStore.delete(account: KeychainCredentialStore.defaultAccount)
        } catch {
            show(error.localizedDescription, isError: true)
            return
        }
        accessKeyID = ""
        secretAccessKey = ""
        sessionToken = ""
        keychainError = nil
        coordinator.destinationDidChange()
        show("Credentials removed from the keychain. Uploads stay off until new ones are saved.", isError: false)
    }

    /// Saves the form, then runs the connection test against what was saved.
    private func test() async {
        guard save() else { return }
        guard let target = coordinator.makeDestination() else {
            show("Saved, but the credentials could not be read back from the keychain. Check the keychain prompt or re-enter them.",
                 isError: true)
            return
        }
        isTesting = true
        defer { isTesting = false }
        let result = await ConnectionTester.run(destination: target.destination, keyTemplate: target.keyTemplate)
        // A leaked probe object is reported on its own line under the outcome.
        let message = [result.summary, result.warning].compactMap { $0 }.joined(separator: "\n")
        show(message, isError: result.outcome != .readable || result.warning != nil)
    }

    private func show(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
