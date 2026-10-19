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

    /// Pasted values often carry spaces; they are trimmed, not rejected.
    @Test func paddedFieldsAreTrimmedNotRejected() throws {
        var padded = aws
        padded.endpoint = " https://s3.us-west-2.amazonaws.com "
        padded.region = " us-west-2 "
        padded.bucket = " my-bucket "
        padded.keyPrefix = " shots "
        #expect(padded.validationError == nil)

        let clean = padded.normalized
        #expect(clean.bucket == "my-bucket")
        #expect(clean.region == "us-west-2")
        #expect(clean.endpoint == "https://s3.us-west-2.amazonaws.com")
        #expect(clean.keyPrefix == "shots")
        #expect(try padded.objectURL(for: "a.png").absoluteString == "https://my-bucket.s3.us-west-2.amazonaws.com/a.png")
        #expect(padded.objectPath(for: "a.png") == "/a.png")
    }
}
