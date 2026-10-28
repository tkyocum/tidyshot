import Testing
@testable import TidyShot

/// The bar's bubble button (design, Webcam bubble, Permission, The bar's button): enabled only with
/// a resolved camera, authorized access and a filmed window.
struct BubbleButtonStateTests {
    let brio = CameraDevice(uniqueID: "0x1200046d0943", name: "Brio 500")

    func disabled(_ toolTip: String) -> BubbleButtonState {
        BubbleButtonState(isEnabled: false, disabledToolTip: toolTip)
    }

    @Test func enabledWithACameraAuthorizedAccessAndAFilmedWindow() {
        #expect(BubbleButtonState.make(camera: brio, access: .authorized, filmed: true)
                == BubbleButtonState(isEnabled: true, disabledToolTip: nil))
    }

    /// Until Settings has asked once, the bar cannot turn the bubble on: the prompt would be filmed.
    @Test func notDeterminedAsksForSettings() {
        for camera in [brio, nil] {
            for filmed in [true, false] {
                #expect(BubbleButtonState.make(camera: camera, access: .notDetermined, filmed: filmed)
                        == disabled("Turn on Show webcam bubble in Settings to allow the camera."))
            }
        }
    }

    @Test(arguments: [CameraAccess.denied, .restricted])
    func accessOffSaysSo(_ access: CameraAccess) {
        for camera in [brio, nil] {
            for filmed in [true, false] {
                #expect(BubbleButtonState.make(camera: camera, access: access, filmed: filmed)
                        == disabled("Camera access is off for TidyShot."))
            }
        }
    }

    @Test func noCameraSaysSo() {
        for filmed in [true, false] {
            #expect(BubbleButtonState.make(camera: nil, access: .authorized, filmed: filmed)
                    == disabled("No camera is connected."))
        }
    }

    @Test func notFilmedIsNotAvailable() {
        #expect(BubbleButtonState.make(camera: brio, access: .authorized, filmed: false)
                == disabled("Not available for this recording"))
    }

    @Test func theStrings() {
        #expect(BubbleButtonState.allowInSettingsText == "Turn on Show webcam bubble in Settings to allow the camera.")
        #expect(BubbleButtonState.notAvailableText == "Not available for this recording")
    }
}
