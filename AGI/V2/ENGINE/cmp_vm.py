#!/usr/bin/env python3
"""Compara el interprete Z80 (volcado del arnes de PC) con el modelo de Python.

Uso: cmp_vm.py VOLCADO.bin agivm.sym JUEGO CICLOS [GUION]

Mira, por orden: el codigo de error del Z80 (errc), los pasos (logica, pc) de la traza y el resumen de cada ciclo
(pasos, suma de variables, suma de banderas, sala). Escribe la primera divergencia de cada uno.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'TOOLS'))
import agi_vm

SUMM, TRACE, TRMAX = 0x8000, 0x9800, 680


def main(argv):
    dump = open(argv[1], 'rb').read()
    mem = dump[65536:2 * 65536]                       # memoria logica
    sym = {}
    for line in open(argv[2]):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-F]+)H', line)
        if m:
            sym[m.group(1).lower()] = int(m.group(2), 16)

    def b(n):
        return mem[sym[n]]

    def w(n):
        return mem[sym[n]] | (mem[sym[n] + 1] << 8)
    errc, nsum, trc = b('errc'), b('nsum'), w('trcount')
    print('Z80: error %d, %d ciclos resumidos, %d pasos trazados' % (errc, nsum, trc))
    it = agi_vm.Interp(argv[3], True)
    it.trace = []
    ncyc = min(int(argv[4]), nsum)
    it.play(ncyc, agi_vm.parse_script(argv[5]) if len(argv) > 5 else [])
    bad = 0
    for i in range(min(trc, len(it.trace))):
        lg, pc = mem[TRACE + 3 * i], mem[TRACE + 3 * i + 1] | (mem[TRACE + 3 * i + 2] << 8)
        if (lg, pc) != it.trace[i]:
            print('traza: el paso %d difiere: Z80 logica %d pc %d, modelo logica %d pc %d' % (i, lg, pc, it.trace[i][0], it.trace[i][1]))
            bad = 1
            break
    else:
        print('traza: %d pasos iguales' % min(trc, len(it.trace)))
    for i in range(ncyc):
        e = SUMM + 15 * i
        z = tuple(mem[e + k] | (mem[e + k + 1] << 8) for k in (0, 2, 4, 6)) + (mem[e + 8], mem[e + 9] | (mem[e + 10] << 8), mem[e + 11] | (mem[e + 12] << 8), mem[e + 13] | (mem[e + 14] << 8))
        if z != it.summ[i]:
            print('ciclo %d: Z80 (ciclo,pasos,vars,banderas,sala,objetos,cadenas,entrada) = %s, modelo = %s' % (i + 1, z, it.summ[i]))
            bad = 1
            break
    else:
        print('resumen: %d ciclos iguales' % ncyc)
    if it.pic is not None and b('picvalid'):
        import agi2hr
        bm, at = it.render()
        PLANE = 168 * 32
        zb, za = mem[0xA100:0xA100 + PLANE], mem[0xC100:0xC100 + PLANE]
        nb = sum(1 for x, y in zip(zb, bm) if x != y)
        na = sum(1 for i, (x, y) in enumerate(zip(za, at)) if x != y and i + 0x100 not in (0xFF8, 0xFF9))   # $CFF8: direccion de retorno del arnes
        print('pantalla: %d bytes de bitmap y %d de atributos distintos' % (nb, na) if nb or na else 'pantalla: la imagen coincide')
        bad |= 1 if nb or na else 0
    elif it.pic is not None:
        print('pantalla: el Z80 no dibujo la imagen')
        bad = 1
    print('OK' if not bad and not errc else 'DIFERENCIAS')
    return 1 if bad or errc else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
