#!/bin/zsh
# Ablation: each row changes one choice from the defaults.
# usage: ablate.sh <work folder>
# The work folder (outside the repository) holds window.mp4, p-area.mp4 and p-4096.mp4, the built
# gifspike (see README.md), and gets the outputs in abl/.
W=${1:?usage: ablate.sh <work folder>}
B=$W/gifspike
O=$W/abl
for f in window.mp4 p-area.mp4 p-4096.mp4 gifspike; do [[ -e $W/$f ]] || { echo "missing $W/$f" >&2; exit 1; }; done
mkdir -p $O
D=(--minsigma 2 --keep 4)
typeset -A V
V=(
  a_default ""
  b_keep0 "--keep 0"
  c_minsigma0 "--minsigma 0"
  d_plain "--keep 0 --minsigma 0"
  e_always "--trans always"
  f_never "--trans never"
  g_splitcount "--split count"
  h_lloyd0 "--lloyd 0"
  i_samples8 "--samples 8"
  j_samples96 "--samples 96"
)
for nm src in window $W/window.mp4 area $W/p-area.mp4 p4096 $W/p-4096.mp4; do
  for v in ${(ok)V}; do
    out=$O/$nm-$v.gif
    $B encode $src $out $D ${=V[$v]} > /dev/null
    $B validate $out > /dev/null
    python3 - "$out" "$nm" "$v" <<'PY'
import json,sys
o,nm,v=sys.argv[1:]
m=json.load(open(o+'.meta.json')); val=json.load(open(o+'.validate.json'))
print(f"{nm:7} {v:14} {m['bytes']/1e6:7.3f} MB  {m['secTotal']:5.2f} s  mae {sum(val['maeRGB'])/3:.2f}  psnr {val['psnr']:5.2f}  T/O {m['transparentChosen']}/{m['opaqueChosen']}  rect {m['meanRectFraction']:.2f}  exp {val['expMismatchPx']}")
PY
  done
done
