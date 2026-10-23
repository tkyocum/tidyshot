import Foundation
setbuf(stdout, nil)
struct Req: Encodable { let id: String; let urls: [URL]; var originalUrls: [URL: URL] = [:]; let hideFloatingResult = true; let copyToClipboard = false; let aggressiveOptimisation = false; var source = "sdk"; var removeAudio: Bool? = nil }
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let work = FileManager.default.temporaryDirectory.appending(path: "clop-raw-\(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let copy = work.appending(path: src.lastPathComponent); try FileManager.default.copyItem(at: src, to: copy)
var req = Req(id: UUID().uuidString, urls: [copy]); if CommandLine.arguments.count > 2 { req.removeAudio = CommandLine.arguments[2] == "true" }
let body = try JSONEncoder().encode(req)
let port = CFMessagePortCreateRemote(nil, "com.lowtechguys.Clop.optimisationService" as CFString)!
var reply: Unmanaged<CFData>?
let t0 = Date()
let status = CFMessagePortSendRequest(port, 7, body as CFData, 2, 600, CFRunLoopMode.defaultMode.rawValue, &reply)
let data = reply?.takeRetainedValue() as Data?
print(String(format: "status %d after %.1fs", status, Date().timeIntervalSince(t0)), "reply:", data.map { String(decoding: $0, as: UTF8.self) } ?? "nil")
print("dir:", (try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? [], (try? FileManager.default.attributesOfItem(atPath: copy.path)[.size]) ?? "?")
