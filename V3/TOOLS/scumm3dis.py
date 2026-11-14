#!/usr/bin/env python3
"""Decodificador de bytecode de SCUMM v3 (Indy3 EGA, ScummEngine_v3old), copiado de ScummVM.

La tabla de opcodes es la de ScummEngine_v5::setupOpcodes, con lo que cambian ScummEngine_v4::setupOpcodes
(drawObject, pickupObject, oldRoomEffect, ifState, ifNotState, saveLoadVars, saveLoadGame) y
ScummEngine_v3::setupOpcodes (setBoxFlags 0x30/0xB0, waitForActor 0x3B/0xBB, waitForSentence 0x4C).
La lectura de parametros es la de cada o5_/o4_/o3_ de script_v5.cpp, script_v4.cpp y script_v3.cpp:
  getVar           u16 de variable; si lleva 0x2000, otra palabra de indice (readVar, version <= 5)
  getResultPos     u16; si lleva 0x2000, otra palabra
  getVarOrDirectByte / Word   variable si el bit del parametro (0x80, 0x40, 0x20) esta en el opcode; si no, u8 / s16
  getWordVararg    lista de (u8 opcode, parametro palabra) hasta 0xFF
Detalles de v3 / Indy3 que trae ScummVM: roomOps lee los dos parametros ANTES del subopcode (version 3); wait no lleva
subopcode en Indy3 (espera al mensaje); getActorX/Y leen un byte en Indy3; actorOps traduce el subopcode con convertTable
(GF_SMALL_HEADER); decodeParseString case 6 lee la altura (version 3); cursorCommand 14 lee dos bytes (version 3).

Uso:
  scumm3dis.py DIR list N                  listado del script global N
  scumm3dis.py DIR check DESCUMM           recorre todos los scripts y compara los limites de instruccion con descumm -3
  scumm3dis.py DIR stats [salida.json]     histograma estatico de opcodes (y subopcodes) en todos los scripts del juego
  scumm3dis.py DIR spec                    comprueba SPEC (la lectura de operandos como datos) contra el Decoder en todos los scripts
"""
import json
import os
import re
import subprocess
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scumm3res as R     # noqa: E402

P1, P2, P3 = 0x80, 0x40, 0x20

NAMES = {}
_T = ('stopObjectCode putActor startMusic getActorRoom isGreaterEqual drawObject getActorElevation setState '
      'isNotEqual faceActor startScript getVerbEntrypoint resourceRoutines walkActorToActor putActorAtObject ifState '
      'getObjectOwner animateActor panCameraTo actorOps print actorFromPos getRandomNr and '
      'jumpRelative doSentence move multiply startSound ifClassOfIs walkActorTo isActorInBox '
      'stopMusic putActor getAnimCounter getActorY loadRoomWithEgo pickupObject setVarRange stringOps '
      'equalZero setOwnerOf startScript delayVariable cursorCommand putActorInRoom delay ifNotState '
      'setBoxFlags getInventoryCount setCameraAt roomOps getDist findObject walkActorToObject startObject '
      'isLessEqual doSentence subtract waitForActor stopSound findInventory walkActorTo drawBox '
      'cutscene putActor chainScript getActorX isLess drawObject increment setState '
      'isEqual faceActor startScript getVerbEntrypoint waitForSentence walkActorToActor putActorAtObject ifState '
      'pickupObject animateActor actorFollowCamera actorOps setObjectName actorFromPos getActorMoving or '
      'beginOverride doSentence add divide oldRoomEffect setClass walkActorTo isActorInBox '
      'freezeScripts putActor stopScript getActorFacing loadRoomWithEgo pickupObject getClosestObjActor getStringWidth '
      'isScriptRunning setOwnerOf startScript debug getActorWidth putActorInRoom stopObjectScript ifNotState '
      'lights getActorCostume loadRoom roomOps getDist findObject walkActorToObject startObject '
      'isGreater doSentence verbOps getActorWalkBox isSoundRunning findInventory walkActorTo drawBox').split()
assert len(_T) == 128, len(_T)
for _i, _n in enumerate(_T):
    NAMES[_i] = _n
    NAMES[_i | 0x80] = _n
# los que difieren en la mitad alta (tabla de ScummEngine_v5 + v4 + v3)
NAMES.update({0x80: 'breakHere', 0x98: 'systemOps', 0xA0: 'stopObjectCode', 0xA7: 'saveLoadVars',
              0xA8: 'notEqualZero', 0xAB: 'saveRestoreVerbs', 0xAC: 'expression', 0xAE: 'wait',
              0xC0: 'endCutscene', 0xC6: 'decrement', 0xCC: 'pseudoRoom', 0xD8: 'printEgo',
              0x22: 'saveLoadGame', 0xA2: 'saveLoadGame', 0x4C: 'waitForSentence'})
