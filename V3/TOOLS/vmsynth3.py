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


GENS = [gen_state_class, gen_inventory, gen_string, gen_string, gen_cursor, gen_verbs, gen_verbs, gen_actor, gen_actor, gen_room,
        gen_sys, gen_extra, gen_print, gen_print, gen_print, gen_print]


def make_code(rng, n_ins=None):
    a = Asm(rng, varprob=rng.choice([0.0, 0.25, 0.5]))
    for sid in range(4 if rng.random() < 0.85 else 0):                  # cadenas ya creadas, para que getStringWidth y compania no fallen siempre
        a.begin()
        a.out.append(0x27)
        a.out += bytes([1, sid]) + a.raw_string()
    for _ in range(n_ins or rng.randrange(3, 16)):
        a.begin()
        rng.choice(GENS)(a, rng)
    a.out.append(0x00)                                      # stopObjectCode
    return bytes(a.out)
