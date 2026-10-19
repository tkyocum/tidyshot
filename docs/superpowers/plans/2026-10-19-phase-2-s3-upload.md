# TidyShot Phase 2: S3 Upload and Clipboard URL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a capture, TidyShot uploads the saved PNG to the user's S3-compatible bucket under a short random key, puts the public URL on the clipboard, shows a small overlay with progress and the URL, and keeps a retryable capture history.

**Architecture:** A pure `S3Signer` (SigV4) signs single `PUT`, `HEAD` and `DELETE` Object requests that `S3Destination` sends over `URLSession`. An `UploadQueue` actor runs one upload at a time with HEAD-before-PUT key reservation and retry with backoff, reporting `UploadEvent`s to the main actor. `AppCoordinator.save` writes the local file first, records a `CaptureRecord` in the JSON-backed `HistoryStore`, shows the `QuickAccessPanel`, then enqueues the upload; on success the URL replaces the clipboard contents. Destination settings live in `UserDefaults` as JSON; credentials live in the login keychain via `KeychainCredentialStore`.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation, CryptoKit (SHA-256, HMAC), URLSession async upload with a task delegate for progress, Security framework (`SecItemAdd` and friends), SwiftUI `MenuBarExtra` and `Settings`, AppKit `NSPanel`, Swift Testing, XcodeGen 2.46, the AWS SigV4 test suite from `awslabs/aws-c-auth` as test fixtures.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, sections 2.2, 3, 5, 6 (Phase 2) and 7 (decisions 2, 3, 4).

