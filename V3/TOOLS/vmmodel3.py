#!/usr/bin/env python3
"""Modelo de referencia del interprete SCUMM v3 (Indy3 EGA, ScummEngine_v3old) para el Z80 y el arnes de pruebas.

Es la especificacion contra la que se compara el Z80 por trazas, igual que SCUMM/V2/TOOLS/vmmodel.py + vmgame.py en v2.
Transcribe la semantica de ScummVM (engines/scumm: script.cpp, script_v5.cpp, script_v4.cpp, script_v3.cpp, scumm.cpp
scummLoop, y lo que usa vmgame3.py). Parte de V3/TOOLS/scumm3vm.py (la VM de medida del estudio, que sigue ahi) pero
con la semantica completa: mensajes (actorTalk y displayDialog con sus codigos de escape y _keepText), getDist,
actorFromPos, findObject con la cadena de padres, clases con la traduccion de GF_SMALL_HEADER, cutscene/override con
la pila de escenas, stopScript/stopObjectCode, resourceRoutines y las demas.

NUCLEO DETERMINISTA: todo lo que lee o escribe un script (variables, ranuras, retardos, estados, duenos, clases,
inventario, actores, cajas, camara, mensajes, frases, verbos) esta aqui. Dibujo, sonido, texto en pantalla, cambio de
sala y demas salen al anfitrion como lineas de la traza.

FORMATO DE LA TRAZA (una linea de texto por suceso; el arnes del Z80 tiene que producir exactamente las mismas):
  H oo [a,b,...]    bytecode cuyo efecto es solo del anfitrion (roomOps, lights, drawBox, cursorCommand, resourceRoutines,
                    saveLoadVars, systemOps...). oo = opcode en hexadecimal; los argumentos van ya decodificados (cadenas:
                    str_value). Si el opcode tiene resultado, es mock_hash(...) y se escribe en la variable de resultado.
  E n [a,b,...]     suceso para el back-end de un opcode del nucleo: 1 inicio de sonido [snd], 2 parar sonido [snd],
                    3 parar todos [], 4 consulta isSoundRunning [snd] (resultado = bit 0 de mock_hash), 5 texto, 6 sala
                    cargada [sala], 8 estado de objeto [obj, estado], 9 drawObject [obj, x, y, estado], 10 la camara se
                    movio [x], 11 verbo [id, modo], 12 (reservado actor).
                    Texto (5): [0, actor, color, 0, n, str_value] es una pagina de mensaje de displayDialog;
                    [1, x, y, color, banderas, str_value] es texto suelto (print en la ranura 1); [255,0,0,0,0,0] borra el area.
  D f=.. V=.. S=..  resumen del estado tras cada FRAMES y tras cada orden que ejecuta scripts: fotograma, crc16 de las 800
                    variables (V), crc de actores (A), de estados+duenos+clases (O), del inventario (I), mensaje (M =
                    haveMsg, talkDelay, keepText, sala, ultimo sonido), frases (Q), camara (C = cur, dest, modo, sigue,
                    moviendose), userPut y cursor (U) y las ranuras vivas S = i:estado:donde:numero:offset[:retardo]
                    [:fN congelada][:cN cutsceneOverride].
  ERR n             error fatal de ScummVM (codigos E_* de vmcommon3.py): la traza acaba ahi.

ESCENARIOS (ficheros scenarios.txt / expected.txt): una orden por linea; mismas que v2 mas las de v3.
  INIT                         estado nuevo (variables a 0, CHARINC = 4...)
  OPT proteccion 0|1           1 = proteccion anticopia como el original (omision); 0 = Var[57] = 1 en la sala 92 tras 30 fotogramas
  OPT sonido mock|timed        modelo de sonido (omision mock: isSoundRunning sale al anfitrion)
  SETVAR v valor               variable
  SCRIPT n [args...]           runScript(n) (global o local de la sala en uso) con locales Local[0..]
  LOADROOM n                   startScene(n) si cambia de sala
  ENTRY n / EXIT n             arranca el script de entrada / salida de la sala n sin cargarla
  OBJ obj verbo                runObjectScript(obj, verbo)
  INPUT area valor [modo]      runInputScript(area, valor, modo) en el siguiente fotograma, tal cual
  CLICK x y                    clic del raton en coordenadas de pantalla (0-319, 0-199): scene/verbo con VAR_VIRT_MOUSE_X/Y
                               y runInputScript(2, 0, 0) si cae en la pantalla principal (caso de v3)
  RCLICK                       boton derecho (= tecla de salir de la escena cortada en v0-v3)
  KEY k                        tecla (ASCII)
  ESC                          tecla ESC (abortCutscene si VAR_CUTSCENEEXIT_KEY != 0)
  SENTENCE verbo a b           doSentence(verbo, a, b)
  ACTOR n sala x y traje       coloca al actor: setActorCostume + putActor
  FRAMES delta n               n fotogramas con VAR_TIMER = delta

Uso:
  vmmodel3.py DIR_LFL boot N [semilla] [--proteccion] [--sonido-real]   arranca el juego (script 1) con clics al azar
  vmmodel3.py DIR_LFL scenarios SALIDA [SEMILLAS]   escribe scenarios.txt y expected.txt
  vmmodel3.py DIR_LFL scenarios-core SALIDA [SEMILLAS] [SALAS]   lo mismo con el modelo del nucleo (CoreVM, fase 3; SALAS = 1,15,...)
El mundo del arnes del Z80 es DATA.BIN de V3/TOOLS/pack_data3.py (formato definitivo; ya no hay world3.bin).
"""
import copy
import os
import re
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scumm3res as R          # noqa: E402
import scumm3dis as DIS        # noqa: E402
from vmsynth3 import SYNTH_SCRIPT  # noqa: E402

from vmcommon3 import *        # noqa: E402,F401
from vmgame3 import GameMixin, MBS_LEFT_CLICK, ObjData  # noqa: E402

P1, P2, P3 = 0x80, 0x40, 0x20
OPTRACE = int(os.environ.get('OPTRACE', '0'))


# ------------------------------------------------------------------------------------------------ mundo
class World:
    """Los datos del juego que necesita el modelo."""

    def __init__(self, directory):
        self.dir = directory
        ix = R.Index(directory)
        self.index = ix
        self.classes = list(ix.classes)
        self.owner = list(ix.owner)
        self.state = list(ix.state)
        self.scripts = {}                      # id -> codigo (sin la cabecera de 4 bytes)
        for i in range(min(NUM_GLOBAL_SCRIPTS, len(ix.res['script']))):
            b = ix.resource('script', i)
            if b is not None:
                self.scripts[i] = b[4:]
        if os.environ.get('SCUMM_SYNTH'):      # fase 9 (solo pruebas): el script global 199 de pack_data3.py
            self.scripts[199] = bytes.fromhex(open(os.environ['SCUMM_SYNTH']).read().strip())
        self.rooms = {}
        for rn in ix.rooms():
            self.rooms[rn] = R.Room(ix, rn)
        self.objects = {}                      # id -> (sala, objeto)
        for rn, r in sorted(self.rooms.items()):
            for o in r.objects:
                self.objects.setdefault(o.id, (rn, o))
        self.sound_table = build_sound_table(ix, os.path.join(directory, '..', 'preview_hr', 'snd', 'SOUNDS.TXT'))   # fase 8: modo de sonido "real"

    def sound_size(self, n):
        b = self.index.resource('sound', n)
        return len(b) if b else 0


