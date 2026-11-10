#!/usr/bin/env python3
"""Bytecode de SCUMM v3 (Indy3) frente al de v2 (Zak, Maniac Mansion): frecuencia estatica y clasificacion.

Indy3: scumm3dis.py (tabla de ScummEngine_v5 + v4 + v3). v2: SCUMM/V2/TOOLS/scummdis.py (tabla de ScummEngine_v2), el
mismo que genera la tabla del Z80. Cada opcode de v3 se clasifica frente al manejador de v2 que hace lo mismo
(las equivalencias y diferencias salen de comparar script_v2.cpp con script_v5.cpp / v4 / v3 de ScummVM):

  codif    misma semantica que en v2: solo cambia la lectura de operandos (variables de 16 bits, locales, bits, indirectas)
  cambia   existe en v2 pero con otra semantica o con otros subopcodes (hay que reescribir el manejador)
  nuevo    no existe en v2

Uso: python compara_bytecode.py "../Indy Last Crusade" "../../V2/Zak McKracken" "../../V2/ManiacMansionDOS" ../medidas/bytecode.json
"""
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import scumm3dis as D3      # noqa: E402
import scumm3res as R3      # noqa: E402
import scumm2               # noqa: E402
import scummdis             # noqa: E402

# opcode v3 -> (clase, manejador v2 equivalente, nota)
CLASS = {
    # misma semantica: el manejador del Z80 vale cambiando la lectura de operandos
    'stopObjectCode': ('codif', 'o5_stopObjectCode', ''), 'breakHere': ('codif', 'o5_breakHere', ''),
    'jumpRelative': ('codif', 'o5_jumpRelative', ''), 'move': ('codif', 'o5_move', ''),
    'isEqual': ('codif', 'o5_isEqual', ''), 'isNotEqual': ('codif', 'o5_isNotEqual', ''),
    'isLess': ('codif', 'o2_isLess', ''), 'isLessEqual': ('codif', 'o2_isLessEqual', ''),
    'isGreater': ('codif', 'o2_isGreater', ''), 'isGreaterEqual': ('codif', 'o2_isGreaterEqual', ''),
    'equalZero': ('codif', 'o5_equalZero', ''), 'notEqualZero': ('codif', 'o5_notEqualZero', ''),
    'increment': ('codif', 'o5_increment', ''), 'decrement': ('codif', 'o5_decrement', ''),
    'add': ('codif', 'o2_add', ''), 'subtract': ('codif', 'o2_subtract', ''),
    'setVarRange': ('codif', 'o5_setVarRange', ''), 'delayVariable': ('codif', 'o5_delayVariable', ''),
    'delay': ('codif', 'o2_delay', ''), 'stopScript': ('codif', 'o2_stopScript', ''),
    'isScriptRunning': ('codif', 'o5_isScriptRunning', ''), 'getRandomNr': ('codif', 'o5_getRandomNr', ''),
    'startSound': ('codif', 'o5_startSound', ''), 'stopSound': ('codif', 'o5_stopSound', ''),
    'startMusic': ('codif', 'o5_startMusic', ''), 'stopMusic': ('codif', 'o5_stopMusic', ''),
    'isSoundRunning': ('codif', 'o5_isSoundRunning', ''), 'putActor': ('codif', 'o2_putActor', 'x, y de 16 bits'),
    'putActorInRoom': ('codif', 'o2_putActorInRoom', ''), 'putActorAtObject': ('codif', 'o2_putActorAtObject', ''),
    'getActorRoom': ('codif', 'o5_getActorRoom', ''), 'getActorX': ('codif', 'o2_getActorX', ''),
    'getActorY': ('codif', 'o2_getActorY', ''), 'getActorElevation': ('codif', 'o2_getActorElevation', ''),
    'getActorMoving': ('codif', 'o5_getActorMoving', ''), 'getActorFacing': ('codif', 'o5_getActorFacing', ''),
    'getActorCostume': ('codif', 'o5_getActorCostume', ''), 'getActorWalkBox': ('codif', 'o2_getActorWalkBox', ''),
    'getObjectOwner': ('codif', 'o5_getObjectOwner', ''), 'setOwnerOf': ('codif', 'o2_setOwnerOf', ''),
    'faceActor': ('codif', 'o5_faceActor', ''), 'animateActor': ('codif', 'o5_animateActor', ''),
    'walkActorTo': ('codif', 'o2_walkActorTo', 'caminata v3 distinta (walk.asm)'),
    'walkActorToObject': ('codif', 'o2_walkActorToObject', 'caminata v3'),
    'walkActorToActor': ('codif', 'o5_walkActorToActor', 'caminata v3'),
    'waitForActor': ('codif', 'o2_waitForActor', ''), 'waitForSentence': ('codif', 'o2_waitForSentence', ''),
    'wait': ('codif', 'o2_waitForMessage', 'Indy3: sin subopcode'),
    'actorFollowCamera': ('codif', 'o5_actorFollowCamera', ''), 'setCameraAt': ('codif', 'o2_setCameraAt', ''),
    'panCameraTo': ('codif', 'o2_panCameraTo', ''), 'getDist': ('codif', 'o5_getDist', ''),
    'findObject': ('codif', 'o2_findObject', ''), 'actorFromPos': ('codif', 'o2_actorFromPos', ''),
    'getClosestObjActor': ('codif', 'o5_getClosestObjActor', ''), 'loadRoom': ('codif', 'o5_loadRoom', ''),
    'setBoxFlags': ('codif', 'o3_setBoxFlags', ''), 'lights': ('codif', 'o2_lights', ''),
    'endCutscene': ('codif', 'o2_endCutscene', ''), 'beginOverride': ('codif', 'o2_beginOverride', ''),
    'pseudoRoom': ('codif', 'o5_pseudoRoom', ''), 'setObjectName': ('codif', 'o5_setObjectName', ''),
    'saveLoadGame': ('codif', 'o4_saveLoadGame', ''),
    # existe pero cambia
    'startScript': ('cambia', 'o2_startScript', 'lista de argumentos -> variables locales'),
    'chainScript': ('cambia', 'o2_chainScript', 'lista de argumentos'),
    'cutscene': ('cambia', 'o2_cutscene', 'lista de argumentos (beginCutscene de v5)'),
    'print': ('cambia', 'o5_print', 'decodeParseString de v5: subopcodes de posicion, color, centrado'),
    'printEgo': ('cambia', 'o5_printEgo', 'decodeParseString de v5'),
    'actorOps': ('cambia', 'o2_actorOps', 'bucle de subopcodes (24) en vez de uno'),
    'verbOps': ('cambia', 'o2_verbOps', 'bucle de subopcodes; verbos con posicion y nombre propios'),
    'roomOps': ('cambia', 'o2_roomOps', 'scroll, pantalla, color, efectos, cadenas'),
    'cursorCommand': ('cambia', 'o2_cursorCommand', 'subopcodes'),
    'resourceRoutines': ('cambia', 'o2_resourceRoutines', 'subopcodes de carga / bloqueo'),
    'ifClassOfIs': ('cambia', 'o2_ifClassOfIs', '24 bits de clase por objeto, lista de clases'),
    'doSentence': ('cambia', 'o2_doSentence', 'frase de v5 (sin preposicion)'),
    'loadRoomWithEgo': ('cambia', 'o2_loadRoomWithEgo', 'x, y de 16 bits y caminata de v5'),
    'drawObject': ('cambia', 'o2_drawObject', 'dibuja en x, y (v4)'),
    'pickupObject': ('cambia', 'o2_pickupObject', 'o4_pickupObject'),
    'setState': ('cambia', 'o2_setState*', 'estado = valor de 8 bits (v2: bits)'),
    'ifState': ('cambia', 'o2_ifState*', 'estado = valor'), 'ifNotState': ('cambia', 'o2_ifState*', 'estado = valor'),
    'getActorWidth': ('nuevo', '', ''), 'getInventoryCount': ('nuevo', '', ''),
    # nuevos
    'expression': ('nuevo', '', 'pila de expresiones con opcodes anidados'),
    'stringOps': ('nuevo', '', 'cadenas en recursos'), 'setClass': ('nuevo', '', 'clases de objeto'),
    'startObject': ('nuevo', '', 'script de verbo de un objeto'), 'stopObjectScript': ('nuevo', '', ''),
    'freezeScripts': ('nuevo', '', ''), 'drawBox': ('nuevo', '', 'rectangulo de color'),
    'saveRestoreVerbs': ('nuevo', '', ''), 'oldRoomEffect': ('nuevo', '', 'efecto de cambio de sala'),
    'systemOps': ('nuevo', '', ''), 'saveLoadVars': ('nuevo', '', 'puntos de IQ de Indy3'),
    'multiply': ('nuevo', '', ''), 'divide': ('nuevo', '', ''), 'and': ('nuevo', '', ''), 'or': ('nuevo', '', ''),
    'findInventory': ('nuevo', '', ''), 'getVerbEntrypoint': ('nuevo', '', ''), 'getStringWidth': ('nuevo', '', ''),
    'isActorInBox': ('nuevo', '', ''), 'getAnimCounter': ('nuevo', '', ''), 'debug': ('nuevo', '', ''),
}


