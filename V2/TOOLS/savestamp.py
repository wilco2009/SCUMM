#!/usr/bin/env python3
"""Genera savestamp.inc: la marca de disposicion del programa para las partidas guardadas (V2/ENGINE/save.asm).

Uso: savestamp.py scumm.sym save.asm > savestamp.inc

La marca es un hash de lo que define el formato de un fichero SAVEnn.SAV: las zonas que se vuelcan ($E000-$FFFF, el bloque de variables del
overlay desde UI_DIRTY con SV_LEN_O bytes, y el inventario desde INVSL hasta el final de SV_LEN_I), NACTORS, NSLOT, ASIZE y el nombre y la
direccion de cada simbolo de esas zonas. Solo cuentan simbolos de datos (los de codigo estan por debajo de $8000, fuera de las zonas), asi que
recompilar, mover codigo o cambiar el tamano del programa NO cambia la marca; mover, anadir, quitar o renombrar una variable guardada, si.
"""
import re
import sys
import zlib


def parse_sym(path):
    d = {}
    for ln in open(path):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-F]+)H', ln, re.I)
        if m:
            d[m.group(1)] = int(m.group(2), 16)
    return d


def main():
    sym = parse_sym(sys.argv[1])
    save = open(sys.argv[2]).read()
    lens = {}
    for k in 'EOIX':
        m = re.search(r'^SV_LEN_%s\s+equ\s+([^;\n]*)' % k, save, re.M | re.I)
        lens[k] = m.group(1).strip()
    lo = sym['UI_DIRTY']
    zones = [(0xE000, 0x10000)]
    zones.append((lo, lo + int(lens['O'].replace('$', '0x'), 16 if lens['O'].startswith('$') else 10)))
    m = re.match(r'\$([0-9A-F]+)-INVSL$', lens['I'], re.I)
    zones.append((sym['INVSL'], int(m.group(1), 16)))
    zones.append((sym['hv_top'], sym['hv_top'] + int(lens['X'])))   # texto arriba, hv_pon y hv_ptab (_roomPalette)
    zones.append((sym['TXSPD'], sym['TXSPD'] + 1))                  # velocidad del texto
    items = ['FMT=3']          # version del formato (sube al cambiar lo que se guarda sin que cambie ningun simbolo)
    items += ['%s=%d' % (k, sym[k]) for k in ('NACTORS', 'NSLOT', 'ASIZE')]
    items += ['%s:%s' % (k, v) for k, v in sorted(lens.items())]
    items += ['Z%04X-%04X' % z for z in zones]
    for name, addr in sorted(sym.items(), key=lambda kv: (kv[1], kv[0])):
        if any(a <= addr < b for a, b in zones):
            items.append('%s@%04X' % (name, addr))
    h = zlib.crc32('\n'.join(items).encode()) & 0xFFFFFFFF
    sys.stdout.write('; GENERADO por TOOLS/savestamp.py (no editar): marca de disposicion de lo que guarda save.asm (%d simbolos de datos)\n' % (len(items)))
    sys.stdout.write('SAVE_STAMP_LO  equ $%04X\nSAVE_STAMP_HI  equ $%04X\n' % (h & 0xFFFF, h >> 16))
    return 0


if __name__ == '__main__':
    sys.exit(main())
