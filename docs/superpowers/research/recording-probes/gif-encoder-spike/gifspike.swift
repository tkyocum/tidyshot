// gifspike: throwaway GIF encoder prototype for TidyShot R2 (option B).
// Written from the GIF89a specification; no third-party encoder source used.
//
//   gifspike encode   <in.mp4> <out.gif> [--fps 15] [--max 1280] [--samples 32]
//                     [--trans auto|always|never] [--keep 0] [--split sqrt|count]
//                     [--lloyd 4] [--colors 255]
//   gifspike imageio  <in.mp4> <out.gif> [--fps 15] [--max 1280] [--global]
//   gifspike validate <out.gif>
//
// encode/imageio also write <out>.meta.json, <out>.src.rgba (scaled source of the
// middle output frame) and, for encode, <out>.exp.rgba (what the decoder must show).

import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import VideoToolbox
import ImageIO
import UniformTypeIdentifiers

func fail(_ s: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + s + "\n").utf8))
    exit(1)
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

// MARK: - Arguments

var argv = Array(CommandLine.arguments.dropFirst())
guard !argv.isEmpty else { fail("usage: gifspike encode|imageio|validate ...") }
let command = argv.removeFirst()
var positional: [String] = []
var flags: [String: String] = [:]
do {
    var k = 0
    while k < argv.count {
        let a = argv[k]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if k + 1 < argv.count, !argv[k + 1].hasPrefix("--") { flags[key] = argv[k + 1]; k += 2 } else { flags[key] = "1"; k += 1 }
        } else { positional.append(a); k += 1 }
    }
}
func flagInt(_ k: String, _ d: Int) -> Int { flags[k].flatMap { Int($0) } ?? d }
func flagStr(_ k: String, _ d: String) -> String { flags[k] ?? d }

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let rgbaInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

/// Whole centiseconds at the end of output frame `e` (exclusive), rounded half up.
func cs(_ e: Int, _ fps: Int) -> Int { (e * 200 + fps) / (2 * fps) }

// MARK: - Reading

/// Maps output frame times to the latest source sample at or before them (the first
/// sample for earlier times). Holds at most two sample buffers.
final class Walker {
    let output: AVAssetReaderTrackOutput
    var cur: CMSampleBuffer?
    var next: CMSampleBuffer?
    var curID = -1
    var decoded = 0
    init(_ output: AVAssetReaderTrackOutput) {
        self.output = output
        next = readImage()
    }
    func readImage() -> CMSampleBuffer? {
        while let sb = output.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(sb) != nil { decoded += 1; return sb }
        }
        return nil
    }
    func frame(at t: CMTime) -> (CMSampleBuffer, Int)? {
        if cur == nil {
            guard let n = next else { return nil }
            cur = n; curID = 0; next = readImage()
        }
        while let n = next, CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(n), t) <= 0 {
            cur = n; curID += 1; next = readImage()
        }
        return (cur!, curID)
    }
}

func makeReader(_ asset: AVAsset, _ track: AVAssetTrack) -> (AVAssetReader, Walker) {
    guard let reader = try? AVAssetReader(asset: asset) else { fail("no reader") }
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    out.alwaysCopiesSampleData = false
    reader.add(out)
    guard reader.startReading() else { fail("startReading: \(String(describing: reader.error))") }
    return (reader, Walker(out))
}

/// Scales a decoded frame into an sRGB RGBA bitmap with high-quality interpolation.
final class Scaler {
    let w: Int, h: Int
    let data: UnsafeMutablePointer<UInt8>
    let ctx: CGContext
    var seconds = 0.0
    init(w: Int, h: Int) {
        self.w = w; self.h = h
        data = .allocate(capacity: w * h * 4)
        ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB, bitmapInfo: rgbaInfo)!
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.copy)
    }
    func scale(_ sb: CMSampleBuffer) {
        let t0 = now()
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { fail("no image buffer") }
        var img: CGImage?
        let st = VTCreateCGImageFromCVPixelBuffer(pb, options: nil, imageOut: &img)
        guard st == noErr, let img else { fail("VTCreateCGImageFromCVPixelBuffer \(st)") }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        seconds += now() - t0
    }
}

// MARK: - Palette

/// 6 bits per channel; each bin keeps its count and the sums of the exact colours,
/// so a bin's representative is the mean of what was really in it.
final class Histogram {
    static let bins = 1 << 18
    let cnt = UnsafeMutablePointer<UInt32>.allocate(capacity: bins)
    let sr = UnsafeMutablePointer<UInt64>.allocate(capacity: bins)
    let sg = UnsafeMutablePointer<UInt64>.allocate(capacity: bins)
    let sb = UnsafeMutablePointer<UInt64>.allocate(capacity: bins)
    init() {
        cnt.initialize(repeating: 0, count: Self.bins)
        sr.initialize(repeating: 0, count: Self.bins)
        sg.initialize(repeating: 0, count: Self.bins)
        sb.initialize(repeating: 0, count: Self.bins)
    }
    func free() { cnt.deallocate(); sr.deallocate(); sg.deallocate(); sb.deallocate() }
    func add(_ p: UnsafePointer<UInt8>, pixels n: Int) {
        for i in 0..<n {
            let r = p[i &* 4], g = p[i &* 4 &+ 1], b = p[i &* 4 &+ 2]
            let bin = Int(r >> 2) << 12 | Int(g >> 2) << 6 | Int(b >> 2)
            cnt[bin] &+= 1
            sr[bin] &+= UInt64(r); sg[bin] &+= UInt64(g); sb[bin] &+= UInt64(b)
        }
    }
}

