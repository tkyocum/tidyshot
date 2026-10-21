import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct ClopClientTests {
    static func fixture(_ name: String) throws -> Data {
        let url = Bundle(for: FixtureLocator.self).resourceURL!
            .appending(path: "Fixtures/Clop/\(name)", directoryHint: .notDirectory)
        return try Data(contentsOf: url)
    }

    // MARK: Request

    @Test func requestEncodesTheKeysClopSDKUses() throws {
        let url = URL(fileURLWithPath: "/tmp/Clop/a.png")
        let request = ClopRequest(id: "REQ-1", urls: [url], hideFloatingResult: true, copyToClipboard: false,
                                  aggressiveOptimisation: false)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])

        #expect(object["id"] as? String == "REQ-1")
        #expect(object["urls"] as? [String] == ["file:///tmp/Clop/a.png"])
        #expect((object["originalUrls"] as? [Any])?.isEmpty == true)
        #expect(object["source"] as? String == "sdk")
        #expect(object["hideFloatingResult"] as? Bool == true)
        #expect(object["copyToClipboard"] as? Bool == false)
        #expect(object["aggressiveOptimisation"] as? Bool == false)
    }

    @Test func requestOmitsNilOptionals() throws {
        let request = ClopRequest(id: "REQ-2", urls: [URL(fileURLWithPath: "/tmp/Clop/b.png")], hideFloatingResult: true,
                                  copyToClipboard: false, aggressiveOptimisation: false)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])

        for key in ["size", "downscaleFactor", "changePlaybackSpeedFactor", "output", "removeAudio"] {
            #expect(object[key] == nil, "\(key) should be omitted")
        }
        #expect(Set(object.keys) == ["id", "urls", "originalUrls", "hideFloatingResult", "copyToClipboard",
                                     "aggressiveOptimisation", "source"])
    }

    // MARK: Response (recorded from Clop 3.6.2)

    @Test func responseDecodesTheRecordedReply() throws {
        let responses = try JSONDecoder().decode([ClopResponse].self, from: Self.fixture("reply-optimised.json"))
        let response = try #require(responses.first)

        #expect(responses.count == 1)
        #expect(response.path == response.forURL.path(percentEncoded: false))
        #expect(response.convertedFrom == nil)
        #expect(response.oldBytes == 208_709)
        #expect(response.newBytes == 15_664)
        #expect(response.oldWidthHeight == CGSize(width: 256, height: 256))
        #expect(response.newWidthHeight == CGSize(width: 256, height: 256))
    }

    @Test func responseDecodesTheAlreadyOptimisedReplyWithoutNewWidthHeight() throws {
        let responses = try JSONDecoder().decode([ClopResponse].self, from: Self.fixture("reply-already-optimised.json"))
        let response = try #require(responses.first)

        #expect(response.oldBytes == response.newBytes)
        #expect(response.oldBytes == 15_664)
        #expect(response.oldWidthHeight == nil)
        #expect(response.newWidthHeight == nil)
        #expect(response.convertedFrom == nil)
    }

    // MARK: Port names

    @Test func portNameAppendsTheServiceSuffix() {
        #expect(ClopClient.portName(bundleID: "com.lowtechguys.Clop") == "com.lowtechguys.Clop.optimisationService")
        #expect(ClopClient.portName(bundleID: "com.lowtechguys.Clop-setapp") == "com.lowtechguys.Clop-setapp.optimisationService")
    }

    @Test func clientDefaultsToTheSpecTimeouts() {
        let client = ClopClient(bundleID: "com.lowtechguys.Clop")
        #expect(client.sendTimeout == 2)
        #expect(client.receiveTimeout == 30)
    }

    /// A port nobody listens on is reported, not hung on. This does not touch the real Clop.
    @Test func unknownPortThrowsPortUnavailable() {
        let client = ClopClient(bundleID: "io.tky.tidyshot.tests.no-such-clop")
        #expect(throws: ClopClientError.portUnavailable) {
            try client.optimise(URL(fileURLWithPath: "/tmp/none.png"))
        }
    }
}
