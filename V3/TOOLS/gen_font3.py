#!/usr/bin/env python3
"""Fase 7: la fuente de 6 pixeles del interfaz de v3: 384 bytes (48 glifos de 8 lineas: los codigos 208 y 209 son las flechas del inventario y los 46
siguientes, 210-255, la fuente: espacio, 0-9, A-Z y / : . , ? - " ! ', en ese orden como ascii_glyph de ui3.asm). Salen de ENGINE/font6.bin (96 glifos de ASCII 32
en adelante, 8 lineas cada uno, el dibujo en los 6 bits de arriba), que se pasan a 6 bits por linea (1 = tinta). Uso: gen_font3.py salida.bin"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARROWS = bytes([0x0C, 0x1E, 0x3F, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C,
                0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x1E, 0x0C])
FONT_ASC = ' 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/:.,?-"!\''


def main():
    f6 = open(os.path.join(HERE, '..', 'ENGINE', 'font6.bin'), 'rb').read()
    out = bytearray(ARROWS)
    for c in FONT_ASC:
        k = (ord(c) - 32) * 8
        out += bytes(b >> 2 for b in f6[k:k + 8])
    assert len(out) == 384, len(out)
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'ENGINE', 'font_tiles.bin')
    open(path, 'wb').write(out)
    print('%s: %d bytes' % (path, len(out)))


if __name__ == '__main__':
    main()
