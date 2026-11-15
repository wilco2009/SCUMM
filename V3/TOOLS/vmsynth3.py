#!/usr/bin/env python3
"""Escenarios SINTETICOS del nucleo v3 (fase 4b-1): scripts de bytecode generados al azar con los 22 opcodes de la fase 4b-1
(y unos pocos de apoyo), para recorrer las ramas que los scripts de Indy3 no tocan (copyString, createString, subopcodes de
actorOps y verbOps poco usados, roomOps 7-16, saveRestoreVerbs 3...). Son la contrapartida de V2/TOOLS/vmsynth.py.

Orden de escenario nueva: CODE <hex>   ejecuta el bytecode como un script global (numero SYNTH_SCRIPT, codigo desde el inicio de su
pagina). El codigo acaba siempre en stopObjectCode (0x00). Lo usan vmmodel3.run_scenario_core (modelo) y test_vm.cpp (Z80).
Los parametros que admiten variable (bits 0x80, 0x40, 0x20) se pasan unas veces directos y otras por variable (una instruccion
`move` antes de la instruccion). Uso: lo llama vmmodel3.py scenarios-core (se anaden a los escenarios de las salas).
"""
import struct

import scumm3dis as DIS

SYNTH_SCRIPT = 199                      # numero de script global que no existe en Indy3 (los globales son 0-199)
FL = (0x80, 0x40, 0x20)

CANDS = {}
for _o in range(256):
    CANDS.setdefault(DIS.NAMES[_o], []).append(_o)
BASE = {n: min(c) for n, c in CANDS.items()}
VARMASK = {}
for _n, _c in CANDS.items():
    m = 0
    for _o in _c:
        m |= _o ^ BASE[_n]
    VARMASK[_n] = m


class Asm:
    def __init__(self, rng, varprob=0.25):
        self.rng = rng
        self.varprob = varprob
        self.out = bytearray()
        self.nv = 0
        self.start = 0
        self.objs = []                  # fase 5: objetos de la sala y del inventario, para los nombres ($FF 6) de los mensajes

    # ---- operandos
    def begin(self):
        """Empieza una instruccion: las `move` de los parametros por variable se insertan aqui, antes de su primer byte."""
        self.start = len(self.out)

    def var(self, value):
        """Una instruccion `move` que deja `value` en una variable de trabajo (224..255); devuelve el numero de variable."""
        vn = 224 + self.nv % 32
        self.nv += 1
        mv = bytes([0x1A]) + struct.pack('<HH', vn, value & 0xFFFF)
        self.out[self.start:self.start] = mv
        self.start += len(mv)
        return vn

    def params(self, spec, allowed=0xE0):
        """spec: lista de (tipo, valor), tipo 'b' (byte) o 'w' (palabra); el i-esimo usa el flag FL[i] (si `allowed` lo admite)."""
        flags = 0
        body = bytearray()
        for i, (k, v) in enumerate(spec):
            if (allowed & FL[i]) and self.rng.random() < self.varprob:
                flags |= FL[i]
                body += struct.pack('<H', self.var(v))
            else:
                body += bytes([v & 0xFF]) if k == 'b' else struct.pack('<H', v & 0xFFFF)
        return flags, bytes(body)

    def result(self):
        return struct.pack('<H', 216 + self.rng.randrange(8))

    def op(self, name, spec=(), pre=b'', post=b''):
        """Un opcode con sus parametros: [opcode | flags] [pre] [parametros] [post]. pre y post son bytes literales (resultado, jump...)."""
        flags, body = self.params(list(spec), VARMASK[name])
        self.out += bytes([BASE[name] | flags]) + pre + body + post

    def sub(self, kbyte, spec=(), allowed=0xE0, post=b''):
        """Un subopcode: byte (k | flags) y sus parametros (los flags son de este byte)."""
        flags, body = self.params(list(spec), allowed)
        self.out += bytes([kbyte | flags]) + body + post

    def msg_var(self, code):
        """Numero de variable para un codigo $FF 4-7 de un mensaje: unas veces una variable de trabajo con un valor que da algo
        (un numero, un verbo, un actor o un objeto, una cadena), otras una variable cualquiera, un local o un bit; muy pocas, con 0x2000."""
        r = self.rng
        x = r.random()
        if code == 6 and self.objs and x < 0.5:
            return self.var(r.choice(self.objs))
        if x < 0.55:
            val = {4: r.choice([0, 1, -1, 7, 42, 100, 255, 1000, -300, 32767, -32768]),
                   5: r.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 99]),
                   6: r.choice([0, 1, 2, 3, 5, 12, 13, 50, -1, 60, 500, 1000]),
                   7: r.choice([0, 1, 2, 3, 3, 4, 31, 32, -1])}[code]
            return self.var(val)
        if x < 0.8:
            return r.choice([0, 1, 2, 3, 20, 100, 224, 225, 255])
        if x < 0.9:
            return 0x4000 | r.randrange(0, 16 if r.random() < 0.9 else 20)
        if x < 0.97:
            return 0x8000 | (r.randrange(0, 256) << 4) | r.randrange(0, 16)
        return r.choice([0x2000 | 5, 0x1000 | 3, 0x0100])

    def raw_string(self, long=False):
        """Una cadena en bruto del script (con su 0 final) con codigos $FF de mensaje: 1, 2, 3 y 8 sin datos; 4 (numero), 5 (verbo),
        6 (nombre), 7 (cadena) con una variable; 9, 10, 12, 13 y 14 con dos bytes; unos codigos invalidos (que read_raw_string si salta pero
        el convertidor no); la arroba y algun $FE."""
        r = self.rng
        s = bytearray()
        for _ in range(r.randrange(0, 12) if not long else r.randrange(150, 260)):
            x = r.random()
            if x < 0.12 and not long:
                code = r.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 4, 5, 6, 7])
                s += bytes([0xFF, code])
                if code in (4, 5, 6, 7):
                    s += struct.pack('<H', self.msg_var(code))
                elif code not in (1, 2, 3, 8):
                    s += bytes([r.randrange(0, 256) if r.random() < 0.3 else r.randrange(1, 40), r.randrange(1, 255)])
            elif x < 0.14 and not long:
                s += bytes([0xFF, r.choice([0, 11, 15, 16, 31, 200]), r.randrange(0, 255), r.randrange(1, 255)])
            elif x < 0.17:
                s.append(0x40)
            elif x < 0.18:
                s.append(0xFE)
            else:
                s.append(r.randrange(32, 127))
        s.append(0)
        return bytes(s)