Builds on Phase 0 and 1 (`docs/superpowers/plans/2026-10-19-phase-0-1-capture-and-save.md`, branch `phase-1-capture`, PR tkyocum/tidyshot#1). Start this plan on a branch cut from `phase-1-capture` (or from `main` once that PR has merged):

```bash
git checkout -b phase-2-upload phase-1-capture
```

## Global Constraints

- Minimum macOS: `26.0`. Xcode 27.1, macOS 27.0 SDK. Everything from the Phase 0 and 1 constraints still applies.
- App Sandbox on. This phase adds the entitlement `com.apple.security.network.client: true` to `project.yml`. The save folder is still reached through its security-scoped bookmark; upload retries read the file through `SaveLocation.read(contentsOf:)`.
- Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Pure value types that the upload actor or URLSession threads touch are declared `nonisolated` and `Sendable`. Delegate callbacks from URLSession are `nonisolated`.
- S3 client is hand-rolled: SigV4 over `URLSession`, request types `PUT Object`, `HEAD Object`, `DELETE Object` only. No AWS SDK, no multipart.
- Credentials (access key ID, secret access key, optional session token) are stored only in the login keychain as a generic-password item with service `io.tky.tidyshot.s3` and account `default`. Never in `UserDefaults`, never logged. Do not use `kSecUseDataProtectionKeychain` (it needs a signed application identifier that ad-hoc builds lack).
- Object keys: random characters from `[A-Za-z0-9]` via `FileNamer.randomString(length:)`, default length `6`, configurable `4...32`, optional prefix folder, `.png` extension. `HEAD` before `PUT`; on HTTP 200 generate a new key, up to 5 times.
- No `x-amz-acl` header by default. The per-destination toggle "Send public-read ACL" adds `x-amz-acl: public-read`.
- Public URL comes from a template containing `{key}`, for example `https://snap.tky.io/{key}`; it is never derived from the endpoint.
- After-capture action default is "Upload and copy URL". In that mode only the URL goes on the clipboard, on upload success. The "Also copy image" setting (off by default) copies the image at capture time and the URL replaces it. In "Save and copy image" mode Phase 1 behaviour is unchanged.
- The local file is written before any upload starts. Upload failures stay in history as `failed` with a retry action and a notification. The app never drops a capture.
- Retry policy: 3 attempts, backoff 1 s then 2 s, only for HTTP 5xx, 429, and transport errors. 4xx responses fail immediately.
- History: `~/Library/Application Support/TidyShot/history.json` inside the sandbox container, newest first, pruned to `historyRetentionDays` (default 30) on load and on add. Records found in `uploading` state on launch become `failed("Upload was interrupted.")`.
- Quick Access overlay: one `NSPanel`, `.nonactivatingPanel`, `.floating` level, in the configurable corner (default bottom right) of the screen under the mouse, 16 pt margin, auto-close 5 s after the upload settles (0 disables), never while the mouse is over it.
- Menu bar icon switches from `camera.viewfinder` to `arrow.up.circle` while any upload is in flight.
- Tests use Swift Testing, run with `xcodebuild test`. Test fixtures are a folder reference copied into the test bundle.
- Phase 1 behaviour and tests stay green throughout: the baseline is `Test run with 30 tests in 5 suites passed`.
- No GPL-licensed code may be read or copied. The SigV4 fixtures are Apache-2.0 from `awslabs/aws-c-auth`; keep their `LICENSE` next to them.
- Commit after every task with a conventional commit message. Never include a Claude Code session URL in a commit or PR. Do not push or open a PR until the final task says so.

## Build and test commands used throughout

```bash
# regenerate the project after any project.yml change or after adding files
xcodegen generate
```

```bash
# build (exit code 0 on success)
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet
```

```bash
# run all unit tests; the summary line is the last "Test run with N tests in M suites" line
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```

```bash
# launch the built app
open .build/Build/Products/Debug/TidyShot.app
```

XcodeGen only sees files that exist when it runs. Every task that creates a Swift file runs `xcodegen generate` before building; a "cannot find 'X' in scope" error for a type you just wrote means the project was not regenerated.

Code signing note: this Mac has ad-hoc signing (`CODE_SIGN_IDENTITY = -`). Two consequences for this phase, in addition to the Screen Recording re-grant from Phase 1: after each rebuild macOS may ask "TidyShot wants to use your confidential information stored in TidyShot S3 credentials in your keychain" the first time the app reads the saved credentials (click Always Allow), and the unit test that touches the keychain creates and deletes its own item in-process, which never prompts.

## File structure

```
project.yml                                  + network.client entitlement, + Fixtures folder reference
TidyShot/
  App/
    AppCoordinator.swift                     modified: upload flow, history, overlay, retry
    MenuContent.swift                        modified: Recent Captures submenu, retry failed
    TidyShotApp.swift                        modified: icon state while uploading
  Upload/
    AWSCredentials.swift                     access key pair (Keychain only)
    S3Signer.swift                           SigV4 canonical request, string to sign, signature (pure)
    S3DestinationConfig.swift                endpoint, region, bucket, prefix, flags, URL building (pure)
    ObjectKeyNamer.swift                     prefix + random name + extension (pure)
    Destination.swift                        Destination protocol, UploadJob, UploadEvent, UploadError
    RetryPolicy.swift                        exponential backoff (pure)
    UploadProgressDelegate.swift             URLSessionTaskDelegate -> progress closure
    S3Destination.swift                      PUT / HEAD / DELETE Object over URLSession
    UploadQueue.swift                        actor: one upload at a time, HEAD-before-PUT, retry
    ConnectionTester.swift                   PUT probe, unauthenticated GET, DELETE probe
    KeychainCredentialStore.swift            CredentialStore protocol, Keychain and in-memory stores
  History/
    CaptureRecord.swift                      id, timestamp, file URL, pixel size, app, upload state
    HistoryStore.swift                       @Observable JSON store with pruning
  Overlay/
    OverlayGeometry.swift                    OverlayCorner, corner -> frame (pure)
    QuickAccessModel.swift                   @Observable state for the panel
    QuickAccessView.swift                    SwiftUI: thumbnail, progress ring, URL, copy, retry
    QuickAccessPanel.swift                   non-activating floating NSPanel
    QuickAccessController.swift              show / update / auto-close
  Output/
    Pasteboard.swift                         modified: copy(url:)
    Notifier.swift                           modified: notifyUploaded(url:)
    SaveLocation.swift                       modified: read(contentsOf:)
  Settings/
    AppSettings.swift                        modified: after-capture action, overlay, history, s3Config
    GeneralSettingsView.swift                modified: after-capture picker, Also copy image
    UploadSettingsView.swift                 destination form, credentials, Test Connection
    OverlaySettingsView.swift                corner, auto-close, history retention
    SettingsView.swift                       modified: Upload and Overlay tabs
TidyShotTests/
  Fixtures/aws-sig-v4-test-suite/            38 case folders + LICENSE (folder reference)
  S3SignerTests.swift
  SigV4TestSuiteTests.swift
  S3DestinationConfigTests.swift
  ObjectKeyNamerTests.swift
  RetryPolicyTests.swift
  S3DestinationTests.swift                   also defines StubURLProtocol
  UploadQueueTests.swift                     also defines FakeDestination, EventLog, eventually()
  ConnectionTesterTests.swift
  KeychainCredentialStoreTests.swift
  HistoryStoreTests.swift
  AppSettingsTests.swift
  OverlayGeometryTests.swift
docs/testing/phase-2-manual-checklist.md
README.md                                    modified: Upload section
```

---

### Task 1: Network entitlement, credentials type, and the SigV4 signer (TDD)

**Files:**
- Modify: `project.yml` (entitlements block)
- Create: `TidyShot/Upload/AWSCredentials.swift`
- Create: `TidyShot/Upload/S3Signer.swift`
- Create: `TidyShotTests/S3SignerTests.swift`

**Interfaces:**
- Consumes: nothing from Phase 1.
- Produces:
  - `struct AWSCredentials: Codable, Equatable, Sendable { var accessKeyID: String; var secretAccessKey: String; var sessionToken: String? }` with `init(accessKeyID:secretAccessKey:sessionToken:)`.
  - `enum S3Signer` with:
    - `struct Request { var method: String; var path: String; var query: [(name: String, value: String)]; var headers: [(name: String, value: String)]; var payloadHash: String }`, `init(method:path:query:headers:payloadHash:)` (`query` defaults to `[]`). `path`, query names and values are decoded strings.
    - `struct Signed { let canonicalRequest: String; let stringToSign: String; let signature: String; let headers: [(name: String, value: String)] }` where `headers` are `x-amz-date`, optional `x-amz-security-token`, and `authorization`.
    - `static func sign(_ request: Request, credentials: AWSCredentials, region: String, service: String = "s3", date: Date, normalizePath: Bool = false) -> Signed`
    - `static let emptyPayloadHash: String`
    - `static func sha256Hex(_ data: Data) -> String`
    - `static func uriEncode(_ string: String, keepSlash: Bool) -> String`
    - `static func canonicalURI(_ path: String, normalize: Bool) -> String`, `static func removingDotSegments(_ path: String) -> String`
    - `static func canonicalQuery(_ query: [(name: String, value: String)]) -> String`
    - `static func canonicalHeaders(_ headers: [(name: String, value: String)]) -> (canonical: String, signed: String)`
    - `static func amzDateString(_ date: Date) -> String`

Background: SigV4 builds a canonical request (method, encoded path, sorted encoded query, sorted lowercased headers, signed header list, payload SHA-256), hashes it into a string to sign with the date and credential scope, derives a signing key with four chained HMACs, and emits the signature as hex. S3 differs from other AWS services in two ways the signer must honour: the path is percent-encoded once (not twice) and never normalized, and every request carries an `x-amz-content-sha256` header. The worked examples below come from the AWS S3 API Reference page "Signature Calculations for the Authorization Header: Transferring Payload in a Single Chunk" (access key `AKIAIOSFODNN7EXAMPLE`, secret `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`, bucket `examplebucket`, 2013-05-24T00:00:00Z).

- [ ] **Step 1: Add the network client entitlement**

In `project.yml`, inside `targets.TidyShot.entitlements.properties`, add the last line:

```yaml
    entitlements:
      path: TidyShot/TidyShot.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.files.user-selected.read-write: true
        com.apple.security.files.bookmarks.app-scope: true
        com.apple.security.network.client: true
```

- [ ] **Step 2: Write the credentials type**

`TidyShot/Upload/AWSCredentials.swift`:
```swift
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
```

- [ ] **Step 3: Write the failing tests**

`TidyShotTests/S3SignerTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

/// Worked examples from the AWS S3 API Reference, "Signature Calculations for the Authorization
/// Header: Transferring Payload in a Single Chunk" (sig-v4-header-based-auth). Credentials and
/// expected values are copied from that page.
struct S3SignerTests {
    let credentials = AWSCredentials(accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                                     secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    /// 2013-05-24T00:00:00Z
    let date = Date(timeIntervalSince1970: 1_369_353_600)
    let host = "examplebucket.s3.amazonaws.com"

    @Test func amzDateIsUTC() {
        #expect(S3Signer.amzDateString(date) == "20130524T000000Z")
    }

    @Test func getObjectExample() {
        let request = S3Signer.Request(
            method: "GET", path: "/test.txt",
            headers: [("host", host), ("range", "bytes=0-9"), ("x-amz-content-sha256", S3Signer.emptyPayloadHash)],
            payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)

        #expect(signed.canonicalRequest == """
        GET
        /test.txt

        host:examplebucket.s3.amazonaws.com
        range:bytes=0-9
        x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        x-amz-date:20130524T000000Z

        host;range;x-amz-content-sha256;x-amz-date
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """)
        #expect(signed.stringToSign == """
        AWS4-HMAC-SHA256
        20130524T000000Z
        20130524/us-east-1/s3/aws4_request
        7344ae5b7ee6c3e7e6b0fe0640412a37625d1fbfff95c48bbb2dc43964946972
        """)
        #expect(signed.signature == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
        #expect(signed.headers.map(\.name) == ["x-amz-date", "authorization"])
        #expect(signed.headers.last?.value == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    @Test func putObjectExampleEncodesDollarAndSignsBody() {
        let body = Data("Welcome to Amazon S3.".utf8)
        let bodyHash = S3Signer.sha256Hex(body)
        #expect(bodyHash == "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")

        let request = S3Signer.Request(
            method: "PUT", path: "/test$file.text",
            headers: [("date", "Fri, 24 May 2013 00:00:00 GMT"), ("host", host),
                      ("x-amz-content-sha256", bodyHash), ("x-amz-storage-class", "REDUCED_REDUNDANCY")],
            payloadHash: bodyHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)

        #expect(signed.canonicalRequest.hasPrefix("PUT\n/test%24file.text\n\ndate:Fri, 24 May 2013 00:00:00 GMT\n"))
        #expect(signed.stringToSign.hasSuffix("9e0e90d9c76de8fa5b200d8c849cd5b8dc7a3be3951ddb7f6a76b4158342019d"))
        #expect(signed.signature == "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
    }

    @Test func getBucketLifecycleExampleHasEmptyQueryValue() {
        let request = S3Signer.Request(
            method: "GET", path: "/", query: [("lifecycle", "")],
            headers: [("host", host), ("x-amz-content-sha256", S3Signer.emptyPayloadHash)],
            payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)
        #expect(signed.canonicalRequest.contains("\nlifecycle=\n"))
        #expect(signed.signature == "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543")
    }

    @Test func listObjectsExampleSortsQuery() {
        let request = S3Signer.Request(
            method: "GET", path: "/", query: [("prefix", "J"), ("max-keys", "2")],
            headers: [("host", host), ("x-amz-content-sha256", S3Signer.emptyPayloadHash)],
            payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)
        #expect(signed.canonicalRequest.contains("\nmax-keys=2&prefix=J\n"))
        #expect(signed.signature == "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")
    }

    @Test func sessionTokenIsSignedAndReturned() {
        let temporary = AWSCredentials(accessKeyID: "AKID", secretAccessKey: "secret", sessionToken: "TOKEN")
        let request = S3Signer.Request(method: "GET", path: "/", headers: [("host", host)], payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: temporary, region: "us-east-1", date: date)
        #expect(signed.canonicalRequest.contains("x-amz-security-token:TOKEN\n"))
        #expect(signed.canonicalRequest.contains("host;x-amz-date;x-amz-security-token"))
        #expect(signed.headers.map(\.name) == ["x-amz-date", "x-amz-security-token", "authorization"])
    }

    @Test func uriEncodeKeepsUnreservedAndOptionallySlash() {
        #expect(S3Signer.uriEncode("a-b_c.d~e", keepSlash: false) == "a-b_c.d~e")
        #expect(S3Signer.uriEncode("x/y z", keepSlash: true) == "x/y%20z")
        #expect(S3Signer.uriEncode("x/y z", keepSlash: false) == "x%2Fy%20z")
        #expect(S3Signer.uriEncode("ሴ", keepSlash: false) == "%E1%88%B4")
        #expect(S3Signer.uriEncode("$+,:=@", keepSlash: false) == "%24%2B%2C%3A%3D%40")
    }

    @Test func removingDotSegments() {
        #expect(S3Signer.removingDotSegments("/example/..") == "/")
        #expect(S3Signer.removingDotSegments("//example//") == "/example/")
        #expect(S3Signer.removingDotSegments("/./example") == "/example")
        #expect(S3Signer.removingDotSegments("/a/b/../c/") == "/a/c/")
    }

    @Test func canonicalHeadersTrimsCollapsesAndJoinsDuplicates() {
        let result = S3Signer.canonicalHeaders([
            ("My-Header1", " value2 "), ("Host", "h"), ("my-header1", "value1"), ("X", "\"a   b   c\""),
        ])
        #expect(result.canonical == "host:h\nmy-header1:value2,value1\nx:\"a b c\"\n")
        #expect(result.signed == "host;my-header1;x")
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'S3Signer' in scope`.

- [ ] **Step 5: Implement the signer**

`TidyShot/Upload/S3Signer.swift`:
```swift
import CryptoKit
import Foundation

/// AWS Signature Version 4 for one HTTP request. Pure functions, no networking.
/// `nonisolated` so the upload actor can call it without hopping to the main actor.
///
/// S3 rules: the path is percent-encoded once (RFC 3986 unreserved set, `/` kept) and is not
/// normalized (no dot-segment removal, no slash collapsing). `normalizePath: true` exists only
/// so the generic AWS test suite can run; TidyShot always signs S3 requests unnormalized.
nonisolated enum S3Signer {
    /// The parts of a request that take part in signing. `path`, query names and values are
    /// the *decoded* values; the signer applies the canonical percent-encoding itself.
    struct Request: Sendable {
        var method: String
        var path: String
        var query: [(name: String, value: String)]
        var headers: [(name: String, value: String)]
        var payloadHash: String

        init(method: String,
             path: String,
             query: [(name: String, value: String)] = [],
             headers: [(name: String, value: String)],
             payloadHash: String) {
            self.method = method
            self.path = path
            self.query = query
            self.headers = headers
            self.payloadHash = payloadHash
        }
    }

    struct Signed: Sendable {
        let canonicalRequest: String
        let stringToSign: String
        let signature: String
        /// Headers to add to the outgoing request: `x-amz-date`, `x-amz-security-token` when a
        /// session token is present, and `authorization`.
        let headers: [(name: String, value: String)]
    }

    static let algorithm = "AWS4-HMAC-SHA256"
    /// SHA-256 of zero bytes; the payload hash for HEAD, GET and DELETE.
    static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// Signs `request`. The caller must already have put `host` and (for S3) `x-amz-content-sha256`
    /// in `request.headers`; every header in the list is signed.
    static func sign(_ request: Request,
                     credentials: AWSCredentials,
                     region: String,
                     service: String = "s3",
                     date: Date,
                     normalizePath: Bool = false) -> Signed {
        let amzDate = amzDateString(date)
        let dateStamp = String(amzDate.prefix(8))

        var headers = request.headers
        headers.append((name: "x-amz-date", value: amzDate))
        if let token = credentials.sessionToken, !token.isEmpty {
            headers.append((name: "x-amz-security-token", value: token))
        }

        let canonicalHeaders = canonicalHeaders(headers)
        let canonicalRequest = [
            request.method.uppercased(),
            canonicalURI(request.path, normalize: normalizePath),
            canonicalQuery(request.query),
            canonicalHeaders.canonical,
            canonicalHeaders.signed,
            request.payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let key = signingKey(secret: credentials.secretAccessKey, dateStamp: dateStamp, region: region, service: service)
        let signature = hmacHex(key: key, message: stringToSign)

        let authorization = "\(algorithm) Credential=\(credentials.accessKeyID)/\(scope), "
            + "SignedHeaders=\(canonicalHeaders.signed), Signature=\(signature)"

        var added: [(name: String, value: String)] = [(name: "x-amz-date", value: amzDate)]
        if let token = credentials.sessionToken, !token.isEmpty {
            added.append((name: "x-amz-security-token", value: token))
        }
        added.append((name: "authorization", value: authorization))

        return Signed(canonicalRequest: canonicalRequest, stringToSign: stringToSign, signature: signature, headers: added)
    }

    // MARK: Canonical pieces

    /// Percent-encodes every byte outside `A-Z a-z 0-9 - _ . ~`, using uppercase hex.
    /// With `keepSlash`, `/` is left alone (object key paths); without it, `/` becomes `%2F` (query parts).
    static func uriEncode(_ string: String, keepSlash: Bool) -> String {
        var output = ""
        output.reserveCapacity(string.utf8.count)
        for byte in string.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                output.unicodeScalars.append(UnicodeScalar(byte))
            case UInt8(ascii: "/") where keepSlash:
                output.append("/")
            default:
                output.append("%")
                output.append(hexDigit(byte >> 4))
                output.append(hexDigit(byte & 0x0F))
            }
        }
        return output
    }

    static func canonicalURI(_ path: String, normalize: Bool) -> String {
        var path = path.isEmpty ? "/" : path
        if normalize {
            path = removingDotSegments(path)
        }
        return uriEncode(path, keepSlash: true)
    }

    /// RFC 3986 dot-segment removal plus collapsing of repeated slashes, as the generic AWS
    /// signing rules require for services other than S3.
    static func removingDotSegments(_ path: String) -> String {
        var segments: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(segment)
            }
        }
        var result = "/" + segments.joined(separator: "/")
        if path.hasSuffix("/"), result != "/" {
            result += "/"
        }
        return result
    }

    /// Encoded `name=value` pairs sorted by name then value (byte order).
    static func canonicalQuery(_ query: [(name: String, value: String)]) -> String {
        var pairs: [(name: String, value: String)] = query.map { item in
            (name: uriEncode(item.name, keepSlash: false), value: uriEncode(item.value, keepSlash: false))
        }
        pairs.sort { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.value < rhs.value
        }
        let encoded: [String] = pairs.map { "\($0.name)=\($0.value)" }
        return encoded.joined(separator: "&")
    }

    /// Lowercased names, trimmed values with internal whitespace runs collapsed to one space,
    /// duplicate names joined with commas in their original order, sorted by name.
    /// Returns the canonical header block (each line newline-terminated) and the `;` list of names.
    static func canonicalHeaders(_ headers: [(name: String, value: String)]) -> (canonical: String, signed: String) {
        var grouped: [String: [String]] = [:]
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespaces).lowercased()
            let value = header.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            grouped[name, default: []].append(value)
        }
        let names = grouped.keys.sorted()
        let canonical = names.map { "\($0):\(grouped[$0]!.joined(separator: ","))\n" }.joined()
        return (canonical, names.joined(separator: ";"))
    }

    // MARK: Crypto helpers

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { byteHex($0) }.joined()
    }

    static func signingKey(secret: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        var key = SymmetricKey(data: Data("AWS4\(secret)".utf8))
        for component in [dateStamp, region, service, "aws4_request"] {
            let mac = HMAC<SHA256>.authenticationCode(for: Data(component.utf8), using: key)
            key = SymmetricKey(data: Data(mac))
        }
        return key
    }

    static func hmacHex(key: SymmetricKey, message: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key).map { byteHex($0) }.joined()
    }

    /// `yyyyMMdd'T'HHmmss'Z'` in UTC.
    static func amzDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func hexDigit(_ value: UInt8) -> Character {
        Character(UnicodeScalar(value < 10 ? 0x30 + value : 0x41 + value - 10))
    }

    private static func byteHex(_ byte: UInt8) -> String {
        let digits = Array("0123456789abcdef")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }
}
```

Notes on the implementation: `canonicalQuery` is written as three statements on purpose; a single chained `map.sorted.map.joined` expression makes the Swift 6 type checker give up ("unable to type-check this expression in reasonable time"). `uriEncode` works on UTF-8 bytes so `ሴ` becomes `%E1%88%B4`, matching the AWS test vectors.

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 39 tests in 6 suites passed`.

- [ ] **Step 7: Confirm the entitlement landed**

Run:
```bash
grep -A1 'network.client' TidyShot/TidyShot.entitlements
```
Expected:
```
	<key>com.apple.security.network.client</key>
	<true/>
```

- [ ] **Step 8: Commit**

```bash
git add project.yml TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/S3Signer.swift TidyShotTests/S3SignerTests.swift
git commit -m "feat: add SigV4 signer and network client entitlement"
```

---

### Task 2: Run the AWS SigV4 test suite against the signer

**Files:**
- Create: `TidyShotTests/Fixtures/aws-sig-v4-test-suite/` (38 case folders plus `LICENSE`, downloaded)
- Modify: `project.yml` (TidyShotTests sources)
- Create: `TidyShotTests/SigV4TestSuiteTests.swift`

**Interfaces:**
- Consumes: `S3Signer.sign`, `S3Signer.sha256Hex`, `AWSCredentials` from Task 1.
- Produces: `final class FixtureLocator` in the test target (anchor for `Bundle(for:)`), reusable by later fixture-based tests.

Background: AWS no longer hosts the SigV4 test suite zip on docs.aws.amazon.com (the old URL returns 404). The same suite is maintained in `awslabs/aws-c-auth` under `tests/aws-signing-test-suite/v4`, Apache-2.0. Each case folder holds `request.txt` (a raw HTTP request), `context.json` (credentials, region, service, timestamp, `normalize`, `sign_body`), `header-canonical-request.txt` and `header-signature.txt` (expected values for header-based signing), plus `query-*` files for pre-signed URLs, which TidyShot does not use. All cases use access key `AKIDEXAMPLE`, secret `wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY`, region `us-east-1`, service `service`, timestamp `2015-08-30T12:36:00Z`. The two `post-sts-*` cases sign without the session token and attach it afterwards; TidyShot never does that, so they are skipped. The `*-unnormalized` cases exercise exactly the S3 path rules.

- [ ] **Step 1: Download the fixtures at a pinned commit**

Run:
```bash
SHA=84a26ea184d9ccd322c8164759510b3604ab13fd
curl -sSL -o /tmp/aws-c-auth.tar.gz "https://github.com/awslabs/aws-c-auth/archive/$SHA.tar.gz"
mkdir -p TidyShotTests/Fixtures
tar -xzf /tmp/aws-c-auth.tar.gz -C /tmp "aws-c-auth-$SHA/tests/aws-signing-test-suite/v4" "aws-c-auth-$SHA/LICENSE"
mv "/tmp/aws-c-auth-$SHA/tests/aws-signing-test-suite/v4" TidyShotTests/Fixtures/aws-sig-v4-test-suite
cp "/tmp/aws-c-auth-$SHA/LICENSE" TidyShotTests/Fixtures/aws-sig-v4-test-suite/LICENSE
rm -rf "/tmp/aws-c-auth-$SHA" /tmp/aws-c-auth.tar.gz
ls TidyShotTests/Fixtures/aws-sig-v4-test-suite | wc -l
find TidyShotTests/Fixtures/aws-sig-v4-test-suite -type f | wc -l
```
Expected: `39` then `381`. Spot check:
```bash
cat TidyShotTests/Fixtures/aws-sig-v4-test-suite/get-vanilla/header-signature.txt; echo
```
Expected: `5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31`.

- [ ] **Step 2: Add the fixtures as a folder reference in project.yml**

Replace the `TidyShotTests` target's `sources` block with:

```yaml
  TidyShotTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: TidyShotTests
        excludes:
          - "Fixtures/**"
      - path: TidyShotTests/Fixtures
        type: folder
        buildPhase: resources
```

The folder reference keeps the directory structure inside the test bundle (`Fixtures/aws-sig-v4-test-suite/<case>/request.txt`); without `excludes`, XcodeGen would copy 38 identically named `request.txt` files flat into the bundle.

- [ ] **Step 3: Write the suite runner**

`TidyShotTests/SigV4TestSuiteTests.swift`:
```swift
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
```

The three `nonisolated static let`s matter: the test struct is main-actor isolated by default, and `@Test(arguments:)` reads the collection outside the actor.

- [ ] **Step 4: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘|argument .* get-vanilla\"" 
```
Expected: a line `Test case passing 1 argument name → "get-vanilla" to suiteCase(name:) started.` and `Test run with 41 tests in 7 suites passed` (the 36 cases count as one parameterized test). If `fixturesArePresent` fails with `found []`, the folder reference did not land: re-check Step 2 and run `xcodegen generate` again.

- [ ] **Step 5: Commit**

```bash
git add project.yml TidyShotTests/Fixtures TidyShotTests/SigV4TestSuiteTests.swift
git commit -m "test: run the AWS SigV4 test suite against S3Signer"
```

---

### Task 3: Object key naming (TDD)

**Files:**
- Create: `TidyShot/Upload/ObjectKeyNamer.swift`
- Create: `TidyShotTests/ObjectKeyNamerTests.swift`

**Interfaces:**
- Consumes: `FileNamer.randomString(length:)` (Phase 1, `nonisolated static`).
- Produces: `struct ObjectKeyNamer: Sendable` with `static let lengthRange = 4...32`, `static let defaultLength = 6`, `var prefix: String`, `var length: Int`, `var randomString: @Sendable (Int) -> String`, `init(prefix:length:randomString:)` (all defaulted), `func makeKey(ext: String) -> String`, `static func clamp(_ length: Int) -> Int`, `static func join(prefix: String, name: String) -> String`, `static func normalizePrefix(_ prefix: String) -> String`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ObjectKeyNamerTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ObjectKeyNamerTests {
    func namer(prefix: String = "", length: Int = 6) -> ObjectKeyNamer {
        ObjectKeyNamer(prefix: prefix, length: length, randomString: { String(repeating: "X", count: $0) })
    }

    @Test func defaultIsSixRandomCharactersPlusExtension() {
        #expect(namer().makeKey(ext: "png") == "XXXXXX.png")
    }

    @Test func prefixBecomesFolder() {
        #expect(namer(prefix: "shots").makeKey(ext: "png") == "shots/XXXXXX.png")
        #expect(namer(prefix: "/a/b/").makeKey(ext: "png") == "a/b/XXXXXX.png")
        #expect(namer(prefix: "  ").makeKey(ext: "png") == "XXXXXX.png")
    }

    @Test func lengthIsClampedToFourThroughThirtyTwo() {
        #expect(namer(length: 1).makeKey(ext: "png") == "XXXX.png")
        #expect(namer(length: 99).makeKey(ext: "png") == String(repeating: "X", count: 32) + ".png")
        #expect(namer(length: 8).makeKey(ext: "png") == "XXXXXXXX.png")
    }

    @Test func realKeysUseTheFileNamerAlphabet() {
        let key = ObjectKeyNamer(length: 10).makeKey(ext: "png")
        #expect(key.count == 14)
        #expect(key.hasSuffix(".png"))
        #expect(key.dropLast(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    @Test func joinHelper() {
        #expect(ObjectKeyNamer.join(prefix: "", name: "probe.txt") == "probe.txt")
        #expect(ObjectKeyNamer.join(prefix: "p/", name: "probe.txt") == "p/probe.txt")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'ObjectKeyNamer' in scope`.

- [ ] **Step 3: Implement the namer**

`TidyShot/Upload/ObjectKeyNamer.swift`:
```swift
import Foundation

/// Builds S3 object keys: an optional prefix folder, a random name, and an extension,
/// for example `shots/aSIS7x.png`. Random characters come from `FileNamer.randomString`.
nonisolated struct ObjectKeyNamer: Sendable {
    static let lengthRange = 4...32
    static let defaultLength = 6

    var prefix: String
    var length: Int
    var randomString: @Sendable (Int) -> String

    init(prefix: String = "", length: Int = ObjectKeyNamer.defaultLength,
         randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) {
        self.prefix = prefix
        self.length = length
        self.randomString = randomString
    }

    /// `prefix/RANDOM.ext`, or `RANDOM.ext` without a prefix. `ext` is given without a dot.
    func makeKey(ext: String) -> String {
        let name = randomString(Self.clamp(length)) + "." + ext
        return Self.join(prefix: prefix, name: name)
    }

    static func clamp(_ length: Int) -> Int {
        min(max(length, lengthRange.lowerBound), lengthRange.upperBound)
    }

    /// Trims whitespace and slashes from `prefix` and joins it to `name` with one slash.
    static func join(prefix: String, name: String) -> String {
        let cleaned = normalizePrefix(prefix)
        return cleaned.isEmpty ? name : "\(cleaned)/\(name)"
    }

    static func normalizePrefix(_ prefix: String) -> String {
        prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 46 tests in 8 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Upload/ObjectKeyNamer.swift TidyShotTests/ObjectKeyNamerTests.swift
git commit -m "feat: add random object key naming with prefix and length"
```

---

### Task 4: Destination configuration and URL building (TDD)

**Files:**
- Create: `TidyShot/Upload/S3DestinationConfig.swift`
- Create: `TidyShotTests/S3DestinationConfigTests.swift`

**Interfaces:**
- Consumes: `S3Signer.uriEncode(_:keepSlash:)` (Task 1), `ObjectKeyNamer.defaultLength` (Task 3).
- Produces: `struct S3DestinationConfig: Codable, Equatable, Sendable` with
  - `var endpoint: String`, `var region: String`, `var bucket: String`, `var keyPrefix: String`, `var usePathStyle: Bool`, `var sendPublicReadACL: Bool`, `var publicURLTemplate: String`, `var keyLength: Int`
  - `init(endpoint:region:bucket:keyPrefix:usePathStyle:sendPublicReadACL:publicURLTemplate:keyLength:)` (defaults: `keyPrefix ""`, flags `false`, `keyLength ObjectKeyNamer.defaultLength`)
  - `static let empty`, `static let keyToken = "{key}"`
  - `enum ConfigError: LocalizedError, Equatable { case invalidEndpoint, missingBucket, missingRegion, invalidPublicURLTemplate }`
  - `var validationError: ConfigError?`, `var isComplete: Bool`, `var endpointURL: URL?`
  - `func objectPath(for key: String) -> String` (decoded, `/key` or `/bucket/key`)
  - `func objectURL(for key: String) throws -> URL`
  - `func hostHeader(for url: URL) -> String` (`host` or `host:port`)
  - `func publicURL(for key: String) throws -> URL`

Background: virtual-host style puts the bucket in the host (`https://snap.s3.us-west-2.amazonaws.com/key`); path style puts it in the path (`http://localhost:9000/snap/key`). MinIO needs path style; so do bucket names with dots over HTTPS, because the wildcard certificate only covers one label. The `host` header that gets signed must match what URLSession sends, which includes the port only when the endpoint names one.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/S3DestinationConfigTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct S3DestinationConfigTests {
    let aws = S3DestinationConfig(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2", bucket: "snap",
                                  publicURLTemplate: "https://snap.tky.io/{key}")

    @Test func virtualHostURL() throws {
        #expect(try aws.objectURL(for: "aSIS7.png").absoluteString == "https://snap.s3.us-west-2.amazonaws.com/aSIS7.png")
        #expect(aws.objectPath(for: "aSIS7.png") == "/aSIS7.png")
        #expect(aws.hostHeader(for: try aws.objectURL(for: "aSIS7.png")) == "snap.s3.us-west-2.amazonaws.com")
    }

    @Test func pathStyleURLWithPortForMinIO() throws {
        var minio = aws
        minio.endpoint = "http://localhost:9000"
        minio.usePathStyle = true
        let url = try minio.objectURL(for: "shots/aSIS7.png")
        #expect(url.absoluteString == "http://localhost:9000/snap/shots/aSIS7.png")
        #expect(minio.objectPath(for: "shots/aSIS7.png") == "/snap/shots/aSIS7.png")
        #expect(minio.hostHeader(for: url) == "localhost:9000")
    }

    @Test func r2AndB2Endpoints() throws {
        var r2 = aws
        r2.endpoint = "https://0123456789abcdef.r2.cloudflarestorage.com"
        r2.region = "auto"
        r2.usePathStyle = true
        #expect(try r2.objectURL(for: "a.png").absoluteString == "https://0123456789abcdef.r2.cloudflarestorage.com/snap/a.png")

        var b2 = aws
        b2.endpoint = "https://s3.us-west-004.backblazeb2.com"
        b2.region = "us-west-004"
        #expect(try b2.objectURL(for: "a.png").absoluteString == "https://snap.s3.us-west-004.backblazeb2.com/a.png")
    }

    @Test func keysWithSpacesAreEncodedInURLButNotInPath() throws {
        let url = try aws.objectURL(for: "my shot.png")
        #expect(url.absoluteString == "https://snap.s3.us-west-2.amazonaws.com/my%20shot.png")
        #expect(aws.objectPath(for: "my shot.png") == "/my shot.png")
    }

    @Test func publicURLFromTemplate() throws {
        #expect(try aws.publicURL(for: "aSIS7.png").absoluteString == "https://snap.tky.io/aSIS7.png")
        #expect(try aws.publicURL(for: "shots/aSIS7.png").absoluteString == "https://snap.tky.io/shots/aSIS7.png")
    }

    @Test func validation() {
        #expect(aws.validationError == nil)
        #expect(S3DestinationConfig.empty.validationError == .invalidEndpoint)

        var noBucket = aws
        noBucket.bucket = " "
        #expect(noBucket.validationError == .missingBucket)

        var noRegion = aws
        noRegion.region = ""
        #expect(noRegion.validationError == .missingRegion)

        var badTemplate = aws
        badTemplate.publicURLTemplate = "https://snap.tky.io/"
        #expect(badTemplate.validationError == .invalidPublicURLTemplate)

        var ftp = aws
        ftp.endpoint = "ftp://example.com"
        #expect(ftp.validationError == .invalidEndpoint)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(aws)
        #expect(try JSONDecoder().decode(S3DestinationConfig.self, from: data) == aws)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'S3DestinationConfig' in scope`.

- [ ] **Step 3: Implement the config**

`TidyShot/Upload/S3DestinationConfig.swift`:
```swift
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
    /// Optional folder inside the bucket; leading and trailing slashes are ignored.
    var keyPrefix: String
    /// `https://host/bucket/key` instead of `https://bucket.host/key`. Needed for MinIO and for
    /// bucket names containing dots over HTTPS.
    var usePathStyle: Bool
    /// Adds `x-amz-acl: public-read` to every PUT. Off by default; most buckets use a policy or CDN.
    var sendPublicReadACL: Bool
    /// Where the object is readable from, with `{key}` standing for the full object key.
    var publicURLTemplate: String
    /// Length of the random part of object keys, clamped to `ObjectKeyNamer.lengthRange`.
    var keyLength: Int

    static let keyToken = "{key}"

    static let empty = S3DestinationConfig(endpoint: "", region: "", bucket: "", keyPrefix: "",
                                           usePathStyle: false, sendPublicReadACL: false,
                                           publicURLTemplate: "", keyLength: ObjectKeyNamer.defaultLength)

    init(endpoint: String, region: String, bucket: String, keyPrefix: String = "",
         usePathStyle: Bool = false, sendPublicReadACL: Bool = false,
         publicURLTemplate: String, keyLength: Int = ObjectKeyNamer.defaultLength) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.keyPrefix = keyPrefix
        self.usePathStyle = usePathStyle
        self.sendPublicReadACL = sendPublicReadACL
        self.publicURLTemplate = publicURLTemplate
        self.keyLength = keyLength
    }

    enum ConfigError: LocalizedError, Equatable {
        case invalidEndpoint
        case missingBucket
        case missingRegion
        case invalidPublicURLTemplate

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "Endpoint must be an http or https URL such as https://s3.us-west-2.amazonaws.com."
            case .missingBucket: "Bucket name is required."
            case .missingRegion: "Region is required (use \"auto\" for Cloudflare R2)."
            case .invalidPublicURLTemplate: "Public URL must be an http or https URL containing {key}."
            }
        }
    }

    /// The first problem with this configuration, or nil when it can be used.
    var validationError: ConfigError? {
        guard let endpointURL, ["http", "https"].contains(endpointURL.scheme ?? ""), endpointURL.host() != nil else {
            return .invalidEndpoint
        }
        if bucket.trimmingCharacters(in: .whitespaces).isEmpty { return .missingBucket }
        if region.trimmingCharacters(in: .whitespaces).isEmpty { return .missingRegion }
        let template = publicURLTemplate.trimmingCharacters(in: .whitespaces)
        guard template.contains(Self.keyToken),
              let probe = URL(string: template.replacingOccurrences(of: Self.keyToken, with: "probe")),
              ["http", "https"].contains(probe.scheme ?? "") else {
            return .invalidPublicURLTemplate
        }
        return nil
    }

    var isComplete: Bool { validationError == nil }

    var endpointURL: URL? {
        URL(string: endpoint.trimmingCharacters(in: .whitespaces))
    }

    /// The decoded request path for `key`: `/key` (virtual-host) or `/bucket/key` (path-style).
    func objectPath(for key: String) -> String {
        usePathStyle ? "/\(bucket)/\(key)" : "/\(key)"
    }

    /// The URL the signed request is sent to.
    func objectURL(for key: String) throws -> URL {
        guard let endpointURL, var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else {
            throw ConfigError.invalidEndpoint
        }
        if !usePathStyle {
            components.host = "\(bucket).\(host)"
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
        let template = publicURLTemplate.trimmingCharacters(in: .whitespaces)
        guard template.contains(Self.keyToken),
              let url = URL(string: template.replacingOccurrences(of: Self.keyToken, with: S3Signer.uriEncode(key, keepSlash: true))),
              ["http", "https"].contains(url.scheme ?? "") else {
            throw ConfigError.invalidPublicURLTemplate
        }
        return url
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 53 tests in 9 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Upload/S3DestinationConfig.swift TidyShotTests/S3DestinationConfigTests.swift
git commit -m "feat: add S3 destination config with URL building and validation"
```

---

### Task 5: Destination protocol, upload types, and retry policy (TDD)

**Files:**
- Create: `TidyShot/Upload/Destination.swift`
- Create: `TidyShot/Upload/RetryPolicy.swift`
- Create: `TidyShotTests/RetryPolicyTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `protocol Destination: Sendable` with `func exists(key: String) async throws -> Bool`, `func upload(_ data: Data, key: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws`, `func delete(key: String) async throws`, `func publicURL(for key: String) throws -> URL`.
  - `struct UploadJob: Sendable, Identifiable { let id: UUID; let data: Data; let contentType: String; let fileExtension: String }` (memberwise init).
  - `enum UploadEvent: Sendable, Equatable { case started(id: UUID, attempt: Int); case progress(id: UUID, fraction: Double); case uploaded(id: UUID, url: URL, key: String); case failed(id: UUID, message: String) }`.
  - `enum UploadError: LocalizedError, Equatable, Sendable { case httpStatus(Int, body: String); case noHTTPResponse; case keyCollisionsExhausted; case notConfigured; case fileUnreadable(String) }` with `var isRetryable: Bool` and `static func isRetryable(_ error: Error) -> Bool`.
  - `struct RetryPolicy: Sendable, Equatable { var maxAttempts: Int; var baseDelay: Duration; var maxDelay: Duration }`, `static let default`, `static let immediate`, `func delay(beforeAttempt attempt: Int) -> Duration`.

- [ ] **Step 1: Write the failing retry tests**

`TidyShotTests/RetryPolicyTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct RetryPolicyTests {
    @Test func defaultBackoffDoubles() {
        let policy = RetryPolicy.default
        #expect(policy.maxAttempts == 3)
        #expect(policy.delay(beforeAttempt: 1) == .zero)
        #expect(policy.delay(beforeAttempt: 2) == .seconds(1))
        #expect(policy.delay(beforeAttempt: 3) == .seconds(2))
        #expect(policy.delay(beforeAttempt: 4) == .seconds(4))
    }

    @Test func delayIsCapped() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: .seconds(1), maxDelay: .seconds(5))
        #expect(policy.delay(beforeAttempt: 6) == .seconds(5))
        #expect(policy.delay(beforeAttempt: 40) == .seconds(5))
    }

    @Test func immediatePolicyNeverWaits() {
        #expect(RetryPolicy.immediate.delay(beforeAttempt: 3) == .zero)
    }
}
```

- [ ] **Step 2: Write the protocol and types**

`TidyShot/Upload/Destination.swift`:
```swift
import Foundation

/// An upload target. One implementation today (`S3Destination`); the protocol keeps the queue,
/// tests, and a future second backend independent of S3 details.
nonisolated protocol Destination: Sendable {
    /// True when an object already exists at `key` (HTTP 200 on HEAD), false on 404.
    func exists(key: String) async throws -> Bool
    /// Uploads `data` to `key`. `progress` receives fractions in 0...1 from the transport thread.
    func upload(_ data: Data, key: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws
    /// Best-effort removal, used by the connection test to clean up its probe object.
    func delete(key: String) async throws
    /// Where `key` can be read from after upload.
    func publicURL(for key: String) throws -> URL
}

nonisolated struct UploadJob: Sendable, Identifiable {
    /// Matches the `CaptureRecord.id` this upload belongs to.
    let id: UUID
    let data: Data
    let contentType: String
    /// Without a dot, for example `png`.
    let fileExtension: String
}

nonisolated enum UploadEvent: Sendable, Equatable {
    case started(id: UUID, attempt: Int)
    case progress(id: UUID, fraction: Double)
    case uploaded(id: UUID, url: URL, key: String)
    case failed(id: UUID, message: String)
}

nonisolated enum UploadError: LocalizedError, Equatable, Sendable {
    case httpStatus(Int, body: String)
    case noHTTPResponse
    case keyCollisionsExhausted
    case notConfigured
    case fileUnreadable(String)

    /// Server-side and transport failures are retried; client errors (bad credentials,
    /// missing bucket, forbidden) are not.
    var isRetryable: Bool {
        switch self {
        case .httpStatus(let status, _): status >= 500 || status == 429
        case .noHTTPResponse: true
        case .keyCollisionsExhausted, .notConfigured, .fileUnreadable: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status, let body):
            body.isEmpty ? "Server returned HTTP \(status)." : "Server returned HTTP \(status): \(body)"
        case .noHTTPResponse: "No HTTP response."
        case .keyCollisionsExhausted: "Could not find an unused object key after 5 tries."
        case .notConfigured: "No upload destination is configured."
        case .fileUnreadable(let path): "The file could not be read: \(path)"
        }
    }

    /// Whether an arbitrary error thrown during an upload attempt is worth retrying.
    static func isRetryable(_ error: Error) -> Bool {
        if let uploadError = error as? UploadError { return uploadError.isRetryable }
        return error is URLError
    }
}
```

- [ ] **Step 3: Implement the retry policy**

`TidyShot/Upload/RetryPolicy.swift`:
```swift
import Foundation

/// Exponential backoff: attempt 2 waits `baseDelay`, attempt 3 waits twice that, and so on,
/// capped at `maxDelay`.
nonisolated struct RetryPolicy: Sendable, Equatable {
    var maxAttempts: Int
    var baseDelay: Duration
    var maxDelay: Duration

    static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: .seconds(1), maxDelay: .seconds(30))
    /// For tests: same attempt count, no waiting.
    static let immediate = RetryPolicy(maxAttempts: 3, baseDelay: .zero, maxDelay: .zero)

    /// The wait before `attempt` (2-based: the first retry is attempt 2).
    func delay(beforeAttempt attempt: Int) -> Duration {
        guard attempt >= 2 else { return .zero }
        let multiplier = 1 << min(attempt - 2, 30)
        return min(baseDelay * multiplier, maxDelay)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 56 tests in 10 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Upload/Destination.swift TidyShot/Upload/RetryPolicy.swift TidyShotTests/RetryPolicyTests.swift
git commit -m "feat: add Destination protocol, upload event types, and retry policy"
```

---

### Task 6: S3Destination over URLSession with progress (TDD with a stub URLProtocol)

**Files:**
- Create: `TidyShot/Upload/UploadProgressDelegate.swift`
- Create: `TidyShot/Upload/S3Destination.swift`
- Create: `TidyShotTests/S3DestinationTests.swift`

**Interfaces:**
- Consumes: `S3Signer`, `AWSCredentials` (Task 1), `S3DestinationConfig` (Task 4), `Destination`, `UploadError` (Task 5).
- Produces:
  - `final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable`, `init(onProgress: @escaping @Sendable (Double) -> Void)`.
  - `struct S3Destination: Destination` with `let config: S3DestinationConfig`, `let credentials: AWSCredentials`, `let session: URLSession`, `let now: @Sendable () -> Date`, `init(config:credentials:session:now:)` (session defaults to `.shared`, now to `{ Date() }`), the four protocol methods, and `func signedRequest(method: String, key: String, body: Data?, extraHeaders: [(name: String, value: String)]) throws -> URLRequest`.
  - In the test target: `final class StubURLProtocol: URLProtocol` with `static func makeSession() -> URLSession`, `static func reset(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, body: Data))`, `static let requests: Mutex<[URLRequest]>`. Task 8's tests reuse it.

Background: `URLSession.upload(for:from:delegate:)` (macOS 12+, verified in the macOS 27 SDK Foundation interface) accepts a per-task delegate, and `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` fires as the body goes out. Under default main-actor isolation the delegate class must be `nonisolated`; the closure it calls is `@Sendable` because it runs on URLSession's queue. The expected signatures in the tests were computed with an independent SigV4 implementation (Python, `hmac`/`hashlib`) for 2026-10-19T12:00:00Z, so they catch wiring mistakes (wrong host header, unsigned content-type) that a self-referential check would miss.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/S3DestinationTests.swift`:
```swift
import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// Answers every request from a handler and records what was sent.
nonisolated final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)

    static let handler = Mutex<Handler?>(nil)
    static let requests = Mutex<[URLRequest]>([])

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset(_ handler: @escaping Handler) {
        self.handler.withLock { $0 = handler }
        requests.withLock { $0 = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        guard let handler = Self.handler.withLock({ $0 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct S3DestinationTests {
    let credentials = AWSCredentials(accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                                     secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    /// 2026-10-19T12:00:00Z
    let date = Date(timeIntervalSince1970: 1_792_411_200)
    let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                     publicURLTemplate: "https://snap.tky.io/{key}")
    let body = Data("hello".utf8)

    func destination(_ config: S3DestinationConfig) -> S3Destination {
        S3Destination(config: config, credentials: credentials, session: StubURLProtocol.makeSession(), now: { date })
    }

    @Test func amzDateForFixedDate() {
        #expect(S3Signer.amzDateString(date) == "20261019T120000Z")
    }

    /// Expected signature computed independently with a reference implementation.
    @Test func putIsSignedWithContentTypeAndNoACLByDefault() async throws {
        StubURLProtocol.reset { _ in (200, Data()) }
        try await destination(config).upload(body, key: "aSIS7.png", contentType: "image/png") { _ in }

        let request = try #require(StubURLProtocol.requests.withLock { $0.first })
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://snap.s3.us-east-1.amazonaws.com/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "content-type") == "image/png")
        #expect(request.value(forHTTPHeaderField: "x-amz-acl") == nil)
        #expect(request.value(forHTTPHeaderField: "x-amz-date") == "20261019T120000Z")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=3ae54c07f6b6d4782a0ad2debd05c43fb93bcb0a1400d61138f78b140d700de9")
    }

    @Test func aclHeaderIsSentAndSignedWhenEnabled() async throws {
        var acl = config
        acl.sendPublicReadACL = true
        StubURLProtocol.reset { _ in (200, Data()) }
        try await destination(acl).upload(body, key: "aSIS7.png", contentType: "image/png") { _ in }

        let request = try #require(StubURLProtocol.requests.withLock { $0.first })
        #expect(request.value(forHTTPHeaderField: "x-amz-acl") == "public-read")
        #expect(request.value(forHTTPHeaderField: "authorization")?.hasSuffix("SignedHeaders=content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date, Signature=5a73cf67b570cbc19fd956f9a79769a4e94ba9415f3ff138609de89785481d5f") == true)
    }

    @Test func headUsesPathStyleAndPortedHost() async throws {
        var minio = config
        minio.endpoint = "http://localhost:9000"
        minio.usePathStyle = true
        StubURLProtocol.reset { _ in (404, Data()) }
        let exists = try await destination(minio).exists(key: "aSIS7.png")

        #expect(exists == false)
        let request = try #require(StubURLProtocol.requests.withLock { $0.first })
        #expect(request.httpMethod == "HEAD")
        #expect(request.url?.absoluteString == "http://localhost:9000/snap/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == S3Signer.emptyPayloadHash)
        #expect(request.value(forHTTPHeaderField: "authorization")?.hasSuffix("Signature=ea41793386c929fe127e31d41a7a6c0afa254275a313db5f86a9132ea8e68793") == true)
    }

    @Test func existsMapsStatusCodes() async throws {
        StubURLProtocol.reset { _ in (200, Data()) }
        #expect(try await destination(config).exists(key: "a.png") == true)

        StubURLProtocol.reset { _ in (403, Data()) }
        await #expect(throws: UploadError.httpStatus(403, body: "")) {
            try await destination(config).exists(key: "a.png")
        }
    }

    @Test func uploadThrowsRetryableErrorOnServerFailure() async throws {
        StubURLProtocol.reset { _ in (500, Data("<Error>InternalError</Error>".utf8)) }
        await #expect(throws: UploadError.httpStatus(500, body: "<Error>InternalError</Error>")) {
            try await destination(config).upload(body, key: "a.png", contentType: "image/png") { _ in }
        }
        #expect(UploadError.httpStatus(500, body: "").isRetryable)
        #expect(!UploadError.httpStatus(403, body: "").isRetryable)
    }

    @Test func deleteAccepts204And404() async throws {
        StubURLProtocol.reset { _ in (204, Data()) }
        try await destination(config).delete(key: "a.png")
        StubURLProtocol.reset { _ in (404, Data()) }
        try await destination(config).delete(key: "a.png")
        let methods = StubURLProtocol.requests.withLock { $0.map(\.httpMethod) }
        #expect(methods == ["DELETE"])
    }
}
```

- [ ] **Step 2: Write the progress delegate**

`TidyShot/Upload/UploadProgressDelegate.swift`:
```swift
import Foundation

/// Forwards URLSession upload progress to a closure. URLSession calls delegates on its own
/// queue, so the class is `nonisolated` and the closure must be `@Sendable`.
nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
```

- [ ] **Step 3: Implement the destination**

`TidyShot/Upload/S3Destination.swift`:
```swift
import Foundation

/// PUT, HEAD and DELETE Object over URLSession with SigV4 headers. Works with AWS S3,
/// Cloudflare R2, Backblaze B2 and MinIO, which all speak the same three requests.
nonisolated struct S3Destination: Destination {
    let config: S3DestinationConfig
    let credentials: AWSCredentials
    let session: URLSession
    let now: @Sendable () -> Date

    init(config: S3DestinationConfig, credentials: AWSCredentials,
         session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.credentials = credentials
        self.session = session
        self.now = now
    }

    func exists(key: String) async throws -> Bool {
        let request = try signedRequest(method: "HEAD", key: key, body: nil, extraHeaders: [])
        let (_, response) = try await session.data(for: request)
        let status = try Self.status(of: response)
        switch status {
        case 200: return true
        case 404: return false
        default: throw UploadError.httpStatus(status, body: "")
        }
    }

    func upload(_ data: Data, key: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        var headers = [(name: "content-type", value: contentType)]
        if config.sendPublicReadACL {
            headers.append((name: "x-amz-acl", value: "public-read"))
        }
        let request = try signedRequest(method: "PUT", key: key, body: data, extraHeaders: headers)
        let delegate = UploadProgressDelegate(onProgress: progress)
        let (body, response) = try await session.upload(for: request, from: data, delegate: delegate)
        let status = try Self.status(of: response)
        guard (200..<300).contains(status) else {
            throw UploadError.httpStatus(status, body: Self.excerpt(body))
        }
    }

    func delete(key: String) async throws {
        let request = try signedRequest(method: "DELETE", key: key, body: nil, extraHeaders: [])
        let (body, response) = try await session.data(for: request)
        let status = try Self.status(of: response)
        guard (200..<300).contains(status) || status == 404 else {
            throw UploadError.httpStatus(status, body: Self.excerpt(body))
        }
    }

    func publicURL(for key: String) throws -> URL {
        try config.publicURL(for: key)
    }

    /// Builds the request for `key` and signs it. `host` and `x-amz-content-sha256` are always
    /// signed; `extraHeaders` are signed too. Visible for tests.
    func signedRequest(method: String, key: String, body: Data?,
                       extraHeaders: [(name: String, value: String)]) throws -> URLRequest {
        let url = try config.objectURL(for: key)
        let payloadHash = body.map(S3Signer.sha256Hex) ?? S3Signer.emptyPayloadHash
        var headers = extraHeaders
        headers.append((name: "host", value: config.hostHeader(for: url)))
        headers.append((name: "x-amz-content-sha256", value: payloadHash))

        let signed = S3Signer.sign(
            S3Signer.Request(method: method, path: config.objectPath(for: key), headers: headers, payloadHash: payloadHash),
            credentials: credentials, region: config.region, date: now())

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // URLSession sets Host itself from the URL; setting it here is ignored, so skip it.
        for header in headers where header.name != "host" {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        for header in signed.headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }

    private static func status(of response: URLResponse) throws -> Int {
        guard let http = response as? HTTPURLResponse else { throw UploadError.noHTTPResponse }
        return http.statusCode
    }

    private static func excerpt(_ body: Data) -> String {
        String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 63 tests in 11 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Upload/UploadProgressDelegate.swift TidyShot/Upload/S3Destination.swift TidyShotTests/S3DestinationTests.swift
git commit -m "feat: add S3Destination with signed PUT, HEAD, DELETE and upload progress"
```

---

### Task 7: UploadQueue actor (TDD with a fake destination)

**Files:**
- Create: `TidyShot/Upload/UploadQueue.swift`
- Create: `TidyShotTests/UploadQueueTests.swift`

**Interfaces:**
- Consumes: `Destination`, `UploadJob`, `UploadEvent`, `UploadError` (Task 5), `ObjectKeyNamer` (Task 3), `RetryPolicy` (Task 5).
- Produces: `actor UploadQueue` with `typealias EventHandler = @MainActor @Sendable (UploadEvent) -> Void`, `typealias Sleeper = @Sendable (Duration) async throws -> Void`, `static let maxKeyAttempts = 5`, `init(destination: any Destination, keyNamer: ObjectKeyNamer, policy: RetryPolicy = .default, sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }, events: @escaping EventHandler)`, `func enqueue(_ job: UploadJob)`, `var isIdle: Bool`.
- In the test target: `final class FakeDestination: Destination` (scripted with a `Mutex<State>`), `@MainActor final class EventLog`, `@MainActor func eventually(_ condition: () -> Bool) async throws`.

Behaviour: `enqueue` appends and starts a drain task if none is running; the drain processes jobs strictly in order. Each job reserves a key (`HEAD` until a 404, at most 5 tries), uploads, resolves the public URL and emits `.uploaded`. Retryable failures wait `policy.delay(beforeAttempt:)` and try again up to `policy.maxAttempts`; anything else emits `.failed`. Progress callbacks arrive on URLSession's queue and are forwarded in their own `Task`, so a progress event can be delivered after `.uploaded`; the history store (Task 10) ignores progress for records that are no longer uploading.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/UploadQueueTests.swift`:
```swift
import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// Scripted destination: records calls, pretends some keys exist, fails a set number of times.
nonisolated final class FakeDestination: Destination, Sendable {
    struct State: Sendable {
        var existingKeys: Set<String> = []
        var failuresRemaining = 0
        var failure: UploadError = .httpStatus(503, body: "")
        var headKeys: [String] = []
        var uploads: [(key: String, data: Data, contentType: String)] = []
    }

    let state: Mutex<State>

    init(_ state: State = State()) {
        self.state = Mutex(state)
    }

    func exists(key: String) async throws -> Bool {
        state.withLock { $0.headKeys.append(key); return $0.existingKeys.contains(key) }
    }

    func upload(_ data: Data, key: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure: UploadError? = state.withLock {
            guard $0.failuresRemaining > 0 else { return nil }
            $0.failuresRemaining -= 1
            return $0.failure
        }
        if let failure { throw failure }
        progress(0.5)
        progress(1)
        state.withLock { $0.uploads.append((key, data, contentType)) }
    }

    func delete(key: String) async throws {}

    func publicURL(for key: String) throws -> URL {
        URL(string: "https://snap.tky.io/\(key)")!
    }
}

@MainActor
final class EventLog {
    var events: [UploadEvent] = []
}

/// Polls `condition` every 10 ms for up to two seconds.
@MainActor
func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true")
}

struct UploadQueueTests {
    let data = Data("png".utf8)

    func makeQueue(destination: FakeDestination, log: EventLog) -> UploadQueue {
        UploadQueue(destination: destination,
                    keyNamer: ObjectKeyNamer(prefix: "s", length: 6, randomString: { String(repeating: "K", count: $0) }),
                    policy: .immediate,
                    sleep: { _ in },
                    events: { log.events.append($0) })
    }

    @Test func uploadsAndReportsPublicURL() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/s/KKKKKK.png")!, key: "s/KKKKKK.png")) }

        #expect(log.events.first == .started(id: id, attempt: 1))
        try await eventually { log.events.contains(.progress(id: id, fraction: 1)) }
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(uploads.first?.contentType == "image/png")
        #expect(uploads.first?.data == data)
    }

    @Test func regeneratesKeyWhenHeadReturns200() async throws {
        let counter = Mutex(0)
        let destination = FakeDestination(.init(existingKeys: ["AAAAAA.png"]))
        let log = EventLog()
        let queue = UploadQueue(
            destination: destination,
            keyNamer: ObjectKeyNamer(length: 6, randomString: { length in
                let n = counter.withLock { $0 += 1; return $0 }
                return String(repeating: n == 1 ? "A" : "B", count: length)
            }),
            policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/BBBBBB.png")!, key: "BBBBBB.png")) }

        #expect(destination.state.withLock { $0.headKeys } == ["AAAAAA.png", "BBBBBB.png"])
    }

    @Test func givesUpAfterFiveCollisions() async throws {
        let destination = FakeDestination(.init(existingKeys: ["KKKKKK.png"]))
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(length: 6, randomString: { String(repeating: "K", count: $0) }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.last == .failed(id: id, message: UploadError.keyCollisionsExhausted.localizedDescription) }

        #expect(destination.state.withLock { $0.headKeys.count } == 5)
        #expect(destination.state.withLock { $0.uploads.isEmpty })
    }

    @Test func retriesServerErrorsWithBackoffThenSucceeds() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "slow down")))
        let log = EventLog()
        let sleeps = Mutex<[Duration]>([])
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(length: 6, randomString: { String(repeating: "K", count: $0) }),
                                policy: RetryPolicy(maxAttempts: 3, baseDelay: .seconds(1), maxDelay: .seconds(30)),
                                sleep: { duration in sleeps.withLock { $0.append(duration) } },
                                events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/KKKKKK.png")!, key: "KKKKKK.png")) }

        let starts = log.events.filter { if case .started = $0 { return true } else { return false } }
        #expect(starts == [.started(id: id, attempt: 1), .started(id: id, attempt: 2), .started(id: id, attempt: 3)])
        #expect(sleeps.withLock { $0 } == [.seconds(1), .seconds(2)])
    }

    @Test func failsAfterMaxAttempts() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 10, failure: .httpStatus(500, body: "")))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.last == .failed(id: id, message: UploadError.httpStatus(500, body: "").localizedDescription) }

        #expect(log.events.filter { if case .started = $0 { return true } else { return false } }.count == 3)
    }

    @Test func doesNotRetryClientErrors() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 10, failure: .httpStatus(403, body: "SignatureDoesNotMatch")))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { if case .failed = log.events.last { return true } else { return false } }

        #expect(log.events == [.started(id: id, attempt: 1),
                               .failed(id: id, message: "Server returned HTTP 403: SignatureDoesNotMatch")])
    }

    @Test func processesJobsInOrderOneAtATime() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let first = UUID()
        let second = UUID()

        await queue.enqueue(UploadJob(id: first, data: data, contentType: "image/png", fileExtension: "png"))
        await queue.enqueue(UploadJob(id: second, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.filter { if case .uploaded = $0 { return true } else { return false } }.count == 2 }

        let ids = log.events.compactMap { event -> UUID? in
            switch event {
            case .started(let id, _), .uploaded(let id, _, _): id
            default: nil
            }
        }
        #expect(ids == [first, first, second, second])
        try await eventually { true }
        #expect(await queue.isIdle)
    }
}
```

- [ ] **Step 2: Implement the actor**

`TidyShot/Upload/UploadQueue.swift`:
```swift
import Foundation

/// Uploads jobs one at a time, in order, with HEAD-before-PUT key reservation and retry with
/// backoff. Reports progress and results through `events`, which runs on the main actor.
actor UploadQueue {
    typealias EventHandler = @MainActor @Sendable (UploadEvent) -> Void
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    static let maxKeyAttempts = 5

    private let destination: any Destination
    private let keyNamer: ObjectKeyNamer
    private let policy: RetryPolicy
    private let sleep: Sleeper
    private let events: EventHandler
    private var pending: [UploadJob] = []
    private var isDraining = false

    init(destination: any Destination,
         keyNamer: ObjectKeyNamer,
         policy: RetryPolicy = .default,
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
         events: @escaping EventHandler) {
        self.destination = destination
        self.keyNamer = keyNamer
        self.policy = policy
        self.sleep = sleep
        self.events = events
    }

    var isIdle: Bool { pending.isEmpty && !isDraining }

    func enqueue(_ job: UploadJob) {
        pending.append(job)
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            await process(job)
        }
        isDraining = false
    }

    private func process(_ job: UploadJob) async {
        var attempt = 1
        while true {
            await events(.started(id: job.id, attempt: attempt))
            do {
                let key = try await reserveKey(ext: job.fileExtension)
                let id = job.id
                let events = events
                try await destination.upload(job.data, key: key, contentType: job.contentType) { fraction in
                    Task { await events(.progress(id: id, fraction: fraction)) }
                }
                let url = try destination.publicURL(for: key)
                await events(.uploaded(id: job.id, url: url, key: key))
                return
            } catch {
                if UploadError.isRetryable(error), attempt < policy.maxAttempts {
                    attempt += 1
                    try? await sleep(policy.delay(beforeAttempt: attempt))
                    continue
                }
                await events(.failed(id: job.id, message: error.localizedDescription))
                return
            }
        }
    }

    /// Generates keys until HEAD reports one unused.
    private func reserveKey(ext: String) async throws -> String {
        for _ in 0..<Self.maxKeyAttempts {
            let key = keyNamer.makeKey(ext: ext)
            if try await destination.exists(key: key) == false {
                return key
            }
        }
        throw UploadError.keyCollisionsExhausted
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 70 tests in 12 suites passed`.

- [ ] **Step 4: Commit**

```bash
git add TidyShot/Upload/UploadQueue.swift TidyShotTests/UploadQueueTests.swift
git commit -m "feat: add UploadQueue actor with key reservation and retry"
```

---

### Task 8: Connection tester (TDD)

**Files:**
- Create: `TidyShot/Upload/ConnectionTester.swift`
- Create: `TidyShotTests/ConnectionTesterTests.swift`

**Interfaces:**
- Consumes: `S3Destination` (Task 6), `ObjectKeyNamer.join(prefix:name:)` (Task 3), `FileNamer.randomString`, `StubURLProtocol` (Task 6 tests).
- Produces: `struct ConnectionTestResult: Sendable, Equatable { enum Outcome { case readable; case notPublic(status: Int); case uploadFailed(String) }; let probeKey: String; let publicURL: URL?; let outcome: Outcome; var summary: String }` and `enum ConnectionTester { static let probeBody: Data; static func run(destination: S3Destination, session: URLSession = .shared, randomString: @Sendable (Int) -> String = FileNamer.randomString) async -> ConnectionTestResult }`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ConnectionTesterTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ConnectionTesterTests {
    let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                     keyPrefix: "p", publicURLTemplate: "https://snap.tky.io/{key}")

    func destination() -> S3Destination {
        S3Destination(config: config,
                      credentials: AWSCredentials(accessKeyID: "AKID", secretAccessKey: "secret"),
                      session: StubURLProtocol.makeSession())
    }

    @Test func readableWhenPutSucceedsAndPublicGetReturnsBody() async {
        StubURLProtocol.reset { request in
            switch request.httpMethod {
            case "PUT": (200, Data())
            case "GET": (200, ConnectionTester.probeBody)
            default: (204, Data())
            }
        }
        let result = await ConnectionTester.run(destination: destination(), session: StubURLProtocol.makeSession(),
                                                randomString: { String(repeating: "Z", count: $0) })

        #expect(result.probeKey == "p/tidyshot-probe-ZZZZZZZZ.txt")
        #expect(result.publicURL?.absoluteString == "https://snap.tky.io/p/tidyshot-probe-ZZZZZZZZ.txt")
        #expect(result.outcome == .readable)
        let sent = StubURLProtocol.requests.withLock { $0.map { "\($0.httpMethod!) \($0.url!.absoluteString)" } }
        #expect(sent == ["PUT https://snap.s3.us-east-1.amazonaws.com/p/tidyshot-probe-ZZZZZZZZ.txt",
                         "GET https://snap.tky.io/p/tidyshot-probe-ZZZZZZZZ.txt",
                         "DELETE https://snap.s3.us-east-1.amazonaws.com/p/tidyshot-probe-ZZZZZZZZ.txt"])
        #expect(StubURLProtocol.requests.withLock { $0[1].value(forHTTPHeaderField: "authorization") } == nil)
    }

    @Test func notPublicWhenGetIsForbidden() async {
        StubURLProtocol.reset { request in request.httpMethod == "GET" ? (403, Data()) : (200, Data()) }
        let result = await ConnectionTester.run(destination: destination(), session: StubURLProtocol.makeSession())
        #expect(result.outcome == .notPublic(status: 403))
        #expect(result.summary.contains("HTTP 403"))
    }

    @Test func uploadFailedWhenPutIsRejected() async {
        StubURLProtocol.reset { _ in (403, Data("AccessDenied".utf8)) }
        let result = await ConnectionTester.run(destination: destination(), session: StubURLProtocol.makeSession())
        #expect(result.outcome == .uploadFailed("Server returned HTTP 403: AccessDenied"))
        #expect(StubURLProtocol.requests.withLock { $0.count } == 1)
    }
}
```

- [ ] **Step 2: Implement the tester**

`TidyShot/Upload/ConnectionTester.swift`:
```swift
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
            try? await destination.delete(key: key)
            return ConnectionTestResult(probeKey: key, publicURL: nil, outcome: .uploadFailed(error.localizedDescription))
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
        try? await destination.delete(key: key)
        return ConnectionTestResult(probeKey: key, publicURL: publicURL, outcome: outcome)
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 73 tests in 13 suites passed`.

- [ ] **Step 4: Commit**

```bash
git add TidyShot/Upload/ConnectionTester.swift TidyShotTests/ConnectionTesterTests.swift
git commit -m "feat: add Test Connection probe (PUT, public GET, DELETE)"
```

---

### Task 9: Credentials in the Keychain (TDD)

**Files:**
- Create: `TidyShot/Upload/KeychainCredentialStore.swift`
- Create: `TidyShotTests/KeychainCredentialStoreTests.swift`

**Interfaces:**
- Consumes: `AWSCredentials` (Task 1).
- Produces: `protocol CredentialStore { func load(account: String) throws -> AWSCredentials?; func save(_ credentials: AWSCredentials, account: String) throws; func delete(account: String) throws }`, `struct KeychainError: LocalizedError { let status: OSStatus }`, `final class KeychainCredentialStore: CredentialStore` with `static let defaultAccount = "default"`, `let service: String`, `init(service: String = "io.tky.tidyshot.s3")`, and `final class InMemoryCredentialStore: CredentialStore`.

Background: generic-password items (`kSecClassGenericPassword`) in the login keychain work inside the App Sandbox with no extra entitlement; the item is keyed by `kSecAttrService` and `kSecAttrAccount` and holds the credentials JSON in `kSecValueData`. `SecItemUpdate` first, `SecItemAdd` on `errSecItemNotFound`, so saving twice updates in place. The real-keychain test uses its own service name and a unique account, and deletes the item before returning; creating and reading an item from the same process never prompts.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/KeychainCredentialStoreTests.swift`:
```swift
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
}
```

- [ ] **Step 2: Implement the stores**

`TidyShot/Upload/KeychainCredentialStore.swift`:
```swift
import Foundation
import Security

protocol CredentialStore {
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
```

- [ ] **Step 3: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 75 tests in 14 suites passed`. If `keychainStoreRoundTrips` fails with `Keychain error -34018`, something added `kSecUseDataProtectionKeychain`; remove it.

- [ ] **Step 4: Commit**

```bash
git add TidyShot/Upload/KeychainCredentialStore.swift TidyShotTests/KeychainCredentialStoreTests.swift
git commit -m "feat: store S3 credentials in the login keychain"
```

---

### Task 10: Capture history store (TDD)

**Files:**
- Create: `TidyShot/History/CaptureRecord.swift`
- Create: `TidyShot/History/HistoryStore.swift`
- Create: `TidyShotTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `struct CaptureRecord: Codable, Identifiable, Equatable, Sendable` with `enum UploadState: Codable, Equatable, Sendable { case none; case uploading(fraction: Double); case uploaded(url: URL, key: String); case failed(message: String) }`, `let id: UUID`, `let timestamp: Date`, `var fileURL: URL`, `var pixelWidth: Int`, `var pixelHeight: Int`, `var appName: String?`, `var uploadState: UploadState`, `init(id:timestamp:fileURL:pixelWidth:pixelHeight:appName:uploadState:)` (`id`, `timestamp`, `uploadState` defaulted), `var uploadedURL: URL?`, `var isFailed: Bool`, `var isUploading: Bool`.
  - `@Observable final class HistoryStore` with `static let fileName = "history.json"`, `private(set) var records: [CaptureRecord]`, `let fileURL: URL`, `init(fileURL: URL, retentionDays: Int = 30, now: @escaping () -> Date = { Date() })`, `static func defaultFileURL() throws -> URL`, `func load()`, `func add(_ record: CaptureRecord)`, `func record(id: UUID) -> CaptureRecord?`, `func update(id: UUID, _ change: (inout CaptureRecord) -> Void)`, `func setProgress(id: UUID, fraction: Double)`, `func remove(id: UUID)`, `var failedRecords: [CaptureRecord]`, `static func pruned(_:retentionDays:now:) -> [CaptureRecord]`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/HistoryStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct HistoryStoreTests {
    let now = Date(timeIntervalSince1970: 1_792_411_200)
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func store(retentionDays: Int = 30) -> HistoryStore {
        HistoryStore(fileURL: dir.appending(path: "history.json"), retentionDays: retentionDays, now: { now })
    }

    func record(age: TimeInterval = 0, state: CaptureRecord.UploadState = .none) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-age), fileURL: dir.appending(path: "shot.png"),
                      pixelWidth: 200, pixelHeight: 100, appName: "Safari", uploadState: state)
    }

    @Test func addPersistsAndReloadsNewestFirst() throws {
        let first = store()
        let older = record(age: 60)
        let newer = record(age: 0, state: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"))
        first.add(older)
        first.add(newer)

        let second = store()
        second.load()
        #expect(second.records == [newer, older])
        #expect(second.record(id: newer.id)?.uploadedURL?.absoluteString == "https://snap.tky.io/a.png")
    }

    @Test func updateChangesStateAndPersists() {
        let first = store()
        let item = record()
        first.add(item)
        first.update(id: item.id) { $0.uploadState = .failed(message: "boom") }

        let second = store()
        second.load()
        #expect(second.records.first?.uploadState == .failed(message: "boom"))
        #expect(second.failedRecords.map(\.id) == [item.id])
    }

    @Test func setProgressDoesNotWriteToDisk() {
        let first = store()
        let item = record(state: .uploading(fraction: 0))
        first.add(item)
        first.setProgress(id: item.id, fraction: 0.5)
        #expect(first.record(id: item.id)?.uploadState == .uploading(fraction: 0.5))

        let second = store()
        second.load()
        #expect(second.records.first?.uploadState == .failed(message: "Upload was interrupted."))
    }

    @Test func lateProgressDoesNotReopenAFinishedUpload() {
        let first = store()
        let item = record(state: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"))
        first.add(item)
        first.setProgress(id: item.id, fraction: 0.9)
        #expect(first.record(id: item.id)?.uploadedURL != nil)
    }

    @Test func prunesRecordsOlderThanRetention() {
        let first = store(retentionDays: 30)
        first.add(record(age: 31 * 86_400))
        first.add(record(age: 29 * 86_400))
        #expect(first.records.count == 1)

        let second = store(retentionDays: 7)
        second.load()
        #expect(second.records.isEmpty)
    }

    @Test func missingOrCorruptFileLoadsEmpty() throws {
        let fresh = store()
        fresh.load()
        #expect(fresh.records.isEmpty)

        try Data("not json".utf8).write(to: dir.appending(path: "history.json"))
        let corrupt = store()
        corrupt.load()
        #expect(corrupt.records.isEmpty)
    }

    @Test func removeDeletesRecord() {
        let first = store()
        let item = record()
        first.add(item)
        first.remove(id: item.id)
        #expect(first.records.isEmpty)
    }
}
```

- [ ] **Step 2: Write the record type**

`TidyShot/History/CaptureRecord.swift`:
```swift
import Foundation

/// One capture: where its PNG is, how big it is, and how its upload went.
nonisolated struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    enum UploadState: Codable, Equatable, Sendable {
        case none
        case uploading(fraction: Double)
        case uploaded(url: URL, key: String)
        case failed(message: String)
    }

    let id: UUID
    let timestamp: Date
    var fileURL: URL
    var pixelWidth: Int
    var pixelHeight: Int
    var appName: String?
    var uploadState: UploadState

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL, pixelWidth: Int, pixelHeight: Int,
         appName: String?, uploadState: UploadState = .none) {
        self.id = id
        self.timestamp = timestamp
        self.fileURL = fileURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.appName = appName
        self.uploadState = uploadState
    }

    var uploadedURL: URL? {
        if case .uploaded(let url, _) = uploadState { return url }
        return nil
    }

    var isFailed: Bool {
        if case .failed = uploadState { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = uploadState { return true }
        return false
    }
}
```

- [ ] **Step 3: Implement the store**

`TidyShot/History/HistoryStore.swift`:
```swift
import Foundation
import Observation

