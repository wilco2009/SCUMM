#!/usr/bin/env python3
"""Compara la ventana de mascara que deja ac_mkdec en BACKBUF (volcado de test_scumm) con la que calcula ScummVM: la mascara de la sala y, encima, las de los
objetos que se dibujan (HR_DLIST, del ultimo al primero) sustituyendola. Uso: mask_obj_test.py volcado.bin "carpeta de los .LFL" sala tira0 fila0 tiras filas"""
import os
import struct
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'TOOLS'))
import lfl2gfx
import scumm2

dump, d, rn, s0, y0, ns, rh = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7])
mem = open(dump, 'rb').read()[65536:131072]
b = lfl2gfx.load_lfl(os.path.join(d, '%02d.LFL' % rn))
w, h = struct.unpack_from('<HH', b, 4)
raw = []
lfl2gfx.room_mask_cells(b, w, h, raw)
m = [row[:] for row in raw]
room = scumm2.Room(d, rn)
n = mem[0x8768]
dl = list(mem[0xBE00:0xBE00 + n])
for i in dl:
    o = room.objects[i]
    if not o.obim or o.width == 0 or o.height == 0 or o.width % 8 or o.x % 8:
        continue
    om = lfl2gfx.decode_obim_mask(room.file, o.obim, o.width, o.height)
    for y, row in enumerate(om):
        for x, v in enumerate(row):
            if o.y + y < h and o.x // 8 + x < len(m[0]):
                m[o.y + y][o.x // 8 + x] = v
BASE = int(os.environ.get("MASK_BASE", "0x9500"), 0)
bad = 0
for k in range(ns):
    for r in range(rh):
        exp = m[y0 + r][s0 + k] if y0 + r < h and s0 + k < len(m[0]) else 0
        got = mem[BASE + rh * k + r]
        if exp != got:
            bad += 1
            if bad <= int(os.environ.get("MASK_SHOW", "10")):
                print('tira %d fila %d: esperado %02X, hay %02X' % (s0 + k, y0 + r, exp, got))
diff = sum(1 for k in range(ns) for r in range(rh) if raw[y0 + r][s0 + k] != m[y0 + r][s0 + k])
print('objetos que se dibujan:', dl, '; bytes que cambian por los objetos:', diff, '; diferencias con la ventana del Z80:', bad)
sys.exit(1 if bad else 0)