# 0x22/0xA2: o4_saveLoadGame (v4 sustituye a getAnimCounter)

ACTOROPS_CONVERT = (1, 0, 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20)   # convertTable de o5_actorOps


class Bad(Exception):
    pass


class Decoder:
    """Lee una instruccion desde pos. Devuelve (nombre, subopcodes, nuevo pos, destino de salto o None)."""

    def __init__(self, code, base=0):
        self.c = code
        self.p = base

    def byte(self):
        if self.p >= len(self.c):
            raise Bad('fin del codigo')
        v = self.c[self.p]
        self.p += 1
        return v

    def word(self):
        lo = self.byte()
        return lo | (self.byte() << 8)

    def sword(self):
        v = self.word()
        return v - 0x10000 if v & 0x8000 else v

    def var(self):
        v = self.word()
        if v & 0x2000:
            self.word()
        return v

    def result(self):
        return self.var()

    def vb(self, op, mask):
        return self.var() if op & mask else self.byte()

    def vw(self, op, mask):
        return self.var() if op & mask else self.sword()

    def vararg(self):
        n = 0
        while True:
            o = self.byte()
            if o == 0xFF:
                return n
            self.vw(o, P1)
            n += 1

    def string(self):
        """resStrLen + 1 (version <= 3, heversion <= 71): 0xFF seguido de un codigo; salvo 1, 2, 3, 8, dos bytes mas."""
        while True:
            ch = self.byte()
            if ch == 0:
                return
            if ch == 0xFF:
                ch = self.byte()
                if ch not in (1, 2, 3, 8):
                    self.byte()
                    self.byte()

    def parse_string(self, subs):
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            k = o & 0x0F
            subs.append('s%d' % k)
            if k == 0:
                self.vw(o, P1)
                self.vw(o, P2)
            elif k == 1:
                self.vb(o, P1)
            elif k == 2:
                self.vw(o, P1)
            elif k == 3:
                self.vw(o, P1)
                self.vw(o, P2)
            elif k == 4:
                pass
            elif k == 6:
                self.vw(o, P1)                     # version 3: altura
            elif k == 7:
                pass
            elif k == 8:
                self.vw(o, P1)
                self.vw(o, P2)
            elif k == 15:
                self.string()
                return
            else:
                raise Bad('decodeParseString %d' % k)

    def insn(self, depth=0):
        op = self.byte()
        name = NAMES[op]
        subs = []
        jump = None
        m = getattr(self, 'o_' + name, None)
        if m is None:
            raise Bad('opcode %02X %s sin decodificar' % (op, name))
        r = m(op, subs)
        if isinstance(r, int):
            jump = r
        return op, name, subs, jump

    def jrel(self):
        off = self.sword()
        return self.p + off

    # ---- uno por funcion de ScummVM
    def o_stopObjectCode(self, op, s): pass
    def o_breakHere(self, op, s): pass
    def o_endCutscene(self, op, s): pass
    def o_stopMusic(self, op, s): pass
    def o_waitForSentence(self, op, s): pass
    def o_wait(self, op, s): pass                          # Indy3: sin subopcode

    def o_putActor(self, op, s):
        self.vb(op, P1); self.vw(op, P2); self.vw(op, P3)

    def o_startMusic(self, op, s): self.vb(op, P1)
    def o_startSound(self, op, s): self.vb(op, P1)
    def o_stopSound(self, op, s): self.vb(op, P1)

    def _res_b(self, op, s):
        self.result(); self.vb(op, P1)
    o_getActorRoom = o_getActorElevation = o_getActorMoving = o_getActorFacing = _res_b
    o_getActorCostume = o_getActorWidth = o_getActorWalkBox = o_getAnimCounter = _res_b
    o_getActorX = o_getActorY = _res_b                     # Indy3: byte
    o_getRandomNr = o_isScriptRunning = o_getInventoryCount = o_isSoundRunning = _res_b
    o_getStringWidth = _res_b

    def _res_w(self, op, s):
        self.result(); self.vw(op, P1)
    o_getObjectOwner = o_move = o_add = o_subtract = o_multiply = o_divide = o_and = o_or = _res_w
    o_getClosestObjActor = _res_w

    def _res_ww(self, op, s):
        self.result(); self.vw(op, P1); self.vw(op, P2)
    o_actorFromPos = o_getDist = o_getVerbEntrypoint = _res_ww

    def _res_bb(self, op, s):
        self.result(); self.vb(op, P1); self.vb(op, P2)
    o_findObject = o_findInventory = _res_bb

    def o_increment(self, op, s): self.result()
    o_decrement = o_increment

    def _cmp(self, op, s):
        self.var(); self.vw(op, P1); return self.jrel()
    o_isGreaterEqual = o_isNotEqual = o_isLessEqual = o_isLess = o_isEqual = o_isGreater = _cmp

    def o_equalZero(self, op, s):
        self.var(); return self.jrel()
    o_notEqualZero = o_equalZero

    def o_jumpRelative(self, op, s):
        return self.jrel()

    def o_drawObject(self, op, s):                         # GF_SMALL_HEADER
        self.vw(op, P1); self.vw(op, P2); self.vw(op, P3)

    def o_setState(self, op, s):
        self.vw(op, P1); self.vb(op, P2)
    o_setOwnerOf = o_setState

    def o_ifState(self, op, s):
        self.vw(op, P1); self.vb(op, P2); return self.jrel()
    o_ifNotState = o_ifState

    def o_faceActor(self, op, s):
        self.vb(op, P1); self.vw(op, P2)
    o_putActorAtObject = o_walkActorToObject = o_faceActor

    def o_startScript(self, op, s):
        self.vb(op, P1); self.vararg()
    o_chainScript = o_startScript

    def o_startObject(self, op, s):
        self.vw(op, P1); self.vb(op, P2); self.vararg()

    def o_resourceRoutines(self, op, s):
        o = self.byte()
        s.append('r%d' % (o & 0x3F))
        if o != 17:
            self.vb(o, P1)
        if (o & 0x3F) == 20:
            self.vw(o, P2)
        elif (o & 0x3F) in (35, 37):
            self.vb(o, P2)
        elif (o & 0x3F) == 36:
            self.vb(o, P2); self.byte()

    def o_walkActorToActor(self, op, s):
        self.vb(op, P1); self.vb(op, P2); self.byte()

    def o_animateActor(self, op, s):
        self.vb(op, P1); self.vb(op, P2)

    def o_panCameraTo(self, op, s): self.vw(op, P1)
    o_setCameraAt = o_panCameraTo
    o_debug = o_panCameraTo
    o_stopObjectScript = o_panCameraTo
    o_pickupObject = o_panCameraTo                         # o4_pickupObject

    def o_actorOps(self, op, s):
        self.vb(op, P1)
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            o = (o & 0xE0) | ACTOROPS_CONVERT[(o & 0x1F) - 1]
            k = o & 0x1F
            s.append('a%d' % k)
            if k in (0, 1, 3, 4, 6, 12, 14, 16, 19, 22, 23):
                self.vb(o, P1)
            elif k in (2, 5, 11):
                self.vb(o, P1); self.vb(o, P2)
            elif k == 7:
                self.vb(o, P1); self.vb(o, P2); self.vb(o, P3)
            elif k in (8, 10, 18, 20, 21):
                pass
            elif k == 9:
                self.vw(o, P1)
            elif k == 13:
                self.string()
            elif k == 17:                                  # version 3: dos parametros
                self.vb(o, P1); self.vb(o, P2)
            else:
                raise Bad('actorOps %d' % k)

    def o_print(self, op, s):
        self.vb(op, P1); self.parse_string(s)

    def o_printEgo(self, op, s):
        self.parse_string(s)

    def o_doSentence(self, op, s):
        v = self.vb(op, P1)
        if v == 0xFE and not (op & P1):
            return
        self.vw(op, P2); self.vw(op, P3)

    def o_ifClassOfIs(self, op, s):
        self.vw(op, P1)
        while True:
            o = self.byte()
            if o == 0xFF:
                break
            self.vw(o, P1)
        return self.jrel()

    def o_setClass(self, op, s):
        self.vw(op, P1)
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            self.vw(o, P1)

    def o_walkActorTo(self, op, s):
        self.vb(op, P1); self.vw(op, P2); self.vw(op, P3)

    def o_isActorInBox(self, op, s):
        self.vb(op, P1); self.vb(op, P2); return self.jrel()

    def o_loadRoomWithEgo(self, op, s):
        self.vw(op, P1); self.vb(op, P2); self.sword(); self.sword()

    def o_setVarRange(self, op, s):
        self.result()
        n = self.byte()
        for _ in range(n):
            if op & 0x80:
                self.sword()
            else:
                self.byte()

    def o_stringOps(self, op, s):
        o = self.byte()
        k = o & 0x1F
        s.append('t%d' % k)
        if k == 1:
            self.vb(o, P1); self.string()
        elif k in (2, 5):
            self.vb(o, P1); self.vb(o, P2)
        elif k == 3:
            self.vb(o, P1); self.vb(o, P2); self.vb(o, P3)
        elif k == 4:
            self.result(); self.vb(o, P1); self.vb(o, P2)
        else:
            raise Bad('stringOps %d' % k)

    def o_delayVariable(self, op, s): self.var()

    def o_cursorCommand(self, op, s):
        o = self.byte()
        k = o & 0x1F
        s.append('c%d' % k)
        if k in (10,):
            self.vb(o, P1); self.vb(o, P2)
        elif k == 11:
            self.vb(o, P1); self.vb(o, P2); self.vb(o, P3)
        elif k in (12, 13):
            self.vb(o, P1)
        elif k == 14:                                      # version 3
            self.vb(o, P1); self.vb(o, P2)

    def o_putActorInRoom(self, op, s):
        self.vb(op, P1); self.vb(op, P2)

    def o_delay(self, op, s):
        self.byte(); self.byte(); self.byte()

    def o_setBoxFlags(self, op, s):                        # o3_setBoxFlags
        self.vb(op, P1); self.byte()

    def o_roomOps(self, op, s):
        self.vw(op, P1); self.vw(op, P2)                   # version 3: parametros antes del subopcode
        o = self.byte()
        k = o & 0x1F
        s.append('m%d' % k)
        if k in (1, 2, 3, 4, 5, 6):
            pass
        elif k == 7:
            self.vb(o, P1); self.vb(o, P2)
            o = self.byte(); self.vb(o, P1); self.vb(o, P2)
            o = self.byte(); self.vb(o, P2)
        elif k == 8:
            self.vb(o, P1); self.vb(o, P2); self.vb(o, P3)
        elif k == 9:
            self.vb(o, P1); self.vb(o, P2)
        elif k == 10:
            self.vw(o, P1)
        elif k in (11, 12):
            self.vw(o, P1); self.vw(o, P2); self.vw(o, P3)
            o = self.byte(); self.vb(o, P1); self.vb(o, P2)
        elif k in (13, 14):
            self.vb(o, P1); self.string()
        elif k == 15:
            self.vb(o, P1)
            o = self.byte(); self.vb(o, P1); self.vb(o, P2)
            o = self.byte(); self.vb(o, P1)
        elif k == 16:
            self.vb(o, P1); self.vb(o, P2)
        else:
            raise Bad('roomOps %d' % k)

    def o_waitForActor(self, op, s): self.vb(op, P1)       # o3_waitForActor

    def o_drawBox(self, op, s):
        self.vw(op, P1); self.vw(op, P2)
        o = self.byte()
        self.vw(o, P1); self.vw(o, P2); self.vb(o, P3)

    def o_cutscene(self, op, s): self.vararg()

    def o_actorFollowCamera(self, op, s): self.vb(op, P1)

    def o_setObjectName(self, op, s):
        self.vw(op, P1); self.string()

    def o_beginOverride(self, op, s): self.byte()

    def o_oldRoomEffect(self, op, s):
        o = self.byte()
        if (o & 0x1F) == 3:
            self.vw(o, P1)

    def o_freezeScripts(self, op, s): self.vb(op, P1)
    def o_stopScript(self, op, s): self.vb(op, P1)

    def o_lights(self, op, s):
        self.vb(op, P1); self.byte(); self.byte()

    def o_loadRoom(self, op, s): self.vb(op, P1)

    def o_verbOps(self, op, s):
        self.vb(op, P1)
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            k = o & 0x1F
            s.append('v%d' % k)
            if k == 1:
                self.vw(o, P1)
            elif k == 2:
                self.string()
            elif k in (3, 4, 16, 18, 23):
                self.vb(o, P1)
            elif k == 5:
                self.vw(o, P1); self.vw(o, P2)
            elif k in (6, 7, 8, 9, 17, 19):
                pass
            elif k == 20:
                self.vw(o, P1)
            elif k == 22:
                self.vw(o, P1); self.vb(o, P2)
            else:
                raise Bad('verbOps %d' % k)

    def o_systemOps(self, op, s):
        s.append('y%d' % self.byte())

    def o_saveLoadVars(self, op, s):                       # o4_saveLoadVars: saveVars / loadVars
        s.append('save' if self.byte() == 1 else 'load')
        while True:
            o = self.byte()
            if o == 0:
                return
            k = o & 0x1F
            if k == 1:
                self.result(); self.result()
            elif k == 2:
                self.vb(o, P1); self.vb(o, P2)
            elif k == 3:
                self.string()
            elif k in (4, 0x1F):
                return

    def o_saveLoadGame(self, op, s):                       # o4_saveLoadGame
        self.result(); self.vb(op, P1)

    def o_saveRestoreVerbs(self, op, s):
        o = self.byte()
        s.append('w%d' % o)
        self.vb(o, P1); self.vb(o, P2); self.vb(o, P3)

    def o_expression(self, op, s):
        self.result()
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            k = o & 0x1F
            s.append('e%d' % k)
            if k == 1:
                self.vw(o, P1)
            elif k == 6:
                _, name, sub2, _ = self.insn()
                s.append('(' + name + ')')
            elif k in (2, 3, 4, 5):
                pass
            else:
                raise Bad('expression %d' % k)

    def o_pseudoRoom(self, op, s):
        self.byte()
        while self.byte() != 0:
            pass


