#!/usr/bin/env python3
"""gen_font.py SALIDA.inc: la fuente de 6 pixeles de SCUMM/V2/ENGINE/font6.bin como lineas defb, para agitxt.asm."""
import os
import sys

src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'V2', 'ENGINE', 'font6.bin')
d = open(src, 'rb').read()
d = d[:512] + bytes([0, 0b00100000, 0b00010000, 0, 0, 0, 0, 0]) + d[520:]      # ASCII 96: acento grave en vez de la libra (comillas ``asi'' de los textos de AGI)
assert len(d) == 768
with open(sys.argv[1], 'w', newline='\n') as f:
    f.write('; generado por TOOLS/gen_font.py: no editar\n')
    for i in range(0, 768, 8):
        f.write('                defb ' + ','.join(str(b) for b in d[i:i + 8]) + '\n')