def pick(r, small, big=(), pbig=0.04):
    return r.choice(big) if big and r.random() < pbig else r.choice(small)


def gen_state_class(a, r):
    obj = pick(r, [0, 1, 2, 3, 12, 13, 14, 50, 100, 500], [999, 1000, 4000, 0xFFFF])
    cls = lambda: pick(r, [1, 2, 3, 8, 9, 18, 19, 20, 21, 22, 23, 24, 29, 30, 31, 32], [0, 25, 33, 127]) | (0x80 if r.random() < 0.6 else 0)
    j = struct.pack('<h', 0)               # (un salto de otra cosa dejaria el codigo desalineado)
    k = r.randrange(5)
    if k == 0:
        a.op('setState', [('w', obj), ('b', pick(r, [0, 1, 2, 7, 255], [256, 1000]))])
    elif k == 1:
        a.op('ifState', [('w', obj), ('b', pick(r, [0, 1, 2, 7, 255], [256]))], post=j)
    elif k == 2:
        a.op('ifNotState', [('w', obj), ('b', pick(r, [0, 1, 2, 7, 255], [256]))], post=j)
    elif k == 3:
        a.op('setClass', [('w', obj)])
        for _ in range(r.randrange(0, 4)):
            f, body = a.params([('w', cls())], 0x80)
            a.out += bytes([r.randrange(1, 0x60) | f]) + body
        a.out.append(0xFF)
    else:
        a.op('ifClassOfIs', [('w', obj)])
        for _ in range(r.randrange(0, 4)):
            f, body = a.params([('w', cls())], 0x80)
            a.out += bytes([r.randrange(1, 0x60) | f]) + body
        a.out.append(0xFF)
        a.out += j


