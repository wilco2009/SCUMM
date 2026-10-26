#!/usr/bin/env python3
"""Desensamblador de scripts de SCUMM v2 (Maniac Mansion / Zak v2 de DOS).

Las tablas salen del codigo de ScummVM (engines/scumm/script_v2.cpp y script_v5.cpp: setupOpcodes y los
manejadores o2_*, o5_*, o3_*, o4_*). Sirve de especificacion para el interprete del Z80 y se compara con
descumm (ver compara_descumm.py).

Operandos (cada manejador de ScummVM los lee en este orden):
  R   posicion del resultado (1 byte: numero de variable)
  v   variable (1 byte)
  B1/B2/B3  byte directo o variable: si el opcode tiene el bit 0x80/0x40/0x20 es una variable (1 byte),
            si no, un byte inmediato
  W1/W2/W3  igual pero el inmediato es una palabra de 16 bits con signo
  b   byte inmediato      w   palabra inmediata
  J   salto relativo de 16 bits con signo, medido desde el final del operando
  S   cadena de dialogo (hasta 0; un byte con (c & 0x7F) en 4..7 lleva un byte mas)
  N   cadena cruda hasta 0 (nombres de objeto o de verbo)
"""
import struct

PARAM = {'1': 0x80, '2': 0x40, '3': 0x20}

