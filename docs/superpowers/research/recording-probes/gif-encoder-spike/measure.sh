#!/bin/zsh
# Final measurements: ours (defaults) vs ImageIO per-frame and global palettes, 15 fps, 1280 px.
# usage: measure.sh <work folder>
# The work folder (outside the repository) holds window.mp4, p-area.mp4 and p-4096.mp4, the built
# gifspike (see README.md), and gets the outputs in final/.
W=${1:?usage: measure.sh <work folder>}
B=$W/gifspike
O=$W/final
for f in window.mp4 p-area.mp4 p-4096.mp4 gifspike; do [[ -e $W/$f ]] || { echo "missing $W/$f" >&2; exit 1; }; done
mkdir -p $O
for nm src in window $W/window.mp4 area $W/p-area.mp4 p4096 $W/p-4096.mp4; do
  for mode in ours imageio-perframe imageio-global; do
    out=$O/$nm-$mode.gif
    case $mode in
      ours) args=(encode $src $out --minsigma 2 --keep 4) ;;
      imageio-perframe) args=(imageio $src $out) ;;
      imageio-global) args=(imageio $src $out --global) ;;
    esac
    /usr/bin/time -l $B $args > $out.stdout 2> $out.time
    $B validate $out --zoom 3 --cw 200 --ch 120 > /dev/null
    python3 - "$out" "$nm" "$mode" <<'PY'
import json,sys,re
o,nm,mode=sys.argv[1:]
m=json.load(open(o+'.meta.json')); v=json.load(open(o+'.validate.json')); t=open(o+'.time').read()
rss=int(re.search(r'(\d+)\s+maximum resident set size',t).group(1))
pk=int(re.search(r'(\d+)\s+peak memory footprint',t).group(1))
real=float(re.search(r'([\d.]+) real',t).group(1))
print(f"{nm:7} {mode:17} {m['bytes']/1e6:7.3f} MB  frames {v['frames']:3}/{m['outputFrames']}  {m['secTotal']:5.2f} s (wall {real:5.2f})  rss {rss/1e6:7.1f} MB  footprint {pk/1e6:7.1f} MB  mae {v['maeRGB']}  psnr {v['psnr']}  dur {v['totalCs']}/{v['expectedTotalCs']} cs  min {v['minDelayCs']}  exp {v['expMismatchPx']}")
PY
  done
done
