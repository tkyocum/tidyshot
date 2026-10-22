// Adapted from ClopSDK (https://github.com/FuzzyIdeas/ClopSDK), MIT License, Copyright (c) 2023 The low-tech guys. See ThirdPartyNotices.md.
import CoreFoundation
import CoreGraphics
import Foundation

/// The request Clop's optimisation port decodes. Field names, order and types match ClopSDK's
/// `OptimisationRequest`, because Clop decodes this JSON with its own copy of it.
nonisolated struct ClopRequest: Codable, Sendable {
    struct CropSize: Codable, Sendable {
        var width: Int
        var height: Int
        var name = ""
        var longEdge = false
    }

    let id: String
    let urls: [URL]
    var originalUrls: [URL: URL] = [:]
    var size: CropSize?
    var downscaleFactor: Double?
    var changePlaybackSpeedFactor: Double?
    let hideFloatingResult: Bool
    let copyToClipboard: Bool
    let aggressiveOptimisation: Bool
    var source = "sdk"
    var output: String?
    var removeAudio: Bool?
}

/// One entry of Clop's reply (ClopSDK's `OptimisationResponse`).
nonisolated struct ClopResponse: Codable, Sendable, Equatable {
    let path: String
    let forURL: URL
    var convertedFrom: String?
    var oldBytes = 0
    var newBytes = 0
    var oldWidthHeight: CGSize?
    var newWidthHeight: CGSize?
}

nonisolated enum ClopClientError: Error, Equatable {
    /// Clop is not running, or the sandbox denied the port lookup.
    case portUnavailable
    /// The `CFMessagePortSendRequest` status: -1 send timeout, -2 receive timeout, -3 invalid, -4 transport, -5 became invalid.
    case sendFailed(Int32)
    /// The reply was empty, undecodable or held no entries.
    case badReply
}

/// Sends one optimisation request to Clop's CFMessagePort and waits for the reply.
/// `optimise` blocks, so call it off the main actor. It never launches Clop.
nonisolated struct ClopClient: Sendable {
    let bundleID: String
    var sendTimeout: TimeInterval
    var receiveTimeout: TimeInterval

    static func portName(bundleID: String) -> String {
        "\(bundleID).optimisationService"
    }

    init(bundleID: String, sendTimeout: TimeInterval = 2, receiveTimeout: TimeInterval = 30) {
        self.bundleID = bundleID
        self.sendTimeout = sendTimeout
        self.receiveTimeout = receiveTimeout
    }

    /// The request for one file. A video (`.mp4`) asks Clop to keep its audio, whatever Clop's own
    /// remove-audio preference says; an image leaves `removeAudio` out.
    static func request(for url: URL, id: String) -> ClopRequest {
        var request = ClopRequest(id: id, urls: [url], hideFloatingResult: true,
                                  copyToClipboard: false, aggressiveOptimisation: false)
        if url.pathExtension.lowercased() == "mp4" {
            request.removeAudio = false
        }
        return request
    }

    /// The first entry of Clop's reply. No reply, an undecodable one, or an empty list (`[]`,
    /// which Clop sends for a file it skips) throws `badReply`.
    static func response(from reply: Data?) throws -> ClopResponse {
        guard let reply, let responses = try? JSONDecoder().decode([ClopResponse].self, from: reply),
              let first = responses.first else { throw ClopClientError.badReply }
        return first
    }

    func optimise(_ url: URL) throws -> ClopResponse {
        let body = try JSONEncoder().encode(Self.request(for: url, id: UUID().uuidString))
        guard let port = CFMessagePortCreateRemote(nil, Self.portName(bundleID: bundleID) as CFString) else {
            throw ClopClientError.portUnavailable
        }
        defer { CFMessagePortInvalidate(port) }

        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, Int32.random(in: 1...100_000), body as CFData,
                                              sendTimeout, receiveTimeout, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess else { throw ClopClientError.sendFailed(status) }
        return try Self.response(from: reply?.takeRetainedValue() as Data?)
    }
}
