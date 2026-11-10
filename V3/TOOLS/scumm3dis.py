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