def gen_inventory(a, r):
    k = r.randrange(3)
    if k == 0:
        a.op('findInventory', [('b', r.choice([0, 1, 2, 3, 5, 6, 15, 255])), ('b', r.choice([0, 1, 2, 3, 4, 9, 80]))], pre=a.result())
    elif k == 1:
        a.op('getInventoryCount', [('b', r.choice([0, 1, 2, 3, 5, 6, 15, 255]))], pre=a.result())
    else:
        a.op('getActorWidth', [('b', pick(r, [0, 1, 2, 5, 12], [13, 255]))], pre=a.result())


def gen_string(a, r):
    sid = lambda: pick(r, [0, 1, 2, 3, 0, 1, 2, 3, 4, 5, 8, 31], [32, 33, 255], 0.02)
    k = r.choice([1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 6, 0])
    if k == 1:
        a.out.append(0x27)
        flags, body = a.params([('b', sid())], 0x80)
        a.out += bytes([1 | flags]) + body + a.raw_string()
    elif k == 2:
        a.out.append(0x27)
        a.sub(2, [('b', sid()), ('b', sid())])
    elif k == 3:
        a.out.append(0x27)
        a.sub(3, [('b', sid()), ('b', pick(r, [0, 1, 2, 3, 5, 8, 11, 12, 13, 20, 255])), ('b', r.randrange(0, 256))])
    elif k == 4:
        a.out.append(0x27)
        flags, body = a.params([('b', sid()), ('b', pick(r, [0, 1, 2, 3, 5, 8, 11, 12, 255]))], 0xC0)
        a.out += bytes([4 | flags]) + a.result() + body
    elif k == 5:
        a.out.append(0x27)
        a.sub(5, [('b', sid()), ('b', pick(r, [0, 1, 2, 5, 20, 40, 100, 200], [255, 256, 300]))])
    elif k == 6:
        a.op('getStringWidth', [('b', sid())], pre=a.result())
    else:
        a.out += bytes([0x27, 7])           # subopcode sin efecto


def gen_cursor(a, r):
    k = r.choice([1, 2, 3, 4, 5, 6, 7, 8, 8, 10, 11, 12, 13, 14, 9, 0])
    a.out.append(0x2C)
    spec = {10: 2, 11: 3, 12: 1, 13: 1, 14: 2}.get(k, 0)
    a.sub(k, [('b', pick(r, [0, 1, 2, 3, 5, 100], [4, 255])) for _ in range(spec)])


def gen_verbs(a, r):
    vid = lambda: pick(r, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [0, 99, 100, 255, 256])
    k = r.randrange(4)
    if k <= 1:                                              # verbOps con una lista de subopcodes
        a.op('verbOps', [('b', vid())])
        for _ in range(r.randrange(1, 7)):
            s = r.choice([9, 9, 2, 2, 3, 4, 5, 6, 7, 8, 16, 17, 18, 19, 22, 23, 1] + ([20, 0, 10] if r.random() < 0.05 else []))
            if s == 2:
                a.out.append(2)
                a.out += a.raw_string()
            elif s in (3, 4, 16, 18, 23):
                a.sub(s, [('b', r.randrange(0, 256))])
            elif s == 5:
                a.sub(5, [('w', r.randrange(0, 330)), ('w', r.randrange(0, 200))])
            elif s == 1:
                a.sub(1, [('w', r.randrange(0, 5))])
            elif s == 22:
                a.sub(22, [('w', r.randrange(0, 5)), ('b', r.randrange(0, 3))])
            else:
                a.out.append(s)
        a.out.append(0xFF)
    else:                                                   # saveRestoreVerbs (con parametros directos: el subopcode va sin bits)
        sub = r.choice([1, 1, 2, 2, 3, 3] + ([0, 4] if r.random() < 0.05 else []))
        lo = r.randrange(0, 12)
        a.out += bytes([BASE['saveRestoreVerbs'], sub, lo, lo + r.randrange(0, 4), r.choice([0, 1, 2, 3, 4])])


CONV = DIS.ACTOROPS_CONVERT


