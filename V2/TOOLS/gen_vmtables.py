#!/usr/bin/env python3
"""Genera SCUMM/V2/ENGINE/tables.inc: la tabla de despacho (256 opcodes) y las especificaciones de
operandos del nucleo del interprete. Salen de scummdis.py (que se comprobo contra descumm) y de la
clasificacion de manejadores de vmmodel.py, asi que el Z80 y el modelo no pueden divergir en ella.

Cada opcode tiene 4 bytes: direccion de su especificacion (cadena de codigos de operando acabada
en 0) y direccion de su manejador.

Codigos de operando: 1 R, 2 v, 3-5 B1-B3, 6-8 W1-W3, 9 b, 10 w, 11 J, 12 S, 13 N, 15 rutina propia.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scummdis
import vmmodel
import vmgame

TOKEN = {'R': 1, 'v': 2, 'B1': 3, 'B2': 4, 'B3': 5, 'W1': 6, 'W2': 7, 'W3': 8, 'b': 9, 'w': 10,
         'J': 11, 'S': 12, 'N': 13}
SPECIAL_DECODER = {'o2_actorOps': 'dec_actorops', 'o2_verbOps': 'dec_verbops',
                   'o2_doSentence': 'dec_dosentence', 'o5_pseudoRoom': 'dec_pseudoroom'}
# setVarRange: el decodificador solo lee R y b; el manejador lee los valores


def spec_for(name):
    if name in SPECIAL_DECODER:
        return ('sp_' + SPECIAL_DECODER[name], [15, SPECIAL_DECODER[name]])
    if name == 'o5_setVarRange':
        return ('sp_setvarrange', [1, 9])
    toks = scummdis._SPEC[name].split() if scummdis._SPEC[name] else []
    return ('sp_' + '_'.join(toks) if toks else 'sp_none', [TOKEN[t] for t in toks])


def handler_for(name):
    if name in vmgame.GameMixin.GAME_OPS or name in vmmodel.CORE or name in vmmodel.STATE_OPS:
        return 'h_' + name
    toks = scummdis._SPEC.get(name, '').split()
    if toks and toks[0] == 'R':
        return 'h_host_r'
    return 'h_host'


def main():
    out = ['; GENERADO por SCUMM/V2/TOOLS/gen_vmtables.py: no editar a mano', '']
    specs = {}
    entries = []
    for op in range(256):
        name = scummdis.OPNAME[op]
        label, toks = spec_for(name)
        specs.setdefault(label, toks)
        entries.append((op, name, label, handler_for(name)))
    out.append('; ---- especificaciones de operandos')
    for label, toks in sorted(specs.items()):
        parts = []
        for t in toks:
            parts.append(str(t))
        if toks and toks[0] == 15:
            out.append('%s:' % label)
            out.append('        defb 15')
            out.append('        defw %s' % toks[1])
            out.append('        defb 0')
        else:
            out.append('%s: defb %s0' % (label, ''.join(p + ',' for p in parts)))
    out.append('')
    out.append('; ---- tabla de despacho: por opcode, especificacion y manejador')
    out.append('disp_table:')
    for op, name, spec, handler in entries:
        out.append('        defw %s, %s   ; %02X %s' % (spec, handler, op, name))
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ENGINE', 'tables.inc')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')
    handlers = sorted({e[3] for e in entries})
    print('%d especificaciones, %d manejadores distintos' % (len(specs), len(handlers)))
    print('manejadores:', ' '.join(handlers))


if __name__ == '__main__':
    main()
