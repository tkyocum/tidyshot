// Build: swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe
// Run:   .build/window-shadow-probe com.apple.finder com.tinyspeck.slackmacgap
// The terminal that runs it needs the Screen Recording grant. Writes PNGs to the temporary folder.
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@main
struct WindowShadowProbe {
    static func main() async {
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "window-shadow-probe")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print("PNGs in \(outDir.path(percentEncoded: false))")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for bundleID in CommandLine.arguments.dropFirst() {
                let candidates = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0
                        && $0.frame.width > 200 && $0.frame.height > 150
                }
                guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                    print("\(bundleID): no suitable on-screen window")
                    continue
                }
                await probe(window, name: bundleID, outDir: outDir)
            }
        } catch {
            print("failed: \(error)")
        }
    }

    static func probe(_ window: SCWindow, name: String, outDir: URL) async {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let fromFilter = (width: Int((filter.contentRect.width * scale).rounded()), height: Int((filter.contentRect.height * scale).rounded()))
        print("\n\(name): frame \(window.frame), contentRect \(filter.contentRect), pointPixelScale \(filter.pointPixelScale)")
        print("  frame x scale = \(Int((window.frame.width * scale).rounded())) x \(Int((window.frame.height * scale).rounded())), contentRect x scale = \(fromFilter.width) x \(fromFilter.height)")
        for ignoreShadows in [true, false] {
            for sizedFromFilter in [false, true] {
                let config = SCScreenshotConfiguration()
                config.showsCursor = false
                config.dynamicRange = .sdr
                config.ignoreShadows = ignoreShadows
                if sizedFromFilter {
                    config.width = fromFilter.width
                    config.height = fromFilter.height
                }
                let label = "ignoreShadows=\(ignoreShadows) size=\(sizedFromFilter ? "contentRect x scale" : "unset")"
                guard let image = try? await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config).sdrImage else {
                    print("  \(label): capture failed")
                    continue
                }
                let w = image.width, h = image.height
                let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)].map { alpha(of: image, x: $0.0, y: $0.1) }
                let below = alpha(of: image, x: w / 2, y: max(0, h - 1 - Int(20 * scale)))
                print("  \(label): \(w) x \(h); corner alphas \(corners); alpha 20 pt above the last row \(below); alpha of last row \(alpha(of: image, x: w / 2, y: h - 1))")
                let file = outDir.appending(path: "\(name)-\(ignoreShadows ? "noshadow" : "shadow")-\(sizedFromFilter ? "filter" : "default").png")
                if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
    }

    /// The alpha byte of the pixel at (x, y), counted from the top left.
    static func alpha(of image: CGImage, x: Int, y: Int) -> Int {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Int(data[y * context.bytesPerRow + x * 4 + 3])
    }
}