def gen_actor(a, r):
    act = pick(r, [0, 1, 2, 3, 4, 5, 6, 12], [13, 255])
    a.op('actorOps', [('b', act)])
    for _ in range(r.randrange(1, 6)):
        o = pick(r, [x for x in range(1, 21) if x != 17], [0, 17, 21, 22, 31], 0.01)
        bv = lambda: ('b', r.choice([0, 1, 2, 3, 4, 5, 8, 15, 24, 31, 1, 2, 3, 32, 100, 255]))
        if not 1 <= o <= 20:
            a.out.append(o)
            continue
        k = CONV[o - 1]                                     # act_conv: el subopcode de v3 se traduce a la funcion k de v5
        if k in (0, 1, 3, 4, 6, 12, 14, 16, 19, 22, 23):
            a.sub(o, [bv()])
        elif k in (2, 5, 11, 17):
            a.sub(o, [bv(), bv()])
        elif k == 7:
            a.sub(o, [bv(), bv(), bv()])
        elif k == 9:
            a.sub(o, [('w', r.choice([0, 1, 5, 40, 100, 0xFFF0]))])
        elif k == 13:
            a.out.append(o)
            a.out += a.raw_string()
        else:
            a.out.append(o)
    a.out.append(0xFF)


def gen_room(a, r):
    k = r.randrange(5)
    if k == 0:
        sub = r.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 13, 14, 0, 17])
        w = lambda: ('w', pick(r, [0, 100, 160, 200, 320, 400, 700, 0xFF00], [257, 256, 0xFFFF]))
        a.op('roomOps', [w(), ('w', pick(r, [0, 100, 160, 200, 320, 400, 700]))])
        bv = lambda: ('b', r.randrange(0, 20))
        if sub in (7,):
            a.sub(7, [bv(), bv()])
            a.sub(r.randrange(0, 32), [bv(), bv()])
            a.sub(r.randrange(0, 32), [bv()])
        elif sub in (8,):
            a.sub(8, [bv(), bv(), bv()])
        elif sub == 9:
            a.sub(9, [bv(), bv()])
        elif sub == 10:
            a.sub(10, [('w', r.randrange(0, 500))])
        elif sub in (11, 12):
            a.sub(sub, [('w', r.randrange(0, 500)), ('w', r.randrange(0, 500)), ('w', r.randrange(0, 500))])
            a.sub(r.randrange(0, 32), [bv(), bv()])
        elif sub in (13, 14):
            a.sub(sub, [bv()])
            a.out += a.raw_string()
        elif sub == 15:
            a.sub(15, [bv()])
            a.sub(r.randrange(0, 32), [bv(), bv()])
            a.sub(r.randrange(0, 32), [bv()])
        elif sub == 16:
            a.sub(16, [('b', r.choice([0, 1, 8, 16, 17, 255])), bv()])
        else:
            a.out.append(sub)
    elif k == 1:
        a.out.append(BASE['resourceRoutines'])
        sb = pick(r, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19], [0, 20, 21, 31, 35])
        flags, body = a.params([('b', r.randrange(0, 100))], 0x80) if sb != 17 else (0, b'')
        a.out += bytes([sb | flags | (0x20 if r.random() < 0.05 else 0)]) + body
    elif k == 2:
        a.op('lights', [('b', r.choice([0, 1, 2, 3, 7, 255]))], post=bytes([r.choice([0, 1, 2, 255]), r.choice([0, 1, 2, 255])]))
    elif k == 3:
        a.out.append(BASE['oldRoomEffect'])
        s = r.choice([1, 2, 3, 3, 4])
        a.sub(s, [('w', r.randrange(0, 5))] if s == 3 else [])
    else:
        a.op('drawBox', [('w', r.randrange(0, 330)), ('w', r.randrange(0, 200))])
        a.sub(r.randrange(0, 32), [('w', r.randrange(0, 330)), ('w', r.randrange(0, 200)), ('b', r.randrange(0, 16))])


