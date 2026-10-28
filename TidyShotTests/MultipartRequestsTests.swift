import Foundation
import Testing
@testable import TidyShot

/// Each multipart call's method, decoded query, extra headers, body and payload hash.
struct MultipartRequestsTests {
    private func pairs(_ list: [(name: String, value: String)]) -> [String] { list.map { "\($0.name)=\($0.value)" } }

    // MARK: Create

    @Test func createWithEveryHeader() {
        let call = MultipartRequests.create(contentType: "video/mp4", cacheControl: "no-cache", publicRead: true)
        #expect(call.method == "POST")
        #expect(pairs(call.query) == ["uploads="])
        #expect(pairs(call.headers) == ["content-type=video/mp4", "cache-control=no-cache", "x-amz-acl=public-read"])
        #expect(call.body.isEmpty)
        #expect(call.payloadHash == S3Signer.emptyPayloadHash)
    }

    @Test func createWithoutCacheControl() {
        let call = MultipartRequests.create(contentType: "image/gif", cacheControl: nil, publicRead: true)
        #expect(pairs(call.headers) == ["content-type=image/gif", "x-amz-acl=public-read"])
    }

    @Test func createWithoutACL() {
        let call = MultipartRequests.create(contentType: "video/mp4", cacheControl: "no-cache", publicRead: false)
        #expect(pairs(call.headers) == ["content-type=video/mp4", "cache-control=no-cache"])
    }

    @Test func createWithContentTypeOnly() {
        let call = MultipartRequests.create(contentType: "video/mp4", cacheControl: nil, publicRead: false)
        #expect(pairs(call.headers) == ["content-type=video/mp4"])
    }

    // MARK: UploadPart

    @Test func uploadPart() {
        let data = Data("part bytes".utf8)
        let call = MultipartRequests.uploadPart(uploadID: "id/+=1", number: 12, data: data)
        #expect(call.method == "PUT")
        #expect(pairs(call.query) == ["partNumber=12", "uploadId=id/+=1"])
        #expect(call.headers.isEmpty)
        #expect(call.body == data)
        #expect(call.payloadHash == S3Signer.sha256Hex(data))
        #expect(call.payloadHash != "UNSIGNED-PAYLOAD")
    }

    // MARK: Complete

    @Test func complete() {
        let parts = [MultipartPart(number: 2, etag: "\"b\"", size: 5)]
        let call = MultipartRequests.complete(uploadID: "abc", parts: parts)
        #expect(call.method == "POST")
        #expect(pairs(call.query) == ["uploadId=abc"])
        #expect(pairs(call.headers) == ["content-type=application/xml"])
        #expect(call.body == MultipartRequests.completeBody(parts))
        #expect(call.payloadHash == S3Signer.sha256Hex(call.body))
    }

    @Test func completeBodyListsPartsInAscendingOrderWithQuotedETags() {
        let parts = [
            MultipartPart(number: 3, etag: "\"ccc\"", size: 1),
            MultipartPart(number: 1, etag: "\"aaa\"", size: 5),
            MultipartPart(number: 2, etag: "\"bbb\"", size: 5),
        ]
        let text = String(decoding: MultipartRequests.completeBody(parts), as: UTF8.self)
        #expect(text == "<CompleteMultipartUpload>"
                + "<Part><PartNumber>1</PartNumber><ETag>\"aaa\"</ETag></Part>"
                + "<Part><PartNumber>2</PartNumber><ETag>\"bbb\"</ETag></Part>"
                + "<Part><PartNumber>3</PartNumber><ETag>\"ccc\"</ETag></Part>"
                + "</CompleteMultipartUpload>")
    }

    // MARK: Abort and ListParts

    @Test func abort() {
        let call = MultipartRequests.abort(uploadID: "abc")
        #expect(call.method == "DELETE")
        #expect(pairs(call.query) == ["uploadId=abc"])
        #expect(call.headers.isEmpty)
        #expect(call.body.isEmpty)
        #expect(call.payloadHash == S3Signer.emptyPayloadHash)
    }

    @Test func listPartsFirstPage() {
        let call = MultipartRequests.listParts(uploadID: "abc", marker: nil)
        #expect(call.method == "GET")
        #expect(pairs(call.query) == ["uploadId=abc"])
        #expect(call.headers.isEmpty)
        #expect(call.body.isEmpty)
        #expect(call.payloadHash == S3Signer.emptyPayloadHash)
    }

    @Test func listPartsLaterPage() {
        let call = MultipartRequests.listParts(uploadID: "abc", marker: 1000)
        #expect(pairs(call.query) == ["uploadId=abc", "part-number-marker=1000"])
    }

    // MARK: Every call

    @Test func everyPayloadHashIsTheBodysHash() {
        let calls = [
            MultipartRequests.create(contentType: "video/mp4", cacheControl: nil, publicRead: false),
            MultipartRequests.uploadPart(uploadID: "abc", number: 1, data: Data(repeating: 7, count: 1024)),
            MultipartRequests.complete(uploadID: "abc", parts: [MultipartPart(number: 1, etag: "\"a\"", size: 1024)]),
            MultipartRequests.abort(uploadID: "abc"),
            MultipartRequests.listParts(uploadID: "abc", marker: 3),
        ]
        for call in calls {
            #expect(call.payloadHash == S3Signer.sha256Hex(call.body))
        }
    }

    @Test func multipartPartRoundTrips() throws {
        let part = MultipartPart(number: 7, etag: "\"abc\"", size: 16_777_216)
        let decoded = try JSONDecoder().decode(MultipartPart.self, from: JSONEncoder().encode(part))
        #expect(decoded == part)
    }
}
