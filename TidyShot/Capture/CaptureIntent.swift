/// How one capture is finished (spec 2.9, URL scheme, Actions): the after-capture action, whether
/// the image only goes on the clipboard, and what opens afterwards. Hotkeys and the menu pass
/// `.standard`; a URL command's `action` makes the others. It travels through every capture
/// function into `AppCoordinator.save(_:intent:)`.
nonisolated struct CaptureIntent: Equatable, Sendable {
    enum Then: Equatable, Sendable {
        case none
        /// Open the editor on the new record.
        case annotate
        /// Open a pin of the new record.
        case pin
    }

    var action: AfterCaptureAction
    /// `action=copy`: the image goes on the clipboard and nothing else happens.
    var copyOnly: Bool
    var then: Then
    /// The app that sent the URL command, cleaned, for the notifications this capture posts. Nil
    /// for hotkeys, the menu and an unknown sender.
    var sender: String?

    init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil) {
        self.action = action
        self.copyOnly = copyOnly
        self.then = then
        self.sender = sender
    }

    /// What a URL command's `action` asks for, given the after-capture action in General.
    init(urlAction: URLCommand.Action?, setting: AfterCaptureAction, sender: String? = nil) {
        switch urlAction {
        case nil: self.init(action: setting, sender: sender)
        case .upload: self.init(action: setting == .uploadOnly ? .uploadOnly : .upload, sender: sender)
        case .save: self.init(action: .save, sender: sender)
        case .copy: self.init(action: setting, copyOnly: true, sender: sender)
        case .annotate: self.init(action: setting, then: .annotate, sender: sender)
        case .pin: self.init(action: setting, then: .pin, sender: sender)
        }
    }

    /// Hotkeys and the menu: the after-capture action in General, read when the capture starts.
    @MainActor static var standard: CaptureIntent {
        CaptureIntent(urlAction: nil, setting: AppSettings.shared.afterCaptureAction)
    }
}
