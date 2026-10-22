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
        spr.append((b[0], b[1] | (b[2] << 8), b[3], b[4:12], b[12:20], b[20:28]))
    t = d[131072 + 2048:]
    fine, rows = t[0], t[1:4]
    W, H = 256, 192
    img = [[(0, 0, 0)] * W for _ in range(H)]
    for r in range(24):
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
    for i in range(64):
        on, sx, sy, col, pix, mask = spr[i]
        if not on:
            continue
        for y in range(8):
            for k in range(8):
                if (mask[y] >> (7 - k)) & 1:
                    x, yy = sx - 32 + k, sy - 32 + y
                    if 0 <= x < W and 0 <= yy < H:
                        c = col[y]
                        img[yy][x] = L.CHROMA[(c >> 4) if (pix[y] >> (7 - k)) & 1 else (c & 15)]
    out = [[img[y // scale][x // scale] for x in range(W * scale)] for y in range(H * scale)]
    L.write_png(sys.argv[2], out)
    print('%s: %dx%d' % (sys.argv[2], W * scale, H * scale))


if __name__ == '__main__':
    main()