/// Capture records, newest first, persisted as JSON. Records older than `retentionDays` are
/// dropped on load and on add; their files on disk are left alone.
@Observable
final class HistoryStore {
    static let fileName = "history.json"

    private(set) var records: [CaptureRecord] = []

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let retentionDays: Int
    @ObservationIgnored private let now: () -> Date

    init(fileURL: URL, retentionDays: Int = 30, now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.retentionDays = retentionDays
        self.now = now
    }

    /// `~/Library/Application Support/TidyShot/history.json` (inside the sandbox container).
    static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appending(path: "TidyShot", directoryHint: .isDirectory).appending(path: fileName)
    }

    /// Reads the file. A missing or unreadable file yields an empty list. Records still marked
    /// `uploading` were interrupted by a quit or crash and become `failed` so they can be retried.
    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            records = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded = (try? decoder.decode([CaptureRecord].self, from: data)) ?? []
        for index in loaded.indices where loaded[index].isUploading {
            loaded[index].uploadState = .failed(message: "Upload was interrupted.")
        }
        records = Self.pruned(loaded, retentionDays: retentionDays, now: now())
        records.sort { $0.timestamp > $1.timestamp }
    }

    func add(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        records = Self.pruned(records, retentionDays: retentionDays, now: now())
        save()
    }

    func record(id: UUID) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    /// Applies `change` to the record and writes the file.
    func update(id: UUID, _ change: (inout CaptureRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        save()
    }

    /// In-memory only; progress arrives often and is not worth a disk write each time. Ignored
    /// unless the record is still uploading, because a late progress callback can arrive after
    /// the upload has already finished.
    func setProgress(id: UUID, fraction: Double) {
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].isUploading else { return }
        records[index].uploadState = .uploading(fraction: fraction)
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    var failedRecords: [CaptureRecord] {
        records.filter(\.isFailed)
    }

    static func pruned(_ records: [CaptureRecord], retentionDays: Int, now: Date) -> [CaptureRecord] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return records.filter { $0.timestamp >= cutoff }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(records)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("History save failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 82 tests in 15 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/History TidyShotTests/HistoryStoreTests.swift
git commit -m "feat: add capture history store with JSON persistence and pruning"
```

---

### Task 11: Settings, pasteboard, notifier, and save-folder read support

**Files:**
- Modify: `TidyShot/Settings/AppSettings.swift` (full replacement below)
- Create: `TidyShotTests/AppSettingsTests.swift`
- Modify: `TidyShot/Output/Pasteboard.swift` (full replacement below)
- Modify: `TidyShot/Output/Notifier.swift` (full replacement below)
- Modify: `TidyShot/Output/SaveLocation.swift` (one method added)
- Modify: `TidyShot/Settings/GeneralSettingsView.swift` (full replacement below)

**Interfaces:**
- Consumes: `S3DestinationConfig` (Task 4), `OverlayCorner` (created in Step 1 of this task; Task 12 completes that file).
- Produces:
  - `enum AfterCaptureAction: String, CaseIterable, Identifiable { case upload, save; var title: String }`
  - On `AppSettings`: `var afterCaptureAction: AfterCaptureAction` (default `.upload`), `var alsoCopyImageWhenUploading: Bool` (false), `var showOverlay: Bool` (true), `var overlayCorner: OverlayCorner` (`.bottomRight`), `var overlayAutoCloseSeconds: Double` (5), `var historyRetentionDays: Int` (30), `var s3Config: S3DestinationConfig?` (nil, JSON in UserDefaults). Existing properties unchanged.
  - `Pasteboard.copy(url: URL)`
  - `Notifier.notifyUploaded(url: URL)`; clicking that notification opens the URL.
  - `SaveLocation.read(contentsOf fileURL: URL) throws -> Data`

- [ ] **Step 1: Write the overlay corner enum first**

`AppSettings` stores an `OverlayCorner`, which belongs to Task 12's `OverlayGeometry.swift`. Create that file now with the enum only (Task 12 appends `OverlayGeometry` to it):

`TidyShot/Overlay/OverlayGeometry.swift`:
```swift
import CoreGraphics

nonisolated enum OverlayCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}
```

- [ ] **Step 2: Write the failing settings tests**

`TidyShotTests/AppSettingsTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct AppSettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func phase2DefaultsAreUploadWithURLOnly() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.afterCaptureAction == .upload)
        #expect(settings.alsoCopyImageWhenUploading == false)
        #expect(settings.showOverlay)
        #expect(settings.overlayCorner == .bottomRight)
        #expect(settings.overlayAutoCloseSeconds == 5)
        #expect(settings.historyRetentionDays == 30)
        #expect(settings.s3Config == nil)
    }

    @Test func s3ConfigRoundTripsThroughDefaults() {
        let defaults = freshDefaults()
        let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                         keyPrefix: "p", usePathStyle: true, sendPublicReadACL: true,
                                         publicURLTemplate: "https://snap.tky.io/{key}", keyLength: 8)
        let first = AppSettings(defaults: defaults)
        first.s3Config = config
        first.afterCaptureAction = .save
        first.overlayCorner = .topLeft

        let second = AppSettings(defaults: defaults)
        #expect(second.s3Config == config)
        #expect(second.afterCaptureAction == .save)
        #expect(second.overlayCorner == .topLeft)

        second.s3Config = nil
        #expect(AppSettings(defaults: defaults).s3Config == nil)
    }
}
```

- [ ] **Step 3: Replace AppSettings**

`TidyShot/Settings/AppSettings.swift`:
```swift
import Foundation
import Observation

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    /// Save the file, upload it, and put the URL on the clipboard when the upload finishes.
    case upload
    /// Save the file and copy the image (Phase 1 behaviour).
    case save

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: "Upload and copy URL"
        case .save: "Save and copy image"
        }
    }
}

