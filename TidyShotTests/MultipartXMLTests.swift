import Foundation
import Testing
@testable import TidyShot

/// The element scans over S3's multipart answers. The Create, Error and ListParts bodies follow
/// the samples in the AWS S3 API Reference (CreateMultipartUpload, CompleteMultipartUpload,
/// ListParts), with the ETags escaped as S3 sends them.
struct MultipartXMLTests {
    private func body(_ text: String) -> Data { Data(text.utf8) }

    // MARK: UploadId

    @Test func uploadIDFromCreateBody() {
        let create = body("""
        <?xml version="1.0" encoding="UTF-8"?>
        <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Bucket>example-bucket</Bucket>
          <Key>example-object</Key>
          <UploadId>VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA</UploadId>
        </InitiateMultipartUploadResult>
        """)
        #expect(MultipartXML.uploadID(in: create) == "VXBsb2FkIElEIGZvciA2aWWpbmcncyBteS1tb3ZpZS5tMnRzIHVwbG9hZA")
    }

    @Test func uploadIDFromEmptyBodyIsNil() {
        #expect(MultipartXML.uploadID(in: Data()) == nil)
        #expect(MultipartXML.uploadID(in: body("<InitiateMultipartUploadResult><UploadId></UploadId></InitiateMultipartUploadResult>")) == nil)
    }

    // MARK: Error

