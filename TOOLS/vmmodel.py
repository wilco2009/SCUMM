#!/usr/bin/env python3
"""Modelo de referencia del nucleo del interprete SCUMM v2 y empaquetado de datos para el arnes del Z80.

El modelo es una transcripcion de la semantica de ScummVM (engines/scumm/script.cpp, script_v2.cpp,
script_v5.cpp) para el nucleo que implementa el Z80 en SCUMM/ENGINE/vm.asm:
  - bucle de scripts, ranuras, retardos, scripts anidados;
  - variables (con la redireccion de las variables 14-16), bits, aritmetica, saltos y comparaciones;
  - estados de objeto; startScript, stopScript, chainScript, isScriptRunning y las esperas.
Todo lo demas (actores, texto, sonido, verbos, camara...) es una llamada al "anfitrion": se anota en la
traza y devuelve un resultado simulado. Asi se comparan dos implementaciones independientes del
nucleo (esta y la del Z80) sobre los scripts de verdad de Maniac Mansion.

Pendiente de portar (esta en ScummVM, no aqui): cutscene y override, congelacion de scripts, las
correcciones especificas de Maniac Mansion de stopScript, y los efectos de loadRoom/doSentence sobre
las ranuras.

Uso:
  vmmodel.py DIR_LFL pack SALIDA              escribe el mundo para el arnes (SALIDA/world.bin)
  vmmodel.py DIR_LFL scenarios SALIDA [N]     escribe los escenarios y las trazas esperadas
"""
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scumm2
import scummdis
import vmsynth

from vmcommon import *
from vmgame import GameMixin, verb_entry


# --------------------------------------------------------------------------------------------- mundo
class World:
    """Los datos del juego que necesita el nucleo."""

    def __init__(self, directory):
        self.dir = directory
        ix = scumm2.Index(directory)
        self.index = ix
        self.owner = [ix.owner(i) for i in range(NUM_OBJECTS)]
        self.state = [ix.state(i) for i in range(NUM_OBJECTS)]
        self.scripts = {}          # id -> codigo (sin la cabecera de 4 bytes)
        for i in range(len(ix.res['script'])):
            if scumm2.resource_ok(directory, ix, 'script', i):
                self.scripts[i] = scumm2.resource(directory, ix, 'script', i)[4:]
        for sid, code in vmsynth.synth_scripts().items():     # scripts sinteticos (ids 180-199, libres)
            if sid in self.scripts:
                raise ValueError('el script sintetico %d choca con uno del juego' % sid)
            self.scripts[sid] = code
        self.rooms = {}
        self.objects = {}          # id -> (sala, bloque OBCD)
        for rn in range(len(ix.res['room'])):
            if not os.path.exists(os.path.join(directory, '%02d.LFL' % rn)):
                continue
            r = scumm2.Room(directory, rn)
            self.rooms[rn] = r
            for o in r.objects:
                if o.id in self.objects:
                    raise ValueError('objeto %d repetido (salas %d y %d)' % (o.id, self.objects[o.id][0], rn))
                self.objects[o.id] = (rn, o.block)
        for rn, r in vmsynth.synth_rooms(self.owner).items():
            if rn in self.rooms:
                raise ValueError('la sala sintetica %d choca con una del juego' % rn)
            self.rooms[rn] = r


# --------------------------------------------------------------------------------------------- modelo
class Slot:
    def __init__(self):
        self.status = SS_DEAD
        self.where = 0
        self.number = 0
        self.code = b''
        self.offs = 0
        self.delay = 0
        self.flags = 0

    def clear(self):
        self.__init__()


class Nest:
    def __init__(self, number, where, slot):
        self.number, self.where, self.slot = number, where, slot