/// Greedy variance split ("median cut" that splits the box with the largest weighted
/// squared error, on the axis and at the position that minimise the two halves' error),
/// then a few Lloyd (k-means) passes over the histogram bins. Returns K*3 bytes.
func buildPalette(_ hist: Histogram, colors K: Int, splitSqrt: Bool, lloyd: Int, minSigma: Double) -> [UInt8] {
    var px: [Double] = [], py: [Double] = [], pz: [Double] = [], ws: [Double] = [], wm: [Double] = []
    for bin in 0..<Histogram.bins where hist.cnt[bin] > 0 {
        let c = Double(hist.cnt[bin])
        px.append(Double(hist.sr[bin]) / c); py.append(Double(hist.sg[bin]) / c); pz.append(Double(hist.sb[bin]) / c)
        wm.append(c)
        ws.append(splitSqrt ? c.squareRoot() : c)
    }
    let n = px.count
    var perm = Array(0..<n)

    func stats(_ idx: ArraySlice<Int>, _ w: [Double]) -> (Double, Double, Double, Double, Double) {
        var sw = 0.0, sx = 0.0, sy = 0.0, sz = 0.0, sq = 0.0
        for i in idx {
            let ww = w[i]
            sw += ww; sx += ww * px[i]; sy += ww * py[i]; sz += ww * pz[i]
            sq += ww * (px[i] * px[i] + py[i] * py[i] + pz[i] * pz[i])
        }
        return (sw, sx, sy, sz, sq)
    }
    func sse(_ s: (Double, Double, Double, Double, Double)) -> Double {
        s.0 > 0 ? max(0, s.4 - (s.1 * s.1 + s.2 * s.2 + s.3 * s.3) / s.0) : 0
    }
    struct Box { var lo: Int; var hi: Int; var sse: Double; var sigma: Double }
    /// Population-weighted RMS distance of a box's pixels from its mean. Boxes tighter
    /// than `minSigma` are codec noise around one colour and are never split.
    func sigma(_ lo: Int, _ hi: Int) -> Double { let s = stats(perm[lo..<hi], wm); return (sse(s) / max(s.0, 1)).squareRoot() }
    var boxes = [Box(lo: 0, hi: n, sse: sse(stats(perm[0..<n], ws)), sigma: sigma(0, n))]
    while boxes.count < K {
        var pick = -1, worst = 0.0
        for (j, b) in boxes.enumerated() where b.hi - b.lo >= 2 && b.sse > worst && b.sigma >= minSigma { worst = b.sse; pick = j }
        if pick < 0 { break }
        let b = boxes[pick]
        var bestCost = Double.infinity, bestPos = -1
        var bestSlice: [Int] = []
        var bestL = 0.0, bestR = 0.0
        let total = stats(perm[b.lo..<b.hi], ws)
        for axis in 0..<3 {
            let coord = axis == 0 ? px : axis == 1 ? py : pz
            let slice = perm[b.lo..<b.hi].sorted { coord[$0] < coord[$1] }
            var l = (0.0, 0.0, 0.0, 0.0, 0.0)
            for k in 0..<(slice.count - 1) {
                let i = slice[k], ww = ws[i]
                l.0 += ww; l.1 += ww * px[i]; l.2 += ww * py[i]; l.3 += ww * pz[i]
                l.4 += ww * (px[i] * px[i] + py[i] * py[i] + pz[i] * pz[i])
                if coord[slice[k]] == coord[slice[k + 1]] { continue }
                let r = (total.0 - l.0, total.1 - l.1, total.2 - l.2, total.3 - l.3, total.4 - l.4)
                let cl = sse(l), cr = sse(r)
                if cl + cr < bestCost { bestCost = cl + cr; bestPos = k + 1; bestSlice = slice; bestL = cl; bestR = cr }
            }
        }
        if bestPos < 0 { boxes[pick].sse = 0; continue }
        for (k, i) in bestSlice.enumerated() { perm[b.lo + k] = i }
        boxes[pick] = Box(lo: b.lo, hi: b.lo + bestPos, sse: bestL, sigma: sigma(b.lo, b.lo + bestPos))
        boxes.append(Box(lo: b.lo + bestPos, hi: b.hi, sse: bestR, sigma: sigma(b.lo + bestPos, b.hi)))
    }
    // Representatives: population-weighted means, so a dominant exact colour stays exact.
    var reps: [(Double, Double, Double)] = boxes.map { b in
        let s = stats(perm[b.lo..<b.hi], wm)
        return (s.1 / s.0, s.2 / s.0, s.3 / s.0)
    }
    for _ in 0..<lloyd {
        var acc = [(Double, Double, Double, Double)](repeating: (0, 0, 0, 0), count: reps.count)
        for i in 0..<n {
            var best = 0, bd = Double.infinity
            for (j, r) in reps.enumerated() {
                let dx = px[i] - r.0, dy = py[i] - r.1, dz = pz[i] - r.2
                let d = dx * dx + dy * dy + dz * dz
                if d < bd { bd = d; best = j }
            }
            let w = wm[i]
            acc[best].0 += w * px[i]; acc[best].1 += w * py[i]; acc[best].2 += w * pz[i]; acc[best].3 += w
        }
        for j in 0..<reps.count where acc[j].3 > 0 { reps[j] = (acc[j].0 / acc[j].3, acc[j].1 / acc[j].3, acc[j].2 / acc[j].3) }
    }
    var out: [UInt8] = []
    for r in reps {
        out.append(UInt8(max(0, min(255, r.0.rounded())))); out.append(UInt8(max(0, min(255, r.1.rounded())))); out.append(UInt8(max(0, min(255, r.2.rounded()))))
    }
    return out
}

