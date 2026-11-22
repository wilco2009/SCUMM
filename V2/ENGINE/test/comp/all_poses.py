"""T-estados del compositor Z80 (comptest.exe) para todas las poses basicas (andar, parado, hablar) de todos los trajes de Zak."""
import os, subprocess, struct, sys, tempfile
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(H, '..', '..', '..', 'TOOLS'))
import scumm2, costume2, lfl2gfx as L
d = os.path.join(H, '..', '..', '..', 'Zak McKracken')
ix = scumm2.Index(d); emap = L.default_map({}); tmp = tempfile.mkdtemp()
allt = []; per = {}
for cid in range(1, 40):
    try:
        raw = scumm2.resource(d, ix, 'costume', cid); c = costume2.Costume(raw)
    except Exception:
        continue
    em = costume2.emap_of(c, emap)
    ts = []
    for dr in range(4):
        m = c.merged(dr)
        if not m:
            continue
        sets = [(m, p) for p in c.steps({k: v for k, v in m.items() if v})]
        for t in (16 + dr, 20 + dr):
            if t <= c.num_anim:
                l = dict(c.anim_limbs(8 + dr)); l.update(c.anim_limbs(4 + dr)); l.update(c.anim_limbs(t))
                l = {k: v for k, v in l.items() if v}
                if l:
                    sets.append((l, c.steps(l)[0]))
        for limbs, pos in sets:
            limbs = {k: v for k, v in limbs.items() if v}
            mir = costume2.MIRROR_OLD_DIR[dr] if dr < 2 else False
            cur = bytes(pos.get(k, limbs[k][0]) if k in limbs else 0xFF for k in range(16))
            inp = os.path.join(tmp, 'in.bin'); out = os.path.join(tmp, 'out.bin')
            open(inp, 'wb').write(raw + bytes(em[:16]) + cur + bytes([1 if mir else 0]))
            r = subprocess.run([os.path.join(H, 'comptest.exe'), os.path.join(H, 'comptest.bin'), inp, out], capture_output=True, text=True)
            ts.append(int(r.stdout.split('T=')[1].split()[0]))
    if ts:
        per[cid] = ts; allt += ts
def md(v): v = sorted(v); return v[len(v) // 2]
print('pose: min %d, mediana %d, max %d (T); %d poses' % (min(allt), md(allt), max(allt), len(allt)))
tot = {k: sum(v) for k, v in per.items()}
print('traje entero (todas sus poses): min %d, mediana %d, max %d (T)' % (min(tot.values()), md(list(tot.values())), max(tot.values())))
for k, v in sorted(per.items()):
    print('  traje %2d: %2d poses, una pose mediana %6d T, todas %8d T (%.2f s)' % (k, len(v), md(v), sum(v), sum(v) / 3.25e6))