def gen_sys(a, r):
    k = r.randrange(3)
    if k == 0:
        a.op('systemOps', [])
        a.out.append(r.choice([2, 2, 2, 2, 2, 2] + ([1, 3, 0, 4] if r.random() < 0.1 else [])))
    elif k == 1:
        a.out.append(BASE['saveLoadGame'])
        a.out += a.result()
        a.out.append(r.choice([0, 0x20, 0x40, 0x80, 0xC0] + ([0x60, 0xA0, 0xE0, 1, 0x21] if r.random() < 0.05 else [])))
    else:
        a.out.append(BASE['saveLoadVars'])
        a.out.append(r.choice([0, 1, 2]))
        for _ in range(r.randrange(0, 5)):
            s = r.choice([1, 2, 2, 3, 4, 31, 5])
            if s == 1:
                a.out.append(1)
                a.out += a.result() + a.result()
            elif s == 2:
                a.sub(2, [('b', r.choice([0, 1, 2, 3, 5, 8, 9, 31, 32, 255])), ('b', r.choice([0, 1, 5, 9, 31, 40, 255]))])
            elif s == 3:
                a.out.append(3)
                a.out += a.raw_string()
            else:
                a.out.append(s)
                if s in (4, 31):
                    break
        a.out.append(0)


def gen_extra(a, r):
    """Cosas que dejan estado para los demas: un actor puesto en la sala, una cadena cargada, un dueno."""
    k = r.randrange(3)
    if k == 0:
        a.op('putActor', [('b', r.randrange(1, 6)), ('w', r.randrange(0, 321)), ('w', r.randrange(0, 150))])
    elif k == 1:
        a.op('putActorInRoom', [('b', r.randrange(1, 6)), ('b', r.choice([0, 1, 2, 5]))])
    else:
        a.op('setOwnerOf', [('w', r.randrange(1, 60)), ('b', r.randrange(0, 6))])


def gen_print(a, r):
    """print y printEgo con una lista de subopcodes (0 posicion, 1 color, 2 derecha, 4 centrado, 6 altura, 7 sobre la cabeza, 15 texto, $FF fin)
    y mensajes con codigos $FF; algun mensaje muy largo, anidado sobre si mismo o con un subopcode que no existe."""
    if r.random() < 0.03:                              # una cadena que se cita a si misma: anidamiento hasta E_RANGE
        a.out.append(0x27)
        a.out += bytes([1, 3, 0xFF, 7]) + struct.pack('<H', a.var(3)) + b'ab\0'
        a.begin()
        a.op('print', [('b', 1)])
        a.out += bytes([15, 0xFF, 7]) + struct.pack('<H', a.var(3)) + b'\0'
        return
    if r.random() < 0.3:
        a.out.append(BASE['printEgo'])
    else:
        a.op('print', [('b', pick(r, [0, 1, 2, 3, 4, 5, 6, 12, 1, 2, 3, 0xFF, 0xFF, 252, 253, 254], [13, 20, 128], 0.05))])
    for _ in range(r.randrange(0, 6)):
        sub = r.choice([0, 0, 1, 1, 2, 4, 6, 7] + ([3, 5, 8, 9, 10, 11, 12, 13, 14] if r.random() < 0.04 else []))
        if sub == 0:
            a.sub(0, [('w', r.choice([0, 20, 100, 160, 300, 400, 0xFFFF])), ('w', r.choice([0, 8, 40, 100, 150, 0xFFF0]))])
        elif sub == 1:
            a.sub(1, [('b', r.choice([0, 1, 5, 15, 200, 255]))])
        elif sub == 2:
            a.sub(2, [('w', r.choice([100, 200, 319, 400]))])
        elif sub == 6:
            a.sub(6, [('w', r.choice([0, 8, 16, 100]))])
        else:
            a.out.append(sub | (0x10 if r.random() < 0.05 else 0))
    if r.random() < 0.2:
        a.out.append(0xFF)
        return
    a.out.append(15 | (0x10 if r.random() < 0.1 else 0))
    a.out += a.raw_string(long=r.random() < 0.04)