/// User preferences, persisted in UserDefaults. Credentials are never stored here.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let showsCursor = "showsCursor"
        static let copyImageToClipboard = "copyImageToClipboard"
        static let showNotification = "showNotification"
        static let playSound = "playSound"
        static let fileNameTemplate = "fileNameTemplate"
        static let counter = "captureCounter"
        static let afterCaptureAction = "afterCaptureAction"
        static let alsoCopyImageWhenUploading = "alsoCopyImageWhenUploading"
        static let showOverlay = "showOverlay"
        static let overlayCorner = "overlayCorner"
        static let overlayAutoCloseSeconds = "overlayAutoCloseSeconds"
        static let historyRetentionDays = "historyRetentionDays"
        static let s3Config = "s3DestinationConfig"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Keys.showsCursor) } }
    var copyImageToClipboard: Bool { didSet { defaults.set(copyImageToClipboard, forKey: Keys.copyImageToClipboard) } }
    var showNotification: Bool { didSet { defaults.set(showNotification, forKey: Keys.showNotification) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Keys.playSound) } }
    var fileNameTemplate: String { didSet { defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate) } }
    var afterCaptureAction: AfterCaptureAction { didSet { defaults.set(afterCaptureAction.rawValue, forKey: Keys.afterCaptureAction) } }
    var alsoCopyImageWhenUploading: Bool { didSet { defaults.set(alsoCopyImageWhenUploading, forKey: Keys.alsoCopyImageWhenUploading) } }
    var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Keys.showOverlay) } }
    var overlayCorner: OverlayCorner { didSet { defaults.set(overlayCorner.rawValue, forKey: Keys.overlayCorner) } }
    var overlayAutoCloseSeconds: Double { didSet { defaults.set(overlayAutoCloseSeconds, forKey: Keys.overlayAutoCloseSeconds) } }
    var historyRetentionDays: Int { didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) } }
    /// Nil until the Upload tab has been saved once. Stored as JSON.
    var s3Config: S3DestinationConfig? {
        didSet { defaults.set(s3Config.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.s3Config) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.showsCursor: false,
            Keys.copyImageToClipboard: true,
            Keys.showNotification: true,
            Keys.playSound: true,
            Keys.fileNameTemplate: FileNamer.defaultTemplate,
            Keys.afterCaptureAction: AfterCaptureAction.upload.rawValue,
            Keys.alsoCopyImageWhenUploading: false,
            Keys.showOverlay: true,
            Keys.overlayCorner: OverlayCorner.bottomRight.rawValue,
            Keys.overlayAutoCloseSeconds: 5.0,
            Keys.historyRetentionDays: 30,
        ])
        showsCursor = defaults.bool(forKey: Keys.showsCursor)
        copyImageToClipboard = defaults.bool(forKey: Keys.copyImageToClipboard)
        showNotification = defaults.bool(forKey: Keys.showNotification)
        playSound = defaults.bool(forKey: Keys.playSound)
        fileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? FileNamer.defaultTemplate
        afterCaptureAction = AfterCaptureAction(rawValue: defaults.string(forKey: Keys.afterCaptureAction) ?? "") ?? .upload
        alsoCopyImageWhenUploading = defaults.bool(forKey: Keys.alsoCopyImageWhenUploading)
        showOverlay = defaults.bool(forKey: Keys.showOverlay)
        overlayCorner = OverlayCorner(rawValue: defaults.string(forKey: Keys.overlayCorner) ?? "") ?? .bottomRight
        overlayAutoCloseSeconds = defaults.double(forKey: Keys.overlayAutoCloseSeconds)
        historyRetentionDays = defaults.integer(forKey: Keys.historyRetentionDays)
        s3Config = defaults.data(forKey: Keys.s3Config).flatMap { try? JSONDecoder().decode(S3DestinationConfig.self, from: $0) }
    }

    /// Increments and returns the persistent capture counter used by the {counter} token.
    func nextCounter() -> Int {
        let next = defaults.integer(forKey: Keys.counter) + 1
        defaults.set(next, forKey: Keys.counter)
        return next
    }
}
```

- [ ] **Step 4: Add URL copying to the pasteboard**

`TidyShot/Output/Pasteboard.swift`:
```swift
import AppKit

