import AVFoundation
import CoreGraphics
import Testing
@testable import TidyShot

/// The `Camera` setting and the camera a recording starts with (design, Webcam bubble, Settings,
/// Permission and Under the lock), over a device list and an access the tests choose.
struct CameraChoiceTests {
    let builtIn = CameraDevice(uniqueID: "BuiltInCamera", name: "MacBook Pro Camera")
    let brio = CameraDevice(uniqueID: "0x1200046d0943", name: "Brio 500")
    let iPhone = CameraDevice(uniqueID: "ContinuityCamera:TKY", name: "TKY Camera")

    var devices: [CameraDevice] { [builtIn, brio, iPhone] }
    /// The Brio, stored and then unplugged.
    var missingBrio: CameraChoice.Stored { .device(id: brio.uniqueID, name: "Brio 500") }

    var accessNote: RecordingNotice {
        RecordingNotice(title: "Recorded without the webcam bubble", body: "Camera access is off for TidyShot.")
    }

    func resolve(_ stored: CameraChoice.Stored, access: CameraAccess = .authorized, devices: [CameraDevice],
                 preferred: CameraDevice?) -> CameraStart {
        CameraChoice.resolveAtStart(stored: stored, access: { access }, devices: { devices }, preferred: { preferred })
    }

    // MARK: Stored values

    @Test func storedValuesParseFromTheTwoSettings() {
        #expect(CameraChoice.Stored(value: "default", name: "") == .systemDefault)
        #expect(CameraChoice.Stored(value: "default", name: "Brio 500") == .systemDefault)
        #expect(CameraChoice.Stored(value: "", name: "") == .systemDefault)
        #expect(CameraChoice.Stored(value: "", name: "Brio 500") == .systemDefault)
        #expect(CameraChoice.Stored(value: brio.uniqueID, name: "Brio 500") == .device(id: brio.uniqueID, name: "Brio 500"))
        #expect(CameraChoice.Stored(value: brio.uniqueID, name: "") == .device(id: brio.uniqueID, name: ""))
    }

    @Test func aStoredChoiceGivesBackTheTwoSettings() {
        #expect(CameraChoice.Stored.systemDefault.value == "default")
        #expect(CameraChoice.Stored.systemDefault.name == "")
        #expect(missingBrio.value == brio.uniqueID)
        #expect(missingBrio.name == "Brio 500")
        for stored in [CameraChoice.Stored.systemDefault, missingBrio, .device(id: iPhone.uniqueID, name: "")] {
            #expect(CameraChoice.Stored(value: stored.value, name: stored.name) == stored)
        }
    }

    // MARK: The start

