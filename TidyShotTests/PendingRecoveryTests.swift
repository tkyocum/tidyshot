import Foundation
import Testing
@testable import TidyShot

/// Which files in `pending/` the launch step adopts (harness design 4.2): a `<UUID>.<png|mp4|gif>` that
/// no record's id names, in name order; any other name is left alone.
struct PendingRecoveryTests {
    let folder = URL(filePath: "/pending/", directoryHint: .isDirectory)

    func file(_ name: String) -> URL {
        folder.appending(path: name)
    }

    @Test func aUUIDNamedPNGWithNoRecordIsAnOrphan() {
        let id = UUID()
        let url = file("\(id.uuidString).png")
        #expect(PendingRecovery.orphans(listed: [url], recordIDs: [])
                == [PendingRecovery.Found(url: url, id: id, kind: .image)])
    }

    @Test func anMP4AndAGIFAreOrphansToo() {
        let movie = UUID()
        let gif = UUID()
        let found = PendingRecovery.orphans(listed: [file("\(movie.uuidString).mp4"), file("\(gif.uuidString).gif")],
                                            recordIDs: [])
        #expect(Set(found.map(\.id)) == [movie, gif])
        #expect(found.first { $0.id == movie }?.kind == .video)
        #expect(found.first { $0.id == gif }?.kind == .gif)
    }

    /// By id, so a trim's write (the record exists, its `fileURL` not yet set) is kept.
    @Test func aFileWhoseUUIDIsARecordsIDIsKept() {
        let id = UUID()
        #expect(PendingRecovery.orphans(listed: [file("\(id.uuidString).mp4")], recordIDs: [id]).isEmpty)
    }

    @Test func aNameThatIsNotAUUIDWithACaptureExtensionIsLeftAlone() {
        let id = UUID()
        let names = ["\(id.uuidString).png.sb-6c1d2a0f-Xy12Ab", ".\(id.uuidString).png", "\(id.uuidString).txt",
                     "notes.png", id.uuidString]
        #expect(PendingRecovery.orphans(listed: names.map { file($0) }, recordIDs: []).isEmpty)
    }

    @Test func theOrphansComeInNameOrder() {
        let urls = (0..<4).map { _ in file("\(UUID().uuidString).png") }
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Reversed from the sorted order, so the input is never in name order by chance.
        #expect(PendingRecovery.orphans(listed: sorted.reversed(), recordIDs: []).map(\.url) == sorted)
    }
}
