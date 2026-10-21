// Adapted from ClopSDK (https://github.com/FuzzyIdeas/ClopSDK), MIT License,
// Copyright (c) 2023 The low-tech guys. See ThirdPartyNotices.
import CoreFoundation
import Foundation

/// The request Clop's optimisation port decodes. Field names and types match ClopSDK's
/// `OptimisationRequest` exactly, because Clop decodes this JSON with its own copy of it.
nonisolated struct ClopRequest: Codable, Sendable {
    struct CropSize: Codable, Sendable { var width: Int; var height: Int; var name = ""; var longEdge = false }
    let id: String
    let urls: [URL]
    var originalUrls: [URL: URL] = [:]
    var size: CropSize? = nil
    var downscaleFactor: Double? = nil
    var changePlaybackSpeedFactor: Double? = nil
    let hideFloatingResult: Bool
    let copyToClipboard: Bool
    let aggressiveOptimisation: Bool
    let source: String
    var output: String? = nil
    var removeAudio: Bool? = nil
}

/// One entry of Clop's reply (ClopSDK's `OptimisationResponse`).
nonisolated struct ClopResponse: Codable, Sendable, Equatable {
    let path: String
    let forURL: URL
    var convertedFrom: String? = nil
    var oldBytes = 0
    var newBytes = 0
    var oldWidthHeight: CGSize? = nil
    var newWidthHeight: CGSize? = nil
}

nonisolated enum ClopClientError: Error, Equatable {
    case portUnavailable          // Clop not running, or the sandbox denied the lookup
    case sendFailed(Int32)        // CFMessagePortSendRequest status (-1 send timeout, -2 receive timeout, -3 invalid, -4 transport, -5 became invalid)
    case badReply
}

/// Sends one optimisation request to Clop's CFMessagePort and waits for the reply.
/// Blocking: call it off the main actor.
nonisolated struct ClopClient: Sendable {
    static let portName = "com.lowtechguys.Clop.optimisationService"
    var sendTimeout: TimeInterval = 5
    var receiveTimeout: TimeInterval = 60

    var isListening: Bool {
        guard let port = CFMessagePortCreateRemote(nil, Self.portName as CFString) else { return false }
        defer { CFMessagePortInvalidate(port) }
        return CFMessagePortIsValid(port)
    }

    func optimise(_ url: URL, output: String? = nil) throws -> ClopResponse {
        let request = ClopRequest(id: UUID().uuidString, urls: [url], hideFloatingResult: true, copyToClipboard: false,
                                  aggressiveOptimisation: false, source: "sdk", output: output)
        guard let port = CFMessagePortCreateRemote(nil, Self.portName as CFString) else { throw ClopClientError.portUnavailable }
        defer { CFMessagePortInvalidate(port) }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, Int32.random(in: 1...100_000), try JSONEncoder().encode(request) as CFData,
                                              sendTimeout, receiveTimeout, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess else { throw ClopClientError.sendFailed(status) }
        guard let data = reply?.takeRetainedValue() as Data?,
              let responses = try? JSONDecoder().decode([ClopResponse].self, from: data),
              let first = responses.first else { throw ClopClientError.badReply }
        return first
    }
}