# ---------------------------------------------------------------------------------------- scripts del juego
def all_scripts(ix):
    """Lista (etiqueta, codigo) de todos los scripts: globales, locales, entrada/salida y verbos de objetos."""
    out = []
    for i in range(len(ix.res['script'])):
        r = ix.resource('script', i)
        if r is not None:
            out.append(('script-%d' % i, r[4:], [0]))
    for rn in ix.rooms():
        room = R.Room(ix, rn)
        for sid, code in sorted(room.local_code.items()):
            out.append(('room-%d-local-%d' % (rn, sid), code, [0]))
        if room.encd_off:
            out.append(('room-%d-entry' % rn, room.entry_script(), [0]))
        if room.excd_off:
            out.append(('room-%d-exit' % rn, room.exit_script(), [0]))
        for o in room.objects:
            starts = sorted(set(off for _, off in o.verbs if off < o.size))
            if starts:
                out.append(('room-%d-obj-%d' % (rn, o.id), o.block, starts))
    return out


def sweep(code, starts):
    """Recorrido lineal desde el primer punto de entrada hasta el final: [(pos, op, name, subs)]."""
    res = []
    p = min(starts)
    d = Decoder(code, p)
    while d.p < len(code):
        pos = d.p
        op, name, subs, j = d.insn()
        res.append((pos, op, name, subs))
    return res


