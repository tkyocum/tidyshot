import Foundation
import Testing
@testable import TidyShot

/// Anchors `Bundle(for:)` to the test bundle, where the fixtures folder is copied.
final class FixtureLocator {}

/// Runs the AWS SigV4 test suite as shipped in awslabs/aws-c-auth
/// (`tests/aws-signing-test-suite/v4`, Apache-2.0). Each case directory holds `request.txt`,
/// `context.json`, `header-canonical-request.txt` and `header-signature.txt`.
struct SigV4TestSuiteTests {
    nonisolated static let suiteURL = Bundle(for: FixtureLocator.self).resourceURL!
        .appending(path: "Fixtures/aws-sig-v4-test-suite", directoryHint: .isDirectory)

    /// `omit_session_token` cases sign without the token and add it afterwards; TidyShot never
    /// does that, and the signer always signs a token it is given.
    nonisolated static let skipped: Set<String> = ["post-sts-header-after", "post-sts-header-before"]

    nonisolated static let caseNames: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: suiteURL.path(percentEncoded: false))) ?? []
        return names
            .filter { !skipped.contains($0) && !$0.hasPrefix(".") && $0 != "LICENSE" }
            .sorted()
    }()

    struct Context: Decodable {
        struct Credentials: Decodable {
            let accessKeyID: String
            let secretAccessKey: String
            let token: String?

            enum CodingKeys: String, CodingKey {
                case accessKeyID = "access_key_id"
                case secretAccessKey = "secret_access_key"
                case token
            }
        }

        let credentials: Credentials
        let normalize: Bool
        let region: String
        let service: String
        let signBody: Bool
        let timestamp: String

        enum CodingKeys: String, CodingKey {
            case credentials, normalize, region, service, timestamp
            case signBody = "sign_body"
        }
    }

    struct ParsedRequest {
        var method: String
        var path: String
        var query: [(name: String, value: String)]
        var headers: [(name: String, value: String)]
        var body: Data
    }

    /// `METHOD target HTTP/1.1`, header lines (`Name:value`, continuation lines start with
    /// whitespace), a blank line, then the body. The path may contain raw spaces and UTF-8.
    static func parse(_ text: String) -> ParsedRequest {
        let sections = text.components(separatedBy: "\n\n")
        let body = sections.dropFirst().joined(separator: "\n\n")
        var lines = sections[0].components(separatedBy: "\n")
        let requestLine = lines.removeFirst()

        let method = String(requestLine.prefix { $0 != " " })
        let target = String(requestLine.dropFirst(method.count + 1).dropLast(" HTTP/1.1".count))
        let path: String
        var query: [(name: String, value: String)] = []
        if let mark = target.firstIndex(of: "?") {
            path = String(target[..<mark])
            for pair in target[target.index(after: mark)...].split(separator: "&", omittingEmptySubsequences: true) {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
                query.append((name, value))
            }
        } else {
            path = target
        }

        var headers: [(name: String, value: String)] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if line.first?.isWhitespace == true, !headers.isEmpty {
                headers[headers.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                headers.append((String(parts[0]), parts.count > 1 ? String(parts[1]) : ""))
            }
        }
        return ParsedRequest(method: method, path: path, query: query, headers: headers, body: Data(body.utf8))
    }

    @Test func fixturesArePresent() {
        #expect(Self.caseNames.count == 36, "expected 36 runnable cases, found \(Self.caseNames)")
    }

    @Test(arguments: caseNames)
    func suiteCase(name: String) throws {
        let dir = Self.suiteURL.appending(path: name, directoryHint: .isDirectory)
        let context = try JSONDecoder().decode(Context.self, from: Data(contentsOf: dir.appending(path: "context.json")))
        let parsed = Self.parse(try String(contentsOf: dir.appending(path: "request.txt"), encoding: .utf8))
        let expectedCanonical = try String(contentsOf: dir.appending(path: "header-canonical-request.txt"), encoding: .utf8)
        let expectedSignature = try String(contentsOf: dir.appending(path: "header-signature.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let payloadHash = S3Signer.sha256Hex(parsed.body)
        var headers = parsed.headers
        if context.signBody {
            headers.append(("x-amz-content-sha256", payloadHash))
        }
        let credentials = AWSCredentials(accessKeyID: context.credentials.accessKeyID,
                                         secretAccessKey: context.credentials.secretAccessKey,
                                         sessionToken: context.credentials.token)
        let date = try #require(ISO8601DateFormatter().date(from: context.timestamp))

        let signed = S3Signer.sign(
            S3Signer.Request(method: parsed.method, path: parsed.path, query: parsed.query, headers: headers, payloadHash: payloadHash),
            credentials: credentials, region: context.region, service: context.service, date: date,
            normalizePath: context.normalize)

        #expect(signed.canonicalRequest == expectedCanonical, "canonical request for \(name)")
        #expect(signed.signature == expectedSignature, "signature for \(name)")
    }
}
