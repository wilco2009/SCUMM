#!/usr/bin/env python3
"""VM minima de SCUMM v3 (Indy3 EGA) para medir la CPU por fotograma. Copia la semantica de ScummVM (engines/scumm):

  scumm.cpp     scummLoop (orden: temporizadores, retardos, displayDialog, variables, runAllScripts, checkExecVerbs,
                checkAndRunSentenceScript, walkActors, moveCamera, actores)
  script.cpp    runScript, runScriptNested, runObjectScript, stop*, freeze/unfreeze, cutscene/override, frases, readVar/writeVar
  script_v5.cpp / script_v4.cpp / script_v3.cpp   los opcodes (misma lectura de operandos que scumm3dis.py)
  room.cpp      startScene (salida, matar scripts de sala, ocultar actores, objetos, entrada)
  object.cpp    whereIsObject, clases (con la traduccion de GF_SMALL_HEADER), findObject, inventario
  string.cpp    actorTalk / CHARSET_1: un mensaje dura 60 + VAR_CHARINC por caracter (jiffies)

Simplificado (no cambia el numero de bytecodes de forma apreciable, pero hay que tenerlo en cuenta):
  - Caminata: por cajas con la matriz de v3 y el punto mas cercano de la caja siguiente (como Actor_v2), no con las
    "puertas" de findPathTowardsOld; pasos de Actor_v3 (speedx 8, speedy 2). La duracion de los paseos es parecida.
  - No hay dibujo: se cuentan las causas de trabajo grafico (actores visibles, que se mueven o cambian de celda, objetos
    redibujados, columnas de scroll).
  - Sonido: isSoundRunning devuelve 0 salvo durante unos fotogramas tras startSound.

Uso (desde SCUMM/V3/TOOLS):
  python scumm3vm.py DIR boot FOTOGRAMAS salida.json [semilla]        arranca el juego (script 1) con clics al azar
  python scumm3vm.py DIR rooms FOTOGRAMAS salida.json SALAS...        recorrido: arranca y luego salta a cada sala
"""
import json
import os
import random
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import scumm3res as R         # noqa: E402
import scumm3dis as DIS       # noqa: E402

P1, P2, P3 = 0x80, 0x40, 0x20
NUM_SLOT = 40
NUM_LOCAL = 25
NUM_VARS = 800
NUM_ACTORS = 13
NUM_SENTENCE = 6
SS_DEAD, SS_PAUSED, SS_RUNNING = 0, 1, 2
WIO_NOT_FOUND, WIO_INVENTORY, WIO_ROOM, WIO_GLOBAL, WIO_LOCAL, WIO_FLOBJECT = -1, 0, 1, 2, 3, 4
OWNER_ROOM = 0x0F
ENCD, EXCD = 10002, 10001                    # kScriptNumENCD / EXCD
MF_NEW_LEG, MF_IN_LEG, MF_TURN, MF_LAST_LEG = 1, 2, 4, 8
BOX_PLAYER_ONLY, BOX_LOCKED, BOX_INVISIBLE = 0x20, 0x40, 0x80

# variables de ScummEngine::setupScummVars (v3)
VAR_EGO, VAR_CAMERA_POS_X, VAR_HAVE_MSG, VAR_ROOM, VAR_OVERRIDE = 1, 2, 3, 4, 5
VAR_ME, VAR_NUM_ACTOR = 7, 8
VAR_TMR_1, VAR_TMR_2, VAR_TMR_3, VAR_MUSIC_TIMER = 11, 12, 13, 14
VAR_ACTOR_RANGE_MIN, VAR_ACTOR_RANGE_MAX, VAR_CAMERA_MIN_X, VAR_CAMERA_MAX_X = 15, 16, 17, 18
VAR_TIMER_NEXT, VAR_VIRT_MOUSE_X, VAR_VIRT_MOUSE_Y, VAR_ROOM_RESOURCE, VAR_LAST_SOUND = 19, 20, 21, 22, 23
VAR_TALK_ACTOR = 25
VAR_ENTRY_SCRIPT, VAR_ENTRY_SCRIPT2, VAR_EXIT_SCRIPT, VAR_EXIT_SCRIPT2 = 28, 29, 30, 31
VAR_VERB_SCRIPT, VAR_SENTENCE_SCRIPT, VAR_INVENTORY_SCRIPT = 32, 33, 34
VAR_CUTSCENE_START_SCRIPT, VAR_CUTSCENE_END_SCRIPT, VAR_CHARINC, VAR_WALKTO_OBJ = 35, 36, 37, 38
VAR_MOUSE_X, VAR_MOUSE_Y, VAR_TIMER, VAR_TIMER_TOTAL = 44, 45, 46, 47


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


class VMError(Exception):
    pass


class Halt(Exception):
    pass


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


class Actor:
    def __init__(self, n):
        self.num = n
        self.room = 0
        self.costume = 0
        self.init()

    def init(self):
        self.x = self.y = 0
        self.elevation = 0
        self.visible = False
        self.moving = 0
        self.facing = 180
        self.target_facing = 180
        self.walk_frame, self.stand_frame, self.init_frame = 2, 3, 1      # Actor::initActor (version >= 3)
        self.talk_start, self.talk_stop = 4, 5
        self.speedx, self.speedy = 8, 2
        self.width = 24
        self.ignore_boxes = False
        self.anim_speed = 0
        self.anim_progress = 0
        self.walkbox = 0
        self.frame = 0
        self.anim = 0
        self.anim_counter = 0
        self.limbs = {}               # miembro -> [inicio, fin, actual, sin bucle]
        self.need_redraw = True
        self.dest = (0, 0)
        self.destbox = 0
        self.destdir = -1
        self.curbox = 0
        self.leg_to = None
        self.talk_color = 15


class Room3:
    """La sala en uso: lo que necesita la VM."""

    def __init__(self, ix, rn):
        r = R.Room(ix, rn)
        self.r = r
        self.num = rn
        self.width, self.height = r.width, r.height
        self.file = r.file
        self.objects = r.objects
        self.local = dict(r.local_scripts)
        bx, matrix = r.boxes()
        self.boxes = bx
        self.box_flags = [b[9] for b in bx]
        self.matrix = matrix
        self.encd = r.encd_off
        self.excd = r.excd_off