def stats(ix):
    ops, subs, fails = Counter(), Counter(), []
    nbytes = 0
    for label, code, starts in all_scripts(ix):
        try:
            for pos, op, name, sb in sweep(code, starts):
                ops[name] += 1
                for x in sb:
                    subs[name + '.' + x] += 1
            nbytes += len(code) - min(starts)
        except Bad as e:
            fails.append((label, str(e)))
    return ops, subs, fails, nbytes


def descumm_offsets(descumm, code, starts, tmp):
    with open(tmp, 'wb') as f:
        f.write(bytes(4) + code[min(starts):])    # descumm -3 -u se salta 4 bytes de cabecera igualmente
    res = subprocess.run([descumm, '-3', '-u', '-o', '-i', '-e', '-f', '-w', '-b', tmp], capture_output=True, text=True)
    offs = []
    for ln in res.stdout.splitlines():
        m = re.match(r'^\[([0-9A-F]{4})\]', ln)
        if m:
            offs.append(int(m.group(1), 16))
    return offs, res.stdout


def check(ix, descumm):
    tmp = os.path.join(os.environ.get('TEMP', '.'), 'scumm3dis_tmp.bin')
    ok = bad = 0
    why = Counter()
    verbose = os.environ.get('V')
    for label, code, starts in all_scripts(ix):
        base = min(starts)
        try:
            mine = [pos - base for pos, _, _, _ in sweep(code, starts)]
        except Bad as e:
            print('%s: mio falla: %s' % (label, e))
            bad += 1
            continue
        theirs, txt = descumm_offsets(descumm, code, starts, tmp)
        if sorted(set(theirs)) == sorted(set(mine)):
            ok += 1
        else:
            # la primera instruccion mia que descumm parte de otra manera
            ins = sweep(code, starts)
            ts = set(theirs)
            first = None
            for k, (pos, op, name, sb) in enumerate(ins):
                nxt = ins[k + 1][0] - base if k + 1 < len(ins) else None
                if pos - base not in ts or (nxt is not None and nxt not in ts):
                    first = (pos - base, op, name)
                    break
            why[first[2] if first else '?'] += 1
            bad += 1
            if verbose:
                print('%s: distinto desde %s' % (label, first))
    print('scripts iguales: %d, distintos: %d; primera instruccion distinta: %s' % (ok, bad, dict(why)))
    return bad


