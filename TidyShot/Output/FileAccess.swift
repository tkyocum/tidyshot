import Foundation

extension URL {
    /// Runs `body` holding this URL's security scope, when it has one (a folder from a bookmark or
    /// an open panel); any other URL runs `body` as it is.
    nonisolated func withSecurityScope<T>(_ body: () throws -> T) rethrows -> T {
        let accessing = startAccessingSecurityScopedResource()
        defer { if accessing { stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

extension Optional<URL> {
    /// `URL.withSecurityScope` for a scope that may be absent: a file in `pending` needs none.
    nonisolated func withSecurityScope<T>(_ body: () throws -> T) rethrows -> T {
        guard let scope = self else { return try body() }
        return try scope.withSecurityScope(body)
    }

    /// `withSecurityScope` around an async read, held across its awaits.
    nonisolated func withSecurityScope<T>(_ body: () async throws -> T) async rethrows -> T {
        let accessing = self?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { self?.stopAccessingSecurityScopedResource() } }
        return try await body()
    }
}

extension FileManager {
    /// Removes the item at `url`. One that is already gone is not an error.
    nonisolated func removeItemIfPresent(at url: URL) throws {
        do {
            try removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {}
    }
}
