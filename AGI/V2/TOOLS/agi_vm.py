#!/usr/bin/env python3
"""Modelo de referencia del interprete AGI v2 (sin pantalla): variables, banderas, logicas, objetos animados y parser.

Uso:
    agi_vm.py JUEGO [--cycles N] [--script EVENTOS] [--quiet]

EVENTOS: lista separada por espacios de ciclo:tipo:valor, por ejemplo  "40:text:look at rock 60:dir:3 80:dir:0 90:key:13"
    str:cadena   respuesta a get.string / get.num
    text:cadena  el jugador escribe esa orden           key:n   pulsa la tecla ASCII n
    ctrl:n       se activa el controlador n (un ciclo)  dir:n   direccion del ego 0-8 (se mantiene hasta otro dir)
El modelo escribe un registro (cambios de sala, textos, objetos) y al final los comandos que no ha modelado.
Sirve para fijar la semantica antes del Z80: el mismo guion tiene que dar el mismo registro en los dos.
"""
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi_read as ag
from agi_logic import CMDS, CONDS

DX = [0, 0, 1, 1, 1, 0, -1, -1, -1]
DY = [0, -1, -1, 0, 1, 1, 1, 0, -1]
LOOP4 = [4, 3, 0, 0, 0, 2, 1, 1, 1]
LOOP2 = [4, 4, 0, 0, 0, 4, 1, 1, 1]
EGO = 0


def b2(x):
    return 1 if x else 0


class Stop(Exception):
    pass


class Obj:
    def __init__(self):
        self.anim = self.drawn = False
        self.upd = True
        self.view = self.loop = self.cel = 0
        self.x = self.y = 0
        self.pri = 0
        self.fixpri = self.fixloop = False
        self.cycling = True
        self.ctype = 0                 # 0 normal, 1 end.of.loop, 2 reverse.loop, 3 reverse
        self.ctime = self.ccount = 1
        self.cflag = 0
        self.motion = 0                # 0 normal, 1 wander, 2 follow, 3 move.obj
        self.mon = True
        self.step = 1
        self.stime = self.scount = 1
        self.dir = 0
        self.ign_horizon = self.ign_blocks = self.ign_objs = False
        self.water = 0                 # 0 cualquiera, 1 solo agua, 2 solo tierra
        self.tx = self.ty = 0
        self.mstep = 0
        self.mflag = 0
        self.wander = 0


