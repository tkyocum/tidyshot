import CoreGraphics

/// How a new frame relates to the last accepted one (spec 2.8, Overlap finder).
nonisolated enum OverlapMatch: Equatable, Sendable {
    /// Nothing that matters moved.
    case still
    /// The content moved up by `dy` rows: row y of the new frame shows row y + dy of the old one.
    /// A negative `dy` is a scroll back up. Rows before `top` are a sticky header and rows from
    /// `bandEnd` on a sticky footer.
    case moved(dy: Int, top: Int, bandEnd: Int, score: Double)
    /// No believable overlap (scrolled further than the band, or nothing to match on).
    case lost
}

/// Finds how far the content of a frame moved relative to the previous frame. Pure.
nonisolated struct OverlapFinder: Sendable {
    /// The rightmost columns that are never hashed.
    var scrollbarColumns: Int
    /// A row hash seen more often than this in a band is uninformative (blank rows, rules, list items).
    var maxRepeat = 4
    /// This fraction of the informative rows equal at the same y, between the leading and the
    /// trailing run of equal rows, means nothing moved.
    var stillFraction = 0.9
    /// A row still counts as equal when at most this many of its stripes differ, and none of the
    /// differing stripe cells shows content the other frame has at another row.
    var stillTolerance = 2
    /// A candidate shift needs this fraction of its informative cells to agree.
    var acceptScore = 0.8
    var minInformativeRows = 8
    /// The header and the footer are each at most this fraction of the frame.
    var maxStaticFraction = 0.4
    /// Each row of the band is hashed in this many vertical stripes, so an animated element
    /// spoils one stripe of the rows it covers instead of whole rows.
    var stripes = 8

    init(scale: CGFloat = 2) {
        scrollbarColumns = Int((ScrollCaptureLimits.scrollbarStripPoints * scale).rounded())
    }

    init(scrollbarColumns: Int) {
        self.scrollbarColumns = scrollbarColumns
    }

    func find(previous a: ScrollFrame, current b: ScrollFrame, predicted: Int?) -> OverlapMatch {
        guard a.width == b.width, a.height == b.height else { return .lost }
        let h = a.height
        let usable = Array(0..<max(1, a.width - scrollbarColumns))

        // 1. Still: informative rows equal at the same y, counted only between the leading and the
        // trailing run of equal rows. A sticky header or footer is equal in both frames whatever
        // happened, so counting it would read a small scroll of a sparse page as still. A row is
        // equal when all but `stillTolerance` of its stripes are, so a spinner, caret or GIF in the
        // band does not break the runs or count as movement; but a differing stripe that shows what the
        // other frame has at another row is a scroll of a narrow column, which is not equal.
        let fa = rowHashes(a, columns: usable), fb = rowHashes(b, columns: usable)
        // Identical rows throughout: nothing to look at, and the stripe hashes are not worth computing.
        if !fa.indices.contains(where: { fa[$0] != fb[$0] }) { return .still }
        let freqA = counts(fa[...])
        let stripeColumns = stripeGroups(usable)
        let sa = stripeColumns.map { rowHashes(a, columns: $0) }, sb = stripeColumns.map { rowHashes(b, columns: $0) }
        let stripeFreqA = sa.map { counts($0[...]) }, stripeFreqB = sb.map { counts($0[...]) }
        func equal(_ y: Int) -> Bool {
            if fa[y] == fb[y] { return true }
            var differing = 0
            for g in 0..<sa.count where sa[g][y] != sb[g][y] {
                // A stripe cell that shows content the other frame has at another row moved: that is a
                // scroll (perhaps of a narrow column), not an animation, so the row is not equal.
                if let n = stripeFreqA[g][sb[g][y]], n <= maxRepeat { return false }
                if let n = stripeFreqB[g][sa[g][y]], n <= maxRepeat { return false }
                differing += 1
            }
            return differing <= stillTolerance
        }
        var lead = 0
        while lead < h && equal(lead) { lead += 1 }
        if lead == h { return .still }
        var trail = 0
        while trail < h - lead && equal(h - 1 - trail) { trail += 1 }
        var informative = 0, same = 0
        for y in lead..<(h - trail) where freqA[fa[y]]! <= maxRepeat {
            informative += 1
            if equal(y) { same += 1 }
        }
        if informative == 0 || Double(same) / Double(informative) >= stillFraction { return .still }

        // 2. Moving columns: drop columns identical at the same position in every row (fixed sidebars).
        var moving: [Int] = []
        a.gray.withUnsafeBufferPointer { pa in
            b.gray.withUnsafeBufferPointer { pb in
                for x in usable {
                    var y = 0
                    while y < h && pa[y * a.width + x] == pb[y * a.width + x] { y += 1 }
                    if y < h { moving.append(x) }
                }
            }
        }
        if moving.isEmpty { return .still }
        let groups = stripeGroups(moving)
        let ha = groups.map { rowHashes(a, columns: $0) }, hb = groups.map { rowHashes(b, columns: $0) }
        let whole = rowHashes(a, columns: moving), wholeB = rowHashes(b, columns: moving)

        // 3. Header and footer: rows equal at the same y from each edge.
        let cap = Int(Double(h) * maxStaticFraction)
        var top = 0
        while top < cap && whole[top] == wholeB[top] { top += 1 }
        var bottom = 0
        while bottom < cap && whole[h - 1 - bottom] == wholeB[h - 1 - bottom] { bottom += 1 }
        let bandEnd = h - bottom
        guard bandEnd - top >= 16 else { return .lost }

        // 4. Vote per stripe cell: B[y] == A[y + dy].
        var votes: [Int: Int] = [:]
        var freqs: [[UInt64: Int]] = []
        for s in 0..<groups.count {
            let freq = counts(ha[s][top..<bandEnd])
            freqs.append(freq)
            var index: [UInt64: [Int]] = [:]
            for y in top..<bandEnd where freq[ha[s][y]]! <= maxRepeat { index[ha[s][y], default: []].append(y) }
            for y in top..<bandEnd {
                guard let ys = index[hb[s][y]] else { continue }
                for ya in ys where ya != y { votes[ya - y, default: 0] += 1 }
            }
        }
        // Most votes, then closest to the prediction, then the smaller shift, then forward.
        let ranked = votes.sorted { l, r in
            if l.value != r.value { return l.value > r.value }
            if let p = predicted, abs(l.key - p) != abs(r.key - p) { return abs(l.key - p) < abs(r.key - p) }
            if abs(l.key) != abs(r.key) { return abs(l.key) < abs(r.key) }
            return l.key > r.key
        }

        // 5. Verify the best few candidates over every informative cell of the overlap.
        for (dy, _) in ranked.prefix(5) {
            var inf = 0, ok = 0
            for s in 0..<groups.count {
                for y in top..<bandEnd {
                    let ya = y + dy
                    guard ya >= top, ya < bandEnd else { continue }
                    guard (freqs[s][ha[s][ya]] ?? 0) <= maxRepeat else { continue }
                    inf += 1
                    if ha[s][ya] == hb[s][y] { ok += 1 }
                }
            }
            guard inf >= minInformativeRows * groups.count / 2 else { continue }
            let score = Double(ok) / Double(inf)
            if score >= acceptScore { return .moved(dy: dy, top: top, bandEnd: bandEnd, score: score) }
        }
        return .lost
    }

    /// `columns` cut into at most `stripes` runs of neighbouring columns.
    private func stripeGroups(_ columns: [Int]) -> [[Int]] {
        let per = max(1, (columns.count + stripes - 1) / stripes)
        return stride(from: 0, to: columns.count, by: per).map { Array(columns[$0..<min(columns.count, $0 + per)]) }
    }

    /// FNV-1a (64 bit) of each row over `columns` of the grey plane.
    private func rowHashes(_ f: ScrollFrame, columns: [Int]) -> [UInt64] {
        var out = [UInt64](repeating: 0, count: f.height)
        f.gray.withUnsafeBufferPointer { p in
            for y in 0..<f.height {
                var h: UInt64 = 0xcbf29ce484222325
                let base = y * f.width
                for x in columns { h = (h ^ UInt64(p[base + x])) &* 0x100000001b3 }
                out[y] = h
            }
        }
        return out
    }

    private func counts(_ hashes: ArraySlice<UInt64>) -> [UInt64: Int] {
        var c: [UInt64: Int] = [:]
        for h in hashes { c[h, default: 0] += 1 }
        return c
    }
}
