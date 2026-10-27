#!/usr/bin/env python3
"""mkovl.py ENTRADA.bin SALIDA.OVL: antepone el tamano (u16) a un overlay para que agivm.asm lo cargue de la SD."""
import sys

d = open(sys.argv[1], 'rb').read()
assert len(d) <= 8192, 'el overlay no cabe en 8 KB: %d' % len(d)
open(sys.argv[2], 'wb').write(bytes((len(d) & 255, len(d) >> 8)) + d)