class Interp:
    def __init__(self, path, quiet=False):
        self.g = ag.Game(path)
        self.quiet = quiet
        self.vars = [0] * 256
        self.flags = [0] * 256
        self.strs = [''] * 12
        self.objs = {}
        self.logics = {}
        self.views = {}
        self.pics = {}
        self.pic = None
        self.use_pic = os.environ.get('AGI_NOPIC') != '1'     # AGI_NOPIC=1: sin el plano de prioridad (lo que modela el Z80 por etapas)
        self.inv = [r for _, r, _ in ag.objects(path)]
        self.inv_names = [n for _, _, n in ag.objects(path)]
        self.words = ag.words(path)
        self.wmap = {}
        for w, n in self.words:
            self.wmap[w] = n
        self.maxw = max((w.count(' ') + 1 for w in self.wmap), default=1)
        self.horizon = 36
        self.blocks = None
        self.pcontrol = True
        self.accept = True
        self.newroom = None
        self.exit_all = False
        self.stop = False
        self.cycle = 0
        self.ticks = 0
        self.stack = []
        self.keys = {}                 # ascii -> controlador
        self.ctl = set()
        self.input = None              # lista de palabras (numeros) de la orden pendiente
        self.said_done = False
        self.keyq = []
        self.textq = []
        self.sound_flags = []
        self.noop = {}
        self.dirhold = 0
        self.seed = random.Random(1)
        self.lfsr = 0xACE1                # igual que el Z80: LFSR de 16 bits (Galois)
        self.trace = None                 # lista de (logica, pc) de cada paso; None = sin traza
        self.summ = []                    # por ciclo: (ciclo, pasos, suma de variables, suma de banderas, sala)
        self.nsteps = 0
        self.out = []
        v = self.vars
        v[8] = 255
        v[10] = 2
        v[15] = 3
        v[20] = 0
        v[22] = 15
        v[24] = 41
        v[26] = 3
        self.flags[9] = 1
        self.flags[5] = 1
        self.flags[11] = 1

    # ------------------------------------------------------------ utilidades
    def log(self, s):
        line = '[%5d] %s' % (self.cycle, s)
        self.out.append(line)
        if not self.quiet:
            print(line)

    def obj(self, n):
        if n not in self.objs:
            self.objs[n] = Obj()
        return self.objs[n]

    def logic(self, n):
        if n not in self.logics:
            d = self.g.resource('LOG', n)
            if d is None:
                raise Stop('logica %d inexistente' % n)
            size = d[0] | (d[1] << 8)
            try:
                msgs = ag.logic_messages(d)
            except (IndexError, ValueError):
                msgs = []
            self.logics[n] = (d[2:2 + size], msgs)
        return self.logics[n]

    def loops(self, view):
        if view not in self.views:
            d = self.g.resource('VIEW', view)
            if d is None:
                raise Stop('vista %d inexistente' % view)
            self.views[view] = ag.view_cells(d)[1]
        return self.views[view]

    def cell(self, o):
        lp = self.loops(o.view)
        if not lp:
            return 0, 0
        o.loop = min(o.loop, len(lp) - 1)
        cs = lp[o.loop]
        o.cel = min(o.cel, len(cs) - 1)
        c = cs[o.cel]
        return c[0], c[1]

    def fmt(self, s, lognum):
        def rep(m):
            k, n = m.group(1), int(m.group(2))
            if k == 'v':
                return str(self.vars[n])
            if k == 'm':
                ms = self.logic(lognum)[1]
                return ms[n - 1] if 0 < n <= len(ms) and ms[n - 1] else ''
            if k == 's':
                return self.strs[n] if n < 12 else ''
            if k == 'g':
                ms = self.logic(0)[1]
                return ms[n - 1] if 0 < n <= len(ms) and ms[n - 1] else ''
            if k == 'w':
                return self.wtext[n - 1] if n - 1 < len(self.wtext) else ''
            return m.group(0)
        return re.sub(r'%([vmsgw])(\d+)(?:\|\d+)?', rep, s)

    wtext = []

    def msg(self, n):
        ms = self.stack[-1][1]
        s = ms[n - 1] if 0 < n <= len(ms) and ms[n - 1] is not None else ''
        return self.fmt(s, self.stack[-1][2])

    # ------------------------------------------------------------ parser
    def parse(self, text):
        t = re.sub(r'[^a-z0-9 ]', ' ', text.lower()).split()
        self.wtext = []
        nums = []
        self.vars[9] = 0
        i = 0
        while i < len(t):
            for k in range(min(self.maxw, len(t) - i), 0, -1):
                w = ' '.join(t[i:i + k])
                if w in self.wmap:
                    if self.wmap[w] != 0:
                        nums.append(self.wmap[w])
                        self.wtext.append(w)
                    i += k
                    break
            else:
                self.vars[9] = len(nums) + 1
                self.wtext.append(t[i])
                return nums
        return nums

    def say(self, args):
        if self.input is None or self.said_done or self.vars[9]:
            return False
        w = self.input
        n = len(args)
        for i, a in enumerate(args):
            if a == 9999:
                ok = True
                break
            if i >= len(w):
                return False
            if a != 1 and a != w[i]:
                return False
        else:
            if n != len(w):
                return False
            ok = True
        self.said_done = True
        self.flags[4] = 1
        return ok

    # ------------------------------------------------------------ condiciones
    def cond(self, op, a, p, code):
        v, f = self.vars, self.flags
        name = CONDS[op][0]
        if name == 'equaln':
            return v[a[0]] == a[1]
        if name == 'equalv':
            return v[a[0]] == v[a[1]]
        if name == 'lessn':
            return v[a[0]] < a[1]
        if name == 'lessv':
            return v[a[0]] < v[a[1]]
        if name == 'greatern':
            return v[a[0]] > a[1]
        if name == 'greaterv':
            return v[a[0]] > v[a[1]]
        if name == 'isset':
            return bool(f[a[0]])
        if name == 'issetv':
            return bool(f[v[a[0]]])
        if name == 'has':
            return self.inv[a[0]] == 255
        if name == 'obj.in.room':
            return self.inv[a[0]] == v[a[1]]
        if name == 'controller':
            return a[0] in self.ctl
        if name == 'have.key':
            if self.keyq:
                v[19] = self.keyq.pop(0)
                return True
            return False
        if name == 'compare.strings':
            return self.strs[a[0]].lower().split() == self.strs[a[1]].lower().split()
        o = self.obj(a[0])
        w, h = self.cell(o) if o.drawn else (0, 0)
        if name == 'posn':
            return a[1] <= o.x <= a[3] and a[2] <= o.y <= a[4]
        if name == 'obj.in.box':
            return o.x >= a[1] and o.y >= a[2] and o.x + w - 1 <= a[3] and o.y <= a[4]
        if name == 'center.posn':
            c = o.x + w // 2
            return a[1] <= c <= a[3] and a[2] <= o.y <= a[4]
        if name == 'right.posn':
            r = o.x + w - 1
            return a[1] <= r <= a[3] and a[2] <= o.y <= a[4]
        raise Stop('condicion %s' % name)

    # ------------------------------------------------------------ ejecucion
    def run(self, n):
        code, msgs = self.logic(n)
        self.stack.append((code, msgs, n))
        if len(self.stack) > 40:
            raise Stop('recursion de logicas')
        p = 0
        end = len(code)
        try:
            while p < end and not self.exit_all and not self.stop:
                op = code[p]
                self.nsteps += 1
                if self.trace is not None and len(self.trace) < 100000:
                    self.trace.append((n, p))
                if op == 0xFF:
                    q = p + 1
                    res = True
                    orm = False
                    orres = False
                    neg = False
                    while True:
                        c = code[q]
                        q += 1
                        if c == 0xFF:
                            break
                        if c == 0xFD:
                            neg = True
                            continue
                        if c == 0xFC:
                            if orm:
                                res = res and orres
                                orres = False
                            orm = not orm
                            continue
                        name, types = CONDS[c]
                        if types is None:
                            k = code[q]
                            q += 1
                            ws = [code[q + 2 * i] | (code[q + 2 * i + 1] << 8) for i in range(k)]
                            q += 2 * k
                            r = self.say(ws)
                        else:
                            a = list(code[q:q + len(types)])
                            q += len(types)
                            r = self.cond(c, a, q, code)
                        if neg:
                            r = not r
                            neg = False
                        if orm:
                            orres = orres or r
                        else:
                            res = res and r
                    ln = code[q] | (code[q + 1] << 8)
                    q += 2
                    p = q if res else q + ln
                    continue
                if op == 0xFE:
                    off = code[p + 1] | (code[p + 2] << 8)
                    if off >= 0x8000:
                        off -= 0x10000
                    p = p + 3 + off
                    continue
                name, types = CMDS[op]
                a = list(code[p + 1:p + 1 + len(types)])
                p += 1 + len(types)
                if name == 'return':
                    break
                self.cmd(name, a)
        finally:
            self.stack.pop()

    def cmd(self, name, a):
        fn = getattr(self, 'c_' + name.replace('.', '_'), None)
        if fn is None:
            self.noop[name] = self.noop.get(name, 0) + 1
            return
        fn(*a)

    # ------------------------------------------------------------ comandos: variables y banderas
    def c_increment(self, a):
        if self.vars[a] < 255:
            self.vars[a] += 1

    def c_decrement(self, a):
        if self.vars[a] > 0:
            self.vars[a] -= 1

    def c_assignn(self, a, n): self.vars[a] = n
    def c_assignv(self, a, b): self.vars[a] = self.vars[b]
    def c_addn(self, a, n): self.vars[a] = (self.vars[a] + n) & 255
    def c_addv(self, a, b): self.vars[a] = (self.vars[a] + self.vars[b]) & 255
    def c_subn(self, a, n): self.vars[a] = (self.vars[a] - n) & 255
    def c_subv(self, a, b): self.vars[a] = (self.vars[a] - self.vars[b]) & 255
    def c_mul_n(self, a, n): self.vars[a] = (self.vars[a] * n) & 255
    def c_mul_v(self, a, b): self.vars[a] = (self.vars[a] * self.vars[b]) & 255
    def c_div_n(self, a, n): self.vars[a] = self.vars[a] // n if n else 0
    def c_div_v(self, a, b): self.vars[a] = self.vars[a] // self.vars[b] if self.vars[b] else 0
    def c_lindirectv(self, a, b): self.vars[self.vars[a]] = self.vars[b]
    def c_rindirect(self, a, b): self.vars[a] = self.vars[self.vars[b]]
    def c_lindirectn(self, a, n): self.vars[self.vars[a]] = n
    def c_set(self, f): self.flags[f] = 1
    def c_reset(self, f): self.flags[f] = 0
    def c_toggle(self, f): self.flags[f] ^= 1
    def c_set_v(self, v): self.flags[self.vars[v]] = 1
    def c_reset_v(self, v): self.flags[self.vars[v]] = 0
    def c_toggle_v(self, v): self.flags[self.vars[v]] ^= 1

    def rand8(self):
        for _ in range(8):
            lsb = self.lfsr & 1
            self.lfsr >>= 1
            if lsb:
                self.lfsr ^= 0xB400
        return self.lfsr & 255

    def c_random(self, lo, hi, v):
        n = hi - lo + 1
        self.vars[v] = lo + (self.rand8() % n if n > 0 else 0)

    # ------------------------------------------------------------ logicas y salas
    def c_new_room(self, n):
        self.newroom = n
        self.exit_all = True

    def c_new_room_v(self, v): self.c_new_room(self.vars[v])
    def c_call(self, n): self.run(n)
    def c_call_v(self, v): self.run(self.vars[v])

    def do_new_room(self, n):
        v = self.vars
        old = v[0]
        for k, o in self.objs.items():
            if k != EGO:
                o.anim = o.drawn = False
        ego = self.obj(EGO)
        ego.drawn = False
        self.pcontrol = True
        self.blocks = None
        self.horizon = 36
        v[1] = old
        v[0] = n
        v[3] = 0
        v[4] = 0
        v[5] = 0
        w, h = self.cell(ego) if ego.anim else (0, 0)
        b = v[2]
        if b == 1:
            ego.y = 167
        elif b == 2:
            ego.x = 0
        elif b == 3:
            ego.y = self.horizon + 1
        elif b == 4:
            ego.x = 160 - w
        v[2] = 0
        self.flags[5] = 1
        self.flags[0] = 0
        self.log('sala %d (desde %d)' % (n, old))
        self.newroom = None
        self.exit_all = False

    def c_draw_pic(self, v):
        n = self.vars[v]
        d = self.g.resource('PIC', n)
        if d is None:
            raise Stop('imagen %d inexistente' % n)
        self.pic = ag.Picture(d)

    def c_overlay_pic(self, v):
        d = self.g.resource('PIC', self.vars[v])
        self.pic = ag.Picture(d, self.pic)

    # ------------------------------------------------------------ objetos animados
    def c_animate_obj(self, n):
        o = self.obj(n)
        if not o.anim:
            o.anim = True
            o.upd = o.cycling = o.mon = True
            o.ign_horizon = o.ign_blocks = o.ign_objs = False
            o.fixpri = o.fixloop = False
            o.motion = 0
            o.dir = 0
            o.step = o.stime = o.scount = o.ctime = o.ccount = 1
            o.ctype = 0
            o.water = 0

    def c_unanimate_all(self):
        for o in self.objs.values():
            o.anim = o.drawn = False

    def c_draw(self, n):
        o = self.obj(n)
        if not o.drawn:
            o.drawn = True
            self.cell(o)
            self.set_pri(o)
            self.log('draw o%d view %d at %d,%d' % (n, o.view, o.x, o.y))

    def c_erase(self, n): self.obj(n).drawn = False

    def set_pri(self, o):
        if not o.fixpri:
            o.pri = 4 if o.y < 48 else min(15, (o.y - 48) // 12 + 5)

    def c_position(self, n, x, y):
        o = self.obj(n)
        o.x, o.y = x, y
        self.set_pri(o)

    def c_position_v(self, n, vx, vy): self.c_position(n, self.vars[vx], self.vars[vy])
    def c_reposition_to(self, n, x, y): self.c_position(n, x, y)
    def c_reposition_to_v(self, n, vx, vy): self.c_position(n, self.vars[vx], self.vars[vy])

    def c_reposition(self, n, vx, vy):
        o = self.obj(n)
        dx, dy = self.vars[vx], self.vars[vy]
        o.x += dx - 256 if dx >= 128 else dx
        o.y += dy - 256 if dy >= 128 else dy
        self.set_pri(o)

    def c_get_posn(self, n, vx, vy):
        o = self.obj(n)
        self.vars[vx], self.vars[vy] = o.x & 255, o.y & 255

    def c_set_view(self, n, view):
        o = self.obj(n)
        o.view = view
        self.loops(view)
        o.loop = o.cel = 0 if not o.drawn else min(o.loop, 0)
        self.cell(o)

    def c_set_view_v(self, n, v): self.c_set_view(n, self.vars[v])

    def c_set_loop(self, n, l):
        o = self.obj(n)
        o.loop = l
        self.cell(o)

    def c_set_loop_v(self, n, v): self.c_set_loop(n, self.vars[v])
    def c_fix_loop(self, n): self.obj(n).fixloop = True
    def c_release_loop(self, n): self.obj(n).fixloop = False

    def c_set_cel(self, n, c):
        o = self.obj(n)
        o.cel = c
        self.cell(o)

    def c_set_cel_v(self, n, v): self.c_set_cel(n, self.vars[v])

    def c_last_cel(self, n, v):
        o = self.obj(n)
        self.cell(o)
        self.vars[v] = len(self.loops(o.view)[o.loop]) - 1

    def c_current_cel(self, n, v): self.vars[v] = self.obj(n).cel
    def c_current_loop(self, n, v): self.vars[v] = self.obj(n).loop
    def c_current_view(self, n, v): self.vars[v] = self.obj(n).view
    def c_number_of_loops(self, n, v): self.vars[v] = len(self.loops(self.obj(n).view))

    def c_set_priority(self, n, p):
        o = self.obj(n)
        o.pri, o.fixpri = p, True

    def c_set_priority_v(self, n, v): self.c_set_priority(n, self.vars[v])

    def c_release_priority(self, n):
        o = self.obj(n)
        o.fixpri = False
        self.set_pri(o)

    def c_get_priority(self, n, v): self.vars[v] = self.obj(n).pri
    def c_stop_update(self, n): self.obj(n).upd = False
    def c_start_update(self, n): self.obj(n).upd = True
    def c_force_update(self, n): pass
    def c_ignore_horizon(self, n): self.obj(n).ign_horizon = True
    def c_observe_horizon(self, n): self.obj(n).ign_horizon = False
    def c_set_horizon(self, n): self.horizon = n
    def c_object_on_water(self, n): self.obj(n).water = 1
    def c_object_on_land(self, n): self.obj(n).water = 2
    def c_object_on_anything(self, n): self.obj(n).water = 0
    def c_ignore_objs(self, n): self.obj(n).ign_objs = True
    def c_observe_objs(self, n): self.obj(n).ign_objs = False
    def c_ignore_blocks(self, n): self.obj(n).ign_blocks = True
    def c_observe_blocks(self, n): self.obj(n).ign_blocks = False
    def c_block(self, x1, y1, x2, y2): self.blocks = (x1, y1, x2, y2)
    def c_unblock(self): self.blocks = None

    def c_distance(self, a, b, v):
        o1, o2 = self.obj(a), self.obj(b)
        if o1.drawn and o2.drawn:
            self.vars[v] = min(255, abs(o1.x - o2.x) + abs(o1.y - o2.y))
        else:
            self.vars[v] = 255

    def c_stop_cycling(self, n): self.obj(n).cycling = False
    def c_start_cycling(self, n): self.obj(n).cycling = True

    def c_normal_cycling(self, n):
        o = self.obj(n)
        o.ctype = 0
        o.cycling = True

    def c_end_of_loop(self, n, f):
        o = self.obj(n)
        o.ctype, o.cflag, o.cycling = 1, f, True
        self.flags[f] = 0

    def c_reverse_loop(self, n, f):
        o = self.obj(n)
        o.ctype, o.cflag, o.cycling = 2, f, True
        self.flags[f] = 0

    def c_reverse_cycle(self, n):
        o = self.obj(n)
        o.ctype, o.cycling = 3, True

    def c_cycle_time(self, n, v): self.obj(n).ctime = self.obj(n).ccount = max(1, self.vars[v])
    def c_stop_motion(self, n):
        o = self.obj(n)
        o.mon = False
        o.dir = 0
        if n == EGO:
            self.vars[6] = 0
            self.pcontrol = False

    def c_start_motion(self, n):
        self.obj(n).mon = True
        if n == EGO:
            self.pcontrol = True

    def c_step_size(self, n, v): self.obj(n).step = self.vars[v]
    def c_step_time(self, n, v): self.obj(n).stime = self.obj(n).scount = max(1, self.vars[v])

    def c_move_obj(self, n, x, y, step, f):
        o = self.obj(n)
        o.motion, o.tx, o.ty, o.mflag = 3, x, y, f
        o.mstep = o.step
        if step:
            o.step = step
        self.flags[f] = 0
        o.mon = True
        if n == EGO:
            self.pcontrol = False

    def c_move_obj_v(self, n, vx, vy, vs, f): self.c_move_obj(n, self.vars[vx], self.vars[vy], self.vars[vs], f)

    def c_follow_ego(self, n, step, f):
        o = self.obj(n)
        o.motion, o.mflag = 2, f
        o.mstep = o.step
        if step:
            o.step = step
        self.flags[f] = 0
        o.mon = True

    def c_wander(self, n):
        o = self.obj(n)
        o.motion = 1
        o.mon = True
        if n == EGO:
            self.pcontrol = False

    def c_normal_motion(self, n): self.obj(n).motion = 0
    def c_set_dir(self, n, v): self.obj(n).dir = self.vars[v]
    def c_get_dir(self, n, v): self.vars[v] = self.obj(n).dir

    def c_program_control(self): self.pcontrol = False
    def c_player_control(self): self.pcontrol = True

    # ------------------------------------------------------------ inventario
    def c_get(self, i): self.inv[i] = 255
    def c_get_v(self, v): self.inv[self.vars[v]] = 255
    def c_drop(self, i): self.inv[i] = 0
    def c_put(self, i, r): self.inv[i] = r
    def c_put_v(self, i, v): self.inv[i] = self.vars[v]
    def c_get_room_v(self, i, v): self.vars[v] = self.inv[self.vars[i]]

    # ------------------------------------------------------------ texto y cadenas
    def c_print(self, m): self.log('print: ' + self.msg(m).replace('\n', ' / '))
    def c_print_v(self, v): self.c_print(self.vars[v])
    def c_print_at(self, m, r, c, w): self.c_print(m)
    def c_print_at_v(self, vm, r, c, w): self.c_print(self.vars[vm])
    def c_display(self, r, c, m): self.log('display %d,%d: %s' % (r, c, self.msg(m)))
    def c_display_v(self, vr, vc, vm): self.c_display(self.vars[vr], self.vars[vc], self.vars[vm])

    def c_set_string(self, s, m): self.strs[s] = self.msg(m)

    def c_get_string(self, s, m, r, c, ln):
        self.log('get.string: ' + self.msg(m))
        self.strs[s] = self.textq.pop(0) if self.textq else ''

    def c_get_num(self, m, v):
        self.log('get.num: ' + self.msg(m))
        t = self.textq.pop(0) if self.textq else '0'
        self.vars[v] = int(t) & 255 if t.isdigit() else 0

    def c_word_to_string(self, n, s):
        self.strs[s] = self.wtext[n] if n < len(self.wtext) else ''

    def c_parse(self, s):
        self.input = self.parse(self.strs[s])
        self.said_done = False
        self.flags[2] = 1

    def c_prevent_input(self): self.accept = False
    def c_accept_input(self): self.accept = True
    def c_set_key(self, a, s, c): self.keys[a if a else (s << 8)] = c
    def c_set_menu_item(self, m, c): pass
    def sound_ticks(self, n):
        """Duracion de la pista 0 de un sonido en 1/60 s."""
        try:
            d = self.g.resource('SND', n)
        except ValueError:
            return 0
        if not d:
            return 0
        p = d[0] | (d[1] << 8)
        t = 0
        while p + 5 <= len(d):
            dur = d[p] | (d[p + 1] << 8)
            if dur == 0xFFFF:
                break
            t += dur
            p += 5
        return min(t, 0xFFFF)

    def sound_cycles(self, n):
        """Ciclos del interprete que dura: t/60 s a 20/v10 ciclos por segundo, redondeado (aritmetica entera, como el Z80)."""
        t = self.sound_ticks(n)
        v10 = max(1, self.vars[10])
        return max(2, (2 * t + 3 * v10) // (6 * v10))

    def c_sound(self, n, f):
        self.flags[f] = 0
        self.sound_flags = [x for x in self.sound_flags if x[1] != f]
        self.sound_flags.append((self.cycle + self.sound_cycles(n), f))
        self.log('sound %d (%d ciclos)' % (n, self.sound_flags[-1][0] - self.cycle))

    def c_stop_sound(self): pass
    def c_set_game_id(self, m): self.log('juego: ' + self.msg(m))
    def c_log(self, m): pass
    def c_quit(self, n):
        self.log('quit')
        self.stop = True

    def c_restart_game(self):
        self.log('restart.game')
        self.stop = True

    def c_version(self): pass

    # ------------------------------------------------------------ movimiento y ciclo
    def can_be_here(self, o, x, y):
        w, h = self.cell(o)
        if x < 0 or x + w > 160 or y - h < -1 or y > 167:
            return True                       # los bordes se tratan aparte
        if not o.ign_horizon and y <= self.horizon:
            return False
        if self.blocks and o is self.objs.get(EGO) and not o.ign_blocks:
            bx1, by1, bx2, by2 = self.blocks
            if not (bx1 <= x and x + w - 1 <= bx2 and by1 <= y <= by2):
                return False
        if self.pic and self.use_pic:
            pri = self.pic.pri
            water = land = 0
            sig = False
            for i in range(w):
                c = pri[y * ag.W + x + i]
                if c == 0 and not o.ign_blocks:
                    return False
                if c == 1 and not o.ign_blocks and o is self.objs.get(EGO) and False:
                    return False
                if c == 3:
                    water += 1
                else:
                    land += 1
                if c == 2:
                    sig = True
            if o.water == 2 and water:
                return False
            if o.water == 1 and land:
                return False
            if o is self.objs.get(EGO):
                self.flags[0] = 1 if water == w else 0
                self.flags[3] = 1 if sig else 0
        if not o.ign_objs:
            for k, q in self.objs.items():
                if q is o or not (q.anim and q.drawn) or q.ign_objs:
                    continue
                qw, qh = self.cell(q)
                if x < q.x + qw and q.x < x + w and (y == q.y or (o.y < q.y <= y) or (y < q.y <= o.y)):
                    return False
        return True

    def pick_loop(self, o):
        if o.fixloop or o.dir == 0:
            return
        n = len(self.loops(o.view))
        if n < 2:
            return
        t = LOOP4[o.dir] if n >= 4 else LOOP2[o.dir]
        if t != 4 and t < n:
            o.loop = t

    def move(self, k, o):
        v = self.vars
        if o.motion == 3:
            dx = max(-o.step, min(o.step, o.tx - o.x))
            dy = max(-o.step, min(o.step, o.ty - o.y))
            if o.x == o.tx and o.y == o.ty:
                dx = dy = 0
            sx = (dx > 0) - (dx < 0)
            sy = (dy > 0) - (dy < 0)
            o.dir = [d for d in range(9) if DX[d] == sx and DY[d] == sy][0]
            nx, ny = o.x + dx, o.y + dy
            self.pick_loop(o)
            o.x, o.y = nx, ny
            if o.x == o.tx and o.y == o.ty:
                self.flags[o.mflag] = 1
                o.motion = 0
                o.dir = 0
                o.step = o.mstep or o.step
                if k == EGO:
                    v[6] = 0
            self.set_pri(o)
            return
        if o.motion == 2:
            ego = self.obj(EGO)
            if abs(o.x - ego.x) <= o.step * 2 and abs(o.y - ego.y) <= o.step:
                self.flags[o.mflag] = 1
                o.motion = 0
                o.dir = 0
                return
            sx = (ego.x > o.x) - (ego.x < o.x)
            sy = (ego.y > o.y) - (ego.y < o.y)
            o.dir = [d for d in range(9) if DX[d] == sx and DY[d] == sy][0]
        if o.motion == 1:
            o.wander -= 1
            if o.wander <= 0 or o.dir == 0:
                o.dir = 1 + self.rand8() % 8
                o.wander = 4 + self.rand8() % 10
        d = o.dir
        if d == 0:
            return
        nx, ny = o.x + DX[d] * o.step, o.y + DY[d] * o.step
        w, h = self.cell(o)
        border = 0
        if nx < 0:
            nx, border = 0, 4
        elif nx + w > 160:
            nx, border = 160 - w, 2
        if ny > 167:
            ny, border = 167, 3
        elif not o.ign_horizon and ny <= self.horizon:
            ny, border = self.horizon + 1, 1
        self.pick_loop(o)
        if self.can_be_here(o, nx, ny):
            o.x, o.y = nx, ny
            self.set_pri(o)
        elif o.motion == 1:
            o.wander = 0
        if border:
            if k == EGO:
                v[2] = border
            else:
                v[4], v[5] = k, border

    def cycle_cel(self, o):
        cs = self.loops(o.view)[o.loop] if self.loops(o.view) else []
        if not cs:
            return
        n = len(cs)
        if o.ctype == 0:
            o.cel = (o.cel + 1) % n
        elif o.ctype == 3:
            o.cel = (o.cel - 1) % n
        elif o.ctype == 1:
            if o.cel + 1 >= n:
                self.flags[o.cflag] = 1
                o.cycling = False
                o.ctype = 0
            else:
                o.cel += 1
        elif o.ctype == 2:
            if o.cel == 0:
                self.flags[o.cflag] = 1
                o.cycling = False
                o.ctype = 0
            else:
                o.cel -= 1

    def update_objects(self):
        v = self.vars
        for k in sorted(self.objs):
            o = self.objs[k]
            if not (o.anim and o.drawn and o.upd):
                continue
            if k == EGO:
                if self.pcontrol:
                    o.dir = v[6]
                else:
                    v[6] = o.dir
            if o.mon:
                o.scount -= 1
                if o.scount <= 0:
                    o.scount = o.stime
                    self.move(k, o)
            if o.cycling:
                o.ccount -= 1
                if o.ccount <= 0:
                    o.ccount = o.ctime
                    self.cycle_cel(o)
            if k == EGO and not self.pcontrol:
                v[6] = o.dir

    NOBJ = 32

    def objbytes(self, o):
        b = lambda x: 1 if x else 0
        f1 = b(o.anim) | b(o.drawn) << 1 | b(o.upd) << 2 | b(o.cycling) << 3 | b(o.mon) << 4 | b(o.fixpri) << 5 | b(o.fixloop) << 6 | b(o.ign_horizon) << 7
        f2 = b(o.ign_blocks) | b(o.ign_objs) << 1
        return [f1, f2, o.view, o.loop, o.cel, o.x & 255, o.y & 255, o.pri & 255, o.ctype, o.ctime & 255, o.ccount & 255, o.cflag,
                o.motion, o.step & 255, o.stime & 255, o.scount & 255, o.dir, o.water, o.tx & 255, o.ty & 255, o.mstep & 255, o.mflag,
                o.wander & 255]

    def objsum(self):
        t = self.horizon + b2(self.pcontrol) + b2(self.blocks)
        for k in range(self.NOBJ):
            if k in self.objs:
                t += sum(self.objbytes(self.objs[k]))
        return t & 0xFFFF

    def tick_clock(self):
        v = self.vars
        per = max(1, 20 // max(1, v[10]))
        self.ticks += 1
        if self.ticks >= per:
            self.ticks = 0
            v[11] += 1
            if v[11] >= 60:
                v[11] = 0
                v[12] += 1
                if v[12] >= 60:
                    v[12] = 0
                    v[13] += 1
                    if v[13] >= 24:
                        v[13] = 0
                        v[14] += 1

    def interpret_cycle(self, events):
        v = self.vars
        self.ctl = set()
        for kind, val in events:
            if kind == 'text':
                self.input = self.parse(val)
                self.said_done = False
                self.flags[2] = 1
                v[19] = 0
                self.log('entrada: ' + val + ' -> palabras %s' % (self.input,))
            elif kind == 'str':
                self.textq.append(val)
            elif kind == 'key':
                n = int(val)
                self.keyq.append(n)
                v[19] = n
                if n in self.keys:
                    self.ctl.add(self.keys[n])
            elif kind == 'ctrl':
                self.ctl.add(int(val))
            elif kind == 'dir':
                self.dirhold = int(val)
        if self.pcontrol:
            v[6] = self.dirhold
        for t, f in list(self.sound_flags):
            if t <= self.cycle:
                self.flags[f] = 1
                self.sound_flags.remove((t, f))
        self.exit_all = False
        while True:
            self.run(0)
            if self.stop:
                return
            if self.newroom is not None:
                self.do_new_room(self.newroom)
                continue
            break
        self.update_objects()
        self.flags[2] = self.flags[4] = self.flags[5] = self.flags[6] = 0
        self.input = None
        self.keyq = []
        v[2] = v[3] = v[4] = v[5] = 0
        self.tick_clock()
        self.summ.append((self.cycle, self.nsteps, sum(v) & 0xFFFF, sum(i for i in range(256) if self.flags[i]) & 0xFFFF, v[0], self.objsum()))
        self.nsteps = 0

    def play(self, cycles, script):
        ev = {}
        for item in script:
            c, k, val = item.split(':', 2)
            ev.setdefault(int(c), []).append((k, val))
        for self.cycle in range(1, cycles + 1):
            try:
                self.interpret_cycle(ev.get(self.cycle, []))
            except Stop as e:
                self.log('PARADA: %s' % e)
                break
            if self.stop:
                break


def parse_script(s):
    # los textos pueden llevar espacios: se separan los eventos al ver ' N:'
    return re.findall(r'\d+:(?:text|str|key|ctrl|dir):.*?(?=\s\d+:(?:text|str|key|ctrl|dir):|$)', s.strip())


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cycles = 200
    script = ''
    quiet = '--quiet' in argv
    for i, a in enumerate(argv):
        if a == '--cycles':
            cycles = int(argv[i + 1])
        if a == '--script':
            script = argv[i + 1]
    it = Interp(argv[1], quiet)
    tr = None
    for i, a in enumerate(argv):
        if a == '--trace':
            tr = argv[i + 1]
            it.trace = []
    it.play(cycles, parse_script(script))
    if tr:
        with open(tr, 'w') as f:
            for n, p in it.trace:
                f.write('T %d %d\n' % (n, p))
            for c in it.summ:
                f.write('C %d %d %d %d %d %d\n' % c)
    ego = it.obj(EGO)
    print('fin: sala %d, ciclo %d, ego en %d,%d, v0..v9 = %s' % (it.vars[0], it.cycle, ego.x, ego.y, it.vars[:10]))
    if it.noop:
        print('comandos sin modelar:', ', '.join('%s x%d' % kv for kv in sorted(it.noop.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
