#!/usr/bin/env python3
"""Genera SCUMM/V3/ENGINE/tables3.inc: la tabla de despacho de los 256 opcodes de SCUMM v3 y las especificaciones de operandos
del decodificador generico del Z80. Todo sale de scumm3dis.py (NAMES y SPEC, comprobada contra el Decoder con `scumm3dis.py DIR
spec`) y de la lista de manejadores de abajo, asi que el Z80, el modelo (vmmodel3.CoreVM) y el desensamblador no pueden divergir.

Tablas (son datos: en el programa de la placa van por encima de $8000, alineadas a 256):
  disp_lo / disp_hi   por opcode, la direccion de su manejador (bytes bajo y alto en dos tablas de 256: es_loop hace
                      `ld l,a / ld h,disp_lo>>8 / ld c,(hl) / inc h / ld b,(hl)`).
  spec_lo / spec_hi   por opcode, la especificacion que lee `decode` (0 en los opcodes con lectura propia).
Un manejador NATIVO lee sus operandos el mismo (rd_var, rd_vb1...; vm_core.asm). Los demas empiezan con `call decode`, que deja
los valores en ARGS (ARGN palabras), el numero de variable de la R de arriba en RESV y el destino de la J en JTGT.

Especificacion: bytes de ficha acabados en 0.
   1 R   2 v   3 B1  4 B2  5 B3  6 W1  7 W2  8 W3  9 b  10 w  11 J  12 L  13 S  14 O  15 o  16 Q  17 X  18 Z  19 N
  20 SW   + mascara, tabla                      21 LOOP  + fin, mascara, conversion (1 = actorOps), tabla
  tabla: u8 n, n x defw (subespecificacion de k = 0..n-1, o 0 = subopcode desconocido), defw por omision (k >= n; 0 = desconocido)
El significado de cada ficha esta en scumm3dis.py (SPEC).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scumm3dis as DIS     # noqa: E402
import vmmodel3              # noqa: E402

TOKEN = {'R': 1, 'v': 2, 'B1': 3, 'B2': 4, 'B3': 5, 'W1': 6, 'W2': 7, 'W3': 8, 'b': 9, 'w': 10, 'J': 11, 'L': 12, 'S': 13,
         'O': 14, 'o': 15, 'Q': 16, 'X': 17, 'Z': 18, 'N': 19}
T_SW, T_LOOP = 20, 21

# Manejadores del Z80: nombre de ScummVM -> etiqueta. Los de NATIVE leen sus operandos; los de SPEC_HANDLERS usan decode y ARGS.
# La fase 3 tiene el nucleo (vmmodel3.CORE_OPS); las fases 4a/4b anaden aqui los suyos (ver V3/PLAN.md).
# OVB_HANDLERS: los manejadores del overlay B (ENGINE/ovb4.asm, etiqueta b_<nombre>), por orden de grupo. Los de CORE_OPS que estan aqui
# entran todos por h3_ovb (residente: ld hl,OVB_OP / jp call_ovb) y B los reparte por el opcode con ovb_lo/ovb_hi (ovbtab.inc).
OVB_HANDLERS = ['startSound', 'startMusic', 'stopSound', 'stopMusic', 'isSoundRunning',
                'getObjectOwner', 'setOwnerOf', 'setObjectName',
                'setCameraAt', 'panCameraTo', 'actorFollowCamera',
                'putActor', 'putActorInRoom', 'putActorAtObject', 'getActorRoom', 'getActorX', 'getActorY', 'getActorElevation',
                'getActorMoving', 'getActorFacing', 'getActorCostume', 'getActorWalkBox', 'animateActor', 'faceActor',
                'actorFromPos', 'getClosestObjActor', 'getDist',
                # fase 4b-1 (ENGINE/ovb4b.asm): estados y clases; inventario; cadenas; cursor y verbos; actorOps; sala y recursos
                'setState', 'ifState', 'ifNotState', 'setClass', 'ifClassOfIs',
                'findInventory', 'getInventoryCount', 'getActorWidth',
                'stringOps', 'getStringWidth',
                'cursorCommand', 'verbOps', 'saveRestoreVerbs',
                'actorOps',
                'roomOps', 'resourceRoutines', 'lights', 'systemOps', 'saveLoadVars', 'saveLoadGame',
                # fase 4b-2 (ENGINE/ovb4c.asm): mensajes
                'print', 'printEgo']
# OVC_HANDLERS: los del overlay C (ENGINE/ovc1.asm, etiqueta b_<nombre>, despacho ovc_lo/ovc_hi); salieron de B cuando se lleno (fase 4b-2)
OVC_HANDLERS = ['roomOps', 'resourceRoutines', 'lights', 'systemOps', 'saveLoadGame']
OVC = [n for n in OVC_HANDLERS if n in vmmodel3.CORE_OPS]
OVB = [n for n in OVB_HANDLERS if n in vmmodel3.CORE_OPS and n not in OVC]
# los del nucleo que no necesitan manejador propio: salen al anfitrion con la lectura generica y el modelo los trata igual (H oo [args])
HOST_CORE = {'oldRoomEffect', 'drawBox'}
# los de B que empiezan con `call decode` (leen sus operandos con la especificacion): conservan su entrada en spec_lo/spec_hi
OVB_DECODE = {'lights', 'cursorCommand', 'roomOps'}      # (los de decode: tambien los de C)
NATIVE = {name: 'h3_ovb' if name in OVB else 'h3_ovc' if name in OVC else 'h3_' + name for name in vmmodel3.CORE_OPS if name not in HOST_CORE}
SPEC_HANDLERS = {}


def handler_for(name):
    if name in NATIVE:
        return NATIVE[name]
    if name in SPEC_HANDLERS:
        return SPEC_HANDLERS[name]
    toks = DIS.spec_tokens(DIS.SPEC[name])
    if toks and toks[0] == 'R':
        return 'h_host_r'
    if 'J' in toks:
        return 'h_host_j'
    return 'h_host'


class Emitter:
    def __init__(self):
        self.lines = []
        self.n = 0
        self.cache = {}

    def label(self, prefix):
        self.n += 1
        return '%s%d' % (prefix, self.n)

    def spec(self, toks, top=False):
        """Etiqueta de una (sub)especificacion. Las iguales se comparten."""
        key = repr(toks)
        if key in self.cache:
            return self.cache[key]
        parts = []
        for t in toks:
            if isinstance(t, tuple):
                if t[0] == 'SW':
                    _, mask, table, dflt = t
                    parts.append('%d,$%02X' % (T_SW, mask))
                    parts.append(('W', self.table(table, dflt)))
                else:
                    _, end, mask, conv, table, dflt = t
                    parts.append('%d,$%02X,$%02X,%d' % (T_LOOP, end, mask, 1 if conv == 'actor' else 0))
                    parts.append(('W', self.table(table, dflt)))
            else:
                if t == 'E':
                    raise ValueError('E solo en expression (nativo)')
                parts.append(str(TOKEN[t]))
        lab = self.label('sp3_')
        out = []
        for p in parts:
            if isinstance(p, tuple):
                out.append('        defw %s' % p[1])
            else:
                out.append('        defb %s' % p)
        self.lines.append('%s:' % lab)
        self.lines += out
        self.lines.append('        defb 0')
        self.cache[key] = lab
        return lab

    def table(self, table, dflt):
        subs = {k: self.spec(DIS.spec_tokens(v)) for k, v in table.items()}
        d = '0' if dflt is None else self.spec(DIS.spec_tokens(dflt))
        n = max(table) + 1
        lab = self.label('st3_')
        self.lines.append('%s:   defb %d' % (lab, n))
        for k in range(n):
            self.lines.append('        defw %s' % (subs[k] if k in subs else d))
        self.lines.append('        defw %s' % d)
        return lab


def write_vars():
    """vars_v3.inc: los numeros de variable de ScummEngine::setupScummVars de v3 (vmcommon3.py, fuente unica)."""
    import vmcommon3 as C
    names = sorted((v, k) for k, v in vars(C).items() if k.startswith('VAR_') and isinstance(v, int))
    out = ['; GENERADO por SCUMM/V3/TOOLS/gen_vmtables3.py desde vmcommon3.py (ScummEngine::setupScummVars, version 3): no editar',
           '; La variable n esta en VARS+2n (palabra). Indy3 PC suma ademas el fotograma a las variables %s (scummLoop).'
           % ', '.join(str(x) for x in C.VARS_INDY3_TIMERS), '']
    for v, k in names:
        out.append('%-26s equ VARS+%d        ; %d' % (k, 2 * v, v))
    with open(os.path.join(HERE, '..', 'ENGINE', 'vars_v3.inc'), 'w') as f:
        f.write('\n'.join(out) + '\n')


def write_ovctab():
    """ovctab.inc: ovc_lo / ovc_hi (alineadas a 256, dentro del overlay C): por opcode, la direccion de su manejador b_<nombre>."""
    out = ['; GENERADO por SCUMM/V3/TOOLS/gen_vmtables3.py (OVC_HANDLERS): no editar a mano', '                defs (256 - ($ & 255)) & 255', 'ovc_lo:']
    lab = ['b_' + DIS.NAMES[op] if DIS.NAMES[op] in OVC else '0' for op in range(256)]
    for op in range(256):
        out.append('        defb %s & 255   ; %02X %s' % (lab[op], op, DIS.NAMES[op]))
    out.append('ovc_hi:')
    for op in range(256):
        out.append('        defb %s / 256' % lab[op])
    with open(os.path.join(HERE, '..', 'ENGINE', 'ovctab.inc'), 'w') as f:
        f.write(chr(10).join(out) + chr(10))


def write_ovbtab():
    """ovbtab.inc: ovb_lo / ovb_hi (alineadas a 256, dentro del overlay B): por opcode, la direccion de su manejador b_<nombre>."""
    out = ['; GENERADO por SCUMM/V3/TOOLS/gen_vmtables3.py (OVB_HANDLERS): no editar a mano', '                defs (256 - ($ & 255)) & 255',
           'ovb_lo:']
    lab = {}
    for op in range(256):
        name = DIS.NAMES[op]
        lab[op] = 'b_' + name if name in OVB else '0'
    for op in range(256):
        out.append('        defb %s & 255   ; %02X %s' % (lab[op], op, DIS.NAMES[op]))
    out.append('ovb_hi:')
    for op in range(256):
        out.append('        defb %s / 256' % lab[op])
    with open(os.path.join(HERE, '..', 'ENGINE', 'ovbtab.inc'), 'w') as f:
        f.write(chr(10).join(out) + chr(10))


def main():
    em = Emitter()
    entries = []
    for op in range(256):
        name = DIS.NAMES[op]
        h = handler_for(name)
        sp = '0' if name in NATIVE and name not in OVB_DECODE else em.spec(DIS.spec_tokens(DIS.SPEC[name]), True)
        entries.append((op, name, h, sp))
    out = ['; GENERADO por SCUMM/V3/TOOLS/gen_vmtables3.py: no editar a mano', '']
    out.append('; ---- tabla de despacho (alineada a 256): manejador de cada opcode, bytes bajo y alto')
    out.append('                defs (256 - ($ & 255)) & 255')
    out.append('disp_lo:')
    for op, name, h, sp in entries:
        out.append('        defb %s & 255   ; %02X %s' % (h, op, name))
    out.append('disp_hi:')
    for op, name, h, sp in entries:
        out.append('        defb %s / 256' % h)
    out.append('; ---- especificacion de cada opcode (0: el manejador lee sus operandos)')
    out.append('spec_lo:')
    for op, name, h, sp in entries:
        out.append('        defb %s & 255   ; %02X %s' % (sp, op, name))
    out.append('spec_hi:')
    for op, name, h, sp in entries:
        out.append('        defb %s / 256' % sp)
    out.append('; ---- especificaciones')
    out += em.lines
    out.append('sp3_empty:      defb 0')
    path = os.path.join(HERE, '..', 'ENGINE', 'tables3.inc')
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')
    write_vars()
    write_ovbtab()
    write_ovctab()
    hs = sorted({e[2] for e in entries})
    print('%d opcodes, %d manejadores distintos (%d nativos), %d especificaciones' % (
        256, len(hs), len([h for h in hs if h.startswith('h3_')]), em.n))
    print('manejadores:', ' '.join(hs))


if __name__ == '__main__':
    main()
