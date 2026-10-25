import struct, sys
def boxes(d, off, end):
    while off + 8 <= end:
        size, typ = struct.unpack(">I4s", d[off:off+8]); hdr = 8
        if size == 1: size = struct.unpack(">Q", d[off+8:off+16])[0]; hdr = 16
        elif size == 0: size = end - off
        yield typ.decode('latin1'), off + hdr, off + size
        off += size
def walk(d, off, end, path):
    for t, s, e in boxes(d, off, end):
        p = path + "/" + t
        if t in ("moov", "trak", "edts", "mdia", "minf", "stbl"):
            walk(d, s, e, p)
        elif t == "mdhd":
            v = d[s]; 
            ts, dur = (struct.unpack(">IQ", d[s+20:s+32]) if v == 1 else struct.unpack(">II", d[s+12:s+20]))
            print(p, "timescale", ts, "duration", dur)
        elif t == "mvhd":
            v = d[s]; ts, dur = (struct.unpack(">IQ", d[s+20:s+32]) if v == 1 else struct.unpack(">II", d[s+12:s+20]))
            print(p, "movie timescale", ts, "duration", dur)
        elif t == "hdlr":
            print(p, d[s+8:s+12].decode())
        elif t == "elst":
            v = d[s]; n = struct.unpack(">I", d[s+4:s+8])[0]; q = s + 8; ents = []
            for _ in range(n):
                if v == 1: dur, mt = struct.unpack(">Qq", d[q:q+16]); q += 16
                else: dur, mt = struct.unpack(">Ii", d[q:q+8]); q += 8
                rate = struct.unpack(">hh", d[q:q+4]); q += 4
                ents.append((dur, mt, rate[0]))
            print(p, "elst", ents)
        elif t == "stss":
            n = struct.unpack(">I", d[s+4:s+8])[0]
            print(p, "sync samples", n, list(struct.unpack(">%dI" % min(n, 20), d[s+8:s+8+4*min(n, 20)])))
        elif t == "stsz":
            n = struct.unpack(">I", d[s+8:s+12])[0]; print(p, "samples", n)
        elif t == "stts":
            n = struct.unpack(">I", d[s+4:s+8])[0]
            ents = [struct.unpack(">II", d[s+8+8*i:s+16+8*i]) for i in range(min(n, 8))]
            print(p, "stts", n, ents)
        elif t == "stsd":
            n = struct.unpack(">I", d[s+4:s+8])[0]; print(p, "stsd entries", n)
d = open(sys.argv[1], "rb").read()
walk(d, 0, len(d), "")