/// Nearest palette entry (squared RGB distance), with a direct-mapped cache of 64K colours.
final class Mapper {
    let k: Int
    let pr: [Int32], pg: [Int32], pb: [Int32]
    let keys = UnsafeMutablePointer<UInt32>.allocate(capacity: 1 << 16)
    let vals = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 << 16)
    var misses = 0
    init(_ pal: [UInt8]) {
        k = pal.count / 3
        pr = (0..<k).map { Int32(pal[$0 * 3]) }
        pg = (0..<k).map { Int32(pal[$0 * 3 + 1]) }
        pb = (0..<k).map { Int32(pal[$0 * 3 + 2]) }
        keys.initialize(repeating: 0xFFFF_FFFF, count: 1 << 16)
        vals.initialize(repeating: 0, count: 1 << 16)
    }
    @inline(__always) func map(_ rgb: UInt32) -> UInt8 {
        let h = Int((rgb &* 2_654_435_761) >> 16)
        if keys[h] == rgb { return vals[h] }
        misses += 1
        let r = Int32(rgb >> 16), g = Int32((rgb >> 8) & 255), b = Int32(rgb & 255)
        var best = 0
        var bd = Int32.max
        pr.withUnsafeBufferPointer { R in pg.withUnsafeBufferPointer { G in pb.withUnsafeBufferPointer { B in
            for j in 0..<k {
                let dr = R[j] &- r, dg = G[j] &- g, db = B[j] &- b
                let d = dr &* dr &+ dg &* dg &+ db &* db
                if d < bd { bd = d; best = j }
            }
        } } }
        keys[h] = rgb; vals[h] = UInt8(best)
        return UInt8(best)
    }
}

// MARK: - Output

/// Byte sink: a file (flushed every 1 MB, with delay fields patched in place later)
/// or memory (grows).
final class Sink {
    var buf: UnsafeMutablePointer<UInt8>
    var cap: Int
    var n = 0
    var flushed = 0
    let fd: Int32
    init(fd: Int32 = -1, capacity: Int = 1 << 20) {
        self.fd = fd; cap = capacity; buf = .allocate(capacity: capacity)
    }
    var total: Int { flushed + n }
    func flush() {
        guard fd >= 0, n > 0 else { return }
        var off = 0
        while off < n {
            let r = write(fd, buf + off, n - off)
            if r <= 0 { fail("write failed: \(errno)") }
            off += r
        }
        flushed += n; n = 0
    }
    func room(_ c: Int) {
        if n + c <= cap { return }
        if fd >= 0 { flush(); if c <= cap { return } }
        var nc = cap * 2
        while nc < n + c { nc *= 2 }
        let nb = UnsafeMutablePointer<UInt8>.allocate(capacity: nc)
        nb.update(from: buf, count: n)
        buf.deallocate(); buf = nb; cap = nc
    }
    @inline(__always) func put(_ b: UInt8) { if n == cap { room(1) }; buf[n] = b; n += 1 }
    func put(_ p: UnsafePointer<UInt8>, _ c: Int) { room(c); (buf + n).update(from: p, count: c); n += c }
    func put16(_ v: Int) { put(UInt8(v & 255)); put(UInt8((v >> 8) & 255)) }
    func put(_ s: String) { for b in s.utf8 { put(b) } }
    func patch8(_ off: Int, _ v: UInt8) {
        if off >= flushed { buf[off - flushed] = v } else {
            var b = v
            if pwrite(fd, &b, 1, off_t(off)) != 1 { fail("pwrite failed") }
        }
    }
    func patch16(_ off: Int, _ v: Int) { patch8(off, UInt8(v & 255)); patch8(off + 1, UInt8((v >> 8) & 255)) }
    func reset() { n = 0 }
}

/// GIF LZW, variable code width 9...12 bits from a minimum code size of 8, clear code
/// whenever the table fills, packed LSB first into 255-byte sub-blocks.
final class LZW {
    static let tableSize = 8192
    let keys = UnsafeMutablePointer<Int32>.allocate(capacity: tableSize)
    let vals = UnsafeMutablePointer<UInt16>.allocate(capacity: tableSize)
    let block = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    var seconds = 0.0
    var clears = 0
    var minCodeSize = 8
    /// "always": clear as soon as the table fills. "never": keep using the full table
    /// (deferred clear) to the end of the frame. "adaptive": deferred, but clear when a
    /// 16K-pixel window compresses 15 % worse than the best window since the table filled.
    var clearMode = "always"

    func encode(_ px: UnsafePointer<UInt8>, _ count: Int, into sink: Sink) {
        let t0 = now()
        let clearCode = UInt64(1 << minCodeSize), eoi = clearCode + 1
        let firstCode = (1 << minCodeSize) + 2
        sink.put(UInt8(minCodeSize))
        var acc: UInt64 = 0
        var nbits = 0
        var blockN = 0
        var codeSize = minCodeSize + 1
        var nextCode = firstCode
        let keys = self.keys, vals = self.vals, block = self.block
        let mode = clearMode == "never" ? 1 : clearMode == "adaptive" ? 2 : 0
        var full = false
        var winStart = 0, winBits = 0
        var bestRatio = -1.0

        @inline(__always) func emit(_ code: UInt64) {
            acc |= code << UInt64(nbits)
            nbits += codeSize
            while nbits >= 8 {
                block[blockN] = UInt8(truncatingIfNeeded: acc)
                blockN += 1
                if blockN == 255 { sink.put(255); sink.put(block, 255); blockN = 0 }
                acc >>= 8; nbits -= 8
            }
        }
        @inline(__always) func resetTable() {
            keys.initialize(repeating: -1, count: LZW.tableSize)
            codeSize = minCodeSize + 1; nextCode = firstCode; full = false; bestRatio = -1
        }
        resetTable()
        emit(clearCode)
        var prefix = Int32(px[0])
        var i = 1
        while i < count {
            let c = Int32(px[i])
            let key = (prefix << 8) | c
            var h = Int((UInt32(bitPattern: key) &* 2_654_435_761) >> 19)
            while true {
                let kk = keys[h]
                if kk == key { prefix = Int32(vals[h]); break }
                if kk == -1 {
                    emit(UInt64(prefix))
                    if full {
                        if mode == 2 {
                            winBits += 12
                            if i - winStart >= 16384 {
                                let r = Double(winBits) / Double(i - winStart)
                                if bestRatio >= 0 && r > bestRatio * 1.15 {
                                    emit(clearCode); resetTable(); clears += 1
                                } else {
                                    bestRatio = bestRatio < 0 ? r : min(bestRatio, r)
                                    winStart = i; winBits = 0
                                }
                            }
                        }
                    } else {
                        keys[h] = key; vals[h] = UInt16(nextCode); nextCode += 1
                        if nextCode > (1 << codeSize) && codeSize < 12 { codeSize += 1 }
                        if nextCode == 4096 {
                            if mode == 0 { emit(clearCode); resetTable(); clears += 1 } else { full = true; winStart = i; winBits = 0; bestRatio = -1 }
                        }
                    }
                    prefix = c
                    break
                }
                h = (h + 1) & (LZW.tableSize - 1)
            }
            i += 1
        }
        emit(UInt64(prefix))
        emit(eoi)
        if nbits > 0 { block[blockN] = UInt8(truncatingIfNeeded: acc); blockN += 1 }
        if blockN > 0 { sink.put(UInt8(blockN)); sink.put(block, blockN) }
        sink.put(0)
        seconds += now() - t0
    }
}

