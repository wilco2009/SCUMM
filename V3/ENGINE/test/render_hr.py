#!/usr/bin/env python3
"""Fase 7: dibuja la pantalla HiRes 8x1 (256 x 192) del volcado de test_scumm (la memoria logica, bitmap en $A000 y atributos en $C000: la fila de texto r esta en
r * 256 + linea * 32 + byte) a un PNG. El atributo es papel << 4 | tinta (4 bits cada uno, paleta aproximada de Chroma). Uso: render_hr.py volcado.bin salida.png [escala]"""
import struct
import sys
import zlib

PAL = [(0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205), (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205),
       (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]


def png(path, w, h, rows):
    raw = b''.join(b'\0' + bytes(r) for r in rows)

    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def main():
    d = open(sys.argv[1], 'rb').read()
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    lg = d[65536:131072]
    rows = []
    for y in range(192):
        r, ln = y // 8, y % 8
        px = bytearray()
        for bx in range(32):
            a = r * 256 + ln * 32 + bx
            bm, at = lg[0xA000 + a], lg[0xC000 + a]
            for bit in range(8):
                c = PAL[(at & 15) if (bm >> (7 - bit)) & 1 else (at >> 4)]
                px += bytes(c) * scale
        for _ in range(scale):
            rows.append(px)
    png(sys.argv[2], 256 * scale, 192 * scale, rows)


main()