def gen_room5(a, r, ctx):
    """Fase 5: los 12 opcodes de salas, objetos y frases. ctx (vmmodel3.make_synth_scenarios): rooms (existentes), room (la sala en uso),
    robjs (sala -> objetos), verbs (objeto -> verbos de su OBCD), nboxes (cajas de la sala en uso), mapped (claves de pseudosala)."""
    objs = ctx['robjs'].get(ctx['room'], [])
    anyobj = lambda: pick(r, objs or [1, 2], [0, 1, 2, 13, 14, 700, 999, 1000, 4000, 0xFFFF, 0xFFFE], 0.12)
    obj = lambda: (r.choice(objs) if objs and r.random() < 0.8 else anyobj())
    verb_of = lambda o: pick(r, ctx['verbs'](o) or [1, 2, 9], [0, 1, 2, 3, 250, 255, 256, 1000], 0.15)
    j = struct.pack('<h', 0)
    k = r.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 10, 11, 11])
    if k == 0:                                           # loadRoom
        room = pick(r, ctx['rooms'], [0, 100, 127, 128, 129, 200, 255, 256] + [0x80 + m for m in ctx['mapped']], 0.25)
        a.op('loadRoom', [('b', room)])
    elif k == 1:                                         # loadRoomWithEgo
        room = pick(r, ctx['rooms'], [0, 100, 200, 255, 256], 0.1)
        o = (r.choice(ctx['robjs'].get(room, [1])) if ctx['robjs'].get(room) and r.random() < 0.85 else anyobj())
        x = -1 if r.random() < 0.7 else r.randrange(0, 320)
        a.op('loadRoomWithEgo', [('w', o), ('b', room)], post=struct.pack('<hh', x, r.randrange(0, 150)))
    elif k == 2:                                         # pseudoRoom
        a.out += bytes([BASE['pseudoRoom'], pick(r, ctx['rooms'], [0, 100, 255], 0.1)])
        for _ in range(r.randrange(0, 4)):
            a.out.append(pick(r, [0x80 + m for m in ctx['mapped']] or [0x80], [0x80, 0x90, 0xA5, 0xFF, 0x40, 0x7F], 0.5))
        a.out.append(0)
    elif k == 3:                                         # startObject
        o = obj()
        a.op('startObject', [('w', o), ('b', verb_of(o))])
        for _ in range(r.randrange(0, 4)):
            f, body = a.params([('w', r.choice([0, 1, 2, 5, 100, 999]))], 0x80)
            a.out += bytes([r.randrange(1, 0x60) | f]) + body
        a.out.append(0xFF)
    elif k == 4:                                         # getVerbEntrypoint
        o = obj()
        a.op('getVerbEntrypoint', [('w', o), ('w', verb_of(o))], pre=a.result())
    elif k == 5:                                         # drawObject (con x = 255: sin mover)
        o = obj()
        x = 255 if r.random() < 0.4 else pick(r, [0, 1, 20, 40, 100, 254], [256, 300, 0xFFFF, 255 + 0x100], 0.06)
        a.op('drawObject', [('w', o), ('w', x), ('w', pick(r, [0, 2, 8, 16, 100, 255], [256, 0xFFFE], 0.06))])
    elif k == 6:                                         # pickupObject
        a.op('pickupObject', [('w', obj() if r.random() < 0.95 else pick(r, [0, 0xFFFF, 5000]))])
    elif k == 7:                                         # findObject (a menudo sobre el rectangulo de un objeto de la sala)
        if objs and ctx['rects'] and r.random() < 0.7:
            x, y = r.choice(ctx['rects'])
            x, y = x + r.choice([0, 0, 1, -1, 3]), y + r.choice([0, 0, 1, -1, 3])
        else:
            x, y = pick(r, [0, 8, 50, 160, 300, 319, 0xFFFF], [], 0), pick(r, [0, 30, 60, 100, 144, 0xFFF0])
        a.op('findObject', [('b', x), ('b', y)], pre=a.result())
    elif k == 8:                                         # isActorInBox / setBoxFlags
        nb = ctx['nboxes']
        box = pick(r, list(range(max(nb, 1))), [nb, nb + 1, 255, 254, 256, 0], 0.15)
        if r.random() < 0.6:
            a.op('isActorInBox', [('b', pick(r, [0, 1, 2, 3, 4, 5, 12], [13, 255], 0.05)), ('b', box)], post=j)
        else:
            a.op('setBoxFlags', [('b', box)], post=bytes([r.choice([0, 1, 8, 0x10, 0x20, 0x40, 0x80, 0xFF, 7])]))
    elif k == 9:                                         # doSentence
        if r.random() < 0.08:
            a.out += bytes([BASE['doSentence'], 0xFE])
        else:
            o = obj()
            a.op('doSentence', [('b', pick(r, [1, 2, 3, 4, 5, 7, 8, 9, 13, 14, 15], [0, 255, 256], 0.05)), ('w', o),
                                ('w', obj() if r.random() < 0.4 else 0)])
    else:                                                # waitForSentence
        a.out.append(BASE['waitForSentence'])


