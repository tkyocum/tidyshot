import CoreAudio
import Foundation
func prop<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as: T.Type) -> T? {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    let p = UnsafeMutablePointer<T>.allocate(capacity: 1); defer { p.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, p) == noErr else { return nil }
    return p.pointee
}
var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
for id in ids {
    let name = prop(id, kAudioObjectPropertyName, as: CFString.self) as String? ?? "?"
    let uid = prop(id, kAudioDevicePropertyDeviceUID, as: CFString.self) as String? ?? "?"
    func chans(_ scope: AudioObjectPropertyScope) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var s: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &s) == noErr else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(s), alignment: 16); defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, buf) == noErr else { return 0 }
        let abl = buf.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(abl).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    let lat = prop(id, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput, as: UInt32.self) ?? 0
    let latIn = prop(id, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeInput, as: UInt32.self) ?? 0
    let bufOut = prop(id, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeOutput, as: UInt32.self) ?? 0
    print("\(name) | uid \(uid) | in \(chans(kAudioObjectPropertyScopeInput)) out \(chans(kAudioObjectPropertyScopeOutput)) | latency out \(lat) in \(latIn) frames | buf \(bufOut)")
}
