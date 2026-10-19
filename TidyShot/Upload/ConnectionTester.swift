import Foundation

nonisolated struct ConnectionTestResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        /// PUT succeeded and an unauthenticated GET on the public URL returned the probe body.
        case readable
        /// PUT succeeded but the public URL did not serve it (bucket policy or URL template problem).
        case notPublic(status: Int)
        case uploadFailed(String)
    }

    let probeKey: String
    let publicURL: URL?
    let outcome: Outcome
    /// Set when the probe object could not be deleted afterwards, so it is not left behind silently.
    var warning: String? = nil

    var summary: String {
        switch outcome {
        case .readable:
            "Upload and public read both work. \(publicURL?.absoluteString ?? "")"
        case .notPublic(let status):
            "Upload worked, but the public URL returned HTTP \(status). Check the bucket policy, CDN, or the public URL template."
        case .uploadFailed(let message):
            "Upload failed: \(message)"
        }
    }
}

/// PUTs a small text object, GETs its public URL without credentials, then deletes the probe.
nonisolated enum ConnectionTester {
    static let probeBody = Data("TidyShot connection test\n".utf8)

    static func run(destination: S3Destination,
                    session: URLSession = .shared,
                    randomString: @Sendable (Int) -> String = FileNamer.randomString) async -> ConnectionTestResult {
        let key = ObjectKeyNamer.join(prefix: destination.config.keyPrefix, name: "tidyshot-probe-\(randomString(8)).txt")
        do {
            try await destination.upload(probeBody, key: key, contentType: "text/plain") { _ in }
        } catch {
            return ConnectionTestResult(probeKey: key, publicURL: nil, outcome: .uploadFailed(error.localizedDescription))
        }

        let publicURL: URL
        do {
            publicURL = try destination.publicURL(for: key)
        } catch {
            let warning = await deleteProbe(key, destination: destination)
            return ConnectionTestResult(probeKey: key, publicURL: nil, outcome: .uploadFailed(error.localizedDescription),
                                        warning: warning)
        }

        var request = URLRequest(url: publicURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let outcome: ConnectionTestResult.Outcome
        do {
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            outcome = (status == 200 && body == probeBody) ? .readable : .notPublic(status: status)
        } catch {
            outcome = .notPublic(status: 0)
        }
        let warning = await deleteProbe(key, destination: destination)
        return ConnectionTestResult(probeKey: key, publicURL: publicURL, outcome: outcome, warning: warning)
    }

    /// Deletes the probe object. Returns a warning instead of throwing, so a leaked probe is
    /// reported without hiding the outcome of the test itself.
    private static func deleteProbe(_ key: String, destination: S3Destination) async -> String? {
        do {
            try await destination.delete(key: key)
            return nil
        } catch {
            NSLog("Probe delete failed: \(error.localizedDescription)")
            return "Probe object \(key) could not be deleted; remove it by hand."
        }
    }
}