enum Pasteboard {
    /// Puts the image on the general pasteboard as PNG and TIFF. The TIFF rep's size is set in
    /// points so Retina images paste at their on-screen size.
    static func copy(image: CGImage, pngData: Data, scale: CGFloat) {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)

        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Replaces the pasteboard contents with `url`, as plain text and as a URL.
    static func copy(url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
```

- [ ] **Step 5: Add the uploaded notification**

`TidyShot/Output/Notifier.swift`:
```swift
import AppKit
import UserNotifications

/// Posts "saved", "uploaded" and "failed" notifications. Clicking a saved notification reveals
/// the file in Finder; clicking an uploaded notification opens the URL.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read from the nonisolated delegate callbacks, so they must not be MainActor-isolated.
    nonisolated private static let pathKey = "path"
    nonisolated private static let urlKey = "url"
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Notification authorization failed: \(error.localizedDescription)") }
        }
    }

    func notifySaved(fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot saved"
        content.body = fileURL.lastPathComponent
        content.userInfo = [Self.pathKey: fileURL.path]
        post(content)
    }

    func notifyUploaded(url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Uploaded, URL copied"
        content.body = url.absoluteString
        content.userInfo = [Self.urlKey: url.absoluteString]
        post(content)
    }

    func notifyError(_ message: String, title: String = "Capture failed") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { NSLog("Notification failed: \(error.localizedDescription)") }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let path = userInfo[Self.pathKey] as? String {
            let url = URL(fileURLWithPath: path)
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else if let string = userInfo[Self.urlKey] as? String, let url = URL(string: string) {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }
}
```

- [ ] **Step 6: Add a scoped read to SaveLocation**

In `TidyShot/Output/SaveLocation.swift`, insert this method directly above `private func withAccess<T>(...)`:

```swift
    /// Reads a file inside the save folder (for upload retries), holding security-scoped access.
    func read(contentsOf fileURL: URL) throws -> Data {
        guard let currentURL else { throw CocoaError(.fileNoSuchFile) }
        return try withAccess(to: currentURL) {
            try Data(contentsOf: fileURL)
        }
    }