# ---------------------------------------------------------------------------------------- especificacion de operandos (datos)
# La lectura de operandos de cada opcode como DATOS, para el Z80 (V3/TOOLS/gen_vmtables3.py la convierte en tables3.inc) y para
# el modelo (vmmodel3.py, modo nucleo: las instrucciones que van al anfitrion se decodifican con run_spec). La orden `spec` la
# comprueba contra el Decoder de arriba en todos los scripts del juego: mismas longitudes de instruccion.
#
# Fichas simples:
#   R  getResultPos (u16; con 0x2000, otra palabra)       v  getVar
#   B1 B2 B3  getVarOrDirectByte (bit 0x80, 0x40, 0x20 del opcode en curso)    W1 W2 W3  getVarOrDirectWord
#   b  byte    w  palabra    J  salto relativo (s16)    L  getWordVararg (u8 opcode + W1, hasta 0xFF)
#   S  cadena (resStrLen: 0xFF + codigo; salvo 1, 2, 3 y 8, dos bytes mas)
#   O  byte que pasa a ser el opcode en curso (para las mascaras siguientes), sin argumento     o  igual, y es argumento
#   Q  si el ultimo valor leido es 0xFE, la instruccion acaba (doSentence)
#   X  la instruccion acaba aqui (dentro de una lista: print 15, saveLoadVars 4 y 31)
#   Z  bytes hasta un 0 (pseudoRoom)           N  setVarRange: u8 n y n valores (palabra si el bit 0x80 del opcode, si no byte)
#   E  lista de expression (solo para la comprobacion: el Z80 y el modelo la hacen a mano)
# Fichas compuestas (tuplas):
#   ('SW', mascara, {k: fichas}, por_omision)       un subopcode: byte -> opcode en curso, k = byte & mascara (es argumento)
#   ('LOOP', fin, mascara, conv, {k: fichas}, por_omision)   lista de subopcodes hasta el byte `fin`; conv = traduccion de actorOps
#   por_omision: None = subopcode desconocido (E_BADSUB), () = sin operandos
SUB_BAD = None
_RES_B = 'R B1'
_RES_W = 'R W1'
SPEC = {
    'stopObjectCode': '', 'breakHere': '', 'endCutscene': '', 'stopMusic': '', 'waitForSentence': '', 'wait': '',
    'putActor': 'B1 W2 W3', 'walkActorTo': 'B1 W2 W3', 'drawObject': 'W1 W2 W3',
    'startMusic': 'B1', 'startSound': 'B1', 'stopSound': 'B1', 'waitForActor': 'B1', 'actorFollowCamera': 'B1',
    'freezeScripts': 'B1', 'stopScript': 'B1', 'loadRoom': 'B1',
    'getActorRoom': _RES_B, 'getActorElevation': _RES_B, 'getActorMoving': _RES_B, 'getActorFacing': _RES_B,
    'getActorCostume': _RES_B, 'getActorWidth': _RES_B, 'getActorWalkBox': _RES_B, 'getAnimCounter': _RES_B,
    'getActorX': _RES_B, 'getActorY': _RES_B, 'getRandomNr': _RES_B, 'isScriptRunning': _RES_B,
    'getInventoryCount': _RES_B, 'isSoundRunning': _RES_B, 'getStringWidth': _RES_B, 'saveLoadGame': _RES_B,
    'getObjectOwner': _RES_W, 'move': _RES_W, 'add': _RES_W, 'subtract': _RES_W, 'multiply': _RES_W, 'divide': _RES_W,
    'and': _RES_W, 'or': _RES_W, 'getClosestObjActor': _RES_W,
    'actorFromPos': 'R W1 W2', 'getDist': 'R W1 W2', 'getVerbEntrypoint': 'R W1 W2',
    'findObject': 'R B1 B2', 'findInventory': 'R B1 B2',
    'increment': 'R', 'decrement': 'R',
    'isGreaterEqual': 'v W1 J', 'isNotEqual': 'v W1 J', 'isLessEqual': 'v W1 J', 'isLess': 'v W1 J', 'isEqual': 'v W1 J',
    'isGreater': 'v W1 J', 'equalZero': 'v J', 'notEqualZero': 'v J', 'jumpRelative': 'J',
    'setState': 'W1 B2', 'setOwnerOf': 'W1 B2', 'ifState': 'W1 B2 J', 'ifNotState': 'W1 B2 J',
    'faceActor': 'B1 W2', 'putActorAtObject': 'B1 W2', 'walkActorToObject': 'B1 W2',
    'startScript': 'B1 L', 'chainScript': 'B1 L', 'startObject': 'W1 B2 L', 'cutscene': 'L',
    'walkActorToActor': 'B1 B2 b', 'animateActor': 'B1 B2', 'putActorInRoom': 'B1 B2', 'isActorInBox': 'B1 B2 J',
    'panCameraTo': 'W1', 'setCameraAt': 'W1', 'debug': 'W1', 'stopObjectScript': 'W1', 'pickupObject': 'W1',
    'doSentence': 'B1 Q W2 W3', 'ifClassOfIs': 'W1 L J', 'setClass': 'W1 L', 'loadRoomWithEgo': 'W1 B2 w w',
    'setVarRange': 'R N', 'delayVariable': 'v', 'delay': 'b b b', 'setBoxFlags': 'B1 b', 'drawBox': 'W1 W2 O W1 W2 B3',
    'setObjectName': 'W1 S', 'beginOverride': 'b', 'lights': 'B1 b b', 'systemOps': 'b', 'saveRestoreVerbs': 'o B1 B2 B3',
    'expression': 'R E', 'pseudoRoom': 'b Z',
}
_RR = {k: ('B1',) for k in range(64)}
_RR[17] = ()
_RR[20] = ('B1', 'W2')
_RR[35] = _RR[37] = ('B1', 'B2')
_RR[36] = ('B1', 'B2', 'b')
SPEC['resourceRoutines'] = [('SW', 0x3F, _RR, SUB_BAD)]
SPEC['cursorCommand'] = [('SW', 0x1F, {10: 'B1 B2', 11: 'B1 B2 B3', 12: 'B1', 13: 'B1', 14: 'B1 B2'}, ())]
SPEC['stringOps'] = [('SW', 0x1F, {1: 'B1 S', 2: 'B1 B2', 3: 'B1 B2 B3', 4: 'R B1 B2', 5: 'B1 B2'}, SUB_BAD)]
SPEC['oldRoomEffect'] = [('SW', 0x1F, {3: 'W1'}, ())]
_ROOM = {k: () for k in range(1, 7)}
_ROOM.update({7: 'B1 B2 O B1 B2 O B2', 8: 'B1 B2 B3', 9: 'B1 B2', 10: 'W1', 11: 'W1 W2 W3 O B1 B2', 12: 'W1 W2 W3 O B1 B2',
              13: 'B1 S', 14: 'B1 S', 15: 'B1 O B1 B2 O B1', 16: 'B1 B2'})