    @Test func systemDefaultTakesThePreferredCamera() {
        #expect(resolve(.systemDefault, devices: devices, preferred: iPhone)
                == CameraStart(camera: iPhone, access: .authorized, note: nil))
    }

    @Test func aPresentDeviceTakesThatCamera() {
        #expect(resolve(.device(id: brio.uniqueID, name: "Brio 500"), devices: devices, preferred: iPhone)
                == CameraStart(camera: brio, access: .authorized, note: nil))
    }

    /// The listed camera is taken with its listed name, not the stored one.
    @Test func aPresentDeviceStoredUnderAnOldNameTakesTheListedCamera() {
        #expect(resolve(.device(id: brio.uniqueID, name: "Old name"), devices: devices, preferred: iPhone).camera == brio)
    }

    @Test func aMissingDeviceTakesThePreferredCameraAndSaysSo() {
        let start = resolve(missingBrio, devices: [builtIn, iPhone], preferred: iPhone)
        #expect(start == CameraStart(camera: iPhone, access: .authorized,
                                     note: RecordingNotice(title: "Recorded with TKY Camera", body: "Brio 500 is not connected.")))
        #expect(CameraChoice.entries(stored: missingBrio, devices: [builtIn, iPhone]).last
                == CameraChoice.Entry(tag: brio.uniqueID, title: "Brio 500 (not connected)"))
    }

    @Test func aMissingDeviceWithNoStoredNameIsAnUnknownCamera() {
        let stored = CameraChoice.Stored.device(id: brio.uniqueID, name: "")
        let start = resolve(stored, devices: [builtIn], preferred: builtIn)
        #expect(start == CameraStart(camera: builtIn, access: .authorized,
                                     note: RecordingNotice(title: "Recorded with MacBook Pro Camera",
                                                           body: "Unknown camera is not connected.")))
        #expect(CameraChoice.entries(stored: stored, devices: [builtIn]).last
                == CameraChoice.Entry(tag: brio.uniqueID, title: "Unknown camera (not connected)"))
    }

    /// The preferred camera counts as present when the discovery session leaves it out.
    @Test func theStoredPreferredCameraCountsAsPresentWhenTheListLeavesItOut() {
        #expect(resolve(missingBrio, devices: [builtIn], preferred: brio)
                == CameraStart(camera: brio, access: .authorized, note: nil))
    }

    @Test func systemDefaultWithNoCameraTakesNone() {
        #expect(resolve(.systemDefault, devices: [], preferred: nil)
                == CameraStart(camera: nil, access: .authorized,
                               note: RecordingNotice(title: "Recorded without the webcam bubble", body: "No camera is connected.")))
    }

    @Test func aMissingDeviceWithNoCameraTakesNoneAndNamesIt() {
        #expect(resolve(missingBrio, devices: [], preferred: nil)
                == CameraStart(camera: nil, access: .authorized,
                               note: RecordingNotice(title: "Recorded without the webcam bubble", body: "Brio 500 is not connected.")))
        #expect(resolve(.device(id: brio.uniqueID, name: ""), devices: [], preferred: nil).note
                == RecordingNotice(title: "Recorded without the webcam bubble", body: "Unknown camera is not connected."))
    }

    /// Without access no camera is taken and the note says so; the choice and the toggle are kept,
    /// so the row still shows the note (`.denied`, `.restricted`) or the next start asks
    /// (`.notDetermined`).
    @Test(arguments: [CameraAccess.denied, .restricted, .notDetermined])
    func accessNotAuthorizedTakesNoCameraAndGivesTheAccessNote(_ access: CameraAccess) {
        for stored in [CameraChoice.Stored.systemDefault, .device(id: brio.uniqueID, name: "Brio 500"), missingBrio] {
            #expect(resolve(stored, access: access, devices: devices, preferred: iPhone)
                    == CameraStart(camera: nil, access: access, note: accessNote))
        }
        // Not authorized and no camera: the access note, not the missing camera's.
        #expect(resolve(missingBrio, access: access, devices: [], preferred: nil).note == accessNote)
        #expect(CameraChoice.asksForAccess(bubble: true, access: access) == (access == .notDetermined))
        #expect(CameraChoice.showsAccessNote(bubble: true, access: access) == (access != .notDetermined))
    }

    /// The access is read first; only with it are the cameras listed, so a start without it runs
    /// no discovery session under the capture lock.
    @Test(arguments: [CameraAccess.authorized, .denied, .restricted, .notDetermined])
    func theStartReadsTheAccessFirstAndTheCamerasOnlyWithIt(_ access: CameraAccess) {
        var reads: [String] = []
        let start = CameraChoice.resolveAtStart(stored: .device(id: brio.uniqueID, name: "Brio 500"),
                                                access: { reads.append("access"); return access },
                                                devices: { reads.append("devices"); return devices },
                                                preferred: { reads.append("preferred"); return iPhone })
        if access == .authorized {
            #expect(reads.first == "access")
            #expect(reads.contains("devices"))
            #expect(start == CameraStart(camera: brio, access: .authorized, note: nil))
        } else {
            #expect(reads == ["access"])
            #expect(start == CameraStart(camera: nil, access: access, note: accessNote))
        }
        reads = []
        _ = CameraChoice.resolveAtStart(stored: .systemDefault, access: { reads.append("access"); return access },
                                        devices: { reads.append("devices"); return devices },
                                        preferred: { reads.append("preferred"); return iPhone })
        #expect(reads.first == "access")
        #expect(access == .authorized || reads == ["access"])
    }

    @Test func aRefusedPromptTakesNoCameraAndGivesTheAccessNote() async {
        let cameras = FakeCameraDevices(devices: devices, preferredCamera: iPhone, access: .notDetermined, grants: false)
        #expect(CameraChoice.asksForAccess(bubble: true, access: cameras.access()))
        #expect(await cameras.requestAccess() == false)
        #expect(cameras.requestCount == 1)
        let start = CameraChoice.resolveAtStart(stored: .systemDefault, access: { cameras.access() },
                                                devices: { cameras.list() }, preferred: { cameras.preferred() })
        #expect(start == CameraStart(camera: nil, access: .denied, note: accessNote))
        // The toggle is kept, and the row shows the note.
        #expect(CameraChoice.showsAccessNote(bubble: true, access: cameras.access()))
    }

    @Test func aGrantedPromptTakesTheCamera() async {
        let cameras = FakeCameraDevices(devices: devices, preferredCamera: iPhone, access: .notDetermined, grants: true)
        #expect(await cameras.requestAccess())
        let start = CameraChoice.resolveAtStart(stored: .systemDefault, access: { cameras.access() },
                                                devices: { cameras.list() }, preferred: { cameras.preferred() })
        #expect(start == CameraStart(camera: iPhone, access: .authorized, note: nil))
    }

    // MARK: The hand-off

    var starts: [CameraStart] {
        [CameraStart(camera: brio, access: .authorized, note: nil),
         CameraStart(camera: iPhone, access: .authorized,
                     note: RecordingNotice(title: "Recorded with TKY Camera", body: "Brio 500 is not connected.")),
         CameraStart(camera: nil, access: .denied, note: accessNote)]
    }

    var display: RecordingDisplay { RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2) }

    /// There is no format argument: a GIF start resolves as an MP4 one, so a GIF keeps the choice
    /// (unlike the microphone).
    @Test func anAreaOrFullscreenRecordingKeepsTheCameraAndItsNote() {
        for start in starts {
            #expect(CameraChoice.forRecording(start, source: .area(CGRect(x: 10, y: 10, width: 400, height: 300), on: display))
                    == start)
            #expect(CameraChoice.forRecording(start, source: .display(display)) == start)
        }
    }

    @Test func aWindowRecordingDropsTheCameraAndItsNote() {
        for start in starts {
            let dropped = CameraChoice.forRecording(start, source: .window(id: 42, frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                                           scale: 2))
            #expect(dropped.camera == nil)
            #expect(dropped.note == nil)
        }
    }

    // MARK: Asking and the note in Settings

    @Test func onlyTheToggleOnAsksWhileAccessIsNotDetermined() {
        for access in [CameraAccess.authorized, .denied, .restricted, .notDetermined] {
            #expect(!CameraChoice.asksForAccess(bubble: false, access: access))
            #expect(CameraChoice.asksForAccess(bubble: true, access: access) == (access == .notDetermined))
        }
    }

    @Test func theAccessNoteShowsOnlyWithTheToggleOnAndAccessDeniedOrRestricted() {
        for access in [CameraAccess.authorized, .denied, .restricted, .notDetermined] {
            #expect(!CameraChoice.showsAccessNote(bubble: false, access: access))
            #expect(CameraChoice.showsAccessNote(bubble: true, access: access) == (access == .denied || access == .restricted))
        }
        #expect(CameraChoice.accessOffText == "Camera access is off for TidyShot.")
        #expect(CameraChoice.privacySettingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    // MARK: The pop-up

    @Test func theEntriesAreSystemDefaultThenEachCamera() {
        let expected = [
            CameraChoice.Entry(tag: "default", title: "System Default"),
            CameraChoice.Entry(tag: builtIn.uniqueID, title: "MacBook Pro Camera"),
            CameraChoice.Entry(tag: brio.uniqueID, title: "Brio 500"),
            CameraChoice.Entry(tag: iPhone.uniqueID, title: "TKY Camera"),
        ]
        #expect(CameraChoice.entries(stored: .systemDefault, devices: devices) == expected)
        // A present stored camera is listed once, under its own name.
        #expect(CameraChoice.entries(stored: .device(id: brio.uniqueID, name: "Old name"), devices: devices) == expected)
        #expect(CameraChoice.entries(stored: .systemDefault, devices: [])
                == [CameraChoice.Entry(tag: "default", title: "System Default")])
    }

    @Test func aMissingStoredCameraStaysTheSelectionAfterTheCameras() {
        #expect(CameraChoice.entries(stored: missingBrio, devices: [builtIn]) == [
            CameraChoice.Entry(tag: "default", title: "System Default"),
            CameraChoice.Entry(tag: builtIn.uniqueID, title: "MacBook Pro Camera"),
            CameraChoice.Entry(tag: brio.uniqueID, title: "Brio 500 (not connected)"),
        ])
        // Plugging it in again restores it.
        #expect(CameraChoice.entries(stored: missingBrio, devices: devices).contains(
            CameraChoice.Entry(tag: brio.uniqueID, title: "Brio 500")))
    }

    /// The list is the three device types, so the pop-up has no Desk View. A constant: nothing
    /// lists or opens a camera.
    @Test func theListLeavesOutDeskView() {
        #expect(LiveCameraDevices.deviceTypes == [.builtInWideAngleCamera, .external, .continuityCamera])
        #expect(!LiveCameraDevices.deviceTypes.contains(.deskViewCamera))
        #expect(LiveCameraDevices.changeNotifications
                == [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification])
    }

    // MARK: A pick, and the name refreshed

    @Test func aPickOfSystemDefaultStoresIt() {
        #expect(CameraChoice.pick(tag: "default", devices: devices, stored: missingBrio) == .systemDefault)
    }

    @Test func aPickOfAListedCameraStoresItsListedName() {
        #expect(CameraChoice.pick(tag: brio.uniqueID, devices: devices, stored: .systemDefault)
                == .device(id: brio.uniqueID, name: "Brio 500"))
        // Renamed since it was stored: the list's name.
        #expect(CameraChoice.pick(tag: brio.uniqueID, devices: devices, stored: .device(id: brio.uniqueID, name: "Old name"))
                == .device(id: brio.uniqueID, name: "Brio 500"))
    }

    /// The `(not connected)` entry picked again keeps the stored name.
    @Test func aPickOfTheMissingStoredCameraKeepsItsStoredName() {
        #expect(CameraChoice.pick(tag: brio.uniqueID, devices: [builtIn], stored: missingBrio) == missingBrio)
        #expect(CameraChoice.pick(tag: brio.uniqueID, devices: [builtIn], stored: .device(id: brio.uniqueID, name: ""))
                == .device(id: brio.uniqueID, name: ""))
    }

    @Test func aRenamedCameraGivesItsListedName() {
        #expect(CameraChoice.refreshedName(stored: .device(id: brio.uniqueID, name: "Old name"), devices: devices) == "Brio 500")
        #expect(CameraChoice.refreshedName(stored: .device(id: brio.uniqueID, name: ""), devices: devices) == "Brio 500")
    }

    @Test func aListedOrMissingCameraOrSystemDefaultGivesNoNewName() {
        #expect(CameraChoice.refreshedName(stored: .device(id: brio.uniqueID, name: "Brio 500"), devices: devices) == nil)
        #expect(CameraChoice.refreshedName(stored: missingBrio, devices: [builtIn]) == nil)
        #expect(CameraChoice.refreshedName(stored: .systemDefault, devices: devices) == nil)
    }

    // MARK: Strings

    @Test func theStrings() {
        #expect(CameraChoice.systemDefaultValue == "default")
        #expect(CameraChoice.systemDefaultTitle == "System Default")
        #expect(CameraChoice.unknownName == "Unknown camera")
        #expect(CameraChoice.recordedWithoutTitle == "Recorded without the webcam bubble")
        #expect(CameraChoice.noCameraText == "No camera is connected.")
        #expect(CameraChoice.couldNotStartText == "The camera could not be started.")
        #expect(CameraChoice.notFilmedText == "The bubble could not be filmed.")
        #expect(CameraChoice.recordedWithTitle("Brio 500") == "Recorded with Brio 500")
        #expect(CameraChoice.notConnectedText("Brio 500") == "Brio 500 is not connected.")
        #expect(CameraChoice.notConnectedText("") == "Unknown camera is not connected.")
    }
}