class VM:
    def __init__(self, ix, seed=1):
        self.ix = ix
        self.rng = random.Random(seed)
        self.scripts = {}
        for i in range(len(ix.res['script'])):
            b = ix.resource('script', i)
            if b is not None:
                self.scripts[i] = b[4:]
        self.costumes = {}
        self.vars = [0] * NUM_VARS
        self.owner = list(ix.owner)
        self.state = list(ix.state)
        self.classes = list(ix.classes)
        self.slots = [Slot() for _ in range(NUM_SLOT)]
        self.locals = [[0] * NUM_LOCAL for _ in range(NUM_SLOT)]
        self.nest = []
        self.cur = 0xFF
        self.code = b''
        self.ptr = 0
        self.opcode = 0
        self.actors = [Actor(i) for i in range(NUM_ACTORS)]
        self.room = None
        self.cur_room = 0
        self.inventory = []            # (obj, bloque OBCD)
        self.new_names = {}
        self.sentence = []
        self.cut_stack = [dict(data=0, script=0, ptr=0)]
        self.cut_script_index = 0xFF
        self.have_msg = 0
        self.talk_delay = 0
        self.talk_actor = 0xFF
        self.pages = []
        self.keep_text = False
        self.user_put = 0
        self.cursor_state = 0
        self.cam_cur = self.cam_dest = 160
        self.cam_follows = 0
        self.cam_moving = False
        self.sound_left = {}
        self.music_jiffies = 0
        self.strings = {}
        self.verbs = {}
        self.frame = 0
        self.insn_total = 0
        self.halted = False
        # medidas
        self.f_ops = 0
        self.f_names = Counter()
        self.f_slots = set()
        self.f_events = Counter()
        self.max_slots = 0
        self.max_nest = 0
        self.loaded = dict(costume=set(), script=set(), sound=set())
        self.errors = Counter()

    # ------------------------------------------------------------------ lectura del script
    def byte(self):
        v = self.code[self.ptr]
        self.ptr += 1
        return v

    def word(self):
        v = self.code[self.ptr] | (self.code[self.ptr + 1] << 8)
        self.ptr += 2
        return v

    def sword(self):
        return s16(self.word())

    # ------------------------------------------------------------------ variables
    def read_var(self, var):
        if var & 0x2000:
            a = self.word()
            if a & 0x2000:
                var += self.read_var(a & ~0x2000)
            else:
                var += a & 0xFFF
            var &= ~0x2000
        if not (var & 0xF000):
            if var >= NUM_VARS:
                raise VMError('var %d' % var)
            return self.vars[var]
        if var & 0x8000:
            bit = var & 0xF
            v = (var >> 4) & 0xFF
            return 1 if self.vars[v] & (1 << bit) else 0
        if var & 0x4000:
            return self.locals[self.cur][var & 0xFFF] if self.cur != 0xFF else 0
        raise VMError('varbits %04X' % var)

    def write_var(self, var, value):
        value = s16(value)
        if not (var & 0xF000):
            if var >= NUM_VARS:
                raise VMError('var %d' % var)
            self.vars[var] = value
            return
        if var & 0x8000:
            bit = var & 0xF
            v = (var >> 4) & 0xFF
            if value:
                self.vars[v] |= (1 << bit)
            else:
                self.vars[v] &= ~(1 << bit)
            self.vars[v] = s16(self.vars[v])
            return
        if var & 0x4000:
            if self.cur != 0xFF:
                self.locals[self.cur][var & 0xFFF] = value
            return
        raise VMError('varbits w %04X' % var)

    def get_var(self):
        return self.read_var(self.word())

    def result_pos(self):
        r = self.word()
        if r & 0x2000:
            a = self.word()
            if a & 0x2000:
                r += self.read_var(a & ~0x2000)
            else:
                r += a & 0xFFF
            r &= ~0x2000
        self.res = r

    def set_result(self, v):
        self.write_var(self.res, v)

    def vb(self, mask, op=None):
        op = self.opcode if op is None else op
        return self.get_var() if op & mask else self.byte()

    def vw(self, mask, op=None):
        op = self.opcode if op is None else op
        return self.get_var() if op & mask else self.sword()

    def vararg(self):
        out = []
        while True:
            o = self.byte()
            if o == 0xFF:
                break
            out.append(self.vw(P1, o))
        return out + [0] * (NUM_LOCAL - len(out))

    def raw_string(self):
        s = bytearray()
        while True:
            c = self.byte()
            if c == 0:
                return bytes(s)
            s.append(c)
            if c == 0xFF:
                c = self.byte()
                s.append(c)
                if c not in (1, 2, 3, 8):
                    s.append(self.byte())
                    s.append(self.byte())

    def jrel(self, cond):
        off = self.sword()
        if not cond:
            self.ptr += off

    # ------------------------------------------------------------------ scripts
    def get_slot(self):
        for i in range(1, NUM_SLOT):
            if self.slots[i].status == SS_DEAD:
                return i
        raise VMError('sin ranuras')

    def update_ptr(self):
        if self.cur != 0xFF:
            self.slots[self.cur].offs = self.ptr

    def load_slot(self, i):
        self.code = self.slots[i].code
        self.ptr = self.slots[i].offs

    def run_nested(self, i):
        self.update_ptr()
        if len(self.nest) >= 15:
            raise VMError('anidamiento')
        if self.cur == 0xFF:
            entry = (0, 0xFF, 0xFF)
        else:
            s = self.slots[self.cur]
            entry = (s.number, s.where, self.cur)
        self.nest.append(entry)
        self.max_nest = max(self.max_nest, len(self.nest))
        self.max_slots = max(self.max_slots, sum(1 for s in self.slots if s.status != SS_DEAD))
        self.cur = i
        self.load_slot(i)
        self.execute()
        if self.nest:
            self.nest.pop()
        num, where, slot = entry
        if num:
            s = self.slots[slot]
            if s.number == num and s.where == where and s.status != SS_DEAD and s.freeze_count == 0:
                self.cur = slot
                self.load_slot(slot)
                return
        self.cur = 0xFF

    def start_slot(self, number, where, code, offs, args=None, fr=False, rec=False):
        i = self.get_slot()
        s = self.slots[i]
        s.number, s.where, s.code, s.offs = number, where, code, offs
        s.status = SS_RUNNING
        s.freeze_resistant, s.recursive = fr, rec
        s.freeze_count = s.delay = s.cutscene_override = 0
        self.locals[i] = list(args[:NUM_LOCAL]) if args else [0] * NUM_LOCAL
        self.run_nested(i)

    def run_script(self, script, fr=False, rec=False, args=None):
        if not script:
            return
        if not rec:
            self.stop_script(script)
        if script < R.NUM_GLOBAL_SCRIPTS:
            if script not in self.scripts:
                raise VMError('script %d' % script)
            self.loaded['script'].add(script)
            self.start_slot(script, WIO_GLOBAL, self.scripts[script], 0, args, fr, rec)
        else:
            if not self.room or script not in self.room.local:
                raise VMError('local %d no esta en la sala %d' % (script, self.cur_room))
            self.start_slot(script, WIO_LOCAL, self.room.file, self.room.local[script], args, fr, rec)

    def stop_script(self, script):
        if not script:
            return
        for i, s in enumerate(self.slots):
            if s.number == script and s.status != SS_DEAD and s.where in (WIO_GLOBAL, WIO_LOCAL):
                s.number = 0
                s.status = SS_DEAD
                if self.cur == i:
                    self.cur = 0xFF
        self.nest = [(0, 0xFF, 0xFF) if (n[0] == script and n[1] in (WIO_GLOBAL, WIO_LOCAL)) else n for n in self.nest]

    def stop_object_script(self, obj):
        if not obj:
            return
        for i, s in enumerate(self.slots):
            if s.number == obj and s.status != SS_DEAD and s.where in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT):
                s.number = 0
                s.status = SS_DEAD
                if self.cur == i:
                    self.cur = 0xFF
        self.nest = [(0, 0xFF, 0xFF) if (n[0] == obj and n[1] in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT)) else n
                     for n in self.nest]

    def is_script_running(self, script):
        return any(s.number == script and s.where in (WIO_GLOBAL, WIO_LOCAL) and s.status != SS_DEAD for s in self.slots)

    def is_script_in_use(self, script):
        return any(s.number == script for s in self.slots if s.status != SS_DEAD)

    def execute(self):
        while self.cur != 0xFF:
            self.opcode = self.byte()
            self.slots[self.cur].didexec = True
            self.f_slots.add((self.slots[self.cur].number, self.slots[self.cur].where))
            self.op(self.opcode)

    def op(self, opcode):
        self.opcode = opcode
        name = DIS.NAMES[opcode]
        self.f_ops += 1
        self.f_names[name] += 1
        self.insn_total += 1
        getattr(self, 'o_' + name)()

    def break_here(self):
        self.update_ptr()
        self.cur = 0xFF

    def decrease_delay(self, amount):
        for s in self.slots:
            if s.status == SS_PAUSED:
                s.delay -= amount
                if s.delay < 0:
                    s.status = SS_RUNNING
                    s.delay = 0

    def run_all_scripts(self):
        for s in self.slots:
            s.didexec = False
        self.cur = 0xFF
        for i in range(NUM_SLOT):
            s = self.slots[i]
            if s.status == SS_RUNNING and not s.didexec:
                self.cur = i
                self.load_slot(i)
                self.execute()

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
                if s.freeze_count <= 0:
                    s.freeze_count = 0
                    s.status &= 0x7F
        for st in self.sentence:
            if st['freeze'] > 0:
                st['freeze'] -= 1

    # ------------------------------------------------------------------ objetos
    def get_class(self, obj, cls):
        cls &= 0x7F
        cls = {32: 24, 31: 23, 30: 19, 29: 18}.get(cls, cls)     # traduccion de GF_SMALL_HEADER
        if not 0 <= obj < len(self.classes) or cls < 1:
            return False
        return bool(self.classes[obj] & (1 << (cls - 1)))

    def put_class(self, obj, cls, on):
        cls &= 0x7F
        cls = {32: 24, 31: 23, 30: 19, 29: 18}.get(cls, cls)
        if not 0 <= obj < len(self.classes) or cls < 1:
            return
        if on:
            self.classes[obj] |= (1 << (cls - 1))
        else:
            self.classes[obj] &= ~(1 << (cls - 1))

    def room_object(self, obj):
        if self.room:
            for o in self.room.objects:
                if o.id == obj:
                    return o
        return None

    def where_is(self, obj):
        if obj < 0 or obj >= len(self.owner):
            return WIO_NOT_FOUND
        if self.owner[obj] != OWNER_ROOM:
            if any(i == obj for i, _ in self.inventory):
                return WIO_INVENTORY
            return WIO_NOT_FOUND
        return WIO_ROOM if self.room_object(obj) else WIO_NOT_FOUND

    def obcd(self, obj):
        """(codigo, offset del OBCD) del objeto o None."""
        for i, blk in self.inventory:
            if i == obj:
                return blk, 0
        o = self.room_object(obj)
        if o:
            return self.room.file, o.obcd
        return None

    def verb_entry(self, obj, verb):
        if self.where_is(obj) == WIO_NOT_FOUND:
            return 0
        c = self.obcd(obj)
        if not c:
            return 0
        code, base = c
        p = base + 17
        while True:
            v = code[p]
            if v == 0:
                return 0
            if v == verb or v == 0xFF:
                return 17 + (code[p + 1] | (code[p + 2] << 8))
            p += 3

    def run_object_script(self, obj, entry, fr=False, rec=False, args=None):
        if not obj:
            return
        if not rec:
            self.stop_object_script(obj)
        where = self.where_is(obj)
        if where == WIO_NOT_FOUND:
            return
        code, base = self.obcd(obj)
        offs = self.verb_entry(obj, entry)
        if offs == 0:
            return
        self.get_slot()
        self.start_slot(obj, where, code, base + offs - 17, args, fr, rec)   # verb_entry suma los 17 de verboffs

    def obj_xy(self, obj):
        """getObjectXYPos (v3): punto de acercamiento y direccion."""
        o = self.room_object(obj)
        if not o:
            return 0, 0, 180
        return o.walk_x, o.walk_y, (270, 90, 180, 0)[o.actordir & 3]

    def obj_or_actor_xy(self, obj):
        if 0 < obj < NUM_ACTORS:
            a = self.actors[obj]
            if a.room == self.cur_room:
                return a.x, a.y
            return None
        w = self.where_is(obj)
        if w == WIO_NOT_FOUND:
            return None
        if w == WIO_INVENTORY:
            a = self.actors[self.owner[obj]] if self.owner[obj] < NUM_ACTORS else None
            return (a.x, a.y) if a and a.room == self.cur_room else None
        x, y, _ = self.obj_xy(obj)
        return x, y

    def find_object(self, x, y):
        if not self.room:
            return 0
        for o in reversed(self.room.objects):
            if o.id < 1 or self.get_class(o.id, 32):
                continue
            if o.x <= x < o.x + o.width and o.y <= y < o.y + o.height:
                return o.id
        return 0

    # ------------------------------------------------------------------ cajas y actores
    def box_quad(self, k):
        b = self.room.boxes[k]
        return (b[0], b[1]), (b[2], b[3]), (b[4], b[5]), (b[6], b[7])     # ul, ur, lr, ll

    @staticmethod
    def in_quad(q, x, y):
        """checkXYInBoxBounds: el punto esta dentro del cuadrilatero (convexo) ul, ur, lr, ll."""
        def side(a, b):
            return (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
        s = [side(q[i], q[(i + 1) % 4]) for i in range(4)]
        return all(v >= 0 for v in s) or all(v <= 0 for v in s)

    @staticmethod
    def closest_on_line(s, e, p):
        sx, sy = s
        ex, ey = e
        px, py = p
        lx, ly = ex - sx, ey - sy
        if lx == 0 and ly == 0:
            return sx, sy
        t = ((px - sx) * lx + (py - sy) * ly) / float(lx * lx + ly * ly)
        t = max(0.0, min(1.0, t))
        return int(round(sx + t * lx)), int(round(sy + t * ly))

    def closest_on_box(self, k, x, y):
        q = self.box_quad(k)
        best, out = None, (x, y)
        for i in range(4):
            px, py = self.closest_on_line(q[i], q[(i + 1) % 4], (x, y))
            d = (px - x) ** 2 + (py - y) ** 2
            if best is None or d < best:
                best, out = d, (px, py)
        return out

    def adjust_xy(self, x, y):
        if not self.room or not self.room.boxes:
            return x, y, 0
        best, res = None, (x, y, 0)
        for k in range(len(self.room.boxes) - 1, -1, -1):
            if self.room.box_flags[k] & BOX_INVISIBLE:
                continue
            if self.in_quad(self.box_quad(k), x, y):
                return x, y, k
            px, py = self.closest_on_box(k, x, y)
            d = (px - x) ** 2 + (py - y) ** 2
            if best is None or d < best:
                best, res = d, (px, py, k)
        return res

    def next_box(self, frm, to):
        """getNextBox de v3: por cada caja, ternas (desde, hasta, siguiente) acabadas en 0xFF."""
        if frm == to:
            return to
        m = self.room.matrix
        p = 0
        for _ in range(frm):
            while p < len(m) and m[p] != 0xFF:
                p += 3
            p += 1
        dest = -1
        while p + 2 < len(m) and m[p] != 0xFF:
            if m[p] <= to <= m[p + 1]:
                dest = m[p + 2] if m[p + 2] < 0x80 else m[p + 2] - 256
            p += 3
        return dest

    def costume(self, c):
        if c not in self.costumes:
            import costume2
            data = self.ix.resource('costume', c)
            try:
                self.costumes[c] = costume2.Costume(data) if data else None
            except Exception:
                self.costumes[c] = None
            self.loaded['costume'].add(c)
        return self.costumes[c]

    def dir_index(self, facing):
        return {270: 0, 90: 1, 180: 2, 0: 3}.get(facing, 2)       # newDirToOldDir (izq, der, abajo, arriba)

    def start_anim(self, a, frame):
        """startAnimActor + cost.reset/loadCostume: los miembros que nombra la animacion frame*4 + direccion."""
        a.frame = frame
        a.anim = frame * 4 + self.dir_index(a.facing)
        c = self.costume(a.costume) if a.costume else None
        if c:
            for limb, v in c.anim_limbs(a.anim).items():
                if v is None:
                    a.limbs.pop(limb, None)
                else:
                    s, e, nl = v
                    a.limbs[limb] = [s, e, s, nl]
        a.need_redraw = True

    def put_actor(self, a, x, y, room):
        a.x, a.y = x, y
        a.room = room
        a.need_redraw = True
        if room == self.cur_room and self.cur_room:
            if not a.visible:
                a.visible = True
                if a.costume:
                    self.start_anim(a, a.init_frame)
            ax, ay, box = self.adjust_xy(x, y) if not a.ignore_boxes else (x, y, 0)
            a.walkbox = box
        elif a.visible and room != self.cur_room:
            a.visible = False
        a.moving = 0

    def set_direction(self, a, d):
        if a.facing != d:
            a.facing = d
            if a.costume and a.visible:
                self.start_anim(a, a.frame)

    def start_walk(self, a, x, y, d):
        if a.room != self.cur_room:
            a.x, a.y = x, y
            return
        if a.ignore_boxes:
            box = 0
        else:
            x, y, box = self.adjust_xy(x, y)
        if (a.x, a.y) == (x, y) and (d == -1 or d == a.facing):
            return
        a.dest, a.destbox, a.destdir = (x, y), box, d
        a.curbox = a.walkbox
        a.moving = MF_NEW_LEG
        a.leg_to = None

    def walk_actor(self, a):
        if not a.moving:
            return
        if a.leg_to is None:
            # nueva etapa: hasta el destino si ya esta en su caja, si no hasta la caja siguiente
            if a.ignore_boxes or not self.room.boxes or a.walkbox == a.destbox:
                a.leg_to = a.dest
                a.moving |= MF_LAST_LEG
            else:
                nb = self.next_box(a.walkbox, a.destbox)
                if nb < 0 or nb >= len(self.room.boxes):
                    a.leg_to = a.dest
                    a.moving |= MF_LAST_LEG
                else:
                    a.leg_to = self.closest_on_box(nb, a.x, a.y)
                    a.curbox = nb
            dx, dy = a.leg_to[0] - a.x, a.leg_to[1] - a.y
            nf = (90 if dx > 0 else 270) if abs(dx) * 3 > abs(dy) * 2 * 2 else (180 if dy > 0 else 0)  # _facingXYratio de v3
            if a.frame != a.walk_frame or a.facing != nf:
                a.facing = nf
                self.start_anim(a, a.walk_frame)
            return
        tx, ty = a.leg_to
        if a.x != tx:
            a.x += max(-a.speedx, min(a.speedx, tx - a.x))
        if a.y != ty:
            a.y += max(-a.speedy, min(a.speedy, ty - a.y))
        a.need_redraw = True
        if (a.x, a.y) == (tx, ty):
            if a.moving & MF_LAST_LEG or a.ignore_boxes:
                a.moving = 0
                self.start_anim(a, a.stand_frame)
                if a.destdir != -1:
                    self.set_direction(a, a.destdir)
            else:
                a.walkbox = a.curbox
                a.leg_to = None

    def animate(self, a):
        """animateCostume: los miembros con bucle avanzan cada (animSpeed + 1) fotogramas."""
        if a.anim_progress < a.anim_speed:
            a.anim_progress += 1
            return False
        a.anim_progress = 0
        a.anim_counter += 1
        changed = False
        for limb, v in a.limbs.items():
            s, e, cur, nl = v
            if s == e:
                continue
            if not nl:
                cur = s if cur >= e else cur + 1
            elif cur != e:
                cur += 1
            if cur != v[2]:
                v[2] = cur
                changed = True
        return changed

    def actor_cells(self, a):
        """Pixeles de las celdas que se dibujan del actor (w*h de cada miembro) en su paso actual."""
        c = self.costume(a.costume) if a.costume else None
        if not c:
            return 0
        tot = 0
        for limb, (s, e, cur, nl) in a.limbs.items():
            try:
                code = c.b[c.cmds + cur] & 0x7F
                if code >= 0x79:                       # 0x7B: nada; 0x79/0x7A no son imagenes
                    continue
                p = c.limb_tab[limb]
                q = c.b[p + code * 2] | (c.b[p + code * 2 + 1] << 8)
                w, h = c.b[q] | (c.b[q + 1] << 8), c.b[q + 2] | (c.b[q + 3] << 8)
                if w <= 255 and h <= 255:
                    tot += w * h
            except IndexError:
                pass
        return tot

    # ------------------------------------------------------------------ sala
    def kill_room_scripts(self):
        for s in self.slots:
            if s.where in (WIO_ROOM, WIO_FLOBJECT, WIO_LOCAL):
                s.status = SS_DEAD
                s.number = 0

    def start_scene(self, room):
        self.stop_talk()
        if self.cur != 0xFF and self.slots[self.cur].where in (WIO_ROOM, WIO_FLOBJECT, WIO_LOCAL):
            self.cur = 0xFF
        # runExitScript
        if self.vars[VAR_EXIT_SCRIPT]:
            self.run_script(self.vars[VAR_EXIT_SCRIPT])
        if self.room and self.room.excd:
            self.start_slot(EXCD, WIO_ROOM, self.room.file, self.room.excd)
        if self.vars[VAR_EXIT_SCRIPT2]:
            self.run_script(self.vars[VAR_EXIT_SCRIPT2])
        self.kill_room_scripts()
        for a in self.actors[1:]:
            a.visible = False
        self.vars[VAR_ROOM] = room
        self.cur_room = room
        self.vars[VAR_ROOM_RESOURCE] = room
        self.f_events['cambio_sala'] += 1
        if room == 0:
            self.room = None
            return
        self.room = Room3(self.ix, room)
        self.vars[VAR_CAMERA_MIN_X] = 160
        self.vars[VAR_CAMERA_MAX_X] = self.room.width - 160
        self.cam_cur = self.cam_dest = 160
        self.cam_follows = 0
        for a in self.actors[1:]:                     # showActors
            if a.room == room:
                a.visible = True
                if a.costume:
                    self.start_anim(a, a.init_frame)
        if self.vars[VAR_ENTRY_SCRIPT]:
            self.run_script(self.vars[VAR_ENTRY_SCRIPT])
        if self.room.encd:
            self.start_slot(ENCD, WIO_ROOM, self.room.file, self.room.encd)
        if self.vars[VAR_ENTRY_SCRIPT2]:
            self.run_script(self.vars[VAR_ENTRY_SCRIPT2])

    # ------------------------------------------------------------------ mensajes
    def stop_talk(self):
        self.have_msg = 0
        self.talk_delay = 0
        self.pages = []
        if self.talk_actor not in (0, 0xFF) and self.talk_actor < NUM_ACTORS:
            a = self.actors[self.talk_actor]
            if a.room == self.cur_room and a.costume:
                self.start_anim(a, a.talk_stop)
        self.talk_actor = 0xFF

    def actor_talk(self, actor, msg):
        if actor == 0xFF:
            if not self.keep_text:
                self.stop_talk()
            self.talk_actor = 0xFF
        else:
            a = self.actors[actor] if actor < NUM_ACTORS else None
            if a and a.room == self.cur_room:
                if not self.keep_text:
                    self.stop_talk()
                self.talk_actor = actor
                if a.costume:
                    self.start_anim(a, a.talk_start)
            else:
                return
        pages, cur = [], 0
        i = 0
        while i < len(msg):
            c = msg[i]
            if c == 0xFF:
                code = msg[i + 1]
                if code == 3:
                    pages.append(cur)
                    cur = 0
                i += 2 if code in (1, 2, 3, 8) else 4
                if code in (4, 5, 6, 7):
                    cur += 4
                continue
            cur += 1
            i += 1
        pages.append(cur)
        self.pages = pages
        self.talk_delay = 0
        self.have_msg = 0xFF
        self.vars[VAR_HAVE_MSG] = 0xFF
        self.vars[VAR_TALK_ACTOR] = actor
        self.f_events['mensaje'] += 1

    def display_dialog(self):
        """CHARSET_1 reducido: cada pagina dura 60 + VAR_CHARINC por caracter."""
        if self.talk_delay:
            return
        if self.have_msg == 1 and not self.pages:
            self.stop_talk()
            return
        if not self.pages:
            return
        n = self.pages.pop(0)
        self.talk_delay = 60 + n * max(0, self.vars[VAR_CHARINC])
        self.have_msg = 1

    # ------------------------------------------------------------------ bucle principal
    def scumm_loop(self, delta):
        self.vars[VAR_TIMER] = delta
        self.vars[VAR_TIMER_TOTAL] = s16(self.vars[VAR_TIMER_TOTAL] + delta)
        for v in (VAR_TMR_1, VAR_TMR_2, VAR_TMR_3, 39, 40, 41):
            self.vars[v] = s16(self.vars[v] + delta)
        if delta > 15:
            delta = 15
        self.decrease_delay(delta)
        self.talk_delay = max(0, self.talk_delay - delta)
        for k in list(self.sound_left):
            self.sound_left[k] -= delta
            if self.sound_left[k] <= 0:
                del self.sound_left[k]
        self.display_dialog()
        # Sound::updateMusicTimer: el reproductor cuenta el tiempo de la cancion (aqui, 1 cada 6 jiffies)
        self.music_jiffies += delta
        self.vars[VAR_MUSIC_TIMER] = self.music_jiffies // 6
        self.vars[VAR_CAMERA_POS_X] = self.cam_cur
        self.vars[VAR_HAVE_MSG] = self.have_msg
        self.run_all_scripts()
        self.check_exec_verbs()
        self.check_sentence()
        if self.cur_room:
            for a in self.actors[1:]:
                if a.room == self.cur_room:
                    self.walk_actor(a)
            self.move_camera()
            for a in self.actors[1:]:
                if a.room == self.cur_room and a.visible and a.costume:
                    if self.animate(a):
                        a.need_redraw = True

    def check_exec_verbs(self):
        if self.pending is None:
            return
        click, self.pending = self.pending, None
        if self.user_put <= 0:
            return
        x, y = click
        self.vars[VAR_VIRT_MOUSE_X] = x
        self.vars[VAR_VIRT_MOUSE_Y] = y
        self.vars[VAR_MOUSE_X] = x - (self.cam_cur - 160)
        self.vars[VAR_MOUSE_Y] = y + 8
        self.f_events['clic'] += 1
        self.run_input_script(2, 0, 0)

    def run_input_script(self, area, val, mode):
        args = [area, val, mode] + [0] * (NUM_LOCAL - 3)
        if self.vars[VAR_VERB_SCRIPT]:
            self.run_script(self.vars[VAR_VERB_SCRIPT], args=args)

    def check_sentence(self):
        ss = self.vars[VAR_SENTENCE_SCRIPT]
        for s in self.slots:
            if s.number == ss and s.status != SS_DEAD and s.freeze_count == 0:
                return
        if not self.sentence or self.sentence[-1]['freeze']:
            return
        st = self.sentence.pop()
        if st['prep'] and st['b'] == st['a']:
            return
        self.cur = 0xFF
        if ss:
            self.run_script(ss, args=[st['verb'], st['a'], st['b']] + [0] * (NUM_LOCAL - 3))

    def move_camera(self):
        if self.cam_follows:
            a = self.actors[self.cam_follows]
            if a.room == self.cur_room and abs(a.x - self.cam_cur) > 80:   # ScummVM: fuera de la franja central
                self.cam_dest = a.x
        lo, hi = self.vars[VAR_CAMERA_MIN_X], self.vars[VAR_CAMERA_MAX_X]
        self.cam_dest = max(lo, min(hi, self.cam_dest)) if hi >= lo else lo
        if self.cam_cur // 8 != self.cam_dest // 8:
            step = 8 if self.cam_dest > self.cam_cur else -8
            self.cam_cur += step
            self.f_events['scroll_columna'] += 1
        else:
            self.cam_cur = self.cam_dest

    # ------------------------------------------------------------------ opcodes (los de scumm3dis.NAMES)
    def o_stopObjectCode(self):
        s = self.slots[self.cur]
        if s.where not in (WIO_GLOBAL, WIO_LOCAL):
            s.number = 0
        s.status = SS_DEAD
        self.cur = 0xFF

    def o_breakHere(self):
        self.break_here()

    def o_endCutscene(self):
        s = self.slots[self.cur]
        if s.cutscene_override > 0:
            s.cutscene_override -= 1
        top = self.cut_stack[-1] if len(self.cut_stack) > 1 else self.cut_stack[0]
        args = [top['data']] + [0] * (NUM_LOCAL - 1)
        self.vars[VAR_OVERRIDE] = 0
        if len(self.cut_stack) > 1:
            self.cut_stack.pop()
        if self.vars[VAR_CUTSCENE_END_SCRIPT]:
            self.run_script(self.vars[VAR_CUTSCENE_END_SCRIPT], args=args)

    def o_cutscene(self):
        args = self.vararg()
        scr = self.cur
        self.slots[scr].cutscene_override += 1
        self.cut_stack.append(dict(data=args[0], script=0, ptr=0))
        self.cut_script_index = scr
        if self.vars[VAR_CUTSCENE_START_SCRIPT]:
            self.run_script(self.vars[VAR_CUTSCENE_START_SCRIPT], args=args)
        self.cut_script_index = 0xFF

    def o_beginOverride(self):
        if self.byte() != 0:
            self.cut_stack[-1]['ptr'] = self.ptr
            self.cut_stack[-1]['script'] = self.cur
            self.byte()
            self.word()
        else:
            self.cut_stack[-1]['ptr'] = 0
            self.vars[VAR_OVERRIDE] = 0

    def o_stopMusic(self):
        self.sound_left.clear()

    def o_waitForSentence(self):
        if self.sentence:
            if self.sentence[-1]['freeze'] and not self.is_script_in_use(self.vars[VAR_SENTENCE_SCRIPT]):
                return
        elif not self.is_script_in_use(self.vars[VAR_SENTENCE_SCRIPT]):
            return
        self.ptr -= 1
        self.break_here()

    def o_wait(self):                                  # Indy3: espera al mensaje
        if self.vars[VAR_HAVE_MSG]:
            self.ptr -= 1
            self.break_here()

    def o_waitForActor(self):
        old = self.ptr - 1
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        if a.moving:
            self.ptr = old
            self.break_here()

    def o_putActor(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        x, y = self.vw(P2), self.vw(P3)
        self.put_actor(a, x, y, a.room)

    def o_putActorInRoom(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        room = self.vb(P2)
        if a.visible and self.cur_room != room and self.talk_actor == a.num:
            self.stop_talk()
        a.room = room
        if not room:
            a.x = a.y = 0
        if room == self.cur_room and room:
            self.put_actor(a, a.x, a.y, room)
        else:
            a.visible = False

    def o_putActorAtObject(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        obj = self.vw(P2)
        if self.where_is(obj) != WIO_NOT_FOUND:
            x, y = self.obj_or_actor_xy(obj) or (240, 120)
        else:
            x, y = 240, 120
        self.put_actor(a, x, y, a.room)

    def o_startMusic(self):
        s = self.vb(P1)
        self.sound_left[s] = 600
        self.loaded['sound'].add(s)
        self.music_jiffies = 0

    def o_startSound(self):
        s = self.vb(P1)
        self.vars[VAR_LAST_SOUND] = s
        self.sound_left[s] = 60
        self.loaded['sound'].add(s)
        self.f_events['sonido'] += 1
        snd = self.ix.resource('sound', s)
        if snd and len(snd) > 1000:                   # una cancion: arranca el temporizador de musica
            self.music_jiffies = 0
            self.sound_left[s] = 3600

    def o_stopSound(self):
        self.sound_left.pop(self.vb(P1), None)

    def o_isSoundRunning(self):
        self.result_pos()
        s = self.vb(P1)
        self.set_result(1 if s and s in self.sound_left else 0)

    def _actor_get(self, f):
        self.result_pos()
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        self.set_result(f(a))

    def o_getActorRoom(self): self._actor_get(lambda a: a.room)
    def o_getActorElevation(self): self._actor_get(lambda a: a.elevation)
    def o_getActorMoving(self): self._actor_get(lambda a: a.moving)
    def o_getActorFacing(self): self._actor_get(lambda a: self.dir_index(a.facing))
    def o_getActorCostume(self): self._actor_get(lambda a: a.costume)
    def o_getActorWidth(self): self._actor_get(lambda a: a.width)
    def o_getActorWalkBox(self): self._actor_get(lambda a: a.walkbox)
    def o_getAnimCounter(self): self._actor_get(lambda a: a.anim_counter)

    def o_getActorX(self):
        self.result_pos()
        n = self.vb(P1)
        p = self.obj_or_actor_xy(n)
        self.set_result(p[0] if p else -1)

    def o_getActorY(self):
        self.result_pos()
        n = self.vb(P1)
        p = self.obj_or_actor_xy(n)
        self.set_result(p[1] if p else -1)

    def o_getRandomNr(self):
        self.result_pos()
        self.set_result(self.rng.randint(0, max(0, self.vb(P1))))

    def o_isScriptRunning(self):
        self.result_pos()
        self.set_result(1 if self.is_script_running(self.vb(P1)) else 0)

    def o_getInventoryCount(self):
        self.result_pos()
        who = self.vb(P1)
        self.set_result(sum(1 for o, _ in self.inventory if self.owner[o] == who))

    def o_getStringWidth(self):
        self.result_pos()
        self.vb(P1)
        self.set_result(0)

    def _arith(self, f):
        self.result_pos()
        a = self.vw(P1)
        self.set_result(f(self.read_var(self.res), a))

    def o_move(self):
        self.result_pos()
        self.set_result(self.vw(P1))

    def o_add(self): self._arith(lambda r, a: r + a)
    def o_subtract(self): self._arith(lambda r, a: r - a)
    def o_multiply(self): self._arith(lambda r, a: r * a)
    def o_divide(self): self._arith(lambda r, a: cdiv(r, a) if a else 0)
    def o_and(self): self._arith(lambda r, a: r & a)
    def o_or(self): self._arith(lambda r, a: r | a)

    def o_increment(self):
        self.result_pos()
        self.set_result(self.read_var(self.res) + 1)

    def o_decrement(self):
        self.result_pos()
        self.set_result(self.read_var(self.res) - 1)

    def o_getObjectOwner(self):
        self.result_pos()
        o = self.vw(P1)
        self.set_result(self.owner[o] if 0 <= o < len(self.owner) else 0)

    def o_getClosestObjActor(self):
        self.result_pos()
        act = self.vw(P1)
        p = self.obj_or_actor_xy(act)
        best, res = 0xFF, 0xFF
        lo, hi = self.vars[VAR_ACTOR_RANGE_MIN], self.vars[VAR_ACTOR_RANGE_MAX]
        for o in range(hi, lo - 1, -1):
            if o == act or not 0 < o < NUM_ACTORS:
                continue
            q = self.obj_or_actor_xy(o)
            if p and q:
                d = max(abs(p[0] - q[0]), abs(p[1] - q[1]))
                if d < best:
                    best, res = d, o
        self.set_result(res)

    def o_actorFromPos(self):
        self.result_pos()
        x, y = self.vw(P1), self.vw(P2)
        res = 0
        for a in self.actors[1:]:
            if a.room == self.cur_room and a.visible and abs(a.x - x) < 12 and a.y - 60 <= y <= a.y:
                res = a.num
        self.set_result(res)

    def o_getDist(self):
        self.result_pos()
        o1, o2 = self.vw(P1), self.vw(P2)
        p, q = self.obj_or_actor_xy(o1), self.obj_or_actor_xy(o2)
        self.set_result(max(abs(p[0] - q[0]), abs(p[1] - q[1])) if p and q else 0xFF)

    def o_getVerbEntrypoint(self):
        self.result_pos()
        a, b = self.vw(P1), self.vw(P2)
        self.set_result(self.verb_entry(a, b))

    def o_findObject(self):
        self.result_pos()
        x, y = self.vb(P1), self.vb(P2)
        self.set_result(self.find_object(x, y))

    def o_findInventory(self):
        self.result_pos()
        who, idx = self.vb(P1), self.vb(P2)
        mine = [o for o, _ in self.inventory if self.owner[o] == who]
        self.set_result(mine[idx - 1] if 0 < idx <= len(mine) else 0)

    def _cmp(self, f):
        a = s16(self.get_var())
        b = s16(self.vw(P1))
        self.jrel(f(a, b))

    def o_isEqual(self): self._cmp(lambda a, b: b == a)
    def o_isNotEqual(self): self._cmp(lambda a, b: b != a)
    def o_isGreater(self): self._cmp(lambda a, b: b > a)
    def o_isGreaterEqual(self): self._cmp(lambda a, b: b >= a)
    def o_isLess(self): self._cmp(lambda a, b: b < a)
    def o_isLessEqual(self): self._cmp(lambda a, b: b <= a)

    def o_equalZero(self):
        self.jrel(self.get_var() == 0)

    def o_notEqualZero(self):
        self.jrel(self.get_var() != 0)

    def o_jumpRelative(self):
        self.jrel(False)

    def o_drawObject(self):
        obj, x, y = self.vw(P1), self.vw(P2), self.vw(P3)
        o = self.room_object(obj)
        if o:
            if 0 <= obj < len(self.state):
                self.state[obj] = 1
            self.f_events['dibuja_objeto'] += 1
            self.f_events['dibuja_objeto_px'] += o.width * o.height

    def o_setState(self):
        obj, st = self.vw(P1), self.vb(P2)
        if 0 <= obj < len(self.state):
            self.state[obj] = st
        o = self.room_object(obj)
        if o:
            self.f_events['dibuja_objeto'] += 1
            self.f_events['dibuja_objeto_px'] += o.width * o.height

    def o_ifState(self):
        a, b = self.vw(P1), self.vb(P2)
        self.jrel(0 <= a < len(self.state) and self.state[a] == b)

    def o_ifNotState(self):
        a, b = self.vw(P1), self.vb(P2)
        self.jrel(not (0 <= a < len(self.state)) or self.state[a] != b)

    def o_setOwnerOf(self):
        obj, owner = self.vw(P1), self.vb(P2)
        if 0 <= obj < len(self.owner):
            self.owner[obj] = owner
            if owner != OWNER_ROOM and not any(i == obj for i, _ in self.inventory) and owner:
                c = self.obcd(obj)
                if c:
                    code, base = c
                    self.inventory.append((obj, code[base:base + (code[base] | (code[base + 1] << 8))]))
            if owner == 0:
                self.inventory = [(i, b) for i, b in self.inventory if i != obj]

    def o_faceActor(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        obj = self.vw(P2)
        p = self.obj_or_actor_xy(obj)
        if p and a.room == self.cur_room:
            dx, dy = p[0] - a.x, p[1] - a.y
            self.set_direction(a, (90 if dx > 0 else 270) if abs(dx) > abs(dy) else (180 if dy > 0 else 0))

    def o_animateActor(self):
        """Actor::animateActor (version < 7): chore = 0x3F - anim / 4 + 2; 2 parar, 3 direccion ya, 4 girar; si no, el fotograma anim."""
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        anim = self.vb(P2)
        chore = 0x3F - (anim >> 2) + 2
        d = (270, 90, 180, 0)[anim & 3]
        if chore == 2:
            if a.room == self.cur_room:
                if a.costume:
                    self.start_anim(a, a.stand_frame)
                a.moving = 0
        elif chore in (3, 4):
            if a.room == self.cur_room:
                a.moving &= ~MF_TURN
            self.set_direction(a, d)
        elif a.room == self.cur_room and a.costume:
            self.start_anim(a, anim)

    def o_startScript(self):
        op = self.opcode
        script = self.vb(P1)
        args = self.vararg()
        self.run_script(script, bool(op & 0x20), bool(op & 0x40), args)

    def o_chainScript(self):
        script = self.vb(P1)
        args = self.vararg()
        cur = self.cur
        self.slots[cur].number = 0
        self.slots[cur].status = SS_DEAD
        self.cur = 0xFF
        self.run_script(script, False, False, args)

    def o_startObject(self):
        obj, script = self.vw(P1), self.vb(P2)
        args = self.vararg()
        self.run_object_script(obj, script, False, False, args)

    def o_stopScript(self):
        s = self.vb(P1)
        if not s:
            self.o_stopObjectCode()
        else:
            self.stop_script(s)

    def o_stopObjectScript(self):
        self.stop_object_script(self.vw(P1))

    def o_freezeScripts(self):
        s = self.vb(P1)
        if s:
            self.freeze_scripts(s)
        else:
            self.unfreeze_scripts()

    def o_resourceRoutines(self):
        o = self.byte()
        if o != 17:
            resid = self.vb(P1, o)
        k = o & 0x3F
        if k == 20:
            self.vw(P2, o)
        elif k in (35, 37):
            self.vb(P2, o)
        elif k == 36:
            self.vb(P2, o)
            self.byte()
        if k in (1, 2, 3):
            self.loaded[('script', 'sound', 'costume')[k - 1]].add(resid)
            self.f_events['carga_recurso'] += 1

    def o_walkActorToActor(self):
        n1, n2 = self.vb(P1), self.vb(P2)
        dist = self.byte()
        a, b = self.actors[n1 % NUM_ACTORS], self.actors[n2 % NUM_ACTORS]
        if a.room != self.cur_room or b.room != self.cur_room:
            return
        if dist == 0xFF:
            dist = 24
        x = b.x + (dist if b.x < a.x else -dist)
        self.start_walk(a, x, b.y, -1)

    def o_walkActorToObject(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        obj = self.vw(P2)
        if self.where_is(obj) != WIO_NOT_FOUND:
            x, y, d = self.obj_xy(obj)
            self.start_walk(a, x, y, d)

    def o_walkActorTo(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        x, y = self.vw(P2), self.vw(P3)
        self.start_walk(a, x, y, -1)

    def o_panCameraTo(self):
        self.cam_dest = self.vw(P1)
        self.cam_follows = 0

    def o_setCameraAt(self):
        self.cam_cur = self.cam_dest = self.vw(P1)
        self.cam_follows = 0

    def o_actorFollowCamera(self):
        n = self.vb(P1)
        self.cam_follows = n
        a = self.actors[n % NUM_ACTORS]
        if a.room == self.cur_room:
            self.cam_dest = a.x

    def o_debug(self): self.vw(P1)

    def o_pickupObject(self):                          # o4_pickupObject
        obj = self.vw(P1)
        if obj < 1 or self.where_is(obj) == WIO_INVENTORY:
            return
        c = self.obcd(obj)
        if c:
            code, base = c
            self.inventory.append((obj, code[base:base + (code[base] | (code[base + 1] << 8))]))
        self.owner[obj] = self.vars[VAR_EGO]
        self.put_class(obj, 32, True)
        self.state[obj] = 1
        if self.vars[VAR_INVENTORY_SCRIPT]:
            self.run_script(self.vars[VAR_INVENTORY_SCRIPT], args=[1] + [0] * (NUM_LOCAL - 1))

    def o_actorOps(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            o = (o & 0xE0) | DIS.ACTOROPS_CONVERT[(o & 0x1F) - 1]
            k = o & 0x1F
            if k == 0:
                self.vb(P1, o)
            elif k == 1:
                c = self.vb(P1, o)
                a.costume = c
                if c:
                    self.costume(c)
                if a.visible and c:
                    self.start_anim(a, a.init_frame)
            elif k == 2:
                a.speedx, a.speedy = self.vb(P1, o), self.vb(P2, o)
            elif k == 3:
                self.vb(P1, o)
            elif k == 4:
                a.walk_frame = self.vb(P1, o)
            elif k == 5:
                a.talk_start, a.talk_stop = self.vb(P1, o), self.vb(P2, o)
            elif k == 6:
                a.stand_frame = self.vb(P1, o)
            elif k == 7:
                self.vb(P1, o); self.vb(P2, o); self.vb(P3, o)
            elif k == 8:
                a.init()
            elif k == 9:
                a.elevation = self.vw(P1, o)
            elif k == 10:
                a.init_frame, a.walk_frame, a.stand_frame, a.talk_start, a.talk_stop = 1, 2, 3, 4, 5
            elif k == 11:
                self.vb(P1, o); self.vb(P2, o)
            elif k == 12:
                a.talk_color = self.vb(P1, o)
            elif k == 13:
                self.raw_string()
            elif k == 14:
                a.init_frame = self.vb(P1, o)
            elif k == 16:
                a.width = self.vb(P1, o)
            elif k == 17:
                self.vb(P1, o); self.vb(P2, o)
            elif k == 18:
                pass
            elif k == 19:
                self.vb(P1, o)
            elif k in (20, 21):
                a.ignore_boxes = not (o & 1)
            elif k == 22:
                a.anim_speed = self.vb(P1, o)
                a.anim_progress = 0
            elif k == 23:
                self.vb(P1, o)
            else:
                raise VMError('actorOps %d' % k)

    def decode_parse_string(self, actor):
        slot = {252: 3, 253: 2, 254: 1}.get(actor, 0)
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            k = o & 0x0F
            if k == 0:
                self.vw(P1, o); self.vw(P2, o)
            elif k == 1:
                self.vb(P1, o)
            elif k == 2:
                self.vw(P1, o)
            elif k == 3:
                self.vw(P1, o); self.vw(P2, o)
            elif k in (4, 7):
                pass
            elif k == 6:
                self.vw(P1, o)
            elif k == 8:
                self.vw(P1, o); self.vw(P2, o)
            elif k == 15:
                msg = self.raw_string()
                if slot == 0:
                    self.actor_talk(actor, msg)
                else:
                    self.f_events['texto'] += 1
                return
            else:
                raise VMError('parse_string %d' % k)

    def o_print(self):
        self.decode_parse_string(self.vb(P1))

    def o_printEgo(self):
        self.decode_parse_string(self.vars[VAR_EGO])

    def o_doSentence(self):
        verb = self.vb(P1)
        if verb == 0xFE:
            self.sentence = []
            self.stop_script(self.vars[VAR_SENTENCE_SCRIPT])
            return
        a, b = self.vw(P2), self.vw(P3)
        if len(self.sentence) < NUM_SENTENCE:
            self.sentence.append(dict(verb=verb, a=a, b=b, prep=b != 0, freeze=0))

    def o_ifClassOfIs(self):
        obj = self.vw(P1)
        cond = True
        while True:
            o = self.byte()
            if o == 0xFF:
                break
            cls = self.vw(P1, o)
            b = self.get_class(obj, cls)
            if (cls & 0x80 and not b) or (not (cls & 0x80) and b):
                cond = False
        self.jrel(cond)

    def o_setClass(self):
        obj = self.vw(P1)
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            cls = self.vw(P1, o)
            if cls == 0:
                if 0 <= obj < len(self.classes):
                    self.classes[obj] = 0
            else:
                self.put_class(obj, cls, bool(cls & 0x80))

    def o_isActorInBox(self):
        a = self.actors[self.vb(P1) % NUM_ACTORS]
        box = self.vb(P2)
        ok = bool(self.room and box < len(self.room.boxes) and self.in_quad(self.box_quad(box), a.x, a.y))
        self.jrel(ok)

    def o_loadRoomWithEgo(self):
        obj, room = self.vw(P1), self.vb(P2)
        x, y = self.sword(), self.sword()
        a = self.actors[self.vars[VAR_EGO] % NUM_ACTORS]
        a.room = room
        self.vars[VAR_WALKTO_OBJ] = obj
        self.start_scene(room)
        self.vars[VAR_WALKTO_OBJ] = 0
        if self.where_is(obj) == WIO_ROOM:
            ox, oy, d = self.obj_xy(obj)
            self.put_actor(a, ox, oy, self.cur_room)
            self.set_direction(a, (d + 180) % 360)
        a.moving = 0
        self.cam_cur = self.cam_dest = a.x
        self.cam_follows = a.num
        self.sentence = []
        if x != -1 and x != 0x7FFF:
            self.start_walk(a, x, y, -1)

    def o_loadRoom(self):
        room = self.vb(P1)
        if room != self.cur_room:
            self.start_scene(room)

    def o_setVarRange(self):
        self.result_pos()
        n = self.byte()
        while n:
            b = self.sword() if self.opcode & 0x80 else self.byte()
            self.set_result(b)
            self.res += 1
            n -= 1

    def o_stringOps(self):
        o = self.byte()
        k = o & 0x1F
        if k == 1:
            a = self.vb(P1, o)
            self.strings[a] = self.raw_string()
        elif k == 2:
            a, b = self.vb(P1, o), self.vb(P2, o)
            self.strings[a] = self.strings.get(b, b'')
        elif k == 3:
            a, b, c = self.vb(P1, o), self.vb(P2, o), self.vb(P3, o)
            s = bytearray(self.strings.get(a, b''))
            while len(s) <= b:
                s.append(0)
            s[b] = c & 0xFF
            self.strings[a] = bytes(s)
        elif k == 4:
            self.result_pos()
            a, b = self.vb(P1, o), self.vb(P2, o)
            s = self.strings.get(a, b'')
            self.set_result(s[b] if 0 <= b < len(s) else 0)
        elif k == 5:
            a, b = self.vb(P1, o), self.vb(P2, o)
            self.strings[a] = bytes(b)

    def o_delayVariable(self):
        self.slots[self.cur].delay = self.get_var()
        self.slots[self.cur].status = SS_PAUSED
        self.break_here()

    def o_delay(self):
        d = self.byte() | (self.byte() << 8) | (self.byte() << 16)
        self.slots[self.cur].delay = d
        self.slots[self.cur].status = SS_PAUSED
        self.break_here()

    def o_cursorCommand(self):
        o = self.byte()
        k = o & 0x1F
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
            self.vb(P1, o); self.vb(P2, o)
        elif k == 11:
            self.vb(P1, o); self.vb(P2, o); self.vb(P3, o)
        elif k in (12, 13):
            self.vb(P1, o)
        elif k == 14:
            self.vb(P1, o); self.vb(P2, o)

    def o_setBoxFlags(self):
        box, fl = self.vb(P1), self.byte()
        if self.room and box < len(self.room.box_flags):
            self.room.box_flags[box] = fl

    def o_roomOps(self):
        a, b = self.vw(P1), self.vw(P2)
        o = self.byte()
        k = o & 0x1F
        if k == 1:
            lo, hi = max(a, 160), min(b, (self.room.width if self.room else 320) - 160)
            self.vars[VAR_CAMERA_MIN_X], self.vars[VAR_CAMERA_MAX_X] = lo, max(lo, hi)
        elif k == 7:
            self.vb(P1, o); self.vb(P2, o)
            o = self.byte(); self.vb(P1, o); self.vb(P2, o)
            o = self.byte(); self.vb(P2, o)
        elif k == 8:
            self.vb(P1, o); self.vb(P2, o); self.vb(P3, o)
        elif k == 9:
            self.vb(P1, o); self.vb(P2, o)
        elif k == 10:
            self.vw(P1, o)
        elif k in (11, 12):
            self.vw(P1, o); self.vw(P2, o); self.vw(P3, o)
            o = self.byte(); self.vb(P1, o); self.vb(P2, o)
        elif k in (13, 14):
            self.vb(P1, o); self.raw_string()
        elif k == 15:
            self.vb(P1, o)
            o = self.byte(); self.vb(P1, o); self.vb(P2, o)
            o = self.byte(); self.vb(P1, o)
        elif k == 16:
            self.vb(P1, o); self.vb(P2, o)
        self.f_events['roomops_%d' % k] += 1

    def o_drawBox(self):
        self.vw(P1); self.vw(P2)
        o = self.byte()
        self.vw(P1, o); self.vw(P2, o); self.vb(P3, o)
        self.f_events['drawbox'] += 1

    def o_setObjectName(self):
        obj = self.vw(P1)
        self.new_names[obj] = self.raw_string()

    def o_oldRoomEffect(self):
        o = self.byte()
        if (o & 0x1F) == 3:
            self.vw(P1, o)

    def o_lights(self):
        self.vb(P1); self.byte(); self.byte()
        self.f_events['luces'] += 1

    def o_verbOps(self):
        verb = self.vb(P1)
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            k = o & 0x1F
            if k == 1:
                self.vw(P1, o)
            elif k == 2:
                self.verbs[verb] = self.raw_string()
            elif k in (3, 4, 16, 18, 23):
                self.vb(P1, o)
            elif k == 5:
                self.vw(P1, o); self.vw(P2, o)
            elif k == 20:
                self.vw(P1, o)
            elif k == 22:
                self.vw(P1, o); self.vb(P2, o)
            self.f_events['verbo'] += 1

    def o_systemOps(self):
        if self.byte() in (1, 3):
            raise Halt()

    def o_saveLoadVars(self):
        self.byte()
        while True:
            o = self.byte()
            if o == 0:
                return
            k = o & 0x1F
            if k == 1:
                self.result_pos(); self.result_pos()
            elif k == 2:
                self.vb(P1, o); self.vb(P2, o)
            elif k == 3:
                self.raw_string()
            elif k in (4, 0x1F):
                return

    def o_saveLoadGame(self):
        self.result_pos()
        self.vb(P1)
        self.set_result(0)

    def o_saveRestoreVerbs(self):
        o = self.byte()
        self.vb(P1, o); self.vb(P2, o); self.vb(P3, o)

    def o_expression(self):
        self.result_pos()
        res = self.res
        stack = []
        while True:
            o = self.byte()
            if o == 0xFF:
                break
            k = o & 0x1F
            if k == 1:
                stack.append(s16(self.vw(P1, o)))
            elif k in (2, 3, 4, 5):
                b = stack.pop() if stack else 0
                a = stack.pop() if stack else 0
                stack.append(a + b if k == 2 else a - b if k == 3 else a * b if k == 4 else (cdiv(a, b) if b else 0))
            elif k == 6:
                self.op(self.byte())
                stack.append(self.read_var(self.res))
        self.res = res
        self.set_result(stack.pop() if stack else 0)

    def o_pseudoRoom(self):
        self.byte()
        while self.byte() != 0:
            pass


# ---------------------------------------------------------------------------------------------- arnes
class Runner:
    """Ejecuta fotogramas y apunta las medidas de cada uno."""

    def __init__(self, vm, seed=1):
        self.vm = vm
        self.rng = random.Random(seed)
        self.frames = []
        self.next_click = 30
        vm.pending = None

    def random_click(self):
        vm = self.vm
        if not vm.room or not vm.room.boxes:
            return (self.rng.randint(0, 319), self.rng.randint(0, 127))
        # un punto al azar dentro de una caja visible (el sitio donde un jugador pincharia para andar)
        ks = [k for k in range(len(vm.room.boxes)) if not vm.room.box_flags[k] & BOX_INVISIBLE]
        if not ks:
            return (vm.cam_cur, 100)
        q = vm.box_quad(self.rng.choice(ks))
        t, u = self.rng.random(), self.rng.random()
        top = (q[0][0] + (q[1][0] - q[0][0]) * t, q[0][1] + (q[1][1] - q[0][1]) * t)
        bot = (q[3][0] + (q[2][0] - q[3][0]) * t, q[3][1] + (q[2][1] - q[3][1]) * t)
        return (int(top[0] + (bot[0] - top[0]) * u), int(top[1] + (bot[1] - top[1]) * u))

    def frame(self, label=''):
        vm = self.vm
        # proteccion anticopia (sala 92): Var[57] = 1 es lo que pone el script local 204 al acertar los cuatro simbolos
        if vm.cur_room == 92:
            self.in92 = getattr(self, 'in92', 0) + 1
            if self.in92 > 30:
                vm.vars[57] = 1
        else:
            self.in92 = 0
        self.next_click -= 1
        if self.next_click <= 0:
            vm.pending = self.random_click()
            self.next_click = self.rng.randint(15, 60)
        vm.f_ops = 0
        vm.f_names = Counter()
        vm.f_slots = set()
        vm.f_events = Counter()
        delta = max(1, vm.vars[VAR_TIMER_NEXT])
        err = None
        try:
            vm.scumm_loop(delta)
        except Halt:
            raise
        except (VMError, IndexError, KeyError, ZeroDivisionError, AttributeError, TypeError) as e:
            err = '%s: %s' % (type(e).__name__, e)
            vm.errors[err[:80]] += 1
            vm.cur = 0xFF
            vm.nest = []
        vm.frame += 1
        inroom = [a for a in vm.actors[1:] if a.room == vm.cur_room and vm.cur_room and a.visible and a.costume]
        moving = [a for a in inroom if a.moving]
        redraw = [a for a in inroom if a.need_redraw]
        px = sum(vm.actor_cells(a) for a in redraw)
        for a in inroom:
            a.need_redraw = False
        running = sum(1 for s in vm.slots if s.status != SS_DEAD)
        self.frames.append(dict(
            f=vm.frame, room=vm.cur_room, delta=delta, ops=vm.f_ops, scripts=len(vm.f_slots), slots=running,
            actors=len(inroom), moving=len(moving), redraw=len(redraw), cel_px=px,
            ev=dict(vm.f_events), names=dict(vm.f_names), err=err, label=label,
            cost=sorted(set(a.costume for a in inroom)),
            glob=sorted(set(n for n, w in vm.f_slots if w == WIO_GLOBAL)),
            snd=sorted(vm.sound_left)))
        return self.frames[-1]


def summarize(frames):
    by_room = {}
    for fr in frames:
        by_room.setdefault(fr['room'], []).append(fr)
    out = []
    for room, fs in sorted(by_room.items()):
        ops = sorted(f['ops'] for f in fs)
        n = len(ops)

        def pct(p):
            return ops[min(n - 1, int(p * n))]
        out.append(dict(room=room, frames=n, ops_mean=round(sum(ops) / n, 1), ops_med=pct(0.5), ops_p90=pct(0.9),
                        ops_max=ops[-1], scripts_mean=round(sum(f['scripts'] for f in fs) / n, 2),
                        slots_max=max(f['slots'] for f in fs),
                        actors_mean=round(sum(f['actors'] for f in fs) / n, 2), actors_max=max(f['actors'] for f in fs),
                        moving_mean=round(sum(f['moving'] for f in fs) / n, 2),
                        redraw_mean=round(sum(f['redraw'] for f in fs) / n, 2),
                        cel_px_mean=round(sum(f['cel_px'] for f in fs) / n), cel_px_max=max(f['cel_px'] for f in fs),
                        delta_mode=Counter(f['delta'] for f in fs).most_common(1)[0][0],
                        errors=sum(1 for f in fs if f['err']),
                        costumes=sorted(set(c for f in fs for c in f['cost'])),
                        globals=sorted(set(c for f in fs for c in f['glob'])),
                        sounds=sorted(set(c for f in fs for c in f['snd']))))
    return out


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 1
    d, mode, nframes, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    ix = R.Index(d)
    seed = 1
    rooms = []
    if mode == 'boot':
        seed = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    else:
        rooms = [int(x) for x in sys.argv[5:]]
    vm = VM(ix, seed)
    run = Runner(vm, seed)
    vm.run_script(1)
    try:
        if mode == 'boot':
            for _ in range(nframes):
                run.frame('boot')
        else:
            for _ in range(200):
                run.frame('boot')
            for rn in rooms:
                ego = vm.actors[vm.vars[VAR_EGO] % NUM_ACTORS]
                try:
                    vm.cur = 0xFF
                    vm.nest = []
                    ego.room = rn
                    vm.start_scene(rn)
                    if vm.room and vm.room.boxes:
                        x, y = run.random_click()
                        vm.put_actor(ego, x, y, rn)
                    vm.cam_follows = ego.num
                    vm.user_put = max(vm.user_put, 1)          # el salto se salta el script que devuelve el control
                    vm.cursor_state = max(vm.cursor_state, 1)
                except Exception as e:
                    vm.errors['sala %d: %s' % (rn, e)] += 1
                for _ in range(nframes):
                    if vm.cur_room != rn:
                        break
                    run.frame('sala %d' % rn)
    except Halt:
        pass
    res = dict(summary=summarize(run.frames), errors=vm.errors.most_common(30), insn_total=vm.insn_total,
               max_slots=vm.max_slots, max_nest=vm.max_nest,
               loaded={k: sorted(v) for k, v in vm.loaded.items()},
               frames=[{k: v for k, v in f.items() if k != 'names'} for f in run.frames])
    tot = Counter()
    for f in run.frames:
        tot.update(f['names'])
    res['opcodes'] = tot.most_common()
    with open(out, 'w') as f:
        json.dump(res, f)
    for s in res['summary']:
        print(s)
    print('errores:', res['errors'][:10])
    print('max ranuras', vm.max_slots, 'max anidamiento', vm.max_nest, 'instrucciones', vm.insn_total)
    return 0


if __name__ == '__main__':
    sys.exit(main())