SPEC['roomOps'] = ['W1', 'W2', ('SW', 0x1F, _ROOM, SUB_BAD)]
_ACT = {k: 'B1' for k in (0, 1, 3, 4, 6, 12, 14, 16, 19, 22, 23)}
_ACT.update({k: 'B1 B2' for k in (2, 5, 11, 17)})
_ACT.update({k: () for k in (8, 10, 18, 20, 21)})
_ACT.update({7: 'B1 B2 B3', 9: 'W1', 13: 'S'})
SPEC['actorOps'] = ['B1', ('LOOP', 0xFF, 0x1F, 'actor', _ACT, SUB_BAD)]
_PARSE = {0: 'W1 W2', 1: 'B1', 2: 'W1', 3: 'W1 W2', 4: (), 6: 'W1', 7: (), 8: 'W1 W2', 15: 'S X'}
SPEC['print'] = ['B1', ('LOOP', 0xFF, 0x0F, None, _PARSE, SUB_BAD)]
SPEC['printEgo'] = [('LOOP', 0xFF, 0x0F, None, _PARSE, SUB_BAD)]
_VERB = {1: 'W1', 2: 'S', 5: 'W1 W2', 20: 'W1', 22: 'W1 B2'}
_VERB.update({k: 'B1' for k in (3, 4, 16, 18, 23)})
_VERB.update({k: () for k in (6, 7, 8, 9, 17, 19)})
SPEC['verbOps'] = ['B1', ('LOOP', 0xFF, 0x1F, None, _VERB, SUB_BAD)]
SPEC['saveLoadVars'] = ['b', ('LOOP', 0x00, 0x1F, None, {1: 'R R', 2: 'B1 B2', 3: 'S', 4: 'X', 31: 'X'}, ())]


