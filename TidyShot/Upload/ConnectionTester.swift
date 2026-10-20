import Foundation

nonisolated struct ConnectionTestResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        /// PUT succeeded and an unauthenticated GET on the public URL returned the probe body.
        case readable
        /// PUT succeeded but the public URL did not serve it (bucket policy or URL template problem).
        case notPublic(status: Int)
        /// PUT succeeded but the public GET could not be judged (network error, unexpected status, wrong content).
        case publicCheckFailed(String)
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
        case .publicCheckFailed(let message):
            "The probe was uploaded, but checking its public URL failed: \(message). Check the public URL template and your network."
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
                    randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) async -> ConnectionTestResult {
        // The probe goes into the folder real uploads would use right now, so a bucket policy
        // scoped to that folder is tested too.
        let namer = ObjectKeyNamer(template: destination.config.keyTemplate, randomString: randomString)
        let folder = ObjectKeyNamer.folder(of: namer.makeKey(ext: "txt", context: TemplateContext(appName: "TidyShot")))
        let key = (folder.isEmpty ? "" : folder + "/") + "tidyshot-probe-\(randomString(8)).txt"
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
            return ConnectionTestResult(probeKey: key, publicURL: nil, outcome: .publicCheckFailed("Invalid public URL template: \(error)"),
                                        warning: warning)
        }

        var request = URLRequest(url: publicURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let outcome: ConnectionTestResult.Outcome
        do {
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200 where body == probeBody:
                outcome = .readable
            case 200:
                outcome = .publicCheckFailed("the URL returned different content, so it probably points somewhere else")
            case 403, 404:
                outcome = .notPublic(status: status)
            default:
                outcome = .publicCheckFailed("HTTP \(status)")
            }
        } catch {
            outcome = .publicCheckFailed(error.localizedDescription)
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
