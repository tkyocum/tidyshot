import Foundation
import Observation

enum AfterCaptureAction: String, CaseIterable, Identifiable {
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
        static let fileNameTemplate = "fileNameTemplate"
        static let counter = "captureCounter"
        static let afterCaptureAction = "afterCaptureAction"
        static let alsoCopyImageWhenUploading = "alsoCopyImageWhenUploading"
        static let showOverlay = "showOverlay"
        static let overlayCorner = "overlayCorner"
        static let overlayAutoCloseSeconds = "overlayAutoCloseSeconds"
        static let historyRetentionDays = "historyRetentionDays"
        static let s3Config = "s3DestinationConfig"
        static let editorStrokeColor = "editorStrokeColor"
        static let editorRedactColor = "editorRedactColor"
        static let editorLineWidthPoints = "editorLineWidthPoints"
        static let editorBlurRadiusPoints = "editorBlurRadiusPoints"
        static let editorPixelBlockPoints = "editorPixelBlockPoints"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: Keys.showsCursor) } }
    var copyImageToClipboard: Bool { didSet { defaults.set(copyImageToClipboard, forKey: Keys.copyImageToClipboard) } }
    var showNotification: Bool { didSet { defaults.set(showNotification, forKey: Keys.showNotification) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Keys.playSound) } }
    var fileNameTemplate: String { didSet { defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate) } }
    var afterCaptureAction: AfterCaptureAction { didSet { defaults.set(afterCaptureAction.rawValue, forKey: Keys.afterCaptureAction) } }
    var alsoCopyImageWhenUploading: Bool { didSet { defaults.set(alsoCopyImageWhenUploading, forKey: Keys.alsoCopyImageWhenUploading) } }
    var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Keys.showOverlay) } }
    var overlayCorner: OverlayCorner { didSet { defaults.set(overlayCorner.rawValue, forKey: Keys.overlayCorner) } }
    var overlayAutoCloseSeconds: Double { didSet { defaults.set(overlayAutoCloseSeconds, forKey: Keys.overlayAutoCloseSeconds) } }
    var historyRetentionDays: Int { didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) } }
    /// Nil until the Upload tab has been saved once. Stored as JSON.
    var s3Config: S3DestinationConfig? {
        didSet { storeS3Config() }
    }
    /// The annotation editor's last colours (sRGB, stored as JSON) and sizes in points. An editor
    /// reads them once, as `editorDefaults`, when it opens. There is no Settings tab for them.
    var editorStrokeColor: RGBA { didSet { storeColor(editorStrokeColor, forKey: Keys.editorStrokeColor) } }
    var editorRedactColor: RGBA { didSet { storeColor(editorRedactColor, forKey: Keys.editorRedactColor) } }
    var editorLineWidthPoints: Double { didSet { defaults.set(editorLineWidthPoints, forKey: Keys.editorLineWidthPoints) } }
    var editorBlurRadiusPoints: Double { didSet { defaults.set(editorBlurRadiusPoints, forKey: Keys.editorBlurRadiusPoints) } }
    var editorPixelBlockPoints: Double { didSet { defaults.set(editorPixelBlockPoints, forKey: Keys.editorPixelBlockPoints) } }

    /// The five editor values as one value. Setting it writes all five keys.
    var editorDefaults: EditorDefaults {
        get {
            EditorDefaults(strokeColor: editorStrokeColor, redactColor: editorRedactColor,
                           lineWidthPoints: CGFloat(editorLineWidthPoints),
                           blurRadiusPoints: CGFloat(editorBlurRadiusPoints),
                           blockPoints: CGFloat(editorPixelBlockPoints))
        }
        set {
            editorStrokeColor = newValue.strokeColor
            editorRedactColor = newValue.redactColor
            editorLineWidthPoints = Double(newValue.lineWidthPoints)
            editorBlurRadiusPoints = Double(newValue.blurRadiusPoints)
            editorPixelBlockPoints = Double(newValue.blockPoints)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.showsCursor: false,
            Keys.copyImageToClipboard: true,
            Keys.showNotification: true,
            Keys.playSound: true,
            Keys.fileNameTemplate: FileNamer.defaultTemplate,
            Keys.afterCaptureAction: AfterCaptureAction.upload.rawValue,
            Keys.alsoCopyImageWhenUploading: false,
            Keys.showOverlay: true,
            Keys.overlayCorner: OverlayCorner.bottomRight.rawValue,
            Keys.overlayAutoCloseSeconds: 5.0,
            Keys.historyRetentionDays: 30,
            Keys.editorLineWidthPoints: Double(EditorDefaults.standard.lineWidthPoints),
            Keys.editorBlurRadiusPoints: Double(EditorDefaults.standard.blurRadiusPoints),
            Keys.editorPixelBlockPoints: Double(EditorDefaults.standard.blockPoints),
        ])
        showsCursor = defaults.bool(forKey: Keys.showsCursor)
        copyImageToClipboard = defaults.bool(forKey: Keys.copyImageToClipboard)
        showNotification = defaults.bool(forKey: Keys.showNotification)
        playSound = defaults.bool(forKey: Keys.playSound)
        let storedFileNameTemplate = defaults.string(forKey: Keys.fileNameTemplate) ?? FileNamer.defaultTemplate
        fileNameTemplate = TemplateMigration.removingAppToken(from: storedFileNameTemplate, fallback: FileNamer.defaultTemplate)
        afterCaptureAction = AfterCaptureAction(rawValue: defaults.string(forKey: Keys.afterCaptureAction) ?? "") ?? .upload
        alsoCopyImageWhenUploading = defaults.bool(forKey: Keys.alsoCopyImageWhenUploading)
        showOverlay = defaults.bool(forKey: Keys.showOverlay)
        overlayCorner = OverlayCorner(rawValue: defaults.string(forKey: Keys.overlayCorner) ?? "") ?? .bottomRight
        overlayAutoCloseSeconds = defaults.double(forKey: Keys.overlayAutoCloseSeconds)
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
