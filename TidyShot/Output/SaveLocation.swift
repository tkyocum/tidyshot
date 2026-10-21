import AppKit
import Observation

/// The user-chosen save folder, persisted as a security-scoped bookmark (required under App Sandbox).
@Observable
final class SaveLocation {
    private static let bookmarkKey = "saveFolderBookmark"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var currentURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentURL = Self.resolveBookmark(from: defaults)
    }

    func store(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: Self.bookmarkKey)
        currentURL = url
    }

    /// Asks the user to pick a folder. Returns nil if cancelled.
    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where TidyShot saves screenshots."
        panel.prompt = "Use This Folder"
        // Reached from a global hotkey while another app is active; a plain activate() can be
        // refused and the panel would open behind that app. Marked for future deprecation; no warning today.
        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        do {
            try store(url)
        } catch {
            NSLog("Could not store bookmark: \(error.localizedDescription)")
            return nil
        }
        return url
    }

    /// The stored folder, or a freshly chosen one.
    func ensureFolder() async -> URL? {
        if let currentURL { return currentURL }
        return await chooseFolder()
    }

    /// Writes `data` as `baseName.ext` (or `baseName 2.ext`, ...) inside `folder`, holding
    /// security-scoped access for both the uniqueness check and the write. Returns the file URL.
    func write(_ data: Data, baseName: String, ext: String, in folder: URL) throws -> URL {
        try withAccess(to: folder) {
            let url = FileNamer.uniqueURL(baseName: baseName, ext: ext, in: folder)
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    /// Reads a file inside the save folder (for upload retries), holding security-scoped access.
    func read(contentsOf fileURL: URL) throws -> Data {
        guard let currentURL else { throw CocoaError(.fileNoSuchFile) }
        return try withAccess(to: currentURL) {
            try Data(contentsOf: fileURL)
        }
    }

    /// Reads `fileURL` inside `folder`, holding that folder's security-scoped access for the read.
    /// Touches no instance state, so it can run off the main actor (thumbnail and preview loads).
    nonisolated static func readScoped(_ fileURL: URL, folder: URL) throws -> Data {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: fileURL)
    }

    /// True when `fileURL` lies inside `folder`, at any depth. Paths are compared component by
    /// component as written, with `.` and `..` applied. Symlinks are not resolved and the file
    /// system is not consulted, so a file reached through another spelling of the folder counts
    /// as outside, which only turns Save off.
    nonisolated static func contains(_ fileURL: URL, inFolder folder: URL) -> Bool {
        guard fileURL.isFileURL, folder.isFileURL else { return false }
        let file = lexicalComponents(of: fileURL)
        let base = lexicalComponents(of: folder)
        return file.count > base.count && file.starts(with: base)
    }

    /// Replaces `fileURL` with `data` atomically, holding `folder`'s security scope for the write.
    /// Throws `CocoaError(.fileWriteNoPermission)` for a file outside `folder`, so Save over never
    /// writes anywhere else. Touches no instance state, so it runs in a detached task.
    nonisolated static func overwriteScoped(_ data: Data, at fileURL: URL, folder: URL) throws {
        guard contains(fileURL, inFolder: folder) else {
            throw CocoaError(.fileWriteNoPermission,
                             userInfo: [NSLocalizedDescriptionKey: "\(fileURL.lastPathComponent) is not in the save folder."])
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        try data.write(to: fileURL, options: .atomic)
    }

    /// The path's components with `.` dropped and `..` applied, from the text alone.
    nonisolated private static func lexicalComponents(of url: URL) -> [String] {
        var parts: [String] = []
        for part in url.path(percentEncoded: false).split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(part))
            }
        }
        return parts
    }

    /// Deletes a file inside the save folder, holding security-scoped access. A file that is
    /// already gone is not an error; any other failure throws, and Delete then offers to remove the
    /// record from history and leave the file.
    func remove(at fileURL: URL) throws {
        guard let currentURL else {
            throw CocoaError(.fileWriteNoPermission,
                             userInfo: [NSLocalizedDescriptionKey: "No save folder is set, so TidyShot cannot reach this file."])
        }
        try withAccess(to: currentURL) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            }
        }
    }

    private func withAccess<T>(to folder: URL, _ body: () throws -> T) rethrows -> T {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    private static func resolveBookmark(from defaults: UserDefaults) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }
}
