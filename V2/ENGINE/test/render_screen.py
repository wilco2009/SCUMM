#!/usr/bin/env python3
"""Dibuja lo que veria la FPGA a partir del volcado de test_scumm: Superfast texto de 32 columnas con 256C,
Chroma modo 0, scroll fino y sprites. Uso: render_screen.py volcado.bin salida.png [escala]"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'TOOLS'))
import lfl2gfx as L

DFILE, TILES, COLORS = 0xC800, 0x3800, 0xC000


def main():
    d = open(sys.argv[1], 'rb').read()
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    sh = d[:65536]
    spr = []
    for i in range(64):
        b = d[131072 + 32 * i:131072 + 32 * i + 32]
        spr.append((b[0], b[1] | (b[2] << 8), b[3], b[4:12], b[12:20], b[20:28], b[28], b[29]))
    t = d[131072 + 2048:]
    fine, rows = t[0], t[1:4]
    W, H = 256, 192
    img = [[(0, 0, 0)] * W for _ in range(H)]
    hires = t[6] == 171
    base = t[7] << 8
    if hires:                                    # HiRes 8x1: bitmap lineal en base, atributos (papel | tinta) en $C000, entrada de la derecha en base + $1800 / $D800
        for y in range(H):
            off = fine if (rows[y // 64] >> ((y // 8) % 8)) & 1 else 0
            px = []
            for c in range(33):
                if c < 32:
                    byte, att = sh[base + y * 32 + c], sh[0xC000 + y * 32 + c]
                else:
                    byte, att = sh[base + 0x1800 + y], sh[0xD800 + y]
                paper, ink = att >> 4, att & 15
                for k in range(8):
                    px.append(L.CHROMA[ink if (byte >> (7 - k)) & 1 else paper])
            for x in range(W):
                img[y][x] = px[x + off]
    for r in range(0 if hires else 0, 0 if hires else 24):
        shifted = (rows[r // 8] >> (r % 8)) & 1
        off = fine if shifted else 0
        line = [sh[DFILE + 1 + 33 * r + c] for c in range(33)]
        for y in range(8):
            px = []
            for c in range(33):
                code = line[c]
                shape = sh[TILES + 8 * code + y]
                if code >= 128:
                    shape ^= 0xFF
                col = sh[COLORS + 8 * code + y]
                paper, ink = col >> 4, col & 15
                for k in range(8):
                    px.append(L.CHROMA[ink if (shape >> (7 - k)) & 1 else paper])
            for x in range(W):
                img[r * 8 + y][x] = px[x + off]
    # sprites extra (POKE 2131 = M, el byte 9 tras la tabla de la FPGA): entrada j = 32 bytes en $4000 + 32 * j; sin bit de activo (Y = 0: no se ve);
    # menos prioridad que los 64 normales y, entre ellos, gana el numero mas bajo: se dibujan primero y del ultimo al primero
    nx = t[8] if len(t) > 8 else 0
    sheet = (t[9] if len(t) > 9 else 2) << 13       # POKE 2129: la hoja (y las entradas de los extra) en la sombra
    ext = []
    for j in range(nx):
        b = sh[sheet + 32 * j:sheet + 32 * j + 32]
        if b[3]:
            ext.append((1, b[1] | ((b[2] & 1) << 8), b[3], b[4:12], b[12:20], b[20:28], b[29], b[2] >> 4))
    per_line = [0] * 256
    for e in ext + [x for x in spr if x[0]]:
        for y in range(8):
            if 0 <= e[2] - 32 + y < H and any(e[5]):
                per_line[e[2] - 32 + y] += 1
    print('sprites: %d normales, %d extra, maximo por linea %d%s' % (sum(1 for x in spr if x[0]), len(ext), max(per_line), ' (SUPERA 12)' if max(per_line) > 12 else ''))
    for on, sx, sy, col, pix, mask, page, trans in list(reversed(ext)) + [x for x in spr if x[0]]:
        for y in range(8):
            for k in range(8):
                if (mask[y] >> (7 - k)) & 1:
                    x, yy = sx - 32 + k, sy - 32 + y
                    if 0 <= x < W and 0 <= yy < H:
                        if page:                 # formato B: celda de 4 bpp en la hoja, nibble alto = pixel de la izquierda; el color transparente no se ve
                            v = sh[sheet + (page << 5) + (y << 2) + (k >> 1)]
                            n = (v >> 4) if k % 2 == 0 else (v & 15)
                            if n != trans:
                                img[yy][x] = L.CHROMA[n]
                            continue
                        c = col[y]
                        img[yy][x] = L.CHROMA[(c >> 4) if (pix[y] >> (7 - k)) & 1 else (c & 15)]
    out = [[img[y // scale][x // scale] for x in range(W * scale)] for y in range(H * scale)]
    L.write_png(sys.argv[2], out)
    print('%s: %dx%d' % (sys.argv[2], W * scale, H * scale))


if __name__ == '__main__':
    main()