# manejadores que implementa el nucleo (nombre de ScummVM -> metodo)
CORE = {
    'o5_stopObjectCode', 'o5_breakHere', 'o2_delay', 'o5_delayVariable', 'o5_jumpRelative', 'o5_equalZero',
    'o5_notEqualZero', 'o5_isEqual', 'o5_isNotEqual', 'o2_isGreater', 'o2_isGreaterEqual', 'o2_isLess',
    'o2_isLessEqual', 'o5_move', 'o2_assignVarByte', 'o2_assignVarWordIndirect', 'o5_increment',
    'o5_decrement', 'o2_add', 'o2_subtract', 'o2_addIndirect', 'o2_subIndirect', 'o5_setVarRange',
    'o2_getBitVar', 'o2_setBitVar', 'o2_startScript', 'o2_stopScript', 'o2_chainScript',
    'o5_isScriptRunning', 'o2_waitForMessage', 'o2_waitForSentence',
}
STATE_OPS = {     # nombre -> (accion, mascara); accion: set, clear, jz (ZeroCommon), jnz (NotZeroCommon)
    'o2_setStateIntrinsicOn': ('set', 8), 'o2_setStateIntrinsicOff': ('clear', 8),
    'o2_setStateLocked': ('set', 4), 'o2_setStateUnlocked': ('clear', 4),
    'o2_setStateUntouchable': ('set', 2), 'o2_setStateTouchable': ('clear', 2),
    'o2_setStatePickupable': ('set', 1), 'o2_setStateUnpickupable': ('clear', 1),
    'o2_ifStateIntrinsicOff': ('zero', 8), 'o2_ifStateIntrinsicOn': ('nonzero', 8),
    'o2_ifStateUnlocked': ('zero', 4), 'o2_ifStateLocked': ('nonzero', 4),
    'o2_ifStateTouchable': ('zero', 2), 'o2_ifStateUntouchable': ('nonzero', 2),
    'o2_ifStatePickupable': ('nonzero', 1), 'o2_ifStateUnpickupable': ('zero', 1),
}
SPECIAL = ('o2_actorOps', 'o2_verbOps', 'o2_doSentence', 'o5_pseudoRoom')