func writeRaw(_ path: String, _ p: UnsafePointer<UInt8>, _ c: Int) {
    FileManager.default.createFile(atPath: path, contents: Data(bytes: p, count: c))
}

func writeMeta(_ path: String, _ meta: [String: Any]) {
    let d = try! JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .prettyPrinted])
    FileManager.default.createFile(atPath: path, contents: d)
}

// MARK: - Commands

func outputSize(_ natural: CGSize, _ maxSide: Int) -> (Int, Int) {
    let sw = Int(natural.width.rounded()), sh = Int(natural.height.rounded())
    let long = max(sw, sh)
    if maxSide <= 0 || long <= maxSide { return (sw, sh) }
    let s = Double(maxSide) / Double(long)
    return (max(1, Int((Double(sw) * s).rounded())), max(1, Int((Double(sh) * s).rounded())))
}

func runEncode(asset: AVURLAsset, track: AVAssetTrack, natural: CGSize, duration: CMTime, outPath: String) {
    let fps = flagInt("fps", 15)
    let (w, h) = outputSize(natural, flagInt("max", 1280))
    let npx = w * h
    let F = max(1, Int((duration.seconds * Double(fps) - 1e-6).rounded(.up)))
    let mid = F / 2
    let tStart = now()

    // Pass 1: sample frames across the recording into the histogram.
    let sampleCount = min(F, flagInt("samples", 32))
    var sampleAt = Set<Int>()
    for k in 0..<sampleCount { sampleAt.insert(sampleCount == 1 ? 0 : Int((Double(k) * Double(F - 1) / Double(sampleCount - 1)).rounded())) }
    let lastSample = sampleAt.max() ?? 0
    let hist = Histogram()
    var sampled = 0
    let scaler = Scaler(w: w, h: h)
    do {
        let (reader, walker) = makeReader(asset, track)
        var lastID = -1
        for i in 0...lastSample {
            guard let (sb, id) = walker.frame(at: CMTime(value: Int64(i), timescale: Int32(fps))) else { fail("no first frame") }
            if sampleAt.contains(i) && id != lastID {
                lastID = id
                scaler.scale(sb)
                hist.add(scaler.data, pixels: npx)
                sampled += 1
            }
        }
        reader.cancelReading()
    }
    let tPass1 = now()
    let Kmax = min(255, flagInt("colors", 255))
    var pal = buildPalette(hist, colors: Kmax, splitSqrt: flagStr("split", "sqrt") == "sqrt", lloyd: flagInt("lloyd", 4), minSigma: Double(flagStr("minsigma", "0")) ?? 0)
    let usedColours = pal.count / 3
    let histBins = (0..<Histogram.bins).reduce(0) { $0 + (hist.cnt[$1] > 0 ? 1 : 0) }
    hist.free()
    let mapper = Mapper(pal)
    // Transparent index sits just after the colours; the table is the next power of two.
    let tIndex = UInt8(usedColours)
    var bits = 1
    while (1 << bits) < usedColours + 1 { bits += 1 }
    let tableEntries = 1 << bits
    while pal.count < 256 * 3 { pal.append(0) }
    let tPalette = now()

    // Pass 2: encode.
    let fd = open(outPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if fd < 0 { fail("open \(outPath)") }
    let sink = Sink(fd: fd)
    sink.put("GIF89a"); sink.put16(w); sink.put16(h)
    sink.put(UInt8(0xF0 | (bits - 1))); sink.put(0); sink.put(0)   // global table of 2^bits entries
    pal.withUnsafeBufferPointer { sink.put($0.baseAddress!, tableEntries * 3) }
    sink.put(0x21); sink.put(0xFF); sink.put(11); sink.put("NETSCAPE2.0")
    sink.put(3); sink.put(1); sink.put16(0); sink.put(0)   // loop forever

    let transMode = flagStr("trans", "auto")
    let keep = flagInt("keep", 0)
    let keepF = Float(keep)
    // Optional ordered (Bayer 8x8) dither, only where the nearest entry is more than
    // `dithermin` away, so flat UI colours and text stay undithered. Off by default.
    let ditherAmp = Int32(flagInt("dither", 0))
    let ditherMin2 = Int32(flagInt("dithermin", 6) * flagInt("dithermin", 6))
    var bayer = [Int32](repeating: 0, count: 64)
    for y in 0..<8 { for x in 0..<8 {
        var v = 0
        let xc = x ^ y
        for bit in 0..<3 { v = (v << 2) | (((xc >> bit) & 1) << 1) | ((y >> bit) & 1) }
        bayer[y * 8 + x] = Int32(v)
    } }
    var dithered = 0
    let composed = UnsafeMutablePointer<UInt8>.allocate(capacity: npx); composed.initialize(repeating: tIndex, count: npx)
    let changedIdx = UnsafeMutablePointer<UInt8>.allocate(capacity: npx)
    let rectT = UnsafeMutablePointer<UInt8>.allocate(capacity: npx)
    let rectO = UnsafeMutablePointer<UInt8>.allocate(capacity: npx)
    let memT = Sink(), memO = Sink()
    let lzw = LZW()
    lzw.minCodeSize = max(2, bits)
    lzw.clearMode = flagStr("clear", "always")
    let wantStats = flags["stats"] != nil
    let prevRGBA = UnsafeMutablePointer<UInt8>.allocate(capacity: wantStats ? npx * 4 : 4)
    var statLines: [String] = []
    let palR = (0..<256).map { Int32(pal[$0 * 3]) }, palG = (0..<256).map { Int32(pal[$0 * 3 + 1]) }, palB = (0..<256).map { Int32(pal[$0 * 3 + 2]) }

    var gifFrames = 0, chosenT = 0, chosenO = 0, holdFrames = 0, emptyDiffs = 0, padFrames = 0
    var curStart = -1, curDelayOff = -1
    var midGifFrame = 0
    var quantSeconds = 0.0
    var rectPixels = 0
    var delays: [Int] = []
    var firstFrameBytes = 0

    func finishFrame(_ endExclusive: Int) {
        var d = cs(endExclusive, fps) - cs(curStart, fps)
        sink.patch16(curDelayOff, min(d, 65535))
        delays.append(min(d, 65535))
        d -= min(d, 65535)
        while d > 0 {   // a held stretch longer than 655.35 s: append 1x1 transparent frames
            let part = min(d, 65535)
            sink.put(0x21); sink.put(0xF9); sink.put(4); sink.put(0x05); sink.put16(part); sink.put(tIndex); sink.put(0)
            sink.put(0x2C); sink.put16(0); sink.put16(0); sink.put16(1); sink.put16(1); sink.put(0)
            var one: UInt8 = tIndex
            lzw.encode(&one, 1, into: sink)
            delays.append(part); gifFrames += 1; padFrames += 1; d -= part
        }
    }

    let (reader, walker) = makeReader(asset, track)
    var lastID = -1
    for i in 0..<F {
        guard let (sb, id) = walker.frame(at: CMTime(value: Int64(i), timescale: Int32(fps))) else { fail("no first frame") }
        if id == lastID { holdFrames += 1 } else {
            lastID = id
            scaler.scale(sb)
            let tq = now()
            let rgba = scaler.data
            var minX = w, maxX = -1, minY = h, maxY = -1
            palR.withUnsafeBufferPointer { PR in palG.withUnsafeBufferPointer { PG in palB.withUnsafeBufferPointer { PB in
                for y in 0..<h {
                    var rowMin = w, rowMax = -1
                    let base = y &* w
                    for x in 0..<w {
                        let p = base &+ x, q = p &* 4
                        let r = UInt32(rgba[q]), g = UInt32(rgba[q &+ 1]), b = UInt32(rgba[q &+ 2])
                        var ni = mapper.map(r << 16 | g << 8 | b)
                        if ditherAmp > 0 {
                            let dr = PR[Int(ni)] &- Int32(r), dg = PG[Int(ni)] &- Int32(g), db = PB[Int(ni)] &- Int32(b)
                            if dr &* dr &+ dg &* dg &+ db &* db > ditherMin2 {
                                let off = (bayer[(y & 7) &* 8 &+ (x & 7)] &* 2 &- 63) &* ditherAmp / 128
                                let r2 = UInt32(max(0, min(255, Int32(r) &+ off))), g2 = UInt32(max(0, min(255, Int32(g) &+ off))), b2 = UInt32(max(0, min(255, Int32(b) &+ off)))
                                ni = mapper.map(r2 << 16 | g2 << 8 | b2)
                                dithered &+= 1
                            }
                        }
                        let ci = composed[p]
                        var changed = ni != ci
                        if changed && keep > 0 && ci != tIndex {
                            // Hysteresis: keep the shown colour unless the new nearest entry is
                            // closer to the source by more than `keep` (RGB distance).
                            let dr = PR[Int(ci)] &- Int32(r), dg = PG[Int(ci)] &- Int32(g), db = PB[Int(ci)] &- Int32(b)
                            let er = PR[Int(ni)] &- Int32(r), eg = PG[Int(ni)] &- Int32(g), eb = PB[Int(ni)] &- Int32(b)
                            let dc = Float(dr &* dr &+ dg &* dg &+ db &* db).squareRoot()
                            let dn = Float(er &* er &+ eg &* eg &+ eb &* eb).squareRoot()
                            if dc <= dn + keepF { changed = false }
                        }
                        if changed {
                            changedIdx[p] = ni; composed[p] = ni
                            if x < rowMin { rowMin = x }
                            rowMax = x
                        } else { changedIdx[p] = tIndex }
                    }
                    if rowMax >= 0 {
                        if y < minY { minY = y }
                        maxY = y
                        if rowMin < minX { minX = rowMin }
                        if rowMax > maxX { maxX = rowMax }
                    }
                }
            } } }
            quantSeconds += now() - tq
            if wantStats {
                var srcDiff = 0, srcBig = 0, idxDiff = 0
                for p in 0..<npx {
                    if changedIdx[p] != tIndex { idxDiff += 1 }
                    let q = p * 4
                    let d = max(abs(Int(rgba[q]) - Int(prevRGBA[q])), abs(Int(rgba[q + 1]) - Int(prevRGBA[q + 1])), abs(Int(rgba[q + 2]) - Int(prevRGBA[q + 2])))
                    if d > 0 { srcDiff += 1 }
                    if d > 8 { srcBig += 1 }
                }
                prevRGBA.update(from: rgba, count: npx * 4)
                statLines.append("i=\(i) src=\(id) srcChanged=\(srcDiff) srcChanged>8=\(srcBig) idxChanged=\(idxDiff) rect=\(maxX < 0 ? "none" : "\(maxX - minX + 1)x\(maxY - minY + 1)")")
            }
            if maxX < 0 { emptyDiffs += 1 } else {
                if curStart >= 0 { finishFrame(i) }
                let rw = maxX - minX + 1, rh = maxY - minY + 1
                rectPixels += rw * rh
                let first = gifFrames == 0
                var useT = !first && transMode != "never"
                for yy in 0..<rh {
                    let src = (minY + yy) * w + minX
                    (rectT + yy * rw).update(from: changedIdx + src, count: rw)
                    (rectO + yy * rw).update(from: composed + src, count: rw)
                }
                // Graphic control extension: disposal 1 (do not dispose), delay patched later.
                func header(_ transparent: Bool) {
                    sink.put(0x21); sink.put(0xF9); sink.put(4); sink.put(transparent ? 0x05 : 0x04)
                    curDelayOff = sink.total
                    sink.put16(0); sink.put(tIndex); sink.put(0)
                    sink.put(0x2C); sink.put16(minX); sink.put16(minY); sink.put16(rw); sink.put16(rh); sink.put(0)
                }
                if first || transMode == "always" || transMode == "never" {
                    header(useT)
                    lzw.encode(useT ? rectT : rectO, rw * rh, into: sink)
                } else {
                    memT.reset(); memO.reset()
                    lzw.encode(rectT, rw * rh, into: memT)
                    lzw.encode(rectO, rw * rh, into: memO)
                    useT = memT.n <= memO.n
                    header(useT)
                    let m = useT ? memT : memO
                    sink.put(m.buf, m.n)
                }
                if !first { if useT { chosenT += 1 } else { chosenO += 1 } }
                if first { firstFrameBytes = sink.total - 13 - tableEntries * 3 - 19 - 18 }
                curStart = i
                gifFrames += 1
            }
        }
        if i == mid {
            midGifFrame = gifFrames - 1
            writeRaw(outPath + ".src.rgba", scaler.data, npx * 4)
            let exp = UnsafeMutablePointer<UInt8>.allocate(capacity: npx * 4)
            for p in 0..<npx {
                let c = Int(composed[p])
                exp[p * 4] = pal[c * 3]; exp[p * 4 + 1] = pal[c * 3 + 1]; exp[p * 4 + 2] = pal[c * 3 + 2]; exp[p * 4 + 3] = 255
            }
            writeRaw(outPath + ".exp.rgba", exp, npx * 4)
            exp.deallocate()
        }
    }
    finishFrame(F)
    sink.put(0x3B)
    sink.flush()
    close(fd)
    reader.cancelReading()
    let tEnd = now()
    let bytes = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? -1
    let meta: [String: Any] = [
        "mode": "ours", "width": w, "height": h, "fps": fps, "outputFrames": F, "gifFrames": gifFrames,
        "mid": mid, "midGifFrame": midGifFrame, "expectedTotalCs": cs(F, fps), "bytes": bytes,
        "sourceFramesDecodedPass2": walker.decoded, "sampledFrames": sampled, "paletteColours": usedColours,
        "histBins": histBins,
        "heldOutputFrames": holdFrames, "emptyDiffFrames": emptyDiffs, "padFrames": padFrames,
        "transparentChosen": chosenT, "opaqueChosen": chosenO, "trans": transMode, "keep": keep,
        "split": flagStr("split", "sqrt"), "clear": lzw.clearMode, "dither": Int(ditherAmp), "ditheredPx": dithered, "minSigma": flagStr("minsigma", "0"), "minCodeSize": lzw.minCodeSize, "lloyd": flagInt("lloyd", 4),
        "meanRectFraction": Double(rectPixels) / Double(max(1, gifFrames - padFrames)) / Double(npx),
        "mapperMisses": mapper.misses, "lzwClears": lzw.clears,
        "secPass1": tPass1 - tStart, "secPalette": tPalette - tPass1, "secPass2": tEnd - tPalette, "secTotal": tEnd - tStart,
        "secScale": scaler.seconds, "secQuantDiff": quantSeconds, "secLZW": lzw.seconds,
        "delaysHead": Array(delays.prefix(12)), "firstFrameBytes": firstFrameBytes,
    ]
    writeMeta(outPath + ".meta.json", meta)
    if wantStats { print(statLines.joined(separator: "\n")) }
    print(String(format: "ours %@: %dx%d, %d output frames -> %d GIF frames, %.2f MB, %.2f s (pass1 %.2f, palette %.2f, pass2 %.2f; scale %.2f, quant %.2f, lzw %.2f)",
                 (outPath as NSString).lastPathComponent, w, h, F, gifFrames, Double(bytes) / 1e6, tEnd - tStart,
                 tPass1 - tStart, tPalette - tPass1, tEnd - tPalette, scaler.seconds, quantSeconds, lzw.seconds))
}

func runImageIO(asset: AVURLAsset, track: AVAssetTrack, natural: CGSize, duration: CMTime, outPath: String) {
    let fps = flagInt("fps", 15)
    let (w, h) = outputSize(natural, flagInt("max", 1280))
    let npx = w * h
    let F = max(1, Int((duration.seconds * Double(fps) - 1e-6).rounded(.up)))
    let mid = F / 2
    let global = flags["global"] != nil
    let t0 = now()
    let url = URL(fileURLWithPath: outPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, F, nil) else { fail("dest") }
    var gifProps: [CFString: Any] = [kCGImagePropertyGIFLoopCount: 0]
    if !global { gifProps[kCGImagePropertyGIFHasGlobalColorMap] = false }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: gifProps] as CFDictionary)
    let scaler = Scaler(w: w, h: h)
    let (reader, walker) = makeReader(asset, track)
    var pending: CGImage?
    var start = 0, lastID = -1, gifFrames = 0, midGifFrame = 0
    func add(_ img: CGImage, _ e: Int) {
        let d = Double(cs(e, fps) - cs(start, fps)) / 100
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: d, kCGImagePropertyGIFUnclampedDelayTime: d]] as CFDictionary)
    }
    for i in 0..<F {
        guard let (sb, id) = walker.frame(at: CMTime(value: Int64(i), timescale: Int32(fps))) else { fail("no first frame") }
        if id != lastID {
            lastID = id
            if let p = pending { add(p, i) }
            scaler.scale(sb)
            pending = scaler.ctx.makeImage()
            start = i; gifFrames += 1
        }
        if i == mid { midGifFrame = gifFrames - 1; writeRaw(outPath + ".src.rgba", scaler.data, npx * 4) }
    }
    if let p = pending { add(p, F) }
    let tf = now()
    guard CGImageDestinationFinalize(dest) else { fail("finalize") }
    reader.cancelReading()
    let t1 = now()
    let bytes = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? -1
    writeMeta(outPath + ".meta.json", ["mode": global ? "imageio-global" : "imageio-perframe", "width": w, "height": h, "fps": fps,
        "outputFrames": F, "gifFrames": gifFrames, "mid": mid, "midGifFrame": midGifFrame, "expectedTotalCs": cs(F, fps),
        "bytes": bytes, "secTotal": t1 - t0, "secFinalize": t1 - tf, "secScale": scaler.seconds])
    print(String(format: "imageio(%@) %@: %dx%d, %d -> %d frames, %.2f MB, %.2f s (finalize %.2f)", global ? "global" : "per-frame",
                 (outPath as NSString).lastPathComponent, w, h, F, gifFrames, Double(bytes) / 1e6, t1 - t0, t1 - tf))
}

