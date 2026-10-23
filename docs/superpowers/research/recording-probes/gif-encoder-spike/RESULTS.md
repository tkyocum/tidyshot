> This spike now lives in `docs/superpowers/research/recording-probes/gif-encoder-spike/`; its input recordings (`window.mp4`, `p-area.mp4`, `p-4096.mp4`) and its outputs (the built `gifspike`, `final/`, `abl/`) are not committed, and `measure.sh` and `ablate.sh` take a work folder outside the repository that holds them.

# GIF encoder spike (option B): results

Throwaway prototype.

- `gifspike.swift`: one file, 875 lines, of which 287 are the encoder core (palette, mapper, file sink, LZW).
  - Build with `xcrun swiftc -O -swift-version 6 -default-isolation MainActor gifspike.swift -o <work folder>/gifspike`. The toolchain here is Swift 6.4 with the macOS 27 SDK, the only SDK installed.
  - Commands: `encode`, `imageio` (the R2 design's ImageIO path, as the baseline) and `validate`. `ablate.sh` and `measure.sh` reproduce the tables below.
- It was written from the GIF89a format and textbook algorithms (variance-split median cut, k-means, LZW). No gifsicle, gifski or ffmpeg source was read. ffmpeg and ImageMagick were run only as binaries, to decode our output as a cross-check.
- It uses no new package: AVFoundation, VideoToolbox, CoreGraphics and ImageIO only.

## Pipeline as built

1. **Pass 1 (palette).** One sequential `AVAssetReader` pass reads BGRA frames.
   - It samples 32 output frames spread evenly across the recording.
   - Each sampled frame goes through `VTCreateCGImageFromCVPixelBuffer`, then is drawn into an sRGB RGBA context with `interpolationQuality = .high`, long side N. This is the same scaler as the design's ImageIO path, so the comparison only changes the encoder.
   - Pixels go into a histogram with 6 bits per channel, and each bin keeps the sums of its exact colours.
2. **Palette.** A greedy variance split:
   - it repeatedly splits the box with the largest sqrt(count)-weighted squared error, on the axis and at the position that minimise the two halves' error;
   - **it never splits a box whose population RMS spread is under 2 RGB levels**;
   - it stops at 255 colours, then runs 4 k-means passes over the bins with count weights;
   - index 255 is transparent.
3. **Pass 2 (encode).** A second sequential pass. Output frame `i` at `i/fps` shows the latest source sample at or before it.
   - A run of output frames that map to one source sample is not decoded, scaled or compared again. The frame's delay just grows.
   - Each new sample is scaled and mapped to its nearest palette entry. There is no dithering. A 64K-entry direct-mapped colour cache makes the lookup cheap.
   - Each mapped frame is compared with the composed (displayed) index frame, with **hysteresis**: a pixel keeps its shown entry unless the new nearest entry is closer to the source by more than 4 RGB levels.
   - If nothing changed, the frame merges into the previous one, which only lengthens its delay.
   - Otherwise the frame is cropped to the changed rectangle with disposal 1 (do not dispose). **Per frame, it LZW-encodes both variants and keeps the smaller one**: unchanged pixels transparent, or the rectangle fully opaque.
4. **Writing.** The header, the global table and NETSCAPE2.0 with loop 0 come first, then each frame.
   - The graphic control extension is written with delay 0 and patched in place (`pwrite`) once the frame's length is known. Nothing waits for a whole frame's delay to be known.
   - LZW uses a minimum code size of 8 and widths from 9 to 12 bits, packed LSB first into 255-byte sub-blocks. It sends a clear code whenever the table fills.
   - Output goes through a 1 MB buffer straight to the file descriptor. Working memory is the scaled frame, the composed index frame, the changed-index frame, two rectangle buffers and two in-memory LZW buffers.
5. **Delays.** A frame covering output frames `i..<e` gets `round(e·100/fps) − round(i·100/fps)` cs (7, 6, 7 at 15 fps), so the total length is exact. A run longer than 65,535 cs is split with 1×1 transparent frames.

## Results (15 fps, long side 1280 px, Apple Silicon Mac, macOS 27.0.1)

"Peak memory" is `/usr/bin/time -l`'s *peak memory footprint* for the encode process alone (validation runs separately). Max RSS is 390 MB for window, 210 MB for area and 620 MB for p-4096 in **every** mode, ours and ImageIO alike: VideoToolbox decode surfaces are mapped, not footprint. MAE is the mean absolute error per channel (R, G, B, 0–255) of the decoded middle frame against the scaled source frame.

| Input | Output | MP4 | Earlier ImageIO (global / per-frame) | ImageIO re-run (global / per-frame) | **Ours** | Encode time: ours / ImageIO global / ImageIO per-frame | Peak memory: ours / ImageIO global / ImageIO per-frame | MAE ours | MAE ImageIO global |
|---|---|---|---|---|---|---|---|---|---|
| window.mp4 (scrolling text, 2560×1664, 10.33 s) | 1280×832, 155 frames | 19.7 MB | 23.0 / 29.3 MB | 23.64 / 30.11 MB | **14.82 MB** | 3.84 / 3.63 / 3.48 s | **43.8** / 1,844 / 41.3 MB | 0.56, 0.55, 0.56 | 2.48, 2.45, 2.48 |
| p-area.mp4 (mostly static, 1200×800, 3.05 s) | 1200×800, 46 frames | 0.36 MB | 0.62 / 4.4 MB | 0.627 / 4.63 MB | **0.314 MB** | 0.76 / 0.62 / 0.65 s | **34.0** / 501 / 90.7 MB | 0.45, 0.35, 0.69 | 0.93, 0.88, 1.17 |
| p-4096.mp4 (desktop with photos and video, 4096×2304, 4.23 s) | 1280×720, 64 frames | 12 MB (at 4096) | none | 2.35 / 14.57 MB | **1.39 MB** | 4.24 / 2.10 / 2.13 s | **44.6** / 670 / 37.4 MB | 1.57, 1.45, 1.58 | 1.84, 1.73, 1.90 |

- Ours is 37 % smaller than ImageIO's global palette on scrolling text, 50 % smaller on the static area and 41 % smaller on p-4096.
  - Against R2's planned per-frame palettes it is 51 %, 93 % and 90 % smaller.
  - The static area GIF (0.31 MB) is now smaller than its MP4 (0.36 MB).
- Memory stays flat at 34–45 MB at 1280 px, against 0.5–1.8 GB for ImageIO's global palette.
- Encode time is the same as ImageIO on text (the extra palette pass costs 0.6 s) and about 2× slower on colour-heavy p-4096 (see Risks).
- The earlier "9.5 s" ImageIO time in the R2 design came from a different harness. On this harness ImageIO takes 3.5–3.6 s.
- Other sizes, for scale:
  - window at 800 px: 7.41 MB, 2.83 s, 36.5 MB peak;
  - window at full size (2560×1664): 28.5 MB, 6.7 s, 111 MB peak;
  - p-4096 at full size (4096×2304): 11.45 MB, 15.7 s, 220 MB peak.

### Validation

- **Decoding.** CGImageSource reads every output as `com.compuserve.gif` with the right frame count, pixel size, loop count 0 and delays: 6 cs ×52 and 7 cs ×103 for window, totalling 1033 cs, exactly the expected `round(155·100/15)`. Area and p-4096 are exact too, and ImageIO's clamped and unclamped delays agree.
- **Exactness.** The decoded middle frame matches what the encoder says the decoder must show (palette colour of the composed index buffer) with **0 mismatched pixels** for all inputs in ImageIO, ffmpeg and ImageMagick (`xdecode.py`). That covers the transparent-delta frames, the opaque-rectangle frames, LZW clear codes and the patched delays.
- **Merging** was exercised on sparse recordings:
  - `r2/mic.mp4`: 34 output frames → 4 GIF frames (20, 7, 6, 194 cs = 227 cs exact);
  - `r2/muted.mp4`: 64 → 2 frames (420 + 7 cs).
  - None of the three main inputs has a held stretch: something changes in every frame, a moving cursor or animation in the area recording and a playing video in p-4096.
- **Sharpness.** I looked at every crop at 3–4× zoom. With source on the left and GIF on the right, the text is indistinguishable from the scaled source: no blur and no fringing. The flat swatch colours are exact.
  - ImageIO's GIF dithers: `final/window-imageio-global.text.png` shows speckle across the flat background. That is why its error is 4× ours and its files are larger.
  - Crops: `final/window-ours.text.png`, `final/area-ours.text.png`, `final/p4096-ours.photo.png` (and the `-imageio-*` equivalents), plus `final/*-ours.crop.png` (the auto-picked busiest region).

## Algorithm choices that mattered

Ablation, changing one thing from the defaults each time (`abl/`; size in MB, mean MAE in brackets):

| Variant | window | area | p-4096 |
|---|---|---|---|
| **Defaults** (min box spread 2, hysteresis 4, auto T/O, sqrt split, 4 k-means passes, 32 samples) | **14.82** (0.56) | **0.314** (0.50) | **1.391** (1.53) |
| No hysteresis (keep 0) | 15.19 (0.55) | 0.466 (0.48) | 1.987 (1.50) |
| No minimum box spread | 20.34 (0.46) | 0.349 (0.47) | 1.391 (1.53) |
| Neither: plain spec as first written | 23.88 (0.24) | 0.567 (0.43) | 1.987 (1.50) |
| Always transparent | 17.98 | 0.314 | 1.391 |
| Always opaque rectangle | 14.82 | 2.246 | 9.788 |
| Count-weighted split | 15.93 (0.52) | 0.386 (0.44) | 1.691 (1.09) |
| No k-means | 14.56 (0.57) | 0.293 (0.53) | 1.382 (1.63) |
| 8 / 96 samples | 15.30 / 14.63 | 0.310 / 0.309 | 1.392 / 1.387 |
| LZW deferred clear (keep the full table), plain config | 32.15, against 23.88 (+35 %) | | |
| LZW adaptive clear, plain config | 26.83, against 23.88 (+12 %) | | |

1. **Do not spend palette entries on codec noise. This was the biggest single win (window 20.3 → 14.8 MB).**
   - H.264 leaves ±1–3 levels of noise on flat backgrounds.
   - Once the palette resolves near-identical shades of the background, the background becomes speckled in index space and LZW runs break.
   - Sweeping the palette size showed a cliff between 160 colours (14.2 MB) and 191 colours (19.8 MB) on window, at the point where the splits start cutting the background cluster.
   - Refusing to split boxes tighter than 2 levels fixes it while still using all 255 entries for real colours.
2. **Use temporal hysteresis on the diff.** Without it, noise flips pixels between neighbouring entries in every frame, and the changed rectangle covers 80–95 % of the frame even when almost nothing moves (area: 84 %). With a 4-level margin the rectangles shrink to 50–70 %: area −33 %, p-4096 −30 %, with a visually nil error cost.
3. **Choose transparent or opaque per frame.** Neither alone works.
   - Scrolling text wants the opaque rectangle: always-transparent costs +21 %, because moved text over unchanged background interleaves transparent and opaque pixels.
   - Mostly static content wants transparency: always-opaque costs 7×.
   - Encoding both doubles LZW time, about +15 % total. A cheap predictor (the fraction of unchanged pixels in the rectangle) would probably do as well; this was not tried.
4. **Never defer the LZW clear.** Clearing as soon as the table fills is best on screen content. Keeping a full table is 35 % larger.
5. **No dithering keeps text crisp, and keeps the files small.** Error diffusion would break temporal stability as well.
   - An optional **selective ordered dither** (Bayer 8×8, ±8 levels, only on pixels more than 6 levels from their nearest entry, so flat UI colours and text are untouched) cost +10 % on p-4096 and +0.4 % on window. It visibly softened the posterisation on faces.
   - It is off by default and is the lever to try if colour-heavy GIFs look poor.
6. **Fewer colours mean much smaller text GIFs, but colours break first.** Window at 127 colours is 13.7 MB (MAE 0.62); at 63 colours 11.5 MB; at 31 colours 8.8 MB.
   - Text looked identical even at 31 colours, but at 31 the flat swatch hues shifted (tan turned orange, with a yellow edge line).
   - With the spread floor in place, 255 colours costs little. I would keep 255 and not add a size knob.

## Risks for productising

- **Colour-heavy content (photos, video in the recording).** One global palette from sampled frames posterises photos: faces in p-4096 become blotchy (`final/p4096-ours.photo.png`).
  - ImageIO's global palette does the same with a little dither.
  - The error is still lower than ImageIO's (MAE 1.5 against 1.8), but it is the weakest case.
  - Options: the selective ordered dither above (+10 %), or a local colour table for frames whose mapping error is high (GIF allows one per frame).
- **Gradients.** Without dithering, smooth gradients (wallpapers, shadows, video) band. Not measured on a synthetic gradient. Same mitigations.
- **Colours missed by sampling.** The palette comes from 32 frames, about one a second for a 30 s GIF.
  - A colourful popup or window shown for less than a second between samples is mapped to the nearest existing colours and can change hue.
  - Mitigations: sample more (each sample costs one scale and one histogram, about 10 ms at 1280 px), or fall back to a local colour table per frame on high error.
- **Thresholds tuned on three recordings.** The spread floor (2) and hysteresis (4) came from these inputs alone. They need a check on dark mode, low-contrast UI and HDR or wide-gamut sources.
  - Hysteresis can leave a pixel up to 4 levels off its best entry, invisible here.
  - A slow fade advances in steps rather than every frame.
- **Speed on colour-rich or full-size frames.** The colour cache misses heavily on photos and noise:
  - p-4096 at 1280 px spends 1.3 s mapping and took 4.2 s for 4.2 s of video;
  - at full 4096 px it spends 7 s of 15.7 s mapping.
  - Fix with a lazily filled 2^18 lookup table on 6-bit colours (bounded misses), or a k-d tree.
  - Scaling is the other big cost, 1.9 s per 155 frames. Overlapping LZW of frame N with mapping of N+1 on a second core is straightforward.
  - The work is O(frames), so a 30 s scrolling GIF at 1280 px is about 11 s.
- **Memory at full size.** Memory is flat in duration but scales with pixel count: 44 MB at 1280 px, 111 MB at 2560×1664 and 220 MB at 4096×2304, including two in-memory LZW candidates per frame. Acceptable, but `Full size` should keep the 4096 cap.
- **Timing.**
  - Delays are whole centiseconds. Cumulative rounding makes the total exact, but individual frames jitter 6 and 7 cs at 15 fps, as with ImageIO.
  - Browsers raise delays under 2 cs to 10 cs, which matters only above 50 fps.
  - A held stretch longer than 655 s is split into extra 1×1 frames (implemented, not exercised).
- **Compatibility.** The output was decoded only by ImageIO (Safari, Finder, Quick Look), ffmpeg (which Clop bundles) and ImageMagick. Chrome, Firefox, Slack and GitHub renderers are not tested. The format uses only plain GIF89a features: a global table, transparent index, disposal 1, NETSCAPE loop and immediate clear codes.
- **Not measured: Clop.** Clop was not run on these GIFs. Our files are already delta-cropped and noise-free, so expect less from Clop than the 9 % it took off ImageIO's GIF. The R2 go or no-go for the Clop GIF path still needs that probe.
- **API.** `copyNextSampleBuffer`, `alwaysCopiesSampleData` and `AVAssetReader.add` are deprecated in the macOS 27 SDK in favour of `outputProvider`. That is fine for a macOS 26 target, but it will warn when the SDK moves.
- **Code to own.** About 300 lines of encoder (palette, mapper, LZW, writer) plus the two-pass reader. It needs unit tests:
  - an LZW round trip through CGImageSource;
  - a delay-sum test;
  - a merge test;
  - a test that the decoded frame matches the composed buffer (this harness already checks that exactly).
