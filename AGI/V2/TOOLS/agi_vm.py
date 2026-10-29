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
from agi_text import plot_hr
import agi_text
import agi2spr

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
        self.static = False             # add.to.pic: objeto fijo


class Interp:
    def __init__(self, path, quiet=False):
        self.path = path
        self.last_key = 0
        self.g = ag.Game(path)
        agi2spr.set_game(path)
        self.quiet = quiet
        self.vars = [0] * 256
        self.flags = [0] * 256
        self.strs = [''] * 12
        self.objs = {}
        self.logics = {}
        self.views = {}
        self.pics = {}
        self.pic = None
        self.saves = {}                 # ranura -> (descripcion, estado)
        self.lastpic = 0
        self.menus = []                 # [titulo, [[texto, controlador, activado]]]
        self.menu_ui = None
        self.margins = []
        self.spans = []                 # add.to.pic: (fila 0 de la celda, prioridad, [(ax0, ax1) por fila])
        self.span_rows = 0
        self.pics_used = set()
        self.ovl_pairs = set()
        self.use_pic = os.environ.get('AGI_NOPIC') != '1'     # AGI_NOPIC=1: sin el plano de prioridad (lo que modela el Z80 por etapas)
        self.inv = [r for _, r, _ in ag.objects(path)]
        self.inv_names = [n for _, _, n in ag.objects(path)]
        for k in os.environ.get('AGI_INV255', '').split(','):          # solo para pruebas (igual en agi2log.py)
            if k.isdigit() and int(k) < len(self.inv):
                self.inv[int(k)] = 255
        self.words = ag.words(path)
        self.wmap = {}
        for w, n in self.words:
            self.wmap[w] = n
        self.maxw = max((w.count(' ') + 1 for w in self.wmap), default=1)
        self.horizon = 36
        self.blocks = None
        self.pcontrol = True
        self.accept = True
        self.tfg, self.tbg = 15, 0
        self.status_on = False
        self.st_last = None
        self.pic_ops = []
        self.spr_big = {}
        self.box = None
        self.ev = {}
        self.max_cycles = 0
        self.ext_bm = bytearray(192 * 32)
        self.ext_at = bytearray(192 * 32)
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
            d = ag.testboot(n, d)
            size = d[0] | (d[1] << 8)
            try:
                msgs = ag.help_override(self.path, n, ag.logic_messages(d))
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

    # ------------------------------------------------------------ sprites (por hardware: ver agi2spr.py y ENGINE/agispr.asm)
    def draw_order(self):
        """Numeros de los objetos con anim y drawn (prioridad < 16) en el orden en que se pintan, de abajo a arriba: por prioridad, a igual prioridad por y (el de
        mas abajo en la pantalla tapa al de mas arriba) y a igual y por numero."""
        return [n for p, y, n in sorted((o.pri, 0 if o.static else o.y, n) for n, o in self.objs.items() if o.anim and o.drawn and o.pri < 16)]

    def pri_plane(self):
        """Plano de prioridad de los pixeles de AGI (160 x 168, agi2hr.sprite_priority) con el rango de cada objeto fijo (add.to.pic) subido a su prioridad; None sin imagen."""
        import agi2hr
        pri2 = agi2hr.sprite_priority(self.pic.pri) if self.pic is not None else None
        if pri2 is not None:
            for row0, pri, pairs in self.spans:
                for i, (a0, a1) in enumerate(pairs):
                    row = row0 + i
                    if 0 <= row < 168 and a0 <= a1:
                        for ax in range(a0, a1 + 1):
                            if pri2[row * 160 + ax] < pri:
                                pri2[row * 160 + ax] = pri
        return pri2

    def hw_sprites(self):
        """Los sprites del hardware que el Z80 tiene que dejar puestos: lista de 64 con (x, y, color[8], dato[8], mascara[8]) o None (apagado); el 0 es el de abajo.
        Los objetos con anim y drawn van de menor a mayor prioridad (a igual prioridad, por numero). Cada uno reserva tantos sprites seguidos como el
        mayor numero de mosaicos de una celda de su bucle (asi los demas no cambian de sprite cuando cambia su celda o los tapa el fondo) y el mosaico j de
        su celda va al sprite reservado j. Coordenadas del hardware (+32); un mosaico que cae entero fuera de la pantalla, o que el fondo tapa entero, deja su
        sprite apagado.
        Prioridad frente al fondo: un pixel del sprite solo se ve si la prioridad del objeto >= la del plano de prioridad de la imagen (agi2hr.sprite_priority) en
        el pixel de AGI que ocupa ese pixel del HiRes ((5 * x) >> 3); se quita de la mascara."""
        import agi2spr
        import agi2hr
        pri2 = self.pri_plane()
        out = [None] * 64
        k = 0
        if self.box is not None or self.menu_ui is not None or self.txtm:
            return out                  # con una ventana, un menu o la pantalla de texto abiertos los sprites se apagan
        for n in self.draw_order():
            if True:
                o = self.objs[n]
                if o.x >= 160:
                    continue
                d = self.g.resource('VIEW', o.view)
                if d is None:
                    continue
                key = (o.view, o.loop)
                if key not in self.spr_big:
                    try:
                        self.spr_big[key] = o.loop < d[2] and len(agi2spr.build_loop(d, o.loop)) > 8190
                    except (IndexError, ValueError):
                        self.spr_big[key] = True
                if self.spr_big[key]:
                    continue
                c = agi2spr.cel_tiles(d, o.loop, o.cel)
                if c is None:
                    continue
                hrw, h, tiles = c
                if agi2spr.meta(tiles, o.view)[0] or o.static:
                    continue                # rotulo ancho o objeto fijo: lo dibuja el Z80 en el bitmap (sw_blit)
                start = k
                k += agi2spr.loop_maxt(d, o.loop)
                x0 = agi2spr.lo(o.x) + 32
                top = 8 + o.y - h + 1 + 32
                for j, (tx, ty, col, pix, msk) in enumerate(tiles):
                    slot = start + j
                    if slot >= 64:
                        break
                    sx, sy = x0 + tx * 8, top + ty * 8
                    if sx <= 24 or sx >= 288 or sy <= 24 or sy >= 224:
                        continue
                    if pri2 is not None:
                        msk = list(msk)
                        for r in range(8):
                            py = sy - 32 + r - 8
                            if not 0 <= py < 168:
                                continue
                            ok = 0
                            for kk in range(8):
                                hx = sx - 32 + kk
                                if hx < 0 or hx > 255 or pri2[py * 160 + ((5 * hx) >> 3)] <= o.pri:
                                    ok |= 0x80 >> kk
                            msk[r] &= ok
                        if not any(msk):
                            continue
                    out[slot] = (sx, sy, col, pix, msk)
        return out

    def screen(self):
        """Pantalla completa (bitmap y atributos de 192x32): el pie y la barra de estado persistentes, y en medio la imagen con su texto. Los sprites
        no estan en ella (son del hardware: hw_sprites)."""
        bm, at = self.render()
        sb = bytearray(self.ext_bm)
        sa = bytearray(self.ext_at)
        sb[256:256 + 168 * 32] = bm
        sa[256:256 + 168 * 32] = at
        if self.pic is not None and not self.txtm:
            self.sw_blit(sb, sa)
        if self.box is not None:
            agi_text.draw_box(sb, sa, self.box[0], self.box[1], self.box[2])
        if self.menu_ui is not None:
            self.draw_menu(sb, sa)
        return sb, sa

    def sw_blit(self, sb, sa):
        """Los objetos con celdas anchas (mas de SW_TILES mosaicos en una fila) no van en sprites: se dibujan en el bitmap, de menor a mayor prioridad, sobre la
        imagen (con su texto). Su borde izquierdo esta en el pixel HiRes lo(x) = 8*cx0 + s; cada fila de cada mosaico (en orden) aporta a la celda cx0 + tx la parte
        desplazada s a la derecha (A) y, si s > 0, a la siguiente la que se sale (B). Una parte con las 8 posiciones opacas escribe el bitmap y el atributo de la
        celda tal cual; si no, pone sus pixeles uno a uno (agi_text.plot_hr) sobre lo que haya. Los pixeles que tapa la prioridad de la imagen no se ponen (pri_plane, como hw_sprites, con los rangos de los objetos fijos). (agisw.asm lo hace por lineas, con un bufer, sin borrar nada.)"""
        import agi2spr
        import agi2hr
        pri2 = self.pri_plane()
        for n in self.draw_order():
            if True:
                o = self.objs[n]
                if o.x >= 160:
                    continue
                d = self.g.resource('VIEW', o.view)
                if d is None:
                    continue
                key = (o.view, o.loop)
                if key not in self.spr_big:
                    try:
                        self.spr_big[key] = o.loop < d[2] and len(agi2spr.build_loop(d, o.loop)) > 8190
                    except (IndexError, ValueError):
                        self.spr_big[key] = True
                if self.spr_big[key]:
                    continue
                c = agi2spr.cel_tiles(d, o.loop, o.cel)
                if c is None or not (agi2spr.meta(c[2], o.view)[0] or o.static):
                    continue
                hrw, h, tiles = c
                x0 = agi2spr.lo(o.x)
                cx0, s = x0 >> 3, x0 & 7
                top = o.y - h + 9
                for tx, ty, col, pix, msk in tiles:
                    for r in range(8):
                        line = top + ty * 8 + r
                        m = msk[r]
                        if line < 8 or line > 175 or m == 0:
                            continue
                        ink, paper = col[r] >> 4, col[r] & 15
                        if s == 0:
                            parts = [(cx0 + tx, m, pix[r])]
                        else:
                            parts = [(cx0 + tx, m >> s, pix[r] >> s), (cx0 + tx + 1, (m << (8 - s)) & 255, (pix[r] << (8 - s)) & 255)]
                        for cell, pm, pp in parts:
                            if pm == 0 or cell > 31:
                                continue
                            if pri2 is not None and 8 <= line < 176:
                                ok = 0      # el fondo tapa los pixeles de prioridad mayor (como en los sprites)
                                for bit in range(8):
                                    hx = cell * 8 + bit
                                    if pri2[(line - 8) * 160 + ((5 * hx) >> 3)] <= o.pri:
                                        ok |= 0x80 >> bit
                                pm &= ok
                                if pm == 0:
                                    continue
                            i = line * 32 + cell
                            if pm == 255:
                                sb[i] = pp
                                sa[i] = (paper << 4) | ink
                            else:
                                for bit in range(8):
                                    if pm & (0x80 >> bit):
                                        plot_hr(sb, sa, line, cell * 8 + bit, ink if pp & (0x80 >> bit) else paper)

    def render(self):
        """Plano de 168x32: la imagen con el texto que se le ha escrito encima."""
        import agi2hr
        if self.pic is None:
            bm = bytearray(168 * 32)
            at = bytearray(168 * 32)
        else:
            bm, at, _, _ = agi2hr.convert(self.pic)
            bm = bytearray(bm)
            at = bytearray(at)
        for op in self.pic_ops:
            if op[0] == 't':
                agi_text.put_line(bm, at, 8, *op[1:])
            else:
                agi_text.fill_row(bm, at, 8, op[1], op[2])
        return bm, at

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
    rs_keep = False
    txtm = False                # pantalla de texto (text.screen)
    ovl_n = None                # overlay.pic aplicado a lastpic
    hk_seen = False             # have.key sin tecla ya llamado en este ciclo

    def msg(self, n):
        ms = self.stack[-1][1]
        s = ms[n - 1] if 0 < n <= len(ms) and ms[n - 1] is not None else ''
        return self.fmt(s, self.stack[-1][2])

    # ------------------------------------------------------------ parser
    def parse(self, text):
        t = ag.norm_word(text.lower()).split()     # ' ` - " . se quitan sin separar (don't = dont); lo demas separa
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
            if not self.keyq and self.txtm and not self.hk_seen:        # en la pantalla de texto un bucle apretado (2a llamada del ciclo sin tecla) espera la tecla
                self.hk_seen = True
                return False
            if not self.keyq and self.txtm:
                while not self.keyq:
                    self.cycle += 1
                    if self.cycle > self.max_cycles:
                        raise Stop('fin de los ciclos en la pantalla de texto')
                    self.apply_events(self.ev.get(self.cycle, []))
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
        self.flags[2] = 0               # la logica 0 se reinicia sin la linea tecleada ni la palabra desconocida, como en AGI
        self.flags[0] = self.flags[3] = 0       # agua y linea de aviso: las de la sala anterior no valen
        v[9] = 0
        self.snd_stop()
        self.spans = []
        self.span_rows = 0
        for k, o in self.objs.items():
            if k != EGO:
                o.anim = o.drawn = False
        ego = self.obj(EGO)
        ego.drawn = False
        ego.upd = ego.cycling = ego.mon = True      # el ego sale de la sala listo para andar y sin prioridad fija aunque la anterior le hiciera stop.motion o set.priority
        ego.fixpri = False
        ego.ign_blocks = ego.ign_objs = False       # y observa bloques y objetos (la sala 7 de SQ1 lo deja con ignore.blocks e ignore.objs al cruzar su puerta)
        self.pcontrol = True
        self.blocks = None
        self.horizon = 36
        v[1] = old
        v[0] = n
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
        self.pics_used.add(n)
        self.lastpic = n
        self.ovl_n = None
        d = self.g.resource('PIC', n)
        if d is None:
            raise Stop('imagen %d inexistente' % n)
        self.pic = ag.Picture(d)
        self.pic_ops = []
        self.margins = []
        self.spans = []
        self.span_rows = 0
        for o in self.objs.values():
            if o.static:
                o.anim = o.drawn = o.static = False

    def c_add_to_pic(self, view, loop, cel, x, y, pri, margin):
        """Un objeto fijo en el ultimo hueco libre de 31 a 24 (no se mueve, no se cicla, no choca ni bloquea); un margen 0 o 1 pone una linea de control bajo la celda."""
        slot = next((k for k in range(31, 23, -1) if not (k in self.objs and self.objs[k].anim)), None)
        if slot is None:
            return
        o = self.objs[slot] = Obj()
        o.anim = o.drawn = o.fixpri = o.ign_horizon = o.ign_blocks = o.ign_objs = o.static = True
        o.upd = o.cycling = o.mon = False
        o.step = o.stime = o.scount = o.ctime = o.ccount = 0
        o.view, o.loop, o.cel, o.x, o.y, o.pri = view, loop, cel, x, y, pri
        self.add_spans(o)
        if margin < 2 and len(self.margins) < 8:
            self.margins.append((x, y, self.cell(o)[0], margin))

    def add_spans(self, o):
        """Lo que un objeto fijo tapa a los sprites: por cada fila de la celda, el rango de pixeles de AGI (5 * x // 8 del HiRes) del primer al ultimo pixel opaco."""
        import agi2spr
        d = self.g.resource('VIEW', o.view)
        c = agi2spr.cel_tiles(d, o.loop, o.cel) if d is not None else None
        if c is None or len(self.spans) >= 8:
            return
        h, tiles = c[1], c[2]
        ex_min = [255] * 128
        ex_max = [0] * 128
        x0 = agi2spr.lo(o.x)
        for tx, ty, col, pix, msk in tiles:
            for r in range(8):
                m, row = msk[r], ty * 8 + r
                if not m or row >= 128:
                    continue
                f = next(i for i in range(8) if m & (0x80 >> i))
                l = max(i for i in range(8) if m & (0x80 >> i))
                bx = x0 + tx * 8
                ex_min[row] = min(ex_min[row], min(255, (5 * (bx + f)) >> 3))
                ex_max[row] = max(ex_max[row], min(255, (5 * (bx + l)) >> 3))
        n = min(h, 128)
        if self.span_rows + n > 512:
            return
        pairs = []
        for i in range(n):
            a0, a1 = ex_min[i], min(ex_max[i], 159)
            pairs.append((255, 0) if a0 > 159 else (a0, a1))
        self.span_rows += n
        self.spans.append((o.y - h + 1, o.pri, pairs))

    def c_add_to_pic_v(self, *a): self.c_add_to_pic(*[self.vars[i] for i in a])

    def build_pic(self):
        """La imagen de lastpic y, si la tiene, su overlay.pic (que se dibuja encima sin borrar)."""
        p = ag.Picture(self.g.resource('PIC', self.lastpic))
        if self.ovl_n is not None:
            p = ag.Picture(self.g.resource('PIC', self.ovl_n), p)
        return p

    def c_overlay_pic(self, v):
        """La imagen de la sala con la superpuesta ya hecha (PICpnn.GFX en el Z80): se redibuja como graphics (los textos y los objetos fijos se rehacen)."""
        self.ovl_n = self.vars[v]
        self.ovl_pairs.add((self.lastpic, self.ovl_n))
        self.c_graphics()

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
            o.static = False

    def c_unanimate_all(self):
        for o in self.objs.values():
            o.anim = o.drawn = False

    def c_draw(self, n):
        o = self.obj(n)
        if not o.drawn:
            o.drawn = True
            self.cell(o)
            if agi2spr.frozen(o.view):              # vista congelada (agi2spr.FREEZE_VIEWS): casi no cicla
                o.ctime = o.ccount = 127
            self.fix_position(o)
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
    def c_reposition_to(self, n, x, y):
        self.c_position(n, x, y)
        self.fix_position(self.obj(n))

    def c_reposition_to_v(self, n, vx, vy): self.c_reposition_to(n, self.vars[vx], self.vars[vy])

    def check_position(self, o, x, y):
        """checkPosition de ScummVM: dentro de la pantalla y, si no ignora el horizonte, por debajo de el."""
        w, h = self.cell(o)
        if x < 0 or x + w > 160 or y - h < -1 or y >= 168:
            return False
        return o.ign_horizon or y > self.horizon

    def fix_position(self, o):
        """fixPosition de ScummVM: espiral (O, S, E, N) desde la posicion actual hasta un sitio valido (sin la zona de block, que no es de fixPosition).
        La posicion de entrada hace de posicion previa para el cruce de lineas base de los objetos; si la espiral da la vuelta a toda la pantalla se deja como estaba."""
        if not o.ign_horizon and o.y <= self.horizon:
            o.y = self.horizon + 1
        x0, y0 = o.x, o.y
        x, y = x0, y0
        blocks, self.blocks = self.blocks, None
        d, count, size = 0, 1, 1
        try:
            while not (self.check_position(o, x, y) and self.can_be_here(o, x, y)):
                if size > 170:
                    x, y = x0, y0
                    break
                if d == 0:
                    x -= 1
                elif d == 1:
                    y += 1
                elif d == 2:
                    x += 1
                else:
                    y -= 1
                count -= 1
                if count:
                    continue
                d = (d + 1) % 4
                if d in (2, 0):
                    size += 1
                count = size
        finally:
            self.blocks = blocks
        o.x, o.y = x, y
        self.set_pri(o)

    def c_reposition(self, n, vx, vy):
        o = self.obj(n)
        dx, dy = self.vars[vx], self.vars[vy]
        o.x += dx - 256 if dx >= 128 else dx
        o.y += dy - 256 if dy >= 128 else dy
        self.fix_position(o)

    def c_get_posn(self, n, vx, vy):
        o = self.obj(n)
        self.vars[vx], self.vars[vy] = o.x & 255, o.y & 255

    def c_set_view(self, n, view):
        o = self.obj(n)
        o.view = view
        if n == EGO:
            self.vars[16] = view            # v16 = la vista del ego (la logica 0 la vuelve a poner con set.view.v en cada sala nueva)
        self.loops(view)
        self.cell(o)                    # el bucle y la celda se conservan (cell los ajusta si la vista nueva no los tiene), como en AGI

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
    # ------------------------------------------------------------ pausa, inventario, ver objeto, reinicio
    def c_pause(self):
        self.do_print('Game paused.\n\nPress any key to continue.', None, None, 0)

    def c_status(self):
        """La ventana del inventario: lo que lleva el ego (objetos con la sala 255), uno por linea. Con la bandera 13 se elige uno (v25 = el objeto o 255): lista de un
        menu de una sola entrada."""
        names = [n[:36] for n in self.inv_names][:255]
        if self.flags[13]:
            items = [[n, i, True] for i, n in enumerate(names) if i < len(self.inv) and self.inv[i] == 255]
            if items:
                real = self.menus
                self.menus = [['You are carrying', items]]
                try:
                    r = self.menu_loop()
                finally:
                    if self.cycle <= self.max_cycles:
                        self.menus = real
                self.vars[25] = 255 if r is None else r
                return
            self.vars[25] = 255
        s = 'You are carrying:\n\n'
        any_ = False
        for i, n in enumerate(names):
            if self.inv[i] == 255 if i < len(self.inv) else False:
                if len(s) > 190:
                    continue
                s += n + '\n'
                any_ = True
        if not any_:
            s += 'Nothing\n'
        s += '\nPress any key to return\nto the game.'
        self.do_print(s, None, None, 0)

    def c_show_obj(self, n):
        """La descripcion de la vista n (el dibujo no se muestra): la cadena a la que apuntan los bytes 3-4 del recurso."""
        d = self.g.resource('VIEW', n)
        if not d or len(d) < 5:
            return
        off = d[3] | (d[4] << 8)
        if off == 0 or off >= len(d):
            return
        q = d.find(b'\x00', off)
        s = bytes(d[off:q if q >= 0 else len(d)]).decode('latin-1')[:239]
        pic = None
        if s:
            try:
                c = agi2spr.cel_tiles(d, 0, 0, framed=True)
            except IndexError:
                c = None
            if c and c[2] and c[0] <= 200 and c[1] <= 56:        # el dibujo: bucle 0, celda 0; delante del texto, las filas que ocupa y una en blanco
                s = '\n' * (((c[1] + 7) >> 3) + 1) + s
                pic = (c[0], c[2])
            self.do_print(s, None, None, 0, pic)

    def c_show_obj_v(self, v): self.c_show_obj(self.vars[v])

    RESTART_FIELDS = ('vars', 'flags', 'strs', 'objs', 'inv', 'keys', 'pic', 'pic_ops', 'margins', 'spans', 'span_rows', 'horizon', 'blocks', 'pcontrol',
                      'lastpic', 'ovl_n', 'lfsr', 'status_on', 'st_last', 'tfg', 'tbg', 'accept', 'sound_flags', 'input', 'said_done', 'keyq', 'textq', 'ctl', 'wtext', 'ext_bm', 'ext_at', 'box')

    def c_restart_game(self):
        """Confirmacion (ENTER reinicia, ESC sigue); el estado vuelve al del arranque y se sale de la logica en curso."""
        self.do_print('Press ENTER to restart\nthe game.\n\nPress ESC to continue\nthis game.', None, None, 0)
        if self.last_key != 13:
            return
        new = Interp(self.path, True)
        for k in self.RESTART_FIELDS:           # los contenedores se cambian por dentro: interpret_cycle guarda referencias a ellos
            cur, nw = getattr(self, k), getattr(new, k)
            if isinstance(cur, (list, bytearray)):
                cur[:] = nw
            elif isinstance(cur, (dict, set)):
                cur.clear()
                cur.update(nw)
            else:
                setattr(self, k, nw)
        self.flags[6] = 1                       # como AGI: la logica 0 conserva los menus y vuelve a la sala 2
        self.rs_keep = True
        self.exit_all = True

    def c_print(self, m): self.do_print(self.msg(m)[:250], None, None, 0)
    def c_print_v(self, v): self.c_print(self.vars[v])
    def c_print_at(self, m, r, c, w): self.do_print(self.msg(m)[:250], r, c, w)
    def c_print_at_v(self, vm, vr, vc, vw): self.c_print_at(self.vars[vm], self.vars[vr], self.vars[vc], self.vars[vw])

    def do_print(self, s, row, col, w, pic=None):
        """Ventana de mensaje: se dibuja y el interprete espera una tecla (un evento `key`); cada vuelta de la espera es un ciclo (con sus eventos). La tecla que la
        cierra no llega a la logica (v19 y la cola de teclas quedan como estaban). Si se acaban los ciclos con la ventana abierta, se queda en la pantalla."""
        width = w if 1 <= w <= 36 else 30
        lines = agi_text.wrap(s, width)
        self.log('print: ' + ' / '.join(lines))
        self.box = (lines, agi_text.box_geom(lines, row, col, ((pic[0] + 7) >> 3) + 2 if pic else 0), pic)
        n, v19 = len(self.keyq), self.vars[19]
        while True:
            self.cycle += 1
            if self.cycle > self.max_cycles:
                raise Stop('fin de los ciclos con una ventana abierta')
            self.apply_events(self.ev.get(self.cycle, []))
            if len(self.keyq) > n:
                break
        self.last_key = self.keyq[n]
        del self.keyq[n:]
        self.vars[19] = v19
        self.box = None
    def c_text_screen(self):
        """La pantalla de texto: las filas 1-21 en negro y sin sprites hasta graphics."""
        self.txtm = True
        for r in range(1, 22):
            self.pic_ops.append(('f', r, self.tbg))          # con el color de fondo del texto (set.text.attribute)

    def c_graphics(self):
        self.txtm = False
        if self.pic is None:                # sin imagen dibujada no hay nada que rehacer
            return
        self.pic = self.build_pic()
        self.pic_ops = []
        self.spans = []
        self.span_rows = 0
        for k in sorted(self.objs):
            o = self.objs[k]
            if k >= 24 and o.static and o.anim:
                self.add_spans(o)

    def c_display(self, r, c, m):
        s = self.msg(m)[:250]
        self.log('display %d,%d: %s' % (r, c, s))
        self.text_out(r, c, s)

    def c_display_v(self, vr, vc, vm): self.c_display(self.vars[vr], self.vars[vc], self.vars[vm])

    def text_out(self, r, c, s):
        row = r
        for line in s.split(chr(10)):
            if row > agi_text.ROWS:                 # AGI tiene 25 filas de texto; la 24 va a la 23 (el HiRes tiene 24)
                break
            t = agi_text.printable(line)[:max(0, agi_text.COLS - c)]
            if t:
                self.text_line(min(row, agi_text.ROWS - 1), c, t, self.tfg, self.tbg)
            row += 1

    def text_line(self, row, col, t, fg, bg):
        if 1 <= row <= 21:
            self.pic_ops.append(('t', row, col, t, fg, bg))
        else:
            agi_text.put_line(self.ext_bm, self.ext_at, 0, row, col, t, fg, bg)

    def c_clear_lines(self, a, b, c):
        for r in range(min(a, agi_text.ROWS - 1), min(b, agi_text.ROWS - 1) + 1):
            if 1 <= r <= 21:
                self.pic_ops.append(('f', r, c))
            else:
                agi_text.fill_row(self.ext_bm, self.ext_at, 0, r, c)

    def c_set_text_attribute(self, fg, bg): self.tfg, self.tbg = fg & 15, bg & 15

    def c_status_line_on(self):
        self.status_on = True
        self.st_last = None

    def c_status_line_off(self):
        self.status_on = False
        agi_text.fill_row(self.ext_bm, self.ext_at, 0, 0, 0)

    def status_tick(self):
        if not self.status_on:
            return
        key = (self.vars[3], self.vars[7], self.flags[9])
        if key == self.st_last:
            return
        self.st_last = key
        agi_text.fill_row(self.ext_bm, self.ext_at, 0, 0, 15)
        self.text_line(0, 0, ' Score:%d of %d' % (key[0], key[1]), 0, 15)
        self.text_line(0, 30, 'Sound:on' if key[2] else 'Sound:off', 0, 15)

    def c_set_string(self, s, m): self.strs[s] = self.msg(m)[:40]

    gs_on = False               # get.string esperando: las lineas escritas van a la cola de cadenas

    def c_get_string(self, s, m, r, c, ln):
        """Modal: cada vuelta es un ciclo (con sus eventos); acaba cuando llega una linea (evento `text` o `str`). Las teclas de la espera no llegan a la logica."""
        self.log('get.string: ' + self.msg(m))
        n, v19 = len(self.keyq), self.vars[19]
        self.gs_on = True
        while not self.textq:
            self.cycle += 1
            if self.cycle > self.max_cycles:
                raise Stop('fin de los ciclos en get.string')
            self.apply_events(self.ev.get(self.cycle, []))
            del self.keyq[n:]
            self.vars[19] = v19
        self.gs_on = False
        self.strs[s] = self.textq.pop(0)[:40]

    def save_desc(self):
        """La descripcion de la partida: una linea (evento `text` o `str`) o None si se cancela con ESC; la linea cuenta 30 caracteres."""
        n, v19 = len(self.keyq), self.vars[19]
        self.gs_on = True
        esc = False
        while not self.textq and not esc:
            self.cycle += 1
            if self.cycle > self.max_cycles:
                raise Stop('fin de los ciclos en la descripcion')
            self.apply_events(self.ev.get(self.cycle, []))
            esc = 27 in self.keyq[n:] and not self.textq
            del self.keyq[n:]
            self.vars[19] = v19
        self.gs_on = False
        return None if esc else self.textq.pop(0)[:30]

    def c_get_num(self, m, v):
        self.log('get.num: ' + self.msg(m))
        t = self.textq.pop(0) if self.textq else '0'
        self.vars[v] = int(t) & 255 if t.isdigit() else 0

    def c_word_to_string(self, n, s):
        self.strs[s] = (self.wtext[n] if n < len(self.wtext) else '')[:40]

    def c_parse(self, s):
        if not self.strs[s]:                # una cadena vacia no es una orden
            self.flags[2] = 0
            return
        self.input = self.parse(self.strs[s])
        self.said_done = False
        self.flags[2] = 1

    def c_prevent_input(self): self.accept = False
    def c_echo_line(self): pass                 # solo cambian la linea de entrada (modo real), que el modelo no tiene
    def c_cancel_line(self): pass
    def c_set_cursor_char(self, m): self.cursor = self.msg(m)[:1] or ' '
    def c_accept_input(self): self.accept = True
    def c_set_key(self, a, s, c): self.keys[a if a else {63: 28, 65: 30}.get(s, s << 8)] = c      # F5 y F7: codigos 28 y 30
    # ------------------------------------------------------------ menus
    def c_set_menu(self, m):
        if len(self.menus) < 8:
            self.menus.append([self.msg(m)[:36], []])

    def c_set_menu_item(self, m, c):
        if self.menus and sum(len(x[1]) for x in self.menus) < 48:
            self.menus[-1][1].append([self.menu_tag(self.msg(m)[:36]), c, True])

    @staticmethod
    def menu_tag(t):
        """La tecla del PC del texto de una opcion (<F5>, <Alt-Z>...): F5 y F7 pasan a <2> y <3> (teclas del ZX81); las demas se quitan con los espacios que las separan."""
        p = t.find('<')
        if p < 0:
            return t
        if t[p:p + 4] in ('<F5>', '<F7>'):
            return t[:p] + ('<2>' if t[p + 2] == '5' else '<3>')
        return t[:p].rstrip(' ')

    def c_submit_menu(self): pass

    def c_enable_item(self, c):
        for t, items in self.menus:
            for it in items:
                if it[1] == c:
                    it[2] = True

    def c_disable_item(self, c):
        for t, items in self.menus:
            for it in items:
                if it[1] == c:
                    it[2] = False

    def c_menu_input(self):
        if not self.menus or not self.flags[14]:
            return                      # f14: los menus estan disponibles (el juego lo enciende al salir de la intro)
        if self.keyq and self.keyq[-1] in self.keys:
            self.keyq.pop()             # la tecla que lo abre (un controlador) no llega a have.key
            self.vars[19] = 0
        r = self.menu_loop()
        if r is not None:
            self.ctl.add(r)

    def menu_loop(self, start=0):
        """Modal como print: cada vuelta es un ciclo; las flechas (cambios de la direccion a 1, 3, 5, 7) mueven, ENTER elige (devuelve el controlador del elemento si
        esta activado) y ESC cierra (None); la tecla no llega a la logica."""
        sel, it = 0, start              # start: la primera linea elegible (la lista de ranuras tiene antes las del titulo)
        self.menu_ui = [sel, it]
        n0, v19 = len(self.keyq), self.vars[19]
        prev = self.dirhold
        res = None
        done = False
        while not done:
            self.cycle += 1
            if self.cycle > self.max_cycles:
                raise Stop('fin de los ciclos con un menu abierto')
            self.apply_events(self.ev.get(self.cycle, []))
            d = self.dirhold
            if d != prev:
                prev = d
                cnt = len(self.menus[sel][1])
                if d == 7:
                    sel, it = (sel - 1) % len(self.menus), start
                elif d == 3:
                    sel, it = (sel + 1) % len(self.menus), start
                elif d == 5 and cnt:
                    it = it + 1 if it + 1 < cnt else start
                elif d == 1 and cnt:
                    it = cnt - 1 if it == start else it - 1
                self.menu_ui = [sel, it]
            if len(self.keyq) > n0:
                k = self.keyq[n0]
                del self.keyq[n0:]
                if k == 27:
                    done = True
                elif k == 13 and self.menus[sel][1] and self.menus[sel][1][it][2]:
                    res = self.menus[sel][1][it][1]
                    done = True
        del self.keyq[n0:]
        self.vars[19] = v19
        self.menu_ui = None
        self.st_last = None
        return res

    # ------------------------------------------------------------ guardar y cargar partida
    def snapshot(self):
        import copy
        return copy.deepcopy(dict(vars=self.vars, flags=self.flags, strs=self.strs, inv=self.inv, keys=self.keys, objs=self.objs, horizon=self.horizon, blocks=self.blocks,
                                  pcontrol=self.pcontrol, lastpic=self.lastpic, ovl_n=self.ovl_n, margins=self.margins, status_on=self.status_on, tfg=self.tfg, tbg=self.tbg,
                                  accept=self.accept, ticks=self.ticks))

    def c_save_game(self): self.save_load(False)
    def c_restore_game(self): self.save_load(True)

    def save_load(self, load):
        """La lista de 12 ranuras es un menu de una sola entrada con el bucle de menu.input (antes, las lineas del titulo, desactivadas); al guardar se pide la
        descripcion (como get.string, con la anterior de texto inicial; ESC cancela) y en los dos casos se confirma con ENTER (ESC cancela).
        Las partidas se guardan en self.saves (el Z80, en SAV/GAMEnn.SAV)."""
        if load:
            ins = ['Use the arrow keys to select the', 'game which you wish to restore.', 'Press ENTER to restore the game,', 'ESC to not restore a game.']
        else:
            ins = ['Use the arrow keys to select the', 'slot in which you wish to save', 'the game.', 'Press ENTER to save in the slot,', 'ESC to not save a game.']
        items = [[t, 0, False] for t in ins]
        for n in range(1, 13):
            s = self.saves.get(n)
            items.append(['%02d:%s' % (n, s[0] if s else '(empty)'), n, (s is not None) if load else True])
        real = self.menus
        self.menus = [['Restore game' if load else 'Save game', items]]
        try:
            r = self.menu_loop(len(ins))
        finally:
            if self.cycle <= self.max_cycles:
                self.menus = real
        if r is None:
            return
        if not load:
            desc = self.save_desc()
            if desc is None:
                return
        else:
            desc = self.saves[r][0]
        self.do_print(('About to %s the game\ndescribed as:\n%s\n%s:\nGAME%02d.SAV\n\nPress ENTER to continue.\nPress ESC to cancel.'
                       % ('restore' if load else 'save', desc, 'from file' if load else 'in file', r)), None, None, 0)
        if self.last_key != 13:
            return
        if not load:
            self.saves[r] = (desc, self.snapshot())
            return
        import copy
        st = copy.deepcopy(self.saves[r][1])
        self.snd_stop()
        self.vars[:] = st['vars']
        self.flags[:] = st['flags']
        self.strs[:] = st['strs']
        self.inv[:] = st['inv']
        self.keys = st['keys']
        self.objs = st['objs']
        for k in ('horizon', 'blocks', 'pcontrol', 'lastpic', 'ovl_n', 'margins', 'status_on', 'tfg', 'tbg', 'accept', 'ticks'):
            setattr(self, k, st[k])
        self.flags[6] = 1
        self.rs_keep = True
        for t, its in self.menus:
            for it in its:
                it[2] = True
        self.st_last = None
        self.pics_used.add(self.lastpic)
        self.pic = self.build_pic()
        self.pic_ops = []
        self.spans = []
        self.span_rows = 0
        for k in sorted(self.objs):
            o = self.objs[k]
            if k >= 24 and o.static and o.anim:
                self.add_spans(o)
        self.exit_all = True

    def draw_menu(self, sb, sa):
        import agi2hr
        sel, it = self.menu_ui
        agi_text.fill_row(sb, sa, 0, 0, 15)
        col = 0
        cols = []
        for i, (t, items) in enumerate(self.menus):
            txt = ' ' + t + ' '
            fg, bg = (15, 0) if i == sel else (0, 15)
            agi_text.put_line(sb, sa, 0, 0, col, txt, fg, bg)
            cols.append(col)
            col += len(txt)
        items = self.menus[sel][1]
        if not items:
            return
        mx = max(len(x[0]) for x in items)
        bw = (6 * (mx + 2) + 7) >> 3
        cxl = min((cols[sel] * 6) >> 3, 32 - bw)
        for i, (t, c, en) in enumerate(items):
            on = i == it
            fg = (15 if on else 0) if en else 8
            bg = 0 if on else 15
            fgc, bgc = agi2hr.to_chroma(fg), agi2hr.to_chroma(bg)
            for k in range(8):
                for cell in range(cxl, cxl + bw):
                    sb[((1 + i) * 8 + k) * 32 + cell] = 0
                    sa[((1 + i) * 8 + k) * 32 + cell] = (bgc << 4) | fgc
            agi_text.put_line(sb, sa, 0, 1 + i, 0, ' ' + t.ljust(mx) + ' ', fg, bg, x0=8 * cxl)

    def sound_ticks(self, n):
        """Duracion de un sonido en 1/60 s: lo que tarda en acabar el ultimo de sus cuatro canales (el sonido acaba cuando han acabado todos)."""
        try:
            d = self.g.resource('SND', n)
        except ValueError:
            return 0
        if not d or len(d) < 8:
            return 0
        best = 0
        for c in range(4):
            p = d[2 * c] | (d[2 * c + 1] << 8)
            t = 0
            while p + 5 <= len(d):
                dur = d[p] | (d[p + 1] << 8)
                if dur == 0xFFFF:
                    break
                t += dur
                p += 5
            best = max(best, t)
        return min(best, 0xFFFF)

    def sound_cycles(self, n):
        """Ciclos del interprete que dura: t/60 s a 20/v10 ciclos por segundo, redondeado (aritmetica entera, como el Z80)."""
        t = self.sound_ticks(n)
        v10 = max(1, self.vars[10])
        return max(2, (2 * t + 3 * v10) // (6 * v10))

    def snd_stop(self):
        """Las banderas de los sonidos pendientes se ponen y quedan libres (stopSound)."""
        for t, f in self.sound_flags:
            self.flags[f] = 1
        self.sound_flags = []

    def c_sound(self, n, f):
        self.snd_stop()
        self.flags[f] = 0
        self.sound_flags = [x for x in self.sound_flags if x[1] != f]
        self.sound_flags.append((self.cycle + self.sound_cycles(n), f))
        self.log('sound %d (%d ciclos)' % (n, self.sound_flags[-1][0] - self.cycle))

    def c_stop_sound(self): self.snd_stop()
    def c_set_game_id(self, m): self.log('juego: ' + self.msg(m))
    def c_log(self, m): pass
    def c_quit(self, n):
        self.log('quit')
        self.stop = True


    def c_version(self): pass

    # ------------------------------------------------------------ movimiento y ciclo
    def can_be_here(self, o, x, y):
        w, h = self.cell(o)
        if x < 0 or x + w > 160 or y - h < -1 or y > 167:
            return True                       # los bordes se tratan aparte
        if not o.ign_horizon and y <= self.horizon:
            return False
        if self.blocks and not o.ign_blocks:
            bx1, by1, bx2, by2 = self.blocks
            # como changePos/checkBlock de ScummVM: la zona de block no se cruza ni hacia dentro ni hacia fuera (el punto x,y, limites excluidos)
            if (bx1 < x < bx2 and by1 < y < by2) != (bx1 < o.x < bx2 and by1 < o.y < by2):
                return False
        if self.pic and self.use_pic:
            pri = self.pic.pri
            water = land = 0
            sig = False
            for i in range(w):
                c = pri[y * ag.W + x + i]
                if c == 0:                      # la linea 0 bloquea siempre; ignore.blocks solo salta las 1 y el rectangulo
                    return False
                if c == 1 and not o.ign_blocks and o is self.objs.get(EGO):
                    return False
                if c == 3:
                    water += 1
                else:
                    land += 1
                if c == 2:
                    sig = True
            for mx, my, mw, mc in self.margins:
                if y == my and x < mx + mw and mx < x + w:
                    if mc == 0:
                        return False
                    if mc == 1 and not o.ign_blocks and o is self.objs.get(EGO):
                        return False
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
                    self.pcontrol = True        # el ego que llega a su destino recupera el control del jugador
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
        else:
            self.fix_position(o)
            border = 0                        # updatePosition de ScummVM: si el paso se rechaza, el borde se descarta
            if o.motion == 1:
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
        f2 = b(o.ign_blocks) | b(o.ign_objs) << 1 | b(o.static) << 2
        return [f1, f2, o.view, o.loop, o.cel, o.x & 255, o.y & 255, o.pri & 255, o.ctype, o.ctime & 255, o.ccount & 255, o.cflag,
                o.motion, o.step & 255, o.stime & 255, o.scount & 255, o.dir, o.water, o.tx & 255, o.ty & 255, o.mstep & 255, o.mflag,
                o.wander & 255]

    def objsum(self):
        t = self.horizon + b2(self.pcontrol) + b2(self.blocks)
        for k in range(self.NOBJ):
            if k in self.objs:
                t += sum(self.objbytes(self.objs[k]))
        return t & 0xFFFF

    def strsum(self):
        return sum(ord(c) + 1 for t in self.strs for c in t) & 0xFFFF

    def miscsum(self):
        t = 0 if self.input is None else 1 + len(self.input) + sum((w & 255) + (w >> 8) for w in self.input)
        t += 97 * b2(self.said_done) + 13 * len(self.keyq) + 5 * len(self.textq) + 3 * len(self.wtext) + 7 * len(self.ctl)
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

    def apply_events(self, events):
        v = self.vars
        for kind, val in events:
            if kind == 'text' and self.gs_on:
                self.textq.append(val)
            elif kind == 'text':
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

    def interpret_cycle(self, events):
        v = self.vars
        self.hk_seen = False
        self.ctl = set()
        self.apply_events(events)
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
        v[2] = v[4] = v[5] = 0          # los codigos de borde se ponen a 0 antes de mover los objetos: el movimiento los pone y la logica del ciclo siguiente los ve
        self.update_objects()
        self.status_tick()
        self.flags[2] = self.flags[4] = 0
        if self.rs_keep:                # tras restart.game / restore.game las banderas 5 y 6 las ve la logica 0 del ciclo siguiente
            self.rs_keep = False
        else:
            self.flags[5] = self.flags[6] = 0
        self.input = None
        self.keyq = []
        self.tick_clock()
        self.summ.append((self.cycle, self.nsteps, sum(v) & 0xFFFF, sum(i for i in range(256) if self.flags[i]) & 0xFFFF, v[0], self.objsum(), self.strsum(), self.miscsum()))
        self.nsteps = 0

    def play(self, cycles, script):
        ev = {}
        for item in script:
            c, k, val = item.split(':', 2)
            ev.setdefault(int(c), []).append((k, val))
        self.ev = ev
        self.max_cycles = cycles
        self.cycle = 0
        while self.cycle < cycles:
            self.cycle += 1
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
    lp = None
    for i, a in enumerate(argv):
        if a == '--listpics':
            lp = argv[i + 1]
        if a == '--trace':
            tr = argv[i + 1]
            it.trace = []
    it.play(cycles, parse_script(script))
    if lp:
        with open(lp, 'w') as f:
            f.write(' '.join([str(n) for n in sorted(it.pics_used)] + ['%d+%d' % p for p in sorted(it.ovl_pairs)]))
    if tr:
        with open(tr, 'w') as f:
            for n, p in it.trace:
                f.write('T %d %d\n' % (n, p))
            for c in it.summ:
                f.write('C %d %d %d %d %d %d %d %d\n' % c)
    ego = it.obj(EGO)
    print('fin: sala %d, ciclo %d, ego en %d,%d, v0..v9 = %s' % (it.vars[0], it.cycle, ego.x, ego.y, it.vars[:10]))
    if it.noop:
        print('comandos sin modelar:', ', '.join('%s x%d' % kv for kv in sorted(it.noop.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