def walk_point(r, boxes, width=320, wild=0.05):
    """Un punto para andar: casi siempre dentro de una caja de la sala (donde pincharia un jugador), a veces cerca de una esquina, en
    cualquier sitio de la sala o (wild) muy lejos, con coordenadas s16 extremas."""
    x = r.random()
    if boxes and x < 0.7:
        b = r.choice(boxes)
        t, u = r.random(), r.random()
        top = (b[0] + (b[2] - b[0]) * t, b[1] + (b[3] - b[1]) * t)
        bot = (b[6] + (b[4] - b[6]) * t, b[7] + (b[5] - b[7]) * t)
        return int(top[0] + (bot[0] - top[0]) * u), int(top[1] + (bot[1] - top[1]) * u)
    if boxes and x < 0.82:
        b = r.choice(boxes)
        k = r.randrange(4)
        return b[2 * k] + r.randrange(-4, 5), b[2 * k + 1] + r.randrange(-4, 5)
    if x < 1 - wild:
        return r.randrange(-8, width + 8), r.randrange(0, 160)
    return (r.choice([-50, 400, 1000, -1000, 4095, 4200, 30000, -32768, 32767, -3000]),
            r.choice([-30, 250, 1000, -4096, 5000, -32768, 32767, 20000]))


def gen_walk(a, r, ctx):
    """Fase 6: caminata. Los 4 opcodes y lo que les cambia el camino: putActor / putActorInRoom (adjustActorPos), actorOps (traje, velocidad,
    ignoreBoxes), setBoxFlags (cajas invisibles, cerradas, con direccion fija o volteadas), setClass (volteo del actor, jugador) y animateActor."""
    boxes = ctx.get('boxes', [])
    room = ctx['room']
    act = lambda: pick(r, [1, 1, 2, 3, 4, 12], [0, 13, 255], 0.015)
    pt = lambda: walk_point(r, boxes, ctx.get('width', 320))
    k = r.choice([0, 0, 0, 0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8, 9])
    if k == 0:
        x, y = pt()
        a.op('walkActorTo', [('b', act()), ('w', x), ('w', y)])
    elif k == 1:
        a.op('walkActorToActor', [('b', act()), ('b', act())], post=bytes([r.choice([0, 0, 5, 20, 40, 0xFF, 0xFF, 200])]))
    elif k == 2:
        objs = ctx['robjs'].get(room, [])
        o = pick(r, objs or [1], [0, 1, 13, 999, 4000] + list(ctx.get('inv', [])), 0.1)
        a.op('walkActorToObject', [('b', act()), ('w', o)])
    elif k == 3:
        a.op('waitForActor', [('b', act())])
    elif k == 4:
        x, y = pt()
        a.op('putActor', [('b', act()), ('w', x), ('w', y)])
    elif k == 5:
        a.op('putActorInRoom', [('b', act()), ('b', pick(r, [room, room, room, 0], [5, 255], 0.1))])
    elif k == 6:
        a.op('actorOps', [('b', act())])
        for _ in range(r.randrange(1, 3)):
            q = r.randrange(5)
            if q == 0:
                a.sub(1, [('b', r.choice([0, 1, 2, 3]))])                            # traje
            elif q == 1:
                a.sub(4, [('b', pick(r, [1, 2, 3, 4, 8, 8, 12, 20], [0, 255, 100], 0.05)),      # velocidad
                          ('b', pick(r, [1, 1, 2, 2, 3, 5, 8], [0, 255, 254], 0.05))])
            elif q == 2:
                a.out.append(20 if r.random() < 0.5 else 10)                         # ignoreBoxes (20) / initActor(0) (10: vuelve a seguir las cajas)
            elif q == 3:
                a.sub(6, [('b', pick(r, [2, 2, 2, 3, 6, 0x39, 0x3A], [0x3D], 0.03))])     # fotograma de caminar
            else:
                a.sub(8, [('b', pick(r, [3, 3, 2, 7, 0x3A], [0x3D], 0.03))])              # fotograma de parado
        a.out.append(0xFF)
    elif k == 7:
        nb = len(boxes)
        a.op('setBoxFlags', [('b', pick(r, list(range(max(nb, 1))), [nb, 255], 0.05))],
             post=bytes([r.choice([0, 0, 1, 2, 3, 4, 5, 6, 8, 0x10, 0x18, 0x20, 0x40, 0x80, 0xA0, 0x89, 0x12])]))
    elif k == 8:
        a.op('setClass', [('w', act())])
        for _ in range(r.randrange(1, 3)):
            f, body = a.params([('w', r.choice([29, 30, 31, 20]) | (0x80 if r.random() < 0.6 else 0))], 0x80)
            a.out += bytes([1 | f]) + body
        a.out.append(0xFF)
    else:
        a.op('animateActor', [('b', act()), ('b', r.choice([244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 2, 3, 6]))])


