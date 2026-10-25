// R3 probe: lists cameras without opening any. Prints, per device: name, uniqueID, modelID,
// deviceType, isContinuityCamera, manufacturer, transport, isSuspended, and every format
// (dimensions, pixel format FourCC, frame-rate ranges, isHighestPhotoQualitySupported is iOS only).
// Then the default, systemPreferredCamera and the authorization status. Watches connect and
// disconnect notifications and polls systemPreferredCamera for [seconds] (default 30), so plug
// the Brio in and out and wake or sleep the iPhone while it runs.
// Build with an Info.plist section that sets NSCameraUseContinuityCameraDeviceType, or the iPhone
// shows as builtInWideAngleCamera (AVCaptureDevice.h): pass -Xlinker -sectcreate -Xlinker __TEXT
// -Xlinker __info_plist -Xlinker r3-camera-info.plist.
import AVFoundation
import AppKit
setbuf(stdout, nil)

func fourCC(_ v: FourCharCode) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "\(v)"
}
let session = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
    mediaType: .video, position: .unspecified)
func dump() {
    for d in session.devices {
        print("\(d.localizedName) | id \(d.uniqueID) | model \(d.modelID) | type \(d.deviceType.rawValue) | continuity \(d.isContinuityCamera) | maker \(d.manufacturer) | transport \(fourCC(FourCharCode(bitPattern: d.transportType))) | suspended \(d.isSuspended)")
        print("  active: \(describe(d.activeFormat)) min frame \(d.activeVideoMinFrameDuration.seconds)")
        for f in d.formats { print("  format: \(describe(f))") }
    }
    print("default:", AVCaptureDevice.default(for: .video)?.localizedName ?? "none")
    print("systemPreferred:", AVCaptureDevice.systemPreferredCamera?.localizedName ?? "none",
          "userPreferred:", AVCaptureDevice.userPreferredCamera?.localizedName ?? "none")
    print("authorization:", AVCaptureDevice.authorizationStatus(for: .video).rawValue, "(0 notDetermined, 1 restricted, 2 denied, 3 authorized)")
    print("center stage enabled \(AVCaptureDevice.isCenterStageEnabled), portrait \(AVCaptureDevice.isPortraitEffectEnabled), reactions \(AVCaptureDevice.reactionEffectsEnabled)")
}
func describe(_ f: AVCaptureDevice.Format) -> String {
    let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
    let rates = f.videoSupportedFrameRateRanges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }.joined(separator: ",")
    return "\(dims.width)x\(dims.height) \(fourCC(CMFormatDescriptionGetMediaSubType(f.formatDescription))) fps \(rates)"
}
dump()
let nc = NotificationCenter.default
nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { n in
    print(Date(), "connected:", (n.object as? AVCaptureDevice)?.localizedName ?? "?")
}
nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { n in
    print(Date(), "disconnected:", (n.object as? AVCaptureDevice)?.localizedName ?? "?")
}
// systemPreferredCamera is a class property; it is polled once a second here instead of KVO.
var preferred = AVCaptureDevice.systemPreferredCamera?.uniqueID
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    let now = AVCaptureDevice.systemPreferredCamera
    if now?.uniqueID != preferred { preferred = now?.uniqueID; print(Date(), "systemPreferredCamera ->", now?.localizedName ?? "none") }
}
let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 30 : 30
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { print("--- after"); dump(); exit(0) }
RunLoop.main.run()
