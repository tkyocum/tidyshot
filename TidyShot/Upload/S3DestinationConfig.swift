import Foundation

/// Everything about an S3-compatible destination except the credentials. Persisted as JSON in
/// UserDefaults by `AppSettings.s3Config`; credentials live in the Keychain.
nonisolated struct S3DestinationConfig: Codable, Equatable, Sendable {
    /// Service endpoint without the bucket, for example `https://s3.us-west-2.amazonaws.com`,
    /// `https://<account>.r2.cloudflarestorage.com`, `https://s3.us-west-004.backblazeb2.com`,
    /// or `http://localhost:9000`.
    var endpoint: String
    /// `us-west-2`, `auto` (R2), `us-west-004` (B2). MinIO accepts any value.
    var region: String
    var bucket: String
    /// `https://host/bucket/key` instead of `https://bucket.host/key`. Needed for MinIO and for
    /// bucket names containing dots over HTTPS.
    var usePathStyle: Bool
    /// Adds `x-amz-acl: public-read` to every PUT. Off by default; most buckets use a policy or CDN.
    var sendPublicReadACL: Bool
    /// Where the object is readable from, with `{key}` standing for the full object key.
    var publicURLTemplate: String
    /// Object key template, see `ObjectKeyNamer`. Replaces the Phase 2 prefix and random length,
    /// which are migrated on decode.
    var keyTemplate: String

    static let keyToken = "{key}"

    static let empty = S3DestinationConfig(endpoint: "", region: "", bucket: "",
                                           usePathStyle: false, sendPublicReadACL: false,
                                           publicURLTemplate: "", keyTemplate: ObjectKeyNamer.defaultTemplate)

    init(endpoint: String, region: String, bucket: String,
         usePathStyle: Bool = false, sendPublicReadACL: Bool = false,
         publicURLTemplate: String, keyTemplate: String = ObjectKeyNamer.defaultTemplate) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.usePathStyle = usePathStyle
        self.sendPublicReadACL = sendPublicReadACL
        self.publicURLTemplate = publicURLTemplate
        self.keyTemplate = keyTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint, region, bucket, usePathStyle, sendPublicReadACL, publicURLTemplate, keyTemplate
    }

    /// Phase 2 stored these instead of `keyTemplate`.
    private enum LegacyCodingKeys: String, CodingKey {
        case keyPrefix, keyLength
    }

    /// A Phase 2 config (prefix and length, no template) decodes to the equivalent template, so
    /// existing uploads keep their folder and name length. Encoding is synthesised and writes
    /// only the current keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        region = try container.decode(String.self, forKey: .region)
        bucket = try container.decode(String.self, forKey: .bucket)
        usePathStyle = try container.decode(Bool.self, forKey: .usePathStyle)
        sendPublicReadACL = try container.decode(Bool.self, forKey: .sendPublicReadACL)
        publicURLTemplate = try container.decode(String.self, forKey: .publicURLTemplate)
        if let template = try container.decodeIfPresent(String.self, forKey: .keyTemplate) {
            // `{app}` was a token until Phase 3.1; a template saved with it loses it here.
            keyTemplate = TemplateMigration.removingAppToken(from: template, fallback: ObjectKeyNamer.defaultTemplate)
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            keyTemplate = ObjectKeyNamer.migratedTemplate(
                prefix: try legacy.decodeIfPresent(String.self, forKey: .keyPrefix) ?? "",
                length: try legacy.decodeIfPresent(Int.self, forKey: .keyLength) ?? TemplateExpander.defaultRandomLength)
        }
    }

    enum ConfigError: LocalizedError, Equatable {
        case invalidEndpoint
        case missingBucket
        case missingRegion
        case invalidPublicURLTemplate
        case invalidKeyTemplate(String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "Endpoint must be an http or https URL such as https://s3.us-west-2.amazonaws.com."
            case .missingBucket: "Bucket name is required."
            case .missingRegion: "Region is required (use \"auto\" for Cloudflare R2)."
            case .invalidPublicURLTemplate: "Public URL must be an http or https URL containing {key}."
            case .invalidKeyTemplate(let reason): "Key template: \(reason)"
            }
        }
    }

    /// A copy with surrounding whitespace removed from every text field and the key template
    /// folded. Pasted values often carry a trailing space or newline; trimming here means
    /// " my-bucket " is used as "my-bucket" instead of producing a broken host name or signature.
    var normalized: S3DestinationConfig {
        var copy = self
        copy.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.publicURLTemplate = publicURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.keyTemplate = ObjectKeyNamer.normalize(keyTemplate)
        return copy
    }

    /// The first problem with this configuration (after trimming), or nil when it can be used.
    var validationError: ConfigError? {
        let config = normalized
        guard let endpointURL = config.endpointURL, ["http", "https"].contains(endpointURL.scheme ?? ""),
              endpointURL.host() != nil else {
            return .invalidEndpoint
        }
        if config.bucket.isEmpty { return .missingBucket }
        if config.region.isEmpty { return .missingRegion }
        if config.expandTemplate(encodedKey: "probe") == nil { return .invalidPublicURLTemplate }
        if let problem = ObjectKeyNamer.validate(config.keyTemplate) { return .invalidKeyTemplate(problem.localizedDescription) }
        return nil
    }

    var isComplete: Bool { validationError == nil }

    var endpointURL: URL? {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Path-style is used when the user asked for it or when the bucket name contains a dot.
    /// AWS wildcard certificates (`*.s3.<region>.amazonaws.com`) cover a single label, so a
    /// virtual-host URL such as `snap.tky.io.s3.amazonaws.com` fails TLS; AWS requires path-style
    /// for such buckets over HTTPS, and the other providers accept it.
    var effectivePathStyle: Bool {
        usePathStyle || normalized.bucket.contains(".")
    }

    /// The decoded request path for `key`: `/key` (virtual-host) or `/bucket/key` (path-style).
    func objectPath(for key: String) -> String {
        effectivePathStyle ? "/\(normalized.bucket)/\(key)" : "/\(key)"
    }

    /// The URL the signed request is sent to.
    func objectURL(for key: String) throws -> URL {
        guard let endpointURL, var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else {
            throw ConfigError.invalidEndpoint
        }
        if !effectivePathStyle {
            components.host = "\(normalized.bucket).\(host)"
        }
        components.percentEncodedPath = S3Signer.uriEncode(objectPath(for: key), keepSlash: true)
        components.query = nil
        guard let url = components.url else { throw ConfigError.invalidEndpoint }
        return url
    }

    /// The value for the `host` header that URLSession will send for `objectURL(for:)`:
    /// the host plus `:port` when the endpoint names a port.
    func hostHeader(for url: URL) -> String {
        guard let host = url.host() else { return "" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// The public URL for `key`, from `publicURLTemplate`.
    func publicURL(for key: String) throws -> URL {
        guard let url = expandTemplate(encodedKey: S3Signer.uriEncode(key, keepSlash: true)) else {
            throw ConfigError.invalidPublicURLTemplate
        }
        return url
    }

    /// The one template check, shared by `validationError` and `publicURL(for:)`: the trimmed
    /// template with `{key}` replaced, or nil when it has no `{key}` or is not an http(s) URL.
    private func expandTemplate(encodedKey: String) -> URL? {
        let template = normalized.publicURLTemplate
        guard template.contains(Self.keyToken),
              let url = URL(string: template.replacingOccurrences(of: Self.keyToken, with: encodedKey)),
              ["http", "https"].contains(url.scheme ?? "") else {
            return nil
        }
        return url
    }
}
