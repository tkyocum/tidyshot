import json, subprocess, sys
# Cross-check: decode our GIF with ffmpeg and ImageMagick (as binaries) and compare the
# middle composed frame with what the encoder says the decoder must show.
for g in sys.argv[1:]:
    m = json.load(open(g + '.meta.json')); w, h, k = m['width'], m['height'], m['midGifFrame']
    exp = open(g + '.exp.rgba', 'rb').read()
    expRGB = bytes(b for i, b in enumerate(exp) if i % 4 != 3)
    n = w * h * 3
    ff = subprocess.run(['ffmpeg', '-v', 'error', '-i', g, '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True)
    nf = len(ff.stdout) // n
    fr = ff.stdout[k * n:(k + 1) * n]
    ffbad = sum(1 for i in range(0, n, 3) if fr[i:i+3] != expRGB[i:i+3])
    mg = subprocess.run(['magick', g + f'[0-{k}]', '-coalesce', '-delete', f'0-{k-1}' if k > 0 else '999', '-depth', '8', 'rgb:-'], capture_output=True)
    mgf = mg.stdout[:n]
    mgbad = sum(1 for i in range(0, n, 3) if mgf[i:i+3] != expRGB[i:i+3]) if len(mgf) == n else 'n/a'
    print(f"{g.split('/')[-1]}: ffmpeg frames {nf} (meta {m['gifFrames']}), stderr {len(ff.stderr)} B, mid mismatches ffmpeg {ffbad} magick {mgbad}")
