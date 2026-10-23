import Foundation

// Trim (design, Trim): what the card and the row offer for a recording. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// Whether an upload destination is set up, for `Trim…`, the sheet and `Upload Trimmed` (plan,
    /// Gap 9). It never reads the keychain: the write itself calls `makeDestination()`.
    var hasUploadDestination: Bool {
        settings.s3Config?.isComplete == true
    }

    /// The card's and the row's Trim items for `record`, from the save folder, the destination and
    /// whether the record is being deleted or trimmed.
    func trimMenuState(for record: CaptureRecord) -> RecordingTrim.MenuState {
        RecordingTrim.menuState(record, saveFolder: saveLocation.currentURL, hasDestination: hasUploadDestination,
                                isDeleting: deletingIDs.contains(record.id), isTrimming: trimmingIDs.contains(record.id))
    }
}
