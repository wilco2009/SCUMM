"""Compara el compositor Z80 (comptest.exe) con la referencia de Python (costume2.cells4) en varias poses y mide los T-estados."""
import os
import subprocess
import struct
import sys
import tempfile
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(H, '..', '..', '..', 'TOOLS'))
import scumm2
import costume2
import lfl2gfx as L

d = os.path.join(H, '..', '..', '..', 'Zak McKracken')
ix = scumm2.Index(d)
emap = L.default_map({})
tmp = tempfile.mkdtemp()
bad = 0
tt = []
for cid, anim, f in [(1, 0, 0), (1, 1, 0), (1, 2, 0), (1, 3, 0), (28, 1, 6), (28, 0, 6), (21, 0, 6), (21, 2, 6), (3, 1, 8), (3, 2, 8), (2, 1, 0), (10, 0, 0)]:
    raw = scumm2.resource(d, ix, 'costume', cid)
    c = costume2.Costume(raw)
    limbs = dict(c.merged(anim))
    if f:
        limbs.update(c.anim_limbs(4 * f + anim % 4))
    limbs = {k: v for k, v in limbs.items() if v}
    mir = costume2.MIRROR_OLD_DIR[anim % 4] if anim % 4 < 2 else False
    for pos in c.steps(limbs)[:2]:
        em = costume2.emap_of(c, emap)
        ref = costume2.cells4(c.render(limbs, pos, mirror=mir), em)
        cur = bytes(pos.get(k, limbs[k][0]) if k in limbs else 0xFF for k in range(16))
        inp = os.path.join(tmp, 'in.bin')
        out = os.path.join(tmp, 'out.bin')
        open(inp, 'wb').write(raw + bytes(em[:16]) + cur + bytes([1 if mir else 0]))
        r = subprocess.run([os.path.join(H, 'comptest.exe'), os.path.join(H, 'comptest.bin'), inp, out], capture_output=True, text=True)
        t = int(r.stdout.split('T=')[1].split()[0])
        o = open(out, 'rb').read()
        dx, dy, cw, ch, n = struct.unpack_from('<hhBBB', o, 0)
        cells = [(o[7 + 41 * i], o[8 + 41 * i:40 + 41 * i], o[40 + 41 * i:48 + 41 * i]) for i in range(n)]
        def vis(cl):        # solo cuentan los pixeles visibles (forma = 1): la mascara del formato B tapa el resto
            out = []
            for p, a, b in cl:
                a = bytearray(a)
                for y in range(8):
                    for k in range(8):
                        if not b[y] & (0x80 >> k):
                            a[4 * y + k // 2] &= 0x0F if k % 2 == 0 else 0xF0
                out.append((p, bytes(a), bytes(b)))
            return out
        ok = ref is not None and (dx, dy, cw, ch) == ref[:4] and vis(cells) == vis(ref[4])
        bad += not ok
        tt.append(t)
        print('traje %2d anim %d fot %d: %s  T=%d  celdas %d%s' % (cid, anim, f, 'igual' if ok else 'DISTINTO', t, n,
              '' if ok else '  z80 %s ref %s' % ((dx, dy, cw, ch, n), ref[:4] + (len(ref[4]),) if ref else None)))
print('distintas: %d, T medio %d, maximo %d' % (bad, sum(tt) // len(tt), max(tt)))
sys.exit(1 if bad else 0)
