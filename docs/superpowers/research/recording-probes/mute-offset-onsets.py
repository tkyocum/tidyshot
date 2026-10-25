import subprocess, sys, array, math
f = sys.argv[1]
raw = subprocess.run(["ffmpeg","-v","error","-i",f,"-map","0:a","-f","s16le","-ac","1","-ar","48000","-"],capture_output=True).stdout
a = array.array('h'); a.frombytes(raw)
sr = 48000
st = float(subprocess.run(["ffprobe","-v","error","-select_streams","a","-show_entries","stream=start_time","-of","csv=p=0",f],capture_output=True,text=True).stdout.strip() or 0)
w = 240  # 5 ms
rms = []
for i in range(0, len(a) - w, w):
    seg = a[i:i+w]
    rms.append(math.sqrt(sum(x*x for x in seg)/w))
srt = sorted(rms)
base = srt[len(srt)//2]
peak = max(rms)
print("audio start", st, "dur", len(a)/sr, "median rms %.1f peak rms %.1f" % (base, peak))
thr = max(base*6, peak*0.2)
import os
K0 = int(os.environ.get("K0","1"))
for k in range(K0, K0+4):
    lo = int(((k-0.2)-st)/ (w/sr)); hi = int(((k+0.6)-st)/(w/sr))
    hit = None
    for j in range(max(lo,0), min(hi, len(rms))):
        if rms[j] > thr:
            hit = st + j*w/sr; break
    print("event %d (called at %.3f): first window above threshold at %s" % (k, k, ("%.3f (+%.0f ms)" % (hit, (hit-k)*1000)) if hit else "none"))
