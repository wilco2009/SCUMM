#!/usr/bin/env python3
"""gen_font.py SALIDA.inc: la fuente de 6 pixeles de SCUMM/V2/ENGINE/font6.bin como lineas defb, para agitxt.asm."""
import os
import sys

src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'V2', 'ENGINE', 'font6.bin')
d = open(src, 'rb').read()
assert len(d) == 768
with open(sys.argv[1], 'w', newline='\n') as f:
    f.write('; generado por TOOLS/gen_font.py: no editar\n')
    for i in range(0, 768, 8):
        f.write('                defb ' + ','.join(str(b) for b in d[i:i + 8]) + '\n')