```

- [ ] **Step 7: Update the General tab**

`TidyShot/Settings/GeneralSettingsView.swift`:
```swift
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    private let saveLocation = AppCoordinator.shared.saveLocation

    var body: some View {
        Form {
            LabeledContent("Save to") {
                HStack {
                    Text(saveLocation.currentURL?.path(percentEncoded: false) ?? "Not set")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") {
                        Task { _ = await saveLocation.chooseFolder() }
                    }
                }
            }
            TextField("File name", text: $settings.fileNameTemplate)
            Text("Tokens: {date} {time} {datetime} {app} {counter} {random} {random:8}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("After capture", selection: $settings.afterCaptureAction) {
                ForEach(AfterCaptureAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            if settings.afterCaptureAction == .upload {
                Toggle("Also copy image (the URL replaces it when the upload finishes)", isOn: $settings.alsoCopyImageWhenUploading)
            } else {
                Toggle("Copy image to clipboard", isOn: $settings.copyImageToClipboard)
            }
            Toggle("Show notification", isOn: $settings.showNotification)
            Toggle("Play sound", isOn: $settings.playSound)
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 84 tests in 16 suites passed`.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Overlay/OverlayGeometry.swift TidyShot/Settings/AppSettings.swift TidyShotTests/AppSettingsTests.swift TidyShot/Output/Pasteboard.swift TidyShot/Output/Notifier.swift TidyShot/Output/SaveLocation.swift TidyShot/Settings/GeneralSettingsView.swift
git commit -m "feat: add after-capture action, overlay and history settings, URL clipboard and notification"
```

---

### Task 12: Quick Access overlay (TDD for geometry, then the panel)

**Files:**
- Modify: `TidyShot/Overlay/OverlayGeometry.swift` (add `OverlayGeometry`)
- Create: `TidyShotTests/OverlayGeometryTests.swift`
- Create: `TidyShot/Overlay/QuickAccessModel.swift`
- Create: `TidyShot/Overlay/QuickAccessView.swift`
- Create: `TidyShot/Overlay/QuickAccessPanel.swift`
- Create: `TidyShot/Overlay/QuickAccessController.swift`

**Interfaces:**
- Consumes: `CaptureRecord` (Task 10), `OverlayCorner` (Task 11).
- Produces:
  - `enum OverlayGeometry { static func frame(size: CGSize, corner: OverlayCorner, in visibleFrame: CGRect, margin: CGFloat = 16) -> CGRect }`
  - `@Observable final class QuickAccessModel` with `var record: CaptureRecord`, `var thumbnail: NSImage?`, `var isHovered: Bool`, closures `onCopy`, `onRetry`, `onReveal`, `onClose: () -> Void`, `init(record:thumbnail:)`, `var isSettled: Bool`.
  - `struct QuickAccessView: View { static let size: CGSize; let model: QuickAccessModel }`
  - `final class QuickAccessPanel: NSPanel { init(model: QuickAccessModel) }`
  - `final class QuickAccessController` with `struct Actions { var copy: (UUID) -> Void; var retry: (UUID) -> Void; var reveal: (UUID) -> Void }`, `func show(record: CaptureRecord, thumbnail: NSImage?, corner: OverlayCorner, autoCloseSeconds: Double, actions: Actions)`, `func update(record: CaptureRecord)`, `func close()`.

- [ ] **Step 1: Write the failing geometry tests**

`TidyShotTests/OverlayGeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct OverlayGeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let size = CGSize(width: 320, height: 96)

    @Test func bottomRightDefault() {
        let frame = OverlayGeometry.frame(size: size, corner: .bottomRight, in: screen)
        #expect(frame == CGRect(x: 1440 - 16 - 320, y: 25 + 16, width: 320, height: 96))
    }

    @Test func topLeft() {
        let frame = OverlayGeometry.frame(size: size, corner: .topLeft, in: screen)
        #expect(frame == CGRect(x: 16, y: 900 - 16 - 96, width: 320, height: 96))
    }

    @Test func secondDisplayOffsetIsHonoured() {
        let second = CGRect(x: 1440, y: 200, width: 1920, height: 1055)
        let frame = OverlayGeometry.frame(size: size, corner: .bottomLeft, in: second, margin: 20)
        #expect(frame.origin == CGPoint(x: 1460, y: 220))
    }
}
```

- [ ] **Step 2: Complete OverlayGeometry.swift**

Replace the whole file (the enum from Task 11 plus the geometry):

`TidyShot/Overlay/OverlayGeometry.swift`:
```swift
import CoreGraphics

nonisolated enum OverlayCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Where the Quick Access panel goes. `visibleFrame` is an AppKit screen rect (origin bottom-left).
nonisolated enum OverlayGeometry {
    static func frame(size: CGSize, corner: OverlayCorner, in visibleFrame: CGRect, margin: CGFloat = 16) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft, .bottomLeft:
            x = visibleFrame.minX + margin
        case .topRight, .bottomRight:
            x = visibleFrame.maxX - margin - size.width
        }
        switch corner {
        case .topLeft, .topRight:
            y = visibleFrame.maxY - margin - size.height
        case .bottomLeft, .bottomRight:
            y = visibleFrame.minY + margin
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run|✘"
```
Expected: `Test run with 87 tests in 17 suites passed`.

- [ ] **Step 4: Write the model**

`TidyShot/Overlay/QuickAccessModel.swift`:
```swift
import AppKit
import Observation

/// State behind the Quick Access panel: the capture it shows and the actions its buttons run.
@Observable
final class QuickAccessModel {
    var record: CaptureRecord
    var thumbnail: NSImage?
    var isHovered = false

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onRetry: () -> Void = {}
    @ObservationIgnored var onReveal: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}

    init(record: CaptureRecord, thumbnail: NSImage?) {
        self.record = record
        self.thumbnail = thumbnail
    }

    /// True once the upload has finished (or there was none), which starts the auto-close timer.
    var isSettled: Bool {
        !record.isUploading
    }
}
```

- [ ] **Step 5: Write the view**

`TidyShot/Overlay/QuickAccessView.swift`:
```swift
import SwiftUI

/// Thumbnail, upload status, and a copy or retry button. Hosted in `QuickAccessPanel`.
struct QuickAccessView: View {
    static let size = CGSize(width: 340, height: 104)

    let model: QuickAccessModel

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .onHover { model.isHovered = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 72)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { model.onReveal() }
        .help("Reveal in Finder")
    }

    @ViewBuilder
    private var status: some View {
        switch model.record.uploadState {
        case .uploading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Uploading…")
            }
            Text(model.record.fileURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .uploaded(let url, _):
            Label("URL copied", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(url.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button("Copy URL") { model.onCopy() }
                .controlSize(.small)
        case .failed(let message):
            Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Retry") { model.onRetry() }
                .controlSize(.small)
        case .none:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(model.record.fileURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
```

- [ ] **Step 6: Write the panel**

`TidyShot/Overlay/QuickAccessPanel.swift`:
```swift
import AppKit
import SwiftUI

/// Floating, non-activating panel in a screen corner. Visible on every Space, including over
/// full-screen apps, and never steals focus from the app the user is working in.
final class QuickAccessPanel: NSPanel {
    init(model: QuickAccessModel) {
        super.init(contentRect: CGRect(origin: .zero, size: QuickAccessView.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        contentView = NSHostingView(rootView: QuickAccessView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 7: Write the controller**

`TidyShot/Overlay/QuickAccessController.swift`:
```swift
import AppKit

/// Shows one Quick Access panel for the latest capture, updates it as the upload progresses,
/// and closes it a few seconds after the upload settles (unless the mouse is over it).
final class QuickAccessController {
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
    }

    private var panel: QuickAccessPanel?
    private var model: QuickAccessModel?
    private var closeTask: Task<Void, Never>?
    private var autoCloseSeconds: Double = 5

    func show(record: CaptureRecord, thumbnail: NSImage?, corner: OverlayCorner, autoCloseSeconds: Double, actions: Actions) {
        close()
        let model = QuickAccessModel(record: record, thumbnail: thumbnail)
        model.onCopy = { actions.copy(record.id) }
        model.onRetry = { actions.retry(record.id) }
        model.onReveal = { actions.reveal(record.id) }
        model.onClose = { [weak self] in self?.close() }
        self.model = model
        self.autoCloseSeconds = autoCloseSeconds

        let panel = QuickAccessPanel(model: model)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(OverlayGeometry.frame(size: QuickAccessView.size, corner: corner, in: screen.visibleFrame), display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        if model.isSettled {
            scheduleClose()
        }
    }

    /// Pushes a new record state into the visible panel, if it shows that record.
    func update(record: CaptureRecord) {
        guard let model, model.record.id == record.id else { return }
        model.record = record
        if model.isSettled {
            scheduleClose()
        }
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// Waits `autoCloseSeconds`, then keeps waiting while the mouse is over the panel.
    private func scheduleClose() {
        closeTask?.cancel()
        let seconds = autoCloseSeconds
        guard seconds > 0 else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            while !Task.isCancelled, self?.model?.isHovered == true {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
```

- [ ] **Step 8: Build**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && echo BUILD_OK
```
Expected: `BUILD_OK` with no warnings mentioning `Overlay/`.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Overlay TidyShotTests/OverlayGeometryTests.swift
git commit -m "feat: add Quick Access overlay panel with progress, URL, copy and retry"
```

---

### Task 13: Wire upload, history, and overlay into AppCoordinator and the menu

**Files:**
- Modify: `TidyShot/App/AppCoordinator.swift` (full replacement below)
- Modify: `TidyShot/App/MenuContent.swift` (full replacement below)
- Modify: `TidyShot/App/TidyShotApp.swift` (full replacement below)

**Interfaces:**
- Consumes: everything from Tasks 1 to 12, plus Phase 1's `CaptureEngine`, `SelectionController`, `SaveLocation`, `ImageEncoder`, `FileNamer`, `Pasteboard`, `Notifier`, `SoundPlayer`, `ScreenCapturePermission`, `PermissionWindowController`, `Geometry`.
- Produces on `AppCoordinator`: `let history: HistoryStore`, `let credentialStore: any CredentialStore`, `private(set) var uploadingIDs: Set<UUID>`, `var isUploading: Bool`, `func makeDestination() -> S3Destination?`, `func destinationDidChange()`, `func retryUpload(recordID: UUID)`, `func retryFailedUploads()`, `func copyURL(recordID: UUID)`, `func reveal(recordID: UUID)`, `func historyItemSelected(_ recordID: UUID)`. `save(_:appName:)` keeps its signature.
- Produces on `MenuContent`: `static func title(for record: CaptureRecord) -> String`.

Flow of `save`: encode PNG; decide `willUpload` (action is upload and a destination exists); copy the image now only if the mode's toggle says so; if upload was wanted but not configured, notify once; write the file (any failure keeps the image on the clipboard and returns, as in Phase 1); play the sound; add a `CaptureRecord`; show the overlay; then either enqueue the upload or post the Phase 1 "saved" notification. Upload events update history and the overlay; `.uploaded` also copies the URL and notifies; `.failed` keeps the record with a retry.

- [ ] **Step 1: Replace AppCoordinator**

`TidyShot/App/AppCoordinator.swift`:
```swift
import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, output, upload, and history together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    let history: HistoryStore
    let credentialStore: any CredentialStore = KeychainCredentialStore()
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    private let overlay = QuickAccessController()
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
    @ObservationIgnored private var queue: UploadQueue?

    private(set) var isCapturing = false
    private(set) var lastCaptureURL: URL?
    /// Records with an upload in flight; drives the menu bar icon.
    private(set) var uploadingIDs: Set<UUID> = []

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }
    var isUploading: Bool { !uploadingIDs.isEmpty }

    init() {
        let url = (try? HistoryStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: HistoryStore.fileName)
        history = HistoryStore(fileURL: url, retentionDays: AppSettings.shared.historyRetentionDays)
    }

    func start() {
        notifier.setUp()
        history.load()
        registerShortcuts()
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureFullscreen) { [weak self] in
            Task { await self?.captureFullscreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            Task { await self?.captureArea() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { await self?.captureWindow() }
        }
    }

    func captureFullscreen() async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result, appName: frontApp)
        }
    }

    func captureArea() async {
        await runSelection(mode: .area)
    }

    func captureWindow() async {
        await runSelection(mode: .window)
    }

    /// Show the overlay, capture with the overlay excluded, dismiss, then save.
    private func runSelection(mode: SelectionMode) async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: mode, content: content) else { return }

            let result: CaptureResult?
            let appName: String?
            switch selection {
            case .area(let rect, let display):
                let overlays = await selector.overlayWindows()
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
                appName = frontApp
            case .window(let window):
                result = await capture(.window(window))
                appName = window.owningApplication?.applicationName
            }
            selector.dismiss()

            if let result {
                await save(result, appName: appName)
            }
        }
    }

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: settings.showsCursor), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    // MARK: Save and upload

    /// Encode, copy to clipboard (image now, or URL later), save, record in history, show the
    /// overlay, and start the upload. The local file is always written before the upload starts;
    /// if it cannot be written the image stays on the clipboard, so a capture is never dropped.
    func save(_ result: CaptureResult, appName: String?) async {
        let png: Data
        do {
            png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return
        }

        let wantsUpload = settings.afterCaptureAction == .upload
        let willUpload = wantsUpload && makeDestination() != nil
        let copyImageNow = willUpload ? settings.alsoCopyImageWhenUploading : settings.copyImageToClipboard
        if copyImageNow {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }
        if wantsUpload, !willUpload {
            notifier.notifyError("Set up a destination in Settings > Upload. The screenshot was saved.", title: "Upload not configured")
        }

        guard let url = await writeFile(png, result: result, appName: appName, alreadyOnClipboard: copyImageNow) else { return }
        if settings.playSound {
            SoundPlayer.playShutter()
        }
        lastCaptureURL = url

        let record = CaptureRecord(fileURL: url, pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, uploadState: willUpload ? .uploading(fraction: 0) : .none)
        history.add(record)
        showOverlay(for: record, image: result.image, scale: result.scale)

        if willUpload {
            startUpload(recordID: record.id, data: png)
        } else if settings.showNotification {
            notifier.notifySaved(fileURL: url)
        }
    }

    /// Writes the PNG into the save folder. Returns nil after notifying, with the image left on
    /// the clipboard, when there is no folder or the write fails.
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, alreadyOnClipboard: Bool) async -> URL? {
        func keepOnClipboard() {
            if !alreadyOnClipboard {
                Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
            }
        }
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard()
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: counter)
            return try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            keepOnClipboard()
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat) {
        guard settings.showOverlay else { return }
        let thumbnail = image.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, corner: settings.overlayCorner,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds,
                     actions: QuickAccessController.Actions(
                        copy: { [weak self] id in self?.copyURL(recordID: id) },
                        retry: { [weak self] id in self?.retryUpload(recordID: id) },
                        reveal: { [weak self] id in self?.reveal(recordID: id) }))
    }

    /// The configured destination, or nil when the Upload tab is incomplete or has no credentials.
    func makeDestination() -> S3Destination? {
        guard let config = settings.s3Config, config.isComplete,
              let credentials = try? credentialStore.load(account: KeychainCredentialStore.defaultAccount),
              !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            return nil
        }
        return S3Destination(config: config, credentials: credentials)
    }

    /// Called by the Upload settings tab after saving, so the next upload uses the new settings.
    func destinationDidChange() {
        queue = nil
    }

    private func startUpload(recordID: UUID, data: Data) {
        guard let destination = makeDestination() else {
            markFailed(recordID, message: UploadError.notConfigured.localizedDescription)
            return
        }
        if queue == nil {
            let config = destination.config
            queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(prefix: config.keyPrefix, length: config.keyLength),
                                events: { [weak self] event in self?.handle(event) })
        }
        guard let queue else { return }
        uploadingIDs.insert(recordID)
        history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
        if let record = history.record(id: recordID) {
            overlay.update(record: record)
        }
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png")
        Task { await queue.enqueue(job) }
    }

    /// Re-reads the file from the save folder and uploads it again.
    func retryUpload(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        do {
            let data = try saveLocation.read(contentsOf: record.fileURL)
            startUpload(recordID: recordID, data: data)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL.lastPathComponent).localizedDescription)
        }
    }

    func retryFailedUploads() {
        for record in history.failedRecords {
            retryUpload(recordID: record.id)
        }
    }

    func copyURL(recordID: UUID) {
        guard let url = history.record(id: recordID)?.uploadedURL else { return }
        Pasteboard.copy(url: url)
    }

    func reveal(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
    }

    /// Menu action for a history row: copy the URL, retry a failed upload, or reveal the file.
    func historyItemSelected(_ recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        switch record.uploadState {
        case .uploaded: copyURL(recordID: recordID)
        case .failed: retryUpload(recordID: recordID)
        case .none, .uploading: reveal(recordID: recordID)
        }
    }

    private func markFailed(_ recordID: UUID, message: String) {
        uploadingIDs.remove(recordID)
        history.update(id: recordID) { $0.uploadState = .failed(message: message) }
        if let record = history.record(id: recordID) {
            overlay.update(record: record)
        }
        notifier.notifyError(message, title: "Upload failed")
    }

    private func handle(_ event: UploadEvent) {
        switch event {
        case .started(let id, let attempt):
            if attempt > 1 {
                NSLog("Upload retry \(attempt) for \(id)")
            }
        case .progress(let id, let fraction):
            history.setProgress(id: id, fraction: fraction)
            if let record = history.record(id: id) {
                overlay.update(record: record)
            }
        case .uploaded(let id, let url, let key):
            uploadingIDs.remove(id)
            history.update(id: id) { $0.uploadState = .uploaded(url: url, key: key) }
            Pasteboard.copy(url: url)
            if settings.showNotification {
                notifier.notifyUploaded(url: url)
            }
            if let record = history.record(id: id) {
                overlay.update(record: record)
            }
        case .failed(let id, let message):
            markFailed(id, message: message)
        }
    }

    // MARK: Helpers

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            if ScreenCapturePermission.isGranted {
                notifier.notifyError("Could not list screens and windows: \(error.localizedDescription)")
            } else {
                permissionWindow.show()
            }
            return nil
        }
    }

    private func withCaptureLock(_ body: () async -> Void) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        await body()
    }

    /// The SCDisplay under an AppKit-global point, falling back to the first display.
    static func display(under appKitPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}
