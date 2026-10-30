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
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"keyTemplate\""))
        #expect(!json.contains("keyPrefix") && !json.contains("keyLength"))
    }

    /// Phase 2 stored a prefix folder and a random length; both fold into the template.
    @Test func phase2PrefixAndLengthMigrateToTemplate() throws {
        func decode(_ json: String) throws -> S3DestinationConfig {
            try JSONDecoder().decode(S3DestinationConfig.self, from: Data(json.utf8))
        }
        let common = """
        "endpoint":"https://s3.us-west-2.amazonaws.com","region":"us-west-2","bucket":"snap",
        "usePathStyle":false,"sendPublicReadACL":false,"publicURLTemplate":"https://snap.tky.io/{key}"
        """
        #expect(try decode("{\(common),\"keyPrefix\":\"shots\",\"keyLength\":8}").keyTemplate == "shots/{random:8}")
        #expect(try decode("{\(common),\"keyPrefix\":\"\",\"keyLength\":6}").keyTemplate == "{random:6}")
        #expect(try decode("{\(common),\"keyPrefix\":\"/a/b/\",\"keyLength\":99}").keyTemplate == "a/b/{random:32}")
        #expect(try decode("{\(common),\"keyPrefix\":\"my shots+1\",\"keyLength\":8}").keyTemplate == "my-shots-1/{random:8}")
        #expect(try decode("{\(common)}").keyTemplate == "{random:6}")
        #expect(try decode("{\(common),\"keyTemplate\":\"{date}/{random}\",\"keyPrefix\":\"ignored\"}").keyTemplate == "{date}/{random}")
    }

    /// `{app}` was removed in Phase 3.1; a stored key template loses it when it is decoded.
    @Test func storedKeyTemplateLosesTheRemovedAppToken() throws {
        func roundTrip(_ template: String) throws -> S3DestinationConfig {
            var config = aws
            config.keyTemplate = template
            return try JSONDecoder().decode(S3DestinationConfig.self, from: JSONEncoder().encode(config))
        }
        #expect(try roundTrip("{app}/{date}/{random}").keyTemplate == "{date}/{random}")
        #expect(try roundTrip("{app}").keyTemplate == ObjectKeyNamer.defaultTemplate)
        #expect(try roundTrip("shots/{random}").keyTemplate == "shots/{random}")
    }

    @Test func invalidKeyTemplateIsAValidationError() {
        var spaced = aws
        spaced.keyTemplate = "my shots/{random}"
        #expect(spaced.validationError == .invalidKeyTemplate(ObjectKeyNamer.TemplateError.illegalCharacter(" ").localizedDescription))
        var unknown = aws
        unknown.keyTemplate = "{foo}"
        #expect(unknown.validationError == .invalidKeyTemplate(ObjectKeyNamer.TemplateError.unknownToken("foo").localizedDescription))
        #expect(!unknown.isComplete)
    }

    /// Pasted values often carry spaces; they are trimmed, not rejected.
    @Test func paddedFieldsAreTrimmedNotRejected() throws {
        var padded = aws
        padded.endpoint = " https://s3.us-west-2.amazonaws.com "
        padded.region = " us-west-2 "
        padded.bucket = " my-bucket "
        padded.keyTemplate = " /shots//{random}/ "
        #expect(padded.validationError == nil)

        let clean = padded.normalized
        #expect(clean.bucket == "my-bucket")
        #expect(clean.region == "us-west-2")
        #expect(clean.endpoint == "https://s3.us-west-2.amazonaws.com")
        #expect(clean.keyTemplate == "shots/{random}")
        #expect(try padded.objectURL(for: "a.png").absoluteString == "https://my-bucket.s3.us-west-2.amazonaws.com/a.png")
        #expect(padded.objectPath(for: "a.png") == "/a.png")
    }

    /// AWS wildcard certificates cover one label, so `snap.tky.io.s3.amazonaws.com` fails TLS;
    /// a bucket whose name contains a dot must use path-style URLs over HTTPS.
    @Test func dottedBucketNameForcesPathStyle() throws {
        let config = S3DestinationConfig(endpoint: "https://s3.dualstack.us-east-1.amazonaws.com",
                                         region: "us-east-1", bucket: "snap.tky.io",
                                         usePathStyle: false, publicURLTemplate: "https://snap.tky.io/{key}")
        #expect(config.effectivePathStyle)
        #expect(try config.objectURL(for: "abc.png").absoluteString
                == "https://s3.dualstack.us-east-1.amazonaws.com/snap.tky.io/abc.png")
        #expect(config.objectPath(for: "abc.png") == "/snap.tky.io/abc.png")
    }

    @Test func plainBucketNameKeepsVirtualHostStyle() throws {
        let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com",
                                         region: "us-east-1", bucket: "snaptky",
                                         usePathStyle: false, publicURLTemplate: "https://snap.tky.io/{key}")
        #expect(!config.effectivePathStyle)
        #expect(try config.objectURL(for: "abc.png").absoluteString == "https://snaptky.s3.us-east-1.amazonaws.com/abc.png")
    }

    /// The URL's query is the canonical query, so what is sent and what is signed cannot disagree.
    @Test(arguments: [
        [(name: "uploads", value: "")],
        [(name: "partNumber", value: "7"), (name: "uploadId", value: "a/b~c")],
        [(name: "uploadId", value: "2~Ab+c/d=")],
    ])
    func objectURLWithQueryCarriesTheCanonicalQuery(query: [(name: String, value: String)]) throws {
        var dotted = aws
        dotted.bucket = "snap.tky.io"
        let components = try #require(URLComponents(url: try dotted.objectURL(for: "r/Recording.mp4", query: query),
                                                    resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedQuery == S3Signer.canonicalQuery(query))
        #expect(components.percentEncodedPath == "/snap.tky.io/r/Recording.mp4")
        #expect(components.queryItems?.map { [$0.name, $0.value ?? ""] } == query.sorted { $0.name < $1.name }.map { [$0.name, $0.value] })
    }

    @Test func objectURLWithQuerySpelledOut() throws {
        var dotted = aws
        dotted.bucket = "snap.tky.io"
        let url = try dotted.objectURL(for: "r/Recording.mp4", query: [(name: "partNumber", value: "7"),
                                                                        (name: "uploadId", value: "a/b~c")])
        #expect(url.absoluteString == "https://s3.us-west-2.amazonaws.com/snap.tky.io/r/Recording.mp4?partNumber=7&uploadId=a%2Fb~c")
    }

    @Test func objectURLWithoutQueryHasNone() throws {
        #expect(try aws.objectURL(for: "aSIS7.png").query() == nil)
        #expect(try aws.objectURL(for: "aSIS7.png", query: []).query() == nil)
        #expect(try aws.objectURL(for: "aSIS7.png", query: []) == aws.objectURL(for: "aSIS7.png"))
    }
}