# opcode -> manejador (setupOpcodes de ScummEngine_v2)
_NAMES = """
00 o5_stopObjectCode|01 o2_putActor|02 o5_startMusic|03 o5_getActorRoom
04 o2_isGreaterEqual|05 o2_drawObject|06 o2_getActorElevation|07 o2_setStateIntrinsicOn
08 o5_isNotEqual|09 o5_faceActor|0a o2_assignVarWordIndirect|0b o2_setObjPreposition
0c o2_resourceRoutines|0d o5_walkActorToActor|0e o2_putActorAtObject|0f o2_ifStateIntrinsicOn
10 o5_getObjectOwner|11 o5_animateActor|12 o2_panCameraTo|13 o2_actorOps
14 o5_print|15 o2_actorFromPos|16 o5_getRandomNr|17 o2_setStateTouchable
18 o5_jumpRelative|19 o2_doSentence|1a o5_move|1b o2_setBitVar
1c o5_startSound|1d o2_ifClassOfIs|1e o2_walkActorTo|1f o2_ifStateTouchable
20 o5_stopMusic|21 o2_putActor|22 o4_saveLoadGame|23 o2_getActorY
24 o2_loadRoomWithEgo|25 o2_drawObject|26 o5_setVarRange|27 o2_setStateLocked
28 o5_equalZero|29 o2_setOwnerOf|2a o2_addIndirect|2b o5_delayVariable
2c o2_assignVarByte|2d o2_putActorInRoom|2e o2_delay|2f o2_ifStateLocked
30 o3_setBoxFlags|31 o2_getBitVar|32 o2_setCameraAt|33 o2_roomOps
34 o5_getDist|35 o2_findObject|36 o2_walkActorToObject|37 o2_setStatePickupable
38 o2_isLessEqual|39 o2_doSentence|3a o2_subtract|3b o2_waitForActor
3c o5_stopSound|3d o2_setActorElevation|3e o2_walkActorTo|3f o2_ifStatePickupable
40 o2_cutscene|41 o2_putActor|42 o2_startScript|43 o2_getActorX
44 o2_isLess|45 o2_drawObject|46 o5_increment|47 o2_setStateIntrinsicOff
48 o5_isEqual|49 o5_faceActor|4a o2_chainScript|4b o2_setObjPreposition
4c o2_waitForSentence|4d o5_walkActorToActor|4e o2_putActorAtObject|4f o2_ifStateIntrinsicOff
50 o2_pickupObject|51 o5_animateActor|52 o5_actorFollowCamera|53 o2_actorOps
54 o5_setObjectName|55 o2_actorFromPos|56 o5_getActorMoving|57 o2_setStateUntouchable
58 o2_beginOverride|59 o2_doSentence|5a o2_add|5b o2_setBitVar
5c o2_dummy|5d o2_ifClassOfIs|5e o2_walkActorTo|5f o2_ifStateUntouchable
60 o2_cursorCommand|61 o2_putActor|62 o2_stopScript|63 o5_getActorFacing
64 o2_loadRoomWithEgo|65 o2_drawObject|66 o5_getClosestObjActor|67 o2_setStateUnlocked
68 o5_isScriptRunning|69 o2_setOwnerOf|6a o2_subIndirect|6b o2_dummy
6c o2_getObjPreposition|6d o2_putActorInRoom|6e o2_dummy|6f o2_ifStateUnlocked
70 o2_lights|71 o5_getActorCostume|72 o5_loadRoom|73 o2_roomOps
74 o5_getDist|75 o2_findObject|76 o2_walkActorToObject|77 o2_setStateUnpickupable
78 o2_isGreater|79 o2_doSentence|7a o2_verbOps|7b o2_getActorWalkBox
7c o5_isSoundRunning|7d o2_setActorElevation|7e o2_walkActorTo|7f o2_ifStateUnpickupable
80 o5_breakHere|81 o2_putActor|82 o5_startMusic|83 o5_getActorRoom
84 o2_isGreaterEqual|85 o2_drawObject|86 o2_getActorElevation|87 o2_setStateIntrinsicOn
88 o5_isNotEqual|89 o5_faceActor|8a o2_assignVarWordIndirect|8b o2_setObjPreposition
8c o2_resourceRoutines|8d o5_walkActorToActor|8e o2_putActorAtObject|8f o2_ifStateIntrinsicOn
90 o5_getObjectOwner|91 o5_animateActor|92 o2_panCameraTo|93 o2_actorOps
94 o5_print|95 o2_actorFromPos|96 o5_getRandomNr|97 o2_setStateTouchable
98 o2_restart|99 o2_doSentence|9a o5_move|9b o2_setBitVar
9c o5_startSound|9d o2_ifClassOfIs|9e o2_walkActorTo|9f o2_ifStateTouchable
a0 o5_stopObjectCode|a1 o2_putActor|a2 o4_saveLoadGame|a3 o2_getActorY
a4 o2_loadRoomWithEgo|a5 o2_drawObject|a6 o5_setVarRange|a7 o2_setStateLocked
a8 o5_notEqualZero|a9 o2_setOwnerOf|aa o2_addIndirect|ab o2_switchCostumeSet
ac o2_drawSentence|ad o2_putActorInRoom|ae o2_waitForMessage|af o2_ifStateLocked
b0 o3_setBoxFlags|b1 o2_getBitVar|b2 o2_setCameraAt|b3 o2_roomOps
b4 o5_getDist|b5 o2_findObject|b6 o2_walkActorToObject|b7 o2_setStatePickupable
b8 o2_isLessEqual|b9 o2_doSentence|ba o2_subtract|bb o2_waitForActor
bc o5_stopSound|bd o2_setActorElevation|be o2_walkActorTo|bf o2_ifStatePickupable
c0 o2_endCutscene|c1 o2_putActor|c2 o2_startScript|c3 o2_getActorX
c4 o2_isLess|c5 o2_drawObject|c6 o5_decrement|c7 o2_setStateIntrinsicOff
c8 o5_isEqual|c9 o5_faceActor|ca o2_chainScript|cb o2_setObjPreposition
cc o5_pseudoRoom|cd o5_walkActorToActor|ce o2_putActorAtObject|cf o2_ifStateIntrinsicOff
d0 o2_pickupObject|d1 o5_animateActor|d2 o5_actorFollowCamera|d3 o2_actorOps
d4 o5_setObjectName|d5 o2_actorFromPos|d6 o5_getActorMoving|d7 o2_setStateUntouchable
d8 o5_printEgo|d9 o2_doSentence|da o2_add|db o2_setBitVar
dc o2_dummy|dd o2_ifClassOfIs|de o2_walkActorTo|df o2_ifStateUntouchable
e0 o2_cursorCommand|e1 o2_putActor|e2 o2_stopScript|e3 o5_getActorFacing
e4 o2_loadRoomWithEgo|e5 o2_drawObject|e6 o5_getClosestObjActor|e7 o2_setStateUnlocked
e8 o5_isScriptRunning|e9 o2_setOwnerOf|ea o2_subIndirect|eb o2_dummy
ec o2_getObjPreposition|ed o2_putActorInRoom|ee o2_dummy|ef o2_ifStateUnlocked
f0 o2_lights|f1 o5_getActorCostume|f2 o5_loadRoom|f3 o2_roomOps
f4 o5_getDist|f5 o2_findObject|f6 o2_walkActorToObject|f7 o2_setStateUnpickupable
f8 o2_isGreater|f9 o2_doSentence|fa o2_verbOps|fb o2_getActorWalkBox
fc o5_isSoundRunning|fd o2_setActorElevation|fe o2_walkActorTo|ff o2_ifStateUnpickupable
"""
OPNAME = {}
for _e in _NAMES.replace('\n', '|').split('|'):
    _e = _e.strip()
    if _e:
        _k, _v = _e.split()
        OPNAME[int(_k, 16)] = _v