```

- [ ] **Step 2: Add the history submenu**

`TidyShot/App/MenuContent.swift`:
```swift
import KeyboardShortcuts
import SwiftUI

struct MenuContent: View {
    private let coordinator = AppCoordinator.shared

    var body: some View {
        if !coordinator.permissionGranted {
            Button("Screen Recording permission needed…") {
                coordinator.showPermissionWindow()
            }
            Divider()
        }
        Button(menuTitle("Capture Area", .captureArea)) {
            Task { await coordinator.captureArea() }
        }
        .disabled(coordinator.isCapturing)
        Button(menuTitle("Capture Window", .captureWindow)) {
            Task { await coordinator.captureWindow() }
        }
        .disabled(coordinator.isCapturing)
        Button(menuTitle("Capture Fullscreen", .captureFullscreen)) {
            Task { await coordinator.captureFullscreen() }
        }
        .disabled(coordinator.isCapturing)
        Divider()
        historyMenu
        Button("Reveal Last Capture") {
            coordinator.revealLastCapture()
        }
        .disabled(coordinator.lastCaptureURL == nil)
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// The ten newest captures. Uploaded: copies the URL. Failed: retries. Otherwise: reveals the file.
    @ViewBuilder
    private var historyMenu: some View {
        let recent = Array(coordinator.history.records.prefix(10))
        Menu("Recent Captures") {
            if recent.isEmpty {
                Text("No captures yet")
            }
            ForEach(recent) { record in
                Button(Self.title(for: record)) {
                    coordinator.historyItemSelected(record.id)
                }
            }
            if !coordinator.history.failedRecords.isEmpty {
                Divider()
                Button("Retry Failed Uploads") {
                    coordinator.retryFailedUploads()
                }
            }
        }
        .disabled(recent.isEmpty)
    }

    static func title(for record: CaptureRecord) -> String {
        let time = record.timestamp.formatted(date: .omitted, time: .standard)
        let marker: String
        switch record.uploadState {
        case .none: marker = "💾"
        case .uploading: marker = "⬆️"
        case .uploaded: marker = "🔗"
        case .failed: marker = "⚠️"
        }
        let name = record.uploadedURL?.lastPathComponent ?? record.fileURL.lastPathComponent
        return "\(marker) \(time)  \(name)"
    }

    private func menuTitle(_ title: String, _ name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return title }
        return "\(title)  \(shortcut)"
    }
}
```

- [ ] **Step 3: Switch the menu bar icon while uploading**

`TidyShot/App/TidyShotApp.swift`:
```swift
import SwiftUI

