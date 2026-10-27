#!/usr/bin/env python3
"""gen_sprtab.py SALIDA.inc: tablas de los sprites del interprete AGI (distancia de colores y EGA -> Chroma), para agivm.asm."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi2hr


def main(argv):
    out = ['; generado por TOOLS/gen_sprtab.py: no editar', 'ega2ch:        defb ' + ','.join(str(agi2hr.to_chroma(e)) for e in range(16)),
           'sdist_tab:']
    for a in range(16):
        out.append('                defb ' + ','.join(str(agi2hr.sdist(a, b)) for b in range(16)))
    with open(argv[1], 'w', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