func savePNG(_ path: String, _ p: UnsafeMutablePointer<UInt8>, _ w: Int, _ h: Int) {
    let ctx = CGContext(data: p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB, bitmapInfo: rgbaInfo)!
    let img = ctx.makeImage()!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    _ = CGImageDestinationFinalize(d)
}

func runValidate(_ gifPath: String) {
    guard let md = FileManager.default.contents(atPath: gifPath + ".meta.json"),
          let meta = try? JSONSerialization.jsonObject(with: md) as? [String: Any] else { fail("meta") }
    let w = meta["width"] as! Int, h = meta["height"] as! Int, npx = w * h
    let midGif = meta["midGifFrame"] as! Int
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: gifPath) as CFURL, nil) else { fail("CGImageSource") }
    let count = CGImageSourceGetCount(src)
    let type = CGImageSourceGetType(src) as String? ?? "?"
    var delaysCs: [Int] = []
    var clampedCs: [Int] = []
    for i in 0..<count {
        let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let g = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        delaysCs.append(Int((((g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? -1) * 100).rounded()))
        clampedCs.append(Int((((g?[kCGImagePropertyGIFDelayTime] as? Double) ?? -1) * 100).rounded()))
    }
    let p0 = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let pw = p0?[kCGImagePropertyPixelWidth] as? Int ?? -1, ph = p0?[kCGImagePropertyPixelHeight] as? Int ?? -1
    let loop = ((CGImageSourceCopyProperties(src, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount]
    guard let img = CGImageSourceCreateImageAtIndex(src, midGif, nil) else { fail("decode frame \(midGif)") }
    let dec = UnsafeMutablePointer<UInt8>.allocate(capacity: npx * 4)
    let space = (img.colorSpace?.model == .rgb) ? img.colorSpace! : sRGB
    let ctx = CGContext(data: dec, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: rgbaInfo)!
    ctx.setBlendMode(.copy)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let ref = FileManager.default.contents(atPath: gifPath + ".src.rgba")!
    let exp = FileManager.default.contents(atPath: gifPath + ".exp.rgba")
    var sum = [0.0, 0.0, 0.0], maxErr = 0, sq = 0.0, transparentPx = 0, over8 = 0
    ref.withUnsafeBytes { R in
        let r = R.bindMemory(to: UInt8.self)
        for p in 0..<npx {
            var pxOver = false
            for c in 0..<3 {
                let e = abs(Int(dec[p * 4 + c]) - Int(r[p * 4 + c]))
                sum[c] += Double(e); sq += Double(e * e); if e > maxErr { maxErr = e }
                if e > 8 { pxOver = true }
            }
            if pxOver { over8 += 1 }
            if dec[p * 4 + 3] != 255 { transparentPx += 1 }
        }
    }
    var expMismatch = -1
    if let exp {
        expMismatch = 0
        exp.withUnsafeBytes { E in
            let e = E.bindMemory(to: UInt8.self)
            for p in 0..<npx where dec[p * 4] != e[p * 4] || dec[p * 4 + 1] != e[p * 4 + 1] || dec[p * 4 + 2] != e[p * 4 + 2] { expMismatch += 1 }
        }
    }
    let mae = sum.map { $0 / Double(npx) }
    let mse = sq / Double(npx * 3)
    let psnr = 10 * log10(255.0 * 255.0 / max(mse, 1e-9))

    // Crop with the most edge energy (text), shown source | GIF at 2x, nearest neighbour.
    let cw = min(w, flagInt("cw", 300)), ch = min(h, flagInt("ch", 180))
    var bestX = 0, bestY = 0, bestE = -1.0
    ref.withUnsafeBytes { R in
        let r = R.bindMemory(to: UInt8.self)
        func luma(_ p: Int) -> Int { (Int(r[p * 4]) * 3 + Int(r[p * 4 + 1]) * 6 + Int(r[p * 4 + 2])) }
        let step = 20
        var yy = 0
        while yy + ch <= h {
            var xx = 0
            while xx + cw <= w {
                var e = 0.0
                var y = yy
                while y < yy + ch - 1 {
                    var x = xx
                    while x < xx + cw - 1 { e += Double(abs(luma(y * w + x) - luma(y * w + x + 1)) + abs(luma(y * w + x) - luma((y + 1) * w + x))); x += 3 }
                    y += 3
                }
                if e > bestE { bestE = e; bestX = xx; bestY = yy }
                xx += step
            }
            yy += step
        }
    }
    if let cx = flags["cx"].flatMap({ Int($0) }), let cy = flags["cy"].flatMap({ Int($0) }) { bestX = min(cx, w - cw); bestY = min(cy, h - ch) }
    let s = flagInt("zoom", 2), gap = 6
    let ow = cw * s * 2 + gap, oh = ch * s
    let crop = UnsafeMutablePointer<UInt8>.allocate(capacity: ow * oh * 4)
    crop.initialize(repeating: 255, count: ow * oh * 4)
    for y in 0..<oh { for x in (cw * s)..<(cw * s + gap) { for c in 0..<3 { crop[(y * ow + x) * 4 + c] = 255 * UInt8(c / 2) } } }
    ref.withUnsafeBytes { R in
        let r = R.bindMemory(to: UInt8.self)
        for y in 0..<oh { for x in 0..<(cw * s) {
            let sp = ((bestY + y / s) * w + bestX + x / s) * 4
            for c in 0..<4 {
                crop[(y * ow + x) * 4 + c] = r[sp + c]
                crop[(y * ow + x + cw * s + gap) * 4 + c] = c == 3 ? 255 : dec[sp + c]
            }
        } }
    }
    let base = (gifPath as NSString).deletingPathExtension
    savePNG(base + flagStr("cropname", ".crop.png"), crop, ow, oh)
    if flags["full"] != nil {
        savePNG(base + ".mid-gif.png", dec, w, h)
        ref.withUnsafeBytes { R in
            let m = UnsafeMutablePointer<UInt8>.allocate(capacity: npx * 4)
            m.update(from: R.bindMemory(to: UInt8.self).baseAddress!, count: npx * 4)
            savePNG(base + ".mid-src.png", m, w, h)
        }
    }
    let totalCs = delaysCs.reduce(0, +)
    var hist: [Int: Int] = [:]
    for d in delaysCs { hist[d, default: 0] += 1 }
    let res: [String: Any] = [
        "type": type, "frames": count, "metaGifFrames": meta["gifFrames"] ?? -1, "pixelSize": "\(pw)x\(ph)", "loop": loop ?? "nil",
        "totalCs": totalCs, "expectedTotalCs": meta["expectedTotalCs"] ?? -1, "minDelayCs": delaysCs.min() ?? -1,
        "clampedTotalCs": clampedCs.reduce(0, +),
        "delayHistogram": hist.sorted { $0.key < $1.key }.prefix(12).map { "\($0.key)cs x\($0.value)" },
        "midGifFrame": midGif, "maeRGB": mae.map { (($0 * 100).rounded()) / 100 }, "maxErr": maxErr,
        "psnr": (psnr * 100).rounded() / 100, "pixelsOver8": over8, "transparentDecodedPx": transparentPx,
        "expMismatchPx": expMismatch, "crop": "\(base).crop.png @ \(bestX),\(bestY) \(cw)x\(ch)",
    ]
    let d = try! JSONSerialization.data(withJSONObject: res, options: [.sortedKeys])
    print(String(decoding: d, as: UTF8.self))
    writeMeta(gifPath + ".validate.json", res)
}

switch command {
case "encode", "imageio":
    guard positional.count == 2 else { fail("need <in.mp4> <out.gif>") }
    let asset = AVURLAsset(url: URL(fileURLWithPath: positional[0]))
    let (tracks, duration) = try await asset.load(.tracks, .duration)
    guard let track = tracks.first(where: { $0.mediaType == .video }) else { fail("no video track") }
    let natural = try await track.load(.naturalSize)
    if command == "encode" {
        runEncode(asset: asset, track: track, natural: natural, duration: duration, outPath: positional[1])
    } else {
        runImageIO(asset: asset, track: track, natural: natural, duration: duration, outPath: positional[1])
    }
case "validate":
    guard positional.count == 1 else { fail("need <out.gif>") }
    runValidate(positional[0])
case "probe":
    for path in positional {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let (tracks, duration) = try await asset.load(.tracks, .duration)
        guard let track = tracks.first(where: { $0.mediaType == .video }) else { continue }
        let (size, fr) = try await track.load(.naturalSize, .nominalFrameRate)
        let (reader, walker) = makeReader(asset, track)
        var n = 0
        var times: [Double] = []
        while let sb = walker.readImage() { n += 1; if times.count < 8 { times.append(CMSampleBufferGetPresentationTimeStamp(sb).seconds) } }
        reader.cancelReading()
        print("\(path): \(Int(size.width))x\(Int(size.height)) \(String(format: "%.3f", duration.seconds)) s nominal \(fr) fps, \(n) video samples, first pts \(times.map { String(format: "%.3f", $0) })")
    }
default:
    fail("unknown command \(command)")
}
