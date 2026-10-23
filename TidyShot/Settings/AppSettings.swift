import Foundation
import Observation

nonisolated enum AfterCaptureAction: String, CaseIterable, Identifiable, Sendable {
    /// Save the file, upload it, and put the URL on the clipboard when the upload finishes.
    case upload
    /// Upload from a temporary file inside the app container, copy the URL, and delete the file
    /// once the upload succeeds. No save folder is needed; Recent Captures keeps a thumbnail.
    case uploadOnly
    /// Save the file and copy the image (Phase 1 behaviour).
    case save

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: "Upload and copy URL"
        case .uploadOnly: "Upload only, keep no local file"
        case .save: "Save and copy image"
        }
    }

    var uploads: Bool { self != .save }
}

/// User preferences, persisted in UserDefaults. Credentials are never stored here.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let showsCursor = "showsCursor"
        static let copyImageToClipboard = "copyImageToClipboard"
        static let showNotification = "showNotification"
        static let playSound = "playSound"
        static let confirmBeforeDeleting = "confirmBeforeDeleting"
        static let fileNameTemplate = "fileNameTemplate"
        static let counter = "captureCounter"
        static let afterCaptureAction = "afterCaptureAction"
        static let alsoCopyImageWhenUploading = "alsoCopyImageWhenUploading"
        static let showOverlay = "showOverlay"
        static let overlayCorner = "overlayCorner"
        static let overlayAutoCloseSeconds = "overlayAutoCloseSeconds"
        static let overlayDisplay = "overlayDisplay"
        static let overlayMaxCards = "overlayMaxCards"
        static let overlayCloseAfterDrag = "overlayCloseAfterDrag"
        static let historyRetentionDays = "historyRetentionDays"
        static let s3Config = "s3DestinationConfig"
        static let editorStrokeColor = "editorStrokeColor"
        static let editorRedactColor = "editorRedactColor"
        static let editorLineWidthPoints = "editorLineWidthPoints"
        static let editorBlurRadiusPoints = "editorBlurRadiusPoints"
        static let editorPixelBlockPoints = "editorPixelBlockPoints"
        static let editorSpotlightEllipse = "editorSpotlightEllipse"
        static let editorCounterDiameterPoints = "editorCounterDiameterPoints"
        static let scrollingAutoScroll = "scrollingAutoScroll"
        static let lastAreaRect = "lastAreaRect"
        static let windowShadow = "windowShadow"
        static let freezeScreen = "freezeScreen"
        static let urlCommandsEnabled = "urlCommandsEnabled"
        static let urlCommandsAllowSilent = "urlCommandsAllowSilent"
        static let selfTimerSeconds = "selfTimerSeconds"
        static let allInOneAspectLock = "allInOneAspectLock"
        static let optimiseWithClop = "optimiseWithClop"
        static let hideDesktopIconsWhileCapturing = "hideDesktopIconsWhileCapturing"
        static let desktopIconsHidden = "desktopIconsHidden"
        static let windowBackground = "windowBackground"
        static let backgroundStyle = "backgroundStyle"
        static let recordingFrameRate = "recordingFrameRate"
        static let recordingRetina = "recordingRetina"
        static let recordingSystemAudio = "recordingSystemAudio"
        static let recordingShowsCursor = "recordingShowsCursor"
        static let recordingCountdown = "recordingCountdown"
        static let recordingFileNameTemplate = "recordingFileNameTemplate"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Keys.showsCursor) } }
    var copyImageToClipboard: Bool { didSet { defaults.set(copyImageToClipboard, forKey: Keys.copyImageToClipboard) } }
    var showNotification: Bool { didSet { defaults.set(showNotification, forKey: Keys.showNotification) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Keys.playSound) } }
    /// General's `Ask before deleting` (spec 2.13). Off, Delete acts at once; the second alert,
    /// after something could not be deleted, still asks.
    var confirmBeforeDeleting: Bool { didSet { defaults.set(confirmBeforeDeleting, forKey: Keys.confirmBeforeDeleting) } }
    var fileNameTemplate: String { didSet { defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate) } }
    var afterCaptureAction: AfterCaptureAction { didSet { defaults.set(afterCaptureAction.rawValue, forKey: Keys.afterCaptureAction) } }
    var alsoCopyImageWhenUploading: Bool { didSet { defaults.set(alsoCopyImageWhenUploading, forKey: Keys.alsoCopyImageWhenUploading) } }
    var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Keys.showOverlay) } }
    var overlayCorner: OverlayCorner { didSet { defaults.set(overlayCorner.rawValue, forKey: Keys.overlayCorner) } }
    var overlayAutoCloseSeconds: Double { didSet { defaults.set(overlayAutoCloseSeconds, forKey: Keys.overlayAutoCloseSeconds) } }
    /// Which screen the card stack uses (Overlay tab, `Show on`).
    var overlayDisplay: OverlayDisplayChoice { didSet { defaults.set(overlayDisplay.rawValue, forKey: Keys.overlayDisplay) } }
    /// How many cards the stack shows at most (Overlay tab, `Show up to N overlays`).
    var overlayMaxCards: Int { didSet { defaults.set(overlayMaxCards, forKey: Keys.overlayMaxCards) } }
    static let overlayMaxCardsRange: ClosedRange<Int> = 1...8
    /// Close a Quick Access card once it was dragged out and dropped (Overlay tab).
    var overlayCloseAfterDrag: Bool { didSet { defaults.set(overlayCloseAfterDrag, forKey: Keys.overlayCloseAfterDrag) } }
    var historyRetentionDays: Int { didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) } }
    /// Nil until the Upload tab has been saved once. Stored as JSON.
    var s3Config: S3DestinationConfig? {
        didSet { storeS3Config() }
    }
    /// The annotation editor's last colours (sRGB, stored as JSON), sizes in points and spotlight
    /// shape. An editor reads them once, as `editorDefaults`, when it opens. There is no Settings
    /// tab for them.
    var editorStrokeColor: RGBA { didSet { storeColor(editorStrokeColor, forKey: Keys.editorStrokeColor) } }
    var editorRedactColor: RGBA { didSet { storeColor(editorRedactColor, forKey: Keys.editorRedactColor) } }
    var editorLineWidthPoints: Double { didSet { defaults.set(editorLineWidthPoints, forKey: Keys.editorLineWidthPoints) } }
    var editorBlurRadiusPoints: Double { didSet { defaults.set(editorBlurRadiusPoints, forKey: Keys.editorBlurRadiusPoints) } }
    var editorPixelBlockPoints: Double { didSet { defaults.set(editorPixelBlockPoints, forKey: Keys.editorPixelBlockPoints) } }
    var editorSpotlightEllipse: Bool { didSet { defaults.set(editorSpotlightEllipse, forKey: Keys.editorSpotlightEllipse) } }
    /// One of `EditorPalette.counterDiametersPoints`.
    var editorCounterDiameterPoints: Double {
        didSet { defaults.set(editorCounterDiameterPoints, forKey: Keys.editorCounterDiameterPoints) }
    }
    /// The scrolling panel's Scroll automatically checkbox. Effective only with the PostEvent grant.
    var scrollingAutoScroll: Bool { didSet { defaults.set(scrollingAutoScroll, forKey: Keys.scrollingAutoScroll) } }
    /// The rect of the last area capture (Capture Area, Capture Scrolling, and the later area
    /// kinds), for Capture Previous Area. Stored as JSON; nil until an area has been captured.
    var lastAreaRect: StoredRect? { didSet { storeLastAreaRect() } }
    /// The Capture tab's Include window shadow. Off keeps window shots without a shadow.
    var windowShadow: Bool { didSet { defaults.set(windowShadow, forKey: Keys.windowShadow) } }
    /// The Capture tab's Freeze screen while selecting (spec 2.9). Area selections then show a still image.
    var freezeScreen: Bool { didSet { defaults.set(freezeScreen, forKey: Keys.freezeScreen) } }
    /// General, URL commands: `Allow URL commands (tidyshot://)`. Off refuses every command.
    var urlCommandsEnabled: Bool { didSet { defaults.set(urlCommandsEnabled, forKey: Keys.urlCommandsEnabled) } }
    /// General, URL commands: `Allow URL commands that capture without a selection`
    /// (capture-fullscreen, capture-previous-area, capture-area or capture-text with a rect). Off by default.
    var urlCommandsAllowSilent: Bool { didSet { defaults.set(urlCommandsAllowSilent, forKey: Keys.urlCommandsAllowSilent) } }
    /// The Capture tab's Self-timer: seconds counted down before the capture. One of `selfTimerChoices`.
    var selfTimerSeconds: Int { didSet { defaults.set(selfTimerSeconds, forKey: Keys.selfTimerSeconds) } }
    static let selfTimerChoices = [3, 5, 10]
    /// All-in-One's aspect-ratio lock, as the toolbar last left it (spec 2.9).
    var allInOneAspectLock: Bool { didSet { defaults.set(allInOneAspectLock, forKey: Keys.allInOneAspectLock) } }
    /// The General tab's Optimize images and videos with Clop (spec 2.7). Takes effect without Save; used only
    /// while Clop is running.
    var optimiseWithClop: Bool { didSet { defaults.set(optimiseWithClop, forKey: Keys.optimiseWithClop) } }
    /// The Capture tab's Hide desktop icons while capturing (spec 2.10): the desktop is covered with
    /// its picture during area, window, fullscreen, previous-area, All-in-One and self-timer captures.
    var hideDesktopIconsWhileCapturing: Bool {
        didSet { defaults.set(hideDesktopIconsWhileCapturing, forKey: Keys.hideDesktopIconsWhileCapturing) }
    }
    /// The status menu's Hide Desktop Icons (spec 2.10): the desktop stays covered until turned off,
    /// also across launches. Set through `AppCoordinator.setDesktopIconsHidden(_:)`.
    var desktopIconsHidden: Bool { didSet { defaults.set(desktopIconsHidden, forKey: Keys.desktopIconsHidden) } }
    /// The Capture tab's Add background to window captures (spec 2.11): each window capture is put
    /// on `backgroundStyle` as it is saved.
    var windowBackground: Bool { didSet { defaults.set(windowBackground, forKey: Keys.windowBackground) } }
    /// The Capture tab's background style, which the editor's Background tool also starts from.
    /// Stored as JSON.
    var backgroundStyle: BackgroundStyle { didSet { storeBackgroundStyle() } }
    /// The Capture tab's Recording section: frames per second, one of `recordingFrameRates`.
    var recordingFrameRate: Int { didSet { defaults.set(recordingFrameRate, forKey: Keys.recordingFrameRate) } }
    static let recordingFrameRates = [30, 60]
    /// `Retina` records at the display's backing scale, `Standard` (false) at 1x.
    var recordingRetina: Bool { didSet { defaults.set(recordingRetina, forKey: Keys.recordingRetina) } }
    /// `Record system audio`.
    var recordingSystemAudio: Bool { didSet { defaults.set(recordingSystemAudio, forKey: Keys.recordingSystemAudio) } }
    /// `Show cursor in recordings`.
    var recordingShowsCursor: Bool { didSet { defaults.set(recordingShowsCursor, forKey: Keys.recordingShowsCursor) } }
    /// `Count down before recording`: the self-timer badge counts 3, 2, 1 before a recording starts.
    var recordingCountdown: Bool { didSet { defaults.set(recordingCountdown, forKey: Keys.recordingCountdown) } }
    /// General's `Recording file name`. An empty one names the file `Recording`.
    var recordingFileNameTemplate: String {
        didSet { defaults.set(recordingFileNameTemplate, forKey: Keys.recordingFileNameTemplate) }
    }

    /// The four Recording settings a recording's stream is made from.
    var recordingOptions: RecordingOptions {
        RecordingOptions(framesPerSecond: recordingFrameRate, retina: recordingRetina,
                         systemAudio: recordingSystemAudio, showsCursor: recordingShowsCursor)
    }

    /// The seven editor values as one value. Setting it writes all seven keys.
    var editorDefaults: EditorDefaults {
        get {
            EditorDefaults(strokeColor: editorStrokeColor, redactColor: editorRedactColor,
                           lineWidthPoints: CGFloat(editorLineWidthPoints),
                           blurRadiusPoints: CGFloat(editorBlurRadiusPoints),
                           blockPoints: CGFloat(editorPixelBlockPoints),
                           spotlightEllipse: editorSpotlightEllipse,
                           counterDiameterPoints: CGFloat(editorCounterDiameterPoints))
        }
        set {
            editorStrokeColor = newValue.strokeColor
            editorRedactColor = newValue.redactColor
            editorLineWidthPoints = Double(newValue.lineWidthPoints)
            editorBlurRadiusPoints = Double(newValue.blurRadiusPoints)
            editorPixelBlockPoints = Double(newValue.blockPoints)
            editorSpotlightEllipse = newValue.spotlightEllipse
            editorCounterDiameterPoints = Double(newValue.counterDiameterPoints)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.showsCursor: false,
            Keys.copyImageToClipboard: true,
            Keys.showNotification: true,
            Keys.playSound: true,
            Keys.confirmBeforeDeleting: true,
            Keys.fileNameTemplate: FileNamer.defaultTemplate,
            Keys.afterCaptureAction: AfterCaptureAction.upload.rawValue,
            Keys.alsoCopyImageWhenUploading: false,
            Keys.showOverlay: true,
            Keys.overlayCorner: OverlayCorner.bottomRight.rawValue,
            Keys.overlayAutoCloseSeconds: 5.0,
            Keys.overlayDisplay: OverlayDisplayChoice.capture.rawValue,
            Keys.overlayMaxCards: 5,
            Keys.overlayCloseAfterDrag: true,
            Keys.historyRetentionDays: 30,
            Keys.editorLineWidthPoints: Double(EditorDefaults.standard.lineWidthPoints),
            Keys.editorBlurRadiusPoints: Double(EditorDefaults.standard.blurRadiusPoints),
            Keys.editorPixelBlockPoints: Double(EditorDefaults.standard.blockPoints),
            Keys.editorSpotlightEllipse: EditorDefaults.standard.spotlightEllipse,
            Keys.editorCounterDiameterPoints: Double(EditorDefaults.standard.counterDiameterPoints),
            Keys.scrollingAutoScroll: true,
            Keys.windowShadow: false,
            Keys.freezeScreen: false,
            Keys.urlCommandsEnabled: true,
            Keys.urlCommandsAllowSilent: false,
            Keys.selfTimerSeconds: 5,
            Keys.allInOneAspectLock: false,
            Keys.optimiseWithClop: false,
            Keys.hideDesktopIconsWhileCapturing: false,
            Keys.desktopIconsHidden: false,
            Keys.windowBackground: false,
            Keys.recordingFrameRate: 30,
            Keys.recordingRetina: true,
            Keys.recordingSystemAudio: false,
            Keys.recordingShowsCursor: true,
            Keys.recordingCountdown: true,
            Keys.recordingFileNameTemplate: FileNamer.recordingDefaultTemplate,
        ])
        showsCursor = defaults.bool(forKey: Keys.showsCursor)
        copyImageToClipboard = defaults.bool(forKey: Keys.copyImageToClipboard)
        showNotification = defaults.bool(forKey: Keys.showNotification)
        playSound = defaults.bool(forKey: Keys.playSound)
        confirmBeforeDeleting = defaults.bool(forKey: Keys.confirmBeforeDeleting)
        let storedFileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? FileNamer.defaultTemplate
        fileNameTemplate = TemplateMigration.removingAppToken(from: storedFileNameTemplate, fallback: FileNamer.defaultTemplate)
        afterCaptureAction = AfterCaptureAction(rawValue: defaults.string(forKey: Keys.afterCaptureAction) ?? "") ?? .upload
        alsoCopyImageWhenUploading = defaults.bool(forKey: Keys.alsoCopyImageWhenUploading)
        showOverlay = defaults.bool(forKey: Keys.showOverlay)
        overlayCorner = OverlayCorner(rawValue: defaults.string(forKey: Keys.overlayCorner) ?? "") ?? .bottomRight
        overlayAutoCloseSeconds = defaults.double(forKey: Keys.overlayAutoCloseSeconds)
        overlayDisplay = OverlayDisplayChoice(rawValue: defaults.string(forKey: Keys.overlayDisplay) ?? "") ?? .capture
        overlayMaxCards = min(max(defaults.integer(forKey: Keys.overlayMaxCards), Self.overlayMaxCardsRange.lowerBound),
                              Self.overlayMaxCardsRange.upperBound)
        overlayCloseAfterDrag = defaults.bool(forKey: Keys.overlayCloseAfterDrag)
        historyRetentionDays = defaults.integer(forKey: Keys.historyRetentionDays)
        // Decoding drops `{app}` from the key template (see `S3DestinationConfig.init(from:)`).
        let storedConfig = defaults.data(forKey: Keys.s3Config)
        s3Config = storedConfig.flatMap { try? JSONDecoder().decode(S3DestinationConfig.self, from: $0) }
        // Colours are not registered: a missing or unreadable value means the default.
        editorStrokeColor = Self.storedColor(defaults.data(forKey: Keys.editorStrokeColor)) ?? EditorDefaults.standard.strokeColor
        editorRedactColor = Self.storedColor(defaults.data(forKey: Keys.editorRedactColor)) ?? EditorDefaults.standard.redactColor
        editorLineWidthPoints = defaults.double(forKey: Keys.editorLineWidthPoints)
        editorBlurRadiusPoints = defaults.double(forKey: Keys.editorBlurRadiusPoints)
        editorPixelBlockPoints = defaults.double(forKey: Keys.editorPixelBlockPoints)
        editorSpotlightEllipse = defaults.bool(forKey: Keys.editorSpotlightEllipse)
        let storedCounterDiameter = defaults.double(forKey: Keys.editorCounterDiameterPoints)
        editorCounterDiameterPoints = EditorPalette.counterDiametersPoints.contains(CGFloat(storedCounterDiameter))
            ? storedCounterDiameter : Double(EditorPalette.defaultCounterDiameterPoints)
        scrollingAutoScroll = defaults.bool(forKey: Keys.scrollingAutoScroll)
        // Not registered: a missing or unreadable value means no previous area.
        lastAreaRect = defaults.data(forKey: Keys.lastAreaRect).flatMap { try? JSONDecoder().decode(StoredRect.self, from: $0) }
        windowShadow = defaults.bool(forKey: Keys.windowShadow)
        freezeScreen = defaults.bool(forKey: Keys.freezeScreen)
        urlCommandsEnabled = defaults.bool(forKey: Keys.urlCommandsEnabled)
        urlCommandsAllowSilent = defaults.bool(forKey: Keys.urlCommandsAllowSilent)
        let storedSelfTimer = defaults.integer(forKey: Keys.selfTimerSeconds)
        selfTimerSeconds = Self.selfTimerChoices.contains(storedSelfTimer) ? storedSelfTimer : 5
        allInOneAspectLock = defaults.bool(forKey: Keys.allInOneAspectLock)
        optimiseWithClop = defaults.bool(forKey: Keys.optimiseWithClop)
        hideDesktopIconsWhileCapturing = defaults.bool(forKey: Keys.hideDesktopIconsWhileCapturing)
        desktopIconsHidden = defaults.bool(forKey: Keys.desktopIconsHidden)
        windowBackground = defaults.bool(forKey: Keys.windowBackground)
        let storedFrameRate = defaults.integer(forKey: Keys.recordingFrameRate)
        recordingFrameRate = Self.recordingFrameRates.contains(storedFrameRate) ? storedFrameRate : 30
        recordingRetina = defaults.bool(forKey: Keys.recordingRetina)
        recordingSystemAudio = defaults.bool(forKey: Keys.recordingSystemAudio)
        recordingShowsCursor = defaults.bool(forKey: Keys.recordingShowsCursor)
        recordingCountdown = defaults.bool(forKey: Keys.recordingCountdown)
        recordingFileNameTemplate = defaults.string(forKey: Keys.recordingFileNameTemplate) ?? FileNamer.recordingDefaultTemplate
        // Not registered: a missing value, or one that does not decode (a fill or aspect from a
        // newer build), means the default style.
        backgroundStyle = defaults.data(forKey: Keys.backgroundStyle)
            .flatMap { try? JSONDecoder().decode(BackgroundStyle.self, from: $0) } ?? BackgroundStyle()

        // Property observers do not run during init, so templates rewritten by
        // `TemplateMigration` are stored here, once.
        if fileNameTemplate != storedFileNameTemplate {
            defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate)
        }
        if let storedConfig, s3Config != nil,
           String(decoding: storedConfig, as: UTF8.self).contains(TemplateMigration.removedAppToken) {
            storeS3Config()
        }
    }

    /// Writes `s3Config` as JSON, or removes it when nil. An encoding failure is logged and leaves
    /// the stored value as it was: `try?` would have stored nil, which deletes the key and with it
    /// the destination.
    private func storeS3Config() {
        guard let s3Config else {
            defaults.removeObject(forKey: Keys.s3Config)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(s3Config), forKey: Keys.s3Config)
        } catch {
            NSLog("Upload settings could not be encoded, so the stored ones are kept: \(error.localizedDescription)")
        }
    }

    /// Writes `lastAreaRect` as JSON, or removes it when nil. An encoding failure is logged and
    /// leaves the stored value as it was.
    private func storeLastAreaRect() {
        guard let lastAreaRect else {
            defaults.removeObject(forKey: Keys.lastAreaRect)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(lastAreaRect), forKey: Keys.lastAreaRect)
        } catch {
            NSLog("The last area could not be encoded, so the stored one is kept: \(error.localizedDescription)")
        }
    }

    /// Writes `backgroundStyle` as JSON. An encoding failure is logged and leaves the stored value
    /// as it was.
    private func storeBackgroundStyle() {
        do {
            defaults.set(try JSONEncoder().encode(backgroundStyle), forKey: Keys.backgroundStyle)
        } catch {
            NSLog("The background style could not be encoded, so the stored one is kept: \(error.localizedDescription)")
        }
    }

    /// An `RGBA` written by `storeColor(_:forKey:)`, or nil when there is none or it does not decode.
    private static func storedColor(_ data: Data?) -> RGBA? {
        data.flatMap { try? JSONDecoder().decode(RGBA.self, from: $0) }
    }

    /// Writes `color` as JSON. An encoding failure is logged and leaves the stored value as it was.
    private func storeColor(_ color: RGBA, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(color), forKey: key)
        } catch {
            NSLog("An editor colour could not be encoded, so the stored one is kept: \(error.localizedDescription)")
        }
    }

    /// The persistent capture counter as it stands, without drawing the next one. The editor's
    /// Save As… suggestion uses it.
    var currentCounter: Int {
        defaults.integer(forKey: Keys.counter)
    }

    /// Increments and returns the persistent capture counter used by the {counter} token.
    func nextCounter() -> Int {
        let next = defaults.integer(forKey: Keys.counter) + 1
        defaults.set(next, forKey: Keys.counter)
        return next
    }
}
