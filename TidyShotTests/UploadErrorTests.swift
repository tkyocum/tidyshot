import Foundation
import Testing
@testable import TidyShot

struct UploadErrorTests {
    @Test func noSuchUploadIsNotRetryable() {
        #expect(!UploadError.noSuchUpload.isRetryable)
        #expect(!UploadError.isRetryable(UploadError.noSuchUpload))
        #expect(UploadError.noSuchUpload.localizedDescription == "The upload was no longer known to the server.")
    }

    @Test func partsRejectedIsNotRetryable() {
        let error = UploadError.partsRejected(body: "InvalidPart: One or more of the specified parts could not be found.")
        #expect(!error.isRetryable)
        #expect(error.localizedDescription
            == "The server rejected the upload's part list: InvalidPart: One or more of the specified parts could not be found.")
    }

    /// A 200 Complete with `<Error>` retries for the codes a 5xx or a 429 would carry.
    @Test(arguments: ["InternalError", "SlowDown", "ServiceUnavailable"])
    func completeErrorIsRetryableForServerCodes(code: String) {
        let error = UploadError.completeError(code: code, body: "\(code): Please try again.")
        #expect(error.isRetryable)
        #expect(UploadError.isRetryable(error))
        #expect(error.localizedDescription == "The server could not complete the upload: \(code): Please try again.")
    }

    @Test(arguments: ["EntityTooLarge", "AccessDenied", "InvalidPart", ""])
    func completeErrorIsNotRetryableForOtherCodes(code: String) {
        #expect(!UploadError.completeError(code: code, body: code).isRetryable)
    }

    @Test func existingCasesKeepTheirRule() {
        #expect(UploadError.httpStatus(500, body: "").isRetryable)
        #expect(UploadError.httpStatus(503, body: "").isRetryable)
        #expect(UploadError.httpStatus(429, body: "").isRetryable)
        #expect(!UploadError.httpStatus(400, body: "").isRetryable)
        #expect(!UploadError.httpStatus(403, body: "").isRetryable)
        #expect(!UploadError.httpStatus(404, body: "").isRetryable)
        #expect(UploadError.noHTTPResponse.isRetryable)
        #expect(!UploadError.keyCollisionsExhausted.isRetryable)
        #expect(!UploadError.notConfigured.isRetryable)
        #expect(!UploadError.fileUnreadable("/a.mp4").isRetryable)
    }

    @Test func arbitraryErrorsKeepTheirRule() {
        #expect(!UploadError.isRetryable(CancellationError()))
        #expect(!UploadError.isRetryable(URLError(.cancelled)))
        #expect(!UploadError.isRetryable(URLError(.fileDoesNotExist)))
        #expect(UploadError.isRetryable(URLError(.networkConnectionLost)))
        #expect(UploadError.isRetryable(URLError(.timedOut)))
        #expect(!UploadError.isRetryable(CocoaError(.fileReadNoSuchFile)))
    }
}