def v2_stats(d):
    ix = scumm2.Index(d)
    ops = Counter()
    nbytes = 0
    fails = 0

    def run(code, start=0):
        nonlocal nbytes, fails
        out, err = scummdis.disassemble(code, start=start, partial=True)
        for i in out:
            ops[i.name.split('_', 1)[1]] += 1
        nbytes += len(code) - start
        if err:
            fails += 1
    for i in range(len(ix.res['script'])):
        if scumm2.resource_ok(d, ix, 'script', i):
            run(scumm2.resource(d, ix, 'script', i)[4:])
    for rn in range(len(ix.res['room'])):
        if not os.path.exists(os.path.join(d, '%02d.LFL' % rn)):
            continue
        try:
            r = scumm2.Room(d, rn)
        except Exception:
            continue
        if r.encd_off:
            run(r.entry_script())
        if r.excd_off:
            run(r.exit_script())
        for o in r.objects:
            starts = [off for _, off in o.verbs if off < o.size]
            if starts:
                run(o.block, min(starts))
    return ops, nbytes, fails


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 1
    d3, dz, dm, out = sys.argv[1:5]
    ix3 = R3.Index(d3)
    ops3, subs3, fails3, bytes3 = D3.stats(ix3)
    total3 = sum(ops3.values())
    res = dict(indy3=dict(ops=ops3, subs=subs3, bytes=bytes3, insns=total3, fails=fails3))
    for name, d in (('zak', dz), ('maniac', dm)):
        ops, nb, fails = v2_stats(d)
        res[name] = dict(ops=ops, bytes=nb, insns=sum(ops.values()), fails=fails)
    by_class = Counter()
    by_class_n = Counter()
    rows = []
    for op, n in ops3.most_common():
        c, v2, note = CLASS.get(op, ('?', '', ''))
        by_class[c] += n
        by_class_n[c] += 1
        rows.append((op, n, c, v2, note))
    res['clases'] = dict(instrucciones=by_class, opcodes=by_class_n)
    res['tabla'] = rows
    # subopcodes distintos por instruccion con bucle de subopcodes
    sub_kinds = {}
    for k in subs3:
        op, s = k.split('.', 1)
        if s.startswith('('):
            continue
        sub_kinds.setdefault(op, set()).add(s)
    res['subopcodes'] = {k: sorted(v) for k, v in sub_kinds.items()}
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(res, f, indent=1, default=list)
    print('Indy3: %d instrucciones en %d bytes, %d opcodes distintos' % (total3, bytes3, len(ops3)))
    for name in ('zak', 'maniac'):
        r = res[name]
        print('%s: %d instrucciones en %d bytes, %d opcodes distintos (%d fallos)' % (
            name, r['insns'], r['bytes'], len(r['ops']), r['fails']))
    print('clases (instrucciones estaticas):', dict(by_class), ' opcodes:', dict(by_class_n))
    for op, n, c, v2, note in rows:
        print('  %-20s %5d %5.1f%%  %-7s %-22s %s' % (op, n, 100.0 * n / total3, c, v2, note))
    print('subopcodes usados:', {k: len(v) for k, v in res['subopcodes'].items()})
    return 0


if __name__ == '__main__':
    sys.exit(main())