class VM(GameMixin):
    @property
    def sentnum(self):
        return len(self.sent)

    def __init__(self, world):
        self.w = world
        self.trace = []
        self.reset()

    def reset(self):
        self.vars = [0] * NUM_VARS
        self.state = list(self.w.state)
        self.owner = list(self.w.owner)
        self.slots = [Slot() for _ in range(NUM_SLOT)]
        self.nest = []
        self.cur = 0xFF
        self.code = b''
        self.ptr = 0
        self.opcode = 0
        self.frame = 0
        self.insn = 0
        self.max_slots = 0
        self.game_reset()

    # ---- lectura del script
    def fetch_byte(self):
        b = self.code[self.ptr]
        self.ptr += 1
        return b

    def fetch_word(self):
        v = self.code[self.ptr] | (self.code[self.ptr + 1] << 8)
        self.ptr += 2
        return v

    def fetch_word_signed(self):
        v = self.fetch_word()
        return v - 0x10000 if v & 0x8000 else v

    # ---- variables
    def read_var(self, v):
        if 14 <= v <= 16:
            v = self.vars[v] & 0xFF
        return self.vars[v]

    def write_var(self, v, value):
        value &= 0xFFFF
        if v == VAR_CUTSCENEEXIT_KEY and value in (4, 13, 64):
            value = 27
        self.vars[v] = value

    def get_var(self):
        return self.read_var(self.fetch_byte())

    def get_var_or_direct_byte(self, mask):
        if self.opcode & mask:
            return self.get_var()
        return self.fetch_byte()

    def get_var_or_direct_word(self, mask):
        if self.opcode & mask:
            return self.get_var()
        return self.fetch_word_signed() & 0xFFFF

    def jump_relative(self, cond):
        off = self.fetch_word_signed()
        if not cond:
            self.ptr += off

    # ---- objetos
    def get_state(self, obj):
        if not 0 <= obj < NUM_OBJECTS:
            raise VMError(E_BADOBJ)
        if obj in (182, 193):
            self.state[obj] |= 8
        return self.state[obj]

    def put_state(self, obj, st):
        if not 0 <= obj < NUM_OBJECTS:
            raise VMError(E_BADOBJ)
        self.state[obj] = st & 0xFF

    # ---- ranuras
    def get_slot(self):
        for i in range(1, NUM_SLOT):
            if self.slots[i].status == SS_DEAD:
                return i
        raise VMError(E_NOSLOT)

    def update_script_ptr(self):
        if self.cur != 0xFF:
            self.slots[self.cur].offs = self.ptr

    def load(self, i):
        self.code = self.slots[i].code
        self.ptr = self.slots[i].offs

    def break_here(self):
        self.update_script_ptr()
        self.cur = 0xFF

    def stop_script(self, script):
        if script == 0:
            return
        for i, ss in enumerate(self.slots):
            if script == ss.number and ss.status != SS_DEAD and ss.where in (WIO_GLOBAL, WIO_LOCAL):
                ss.number = 0
                ss.status = SS_DEAD
                if self.cur == i:
                    self.cur = 0xFF
        for n in self.nest:
            if n.number == script and n.where in (WIO_GLOBAL, WIO_LOCAL):
                n.number = 0
                n.slot = 0xFF
                n.where = 0xFF

    def is_script_running(self, script):
        return any(ss.number == script and ss.where in (WIO_GLOBAL, WIO_LOCAL) and ss.status != SS_DEAD
                   for ss in self.slots)

    def is_script_in_use(self, script):
        return any(ss.number == script for ss in self.slots)

    def run_script(self, script):
        if script == 0:
            return
        self.stop_script(script)          # no recursivo
        if script not in self.w.scripts:
            raise VMError(E_NOSCRIPT)
        i = self.get_slot()
        s = self.slots[i]
        s.number, s.offs, s.code = script, 0, self.w.scripts[script]
        s.status, s.where, s.delay, s.flags = SS_RUNNING, WIO_GLOBAL, 0, 0
        self.run_nested(i)

    def start_slot(self, where, number, code, offs):
        i = self.get_slot()
        s = self.slots[i]
        s.number, s.code, s.offs = number, code, offs
        s.status, s.where, s.delay, s.flags = SS_RUNNING, where, 0, 0
        self.run_nested(i)

    def run_nested(self, i):
        self.max_slots = max(self.max_slots, sum(1 for s in self.slots if s.status != SS_DEAD))
        self.update_script_ptr()
        if len(self.nest) >= MAX_NEST:
            raise VMError(E_NEST)
        if self.cur == 0xFF:
            entry = Nest(0, 0xFF, 0xFF)
        else:
            sl = self.slots[self.cur]
            entry = Nest(sl.number, sl.where, self.cur)
        self.nest.append(entry)
        self.cur = i
        self.load(i)
        self.exec_script()
        if self.nest:
            self.nest.pop()
        if entry.number:
            sl = self.slots[entry.slot]
            if sl.number == entry.number and sl.where == entry.where and sl.status != SS_DEAD:
                self.cur = entry.slot
                self.load(entry.slot)
                return
        self.cur = 0xFF

    def exec_script(self):
        while self.cur != 0xFF:
            self.insn += 1
            if self.insn > MAX_INSN:
                raise VMError(E_BUDGET)
            self.opcode = self.fetch_byte()
            self.execute(self.opcode)

    def decrease_delay(self, amount):
        for ss in self.slots:
            if ss.status == SS_PAUSED:
                ss.delay -= amount
                if ss.delay < 0:
                    ss.status = SS_RUNNING
                    ss.delay = 0

    def step_frame(self, delta):
        """scummLoop sin dibujo: retardos y mensaje, entrada, frases, scripts y actores."""
        self.frame_tick(delta)
        for area, val in self.pending:
            self.process_input(area, val)
        self.pending = []
        self.check_sentence()
        self.run_all_scripts()
        if self.cur_room != 0:
            self.walk_actors()

    def run_all_scripts(self):
        self.cur = 0xFF
        for i in range(NUM_SLOT):
            if self.slots[i].status == SS_RUNNING:
                self.cur = i
                self.load(i)
                self.exec_script()

    # ---- instrucciones
    def execute(self, op):
        name = scummdis.OPNAME[op]
        if name in self.GAME_OPS:
            getattr(self, self.GAME_OPS[name])()
        elif name in CORE:
            getattr(self, 'c_' + name.split('_', 1)[1])()
        elif name in STATE_OPS:
            self.state_op(*STATE_OPS[name])
        else:
            self.host_op(op, name)

    def set_result(self, r, v):
        self.write_var(r, v)

    # control
    def c_stopObjectCode(self):
        ss = self.slots[self.cur]
        if ss.where in (WIO_GLOBAL, WIO_LOCAL):
            self.stop_script(ss.number)
        else:
            ss.number = 0
            ss.status = SS_DEAD
        self.cur = 0xFF

    def c_breakHere(self):
        self.break_here()

    def c_delay(self):
        d = self.fetch_byte()
        d |= self.fetch_byte() << 8
        d |= self.fetch_byte() << 16
        self.slots[self.cur].delay = 0xFFFFFF - d
        self.slots[self.cur].status = SS_PAUSED
        self.break_here()

    def c_delayVariable(self):
        v = self.get_var()
        self.slots[self.cur].delay = v - 0x10000 if v & 0x8000 else v
        self.slots[self.cur].status = SS_PAUSED
        self.break_here()

    def c_jumpRelative(self):
        self.jump_relative(False)

    def c_equalZero(self):
        a = self.get_var()
        self.jump_relative(a == 0)

    def c_notEqualZero(self):
        a = self.get_var()
        self.jump_relative(a != 0)

    def c_isEqual(self):
        a = self.read_var(self.fetch_byte())
        b = self.get_var_or_direct_word(0x80)
        self.jump_relative(b == a)

    def c_isNotEqual(self):
        a = self.get_var()
        b = self.get_var_or_direct_word(0x80)
        self.jump_relative(b != a)

    def c_isGreater(self):
        a = self.get_var()
        b = self.get_var_or_direct_word(0x80)
        self.jump_relative(b > a)

    def c_isGreaterEqual(self):
        a = self.get_var()
        b = self.get_var_or_direct_word(0x80)
        self.jump_relative(b >= a)

    def c_isLess(self):
        a = self.get_var()
        b = self.get_var_or_direct_word(0x80)
        self.jump_relative(b < a)

    def c_isLessEqual(self):
        a = self.get_var()
        b = self.get_var_or_direct_word(0x80)
        self.jump_relative(b <= a)

    # variables
    def c_move(self):
        r = self.fetch_byte()
        self.set_result(r, self.get_var_or_direct_word(0x80))

    def c_assignVarByte(self):
        r = self.fetch_byte()
        self.set_result(r, self.fetch_byte())

    def c_assignVarWordIndirect(self):
        r = self.vars[self.fetch_byte()] & 0xFF
        self.set_result(r, self.get_var_or_direct_word(0x80))

    def c_increment(self):
        r = self.fetch_byte()
        self.set_result(r, self.read_var(r) + 1)

    def c_decrement(self):
        r = self.fetch_byte()
        self.set_result(r, self.read_var(r) - 1)

    def c_add(self):
        r = self.fetch_byte()
        a = self.get_var_or_direct_word(0x80)
        self.vars[r] = (self.vars[r] + a) & 0xFFFF

    def c_subtract(self):
        r = self.fetch_byte()
        a = self.get_var_or_direct_word(0x80)
        self.vars[r] = (self.vars[r] - a) & 0xFFFF

    def c_addIndirect(self):
        r = self.vars[self.fetch_byte()] & 0xFF
        a = self.get_var_or_direct_word(0x80)
        self.vars[r] = (self.vars[r] + a) & 0xFFFF

    def c_subIndirect(self):
        r = self.vars[self.fetch_byte()] & 0xFF
        a = self.get_var_or_direct_word(0x80)
        self.vars[r] = (self.vars[r] - a) & 0xFFFF

    def c_setVarRange(self):
        r = self.fetch_byte()
        a = self.fetch_byte()
        if a == 0:
            raise VMError(E_RANGE)
        while True:
            b = self.fetch_word_signed() if self.opcode & 0x80 else self.fetch_byte()
            self.set_result(r, b)
            r += 1
            a -= 1
            if a == 0:
                break

    def c_getBitVar(self):
        r = self.fetch_byte()
        var = self.fetch_word()
        a = self.get_var_or_direct_byte(0x80)
        bit_var = var + a
        off = bit_var & 15
        bit_var >>= 4
        if bit_var >= NUM_VARS:
            raise VMError(E_RANGE)
        self.set_result(r, 1 if self.vars[bit_var] & (1 << off) else 0)

    def c_setBitVar(self):
        var = self.fetch_word()
        a = self.get_var_or_direct_byte(0x80)
        bit_var = var + a
        off = bit_var & 15
        bit_var >>= 4
        flag = self.get_var_or_direct_byte(0x40)
        if bit_var >= NUM_VARS:
            raise VMError(E_RANGE)
        if flag:
            self.vars[bit_var] |= 1 << off
        else:
            self.vars[bit_var] &= ~(1 << off) & 0xFFFF

    # scripts
    def c_startScript(self):
        script = self.get_var_or_direct_byte(0x80)
        if script == 87 and (self.is_script_running(88) or self.is_script_running(89)):
            return
        if script == 155 and self.vars[120] == 1:
            return
        self.run_script(script)

    def c_stopScript(self):
        script = self.get_var_or_direct_byte(0x80)
        if script == 0:
            script = self.slots[self.cur].number
        if self.cur != 0 and self.slots[self.cur].number == script:
            self.c_stopObjectCode()
        else:
            self.stop_script(script)

    def c_chainScript(self):
        script = self.get_var_or_direct_byte(0x80)
        self.stop_script(self.slots[self.cur].number)
        self.cur = 0xFF
        self.run_script(script)

    def c_isScriptRunning(self):
        r = self.fetch_byte()
        script = self.get_var_or_direct_byte(0x80)
        self.set_result(r, 1 if self.is_script_running(script) else 0)

    def c_waitForMessage(self):
        if self.vars[VAR_HAVE_MSG]:
            self.ptr -= 1
            self.break_here()

    def c_waitForSentence(self):
        if not self.sentnum and not self.is_script_in_use(2):
            return
        self.ptr -= 1
        self.break_here()

    # estados de objeto
    def state_op(self, action, mask):
        obj = self.get_var_or_direct_word(0x80)
        if obj >= 0x8000:
            raise VMError(E_BADOBJ)
        st = self.get_state(obj)
        if action == 'set':
            self.put_state(obj, st | mask)
            self.ev(EV_OBJSTATE, [obj, self.state[obj]])
        elif action == 'clear':
            self.put_state(obj, st & ~mask)
            self.ev(EV_OBJSTATE, [obj, self.state[obj]])
        elif action == 'zero':          # ifStateZeroCommon: cond = (estado & mascara) != 0
            self.jump_relative((st & mask) != 0)
        else:                           # ifStateNotZeroCommon
            self.jump_relative((st & mask) == 0)

    # ---- anfitrion
    def host_log(self, op, args):
        s = mock_hash(op, args, self.frame)
        self.trace.append('H %02X [%s]' % (op, ','.join(str(a & 0xFFFF) for a in args)))
        return s & 0xFF, (s >> 8) & 1

    def read_string(self, kind):
        data = bytearray()
        while True:
            c = self.fetch_byte()
            if c == 0:
                break
            data.append(c)
            if kind == 'S' and 3 < (c & 0x7F) < 8:
                data.append(self.fetch_byte())
        return str_value(data)

    def host_op(self, op, name):
        args = []
        has_r = False
        if name == 'o2_actorOps':
            args = [self.get_var_or_direct_byte(0x80), self.get_var_or_direct_byte(0x40)]
            sub = self.fetch_byte()
            args.append(sub)
            if sub == 2:
                args.append(self.fetch_byte())
            elif sub == 3:
                args.append(self.read_string('N'))
        elif name == 'o2_verbOps':
            verb = self.fetch_byte()
            args = [verb]
            if verb == 0:
                args.append(self.get_var_or_direct_byte(0x80))
            elif verb == 0xFF:
                args += [self.fetch_byte(), self.fetch_byte()]
            else:
                args += [self.fetch_byte(), self.fetch_byte(), self.get_var_or_direct_byte(0x80),
                         self.fetch_byte(), self.read_string('N')]
        elif name == 'o2_doSentence':
            a = self.get_var_or_direct_byte(0x80)
            args = [a]
            if a not in (0xFB, 0xFC):
                args += [self.get_var_or_direct_word(0x40), self.get_var_or_direct_word(0x20), self.fetch_byte()]
        elif name == 'o5_pseudoRoom':
            args = [self.fetch_byte()]
            while True:
                j = self.fetch_byte()
                if j == 0:
                    break
                args.append(j)
        else:
            spec = scummdis._SPEC[name].split() if scummdis._SPEC[name] else []
            has_r = bool(spec) and spec[0] == 'R'
            for tok in spec:
                if tok == 'R':
                    args.append(self.fetch_byte())
                elif tok == 'v':
                    args.append(self.get_var())
                elif tok[0] == 'B':
                    args.append(self.get_var_or_direct_byte({'1': 0x80, '2': 0x40, '3': 0x20}[tok[1]]))
                elif tok[0] == 'W':
                    args.append(self.get_var_or_direct_word({'1': 0x80, '2': 0x40, '3': 0x20}[tok[1]]))
                elif tok == 'b':
                    args.append(self.fetch_byte())
                elif tok == 'w':
                    args.append(self.fetch_word())
                elif tok in ('S', 'N'):
                    args.append(self.read_string(tok))
                else:
                    raise ValueError('operando %s en el anfitrion' % tok)
        res, _ = self.host_log(op, args)
        if has_r:
            self.write_var(args[0], res)

    # ---- escenarios
    def digest(self):
        v = crc16(b''.join(struct.pack('<H', x) for x in self.vars))
        o = crc16(bytes(self.state))
        sl = []
        for i, s in enumerate(self.slots):
            if s.status != SS_DEAD:
                t = '%d:%d:%d:%d:%d' % (i, s.status, s.where, s.number, s.offs)
                if s.status & 0x7F == SS_PAUSED:
                    t += ':%d' % (s.delay & 0xFFFFFFFF)
                sl.append(t)
        return 'D f=%d V=%04X O=%04X %s S=%s' % (self.frame, v, o, self.game_digest(), ' '.join(sl))


