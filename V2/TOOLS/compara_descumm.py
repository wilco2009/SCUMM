#!/usr/bin/env python3
"""Compara el desensamblador propio (scummdis.py) con descumm sobre todos los scripts de una carpeta de LFL.

Para cada bloque de codigo (scripts globales, de entrada, de salida y de objeto) ejecuta
`descumm -2 -i -e -f -w -b` (listado plano, una linea por instruccion) y comprueba que coinciden:
  - la lista de instrucciones: offset y opcode de cada una (por tanto su longitud),
  - el destino de cada salto.
Ademas junta los nombres de instruccion de las dos herramientas para revisarlos.

Uso: compara_descumm.py DIR_LFL RUTA_DESCUMM
"""
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scumm2
import scummdis

LINE = re.compile(r'^\[([0-9A-F]{4})\] \(([0-9A-F]{2})\) (.*?);?$')
GOTO = re.compile(r'goto ([0-9A-F]{4})')


def descumm_listing(exe, path):
    res = subprocess.run([exe, '-2', '-i', '-e', '-f', '-w', '-b', path], capture_output=True, text=True)
    lines = []
    for ln in res.stdout.split('\n'):
        m = LINE.match(ln)
        if m:
            lines.append((int(m.group(1), 16), int(m.group(2), 16), m.group(3)))
    # beginOverride (58) va seguido de un salto (18 xx xx) que ScummVM consume como parte de la
    # propia instruccion (fetchScriptByte + fetchScriptWord); descumm lo lista aparte
    merged = []
    for k, ln in enumerate(lines):
        if merged and merged[-1][1] == 0x58 and ln[1] == 0x18 and ln[0] == merged[-1][0] + 1:
            continue
        merged.append(ln)
    return merged, res.returncode, res.stderr.strip()


def blocks(d, ix):
    """Genera (nombre, bytes del fichero para descumm, codigo, inicio, offset base)."""
    for i in range(len(ix.res['script'])):
        if scumm2.resource_ok(d, ix, 'script', i):
            r = scumm2.resource(d, ix, 'script', i)
            yield 'script %d' % i, r, r[4:], 0, 0
    for rn in range(len(ix.res['room'])):
        if not os.path.exists(os.path.join(d, '%02d.LFL' % rn)):
            continue
        r = scumm2.Room(d, rn)
        if r.encd_off:
            c = r.entry_script()
            yield 'sala %d entrada' % rn, bytes(4) + c, c, 0, 0
        if r.excd_off:
            c = r.exit_script()
            yield 'sala %d salida' % rn, bytes(4) + c, c, 0, 0
        for o in r.objects:
            if o.verbs:
                yield 'sala %d obj %d' % (rn, o.id), o.block, o.block, min(v[1] for v in o.verbs), 0


def main():
    d, exe = sys.argv[1], sys.argv[2]
    ix = scumm2.Index(d)
    nblocks = ninsn = bad = 0
    names = defaultdict(set)
    tmp = os.path.join(tempfile.mkdtemp(), 'b.bin')
    for name, filedata, code, start, base in blocks(d, ix):
        with open(tmp, 'wb') as f:
            f.write(filedata)
        theirs, rc, err = descumm_listing(exe, tmp)
        mine, merr = scummdis.disassemble(code, start, len(code), base, partial=True)
        nblocks += 1
        ninsn += len(mine)
        a = [(i.off, i.op) for i in mine]
        b = [(o, op) for o, op, _ in theirs]
        ok = True
        if merr and rc == 0:
            print('%s: error propio: %s' % (name, merr))
            ok = False
        elif rc != 0:
            # descumm se para en un opcode que no entiende; solo se compara lo que llego a listar
            n = len(b)
            ok = a[:n] == b
            print('%s: descumm termina con error tras %d instrucciones (%s); propio lista %d' % (
                name, n, err, len(a)))
            if not ok:
                print('   ...y ademas difieren antes')
        else:
            ok = a == b
            if not ok:
                k = next((j for j in range(min(len(a), len(b))) if a[j] != b[j]), min(len(a), len(b)))
                print('%s: difieren en la instruccion %d: propio %s, descumm %s' % (
                    name, k, ['%04X/%02X' % x for x in a[k:k + 2]], ['%04X/%02X' % x for x in b[k:k + 2]]))
        for i, (o, op, txt) in zip(mine, theirs):
            if i.off == o:
                short = txt.split('(')[0].split(' ')[0]
                names[i.name].add(short)
                g = GOTO.search(txt)
                if i.target is not None and g and int(g.group(1), 16) != i.target:
                    ok = False
                    print('%s [%04X]: destino de salto %04X, descumm %s' % (name, o, i.target, g.group(1)))
        if not ok:
            bad += 1
    print('bloques: %d, instrucciones propias: %d, bloques con diferencias: %d' % (nblocks, ninsn, bad))
    print('\nnombres (manejador de ScummVM -> texto de descumm):')
    for k in sorted(names):
        print('  %-28s %s' % (k, ' '.join(sorted(names[k]))))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
