import AppKit

enum SoundPlayer {
    private static let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
    private static let shutter = NSSound(contentsOfFile: shutterPath, byReference: true)

    /// Plays the system screenshot sound. Silent if the sound file is missing.
    static func playShutter() {
        shutter?.stop()
        shutter?.play()
    }
}