# manejador -> operandos
_SPEC = {
    'o5_stopObjectCode': '', 'o5_breakHere': '', 'o5_stopMusic': '', 'o2_cutscene': '',
    'o2_endCutscene': '', 'o2_restart': '', 'o2_dummy': '', 'o2_switchCostumeSet': '',
    'o2_drawSentence': '', 'o2_waitForMessage': '', 'o2_waitForSentence': '',
    'o2_putActor': 'B1 B2 B3', 'o2_walkActorTo': 'B1 B2 B3',
    'o5_startMusic': 'B1', 'o5_startSound': 'B1', 'o5_stopSound': 'B1', 'o2_startScript': 'B1',
    'o2_stopScript': 'B1', 'o2_chainScript': 'B1', 'o2_panCameraTo': 'B1', 'o2_setCameraAt': 'B1',
    'o5_actorFollowCamera': 'B1', 'o5_loadRoom': 'B1', 'o2_waitForActor': 'B1',
    'o5_getActorRoom': 'R B1', 'o5_getActorMoving': 'R B1', 'o5_getActorFacing': 'R B1',
    'o5_getActorCostume': 'R B1', 'o2_getActorX': 'R B1', 'o2_getActorY': 'R B1',
    'o2_getActorElevation': 'R B1', 'o2_getActorWalkBox': 'R B1', 'o5_isScriptRunning': 'R B1',
    'o5_isSoundRunning': 'R B1', 'o5_getRandomNr': 'R B1', 'o4_saveLoadGame': 'R B1',
    'o2_actorFromPos': 'R B1 B2', 'o2_findObject': 'R B1 B2',
    'o5_getObjectOwner': 'R W1', 'o5_move': 'R W1', 'o2_assignVarWordIndirect': 'R W1',
    'o2_add': 'R W1', 'o2_subtract': 'R W1', 'o2_addIndirect': 'R W1', 'o2_subIndirect': 'R W1',
    'o5_getClosestObjActor': 'R W1', 'o2_getObjPreposition': 'R W1',
    'o5_getDist': 'R W1 W2', 'o2_assignVarByte': 'R b', 'o5_increment': 'R', 'o5_decrement': 'R',
    'o2_getBitVar': 'R w B1', 'o2_setBitVar': 'w B1 B2',
    'o2_drawObject': 'W1 B2 B3', 'o5_faceActor': 'B1 W2', 'o2_walkActorToObject': 'B1 W2',
    'o2_putActorAtObject': 'B1 W2', 'o5_walkActorToActor': 'B1 B2 b', 'o5_animateActor': 'B1 B2',
    'o2_putActorInRoom': 'B1 B2', 'o2_setActorElevation': 'B1 B2', 'o2_setOwnerOf': 'W1 B2',
    'o2_setObjPreposition': 'W1 b', 'o2_resourceRoutines': 'B1 b', 'o3_setBoxFlags': 'B1 b',
    'o2_roomOps': 'B1 B2 b', 'o2_lights': 'B1 b b', 'o2_loadRoomWithEgo': 'W1 B2 b b',
    'o2_delay': 'b b b', 'o2_beginOverride': 'b w', 'o2_cursorCommand': 'W1',
    'o2_pickupObject': 'W1', 'o5_jumpRelative': 'J', 'o5_delayVariable': 'v',
    'o5_equalZero': 'v J', 'o5_notEqualZero': 'v J',
    'o5_isEqual': 'v W1 J', 'o5_isNotEqual': 'v W1 J', 'o2_isGreater': 'v W1 J',
    'o2_isGreaterEqual': 'v W1 J', 'o2_isLess': 'v W1 J', 'o2_isLessEqual': 'v W1 J',
    'o2_ifClassOfIs': 'W1 B2 J',
    'o5_print': 'B1 S', 'o5_printEgo': 'S', 'o5_setObjectName': 'W1 N',
}
for _n in ('IntrinsicOn', 'IntrinsicOff', 'Touchable', 'Untouchable', 'Locked', 'Unlocked',
           'Pickupable', 'Unpickupable'):
    _SPEC['o2_setState' + _n] = 'W1'
    _SPEC['o2_ifState' + _n] = 'W1 J'
SPECIAL = ('o2_actorOps', 'o2_verbOps', 'o2_doSentence', 'o5_setVarRange', 'o5_pseudoRoom')