@main
struct TidyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra("TidyShot", systemImage: coordinator.isUploading ? "arrow.up.circle" : "camera.viewfinder") {
            MenuContent()
        }
        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 4: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 87 tests in 17 suites passed`.

- [ ] **Step 5: Smoke-run the save path with upload unconfigured**

Run:
```bash
open .build/Build/Products/Debug/TidyShot.app
```
Press `⌃⇧3`. Expected: the screenshot is saved as before, a notification titled "Upload not configured" appears, the Quick Access panel shows the thumbnail with "Saved" in the bottom-right corner and closes after 5 seconds, and the menu's "Recent Captures" submenu lists the capture with a 💾 marker. Quit the app.

- [ ] **Step 6: Commit**

```bash
git add TidyShot/App/AppCoordinator.swift TidyShot/App/MenuContent.swift TidyShot/App/TidyShotApp.swift
git commit -m "feat: upload after capture, copy URL, history menu, and overlay wiring"
```

---

### Task 14: Upload and Overlay settings tabs, docs, and the end-to-end check

**Files:**
- Create: `TidyShot/Settings/UploadSettingsView.swift`
- Create: `TidyShot/Settings/OverlaySettingsView.swift`
- Modify: `TidyShot/Settings/SettingsView.swift` (full replacement below)
- Create: `docs/testing/phase-2-manual-checklist.md`
- Modify: `README.md` (one section added)

**Interfaces:**
- Consumes: `AppCoordinator.credentialStore`, `makeDestination()`, `destinationDidChange()`, `settings` (Task 13), `S3DestinationConfig` (Task 4), `ConnectionTester` (Task 8), `ObjectKeyNamer` (Task 3), `OverlayCorner` (Task 11).
- Produces: `struct UploadSettingsView: View`, `struct OverlaySettingsView: View`.

- [ ] **Step 1: Write the Upload tab**

`TidyShot/Settings/UploadSettingsView.swift`:
```swift
import SwiftUI

/// Destination fields, credentials (saved to the Keychain), key naming, and Test Connection.
struct UploadSettingsView: View {
    private let coordinator = AppCoordinator.shared

    @State private var draft = S3DestinationConfig.empty
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
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
                Text("Stored in your login keychain, never in preferences.")
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

    private func load() {
        draft = coordinator.settings.s3Config ?? .empty
        if let credentials = try? coordinator.credentialStore.load(account: KeychainCredentialStore.defaultAccount) {
            accessKeyID = credentials.accessKeyID
            secretAccessKey = credentials.secretAccessKey
        }
    }

    /// Returns false (and shows why) when the form cannot be saved.
    @discardableResult
    private func save() -> Bool {
        if let error = draft.validationError {
            show(error.localizedDescription, isError: true)
            return false
        }
        let trimmedID = accessKeyID.trimmingCharacters(in: .whitespaces)
        let trimmedSecret = secretAccessKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else {
            show("Access key ID and secret access key are required.", isError: true)
            return false
        }
        do {
            try coordinator.credentialStore.save(AWSCredentials(accessKeyID: trimmedID, secretAccessKey: trimmedSecret),
                                                 account: KeychainCredentialStore.defaultAccount)
        } catch {
            show(error.localizedDescription, isError: true)
            return false
        }
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
        show(result.summary, isError: result.outcome != .readable)
    }

    private func show(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
```

- [ ] **Step 2: Write the Overlay tab**

`TidyShot/Settings/OverlaySettingsView.swift`:
```swift
import SwiftUI

struct OverlaySettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Show Quick Access overlay after capture", isOn: $settings.showOverlay)
            Picker("Position", selection: $settings.overlayCorner) {
                ForEach(OverlayCorner.allCases) { corner in
                    Text(corner.title).tag(corner)
                }
            }
            .disabled(!settings.showOverlay)
            Stepper(value: $settings.overlayAutoCloseSeconds, in: 0...60, step: 1) {
                Text(settings.overlayAutoCloseSeconds == 0
                     ? "Auto-close: never"
                     : "Auto-close after \(Int(settings.overlayAutoCloseSeconds)) s")
            }
            .disabled(!settings.showOverlay)
            Stepper("Keep history for \(settings.historyRetentionDays) days", value: $settings.historyRetentionDays, in: 1...365)
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Add both tabs**

`TidyShot/Settings/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "camera") }
            UploadSettingsView()
                .tabItem { Label("Upload", systemImage: "icloud.and.arrow.up") }
            OverlaySettingsView()
                .tabItem { Label("Overlay", systemImage: "macwindow.on.rectangle") }
        }
        .frame(width: 520)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}
```

- [ ] **Step 4: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 87 tests in 17 suites passed`.

- [ ] **Step 5: Write the manual checklist**

`docs/testing/phase-2-manual-checklist.md`:
````markdown
# Phase 2 manual test checklist

Run after any change to Upload, History, Overlay, or AppCoordinator. Automated tests cover
signing (AWS test suite plus the S3 worked examples), URL building, key naming, the queue,
the keychain store, and history persistence; everything here needs a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a bucket you can
write to, its public URL base (for example `https://snap.tky.io/`), and an access key pair.

## Upload settings
- [ ] Settings > Upload: Save with an empty endpoint shows "Endpoint must be an http or https URL…" in red.
- [ ] Fill in endpoint, region, bucket, public URL `https://snap.tky.io/{key}`, access key ID and secret; Save shows "Saved."
- [ ] Quit and relaunch: the fields are filled in again, including the secret (read back from the keychain).
- [ ] `defaults read io.tky.tidyshot` does not contain the access key ID or secret.
- [ ] Keychain Access (login keychain) shows an item "TidyShot S3 credentials" with account `default`.
- [ ] Test Connection with correct settings reports "Upload and public read both work." and the probe object is gone from the bucket afterwards.
- [ ] Test Connection with a wrong secret reports "Upload failed: Server returned HTTP 403…".
- [ ] Test Connection with a public URL template pointing at a domain that does not serve the bucket reports "Upload worked, but the public URL returned HTTP …".
- [ ] Random name length stepper stops at 4 and 32; the example key updates as the prefix and length change.

## Capture and upload (⌃⇧3, ⌃⇧4, ⌃⇧2)
- [ ] After-capture action "Upload and copy URL": capture, wait for the overlay checkmark, paste into Slack or Notes: a working `https://snap.tky.io/XXXXXX.png` link appears, nothing else.
- [ ] From releasing the mouse to a pasteable link takes about two seconds on a normal connection.
- [ ] The menu bar icon shows an up-arrow circle while uploading and returns to the viewfinder afterwards.
- [ ] Notification "Uploaded, URL copied" appears; clicking it opens the URL in the browser.
- [ ] The uploaded object is a PNG with 144 DPI on a Retina display (download it and check with Preview > Tools > Show Inspector).
- [ ] With "Also copy image" on: immediately after capture, paste gives the image; after the upload finishes, paste gives the URL.
- [ ] With "Send public-read ACL" on, uploads still succeed on a bucket that allows ACLs, and the object is public.
- [ ] After-capture action "Save and copy image": no upload happens, paste gives the image, history shows 💾.
- [ ] Set key prefix `shots`: new objects land under `shots/` and the URL is `https://snap.tky.io/shots/XXXXXX.png`.
- [ ] Path-style on against MinIO (`http://localhost:9000`, region `us-east-1`): upload succeeds.

## Overlay
- [ ] Panel appears in the chosen corner of the display under the mouse, 16 pt from the edges, without taking focus from the frontmost app.
- [ ] Progress ring moves during a large (fullscreen Retina) upload, then shows the checkmark and URL.
- [ ] "Copy URL" puts the URL on the clipboard again after something else was copied.
- [ ] Clicking the thumbnail reveals the file in Finder.
- [ ] Auto-close happens 5 s after the upload finishes; hovering keeps it open; moving away closes it a second later.
- [ ] Auto-close 0 keeps the panel until the X is clicked.
- [ ] Settings > Overlay off: no panel, uploads still work.
- [ ] A second capture replaces the panel with the new capture.

## Failures and history
- [ ] Turn Wi-Fi off, capture: the file is saved, the overlay shows "Upload failed" with Retry, a notification appears, history shows ⚠️, nothing is on the clipboard unless "Also copy image" is on.
- [ ] Turn Wi-Fi on, click Retry in the overlay: the upload succeeds and the URL is copied.
- [ ] Recent Captures > Retry Failed Uploads retries every ⚠️ item.
- [ ] Choosing a 🔗 history item copies its URL; choosing a 💾 item reveals the file.
- [ ] Quit while an upload is in flight (slow connection or large capture), relaunch: the item shows ⚠️ "Upload was interrupted." and Retry works.
- [ ] Wrong secret: the overlay shows "Upload failed … HTTP 403" after one attempt, no retries in the log.
- [ ] `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/history.json` lists the captures newest first.
- [ ] Set history retention to 1 day, relaunch after a day: older items are gone, their files are still on disk.
````

- [ ] **Step 6: Update the README**

Add this section to `README.md` after "## Default shortcuts", and change the intro sentence "(in a later phase) uploaded to your own S3 bucket" to "uploaded to your own S3-compatible bucket":

````markdown
## Upload

Settings > Upload takes an S3-compatible endpoint (AWS S3, Cloudflare R2, Backblaze B2, MinIO),
region, bucket, optional key prefix, and a public URL template such as `https://snap.tky.io/{key}`.
Credentials are stored in your login keychain. Test Connection uploads a small probe object,
fetches it through the public URL without credentials, and deletes it.

Object keys are random, 6 characters by default (4 to 32). The app checks that a key is unused
before uploading. By default no ACL header is sent; turn on "Send public-read ACL" only if your
bucket relies on object ACLs rather than a bucket policy or CDN.

After a capture the file is saved locally first, then uploaded; the public URL replaces the
clipboard contents when the upload finishes. Failed uploads stay in the menu's Recent Captures
list with a retry action.
````

- [ ] **Step 7: Run the end-to-end check**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Configure a real destination in Settings > Upload, click Test Connection, then press `⌃⇧4`, drag a rectangle, and paste into Slack. Expected: a working `https://snap.tky.io/XXXXXX.png` link within about two seconds of releasing the mouse. Then work through `docs/testing/phase-2-manual-checklist.md`.

- [ ] **Step 8: Commit**

```bash
git add TidyShot/Settings/UploadSettingsView.swift TidyShot/Settings/OverlaySettingsView.swift TidyShot/Settings/SettingsView.swift docs/testing/phase-2-manual-checklist.md README.md
git commit -m "feat: add Upload and Overlay settings tabs, Phase 2 checklist and README"
```

Phase 2 is done when the manual checklist passes. Open a PR from `phase-2-upload` against `main` (after PR tkyocum/tidyshot#1 has merged) with the checklist results in the description.

---

## Out of scope for this plan (next plans)

- Phase 3: full overlay (save-as, drag-out with `NSFilePromiseProvider`, annotate button, close and restore, stacking, multi-display), All-in-One mode, capture previous area, freeze screen, self-timer, cursor and shadow options, pin to screen, URL scheme, per-destination format override.
- Multiple destinations and a destinations list (the `Destination` protocol and `S3DestinationConfig` are ready for it).
- Date-based and original-filename object key schemes from spec section 2.2 (only the random scheme ships here).
- Data-protection keychain migration once Developer ID signing exists.
- Deleting an object from the bucket when a history item is removed.
