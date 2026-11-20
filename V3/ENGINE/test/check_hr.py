#!/usr/bin/env python3
"""Comprueba el volcado de test_scumm (fase 5b, diseno D3) en HiRes 8x1: la sombra (lo que ve la FPGA) tiene que ser, columna a columna, la sala en la posicion del
hardware (hv_cam, hv_fine): las 128 lineas de la ventana (HR_TOP = 16: filas 2-17) y los bufers de entrada las columnas hv_cam - 1 y hv_cam + 32; las 16 lineas de arriba y
las 48 de abajo (mensajes e interfaz: fase 7) tienen que estar a cero. Los objetos se componen con la lista de los que se dibujan (HR_DLIST), recortados a la ventana.
El .GFX es el de la version 2 (V3/TOOLS/LFL3HR.md): alto variable (+8), columnas por pagina (+12); se ven las lineas [ytop, ytop + 128) (ytop = 16 si la sala tiene 144 o mas).
Uso: check_hr.py volcado.bin scumm.sym carpeta_con_los_ROOMnn.GFX [mascara de objetos: omitir]"""
import os
import struct
import sys

HR_TOP = 16
d = open(sys.argv[1], 'rb').read()
sym = {}
for ln in open(sys.argv[2]):
    p = ln.split()
    if len(p) == 3 and p[1] == 'EQU':
        sym[p[0]] = int(p[2].rstrip('Hh'), 16)
sh, lg = d[:65536], d[65536:131072]
room = lg[sym['gf_room']]
cam = lg[sym['hv_cam']] | (lg[sym['hv_cam'] + 1] << 8)
fine = lg[sym['hv_fine']]
pend = lg[sym['hv_pend']]
gcam = lg[sym['gf_cam']] | (lg[sym['gf_cam'] + 1] << 8)
gfine = lg[sym['gf_fine']]
drawn = lg[sym['hv_drawn']]
gdir = os.path.join(sys.argv[3], 'gfx')
g = open(os.path.join(gdir if os.path.exists(gdir) else sys.argv[3], 'ROOM%02d.GFX' % room), 'rb').read()
cols, lines, nobj, sec = struct.unpack_from('<HBBH', g, 6)
cpp = g[12]
ytop = 16 if lines >= 144 else 0
hh = min(lines, 128)
recs = [struct.unpack_from('<HBBBB', g, sec + 6 * i) for i in range(nobj)]
ndl = lg[sym['hv_ndl']]
dlist = list(lg[sym['HR_DLIST']:sym['HR_DLIST'] + ndl])
base = d[131072 + 2048 + 7] << 8
print('sala %d (%dx%d), camara hw %d+%d/8 (logica %d+%d/8), dibujada %d, orden pendiente %d, columnas %d, objetos %d (%d se dibujan), ventana de %d lineas desde la %d' % (
    room, cols * 8, lines, cam, fine, gcam, gfine, drawn, pend, cols, nobj, ndl, hh, ytop))
if pend:
    print('orden del motor en curso: estado transitorio, no se comprueba')
    sys.exit(0)
if not drawn:
    print('la sala no se ha dibujado todavia')
    sys.exit(1)
bad = 0
checked = 0


def col(w):
    """La columna w del mundo con sus objetos: (bitmap, atributos) de las 128 lineas de la ventana."""
    if w < 0 or w >= cols:
        return bytes(128), bytes(128)
    off = 256 + (w // cpp) * 8192 + (w % cpp) * 2 * lines
    bm = bytearray(g[off + ytop:off + ytop + hh] + bytes(128 - hh))
    at = bytearray(g[off + lines + ytop:off + lines + ytop + hh] + bytes(128 - hh))
    for i in dlist:                               # los objetos que se dibujan, en el orden de la lista: el ultimo escrito queda encima
        if i >= len(recs):
            continue
        o, c, l, nc, nl = recs[i]
        if o == 0xFFFF or not (c <= w < c + nc):
            continue
        p = o + (w - c) * 2 * nl
        s0, e0 = max(l, ytop), min(l + nl, ytop + hh)
        if e0 <= s0:
            continue
        bm[s0 - ytop:e0 - ytop] = g[p + s0 - l:p + e0 - l]
        at[s0 - ytop:e0 - ytop] = g[p + nl + s0 - l:p + nl + e0 - l]
    return bytes(bm), bytes(at)


for s in range(34):
    w = cam + s if s < 32 else (cam + 32 if s == 32 else cam - 1)
    bm, at = col(w)
    for y in range(128):
        sy = HR_TOP + y
        if s < 32:
            got = (sh[base + sy * 32 + s], sh[0xC000 + sy * 32 + s])
        elif s == 32:
            got = (sh[base + 0x1800 + sy], sh[0xD800 + sy])
        else:
            got = (sh[base + 0x1C00 + sy], sh[0xDC00 + sy])
        checked += 1
        if got != (bm[y], at[y]):
            bad += 1
            if bad <= 5:
                print('  distinto: pantalla col %d (mundo %d) linea %d: %02X/%02X, esperado %02X/%02X' % (s, w, y, got[0], got[1], bm[y], at[y]))
# fase 7: fuera de la sala (filas 0-1 y 18-23) esta la pantalla de texto de la interfaz: lo que pinta hr_ui (ui3.asm) de UIVB (8 filas x 40 columnas de 6 pixeles; la fila r
# de UIVB va a la fila de pantalla r si r < 2 y a r + 16 si no) con la fuente font_tiles (los codigos 208-255; los demas, vacio). Solo se comprueba el bitmap.
uivb = lg[sym['UIVB']:sym['UIVB'] + 336]
ft = lg[sym['font_tiles']:sym['font_tiles'] + 384]
nz = 0
for r in range(8):
    srow = r if r < 2 else r + 16
    for ln in range(8):
        bits = []
        for c in range(42):
            code = uivb[r * 42 + c]
            if 80 <= code < 128: code += 128                 # 10a: letra de un verbo atenuado (el mismo glifo, otro atributo)
            g8 = ft[(code - 208) * 8 + ln] if code >= 208 else 0
            bits += [(g8 >> (5 - k)) & 1 for k in range(6)]
        bits += [0] * 4
        exp = bytes(sum(bits[b * 8 + k] << (7 - k) for k in range(8)) for b in range(32))      # 252 pixeles desde el byte 0
        got = bytes(sh[base + (srow * 8 + ln) * 32 + b] for b in range(32))
        checked += 32
        if got != exp:
            nz += 1
            if nz <= 5:
                print('  interfaz distinta: fila %d linea %d: %s, esperado %s' % (srow, ln, got.hex(), exp.hex()))
print('comprobados %d bytes, distintos %d, filas de la interfaz distintas %d' % (checked, bad, nz))
sys.exit(1 if bad or nz else 0)