def spec_tokens(t):
    """Fichas de una especificacion (cadena, tupla o lista) como lista: las cadenas se parten por espacios."""
    if isinstance(t, str):
        return t.split()
    out = []
    for x in t:
        out += x.split() if isinstance(x, str) else [x]
    return out


class SpecEnd(Exception):
    """X o Q: la instruccion acaba."""


def run_spec(name, rd):
    """Lee los operandos del opcode `name` con el lector `rd`, que da: byte(), word() (u16), sword(), var() (getVar: el valor),
    result() (getResultPos: el numero de variable ya resuelto), opcode (atributo: el opcode en curso), string() (bytes en bruto, sin
    el 0 final), expr() (lista de expression) y bad(k) (subopcode desconocido: lanza). Devuelve (args, resultado, salto): args son
    los valores en el orden en que se leen (subopcodes incluidos, cadenas como bytes), resultado el numero de variable de la R de
    arriba (o None) y salto el desplazamiento de la J (o None)."""
    args, st = [], {'res': None, 'jump': None, 'last': None}
    top = rd.opcode

    def val(v):
        st['last'] = v
        args.append(v)

    def vb(mask):
        return rd.var() if rd.opcode & mask else rd.byte()

    def vw(mask):
        return rd.var() if rd.opcode & mask else rd.sword()

    def run(toks, first):
        for k, t in enumerate(toks):
            if isinstance(t, tuple):
                if t[0] == 'SW':
                    _, mask, table, dflt = t
                    sub(mask, None, table, dflt)
                else:
                    _, end, mask, conv, table, dflt = t
                    while True:
                        o = rd.byte()
                        if o == end:
                            break
                        rd.opcode = o
                        sub(mask, conv, table, dflt, o)
                continue
            if t == 'R':
                r = rd.result()
                if first and k == 0:
                    st['res'] = r
                val(r)
            elif t == 'v':
                val(rd.var())
            elif t[0] == 'B':
                val(vb({'1': 0x80, '2': 0x40, '3': 0x20}[t[1]]))
            elif t[0] == 'W':
                val(vw({'1': 0x80, '2': 0x40, '3': 0x20}[t[1]]))
            elif t == 'b':
                val(rd.byte())
            elif t == 'w':
                val(rd.word())
            elif t == 'J':
                st['jump'] = rd.sword()
            elif t == 'L':
                while True:
                    o = rd.byte()
                    if o == 0xFF:
                        break
                    rd.opcode = o
                    val(vw(0x80))
            elif t == 'S':
                val(rd.string())
            elif t in ('O', 'o'):
                o = rd.byte()
                rd.opcode = o
                if t == 'o':
                    val(o)
            elif t == 'Q':
                if st['last'] == 0xFE:
                    raise SpecEnd()
            elif t == 'X':
                raise SpecEnd()
            elif t == 'Z':
                while True:
                    c = rd.byte()
                    if c == 0:
                        break
                    val(c)
            elif t == 'N':
                n = rd.byte()
                val(n)
                for _ in range(n):
                    val(rd.sword() if top & 0x80 else rd.byte())
            elif t == 'E':
                rd.expr()
            else:
                raise ValueError(t)

    def sub(mask, conv, table, dflt, o=None):
        if o is None:
            o = rd.byte()
            rd.opcode = o
        if conv == 'actor':
            i = (o & 0x1F) - 1
            if not 0 <= i < len(ACTOROPS_CONVERT):
                rd.bad(o & 0x1F)
            o = (o & 0xE0) | ACTOROPS_CONVERT[i]
            rd.opcode = o
        k = o & mask
        val(k)
        toks = table.get(k, dflt)
        if toks is None:
            rd.bad(k)
        run(spec_tokens(toks), False)

    try:
        run(spec_tokens(SPEC[name]), True)
    except SpecEnd:
        pass
    rd.opcode = top
    return args, st['res'], st['jump']