def run_scenario(world, lines):
    """Ejecuta un escenario (lista de ordenes) y devuelve la traza."""
    vm = VM(world)
    out = []
    for ln in lines:
        p = ln.split()
        cmd = p[0]
        try:
            if cmd == 'INIT':
                vm.reset()
            elif cmd == 'SETVAR':
                vm.vars[int(p[1])] = int(p[2]) & 0xFFFF
            elif cmd == 'SCRIPT':
                vm.run_script(int(p[1]))
            elif cmd == 'ROOMSCRIPT':          # un script sintetico como script de sala
                vm.start_slot(WIO_ROOM, 9000 + int(p[1]), world.scripts[int(p[1])], 0)
            elif cmd == 'LOADROOM':
                if int(p[1]) != vm.cur_room:
                    vm.start_scene(int(p[1]))
            elif cmd in ('ENTRY', 'EXIT'):
                r = world.rooms[int(p[1])]
                if cmd == 'ENTRY' and r.encd_off:
                    vm.start_slot(WIO_ROOM, SCRIPT_NUM_ENCD, r.entry_script(), 0)
                elif cmd == 'EXIT' and r.excd_off:
                    vm.start_slot(WIO_ROOM, SCRIPT_NUM_EXCD, r.exit_script(), 0)
            elif cmd == 'OBJ':
                obj, verb = int(p[1]), int(p[2])
                room, block = world.objects[obj]
                i = vm.get_slot()      # runObjectScript pide la ranura antes de buscar el verbo
                offs = verb_entry(block, verb)
                if offs:
                    vm.start_slot(WIO_ROOM, obj, block, offs)
            elif cmd == 'INPUT':               # un clic o una tecla para el siguiente fotograma
                vm.pending.append((int(p[1]), int(p[2])))
            elif cmd == 'FRAMES':
                delta, n = int(p[1]), int(p[2])
                for _ in range(n):
                    vm.frame += 1
                    vm.step_frame(delta)
                    vm.trace.append(vm.digest())
            else:
                raise ValueError(ln)
        except VMError as e:
            vm.trace.append('ERR %d' % e.code)
            out += vm.trace
            return out, vm
        out += vm.trace
        vm.trace = []
        if cmd in ('SCRIPT', 'ENTRY', 'EXIT', 'OBJ', 'LOADROOM', 'ROOMSCRIPT'):
            out.append(vm.digest())
    return out, vm