    @Test func errorFromCompleteBodyWithStatus200() {
        let complete = body("""
        <?xml version="1.0" encoding="UTF-8"?>

        <Error>
          <Code>InternalError</Code>
          <Message>We encountered an internal error. Please try again.</Message>
          <RequestId>656c76696e6727732072657175657374</RequestId>
          <HostId>Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg==</HostId>
        </Error>
        """)
        #expect(MultipartXML.error(in: complete)
                == MultipartXML.ErrorBody(code: "InternalError", message: "We encountered an internal error. Please try again."))
    }

    @Test func noErrorFromPlainCompleteResult() {
        let complete = body("""
        <?xml version="1.0" encoding="UTF-8"?>
        <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Location>http://Example-Bucket.s3.region.amazonaws.com/Example-Object</Location>
          <Bucket>Example-Bucket</Bucket>
          <Key>Example-Object</Key>
          <ETag>&quot;3858f62230ac3c915f300c664312c11f-9&quot;</ETag>
        </CompleteMultipartUploadResult>
        """)
        #expect(MultipartXML.error(in: complete) == nil)
        #expect(MultipartXML.error(in: Data()) == nil)
    }

    @Test(arguments: ["NoSuchUpload", "InvalidPart", "EntityTooSmall"])
    func errorCodes(code: String) {
        let failure = body("<Error><Code>\(code)</Code><Message>Something about \(code).</Message><RequestId>1</RequestId></Error>")
        #expect(MultipartXML.error(in: failure) == MultipartXML.ErrorBody(code: code, message: "Something about \(code)."))
    }

    @Test func errorWithoutMessageOrCode() {
        #expect(MultipartXML.error(in: body("<Error><Code>SlowDown</Code></Error>"))
                == MultipartXML.ErrorBody(code: "SlowDown", message: nil))
        #expect(MultipartXML.error(in: body("<Error><Code></Code><Message>No code.</Message></Error>")) == nil)
        // A Code outside an Error element is not an error.
        #expect(MultipartXML.error(in: body("<Result><Code>InternalError</Code></Result>")) == nil)
    }

    // MARK: ListParts

    private let truncatedPage = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ListPartsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Bucket>example-bucket</Bucket>
      <Key>example-object</Key>
      <UploadId>XXBsb2FkIElEIGZvciBlbHZpbmcncyVcdS1tb3ZpZS5tMnRzEEEwbG9hZA</UploadId>
      <Initiator>
        <ID>arn:aws:iam::111122223333:user/some-user</ID>
        <DisplayName>some-user</DisplayName>
      </Initiator>
      <Owner>
        <ID>75aa57f09aa0c8caeab4f8c24e99d10f8e7faeebf76c078efc7c6caea54ba06a</ID>
        <DisplayName>someName</DisplayName>
      </Owner>
      <StorageClass>STANDARD</StorageClass>
      <PartNumberMarker>0</PartNumberMarker>
      <NextPartNumberMarker>3</NextPartNumberMarker>
      <MaxParts>3</MaxParts>
      <IsTruncated>true</IsTruncated>
      <Part>
        <PartNumber>1</PartNumber>
        <LastModified>2010-11-10T20:48:34.000Z</LastModified>
        <ETag>&quot;7778aef83f66abc1fa1e8477f296d394&quot;</ETag>
        <Size>10485760</Size>
      </Part>
      <Part>
        <PartNumber>2</PartNumber>
        <LastModified>2010-11-10T20:48:33.000Z</LastModified>
        <ETag>&quot;aaaa18db4cc2f85cedef654fccc4a4x8&quot;</ETag>
        <Size>10485760</Size>
      </Part>
      <Part>
        <PartNumber>3</PartNumber>
        <LastModified>2010-11-10T20:48:35.000Z</LastModified>
        <ETag>&quot;0123456789abcdef0123456789abcdef&quot;</ETag>
        <Size>10485760</Size>
      </Part>
    </ListPartsResult>
    """

    @Test func truncatedPartsPage() {
        let page = MultipartXML.partsPage(in: body(truncatedPage))
        #expect(page == MultipartXML.PartsPage(parts: [
            MultipartPart(number: 1, etag: "\"7778aef83f66abc1fa1e8477f296d394\"", size: 10_485_760),
            MultipartPart(number: 2, etag: "\"aaaa18db4cc2f85cedef654fccc4a4x8\"", size: 10_485_760),
            MultipartPart(number: 3, etag: "\"0123456789abcdef0123456789abcdef\"", size: 10_485_760),
        ], isTruncated: true, nextMarker: 3))
    }

    @Test func lastPartsPage() {
        let last = body("""
        <ListPartsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <PartNumberMarker>3</PartNumberMarker>
          <IsTruncated>false</IsTruncated>
          <Part><PartNumber>4</PartNumber><ETag>&quot;dddd&quot;</ETag><Size>1048576</Size></Part>
        </ListPartsResult>
        """)
        #expect(MultipartXML.partsPage(in: last) == MultipartXML.PartsPage(
            parts: [MultipartPart(number: 4, etag: "\"dddd\"", size: 1_048_576)], isTruncated: false, nextMarker: nil))
    }

    @Test func emptyPartsPage() {
        let empty = body("<ListPartsResult><IsTruncated>false</IsTruncated></ListPartsResult>")
        #expect(MultipartXML.partsPage(in: empty) == MultipartXML.PartsPage(parts: [], isTruncated: false, nextMarker: nil))
    }

    @Test func partWithoutNumberETagOrSizeIsLeftOut() {
        let page = body("""
        <ListPartsResult>
          <IsTruncated>false</IsTruncated>
          <Part><PartNumber>1</PartNumber><ETag>&quot;a&quot;</ETag></Part>
          <Part><PartNumber>x</PartNumber><ETag>&quot;b&quot;</ETag><Size>5</Size></Part>
          <Part><PartNumber>3</PartNumber><ETag>&quot;c&quot;</ETag><Size>5</Size></Part>
        </ListPartsResult>
        """)
        #expect(MultipartXML.partsPage(in: page)?.parts == [MultipartPart(number: 3, etag: "\"c\"", size: 5)])
    }

    @Test func bodyWithoutListPartsResultIsNil() {
        #expect(MultipartXML.partsPage(in: Data()) == nil)
        #expect(MultipartXML.partsPage(in: body("<Error><Code>NoSuchUpload</Code></Error>")) == nil)
        #expect(MultipartXML.partsPage(in: body("<ListPartsResults><IsTruncated>false</IsTruncated></ListPartsResults>")) == nil)
    }

    // MARK: Entities

    @Test func unescapesTheFiveEntitiesAmpersandLast() {
        #expect(MultipartXML.unescaped("&quot;a&amp;lt;&quot;") == "\"a&lt;\"")
        #expect(MultipartXML.unescaped("&apos;&lt;&gt;&amp;") == "'<>&")
        #expect(MultipartXML.unescaped("plain") == "plain")
    }
}