class Insn:
    """Una instruccion: offset, opcode, longitud, nombre del manejador, operandos y destino del salto."""

    def __init__(self, off, op, name):
        self.off, self.op, self.name = off, op, name
        self.length = 1
        self.args = []          # (clase, valor, es_variable)
        self.target = None      # destino absoluto de un salto
        self.string = None

    def text(self):
        a = []
        for k, v, isvar in self.args:
            a.append('Var[%d]' % v if isvar else (repr(v) if k == 'str' else str(v)))
        t = '%s(%s)' % (self.name.split('_', 1)[1], ','.join(a))
        if self.target is not None:
            t += ' -> %04X' % self.target
        return t


class Decoder:
    def __init__(self, code, base=0):
        self.c, self.base = code, base

    def u8(self, p):
        return self.c[p - self.base]

    def u16(self, p):
        return struct.unpack_from('<H', self.c, p - self.base)[0]

    def s16(self, p):
        return struct.unpack_from('<h', self.c, p - self.base)[0]

    def decode(self, p):
        op = self.u8(p)
        name = OPNAME[op]
        i = Insn(p, op, name)
        q = p + 1

        def arg(kind, n=None):
            nonlocal q
            if kind == 'R':
                i.args.append(('R', self.u8(q), True))
                q += 1
            elif kind == 'v':
                i.args.append(('v', self.u8(q), True))
                q += 1
            elif kind[0] in 'BW':
                if op & PARAM[kind[1]]:
                    i.args.append((kind, self.u8(q), True))
                    q += 1
                elif kind[0] == 'B':
                    i.args.append((kind, self.u8(q), False))
                    q += 1
                else:
                    i.args.append((kind, self.s16(q), False))
                    q += 2
            elif kind == 'b':
                i.args.append(('b', self.u8(q), False))
                q += 1
            elif kind == 'w':
                i.args.append(('w', self.u16(q), False))
                q += 2
            elif kind == 'J':
                off = self.s16(q)
                q += 2
                i.target = q + off
            elif kind in ('S', 'N'):
                s = bytearray()
                while True:
                    c = self.u8(q)
                    q += 1
                    if c == 0:
                        break
                    s.append(c)
                    if kind == 'S' and 3 < (c & 0x7F) < 8:
                        s.append(self.u8(q))
                        q += 1
                i.args.append(('str', bytes(s).decode('latin1'), False))
        if name in _SPEC:
            for k in _SPEC[name].split():
                arg(k)
        elif name == 'o2_actorOps':
            arg('B1')
            arg('B2')
            arg('b')
            sub = i.args[-1][1]
            if sub == 2:
                arg('b')
            elif sub == 3:
                arg('N')
        elif name == 'o2_verbOps':
            arg('b')
            verb = i.args[-1][1]
            if verb == 0:
                arg('B1')
            elif verb == 0xFF:
                arg('b')
                arg('b')
            else:
                arg('b')
                arg('b')
                arg('B1')
                arg('b')
                arg('N')
        elif name == 'o2_doSentence':
            arg('B1')
            first = i.args[-1]
            if first[2] or first[1] not in (0xFB, 0xFC):
                arg('W2')
                arg('W3')
                arg('b')
        elif name == 'o5_setVarRange':
            arg('R')
            arg('b')
            for _ in range(i.args[-1][1]):
                if op & 0x80:
                    i.args.append(('w', self.s16(q), False))
                    q += 2
                else:
                    i.args.append(('b', self.u8(q), False))
                    q += 1
        elif name == 'o5_pseudoRoom':
            arg('b')
            while True:
                c = self.u8(q)
                q += 1
                if c == 0:
                    break
                i.args.append(('b', c, False))
        else:
            raise ValueError('manejador sin especificacion: %s' % name)
        i.length = q - p
        return i


def disassemble(code, start=0, end=None, base=0, partial=False):
    """Lista de instrucciones desde `start` hasta `end` (offsets absolutos, `base` = offset de code[0]).

    Con partial=True devuelve (lista, error): si el codigo acaba en mitad de una instruccion o hay un
    opcode sin especificacion, devuelve lo decodificado hasta ahi y el mensaje.
    """
    d = Decoder(code, base)
    end = base + len(code) if end is None else end
    out = []
    p = start
    try:
        while p < end:
            i = d.decode(p)
            out.append(i)
            p += i.length
    except (IndexError, struct.error, ValueError) as e:
        if not partial:
            raise
        return out, 'en %04X: %s' % (p, e)
    return (out, '') if partial else out