# --------------------------------------------------------------------------------------------- empaquetado
PAGE = 8192              # tamano de una pagina fisica
WINDOW = 0x2000          # ventana de datos: el bloque 1 ($2000-$37FF; $3800-$3FFF es la tabla de 256 caracteres)
PAGE_USABLE = 0x1800     # lo que cabe en la ventana: 6 KB de cada pagina


class Packer:
    """Reparte los bloques de codigo en paginas de 8 KB sin cruzar el limite de una pagina."""

    def __init__(self, first_page=8):
        self.pages = {}
        self.cur = first_page
        self.fill = 0

    def add(self, data):
        if len(data) > PAGE_USABLE:
            raise ValueError('bloque de %d bytes' % len(data))
        if self.fill + len(data) > PAGE_USABLE:
            self.cur += 1
            self.fill = 0
        page = self.pages.setdefault(self.cur, bytearray(PAGE))
        page[self.fill:self.fill + len(data)] = data
        addr = WINDOW + self.fill
        self.fill += len(data)
        return self.cur, addr


BLOB_MAX = 1024


def room_blob(r):
    """Lo que el Z80 copia al empezar la sala: n, cajas (8 bytes), matriz n*(n+1), nobj y objetos (11 bytes: id,
    caminar x, caminar y, dir, x, y, ancho, alto en 8 px, padre y estado del padre)."""
    n = len(r.boxes)
    b = bytearray([n])
    for box in r.boxes:
        b += bytes(box)
    b += bytes(r.matrix)
    b.append(len(r.objects))
    for o in r.objects:
        b += struct.pack('<HBBBBBBBBB', o.id, o.walk_x // 8, o.walk_y // 2, o.actordir, o.x // 8, o.y // 8, o.width // 8,
                         o.height // 8, o.parent, o.parentstate * 8)
    if len(b) > BLOB_MAX:
        raise ValueError('sala %d: blob de %d bytes' % (r.number if hasattr(r, 'number') else -1, len(b)))
    return bytes(b)


def pack_world(world, path):
    pk = Packer()
    sdir, odir, rdir = [], [], []
    for i, code in sorted(world.scripts.items()):
        page, addr = pk.add(code)
        sdir.append((i, page, addr))
    for oid, (rn, block) in sorted(world.objects.items()):
        page, addr = pk.add(block)
        odir.append((oid, rn, page, addr, len(block)))
    for rn, r in sorted(world.rooms.items()):
        blob = room_blob(r)
        for kind, code in ((1, r.entry_script() if r.encd_off else b''), (2, r.exit_script() if r.excd_off else b''),
                           (3, blob)):
            if code:
                page, addr = pk.add(code)
                rdir.append((rn, kind, page, addr, len(code)))
    with open(path, 'wb') as f:
        f.write(b'VMW1')
        f.write(struct.pack('<H', len(pk.pages)))
        for pg in sorted(pk.pages):
            f.write(struct.pack('<B', pg))
            f.write(bytes(pk.pages[pg]))
        f.write(struct.pack('<H', len(sdir)))
        for e in sdir:
            f.write(struct.pack('<HBH', *e))
        f.write(struct.pack('<H', len(odir)))
        for e in odir:
            f.write(struct.pack('<HHBHH', *e))
        f.write(struct.pack('<H', len(rdir)))
        for e in rdir:
            f.write(struct.pack('<BBBHH', *e))
        f.write(struct.pack('<H', NUM_OBJECTS))
        f.write(bytes(world.owner))
        f.write(bytes(world.state))
        f.write(struct.pack('<H', len(world.rooms)))
        for rn, r in sorted(world.rooms.items()):
            f.write(struct.pack('<BH', rn, r.width))
    return len(pk.pages)


def walk_scenarios(world, seeds):
    """Caminatas al azar en cada sala con cajas: salida, destinos (dentro y fuera de las cajas) y objeto."""
    out = []
    for seed in range(seeds):
        rng = random.Random(5000 + seed)
        for rn, r in sorted(world.rooms.items()):
            if not r.objects:
                continue
            for rep in range(1 if rn < 60 else 6):                    # las salas inventadas, mas veces
              ln = ['INIT', 'SETVAR 100 %d' % rn]
              vals = [rng.randrange(0, 80), rng.randrange(40, 80)]
              for _ in range(3):
                  vals += [rng.randrange(0, 90), rng.randrange(30, 90)]
              ln += ['SETVAR %d %d' % (101 + i, v) for i, v in enumerate(vals)]
              ln += ['SETVAR 109 %d' % rng.choice(r.objects).id,
                     'SETVAR 111 %d' % rng.randrange(0, 80), 'SETVAR 112 %d' % rng.randrange(40, 80),
                     'SCRIPT 209', 'FRAMES 4 700']
              out.append(('walk%02d.s%d.%d' % (rn, seed, rep), ln))
              if rn >= 60:                                  # salas inventadas: tambien con el actor 5 como jugador
                  out.append(('walk%02d.p%d.%d' % (rn, seed, rep), ln[:2] + ['SETVAR 42 3', 'SETVAR 43 6'] + ln[2:]))
    return out


def input_scenarios(world, seeds):
    """Clics y teclas sobre los objetos de cada sala (script de entrada 4, frases, script 2) y doSentence directo."""
    out = []
    for seed in range(seeds):
        rng = random.Random(7000 + seed)
        for rn, r in sorted(world.rooms.items()):
            if not r.objects:
                continue
            base = ['INIT']
            for v in range(NUM_VARS):
                if v in (14, 15, 16):
                    base.append('SETVAR %d %d' % (v, rng.randrange(60, 200)))
                elif rng.random() < 0.3:
                    base.append('SETVAR %d %d' % (v, rng.choice([0, 1, 2, 3, 4, 5, 7, 8, 10, 13, 15, 255])))
            o = rng.choice(r.objects)
            mx = o.x // 8 + o.width // 16
            my = (o.y + o.height // 2) // 2
            if rng.random() < 0.3:
                mx, my = rng.randrange(0, 80), rng.randrange(0, 64)
            ln = base + ['LOADROOM %d' % rn, 'SETVAR 30 %d' % mx, 'SETVAR 31 %d' % my]
            for kind, (area, val) in (('s', (2, 0)), ('v', (1, rng.choice([1, 2, 3, 4, 5, 7, 8, 13, 15, 20, 21, 22, 252]))),
                                      ('k', (4, rng.choice([5, 8, 13, 60, 62, 32, 49]))), ('i', (3, o.id))):
                out.append(('inp%02d.%s.s%d' % (rn, kind, seed), ln + ['INPUT %d %d' % (area, val), 'FRAMES 4 60']))
            # doSentence directo con el objeto de la sala y un verbo suyo (o uno cualquiera)
            verbs = []
            p = 15
            blk = world.objects.get(o.id, (0, b''))[1]
            while blk and blk[p] != 0:
                verbs.append(blk[p])
                p += 2
            verb = rng.choice(verbs + [255, 3, 7, 253, 250]) if verbs else rng.choice([255, 3, 7, 253, 250])
            other = rng.choice(r.objects).id
            out.append(('sent%02d.s%d' % (rn, seed), base + ['SETVAR 100 %d' % rn, 'SETVAR 120 %d' % verb,
                                                              'SETVAR 121 %d' % o.id, 'SETVAR 122 %d' % other,
                                                              'SCRIPT 210', 'FRAMES 4 30']))
    return out


def make_scenarios(world, seeds=2):
    """Escenarios: cada sala (entrada, fotogramas, salida), cada verbo de cada objeto, cada script global."""
    sc = []

    def init(rng):
        lines = ['INIT']
        for v in range(NUM_VARS):
            if v in (14, 15, 16):
                lines.append('SETVAR %d %d' % (v, rng.randrange(60, 200)))
            elif rng.random() < 0.35:
                lines.append('SETVAR %d %d' % (v, rng.choice([1, 1, 2, 3, 4, 5, 8, 10, 255])))
        return lines
    for seed in range(seeds):
        rng = random.Random(1000 + seed)
        for rn in sorted(world.rooms):
            ln = init(rng) + ['LOADROOM %d' % rn, 'FRAMES 4 30', 'LOADROOM 0', 'FRAMES 4 10']
            sc.append(('room%02d.s%d' % (rn, seed), ln))
        for oid, (rn, block) in sorted(world.objects.items()):
            verbs = []
            p = 15
            while block[p] != 0:
                verbs.append(block[p])
                p += 2
            for verb in verbs:
                ln = init(rng) + ['LOADROOM %d' % rn, 'OBJ %d %d' % (oid, verb), 'FRAMES 3 25']
                sc.append(('obj%03d.v%02X.s%d' % (oid, verb, seed), ln))
        for sid in sorted(world.scripts):
            if sid >= 180:
                continue                  # los sinteticos tienen sus propios escenarios
            ln = init(rng) + ['SCRIPT %d' % sid, 'FRAMES 3 25']
            sc.append(('scr%03d.s%d' % (sid, seed), ln))
    sc += vmsynth.synth_scenarios()
    sc += walk_scenarios(world, seeds)
    sc += input_scenarios(world, seeds)
    return sc


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 1
    d, cmd, out = sys.argv[1], sys.argv[2], sys.argv[3]
    world = World(d)
    os.makedirs(out, exist_ok=True)
    if cmd == 'pack':
        n = pack_world(world, os.path.join(out, 'world.bin'))
        print('mundo: %d paginas de datos, %d scripts, %d objetos' % (n, len(world.scripts), len(world.objects)))
    elif cmd == 'scenarios':
        seeds = int(sys.argv[4]) if len(sys.argv) > 4 else 2
        sc = make_scenarios(world, seeds)
        errs = 0
        maxs = 0
        with open(os.path.join(out, 'scenarios.txt'), 'w') as fs, open(os.path.join(out, 'expected.txt'), 'w') as fe:
            for name, lines in sc:
                trace, vm = run_scenario(world, lines)
                maxs = max(maxs, vm.max_slots)
                if trace and trace[-1].startswith('ERR'):
                    errs += 1
                    if trace[-1] == 'ERR %d' % E_BUDGET:
                        continue          # bucle sin ceder el control: no sirve para comparar
                fs.write('SCENARIO %s\n' % name)
                fs.write('\n'.join(lines) + '\nEND\n')
                fe.write('SCENARIO %s\n' % name)
                fe.write('\n'.join(trace) + '\nEND\n')
        print('%d escenarios, %d acaban en error, ranuras simultaneas maximas: %d' % (len(sc), errs, maxs))
    return 0


if __name__ == '__main__':
    sys.exit(main())
