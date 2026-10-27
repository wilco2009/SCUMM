#!/usr/bin/env python3
"""Genera agitab.inc (tablas de despacho del interprete Z80) a partir de agi_logic.CMDS/CONDS y de los manejadores
h_<nombre> / hc_<nombre> que existen en agivm.asm. Lo que no tiene manejador va a h_nop / hc_false.

Uso: gen_agitab.py agivm.asm agiobj.asm ... agitab.inc
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agi_logic import CMDS, CONDS


def mangle(n):
    return n.replace('.', '_')


def main(argv):
    asm = ''.join(open(f).read() for f in argv[1:-1])
    have = set(re.findall(r'^(hc?_[a-z0-9_]+):', asm, re.M))
    out = ['; GENERADO por TOOLS/gen_agitab.py: no editar', 'NCMDS          equ %d' % len(CMDS), 'NCONDS         equ %d' % len(CONDS), '']
    out.append('argtab:')
    for i in range(0, len(CMDS), 16):
        out.append('                defb ' + ','.join(str(len(t)) for _, t in CMDS[i:i + 16]))
    out.append('cmdtab:')
    nimpl = 0
    for n, t in CMDS:
        h = 'h_' + mangle(n)
        if h in have:
            nimpl += 1
        else:
            h = 'h_nop'
        out.append('                defw ' + h)
    out.append('cargtab:')
    for c in sorted(CONDS):
        n, t = CONDS[c]
        out.append('                defb %d' % (0 if t is None else len(t)))
    out.append('ccmdtab:')
    ncond = 0
    for c in sorted(CONDS):
        n = CONDS[c][0]
        h = 'hc_' + mangle(n)
        if h in have:
            ncond += 1
        else:
            h = 'hc_false'
        out.append('                defw ' + h)
    open(argv[-1], 'w').write('\n'.join(out) + '\n')
    print('%d de %d comandos y %d de %d condiciones con manejador' % (nimpl, len(CMDS), ncond, len(CONDS)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