def build_sound_table(ix, txt_path):
    """La tabla de sonidos del Z80 (pack_data3.read_sounds + las banderas de existencia y cancion de build): 256 x (prioridad, banderas, duracion u16)."""
    t = bytearray(256 * 4)
    if txt_path and os.path.exists(txt_path):
        with open(txt_path) as f:
            for ln in f:
                if ln.startswith('#') or len(ln.split()) < 7:
                    continue
                sid, prio, rest, ticks, loop, tempo, ttick = (int(x) for x in ln.split()[:7])
                dur = 65535 if loop >= 0 else min(65534, -(-ticks * 50 // 236))
                t[4 * sid:4 * sid + 4] = struct.pack('<BBH', prio, (1 if rest else 0) | (2 if loop >= 0 else 0) | (4 if tempo else 0), dur)
    for sid in range(256):
        r = ix.resource('sound', sid)
        if r:
            t[4 * sid + 1] |= 0x80 | (8 if len(r) > 1000 else 0)
    return bytes(t)


# ------------------------------------------------------------------------------------------------ modelo
class Slot:
    def __init__(self):
        self.clear()

    def clear(self):
        self.number = 0
        self.status = SS_DEAD
        self.where = 0
        self.code = b''
        self.offs = 0
        self.freeze_resistant = False
        self.recursive = False
        self.freeze_count = 0
        self.delay = 0
        self.cutscene_override = 0
        self.didexec = False
        self.base = 0                          # inicio del bloque de codigo en self.code: los offsets de la traza van desde aqui


class Nest:
    def __init__(self, number, where, slot):
        self.number, self.where, self.slot = number, where, slot


class VM(GameMixin):
    def __init__(self, world, seed=1, protection=True, sound_mode='mock', soundcard=0):
        self.w = world
        self.seed = seed
        self.protection = protection
        self.saves = {}                        # fase 9: ranura -> (nombre, estado) de las partidas guardadas (modo real_saves)
        self.real_saves = False
        self.sound_mode = sound_mode
        self.soundcard = soundcard
        self.trace = []
        self.reset()

    def reset(self):
        self.vars = [0] * NUM_VARS
        self.slots = [Slot() for _ in range(NUM_SLOT)]
        self.locals = [[0] * NUM_LOCAL for _ in range(NUM_SLOT)]
        self.nest = []
        self.cur = 0xFF
        self.code = b''
        self.ptr = 0
        self.opcode = 0
        self.res = 0                           # _resultVarNumber
        self.stack = []                        # _vmStack de expression
        self.frame = 0
        self.insn = 0
        self.max_slots = 0
        self.resource_mapper = {}
        self.in92 = 0
        self.pan_on = False
        self.pan_px = 0
        self.charset_color = 15
        self.game_reset(self.soundcard)
        self.reset_vars_v3()

    # ---- lectura del script
    def fetch_byte(self):
        if self.ptr >= len(self.code):
            raise VMError(E_RANGE, 'fin del codigo')
        b = self.code[self.ptr]
        self.ptr += 1
        return b

    def fetch_word(self):
        lo = self.fetch_byte()
        return lo | (self.fetch_byte() << 8)

    def fetch_word_signed(self):
        return s16(self.fetch_word())

    def update_script_ptr(self):
        if self.cur != 0xFF:
            self.slots[self.cur].offs = self.ptr

    # ---- variables (ScummEngine::readVar / writeVar, version 3)
    def read_var(self, var):
        if var & 0x2000:
            a = self.fetch_word()
            if a & 0x2000:
                var += self.read_var(a & ~0x2000)
            else:
                var += a & 0xFFF
            var &= 0xFFFF & ~0x2000             # el Z80 suma en 16 bits
        if not (var & 0xF000):
            if not 0 <= var < NUM_VARS:
                raise VMError(E_RANGE, 'variable %d' % var)
            return self.vars[var]
        if var & 0x8000:
            bit = var & 0xF
            v = (var >> 4) & 0xFF
            return 1 if (self.vars[v] & 0xFFFF) & (1 << bit) else 0
        if var & 0x4000:
            idx = var & 0xFFF
            if idx >= NUM_LOCAL:
                raise VMError(E_RANGE, 'local %d' % idx)
            return self.locals[self.cur][idx] if self.cur != 0xFF else 0
        raise VMError(E_RANGE, 'varbits')

    def write_var(self, var, value):
        value = s16(value)
        if not (var & 0xF000):
            if not 0 <= var < NUM_VARS:
                raise VMError(E_RANGE, 'variable %d' % var)
            self.vars[var] = value
            return
        if var & 0x8000:
            bit = var & 0xF
            v = (var >> 4) & 0xFF
            cur = self.vars[v] & 0xFFFF
            cur = (cur | (1 << bit)) if value else (cur & ~(1 << bit))
            self.vars[v] = s16(cur)
            return
        if var & 0x4000:
            idx = var & 0xFFF
            if idx >= NUM_LOCAL:
                raise VMError(E_RANGE, 'local %d' % idx)
            if self.cur != 0xFF:
                self.locals[self.cur][idx] = value
            return
        raise VMError(E_RANGE, 'varbits (w)')

    def get_var(self):
        return self.read_var(self.fetch_word())

    def get_result_pos(self):
        r = self.fetch_word()
        if r & 0x2000:
            a = self.fetch_word()
            if a & 0x2000:
                r += self.read_var(a & ~0x2000)
            else:
                r += a & 0xFFF
            r &= 0xFFFF & ~0x2000
        self.res = r

    def set_result(self, v):
        self.write_var(self.res, v)

    def vb(self, mask):
        """getVarOrDirectByte"""
        return self.get_var() if self.opcode & mask else self.fetch_byte()

    def vw(self, mask):
        """getVarOrDirectWord"""
        return self.get_var() if self.opcode & mask else self.fetch_word_signed()

    def vararg(self):
        """getWordVararg: lista de 25 palabras. Deja el 0xFF en _opcode, como ScummVM."""
        out = [0] * NUM_LOCAL
        i = 0
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                break
            v = self.vw(P1)
            if i < NUM_LOCAL:
                out[i] = v
            i += 1
        return out

    def read_raw_string(self):
        """La cadena en bruto del script, con su 0 final (resStrLen)."""
        s = bytearray()
        while True:
            c = self.fetch_byte()
            s.append(c)
            if c == 0:
                return bytes(s)
            if c == 0xFF:
                c = self.fetch_byte()
                s.append(c)
                if c not in (1, 2, 3, 8):
                    s.append(self.fetch_byte())
                    s.append(self.fetch_byte())

    def jump_relative(self, cond):
        off = self.fetch_word_signed()
        if not cond:
            self.ptr += off

    # ---- ranuras y scripts (script.cpp)
    def get_script_slot(self):
        for i in range(1, NUM_SLOT):
            if self.slots[i].status == SS_DEAD:
                return i
        raise VMError(E_NOSLOT)

    def start_slot(self, number, where, code, offs, args=None, fr=False, rec=False, slot=-1, base=None):
        """base: inicio del bloque que el Z80 tiene aparte (script local, ENCD/EXCD, OBCD); por omision, offs."""
        if slot == -1:
            slot = self.get_script_slot()
        s = self.slots[slot]
        s.number, s.code, s.offs, s.where = number, code, offs, where
        s.base = offs if base is None else base
        s.status = SS_RUNNING
        s.freeze_resistant, s.recursive = fr, rec
        s.freeze_count = s.delay = 0
        s.cutscene_override = 0 if s.status == SS_DEAD else s.cutscene_override
        s.cutscene_override = 0
        self.locals[slot] = list(args) + [0] * (NUM_LOCAL - len(args)) if args else [0] * NUM_LOCAL
        self.run_nested(slot)

    def run_script(self, script, fr=False, rec=False, args=None):
        """ScummEngine::runScript"""
        if not script:
            return
        if not rec:
            self.stop_script(script)
        if script < NUM_GLOBAL_SCRIPTS:
            synth = getattr(self, 'synth_codes', {})
            if script in synth:                         # 10e: ordenes CODER y SYNTH (scripts globales sinteticos que se pueden arrancar desde el bytecode)
                self.start_slot(script, WIO_GLOBAL, synth[script], 0, args, fr, rec)
                return
            if script not in self.w.scripts:
                raise VMError(E_NOSCRIPT, 'script %d' % script)
            self.start_slot(script, WIO_GLOBAL, self.w.scripts[script], 0, args, fr, rec, base=0)
        else:
            r = self.room
            offs = dict(r.local_scripts).get(script, 0) if r else 0
            if not offs:
                raise VMError(E_NOSCRIPT, 'local %d no esta en la sala %d' % (script, self.cur_room))
            self.start_slot(script, WIO_LOCAL, r.file, offs, args, fr, rec)

    def run_object_script(self, obj, entry, fr=False, rec=False, args=None, slot=-1):
        """ScummEngine::runObjectScript"""
        if not obj:
            return
        if not rec:
            self.stop_object_script(obj)
        where = self.where_is_object(obj)
        if where == WIO_NOT_FOUND:
            return
        if slot == -1:
            slot = self.get_script_slot()
        offs = self.get_verb_entrypoint(obj, entry)
        if offs == 0:
            return
        code, base = self.obcd_of(obj)
        self.start_slot(obj, where, code, base + offs, args, fr, rec, slot, base)

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
            if sl.number == entry.number and sl.where == entry.where and sl.status != SS_DEAD and sl.freeze_count == 0:
                self.cur = entry.slot
                self.load(entry.slot)
                return
        self.cur = 0xFF

    def load(self, i):
        self.code = self.slots[i].code
        self.ptr = self.slots[i].offs

    def exec_script(self):
        while self.cur != 0xFF:
            self.insn += 1
            if self.insn > MAX_INSN:
                raise VMError(E_BUDGET)
            if OPTRACE and self.frame >= OPTRACE:       # 10g-3 (depuracion): OPTRACE=fotograma -> cada opcode a stderr
                sl = self.slots[self.cur]
                sys.stderr.write('OP f=%d s=%d n=%d @%04X %s' % (self.frame, self.cur, sl.number, self.ptr, DIS.NAMES[self.code[self.ptr]]) + chr(10))
            self.opcode = self.fetch_byte()
            self.slots[self.cur].didexec = True
            self.execute(self.opcode)

    def execute(self, op):
        self.op_byte = op
        name = DIS.NAMES[op]
        h = getattr(self, 'o_' + name, None)
        if h is None:
            raise VMError(E_BADOP, 'opcode %02X %s' % (op, name))
        h()

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
                n.number, n.slot, n.where = 0, 0xFF, 0xFF

    def stop_object_script(self, script):
        if script == 0:
            return
        for i, ss in enumerate(self.slots):
            if script == ss.number and ss.status != SS_DEAD and ss.where in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT):
                ss.number = 0
                ss.status = SS_DEAD
                if self.cur == i:
                    self.cur = 0xFF
        for n in self.nest:
            if n.number == script and n.where in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT):
                n.number, n.slot, n.where = 0, 0xFF, 0xFF

    def stop_object_code(self):
        ss = self.slots[self.cur]
        if ss.where not in (WIO_GLOBAL, WIO_LOCAL):
            self.stop_object_script(ss.number)
        else:
            ss.number = 0
            ss.status = SS_DEAD
        self.cur = 0xFF

    def is_script_running(self, script):
        return any(ss.number == script and ss.where in (WIO_GLOBAL, WIO_LOCAL) and ss.status != SS_DEAD
                   for ss in self.slots)

    def is_script_in_use(self, script):
        return any(ss.number == script for ss in self.slots)

    def decrease_script_delay(self, amount):
        for ss in self.slots:
            if ss.status == SS_PAUSED:
                ss.delay -= amount
                if ss.delay < 0:
                    ss.status = SS_RUNNING
                    ss.delay = 0

    def run_all_scripts(self):
        for ss in self.slots:
            ss.didexec = False
        self.cur = 0xFF
        for i in range(NUM_SLOT):
            if self.slots[i].status == SS_RUNNING and not self.slots[i].didexec:
                self.cur = i
                self.load(i)
                self.exec_script()

    def freeze_scripts(self, flag):
        for i, s in enumerate(self.slots):
            if self.cur != i and s.status != SS_DEAD and (not s.freeze_resistant or flag >= 0x80):
                s.status |= 0x80
                s.freeze_count += 1
        for st in self.sentence:
            st['freeze'] += 1
        if self.cut_script_index != 0xFF:
            s = self.slots[self.cut_script_index]
            s.status &= 0x7F
            s.freeze_count = 0

    def unfreeze_scripts(self):
        for s in self.slots:
            if s.status & 0x80:
                s.freeze_count -= 1
                if s.freeze_count == 0:
                    s.status &= 0x7F
        for st in self.sentence:
            if st['freeze'] > 0:
                st['freeze'] -= 1

    def run_exit_script(self):
        if self.vars[VAR_EXIT_SCRIPT]:
            self.run_script(self.vars[VAR_EXIT_SCRIPT])
        if self.excd:
            self.start_slot(SCRIPT_NUM_EXCD, WIO_ROOM, self.room.file, self.excd)
        if self.vars[VAR_EXIT_SCRIPT2]:
            self.run_script(self.vars[VAR_EXIT_SCRIPT2])

    def run_entry_script(self):
        if self.vars[VAR_ENTRY_SCRIPT]:
            self.run_script(self.vars[VAR_ENTRY_SCRIPT])
        if self.encd:
            self.start_slot(SCRIPT_NUM_ENCD, WIO_ROOM, self.room.file, self.encd)
        if self.vars[VAR_ENTRY_SCRIPT2]:
            self.run_script(self.vars[VAR_ENTRY_SCRIPT2])

    def kill_scripts_and_resources(self):
        for ss in self.slots:
            if ss.where in (WIO_ROOM, WIO_FLOBJECT, WIO_LOCAL):
                ss.cutscene_override = 0
                ss.status = SS_DEAD
        for i in range(NUM_NEW_NAMES):
            obj = self.new_names[i]
            if obj:
                owner = self.get_owner(obj)
                if owner == 0 or owner == OWNER_ROOM:
                    self.new_names[i] = 0
                    self.new_name_str[i] = b''

    # ---- escenas cortadas (cutscene / override)
    def begin_cutscene(self, args):
        scr = self.cur
        self.slots[scr].cutscene_override += 1
        self.cut_sp += 1
        if self.cut_sp >= MAX_CUTSCENE:
            raise VMError(E_CUTSCENE, 'pila de cutscenes desbordada')
        self.cut_data[self.cut_sp] = args[0]
        self.cut_script[self.cut_sp] = 0
        self.cut_ptr[self.cut_sp] = 0
        self.cut_script_index = scr
        if self.vars[VAR_CUTSCENE_START_SCRIPT]:
            self.run_script(self.vars[VAR_CUTSCENE_START_SCRIPT], False, False, args)
        self.cut_script_index = 0xFF

    def end_cutscene(self):
        ss = self.slots[self.cur]
        if ss.cutscene_override > 0:
            ss.cutscene_override -= 1
        args = [self.cut_data[self.cut_sp]] + [0] * (NUM_LOCAL - 1)
        self.vars[VAR_OVERRIDE] = 0
        if self.cut_ptr[self.cut_sp] and ss.cutscene_override > 0:
            ss.cutscene_override -= 1
        self.cut_script[self.cut_sp] = 0
        self.cut_ptr[self.cut_sp] = 0
        if self.cut_sp == 0:
            raise VMError(E_CUTSCENE, 'pila de cutscenes vacia')
        self.cut_sp -= 1
        if self.vars[VAR_CUTSCENE_END_SCRIPT]:
            self.run_script(self.vars[VAR_CUTSCENE_END_SCRIPT], False, False, args)

    def abort_cutscene(self):
        idx = self.cut_sp
        offs = self.cut_ptr[idx]
        if offs:
            ss = self.slots[self.cut_script[idx]]
            ss.offs = offs
            ss.status = SS_RUNNING
            ss.freeze_count = 0
            if ss.cutscene_override > 0:
                ss.cutscene_override -= 1
            self.vars[VAR_OVERRIDE] = 1
            self.cut_ptr[idx] = 0

    # ---- anfitrion
    def host_log(self, args):
        s = mock_hash(self.opcode_logged, args, self.frame)
        self.trace.append('H %02X [%s]' % (self.opcode_logged, ','.join(str(a & 0xFFFF) for a in args)))
        return s & 0xFF

    def host(self, args, op=None):
        self.opcode_logged = self.op_byte if op is None else op
        return self.host_log(args)

    def execute_main(self, op):
        self.op_byte = op
        self.execute(op)

    # =========================================================================================== opcodes
    # control
    def o_stopObjectCode(self):
        self.stop_object_code()

    def o_breakHere(self):
        self.break_here()

    def o_endCutscene(self):
        self.end_cutscene()

    def o_cutscene(self):
        self.begin_cutscene(self.vararg())

    def o_beginOverride(self):
        if self.fetch_byte() != 0:                  # beginOverride: sin tocar VAR_OVERRIDE en v3
            self.cut_ptr[self.cut_sp] = self.ptr
            self.cut_script[self.cut_sp] = self.cur
            self.fetch_byte()
            self.fetch_word()
        else:                                       # endOverride
            self.cut_ptr[self.cut_sp] = 0
            self.cut_script[self.cut_sp] = 0

    def o_wait(self):                               # Indy3: SO_WAIT_FOR_MESSAGE sin subopcode
        old = self.ptr - 1
        if self.vars[VAR_HAVE_MSG]:
            self.ptr = old
            self.break_here()

    def o_waitForActor(self):
        old = self.ptr - 1
        a = self.deref_actor(self.vb(P1))
        if a.moving:
            self.ptr = old
            self.break_here()

    def o_waitForSentence(self):
        if self.sentence:
            if self.sentence[-1]['freeze'] and not self.is_script_in_use(self.vars[VAR_SENTENCE_SCRIPT]):
                return
        elif not self.is_script_in_use(self.vars[VAR_SENTENCE_SCRIPT]):
            return
        self.ptr -= 1
        self.break_here()

    def o_delay(self):
        d = self.fetch_byte()
        d |= self.fetch_byte() << 8
        d |= self.fetch_byte() << 16
        self.slots[self.cur].delay = d
        self.slots[self.cur].status = SS_PAUSED
        self.break_here()

    def o_delayVariable(self):
        self.slots[self.cur].delay = self.get_var()
        self.slots[self.cur].status = SS_PAUSED
        self.break_here()

    def o_jumpRelative(self):
        self.jump_relative(False)

    def o_equalZero(self):
        self.jump_relative(self.get_var() == 0)

    def o_notEqualZero(self):
        self.jump_relative(self.get_var() != 0)

    def _cmp(self, f):
        a = s16(self.get_var())
        b = s16(self.vw(P1))
        self.jump_relative(f(a, b))

    def o_isEqual(self): self._cmp(lambda a, b: b == a)
    def o_isNotEqual(self): self._cmp(lambda a, b: b != a)
    def o_isGreater(self): self._cmp(lambda a, b: b > a)
    def o_isGreaterEqual(self): self._cmp(lambda a, b: b >= a)
    def o_isLess(self): self._cmp(lambda a, b: b < a)
    def o_isLessEqual(self): self._cmp(lambda a, b: b <= a)

    # variables
    def _arith(self, f):
        self.get_result_pos()
        a = self.vw(P1)
        self.set_result(f(self.read_var(self.res), a))

    def o_move(self):
        self.get_result_pos()
        self.set_result(self.vw(P1))

    def o_add(self): self._arith(lambda r, a: r + a)
    def o_subtract(self): self._arith(lambda r, a: r - a)
    def o_multiply(self): self._arith(lambda r, a: r * a)
    def o_and(self): self._arith(lambda r, a: r & a)
    def o_or(self): self._arith(lambda r, a: r | a)

    def o_divide(self):
        def f(r, a):
            if a == 0:
                raise VMError(E_RANGE, 'division por cero')
            return cdiv(r, a)
        self._arith(f)

    def o_increment(self):
        self.get_result_pos()
        self.set_result(self.read_var(self.res) + 1)

    def o_decrement(self):
        self.get_result_pos()
        self.set_result(self.read_var(self.res) - 1)

    def o_setVarRange(self):
        self.get_result_pos()
        a = self.fetch_byte()
        if a == 0:
            raise VMError(E_RANGE, 'setVarRange 0')
        while True:
            b = self.fetch_word_signed() if self.opcode & 0x80 else self.fetch_byte()
            self.set_result(b)
            self.res += 1
            a -= 1
            if a == 0:
                break

    def o_expression(self):
        self.stack = []
        self.get_result_pos()
        dst = self.res

        def pop():
            if not self.stack:
                raise VMError(E_RANGE, 'pila vacia')
            return self.stack.pop()
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                break
            k = self.opcode & 0x1F
            if k == 1:
                self.stack.append(self.vw(P1))
            elif k == 2:
                i = pop()
                self.stack.append(wrap32(i + pop()))
            elif k == 3:
                i = pop()
                self.stack.append(wrap32(pop() - i))
            elif k == 4:
                i = pop()
                self.stack.append(wrap32(i * pop()))
            elif k == 5:
                i = pop()
                if i == 0:
                    raise VMError(E_RANGE, 'division por cero')
                self.stack.append(cdiv(pop(), i))
            elif k == 6:
                self.opcode = self.fetch_byte()
                self.execute(self.opcode)
                self.stack.append(self.vars[0])
        self.res = dst
        self.set_result(pop())

    # scripts
    def o_startScript(self):
        op = self.opcode
        script = self.vb(P1)
        data = self.vararg()
        self.run_script(script, bool(op & 0x20), bool(op & 0x40), data)

    def o_chainScript(self):
        script = self.vb(P1)
        data = self.vararg()
        cur = self.cur
        if cur == 0xFF:
            raise VMError(E_RANGE, 'chainScript sin script')
        s = self.slots[cur]
        fr, rec = s.freeze_resistant, s.recursive
        s.number = 0
        s.status = SS_DEAD
        self.cur = 0xFF
        self.run_script(script, fr, rec, data)

    def o_stopScript(self):
        script = self.vb(P1)
        if not script:
            self.stop_object_code()
        else:
            self.stop_script(script)

    def o_stopObjectScript(self):
        self.stop_object_script(self.vw(P1))

    def o_startObject(self):
        obj = self.vw(P1)
        script = self.vb(P2)
        data = self.vararg()
        self.run_object_script(obj, script, False, False, data)

    def o_freezeScripts(self):
        scr = self.vb(P1)
        if scr != 0:
            self.freeze_scripts(scr)
        else:
            self.unfreeze_scripts()

    def o_isScriptRunning(self):
        self.get_result_pos()
        self.set_result(1 if self.is_script_running(self.vb(P1)) else 0)

    def o_resourceRoutines(self):
        op = self.op_byte
        o = self.fetch_byte()
        self.opcode = o
        resid = 0
        if o != 17:
            resid = self.vb(P1)
        if (o & 0x3F) != (o & 0x1F):
            raise VMError(E_BADSUB, 'resourceRoutines %d' % o)
        k = o & 0x3F
        args = [k, resid]
        if k == 20:
            raise VMError(E_BADSUB, 'loadFlObject no soportado')
        if k not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19):
            raise VMError(E_BADSUB, 'resourceRoutines %d' % k)
        self.host(args, op)

    def o_pseudoRoom(self):
        i = self.fetch_byte()
        while True:
            j = self.fetch_byte()
            if j == 0:
                break
            if j >= 0x80:
                self.resource_mapper[j & 0x7F] = i

    # objetos
    def o_getObjectOwner(self):
        self.get_result_pos()
        self.set_result(self.get_owner(self.vw(P1)))

    def o_setOwnerOf(self):
        obj = self.vw(P1)
        owner = self.vb(P2)
        self.set_owner_of(obj, owner)
        self.ev(EV_OBJSTATE, [obj, self.gstate[obj]])

    def o_ifState(self):
        a = self.vw(P1)
        b = self.vb(P2)
        self.jump_relative(self.get_state(a) == b)

    def o_ifNotState(self):
        a = self.vw(P1)
        b = self.vb(P2)
        self.jump_relative(self.get_state(a) != b)

    def o_setState(self):
        obj = self.vw(P1)
        st = self.vb(P2)
        self.put_state(obj, st)
        self.ev(EV_OBJSTATE, [obj, st])

    def o_drawObject(self):
        obj = self.vw(P1)
        xpos = self.vw(P2)
        ypos = self.vw(P3)
        idx = self.get_object_index(obj)
        if idx == -1:
            return
        od = self.objs[idx]
        if xpos != 0xFF:
            od.walk_x += xpos * 8 - od.x
            od.x = xpos * 8
            od.walk_y += ypos * 8 - od.y
            od.y = ypos * 8
        for i in range(NUM_LOCAL_OBJECTS - 1, 0, -1):
            o = self.objs[i]
            if o.obj_nr and o.x == od.x and o.y == od.y and o.width == od.width and o.height == od.height:
                self.put_state(o.obj_nr, 0)
        self.put_state(obj, 1)
        self.ev(EV_DRAWOBJ, [obj, od.x, od.y, 1])

    def o_pickupObject(self):
        obj = self.vw(P1)
        if obj < 1:
            raise VMError(E_BADOBJ, 'pickupObject %d' % obj)
        if self.get_object_index(obj) == -1:
            return
        if self.where_is_object(obj) == WIO_INVENTORY:
            return
        self.add_object_to_inventory(obj, self.cur_room_resource())
        self.put_owner(obj, self.vars[VAR_EGO])
        self.put_class(obj, CLASS_UNTOUCHABLE, True)
        self.put_state(obj, 1)
        self.ev(EV_OBJSTATE, [obj, 1])
        self.run_inventory_script(1)

    def cur_room_resource(self):
        return self.room.num if self.room else 0

    def o_setClass(self):
        obj = self.vw(P1)
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                return
            cls = self.vw(P1)
            if cls == 0:
                self._check_obj(obj)
                self.classes[obj] = 0
                if self.obj_is_actor(obj):
                    a = self.deref_actor(obj)
                    a.ignore_boxes = False
            else:
                self.put_class(obj, cls, bool(cls & 0x80))

    def o_ifClassOfIs(self):
        obj = self.vw(P1)
        cond = True
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                break
            cls = self.vw(P1)
            b = self.get_class(obj, cls)
            if ((cls & 0x80) and not b) or (not (cls & 0x80) and b):
                cond = False
        self.jump_relative(cond)

    def o_getVerbEntrypoint(self):
        self.get_result_pos()
        a = self.vw(P1)
        b = self.vw(P2)
        self.set_result(self.get_verb_entrypoint(a, b))

    def o_findObject(self):
        self.get_result_pos()
        x = self.vb(P1)
        y = self.vb(P2)
        self.set_result(self.find_object(x, y))

    def o_findInventory(self):
        self.get_result_pos()
        x = self.vb(P1)
        y = self.vb(P2)
        self.set_result(self.find_inventory(x, y))

    def o_getInventoryCount(self):
        self.get_result_pos()
        self.set_result(self.get_inventory_count(self.vb(P1)))

    def o_setObjectName(self):
        obj = self.vw(P1)
        self.set_object_name(obj, self.read_raw_string())

    def o_getDist(self):
        self.get_result_pos()
        o1 = self.vw(P1)
        o2 = self.vw(P2)
        self.set_result(self.get_obj_act_to_obj_act_dist(o1, o2))

    def o_getClosestObjActor(self):
        self.get_result_pos()
        act = self.vw(P1)
        obj = self.vars[VAR_ACTOR_RANGE_MAX]
        closest_obj, closest_dist = 0xFF, 0xFF
        while True:
            dist = self.get_obj_act_to_obj_act_dist(act, obj)
            if dist < closest_dist:
                closest_dist, closest_obj = dist, obj
            obj -= 1
            if obj < self.vars[VAR_ACTOR_RANGE_MIN]:
                break
        self.set_result(closest_obj)

    def o_getActorX(self):
        self.get_result_pos()
        self.set_result(self.get_obj_x(self.vb(P1)))

    def o_getActorY(self):
        self.get_result_pos()
        self.set_result(self.get_obj_y(self.vb(P1)))

    def o_actorFromPos(self):
        self.get_result_pos()
        x = self.vw(P1)
        y = self.vw(P2)
        self.set_result(self.get_actor_from_pos(x, y))

    def o_getRandomNr(self):
        self.get_result_pos()
        mx = self.vb(P1)
        self.rnd = (self.rnd * 5 + 1) & 0xFFFF
        b = self.rnd >> 8
        self.set_result(b if mx >= 255 else (b * (mx + 1)) >> 8)

    # actores
    def _actor_get(self, f):
        self.get_result_pos()
        a = self.deref_actor(self.vb(P1))
        self.set_result(f(a))

    def o_getActorRoom(self):
        self.get_result_pos()
        act = self.vb(P1)
        self.set_result(self.actors[act].room if self.is_valid_actor(act) else 0)

    def o_getActorElevation(self): self._actor_get(lambda a: a.elevation)
    def o_getActorMoving(self): self._actor_get(lambda a: a.moving)
    def o_getActorFacing(self): self._actor_get(lambda a: new_to_old_dir(a.facing))
    def o_getActorCostume(self): self._actor_get(lambda a: a.costume)
    def o_getActorWidth(self): self._actor_get(lambda a: a.width)
    def o_getActorWalkBox(self): self._actor_get(lambda a: a.walkbox)
    def o_getAnimCounter(self): self._actor_get(lambda a: 0)

    def o_putActor(self):
        a = self.deref_actor(self.vb(P1))
        x = self.vw(P2)
        y = self.vw(P3)
        self.put_actor(a, x, y, a.room)

    def o_putActorAtObject(self):
        a = self.deref_actor(self.vb(P1))
        obj = self.vw(P2)
        if self.where_is_object(obj) != WIO_NOT_FOUND:
            x, y, _ = self.get_object_xy_pos(obj)
        else:
            x, y = 240, 120
        self.put_actor(a, x, y, a.room)

    def o_putActorInRoom(self):
        act = self.vb(P1)
        room = self.vb(P2)
        a = self.deref_actor(act)
        if a.visible and self.cur_room != room and self.get_talking_actor() == a.num:
            self.stop_talk()
        a.room = room & 0xFF                        # Actor::_room es un byte
        if not room:
            self.put_actor(a, 0, 0, 0)

    def o_faceActor(self):
        act = self.vb(P1)
        obj = self.vw(P2)
        a = self.deref_actor_safe(act)
        if a:
            self.face_to_object(a, obj)

    def o_animateActor(self):
        act = self.vb(P1)
        anim = self.vb(P2)
        if not self.is_valid_actor(act):
            return
        self.animate_actor(self.actors[act], anim)

    def o_walkActorTo(self):
        a = self.deref_actor(self.vb(P1))
        x = self.vw(P2)
        y = self.vw(P3)
        self.start_walk_actor(a, x, y, -1)

    def o_walkActorToObject(self):
        a = self.deref_actor(self.vb(P1))
        obj = self.vw(P2)
        if self.where_is_object(obj) != WIO_NOT_FOUND:
            x, y, d = self.get_object_xy_pos(obj)
            self.start_walk_actor(a, x, y, d)

    def o_walkActorToActor(self):
        nr = self.vb(P1)
        nr2 = self.vb(P2)
        dist = self.fetch_byte()
        if not self.is_valid_actor(nr):
            return
        a = self.actors[nr]
        if not a.in_room():
            return
        if not self.is_valid_actor(nr2):
            return
        to = self.actors[nr2]
        if not to.in_room():
            return
        if dist == 0xFF:
            dist = a.width + to.width // 2                 # _scalex = 0xFF
        x, y = to.x, to.y
        x = x + dist if x < a.x else x - dist
        x, y, _ = self.adjust_xy_to_be_in_box(a, x, y)
        self.start_walk_actor(a, x, y, -1)

    def o_isActorInBox(self):
        a = self.deref_actor(self.vb(P1))
        box = self.vb(P2)
        self.jump_relative(self.check_xy_in_box_bounds(box, a.x, a.y))

    def o_setBoxFlags(self):
        box = self.vb(P1)
        b = self.fetch_byte()
        self.set_box_flags(box, b)

    def o_actorOps(self):
        act = self.vb(P1)
        a = self.deref_actor(act)
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                return
            idx = (self.opcode & 0x1F) - 1
            if not 0 <= idx < len(DIS.ACTOROPS_CONVERT):
                raise VMError(E_BADSUB, 'actorOps %d' % (self.opcode & 0x1F))
            self.opcode = (self.opcode & 0xE0) | DIS.ACTOROPS_CONVERT[idx]
            k = self.opcode & 0x1F
            if k == 0:
                self.vb(P1)
            elif k == 1:
                self.set_actor_costume(a, self.vb(P1))
            elif k == 2:
                i = self.vb(P1) & 0xFF                  # los campos de un byte de Actor se guardan en un byte
                j = self.vb(P2) & 0xFF
                a.set_actor_walk_speed(i, j)
            elif k == 3:
                a.sound0 = self.vb(P1) & 0xFF
            elif k == 4:
                a.walk_frame = self.vb(P1) & 0xFF
            elif k == 5:
                a.talk_start = self.vb(P1) & 0xFF
                a.talk_stop = self.vb(P2) & 0xFF
            elif k == 6:
                a.stand_frame = self.vb(P1) & 0xFF
            elif k == 7:
                self.vb(P1); self.vb(P2); self.vb(P3)
            elif k == 8:
                a.init_actor(0)
            elif k == 9:
                e = self.vw(P1)
                if a.elevation != e:
                    a.elevation = e
                    a.need_redraw = True
            elif k == 10:
                a.init_frame, a.walk_frame, a.stand_frame, a.talk_start, a.talk_stop = 1, 2, 3, 4, 5
            elif k == 11:
                i = self.vb(P1)
                self.vb(P2)
                if not 0 <= i <= 31:
                    raise VMError(E_RANGE, 'actorOps palette %d' % i)
            elif k == 12:
                a.talk_color = self.vb(P1) & 0xFF
            elif k == 13:
                a.name = self.read_raw_string()
            elif k == 14:
                a.init_frame = self.vb(P1) & 0xFF
            elif k == 16:
                a.width = self.vb(P1) & 0xFF
            elif k == 17:
                self.vb(P1); self.vb(P2)
            elif k == 18:
                pass
            elif k == 19:
                self.vb(P1)
            elif k in (20, 21):
                a.ignore_boxes = not (self.opcode & 1)
                if a.in_room():
                    self.put_actor(a, a.x, a.y, a.room)
            elif k == 22:
                a.anim_speed = self.vb(P1) & 0xFF
                a.anim_progress = 0
            elif k == 23:
                self.vb(P1)
            else:
                raise VMError(E_BADSUB, 'actorOps %d' % k)

    # camara
    def o_panCameraTo(self):
        self.pan_camera_to(self.vw(P1), 0)

    def o_setCameraAt(self):
        self.set_camera_at_ex(self.vw(P1))

    def o_actorFollowCamera(self):
        self.actor_follow_camera(self.vb(P1))

    # salas
    def o_loadRoom(self):
        room = self.vb(P1)
        if room != self.cur_room:
            self.start_scene(room)

    def o_loadRoomWithEgo(self):
        obj = self.vw(P1)
        room = self.vb(P2)
        a = self.deref_actor(self.vars[VAR_EGO])
        self.put_actor(a, a.x, a.y, room)
        old_dir = a.facing
        self.ego_positioned = False
        x = self.fetch_word_signed()
        y = self.fetch_word_signed()
        self.vars[VAR_WALKTO_OBJ] = obj
        self.start_scene(a.room)
        self.vars[VAR_WALKTO_OBJ] = 0
        if self.where_is_object(obj) != WIO_ROOM:
            raise VMError(E_BADOBJ, 'loadRoomWithEgo: objeto %d no esta en la sala' % obj)
        if not self.ego_positioned:
            x2, y2, d = self.get_object_xy_pos(obj)
            self.put_actor(a, x2, y2, self.cur_room)
            if a.facing == old_dir:
                self.set_direction(a, d + 180)
        a.moving = 0
        self.cam['cur'] = self.cam['dest'] = a.x
        self.set_camera_follows(a)
        if x != -1:
            self.start_walk_actor(a, x, y, -1)

    def o_roomOps(self):
        op = self.op_byte
        a = self.vw(P1)
        b = self.vw(P2)
        self.opcode = self.fetch_byte()
        k = self.opcode & 0x1F
        args = [k, a, b]
        if k == 1:
            half = SCREEN_WIDTH // 2
            width = self.room.width if self.room else SCREEN_WIDTH
            a = max(a, half); b = max(b, half)
            a = min(a, width - half); b = min(b, width - half)
            self.vars[VAR_CAMERA_MIN_X], self.vars[VAR_CAMERA_MAX_X] = a, b
        elif k in (2, 4):
            if not 0 <= a <= 256:
                raise VMError(E_RANGE, 'roomOps color')
            if a > 15 or not 0 <= b <= 15:                     # la pantalla del Z80 tiene 16 colores: lo demas es E_RANGE (ScummVM escribiria en una tabla de 256)
                raise VMError(E_RANGE, 'roomOps color de 16')
            (self.room_pal if k == 2 else self.shadow_pal)[b] = a
            self.ev(EV_PALETTE, [])
        elif k == 3:
            self.main_top, self.main_h = a, b
        elif k in (5, 6):
            pass
        elif k == 7:
            args = [k, self.vb(P1), self.vb(P2)]
            self.opcode = self.fetch_byte()
            args += [self.vb(P1), self.vb(P2)]
            self.opcode = self.fetch_byte()
            args += [self.vb(P2)]
        elif k == 8:
            args = [k, self.vb(P1), self.vb(P2), self.vb(P3)]
        elif k == 9:
            args = [k, self.vb(P1), self.vb(P2)]
        elif k == 10:
            args = [k, self.vw(P1)]
        elif k in (11, 12):
            args = [k, self.vw(P1), self.vw(P2), self.vw(P3)]
            self.opcode = self.fetch_byte()
            args += [self.vb(P1), self.vb(P2)]
        elif k in (13, 14):
            raise VMError(E_BADSUB, 'roomOps %d: nombre de fichero no soportado' % k)
        elif k == 15:
            args = [k, self.vb(P1)]
            self.opcode = self.fetch_byte()
            args += [self.vb(P1), self.vb(P2)]
            self.opcode = self.fetch_byte()
            args += [self.vb(P1)]
        elif k == 16:
            args = [k, self.vb(P1), self.vb(P2)]
            if not 1 <= args[1] <= 16:
                raise VMError(E_RANGE, 'roomOps cycle')
        else:
            raise VMError(E_BADSUB, 'roomOps %d' % k)
        self.host(args, op)

    def o_lights(self):
        op = self.op_byte
        a = self.vb(P1)
        b = self.fetch_byte()
        c = self.fetch_byte()
        if c == 0:
            self.vars[VAR_CURRENT_LIGHTS] = a
        self.host([a, b, c], op)

    def o_oldRoomEffect(self):
        op = self.op_byte
        self.opcode = self.fetch_byte()
        args = [self.opcode & 0x1F]
        if (self.opcode & 0x1F) == 3:
            args.append(self.vw(P1))
        self.host(args, op)

    def o_drawBox(self):
        op = self.op_byte
        x = self.vw(P1)
        y = self.vw(P2)
        self.opcode = self.fetch_byte()
        x2 = self.vw(P1)
        y2 = self.vw(P2)
        c = self.vb(P3)
        self.host([x, y, x2, y2, c], op)

    def o_debug(self):
        self.vw(P1)

    def o_systemOps(self):
        sub = self.fetch_byte()
        if sub in (1, 3):
            raise Halt()
        if sub != 2:
            raise VMError(E_BADSUB, 'systemOps %d' % sub)

    def o_cursorCommand(self):
        op = self.op_byte
        self.opcode = self.fetch_byte()
        k = self.opcode & 0x1F
        args = [k]
        if k == 1:
            self.cursor_state = 1
        elif k == 2:
            self.cursor_state = 0
        elif k == 3:
            self.user_put = 1
        elif k == 4:
            self.user_put = 0
        elif k == 5:
            self.cursor_state += 1
        elif k == 6:
            self.cursor_state -= 1
        elif k == 7:
            self.user_put += 1
        elif k == 8:
            self.user_put -= 1
        elif k == 10:
            args += [self.vb(P1), self.vb(P2)]
        elif k == 11:
            args += [self.vb(P1), self.vb(P2), self.vb(P3)]
        elif k == 12:
            i = self.vb(P1)
            if not 0 <= i <= 3:
                raise VMError(E_RANGE, 'SO_CURSOR_SET %d' % i)
            args.append(i)
        elif k == 13:
            args.append(self.vb(P1))
        elif k == 14:
            args += [self.vb(P1), self.vb(P2)]
        self.host(args, op)

    # sonido
    def o_startMusic(self):
        self.start_sound(self.vb(P1))

    def o_startSound(self):
        snd = self.vb(P1)
        self.vars[VAR_MUSIC_TIMER] = 0
        self.start_sound(snd)

    def o_stopSound(self):
        self.stop_sound(self.vb(P1))

    def o_stopMusic(self):
        self.stop_all_sounds()

    def o_isSoundRunning(self):
        self.get_result_pos()
        snd = self.vb(P1)
        if snd:
            snd = self.is_sound_running(snd)
        self.set_result(snd)

    # mensajes
    def decode_parse_string(self):
        slot = {252: 3, 253: 2, 254: 1}.get(self.actor_to_print_str_for, 0)
        st = self.str_slots[slot]
        for k, v in st['default'].items():
            st[k] = v
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                d = st['default']
                for k in d:
                    d[k] = st[k]
                return
            k = self.opcode & 0xF
            if k == 0:
                st['xpos'] = self.vw(P1)
                st['ypos'] = self.vw(P2)
                st['overhead'] = False
            elif k == 1:
                st['color'] = self.vb(P1) & 0xFF         # (un byte en el Z80)
            elif k == 2:
                st['right'] = self.vw(P1)
            elif k == 4:
                st['center'] = True
                st['overhead'] = False
            elif k == 6:
                st['height'] = self.vw(P1)
            elif k == 7:
                st['overhead'] = True
            elif k == 15:
                raw = self.read_raw_string()
                self.print_string(slot, raw)
                d = st['default']
                d['xpos'], d['ypos'], d['height'], d['color'] = st['xpos'], st['ypos'], st['height'], st['color']
                return
            else:
                raise VMError(E_BADSUB, 'decodeParseString %d' % k)

    def o_print(self):
        self.actor_to_print_str_for = self.vb(P1)
        self.decode_parse_string()

    def o_printEgo(self):
        self.actor_to_print_str_for = self.vars[VAR_EGO] & 0xFF
        self.decode_parse_string()

    def o_doSentence(self):
        verb = self.vb(P1)
        if verb == 0xFE:
            self.sentence = []
            self.stop_script(self.vars[VAR_SENTENCE_SCRIPT])
            return
        a = self.vw(P2)
        b = self.vw(P3)
        self.do_sentence(verb, a, b)

    # Limites del Z80 (vmcommon3.py): NUM_STRINGS ids, STR_HEAP bytes en total y MAX_STRLEN por cadena (E_RANGE si se pasan).
    def _str_id(self, sid):
        if not 0 <= sid < NUM_STRINGS:
            raise VMError(E_RANGE, 'cadena %d fuera de 0..%d' % (sid, NUM_STRINGS - 1))
        return sid

    def _str_check(self):
        st = self.strings
        if any(len(x) > MAX_STRLEN for x in st.values()) or sum(len(x) for x in st.values()) > STR_HEAP:
            raise VMError(E_RANGE, 'monton de cadenas lleno')

    def o_stringOps(self):
        self.opcode = self.fetch_byte()
        k = self.opcode & 0x1F
        st = self.strings
        if k == 1:
            sid = self._str_id(self.vb(P1))
            st[sid] = bytearray(self.read_raw_string())
        elif k == 2:
            a = self.vb(P1)
            b = self.vb(P2)
            if a == b:
                raise VMError(E_RANGE, 'copyString a == b')
            self._str_id(a)
            st.pop(a, None)
            if b in st:
                st[a] = bytearray(st[b])
        elif k == 3:
            a = self.vb(P1)
            b = self.vb(P2)
            c = self.vb(P3)
            if a not in st:
                raise VMError(E_RANGE, 'la cadena %d no existe' % a)
            if 0 <= b < len(st[a]) + 2:
                while len(st[a]) <= b:
                    st[a].append(0)
                st[a][b] = c & 0xFF
        elif k == 4:
            self.get_result_pos()
            a = self.vb(P1)
            b = self.vb(P2)
            if a not in st:
                raise VMError(E_RANGE, 'la cadena %d no existe' % a)
            self.set_result(st[a][b] if 0 <= b < len(st[a]) else 0)
        elif k == 5:
            a = self.vb(P1)
            b = self.vb(P2)
            self._str_id(a)
            if not 0 <= b <= MAX_STRLEN:
                raise VMError(E_RANGE, 'createString %d' % b)
            st.pop(a, None)
            if b:
                st[a] = bytearray(b)
        self._str_check()

    def o_getStringWidth(self):
        self.get_result_pos()
        n = self.vb(P1)
        if n not in self.strings:
            raise VMError(E_RANGE, 'la cadena %d no existe' % n)
        self.set_result(6 * self.string_chars(self.strings[n]) + 8)      # 10g: 6 pixeles por caracter (la fuente de la interfaz) + 8 (el cursor y 2 de margen: ver gsw_scale); antes 8 por caracter

    @staticmethod
    def string_chars(s):
        """CharsetRenderer::getStringWidth (charset.cpp, version 3, arg 0): los caracteres hasta el primer 0 (o salto de linea) sin contar los '@' ni los codigos $FF / $FE;
        el modelo (y el Z80) cuentan 1 por caracter: 6 pixeles (10g; antes 8: el dialogo de guardar solo dejaba 21-22 letras). Fase 9: antes se contaban todos los bytes que no eran 0 ni $FF, aunque vinieran detras del 0 final
        (el dialogo de guardar de Indy3 mide con esto el nombre que se esta escribiendo, una cadena de 49 '@' despues de su 0: salia 392 y rechazaba cada tecla)."""
        pos, n = 0, 0
        rd = lambda k: s[k] if k < len(s) else 0
        while True:
            c = rd(pos)
            pos += 1
            if c == 0 or c in (10, 13):
                break
            if c == 64:
                continue
            if c in (255, 254):
                c = rd(pos)
                pos += 1
                if c in (3, 9, 1, 2):
                    break
                if c == 8:                                     # while (text[pos++] == ' ') {}
                    while True:
                        k = rd(pos)
                        pos += 1
                        if k != 32:
                            break
                    continue
                if c in (10, 21, 12, 13, 14):
                    pos += 2
                    continue
            if pos > len(s):
                break
            n += 1
        return n

    # verbos. Limites del Z80: NUM_VERBS ranuras (la 0 es una ranura de trabajo como en ScummVM), ids y saveid de 0 a 255, los campos
    # de un byte (color...) se guardan en un byte, y el nombre de un verbo desde una cadena (subopcode 20) no esta soportado (E_BADSUB:
    # el nombre del verbo es un puntero al texto del script y no una copia; Indy3 no lo usa)
    def _verb_id(self, v):
        if not 0 <= v <= 255:
            raise VMError(E_RANGE, 'verbo %d fuera de 0..255' % v)
        return v

    def o_verbOps(self):
        verb = self._verb_id(self.vb(P1))
        slot = self.get_verb_slot(verb, 0)
        vs = self.verbs[slot]
        vs.verbid = verb
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                break
            k = self.opcode & 0x1F
            if k == 1:
                self.vw(P1)
                if slot:
                    vs.type = 1
            elif k == 2:
                vs.name = self.read_raw_string()
                vs.type = 0
                vs.imgindex = 0
            elif k == 3:
                vs.color = self.vb(P1) & 0xFF
            elif k == 4:
                vs.hicolor = self.vb(P1) & 0xFF
            elif k == 5:
                vs.left = self.vw(P1)
                vs.top = self.vw(P2)
            elif k == 6:
                vs.curmode = 1
            elif k == 7:
                vs.curmode = 0
            elif k == 8:
                self.kill_verb(slot)
            elif k == 9:
                slot = self.get_verb_slot(verb, 0)
                if slot == 0:
                    for slot in range(1, NUM_VERBS):
                        if self.verbs[slot].verbid == 0:
                            break
                    else:
                        raise VMError(E_RANGE, 'demasiados verbos')
                vs = self.verbs[slot]
                vs.verbid = verb
                vs.color, vs.hicolor, vs.dimcolor = 2, 14, 8
                vs.type, vs.curmode, vs.saveid, vs.key, vs.center, vs.imgindex = 0, 0, 0, 0, 0, 0
                vs.name = b''
            elif k == 16:
                vs.dimcolor = self.vb(P1) & 0xFF
            elif k == 17:
                vs.curmode = 2
            elif k == 18:
                vs.key = self.vb(P1) & 0xFF
            elif k == 19:
                vs.center = 1
            elif k == 20:
                raise VMError(E_BADSUB, 'verbOps 20: nombre desde una cadena no soportado')
            elif k == 22:
                a = self.vw(P1)
                self.vb(P2)
                if slot and vs.imgindex != a:
                    vs.type = 1
                    vs.imgindex = a
            elif k == 23:
                vs.bkcolor = self.vb(P1) & 0xFF
            else:
                raise VMError(E_BADSUB, 'verbOps %d' % k)
        self.draw_verb(slot)
        self.ev(EV_VERB, [vs.verbid, vs.curmode])

    def o_saveRestoreVerbs(self):
        self.opcode = self.fetch_byte()
        sub = self.opcode
        a = self.vb(P1)
        b = self.vb(P2)
        c = self.vb(P3)
        if sub in (1, 2, 3) and not (0 <= a <= 255 and 0 <= b <= 255 and 0 <= c <= 255):
            raise VMError(E_RANGE, 'saveRestoreVerbs fuera de 0..255')
        if sub == 1:
            while a <= b:
                slot = self.get_verb_slot(a, 0)
                if slot and self.verbs[slot].saveid == 0:
                    self.verbs[slot].saveid = c
                a += 1
        elif sub == 2:
            while a <= b:
                slot = self.get_verb_slot(a, c)
                if slot:
                    slot2 = self.get_verb_slot(a, 0)
                    if slot2:
                        self.kill_verb(slot2)
                    slot = self.get_verb_slot(a, c)
                    self.verbs[slot].saveid = 0
                    self.draw_verb(slot)
                a += 1
        elif sub == 3:
            while a <= b:
                slot = self.get_verb_slot(a, c)
                if slot:
                    self.kill_verb(slot)
                a += 1
        else:
            raise VMError(E_BADSUB, 'saveRestoreVerbs %d' % sub)

    # guardar y cargar
    def o_saveLoadVars(self):
        op = self.op_byte
        saving = self.fetch_byte() == 1
        args = [1 if saving else 0]
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0:
                break
            k = self.opcode & 0x1F
            if k == 1:
                self.get_result_pos()
                self.get_result_pos()
            elif k == 2:
                a = self.vb(P1)
                b = self.vb(P2)
                args += [a, b]
                if not saving and not (a == 9 and b == 9):
                    self.load_save_names(a, b)
            elif k == 3:
                self.read_raw_string()
            elif k == 4 or k == 0x1F:
                break
        self.host(args, op)

    def o_saveLoadGame(self):
        op = self.op_byte
        self.get_result_pos()
        a = self.vb(P1)
        sub = a & 0xE0
        res = {0x00: 100, 0x20: 3, 0x40: 5, 0x80: 0, 0xC0: 7}.get(sub)
        if res is None:
            raise VMError(E_BADSUB, 'saveLoadGame %d' % sub)
        if self.real_saves:                                        # fase 9: partidas de verdad (sl_main del Z80, overlay C)
            res = self.save_load_game(a)
        else:
            self.host([a], op)
        self.set_result(res)

    # ---- fase 9: guardar y cargar (ScummEngine_v4::o4_saveLoadGame, ScummEngine::saveState / loadState; el Z80: ovc9.asm)
    # Que se guarda: todo el estado de la VM (variables, ranuras, locales, objetos, inventario, actores, verbos, cadenas, camara, mensaje,
    # frases, paletas, cajas y sala en uso, el reproductor de sonido y su temporizador). Lo que NO: el fotograma, los sucesos de entrada
    # y el raton, el resultado en curso (_resultVarNumber), la pila de expression, las ordenes de sonido ni lo que sea del anfitrion.
    # fase 9: la ventana movil del programa (el ZX81 ensena 256 de los 320 pixeles de SCUMM): no es estado de la partida
    def start_scene(self, room):
        """10f: el Z80 llama a ov_clear al cambiar de sala (scumm.asm evh_room), que apaga la ventana movil (pan_on, pan_px); el modelo la dejaba corrida y el clic siguiente
        del segundo dialogo de guardar caia 64 pixeles a la derecha (objeto 168 en vez del 167)."""
        GameMixin.start_scene(self, room)
        self.pan_on = False
        self.pan_px = 0

    def pan_event(self, px):
        if px >= 232:
            self.pan_on = True
        elif px < 100:
            self.pan_on = False

    def update_pan_px(self):
        """cam_update: lo que esta corrida la ventana = min(64, borde izquierdo maximo - borde izquierdo de SCUMM) si pan_on."""
        w = self.room.width if self.room else 0
        maxleft = max(0, (w // 8 - 32) * 8)
        left = min(max(0, self.cam['cur'] - 160), maxleft)
        self.pan_px = min(64, maxleft - left) if self.pan_on else 0

    SAVE_SKIP = frozenset(['pan_on', 'pan_px', 'w', 'seed', 'protection', 'soundcard', 'sound_mode', 'trace', 'snd_log', 'at_events', 'saves', 'real_saves',
                           'frame', 'insn', 'max_slots', 'pending', 'mouse', 'vmouse', 'res', 'op_byte', 'opcode', 'room', 'stack',
                           'code', 'ptr', 'in92'])
    SAVE_NAME_BASE = 9                                              # STRINGID_SAVENAME1 (10) + slot - 1: el nombre de la partida de la ranura es la cadena 9 + ranura
    SAVE_NAME_MAX = 31                                              # strlcpy(name, ptr, 32)

    def save_name(self, slot):
        sid = self.SAVE_NAME_BASE + slot
        s = self.strings.get(sid)
        if sid >= NUM_STRINGS or not s:
            return b''
        out = bytearray()
        for c in s[:self.SAVE_NAME_MAX]:
            if c == 0:
                break
            out.append(c)
        return bytes(out)

    def save_game(self, slot):
        """saveState: el puntero del script en marcha va a su ranura (al cargar sigue justo despues de este opcode)."""
        self.update_script_ptr()
        memo = {id(self): self, id(self.w): self.w}                    # los actores llevan una referencia a la VM: que no se copie
        snap = {k: copy.deepcopy(v, memo) for k, v in self.__dict__.items() if k not in self.SAVE_SKIP}
        self.saves[slot] = (self.save_name(slot), snap)

    def load_game(self, slot):
        """loadState: el estado vuelve a como estaba; el script que estaba en marcha sigue por su ranura; el sonido para y vuelve a empezar el que sonaba."""
        name, snap = self.saves[slot]
        in_script, ptr_now = self.cur != 0xFF, self.ptr                # 10a: el puntero del script que carga, justo despues del opcode
        memo = {id(self): self, id(self.w): self.w}
        for k, v in snap.items():
            setattr(self, k, copy.deepcopy(v, memo))
        self.room = self.w.rooms.get(self.cur_room)
        if self.cur != 0xFF:
            # 10a: o4_saveLoadGame acaba con updateScriptPtr / getScriptBaseAddress / resetScriptPointer y loadState no toca _scriptPointer: el script en marcha
            # (la ranura _currentScript RESTAURADA) sigue justo despues del opcode de CARGAR, no del de guardar (asi se quedaba en un bucle el dialogo de Indy3).
            # Cargando desde el bucle principal (DBG_SAVE, sin script en marcha) la ranura sigue por donde la dejo el guardado, como antes.
            if in_script:
                self.slots[self.cur].offs = ptr_now
            self.load(self.cur)
        self.snd_log.append('SND f=%d STOP' % self.frame)               # sd_stopvgm; si sonaba algo, vuelve a empezar (sc_nt: STOP, LOOP, PLAY)
        cur = self.snd_cur
        if cur:
            info = self.snd_info(cur['nr'])
            self.snd_log += ['SND f=%d STOP' % self.frame, 'SND f=%d LOOP %d' % (self.frame, info[3] if info else 0),
                             'SND f=%d PLAY DATA/SND/SOUND%03d.VGM' % (self.frame, cur['nr'])]

    def save_load_game(self, a):
        slot, sub = a & 0x1F, a & 0xE0
        if sub == 0x00:
            return 100
        if sub == 0x20:
            return 3
        if sub == 0x80:
            if os.environ.get('TS_WRFAIL'):                     # 10e (pruebas): la SD rechaza las escrituras: saveState falla (2) y la partida no queda
                return 2
            self.save_game(slot)
            return 0
        if sub == 0x40:
            if slot not in self.saves:
                return 5
            self.load_game(slot)
            return 3
        return 6 if slot in self.saves else 7                          # 0xC0

    def load_save_names(self, a, b):
        """loadVars 2: las cadenas a..b reciben los nombres de las partidas 1.. (las que existen); el resto, vacias. En modo mock solo se vacian."""
        for sid in range(a, b + 1):
            s = self.strings.get(sid)
            if not s:
                continue
            slot = sid - a + 1
            if self.real_saves and slot in self.saves:
                nm = self.saves[slot][0]
                n = min(len(nm), len(s) - 2) if len(s) >= 2 else 0
                for i in range(n):
                    c = nm[i]
                    s[i] = c if 32 <= c <= 122 and c != 64 else 0x5F    # '_' como ScummVM (los caracteres especiales)
                s[n] = 0
            else:
                s[0] = 0

    # =========================================================================================== bucle principal
    def update_scumm_vars(self):
        v = self.vars
        v[VAR_CAMERA_POS_X] = s16(self.cam['cur'])
        v[VAR_HAVE_MSG] = self.have_msg
        v[VAR_VIRT_MOUSE_X] = s16(self.vmouse[0])
        v[VAR_VIRT_MOUSE_Y] = s16(self.vmouse[1])
        v[VAR_MOUSE_X] = s16(self.mouse[0])
        v[VAR_MOUSE_Y] = s16(self.mouse[1])

    def step_frame(self, delta):
        """ScummEngine::scummLoop (version 3)."""
        v = self.vars
        v[VAR_TIMER] = delta
        v[VAR_TIMER_TOTAL] = s16(v[VAR_TIMER_TOTAL] + delta)
        for i in (VAR_TMR_1, VAR_TMR_2, VAR_TMR_3) + VARS_INDY3_TIMERS:
            v[i] = s16(v[i] + delta)
        real = delta
        if delta > 15:
            delta = 15
        self.decrease_script_delay(delta)
        self.talk_delay = max(0, self.talk_delay - delta)
        self.display_dialog()
        self.process_input()
        self.update_scumm_vars()
        self.update_music_timer(real)
        self.run_all_scripts()
        self.check_exec_verbs()
        self.check_and_run_sentence_script()
        if self.cur_room != 0:
            self.walk_actors()
            self.move_camera()
            self.update_object_states()
        self.cam['last'] = self.cam['cur']

    # ---- resumen para la traza
    def digest(self):
        v = crc16(b''.join(struct.pack('<H', x & 0xFFFF) for x in self.vars))
        sl = []
        for i, s in enumerate(self.slots):
            if s.status != SS_DEAD:
                t = '%d:%d:%d:%d:%d' % (i, s.status, s.where, s.number, s.offs - s.base)
                if s.status & 0x7F == SS_PAUSED:
                    t += ':%d' % (s.delay & 0xFFFFFFFF)
                if s.freeze_count:
                    t += ':f%d' % s.freeze_count
                if s.cutscene_override:
                    t += ':c%d' % s.cutscene_override
                sl.append(t)
        return 'D f=%d V=%04X %s S=%s' % (self.frame, v, self.game_digest(), ' '.join(sl))


# ------------------------------------------------------------------------------------------------ escenarios
def run_scenario(world, lines, protection=True, soundcard=0):
    """Ejecuta un escenario (lista de ordenes) y devuelve (traza, vm)."""
    vm = VM(world, seed=0, protection=protection)
    out = []
    for ln in lines:
        p = ln.split()
        cmd = p[0]
        try:
            if cmd == 'INIT':
                vm.reset()
            elif cmd == 'OPT':
                if p[1] == 'proteccion':
                    vm.protection = bool(int(p[2]))
                elif p[1] == 'sonido':
                    vm.sound_mode = p[2]
            elif cmd == 'SETVAR':
                vm.vars[int(p[1])] = s16(int(p[2]))
            elif cmd == 'PSEUDO':
                vm.resource_mapper[int(p[1])] = int(p[2])
            elif cmd == 'STRING':
                vm.strings[int(p[1])] = bytearray(bytes.fromhex(p[2]))
            elif cmd == 'OWNER':
                vm.owner[int(p[1])] = int(p[2])
            elif cmd == 'STATE':
                vm.gstate[int(p[1])] = int(p[2])
            elif cmd == 'CLASS':
                vm.classes[int(p[1])] = int(p[2], 16)
            elif cmd == 'SCRIPT':
                vm.cur = 0xFF
                vm.run_script(int(p[1]), False, False, [int(x) for x in p[2:]])
            elif cmd == 'LOADROOM':
                if int(p[1]) != vm.cur_room:
                    vm.cur = 0xFF
                    vm.start_scene(int(p[1]))
            elif cmd in ('ENTRY', 'EXIT'):
                r = world.rooms[int(p[1])]
                if cmd == 'ENTRY' and r.encd_off:
                    vm.start_slot(SCRIPT_NUM_ENCD, WIO_ROOM, r.file, r.encd_off)
                elif cmd == 'EXIT' and r.excd_off:
                    vm.start_slot(SCRIPT_NUM_EXCD, WIO_ROOM, r.file, r.excd_off)
            elif cmd == 'OBJ':
                vm.cur = 0xFF
                vm.run_object_script(int(p[1]), int(p[2]))
            elif cmd == 'INPUT':
                vm.cur = 0xFF
                vm.run_input_script(int(p[1]), int(p[2]), int(p[3]) if len(p) > 3 else 0)
            elif cmd == 'CLICK':
                vm.pending.append(('click', int(p[1]), int(p[2])))
            elif cmd == 'RCLICK':
                vm.pending.append(('rclick',))
            elif cmd == 'KEY':
                vm.pending.append(('key', int(p[1])))
            elif cmd == 'ESC':
                vm.pending.append(('esc',))
            elif cmd == 'SENTENCE':
                vm.do_sentence(int(p[1]), int(p[2]), int(p[3]))
            elif cmd == 'ACTOR':
                a = vm.deref_actor(int(p[1]))
                a.room = int(p[2])
                vm.set_actor_costume(a, int(p[5]))
                vm.put_actor(a, int(p[3]), int(p[4]), int(p[2]))
            elif cmd == 'FRAMES':
                delta, n = int(p[1]), int(p[2])
                for _ in range(n):
                    vm.frame += 1
                    protection_hook(vm)
                    vm.step_frame(delta)
                    vm.trace.append(vm.digest())
            else:
                raise ValueError(ln)
        except VMError as e:
            vm.trace.append('ERR %d' % e.code)
            out += vm.trace
            return out, vm
        except Halt:
            vm.trace.append('ERR 99')
            out += vm.trace
            return out, vm
        out += vm.trace
        vm.trace = []
        if cmd in ('SCRIPT', 'ENTRY', 'EXIT', 'OBJ', 'LOADROOM', 'INPUT', 'SENTENCE', 'ACTOR'):
            out.append(vm.digest())
    return out, vm


def protection_hook(vm):
    """Proteccion anticopia (sala 92): sin ella (protection = False), Var[57] = 1 a los 30 fotogramas, que es lo que
    pone el script local 204 al acertar los cuatro simbolos."""
    if vm.cur_room == 92:
        vm.in92 += 1
        if not vm.protection and vm.in92 > 30:
            vm.vars[57] = 1
    else:
        vm.in92 = 0


_SNAPSHOTS = {}
# variables que apuntan a scripts o fijan el reloj del juego: no se tocan al azar
NO_RANDOM_VARS = set(range(24, 39)) | {VAR_ROOM, VAR_EGO, VAR_TIMER, VAR_TIMER_TOTAL, VAR_TIMER_NEXT, VAR_CAMERA_MIN_X,
                                       VAR_CAMERA_MAX_X, VAR_MUSIC_TIMER, VAR_ACTOR_RANGE_MIN, VAR_ACTOR_RANGE_MAX}


def boot_snapshot(world):
    """Ordenes de escenario (SETVAR, PSEUDO, STRING, OWNER, STATE, CLASS, ACTOR) que dejan el estado que tiene el juego
    justo despues de arrancar y llegar al pasillo (sala 1): sin ese estado, los scripts de sala fallan porque faltan
    cadenas, actores o variables que pone el script de arranque. Se calcula con run_boot (semilla 1, sin proteccion)."""
    key = id(world)
    if key in _SNAPSHOTS:
        return _SNAPSHOTS[key]
    vm, first = run_boot(world, 1500, 1)
    if 1 not in first:
        raise RuntimeError('el arranque no llega a la sala 1')
    lines = []
    for v, val in enumerate(vm.vars):
        if val and v not in (VAR_ROOM, VAR_ROOM_RESOURCE, VAR_HAVE_MSG, VAR_TIMER, VAR_TIMER_TOTAL, VAR_CAMERA_POS_X,
                             VAR_VIRT_MOUSE_X, VAR_VIRT_MOUSE_Y, VAR_MOUSE_X, VAR_MOUSE_Y, VAR_TALK_ACTOR, VAR_LAST_SOUND,
                             VAR_OVERRIDE, VAR_MUSIC_TIMER, VAR_TIMER_NEXT):
            lines.append('SETVAR %d %d' % (v, val))
    for k, v in sorted(vm.resource_mapper.items()):
        lines.append('PSEUDO %d %d' % (k, v))
    for k, v in sorted(vm.strings.items()):
        lines.append('STRING %d %s' % (k, bytes(v).hex()))
    for i in range(len(vm.owner)):
        if vm.owner[i] != world.owner[i]:
            lines.append('OWNER %d %d' % (i, vm.owner[i]))
        if vm.gstate[i] != world.state[i]:
            lines.append('STATE %d %d' % (i, vm.gstate[i]))
        if vm.classes[i] != world.classes[i]:
            lines.append('CLASS %d %06X' % (i, vm.classes[i] & 0xFFFFFF))
    for a in vm.actors[1:]:
        if a.costume:
            lines.append('ACTOR %d %d %d %d %d' % (a.num, a.room, a.x, a.y, a.costume))
    _SNAPSHOTS[key] = lines
    return lines


def init_lines(rng, world, nvars=NUM_VARS):
    """INIT + el estado de despues del arranque + unas pocas variables cambiadas al azar."""
    lines = ['INIT', 'OPT proteccion 0'] + boot_snapshot(world)
    for v in range(nvars):
        if v not in NO_RANDOM_VARS and rng.random() < 0.02:
            lines.append('SETVAR %d %d' % (v, rng.choice([0, 1, 1, 2, 3, 4, 5, 8, 10, 15, 255])))
    return lines


def make_scenarios(world, seeds=1, rooms=None, limit_objs=None, scripts=True):
    """Escenarios: cada sala (entrada, fotogramas, salida), cada verbo de cada objeto, scripts globales y locales, y
    clics, teclas y frases en cada sala. Son reproducibles: misma semilla, misma lista."""
    sc = []
    rlist = sorted(world.rooms) if rooms is None else [r for r in rooms if r in world.rooms]
    for seed in range(seeds):
        rng = random.Random(3000 + seed)
        for rn in rlist:
            r = world.rooms[rn]
            ln = init_lines(rng, world) + ['LOADROOM %d' % rn, 'FRAMES 4 30', 'LOADROOM 0', 'FRAMES 4 10']
            sc.append(('room%02d.s%d' % (rn, seed), ln))
            for sid, _ in r.local_scripts:
                sc.append(('loc%02d.%d.s%d' % (rn, sid, seed),
                           init_lines(rng, world) + ['LOADROOM %d' % rn, 'SCRIPT %d' % sid, 'FRAMES 3 25']))
            objs = r.objects if limit_objs is None else r.objects[:limit_objs]
            for o in objs:
                for verb, _ in o.verbs:
                    sc.append(('obj%03d.v%02X.s%d' % (o.id, verb, seed),
                               init_lines(rng, world) + ['LOADROOM %d' % rn, 'OBJ %d %d' % (o.id, verb), 'FRAMES 3 25']))
            # entrada: clic en un objeto de la sala, clic en el suelo, tecla, ESC, boton derecho y frase directa
            base = init_lines(rng, world) + ['LOADROOM %d' % rn]
            if r.objects:
                o = rng.choice(r.objects)
                cx = min(319, max(0, o.x + o.width // 2))
                cy = min(199, o.y + o.height // 2 + 16)
                sc.append(('clk%02d.o.s%d' % (rn, seed), base + ['CLICK %d %d' % (cx, cy), 'FRAMES 4 40']))
                other = rng.choice(r.objects).id
                sc.append(('snt%02d.s%d' % (rn, seed), base + ['SENTENCE %d %d %d' % (rng.choice([1, 2, 3, 4, 7, 13]), o.id, other),
                                                              'FRAMES 4 40']))
            sc.append(('clk%02d.g.s%d' % (rn, seed), base + ['CLICK %d %d' % (rng.randrange(320), rng.randrange(16, 150)),
                                                            'FRAMES 4 40']))
            sc.append(('key%02d.s%d' % (rn, seed), base + ['KEY %d' % rng.choice([32, 46, 97, 111, 112, 13, 65]), 'FRAMES 4 20']))
            sc.append(('esc%02d.s%d' % (rn, seed), base + ['SETVAR %d 27' % VAR_CUTSCENEEXIT_KEY, 'ESC', 'FRAMES 4 20',
                                                          'RCLICK', 'FRAMES 4 20']))
        for sid in (sorted(world.scripts) if scripts else ()):
            sc.append(('scr%03d.s%d' % (sid, seed), init_lines(rng, world) + ['SCRIPT %d' % sid, 'FRAMES 3 25']))
    return sc


# ------------------------------------------------------------------------------------------------ modo nucleo (fase 3)
# El Z80 de la fase 3 solo tiene el nucleo de la VM (control, variables, scripts, locales, retardos, cutscene/override, freeze,
# expression). CoreVM es el modelo con esa misma frontera: los opcodes de CORE_OPS van como en VM y los demas salen al anfitrion
# como la linea 'H oo [args]', con los operandos leidos por scumm3dis.run_spec (la misma SPEC que el decodificador generico del
# Z80) y el resultado y el salto simulados:
#   args   los valores en el orden de lectura, en 16 bits sin signo (subopcodes incluidos; R da el numero de variable ya resuelto;
#          una cadena da str_value de sus bytes en bruto sin el 0 final; J no da argumento); mas de MAX_ARGS: E_RANGE
#   s = mock_hash(opcode, args, fotograma); si la SPEC empieza por R, la variable recibe s & 0xFF; si lleva J, salta cuando
#          el bit 8 de s es 0 (la condicion es falsa)
# Fotograma: VAR_TIMER y temporizadores, decreaseScriptDelay(min(delta, 15)) y runAllScripts; nada mas.
# Resumen: D f=.. V=crc(256 variables) L=crc(locales de las NUM_SLOT ranuras) K=cut_sp,crc(datos y ranuras de la pila de
# cutscenes) S=ranuras vivas (como VM.digest, con los offsets desde el inicio del bloque de codigo).
# Ordenes de escenario: INIT, OPT (se ignora), SETVAR v n, ROOM n [1] (sala en uso con sus objetos y, con el 1, sus cajas: sin startScene),
# SCRIPT n [args], ENTRY n / EXIT n, OBJ obj verbo (runObjectScript sin buscar el objeto en la sala: el OBCD del indice),
# ABORT (abortCutscene), FRAMES delta n y, desde la fase 5, LOADROOM n (loadRoom desde fuera de un script), SENTENCE verbo a b (doSentence),
# PSEUDO clave sala (pseudoRoom) y ACTORSET n sala x y traje visible [ignoreBoxes].
# Fase 6 (caminata): el fotograma acaba con walkActors (si hay sala en uso) y el resumen lleva G= con cada actor de la sala en uso
# (n:x,y,caja,moving separados por ';', o '-'): la traza de posiciones fotograma a fotograma. Los "clics" de los escenarios cwlk son
# walkActorTo del ego (lo que hace el script de verbos con un clic en la sala; la entrada de verdad es de la fase 7).
CORE_OPS = {
    'stopObjectCode', 'breakHere', 'endCutscene', 'cutscene', 'beginOverride', 'wait', 'delay', 'delayVariable',
    'jumpRelative', 'equalZero', 'notEqualZero', 'isEqual', 'isNotEqual', 'isGreater', 'isGreaterEqual', 'isLess',
    'isLessEqual', 'move', 'add', 'subtract', 'multiply', 'divide', 'and', 'or', 'increment', 'decrement', 'setVarRange',
    'expression', 'startScript', 'chainScript', 'stopScript', 'stopObjectScript', 'freezeScripts', 'isScriptRunning',
    'getRandomNr', 'debug',
    # fase 4a, grupo 1: sonido
    'startSound', 'startMusic', 'stopSound', 'stopMusic', 'isSoundRunning',
    # grupo 2: objetos; grupo 3: camara
    'getObjectOwner', 'setOwnerOf', 'setObjectName',
    'setCameraAt', 'panCameraTo', 'actorFollowCamera',
    # grupo 4: actores sin caminar (findObject se queda en el anfitrion: necesita los objetos de la sala, fase 5)
    'putActor', 'putActorInRoom', 'putActorAtObject', 'getActorRoom', 'getActorX', 'getActorY', 'getActorElevation',
    'getActorMoving', 'getActorFacing', 'getActorCostume', 'getActorWalkBox', 'animateActor', 'faceActor',
    'actorFromPos', 'getClosestObjActor', 'getDist',
    # fase 4b-1 (se anaden por grupos): estados y clases
    'setState', 'ifState', 'ifNotState', 'setClass', 'ifClassOfIs',
    'findInventory', 'getInventoryCount', 'getActorWidth',
    'stringOps', 'getStringWidth',
    'cursorCommand', 'verbOps', 'saveRestoreVerbs',
    'actorOps',
    'roomOps', 'resourceRoutines', 'lights', 'oldRoomEffect', 'drawBox', 'systemOps', 'saveLoadVars', 'saveLoadGame',
    # fase 4b-2: mensajes
    'print', 'printEgo',
    # fase 5: salas, objetos y frases
    'loadRoom', 'loadRoomWithEgo', 'pseudoRoom', 'startObject', 'getVerbEntrypoint', 'drawObject', 'pickupObject', 'findObject',
    'isActorInBox', 'setBoxFlags', 'doSentence', 'waitForSentence',
    # fase 6: caminata
    'walkActorTo', 'walkActorToObject', 'walkActorToActor', 'waitForActor',
}


class _SpecReader:
    """Lector de scumm3dis.run_spec sobre la VM (valores de verdad)."""

    def __init__(self, vm):
        self.vm = vm

    @property
    def opcode(self):
        return self.vm.opcode

    @opcode.setter
    def opcode(self, v):
        self.vm.opcode = v

    def byte(self):
        return self.vm.fetch_byte()

    def word(self):
        return self.vm.fetch_word()

    def sword(self):
        return self.vm.fetch_word_signed()

    def var(self):
        return self.vm.get_var()

    def result(self):
        self.vm.get_result_pos()
        return self.vm.res

    def string(self):
        return self.vm.read_raw_string()[:-1]

    def expr(self):
        raise VMError(E_BADOP, 'expression no va al anfitrion')

    def bad(self, k):
        raise VMError(E_BADSUB, 'subopcode %d' % k)


class CoreVM(VM):
    def execute(self, op):
        self.op_byte = op
        name = DIS.NAMES[op]
        if name in CORE_OPS:
            return VM.execute(self, op)
        self.opcode = op
        args, res, jump = DIS.run_spec(name, _SpecReader(self))
        vals = [str_value(a) if isinstance(a, bytes) else a & 0xFFFF for a in args]
        if len(vals) > MAX_ARGS:
            raise VMError(E_RANGE, 'demasiados argumentos')
        s = mock_hash(op, vals, self.frame)
        self.trace.append('H %02X [%s]' % (op, ','.join(str(v) for v in vals)))
        if res is not None:
            self.write_var(res, s & 0xFF)
        if jump is not None and not (s >> 8) & 1:
            self.ptr += jump

    # ---- fase 5: lo que el Z80 hace distinto (V3/FASE3.md, "Fase 5"). La caminata (fase 6) ya es la de GameMixin
    def obcd_of(self, obj):
        """(codigo, offset) del OBCD del objeto: el del indice de DATA.BIN (ODIR), tanto del inventario como de la sala (en Indy3 ningun
        objeto esta en dos salas: pack_data3 lo comprueba). El Z80 no copia el OBCD al inventario."""
        if obj in self.inventory or (self.get_object_index(obj) >= 0 and self.owner[obj] == OWNER_ROOM):
            e = self.w.objects.get(obj)
            if e is not None:
                return e[1].block, 0
        return None

    def get_obcd_offs(self, obj):
        return 0

    def add_object_to_inventory(self, obj, room):
        for slot in range(NUM_INVENTORY):
            if self.inventory[slot] == 0:
                self.inventory[slot] = obj
                return
        raise VMError(E_RANGE, 'inventario lleno')

    def find_object(self, x, y):
        """findObject (v3). El estado de un padre se lee vivo (OBJST), no la copia de objs[].state que ScummVM refresca en cada fotograma:
        el Z80 no tiene esa copia. Solo difiere si se cambia el estado y se llama a findObject en el mismo fotograma."""
        for i in range(1, NUM_LOCAL_OBJECTS):
            o = self.objs[i]
            if o.obj_nr < 1 or self.get_class(o.obj_nr, CLASS_UNTOUCHABLE):
                continue
            b = i
            while True:
                a = self.objs[b].parentstate
                b = self.objs[b].parent
                if b == 0:
                    if o.x <= x < o.x + o.width and o.y <= y < o.y + o.height:
                        return o.obj_nr
                    break
                if b >= NUM_LOCAL_OBJECTS:
                    break
                po = self.objs[b]
                if ((self.gstate[po.obj_nr] if po.obj_nr else 0) & 0xF) != a:
                    break
        return 0

    def o_findObject(self):
        self.get_result_pos()
        x = self.vb(P1)
        y = self.vb(P2)
        self.set_result(self.find_object(x, y))

    def o_drawObject(self):
        obj = self.vw(P1)
        xpos = self.vw(P2)
        ypos = self.vw(P3)
        idx = self.get_object_index(obj)
        if idx == -1:
            return
        od = self.objs[idx]
        if xpos != 0xFF:
            if not (0 <= xpos <= 255 and 0 <= ypos <= 255):         # el Z80 guarda x/8 e y/8 en un byte
                raise VMError(E_RANGE, 'drawObject en %d, %d' % (xpos, ypos))
            od.walk_x = s16(od.walk_x + xpos * 8 - od.x)
            od.x = xpos * 8
            od.walk_y = s16(od.walk_y + ypos * 8 - od.y)
            od.y = ypos * 8
        for i in range(NUM_LOCAL_OBJECTS - 1, 0, -1):
            o = self.objs[i]
            if o.obj_nr and o.x == od.x and o.y == od.y and o.width == od.width and o.height == od.height:
                self.put_state(o.obj_nr, 0)
        self.put_state(obj, 1)
        self.ev(EV_DRAWOBJ, [obj, od.x, od.y, 1])

    def o_loadRoom(self):
        room = self.vb(P1)
        if not 0 <= room <= 255:                                     # el Z80 trabaja con la sala en un byte
            raise VMError(E_RANGE, 'loadRoom %d' % room)
        if room != self.cur_room:
            self.start_scene(room)

    def o_loadRoomWithEgo(self):
        obj = self.vw(P1)
        room = self.vb(P2)
        if not 0 <= room <= 255:
            raise VMError(E_RANGE, 'loadRoomWithEgo %d' % room)
        a = self.deref_actor(self.vars[VAR_EGO])
        self.put_actor(a, a.x, a.y, room)
        old_dir = a.facing
        self.ego_positioned = False
        x = self.fetch_word_signed()
        y = self.fetch_word_signed()
        self.vars[VAR_WALKTO_OBJ] = obj
        self.start_scene(a.room)
        self.vars[VAR_WALKTO_OBJ] = 0
        if self.where_is_object(obj) != WIO_ROOM:
            raise VMError(E_BADOBJ, 'loadRoomWithEgo: objeto %d no esta en la sala' % obj)
        if not self.ego_positioned:
            x2, y2, d = self.get_object_xy_pos(obj)
            self.put_actor(a, x2, y2, self.cur_room)
            if a.facing == old_dir:
                self.set_direction(a, d + 180)
        a.moving = 0
        self.cam['cur'] = self.cam['dest'] = a.x
        self.set_camera_follows(a)
        if x != -1:
            self.start_walk_actor(a, x, y, -1)

    def o_doSentence(self):
        verb = self.vb(P1)
        if verb == 0xFE:
            self.sentence = []
            self.stop_script(self.vars[VAR_SENTENCE_SCRIPT])
            return
        if not 0 <= verb <= 255:                                     # el Z80 guarda el verbo en un byte
            raise VMError(E_RANGE, 'doSentence verbo %d' % verb)
        a = self.vw(P2)
        b = self.vw(P3)
        self.do_sentence(verb, a, b)

    def o_pseudoRoom(self):
        i = self.fetch_byte()
        while True:
            j = self.fetch_byte()
            if j == 0:
                break
            if j >= 0x80:
                if i == 0:                                           # el Z80 usa 0 como "sin sala asignada"
                    raise VMError(E_RANGE, 'pseudoRoom 0')
                self.resource_mapper[j & 0x7F] = i

    def o_systemOps(self):
        sub = self.fetch_byte()
        if sub in (1, 3):
            raise VMError(E_HALT, 'systemOps %d' % sub)
        if sub != 2:
            raise VMError(E_BADSUB, 'systemOps %d' % sub)

    def o_expression(self):
        # como VM.o_expression, con la pila limitada a MAX_ESTACK (el Z80 la tiene de ese tamano)
        self.stack = []
        self.get_result_pos()
        dst = self.res

        def pop():
            if not self.stack:
                raise VMError(E_RANGE, 'pila vacia')
            return self.stack.pop()

        def push(v):
            if len(self.stack) >= MAX_ESTACK:
                raise VMError(E_RANGE, 'pila llena')
            self.stack.append(v)
        while True:
            self.opcode = self.fetch_byte()
            if self.opcode == 0xFF:
                break
            k = self.opcode & 0x1F
            if k == 1:
                push(self.vw(P1))
            elif k == 2:
                i = pop()
                push(wrap32(i + pop()))
            elif k == 3:
                i = pop()
                push(wrap32(pop() - i))
            elif k == 4:
                i = pop()
                push(wrap32(i * pop()))
            elif k == 5:
                i = pop()
                if i == 0:
                    raise VMError(E_RANGE, 'division por cero')
                push(wrap32(cdiv(pop(), i)))
            elif k == 6:
                self.opcode = self.fetch_byte()
                self.execute(self.opcode)
                push(self.vars[0])
            else:
                raise VMError(E_BADSUB, 'expression %d' % k)
        self.res = dst
        self.set_result(pop())

    def step_frame(self, delta):
        v = self.vars
        v[VAR_TIMER] = delta
        v[VAR_TIMER_TOTAL] = s16(v[VAR_TIMER_TOTAL] + delta)
        for i in (VAR_TMR_1, VAR_TMR_2, VAR_TMR_3) + VARS_INDY3_TIMERS:
            v[i] = s16(v[i] + delta)
        real = delta
        if delta > 15:
            delta = 15
        self.decrease_script_delay(delta)
        self.talk_delay = max(0, self.talk_delay - delta)       # fase 4b-2: mensajes (como VM.step_frame)
        self.display_dialog()
        self.process_input()                                    # fase 7: un suceso de entrada por fotograma (INEV del Z80)
        self.vars[VAR_CAMERA_POS_X] = s16(self.cam['cur'])      # (update_scumm_vars: de lo demas, solo estas y el raton)
        self.vars[VAR_HAVE_MSG] = self.have_msg
        self.vars[VAR_VIRT_MOUSE_X] = s16(self.vmouse[0])
        self.vars[VAR_VIRT_MOUSE_Y] = s16(self.vmouse[1])
        self.vars[VAR_MOUSE_X] = s16(self.mouse[0])
        self.vars[VAR_MOUSE_Y] = s16(self.mouse[1])
        self.update_music_timer(real)                           # fase 5b: solo en el modo de sonido "timed" (BOOT); en "mock" no hace nada
        self.run_all_scripts()
        self.check_exec_verbs()                                 # fase 7: checkExecVerbs (VAR_VERB_SCRIPT)
        self.check_and_run_sentence_script()                    # fase 5
        if self.cur_room != 0:                                  # fase 6: walkActors; fase 5b: moveCamera (updateObjectStates no esta en el nucleo: el Z80 mira OBJST vivo)
            self.walk_actors()
            self.move_camera()
        self.update_pan_px()                                    # fase 9: la ventana movil (cam_update del programa)

    def digest(self):
        v = crc16(b''.join(struct.pack('<H', x & 0xFFFF) for x in self.vars))
        lc = crc16(b''.join(struct.pack('<H', x & 0xFFFF) for loc in self.locals for x in loc))
        k = crc16(b''.join(struct.pack('<H', x & 0xFFFF) for x in self.cut_data) + bytes(x & 0xFF for x in self.cut_script))
        sl = []
        for i, s in enumerate(self.slots):
            if s.status != SS_DEAD:
                t = '%d:%d:%d:%d:%d' % (i, s.status, s.where, s.number, s.offs - s.base)
                if s.status & 0x7F == SS_PAUSED:
                    t += ':%d' % (s.delay & 0xFFFFFFFF)
                if s.freeze_count:
                    t += ':f%d' % s.freeze_count
                if s.cutscene_override:
                    t += ':c%d' % s.cutscene_override
                sl.append(t)
        # estado de la capa de juego que ya tiene el Z80 (fase 4a): A actores, O estados+duenos+clases, I inventario, N nombres
        # nuevos de objeto, M mensaje (haveMsg, talkDelay, keepText, sala, ultimo sonido), C camara (los mismos campos que game_digest)
        a = crc16(b''.join(x.pack() for x in self.actors))
        o = crc16(bytes(x & 0xFF for x in self.gstate) + bytes(self.owner)
                  + b''.join(struct.pack('<I', c & 0xFFFFFF) for c in self.classes))
        inv = crc16(b''.join(struct.pack('<H', x) for x in self.inventory))
        nn = crc16(b''.join(struct.pack('<H', x & 0xFFFF) for x in self.new_names))
        cam = self.cam
        return ('D f=%d V=%04X L=%04X K=%d,%04X A=%04X O=%04X I=%04X N=%04X M=%d,%d,%d,%d,%d X=%d,%d,%d,%d,%04X,%04X C=%d,%d,%d,%d,%d U=%d,%d,%d,%d W=%04X T=%04X P=%04X Q=%d,%04X R=%d,%d,%04X,%d,%04X Y=%04X G=%s S=%s' % (
            self.frame, v, lc, self.cut_sp, k, a, o, inv, nn, self.have_msg, self.talk_delay, int(self.keep_text), self.cur_room,
            s16(self.last_sound), int(self.use_talk_anims), self.msg_count, self.charset_pos, self.charset_color,
            crc16(self.charset_buf), self.slots_crc(), s16(cam['cur']), s16(cam['dest']), cam['mode'], cam['follows'], int(cam['moving_to_actor']),
            s16(self.user_put), s16(self.cursor_state), s16(self.main_top), s16(self.main_h), self.verbs_crc(), self.strings_crc(),
            self.actor_names_crc(), len(self.sentence), self.sentence_crc(), len(self.boxes), self.room_nobj(), self.room_crc(),
            int(self.ego_positioned), self.resmap_crc(), crc16(bytes(self.room_pal + self.shadow_pal)), self.walk_trace(), ' '.join(sl)))

    def walk_trace(self):
        """fase 6: posicion de cada actor de la sala en uso (n:x,y,caja,moving), para seguir la caminata fotograma a fotograma."""
        if self.cur_room == 0:
            return '-'
        t = ['%d:%d,%d,%d,%d' % (a.num, a.x, a.y, a.walkbox, a.moving) for a in self.actors[1:] if a.in_room()]
        return ';'.join(t) or '-'

    # fase 5: cola de frases, objetos y cajas de la sala (el Z80 los tiene en RBLOB), mapa de pseudosalas
    def sentence_crc(self):
        return crc16(b''.join(struct.pack('<BHHBB', st['verb'] & 0xFF, st['a'] & 0xFFFF, st['b'] & 0xFFFF, st['prep'], min(st['freeze'], 255))
                              for st in self.sentence))

    def room_nobj(self):
        return len(self.room.objects) if self.room else 0

    def room_crc(self):
        """Los registros de los objetos de la sala (13 bytes de los 14 del blob: sin la bandera de imagen propia) y las cajas (18 bytes)."""
        b = bytearray()
        for i in range(1, self.room_nobj() + 1):
            o = self.objs[i]
            b += struct.pack('<HBBBBBBhhB', o.obj_nr, o.x // 8, o.y // 8, o.width // 8, o.height // 8, o.parent, o.parentstate,
                             o.walk_x, o.walk_y, o.actordir)
        for bx in self.boxes:
            b += struct.pack('<8hBB', *bx)
        return crc16(b)

    def resmap_crc(self):
        return crc16(bytes(self.resource_mapper.get(k, 0) & 0xFF for k in range(128)))

    def slots_crc(self):
        """fase 4b-2: los valores por omision de las 4 ranuras de texto de print (el Z80 guarda esos y una copia de trabajo): xpos, ypos,
        right, height (palabras), color, center, overhead (bytes)."""
        b = bytearray()
        for st in self.str_slots:
            d = st['default']
            b += struct.pack('<HHHHBBB', d['xpos'] & 0xFFFF, d['ypos'] & 0xFFFF, d['right'] & 0xFFFF, d['height'] & 0xFFFF,
                             d['color'] & 0xFF, int(d['center']), int(d['overhead']))
        return crc16(b)

    # fase 4b-1: verbos (con su nombre), cadenas y nombres de actor. El arnes del Z80 calcula lo mismo desde su memoria
    def verbs_crc(self):
        b = bytearray()
        for vs in self.verbs:
            b += bytes([vs.verbid & 255, vs.color & 255, vs.hicolor & 255, vs.dimcolor & 255, vs.bkcolor & 255, vs.curmode & 255,
                        vs.saveid & 255, vs.key & 255, vs.center & 255, vs.type & 255, vs.length & 255])
            b += struct.pack('<HHHH', vs.imgindex & 0xFFFF, vs.left & 0xFFFF, vs.top & 0xFFFF, len(vs.name)) + vs.name
        return crc16(b)

    def strings_crc(self):
        b = bytearray()
        for sid in range(NUM_STRINGS):
            if sid in self.strings:
                b += struct.pack('<BH', sid, len(self.strings[sid])) + bytes(self.strings[sid])
        return crc16(b)

    def actor_names_crc(self):
        b = bytearray()
        for a in self.actors:
            n = a.name or b''
            b += struct.pack('<H', len(n)) + n
        return crc16(b)

    def run_object_core(self, obj, verb):
        """runObjectScript(obj, verb) con el OBCD del indice (el de la primera sala que lo tiene), como hace el arnes del Z80."""
        if not obj:
            return
        self.stop_object_script(obj)
        if obj not in self.w.objects:
            return
        rn, o = self.w.objects[obj]
        slot = self.get_script_slot()
        b, p = o.block, 17
        entry = 0
        while b[p]:
            if b[p] == verb or b[p] == 0xFF:
                entry = b[p + 1] | (b[p + 2] << 8)
                break
            p += 3
        if entry:
            self.start_slot(obj, WIO_ROOM, o.block, entry, None, slot=slot, base=0)


def screen_to_scumm(px, py):
    """Pixeles de la pantalla del ZX81 (256 x 192) -> coordenadas de SCUMM (como in_conv de ui3.asm): en la sala y arriba tal cual; en la interfaz (y >= 144) la columna
    de 6 pixeles * 8 y la y + 8 (las filas de verbos e inventario de SCUMM, 152-199, van a las 144-191)."""
    px = max(0, min(248, px))
    py = max(0, min(184, py))
    if py < 144:
        return px, py
    return min(px // 6, 41) * 8 + 7, (py | 7) + 8          # el texto de la interfaz empieza en el pixel 0 (hr_ui); 42 columnas


def screen_event(kind, a, vm=None):
    """Un suceso de entrada de la pantalla (click px py, move px py, rclick, key k, esc) -> el de CoreVM.pending.
    Con vm: la ventana movil del programa (ui3.asm pan_update / scumm.asm cam_update): la x de SCUMM suma lo que esta corrida (vm.pan_px, la del fotograma anterior) y
    el cursor a la derecha del todo (px >= 232) la corre, a la izquierda (px < 100) la devuelve."""
    if kind in ('click', 'move'):
        x, y = screen_to_scumm(a[0], a[1])
        if vm is not None:
            x += vm.pan_px
            vm.pan_event(a[0])
        return ('click' if kind == 'click' else 'mouse', x, y)
    if kind == 'key':
        return ('key', a[0])
    return ('rclick',) if kind == 'rclick' else ('esc',)


def run_scenario_core(world, lines):
    vm = CoreVM(world, seed=0)
    vm.at_events = {}
    out = []
    for ln in lines:
        p = ln.split()
        cmd = p[0]
        try:
            if cmd == 'INIT':
                vm.reset()
            elif cmd == 'OPT':                          # OPT sonido mock|timed, OPT proteccion 0|1 (solo las usa BOOT)
                if p[1] == 'sonido':
                    vm.sound_mode = p[2]
                elif p[1] == 'proteccion':
                    vm.protection = bool(int(p[2]))
                elif p[1] == 'guardar':                 # fase 9: OPT guardar 1 = guardar y cargar de verdad (el programa; en el nucleo de pruebas es el resultado simulado)
                    vm.real_saves = bool(int(p[2]))
            elif cmd == 'SETVAR':
                vm.vars[int(p[1])] = s16(int(p[2]))
            elif cmd == 'AT':                           # AT fotograma tipo [a b] (fase 7): un suceso de entrada en ese fotograma de BOOT; a, b en pixeles de la pantalla del ZX81
                vm.at_events.setdefault(int(p[1]), []).append((p[2], [int(x) for x in p[3:]]))
            elif cmd == 'BOOT':                         # BOOT n: n fotogramas como el bucle principal del programa (scumm.asm): proteccion y delta = max(1, VAR_TIMER_NEXT)
                for _ in range(int(p[1])):
                    vm.frame += 1
                    delta = max(1, vm.vars[VAR_TIMER_NEXT])     # (el programa lo lee antes de cargar una sala o arrancar un script de depuracion en este fotograma)
                    for kind, a in vm.at_events.pop(vm.frame, []):
                        if kind == 'script':                    # un script global en ese fotograma (el programa: DBG_START)
                            vm.cur = 0xFF
                            vm.run_script(a[0], False, False, [0] * NUM_LOCAL)
                        elif kind == 'snd':                     # fase 8: un sonido sin pasar por un script (el programa: DBG_SND): a = [operacion (1 empezar, 2 parar, 3 parar todo), sonido]
                            if a[0] == 1:
                                vm.real_start(a[1])
                            elif a[0] == 2:
                                vm.real_stop(a[1])
                            else:
                                vm.snd_log.append('SND f=%d STOP' % vm.frame)
                                vm.snd_cur = None
                                vm.snd_next = 0
                        elif kind in ('save', 'load'):          # fase 9: guardar / cargar la ranura a[0] entre fotogramas (el programa: DBG_SAVE)
                            vm.cur = 0xFF
                            if kind == 'save':
                                vm.save_game(a[0])
                            elif a[0] in vm.saves:
                                vm.load_game(a[0])
                        elif kind == 'room':                    # 10g: ir a una sala (el programa: DBG_ROOM, vm_dbg_room y dbg_room de ovc5.asm)
                            vm.cur = 0xFF                       # ScummDebugger::Cmd_Room: la sala del ego, stopAllSounds y startScene
                            ego = vm.actors[vm.vars[VAR_EGO]]
                            ego.room = a[0] & 0xFF
                            vm.snd_log.append('SND f=%d STOP' % vm.frame)
                            vm.snd_cur = None
                            vm.snd_next = 0
                            vm.start_scene(a[0])
                            if not vm.ego_positioned:           # como startScene con loadRoomWithEgo: si los scripts de entrada no lo colocan, putActor (adjustActorPos: a una caja)
                                vm.put_actor(ego, ego.x, ego.y, vm.cur_room)
                        else:
                            vm.pending.append(screen_event(kind, a, vm))
                    protection_hook(vm)
                    vm.step_frame(delta)
                    vm.trace.append(vm.digest())
            elif cmd == 'ROOM':                         # ROOM n [1]: sala en uso con sus objetos (y con las cajas si hay un 1), sin startScene
                set_room_core(vm, int(p[1]), len(p) > 2 and p[2] == '1')
            elif cmd == 'PSEUDO':
                vm.resource_mapper[int(p[1])] = int(p[2])
            elif cmd == 'LOADROOM':                     # como o_loadRoom desde fuera de un script
                vm.cur = 0xFF
                if int(p[1]) != vm.cur_room:
                    vm.start_scene(int(p[1]))
            elif cmd == 'SENTENCE':
                vm.do_sentence(int(p[1]), s16(int(p[2])), s16(int(p[3])))
            elif cmd == 'OWNER':
                vm.owner[int(p[1])] = int(p[2])
            elif cmd == 'STATE':
                vm.gstate[int(p[1])] = int(p[2])
            elif cmd == 'CLASS':
                vm.classes[int(p[1])] = int(p[2], 16)
            elif cmd == 'INV':                          # inventory[k] = obj (el arnes del Z80 escribe en la misma tabla)
                vm.inventory[int(p[1])] = int(p[2])
            elif cmd == 'ACTORSET':                     # ACTORSET n sala x y traje visible: campos a mano, sin efectos
                a = vm.actors[int(p[1])]
                a.room, a.x, a.y, a.costume, a.visible = int(p[2]) & 0xFF, s16(int(p[3])), s16(int(p[4])), int(p[5]), bool(int(p[6]))
                if len(p) > 7:                          # 7.o: ignoreBoxes
                    a.ignore_boxes = bool(int(p[7]))
            elif cmd == 'SCRIPT':
                vm.cur = 0xFF
                vm.run_script(int(p[1]), False, False, [int(x) for x in p[2:]])
            elif cmd in ('ENTRY', 'EXIT'):
                vm.cur = 0xFF
                r = world.rooms[int(p[1])]
                if cmd == 'ENTRY' and r.encd_off:
                    vm.start_slot(SCRIPT_NUM_ENCD, WIO_ROOM, r.file, r.encd_off)
                elif cmd == 'EXIT' and r.excd_off:
                    vm.start_slot(SCRIPT_NUM_EXCD, WIO_ROOM, r.file, r.excd_off)
            elif cmd == 'OBJ':
                vm.cur = 0xFF
                vm.run_object_core(int(p[1]), int(p[2]))
            elif cmd == 'ABORT':
                vm.abort_cutscene()
            elif cmd == 'USERPUT':                      # USERPUT u c: _userPut y _cursor.state a mano (fase 7)
                vm.user_put, vm.cursor_state = int(p[1]), int(p[2])
            elif cmd == 'INPUT':                        # INPUT area valor modo: runInputScript tal cual (fase 7)
                vm.cur = 0xFF
                vm.run_input_script(int(p[1]), s16(int(p[2])), int(p[3]) if len(p) > 3 else 0)
            elif cmd in ('CLICK', 'MOVE', 'RCLICK', 'KEY', 'ESC'):   # fase 7: un suceso de entrada para el siguiente fotograma (x, y en coordenadas de SCUMM)
                vm.pending.append({'CLICK': ('click', int(p[1]) if len(p) > 1 else 0, int(p[2]) if len(p) > 2 else 0),
                                   'MOVE': ('mouse', int(p[1]) if len(p) > 1 else 0, int(p[2]) if len(p) > 2 else 0),
                                   'RCLICK': ('rclick',), 'KEY': ('key', int(p[1]) if len(p) > 1 else 0), 'ESC': ('esc',)}[cmd])
            elif cmd in ('CODE', 'CODER'):              # bytecode sintetico (vmsynth3.py) como un script global; CODER (10e): ademas, startScript(199) lo vuelve a arrancar
                vm.cur = 0xFF
                if cmd == 'CODER':
                    vm.synth_codes = getattr(vm, 'synth_codes', {})
                    vm.synth_codes[SYNTH_SCRIPT] = bytes.fromhex(p[1])
                vm.start_slot(SYNTH_SCRIPT, WIO_GLOBAL, bytes.fromhex(p[1]), 0)
            elif cmd == 'SYNTH':                        # SYNTH n <hex> (10e): el script global n pasa a ser ese bytecode (solo en este escenario; no lo arranca)
                vm.synth_codes = getattr(vm, 'synth_codes', {})
                vm.synth_codes[int(p[1])] = bytes.fromhex(p[2])
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
        if cmd in ('SCRIPT', 'ENTRY', 'EXIT', 'OBJ', 'ABORT', 'CODE', 'CODER', 'LOADROOM', 'SENTENCE', 'INPUT'):
            out.append(vm.digest())
    return out, vm


def set_room_core(vm, rn, boxes):
    """La orden ROOM del modo nucleo: la sala en uso con sus objetos (objs[]), ENCD/EXCD y, si boxes, las cajas y la matriz; sin startScene
    (ni scripts, ni actores, ni camara). El Z80 (vm_set_room) copia el blob de DATA.BIN a RBLOB."""
    vm.cur_room = rn
    vm.room = vm.w.rooms.get(rn)
    vm.boxes, vm.matrix = [], b''
    vm.encd = vm.excd = 0
    for i in range(NUM_LOCAL_OBJECTS):
        vm.objs[i] = ObjData()
    r = vm.room
    if r:
        vm.encd, vm.excd = r.encd_off, r.excd_off
        if boxes:
            bx, mat = r.boxes()
            vm.boxes = [list(b) for b in bx]
            vm.matrix = bytes(mat)
        vm.reset_room_objects()


def make_synth_scenarios(world, seeds=1, per_seed=1200):
    """Escenarios sinteticos de la fase 4b-1 (vmsynth3.py): uno o dos scripts de bytecode al azar, con la sala en uso al azar."""
    import vmsynth3
    sc = []
    rooms = sorted(world.rooms) + [0, 0]
    robjs = {rn: [o.id for o in r.objects] for rn, r in world.rooms.items()}
    mapped = sorted({0x7F & k for k in range(0, 128, 9)}) or [0]
    verbs = lambda o: [v for v, _ in world.objects[o][1].verbs] if o in world.objects else []
    for seed in range(seeds):
        rng = random.Random(9000 + seed)
        for i in range(per_seed):
            room = rng.choice(rooms)
            nbx = len(world.rooms[room].boxes()[0]) if room else 0
            rects = [(o.x + o.width // 2, o.y + o.height // 2) for o in world.rooms[room].objects] if room else []
            ctx = dict(rooms=sorted(world.rooms), room=room, robjs=robjs, verbs=verbs, nboxes=nbx, mapped=mapped, rects=rects,
                       boxes=world.rooms[room].boxes()[0] if room else [], width=world.rooms[room].width if room else 320)
            lines = init_lines_core(rng, world, room or None, rng.random() < 0.6 or None) + ['ROOM %d%s' % (room, ' 1' if rng.random() < 0.6 else '')]
            ctx['inv'] = [int(ln.split()[2]) for ln in lines if ln.startswith('INV ')]
            for _ in range(rng.choice([1, 1, 2])):
                lines.append('CODE ' + vmsynth3.make_code(rng, ctx=ctx).hex())
            lines.append(rng.choice(['FRAMES 3 2', 'FRAMES 3 2', 'FRAMES 15 8', 'FRAMES 15 40', 'FRAMES 1 70', 'FRAMES 6 25']))
            sc.append(('syn%04d.s%d' % (i, seed), lines))
    return sc


def init_lines_core(rng, world, room=None, ign=None):
    """INIT + las variables de despues del arranque (boot_snapshot: solo SETVAR) + unas pocas cambiadas al azar, y desde la
    fase 4a unos actores puestos a mano (ACTORSET: en la sala en uso, en la 0 o en otra, con o sin traje, visibles o no),
    unos duenos de objeto (OWNER) y el inventario (INV) con esos objetos."""
    lines = ['INIT'] + [ln for ln in boot_snapshot(world) if ln.startswith(('SETVAR ', 'PSEUDO '))]
    for v in range(NUM_VARS):
        if v not in NO_RANDOM_VARS and rng.random() < 0.02:
            lines.append('SETVAR %d %d' % (v, rng.choice([0, 1, 1, 2, 3, 4, 5, 8, 10, 15, 255])))
    rooms = [room, room, room, 0, 5] if room else [0, 0, 1, 5]
    for n in range(NUM_ACTORS):
        if rng.random() < 0.3:
            lines.append('ACTORSET %d %d %d %d %d %d %d' % (n, rng.choice(rooms), rng.randrange(0, 321), rng.randrange(0, 160),
                                                             rng.choice([0, 1, 2, 3, 5]), rng.randrange(2),
                                                             (rng.random() < 0.3) if ign is None else int(ign)))
    if rng.random() < 0.4:
        for k in range(rng.randrange(1, 5)):
            obj = rng.randrange(1, NUM_OBJECTS)
            lines.append('OWNER %d %d' % (obj, rng.randrange(1, NUM_ACTORS)))
            lines.append('INV %d %d' % (rng.randrange(NUM_INVENTORY), obj))
    return lines


WALK_ROOMS = (1, 15, 20, 28)             # fase 6: pasillo, Venecia y castillo (mas escenarios de caminata)


# fase 7: donde estan los verbos de Indy3 (script 96) y sus teclas, para los escenarios de entrada
INPUT_VERB_X = [0, 48, 104, 176, 256, 152, 168]
INPUT_VERB_Y = [144, 152, 160, 168, 176, 184, 192]
INPUT_KEYS = [113, 97, 122, 119, 115, 120, 101, 100, 99, 114, 102, 118, 116, 103, 98, 121, 117, 104, 106, 110, 109, 111, 108, 13, 27, 46, 32]


def make_scenarios_core(world, seeds=1, rooms=None, scripts=True, objects=True):
    """Escenarios del nucleo: cada sala (entrada, fotogramas, ABORT, salida), cada script local, cada verbo de cada objeto y
    cada script global (con argumentos al azar). Reproducibles: misma semilla, misma lista."""
    sc = []
    rlist = sorted(world.rooms) if rooms is None else [r for r in rooms if r in world.rooms]
    for seed in range(seeds):
        rng = random.Random(5000 + seed)
        for rn in rlist:
            r = world.rooms[rn]
            rb = lambda: 'ROOM %d%s' % (rn, ' 1' if rng.random() < 0.5 else '')      # con cajas o sin ellas
            sc.append(('croom%02d.s%d' % (rn, seed), init_lines_core(rng, world, rn) + [
                rb(), 'ENTRY %d' % rn, 'FRAMES 4 30', 'FRAMES 40 2', 'ABORT', 'FRAMES 4 10', 'EXIT %d' % rn, 'FRAMES 4 10']))
            nbx = len(r.boxes()[0])
            if nbx:                                                # isActorInBox con cada caja de la sala y el actor 3 en varios puntos
                import vmsynth3 as VS
                bxs = r.boxes()[0]
                for t in range(3):
                    b0 = bxs[rng.randrange(nbx)]
                    cx_, cy_ = sum(b0[0:8:2]) // 4, sum(b0[1:8:2]) // 4
                    vk = rng.randrange(4)                              # un punto un poco dentro, cerca de un vertice
                    ix_, iy_ = b0[2 * vk] + (cx_ - b0[2 * vk]) // 6, b0[2 * vk + 1] + (cy_ - b0[2 * vk + 1]) // 6
                    px = rng.choice([cx_, b0[0] + 1, b0[2], b0[4] - 1, rng.randrange(0, r.width), ix_, ix_])
                    py = rng.choice([cy_, b0[1], b0[3] + 1, b0[5] - 1, rng.randrange(0, 150), iy_, iy_])
                    if rng.random() < 0.5:
                        px, py = ix_, iy_
                    code = bytearray()
                    for k in range(nbx + 1):
                        code += bytes([0x1F, 3, k, 5, 0, 0x1A, 224 + k % 32, 0, 1, 0])
                    code.append(0)
                    sc.append(('cbox%02d.%d.s%d' % (rn, t, seed), init_lines_core(rng, world, rn, True) + [
                        'ACTORSET 3 %d %d %d 1 1 1' % (rn, px, py), 'ROOM %d 1' % rn, 'CODE ' + code.hex(), 'FRAMES 3 1']))
            # fase 5: startScene (loadRoom desde otra sala: salida de la anterior, entrada de esta) y la cola de frases
            frm = rng.choice(rlist)
            sc.append(('clrm%02d.s%d' % (rn, seed), init_lines_core(rng, world, rn, True) + [
                'ROOM %d 1' % frm, 'LOADROOM %d' % rn, 'FRAMES 4 30', 'LOADROOM %d' % rng.choice(rlist), 'FRAMES 4 10']))
            if r.objects:
                import vmsynth3 as VS
                a = VS.Asm(rng, varprob=1.0)                       # findObject sobre el centro de cada objeto de la sala, con estados al azar (cadena de padres)
                for o in rng.sample(r.objects, min(len(r.objects), 26)):
                    a.begin()
                    a.op('findObject', [('b', o.x + o.width // 2 + rng.choice([0, 0, 1])), ('b', o.y + o.height // 2)], pre=a.result())
                a.out.append(0)
                st = ['STATE %d %d' % (o.id, rng.randrange(2)) for o in r.objects if rng.random() < 0.5]
                sc.append(('cfnd%02d.s%d' % (rn, seed), init_lines_core(rng, world, rn, True) + ['ROOM %d 1' % rn] + st + [
                    'CODE ' + a.out.hex(), 'FRAMES 3 1']))
                o1, o2 = rng.choice(r.objects), rng.choice(r.objects)
                snt = [('SENTENCE %d %d %d' % (rng.choice([1, 2, 3, 4, 5, 7, 8, 9, 13, 14, 15]), (o1 if rng.random() < 0.8 else o2).id,
                        o2.id if rng.random() < 0.4 else 0)) for _ in range(rng.choice([1, 1, 2, 3]))]
                sc.append(('csnt%02d.s%d' % (rn, seed), init_lines_core(rng, world, rn, True) + [
                    'ROOM %d 1' % rn] + snt + ['FRAMES 4 12', 'FRAMES 6 25']))
            if nbx:                                                # fase 6: caminata (clics = walkActorTo del ego) y los demas opcodes que la tocan
                import vmsynth3 as VS
                wr_ = random.Random(7000 + 100 * seed + rn)        # (generador aparte: no cambia los escenarios de antes)
                ctx = dict(rooms=rlist, room=rn, robjs={rn: [o.id for o in r.objects]}, boxes=bxs, width=r.width, nboxes=nbx)
                ego = 1
                for t in range(12 if rn in WALK_ROOMS else 3):
                    lines = init_lines_core(wr_, world, rn, False) + ['SETVAR %d %d' % (VAR_EGO, ego)]
                    for n in (1, 2, 3):                            # clases de actor que cambian la caminata: volteo en x (bit 18), en y (17), jugador (22)
                        if wr_.random() < 0.25:
                            lines.append('CLASS %d %X' % (n, wr_.choice([0x40000, 0x20000, 0x60000, 0x400000, 0x440000])))
                    lines.append('ROOM %d 1' % rn)
                    if t % 3 != 2:                                 # clics: el ego en la sala y de 3 a 7 clics, algunos antes de llegar
                        x0, y0 = VS.walk_point(wr_, bxs, r.width, wild=0)
                        lines.append('CODE ' + VS.make_walk_code(wr_, ctx, 0, [(ego, 1, x0, y0)]).hex())
                        for c in range(wr_.randrange(3, 8)):
                            code = VS.click_code(wr_, ctx, ego).hex()
                            lines += ['CODE ' + code, 'FRAMES %d %d' % (wr_.choice([1, 4, 4, 6]), wr_.choice([2, 5, 10, 20, 40, 80, 80]))]
                            if wr_.random() < 0.25:                # el mismo clic otra vez (startWalkActor con el mismo destino)
                                lines += ['CODE ' + code, 'FRAMES 4 %d' % wr_.choice([1, 3, 12])]
                            if wr_.random() < 0.25:                # cambio de velocidad andando (actorOps 2: calcMovementFactor)
                                lines += ['CODE ' + VS.speed_code(wr_, ego).hex(), 'FRAMES 4 %d' % wr_.choice([2, 6, 20])]
                        lines.append('FRAMES 4 150')
                    else:                                          # mezcla: varios actores, velocidades, banderas de caja, clases y esperas
                        setup = [(n, wr_.choice([1, 2, 3]), *VS.walk_point(wr_, bxs, r.width, wild=0)) for n in (1, 2, 3) if n == 1 or wr_.random() < 0.6]
                        lines.append('CODE ' + VS.make_walk_code(wr_, ctx, 0, setup).hex())
                        for c in range(wr_.randrange(3, 7)):
                            lines += ['CODE ' + VS.make_walk_code(wr_, ctx).hex(),
                                      'FRAMES %d %d' % (wr_.choice([1, 4, 6, 15]), wr_.choice([1, 3, 10, 25, 60]))]
                        lines.append('FRAMES 4 100')
                    sc.append(('cwlk%02d.%d.s%d' % (rn, t, seed), lines))
            if nbx:                                                # fase 7: la entrada (clics, teclas, ESC, boton derecho) con los verbos de Indy3 puestos (script 96)
                wi_ = random.Random(8000 + 100 * seed + rn)        # (generador aparte)
                for t in range(6 if rn in WALK_ROOMS else 2):
                    lines = init_lines_core(wi_, world, rn, False) + ['SETVAR %d 1' % VAR_EGO, 'ROOM %d 1' % rn, 'SCRIPT 96']
                    lines.append('USERPUT %d %d' % wi_.choice([(1, 1), (1, 1), (1, 1), (1, 1), (0, 0), (-1, -1), (2, 3)]))
                    lines.append('FRAMES 6 2')
                    if r.encd_off and wi_.random() < 0.4:              # la entrada de la sala (con sus escenas cortadas: ESC y el boton derecho las abortan)
                        lines += ['ENTRY %d' % rn, 'FRAMES 4 3']
                    if wi_.random() < 0.3:                             # los verbos guardados (saveRestoreVerbs 1, 1..14, 1): sus teclas y clics ya no valen
                        import vmsynth3 as VS
                        asm = VS.Asm(wi_, varprob=0)
                        asm.begin()
                        asm.op('saveRestoreVerbs', [('b', 1), ('b', 14), ('b', 1)], pre=bytes([1]))
                        asm.out.append(0)
                        lines += ['CODE ' + asm.out.hex(), 'FRAMES 6 2']
                    if wi_.random() < 0.5:                             # Intro con el raton sobre un verbo = un clic en el verbo
                        lines += ['MOVE %d %d' % (wi_.choice(INPUT_VERB_X[:5]) + wi_.randrange(0, 20), wi_.choice(INPUT_VERB_Y[1:4]) + wi_.randrange(0, 8)),
                                  'FRAMES 6 1', 'KEY 13', 'FRAMES 6 3']
                    for _ in range(wi_.randrange(6, 15)):
                        kind = wi_.random()
                        if kind < 0.45:                            # clic: sobre un verbo, en la escena, en el inventario, arriba, o en cualquier sitio
                            where = wi_.random()
                            if where < 0.4:
                                x, y = wi_.choice(INPUT_VERB_X) + wi_.randrange(0, 40), wi_.choice(INPUT_VERB_Y) + wi_.randrange(0, 8)
                            elif where < 0.7:
                                if r.objects and wi_.random() < 0.7:        # el centro de un objeto de la sala (y de la pantalla = y de SCUMM + 16)
                                    o = wi_.choice(r.objects)
                                    x, y = o.x + o.width // 2, o.y + o.height // 2 + 16
                                else:
                                    x, y = wi_.randrange(0, 320), wi_.randrange(16, 144)
                            elif where < 0.8:
                                x, y = wi_.randrange(0, 320), wi_.randrange(176, 200)
                            elif where < 0.9:
                                x, y = wi_.randrange(0, 320), wi_.randrange(0, 16)
                            else:
                                x, y = wi_.randrange(-20, 340), wi_.randrange(-20, 220)
                            lines.append('CLICK %d %d' % (x, y))
                        elif kind < 0.55:
                            lines.append('MOVE %d %d' % (wi_.randrange(0, 320), wi_.randrange(0, 200)))
                        elif kind < 0.8:
                            lines.append('KEY %d' % wi_.choice(INPUT_KEYS + [wi_.randrange(32, 128)]))
                        elif kind < 0.9:
                            lines.append('RCLICK')
                        else:
                            lines.append('ESC')
                        lines.append('FRAMES %d %d' % (wi_.choice([1, 4, 6, 6]), wi_.choice([1, 2, 4, 10, 25])))
                    if wi_.random() < 0.3:
                        lines.append('INPUT %d %d %d' % (wi_.choice([1, 2, 3, 4]), wi_.choice([0, 6, 10, 13, 97, 101]), wi_.choice([0, 1])))
                    lines.append('FRAMES 6 30')
                    sc.append(('cinp%02d.%d.s%d' % (rn, t, seed), lines))
            for sid, _ in r.local_scripts:
                args = ' '.join(str(rng.choice([0, 1, 2, 3, 5, 10, 100])) for _ in range(rng.randrange(3)))
                sc.append(('cloc%02d.%d.s%d' % (rn, sid, seed), init_lines_core(rng, world, rn) + [
                    rb(), ('SCRIPT %d %s' % (sid, args)).strip(), 'FRAMES 3 25']))
            if objects:
                for o in r.objects:
                    if world.objects.get(o.id, (None,))[0] != rn:
                        continue
                    for verb, _ in o.verbs:
                        sc.append(('cobj%03d.v%02X.s%d' % (o.id, verb, seed), init_lines_core(rng, world, rn) + [
                            rb(), 'OBJ %d %d' % (o.id, verb), 'FRAMES 3 25']))
        for sid in (sorted(world.scripts) if scripts else ()):
            args = ' '.join(str(rng.choice([0, 1, 2, 3, 5, 10, 100])) for _ in range(rng.randrange(4)))
            sroom = rng.choice(rlist + [None])           # fase 5: una sala en uso (con o sin cajas) para los scripts globales
            sc.append(('cscr%03d.s%d' % (sid, seed), init_lines_core(rng, world, sroom) + (
                ['ROOM %d%s' % (sroom, ' 1' if rng.random() < 0.4 else '')] if sroom else []) + [
                'SETVAR %d 7' % VAR_MUSIC_TIMER, ('SCRIPT %d %s' % (sid, args)).strip(), 'FRAMES 3 25', 'ABORT', 'FRAMES 3 5']))
        # fase 7: escenarios fijos de la entrada (sin azar): ESC y el boton derecho en las escenas cortadas del arranque; un clic en el borde derecho de cada verbo
        # de Indy3 (el rectangulo es [left, left + 8 * columnas)); '.' con un mensaje en pantalla (script 3: printEgo)
        wf_ = random.Random(8500 + seed)
        sc.append(('cinpboot.s%d' % seed, ['INIT', 'OPT proteccion 0', 'SCRIPT 1', 'FRAMES 6 30', 'ESC', 'FRAMES 6 12', 'FRAMES 6 150', 'KEY 27', 'FRAMES 6 20',
                                           'RCLICK', 'FRAMES 6 40', 'FRAMES 6 100', 'ESC', 'FRAMES 6 30']))
        if 1 in world.rooms and world.rooms[1].boxes()[0]:
            vl = init_lines_core(wf_, world, 1, False) + ['SETVAR %d 1' % VAR_EGO, 'ROOM 1 1', 'SCRIPT 96', 'USERPUT 1 1', 'FRAMES 6 2']
            for x in INPUT_VERB_X[:4]:
                for y in INPUT_VERB_Y[1:4]:
                    vl += ['CLICK %d %d' % (x + 28 + wf_.randrange(0, 4), y + wf_.randrange(0, 8)), 'FRAMES 6 2']
            vl += ['CLICK 300 160', 'FRAMES 6 2', 'CLICK 200 151', 'FRAMES 6 2']
            sc.append(('cinpverb.s%d' % seed, vl))
            sc.append(('cinpdot.s%d' % seed, init_lines_core(wf_, world, 1, False) + ['SETVAR %d 1' % VAR_EGO, 'ROOM 1 1', 'SCRIPT 96', 'USERPUT 1 1', 'SCRIPT 3',
                                                                                    'FRAMES 6 2', 'KEY 46', 'FRAMES 6 3', 'SCRIPT 3', 'FRAMES 6 1', 'KEY 46', 'FRAMES 6 1',
                                                                                    'KEY 46', 'FRAMES 6 30']))
        # 10e: huecos del nucleo que los scripts de Indy3 no recorren (mutaciones sin detectar). Bytecode fijo, sin azar (no cambia los demas escenarios):
        #  - cgapidx: indice constante de 0x2000 >= 0x800 (readVar suma a & 0xFFF): escribe y lee el bit 0x8C80 + 0x805 (variable 72, bit 5)
        #  - cgapdiv: divide con los dos operandos negativos (-7 / -2 = 3) y con uno (7 / -2 = -3)
        #  - cgapnest: stopScript de un script anidado. runScriptNested (ScummVM) solo vuelve al padre si su ranura sigue con el mismo numero, viva y sin
        #    congelar, asi que limpiar vm.nest solo se nota si el script parado se vuelve a arrancar en la misma ranura antes de volver: el 199 (CODER)
        #    arranca el 198 (SYNTH), que arranca el 199 (no recursivo: stopScript(199) mata al de fuera); el nuevo 199 cede el turno (breakHere) y al
        #    acabar el 198 el padre no sigue: el nuevo 199 pone la variable 252 en el fotograma siguiente, no en este
        gl = ['INIT'] + [ln for ln in boot_snapshot(world) if ln.startswith(('SETVAR ', 'PSEUDO '))]
        sc.append(('cgapidx.s%d' % seed, gl + ['SETVAR 72 0', 'SETVAR 200 0', 'SETVAR 252 0',
                                              'CODE 1a80ac050801009afc0080ac050800', 'FRAMES 3 1']))
        sc.append(('cgapdiv.s%d' % seed, gl + ['CODE 1afd00f9ff5bfd00feff1afe0007005bfe00feff00', 'FRAMES 3 1']))
        sc.append(('cgapnest.s%d' % seed, gl + ['SETVAR 250 0', 'SETVAR 251 0', 'SETVAR 252 0', 'SETVAR 253 0', 'SYNTH 198 0ac7ff1afd00010000',
                                               'CODER 48fa0000000e001afa0001000ac6ff1afb00010000' + '801afc00010000', 'FRAMES 3 2']))
        #  - cgapcam (moveCamera, sala 1, 960 de ancho): setCameraAt(100) deja el destino por debajo del minimo (moveCamera lo acota); roomOps 1 (400, 500) deja
        #    la camara por debajo del minimo (avanza de 8 en 8) y roomOps 1 (160, 200) por encima del maximo (retrocede); despues, con la camara en 400
        #    (_screenStartStrip = 30), el actor 1 en x = 316 (columna 39: t = 9, justo por debajo de _leftTrigger = 10) y actorFollowCamera(1)
        if 1 in world.rooms and world.rooms[1].width == 960:
            sc.append(('cgapcam.s%d' % seed, gl + ['SETVAR %d 0' % VAR_CAMERA_FAST_X, 'SETVAR %d 1' % VAR_EGO, 'ROOM 1 1', 'FRAMES 3 2',
                                                  'CODE 32640000', 'FRAMES 3 3',
                                                  'CODE 339001f4010100', 'FRAMES 3 34',
                                                  'CODE 33a000c8000100', 'FRAMES 3 6',
                                                  'CODE 33a0002003010032900100', 'FRAMES 3 2',
                                                  'ACTORSET 1 1 316 100 0 1 1', 'CODE 520100', 'FRAMES 3 6']))
        #  - cgapverb (fase 7): un verbo centrado (verbOps 19; Indy3 no los usa) y un clic 4 px a la izquierda de su left (findVerbAtPos: dentro si es centrado);
        #    un verbo con el nombre "A" + $FF 4 (la variable 250) se guarda (saveRestoreVerbs 1), la variable cambia y se restaura (2): drawVerb le vuelve
        #    a calcular el rectangulo (de 2 columnas a 6)
        sc.append(('cgapverb.s%d' % seed, gl + ['SETVAR %d 1' % VAR_EGO, 'ROOM 1 1', 'USERPUT 1 1', 'SETVAR 250 5', 'FRAMES 6 1',
                                               'CODE 7a65090241420005500098000613ff' + '7a66090241ff04fa0000050001b80006ff00', 'FRAMES 6 1',
                                               'CODE ab01666601' + '1afa003930' + 'ab0266660100', 'FRAMES 6 1',
                                               'CLICK 76 156', 'FRAMES 6 3', 'CLICK 300 188', 'FRAMES 6 3']))
        #  - cgapibx<sala>: isActorInBox con el actor justo dentro de la caja junto a su 4.a esquina (ll), en las cajas en que esa esquina es la unica
        #    con la x (o la y) mas pequena o mas grande (suelos en trapecio): el rechazo rapido por el rectangulo de las 4 esquinas tiene que contarla
        for rn in rlist:
            bxs = world.rooms[rn].boxes()[0]
            lines = []
            for k, b0 in enumerate(bxs):
                xs, ys = b0[0:8:2], b0[1:8:2]
                cx_, cy_ = sum(xs) // 4, sum(ys) // 4
                px, py = xs[3] + (cx_ - xs[3]) // 4, ys[3] + (cy_ - ys[3]) // 4
                if not ((px < min(xs[:3]) or px > max(xs[:3])) or (py < min(ys[:3]) or py > max(ys[:3]))):
                    continue
                lines += ['ACTORSET 3 %d %d %d 1 1 1' % (rn, px, py), 'CODE 1f03%02x05001a%02x00070000' % (k, 224 + len(lines) // 3 % 32), 'FRAMES 3 1']
                if len(lines) >= 12:
                    break
            if lines:
                sc.append(('cgapibx%02d.s%d' % (rn, seed), gl + ['ROOM %d 1' % rn] + lines))
        # D5: los scripts de mas de una pagina (en Indy3, el 95: un dialogo que espera a la variable 114). Con 114 cambiando
        # en cada fotograma, el script recorre el arbol y cruza la frontera de 4 KB de sus paginas en los dos sentidos
        for sid in (sorted(s for s, c in world.scripts.items() if len(c) > 6144) if scripts else ()):
            for k in range(3):
                ln = init_lines_core(rng, world) + ['SCRIPT %d' % sid]
                for _ in range(120):
                    ln += ['SETVAR 114 %d' % rng.choice([1, 2, 3, 4, 5]), 'FRAMES 2 1']
                sc.append(('cbig%03d.%d.s%d' % (sid, k, seed), ln))
    return sc


# ------------------------------------------------------------------------------------------------ arranque
def random_click(vm, rng):
    """Un clic de pantalla sobre una caja visible de la sala (donde un jugador pincharia para andar)."""
    if not vm.room or not vm.boxes:
        return rng.randrange(320), rng.randrange(16, 150)
    ks = [k for k in range(len(vm.boxes)) if not vm.boxes[k][9] & BOX_INVISIBLE]
    if not ks:
        return 160, 100
    ul, ur, lr, ll = vm.get_box_coordinates(rng.choice(ks))
    t, u = rng.random(), rng.random()
    top = (ul[0] + (ur[0] - ul[0]) * t, ul[1] + (ur[1] - ul[1]) * t)
    bot = (ll[0] + (lr[0] - ll[0]) * t, ll[1] + (lr[1] - ll[1]) * t)
    vx = int(top[0] + (bot[0] - top[0]) * u)
    vy = int(top[1] + (bot[1] - top[1]) * u)
    return max(0, min(319, vx - vm.cam_xstart())), max(0, min(199, vy + vm.main_top))


def run_boot(world, frames, seed=1, protection=False, sound_mode='timed', verbose=True):
    """Arranca el juego (script 1) con clics al azar. Devuelve (vm, {sala: primer fotograma})."""
    vm = VM(world, seed=seed, protection=protection, sound_mode=sound_mode)
    rng = random.Random(seed)
    first = {}
    nxt = 30
    try:
        vm.run_script(1, False, False, [0] * NUM_LOCAL)
        for _ in range(frames):
            nxt -= 1
            if nxt <= 0:
                x, y = random_click(vm, rng)
                vm.pending.append(('click', x, y))
                nxt = rng.randint(15, 60)
            vm.frame += 1
            protection_hook(vm)
            delta = max(1, vm.vars[VAR_TIMER_NEXT])
            vm.step_frame(delta)
            first.setdefault(vm.cur_room, vm.frame)
            vm.trace = []
    except Halt:
        pass
    return vm, first


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = [a for a in sys.argv[1:] if a.startswith('--')]
    if len(args) < 3:
        print(__doc__)
        return 1
    d, cmd = args[0], args[1]
    world = World(d)
    if cmd == 'boot':
        n = int(args[2])
        seed = int(args[3]) if len(args) > 3 else 1
        vm, first = run_boot(world, n, seed, protection='--proteccion' in flags,
                             sound_mode='mock' if '--sonido-mock' in flags else 'timed')
        print('fotogramas %d, sala final %d, instrucciones %d, ranuras maximas %d' % (vm.frame, vm.cur_room, vm.insn, vm.max_slots))
        print('primer fotograma en cada sala:', ' '.join('%d@%d' % (r, f) for r, f in sorted(first.items(), key=lambda x: x[1])))
        return 0 if 1 in first else 2
    out = args[2]
    os.makedirs(out, exist_ok=True)
    if cmd == 'scenarios-core':
        seeds = int(args[3]) if len(args) > 3 else 1
        rooms = [int(x) for x in args[4].split(',')] if len(args) > 4 else None
        sc = make_scenarios_core(world, seeds, rooms) + make_synth_scenarios(world, seeds)
        errs = skipped = 0
        with open(os.path.join(out, 'scenarios.txt'), 'w') as fs, open(os.path.join(out, 'expected.txt'), 'w') as fe:
            for name, lines in sc:
                trace, vm = run_scenario_core(world, lines)
                if trace and trace[-1].startswith('ERR'):
                    errs += 1
                    if trace[-1] == 'ERR %d' % E_BUDGET:
                        skipped += 1
                        continue
                fs.write('SCENARIO %s' % name + chr(10) + chr(10).join(lines) + chr(10) + 'END' + chr(10))
                fe.write('SCENARIO %s' % name + chr(10) + chr(10).join(trace) + chr(10) + 'END' + chr(10))
        print('%d escenarios del nucleo, %d acaban en error (%d sin presupuesto, descartados)' % (len(sc), errs, skipped))
    elif cmd == 'boot-core':                            # fase 5b: el arranque (script 1) en modo nucleo con sonido "timed": solo las lineas D (el programa no saca sucesos)
        n = int(args[3]) if len(args) > 3 else 1500
        evl = []                                        # fase 7: sucesos de entrada (un fichero con lineas "fotograma tipo [a b]": click, move, rclick, key, esc; a, b en pixeles)
        if len(args) > 4:
            evl = ['AT ' + ln.strip() for ln in open(args[4]) if ln.strip() and not ln.startswith('#')]
        trace, vm = run_scenario_core(world, ['INIT', 'OPT proteccion 0', 'OPT sonido real', 'OPT guardar 1', 'SCRIPT 1'] + evl + ['BOOT %d' % n])
        if os.environ.get('BOOT_TRACE'):                # 10g-3 (depuracion): la traza entera (H, E, D) a un fichero
            with open(os.environ['BOOT_TRACE'], 'w') as ft:
                ft.write(chr(10).join(trace) + chr(10))
        with open(os.path.join(out, 'boot_expected.txt'), 'w') as fe:
            for t in trace:
                if t.startswith(('D ', 'ERR')):
                    fe.write(t + chr(10))
        with open(os.path.join(out, 'boot_snd_expected.txt'), 'w') as fe:       # fase 8: las ordenes al MCU (STOP, LOOP, PLAY) que tiene que dar el Z80
            for t in vm.snd_log:
                fe.write(t + chr(10))
        firsts = {}
        for t in trace:
            if t.startswith('D '):
                m = re.search(r' M=\d+,\d+,\d+,(\d+),', t)
                f = int(t.split()[1][2:])
                if m:
                    firsts.setdefault(int(m.group(1)), f)
        print('fotogramas %d, primer fotograma en cada sala: %s' % (vm.frame, ' '.join('%d@%d' % (r, f) for r, f in sorted(firsts.items(), key=lambda x: x[1]))))
    elif cmd == 'scenarios':
        seeds = int(args[3]) if len(args) > 3 else 1
        sc = make_scenarios(world, seeds)
        errs = skipped = 0
        with open(os.path.join(out, 'scenarios.txt'), 'w') as fs, open(os.path.join(out, 'expected.txt'), 'w') as fe:
            for name, lines in sc:
                trace, vm = run_scenario(world, lines)
                if trace and trace[-1].startswith('ERR'):
                    errs += 1
                    if trace[-1] == 'ERR %d' % E_BUDGET:
                        skipped += 1
                        continue          # bucle sin ceder el control: no sirve para comparar
                fs.write('SCENARIO %s\n' % name + '\n'.join(lines) + '\nEND\n')
                fe.write('SCENARIO %s\n' % name + '\n'.join(trace) + '\nEND\n')
        print('%d escenarios, %d acaban en error (%d sin presupuesto, descartados)' % (len(sc), errs, skipped))
    return 0


if __name__ == '__main__':
    sys.exit(main())
