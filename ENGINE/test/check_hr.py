#!/usr/bin/env python3
"""Comprueba el volcado de test_scumm en HiRes 8x1: la sombra (lo que ve la FPGA) tiene que ser, columna a columna, la sala en la posicion del
hardware (hv_cam, hv_fine) y los bufers de entrada las columnas hv_cam - 1 y hv_cam + 32. Se ignoran las zonas de los objetos (se dibujan o no segun su estado).
Uso: check_hr.py volcado.bin scumm.sym carpeta_con_los_ROOMnn.GFX"""
import os
import struct
import sys

d = open(sys.argv[1], 'rb').read()
sym = {}
for ln in open(sys.argv[2]):
    p = ln.split()
    if len(p) == 3 and p[1] == 'EQU':
        sym[p[0]] = int(p[2].rstrip('Hh'), 16)
sh, lg = d[:65536], d[65536:131072]
room = lg[0xEB40]
cam = lg[sym['hv_cam']] | (lg[sym['hv_cam'] + 1] << 8)
fine = lg[sym['hv_fine']]
pend = lg[sym['hv_pend']]
gcam = lg[sym['gf_cam']] | (lg[sym['gf_cam'] + 1] << 8)
gfine = lg[sym['gf_fine']]
g = open(os.path.join(sys.argv[3], 'gfx', 'ROOM%02d.GFX' % room) if os.path.exists(os.path.join(sys.argv[3], 'gfx')) else os.path.join(sys.argv[3], 'ROOM%02d.GFX' % room), 'rb').read()
cols, h, nobj, sec = struct.unpack_from('<HBBH', g, 6)
rects = []
for i in range(nobj):
    off, c, l, nc, nl = struct.unpack_from('<HBBBB', g, sec + 6 * i)
    if off != 0xFFFF:
        rects.append((c, l, nc, nl))
base = d[131072 + 2048 + 7] << 8
print('sala %d, camara hw %d+%d/8 (logica %d+%d/8), orden pendiente %d, columnas %d, objetos %d' % (room, cam, fine, gcam, gfine, pend, cols, len(rects)))
if pend:
    print('orden del motor en curso: estado transitorio, no se comprueba')
    sys.exit(0)
bad = 0
checked = 0


def covered(w, y):
    return any(c <= w < c + nc and l <= y < l + nl for c, l, nc, nl in rects)


def col(w):
    if w < 0 or w >= cols:
        return bytes(256)
    return g[256 * (w + 1):256 * (w + 2)]


for s in range(34):
    w = cam + s if s < 32 else (cam + 32 if s == 32 else cam - 1)
    cb = col(w)
    for y in range(128):
        if covered(w, y):
            continue
        if s < 32:
            got = (sh[base + y * 32 + s], sh[0xC000 + y * 32 + s])
        elif s == 32:
            got = (sh[base + 0x1800 + y], sh[0xD800 + y])
        else:
            got = (sh[base + 0x1C00 + y], sh[0xDC00 + y])
        checked += 1
        if got != (cb[y], cb[128 + y]):
            bad += 1
            if bad <= 5:
                print('  distinto: pantalla col %d (mundo %d) linea %d: %02X/%02X, esperado %02X/%02X' % (s, w, y, got[0], got[1], cb[y], cb[128 + y]))
print('comprobados %d bytes, distintos %d' % (checked, bad))
sys.exit(1 if bad else 0)