class _StaticReader:
    """Lector de run_spec sobre el Decoder, sin valores de variables (las variables leidas valen None): para comprobar longitudes."""

    def __init__(self, dec, op):
        self.d, self.opcode = dec, op

    def byte(self):
        return self.d.byte()

    def word(self):
        return self.d.word()

    def sword(self):
        return self.d.sword()

    def var(self):
        self.d.var()
        return None

    def result(self):
        return self.d.result()

    def string(self):
        s = self.d.p
        self.d.string()
        return bytes(self.d.c[s:self.d.p - 1])

    def expr(self):
        while True:
            o = self.d.byte()
            if o == 0xFF:
                return
            k = o & 0x1F
            if k == 1:
                self.d.vw(o, P1)
            elif k == 6:
                op = self.d.byte()
                run_spec(NAMES[op], _StaticReader(self.d, op))
            elif k not in (2, 3, 4, 5):
                raise Bad('expression %d' % k)

    def bad(self, k):
        raise Bad('subopcode %d' % k)


def check_spec(ix):
    """Recorre todos los scripts: la longitud de cada instruccion con SPEC tiene que ser la del Decoder. Devuelve (instrucciones,
    distintas, maximo de argumentos, donde)."""
    n = bad = maxargs = 0
    worst = None
    for label, code, starts in all_scripts(ix):
        try:
            ins = sweep(code, starts)
        except Bad:
            continue
        for k, (pos, op, name, sb) in enumerate(ins):
            end = ins[k + 1][0] if k + 1 < len(ins) else len(code)
            d = Decoder(code, pos + 1)
            try:
                args, _, _ = run_spec(name, _StaticReader(d, op))
            except Bad as e:
                bad += 1
                print('%s [%04X] %s: %s' % (label, pos, name, e))
                continue
            n += 1
            if d.p != end:
                bad += 1
                print('%s [%04X] %s: SPEC lee %d bytes, el Decoder %d' % (label, pos, name, d.p - pos, end - pos))
            if len(args) > maxargs:
                maxargs, worst = len(args), (label, pos, name)
    return n, bad, maxargs, worst


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    ix = R.Index(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == 'list':
        code = ix.resource('script', int(sys.argv[3]))[4:]
        for pos, op, name, sb in sweep(code, [0]):
            print('[%04X] %02X %s %s' % (pos, op, name, ' '.join(sb)))
    elif cmd == 'check':
        return 1 if check(ix, sys.argv[3]) else 0
    elif cmd == 'spec':
        n, bad, mx, worst = check_spec(ix)
        print('instrucciones: %d, distintas: %d; maximo de argumentos: %d (%s)' % (n, bad, mx, worst))
        return 1 if bad else 0
    elif cmd == 'stats':
        ops, subs, fails, nbytes = stats(ix)
        print('bytes de codigo: %d, opcodes distintos: %d, instrucciones: %d' % (nbytes, len(ops), sum(ops.values())))
        for k, v in ops.most_common():
            print('  %-22s %6d' % (k, v))
        print('fallos:', fails[:10])
        if len(sys.argv) > 3:
            with open(sys.argv[3], 'w') as f:
                json.dump(dict(ops=ops, subs=subs, fails=fails, bytes=nbytes), f, indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main())
