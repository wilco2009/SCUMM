#!/usr/bin/env python3
"""objflip.py (fase 8): TS_POKE que cambia el estado de 2 objetos de la sala por fotograma (los que tienen imagen), como los fuegos y antorchas de las salas 20 y 28, y pide
gd_pending (lo que haria el suceso EV_OBJSTATE). Uso: objflip.py scumm.sym DATA.BIN sala desde hasta semilla > pokes; ademas escribe en stderr los fotogramas."""
import os, random, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'TOOLS'))
import pack_data3 as P3
sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 3 and p[1] == 'EQU':
        sym[p[0]] = int(p[2].rstrip('Hh'), 16)
data = P3.Data(open(sys.argv[2], 'rb').read())
room, lo, hi, seed = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
rng = random.Random(seed)
e = data.tab('ROOMDIR', room, P3.ROOM_ENTRY)
bp, ba, bl = struct.unpack_from('<BHH', e, 10)
blob = data.read(bp, ba, bl)
nb = blob[0]
p = 1 + 18 * nb
ml = struct.unpack_from('<H', blob, p)[0]
p += 2 + ml
nobj = blob[p]
objs = []
for i in range(nobj):
    r = blob[p + 1 + 14 * i:p + 15 + 14 * i]
    oid = r[0] | (r[1] << 8)
    if r[13] & 1:                                   # tiene imagen
        objs.append(oid)
out = ['2:%X:%X' % (sym['DBG_ROOM'], room), '2:%X:0' % (sym['DBG_ROOM'] + 1)]
st = {}
for f in range(lo, hi):
    for oid in rng.sample(objs, min(2, len(objs))):
        v = st.get(oid, 1) ^ 1 if rng.random() < 0.9 else 2
        st[oid] = v
        out.append('%d:%X:%X' % (f, 0xE200 + oid, v))
    out.append('%d:%X:1' % (f, sym['gd_pending']))
print(','.join(out))