GENS = [gen_state_class, gen_inventory, gen_string, gen_string, gen_cursor, gen_verbs, gen_verbs, gen_actor, gen_actor, gen_room,
        gen_sys, gen_extra, gen_print, gen_print, gen_print, gen_print, gen_room5, gen_room5, gen_room5, gen_room5, gen_room5,
        gen_walk, gen_walk, gen_walk, gen_walk, gen_walk]


def make_code(rng, n_ins=None, ctx=None):
    a = Asm(rng, varprob=rng.choice([0.0, 0.25, 0.5]))
    for sid in range(4 if rng.random() < 0.85 else 0):                  # cadenas ya creadas, para que getStringWidth y compania no fallen siempre
        a.begin()
        a.out.append(0x27)
        a.out += bytes([1, sid]) + a.raw_string()
    for _ in range(n_ins or rng.randrange(3, 16)):
        a.begin()
        g = rng.choice(GENS)
        if ctx is not None:
            a.objs = list(ctx['robjs'].get(ctx['room'], [])) + list(ctx.get('inv', []))
        if g is gen_room5 or g is gen_walk:
            if ctx is None:
                continue
            g(a, rng, ctx)
        else:
            g(a, rng)
    a.out.append(0x00)                                      # stopObjectCode
    return bytes(a.out)


def make_walk_code(rng, ctx, n_ins=None, setup=None):
    """Fase 6: un script solo de caminata (gen_walk). setup: lista de (actor, traje, x, y) que se colocan primero en la sala."""
    a = Asm(rng, varprob=rng.choice([0.0, 0.0, 0.3]))
    for act, cost, x, y in setup or ():
        a.begin()
        a.op('actorOps', [('b', act)])
        a.sub(1, [('b', cost)])
        a.out.append(0xFF)
        a.begin()
        a.op('putActor', [('b', act), ('w', x), ('w', y)])
        a.begin()
        a.op('putActorInRoom', [('b', act), ('b', ctx['room'])])
    for _ in range(rng.randrange(1, 4) if n_ins is None else n_ins):
        a.begin()
        gen_walk(a, rng, ctx)
    a.out.append(0x00)
    return bytes(a.out)


def click_code(rng, ctx, act):
    """Un "clic" en la sala: lo que hace el script de verbos de Indy3 con un clic en la escena, walkActorTo del ego a ese punto."""
    a = Asm(rng, varprob=0.0)
    a.begin()
    x, y = walk_point(rng, ctx.get('boxes', []), ctx.get('width', 320), wild=0.02)
    a.op('walkActorTo', [('b', act), ('w', x), ('w', y)])
    a.out.append(0x00)
    return bytes(a.out)


def speed_code(rng, act):
    """actorOps 2 (velocidad de caminata) del actor: con el actor andando, setActorWalkSpeed recalcula el tramo (calcMovementFactor)."""
    return bytes([BASE['actorOps'], act, 4, rng.choice([1, 2, 3, 4, 6, 12, 16]), rng.choice([1, 2, 3, 4, 6]), 0xFF, 0x00])
