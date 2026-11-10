#!/usr/bin/env python3
"""Modelo de la VM de SCI0 para medir (no para jugar).

Copia la semantica de ScummVM engines/sci (vm.cpp, kernel, animate.cpp,
compare.cpp, kmovement.cpp, picture.cpp) con el modelo de memoria del
interprete original de Sierra: un heap plano de 64 KB con punteros de 16 bits
donde viven los scripts (codigo + objetos + locales + cadenas), los clones,
las listas y la pila. Los recursos (vistas, imagenes, sonidos...) van en el
"hunk", fuera del heap, como en SCIV.EXE.

Cuenta, por ciclo de juego (cada llamada a Animate con el reparto), los
bytecodes ejecutados por opcode y por categoria (movimiento, ciclado,
resto), las llamadas al kernel y su trabajo (pixeles mirados, nodos, etc.),
y la ocupacion del heap y del hunk.
"""
import math
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sci0res import ResMan, vocab_strings, script_blocks  # noqa: E402
import sci0pic  # noqa: E402

DEFAULT_KERNEL = ("Load UnLoad ScriptID DisposeScript Clone DisposeClone IsObject RespondsTo DrawPic Show "
                  "PicNotValid Animate SetNowSeen NumLoops NumCels CelWide CelHigh DrawCel AddToPic NewWindow "
                  "GetPort SetPort DisposeWindow DrawControl HiliteControl EditControl TextSize Display GetEvent "
                  "GlobalToLocal LocalToGlobal MapKeyToDir DrawMenuBar MenuSelect AddMenu DrawStatus Parse Said "
                  "SetSynonyms HaveMouse SetCursor SaveGame RestoreGame RestartGame GameIsRestarting DoSound "
                  "NewList DisposeList NewNode FirstNode LastNode EmptyList NextNode PrevNode NodeValue AddAfter "
                  "AddToFront AddToEnd FindKey DeleteKey Random Abs Sqrt GetAngle GetDistance Wait GetTime StrEnd "
                  "StrCat StrCmp StrLen StrCpy Format GetFarText ReadNumber BaseSetter DirLoop CanBeHere OnControl "
                  "InitBresen DoBresen Platform SetJump SetDebug InspectObj ShowSends ShowObjs ShowFree MemoryInfo "
                  "StackUsage Profiler GetMenu SetMenu GetSaveFiles GetCWD CheckFreeSpace ValidPath CoordPri StrAt "
                  "DeviceInfo GetSaveDir CheckSaveGame ShakeScreen FlushResources SinMult CosMult SinDiv CosDiv "
                  "Graph Joystick ShiftScreen Palette MemorySegment Intersections Memory ListOps FileIO DoAudio "
                  "DoSync AvoidPath").split()

OPNAMES = ("bnot add sub mul div mod shr shl xor and or neg not eq ne gt ge lt le ugt uge ult ule bt bnt jmp "
           "ldi push pushi toss dup link call callk callb calle ret send op26 op27 class op29 self super rest "
           "lea selfID op2f pprev pToa aTop pTos sTop ipToa dpToa ipTos dpTos lofsa lofss push0 push1 push2 "
           "pushSelf line").split()
for _v in ('a', 's'):
    pass
_VT = 'gltp'
OPNAMES += ['l%s%s' % ('a', t) for t in _VT] + ['l%s%s' % ('s', t) for t in _VT]
OPNAMES += ['l%s%si' % ('a', t) for t in _VT] + ['l%s%si' % ('s', t) for t in _VT]
OPNAMES += ['s%s%s' % ('a', t) for t in _VT] + ['s%s%s' % ('s', t) for t in _VT]
OPNAMES += ['s%s%si' % ('a', t) for t in _VT] + ['s%s%si' % ('s', t) for t in _VT]
OPNAMES += ['plus%s%s' % ('a', t) for t in _VT] + ['plus%s%s' % ('s', t) for t in _VT]
OPNAMES += ['plus%s%si' % ('a', t) for t in _VT] + ['plus%s%si' % ('s', t) for t in _VT]
OPNAMES += ['minus%s%s' % ('a', t) for t in _VT] + ['minus%s%s' % ('s', t) for t in _VT]
OPNAMES += ['minus%s%si' % ('a', t) for t in _VT] + ['minus%s%si' % ('s', t) for t in _VT]
assert len(OPNAMES) == 128

# formatos de operandos (g_base_opcode_formats): 'v' = byte si bit0, word si no;
# 's' igual con signo; 'B' byte; 'W' word
FMT = [()] * 0x17 + [('s',), ('s',), ('s',), ('s',), (), ('s',), (), (), ('v',),
                     ('s', 'B'), ('v', 'B'), ('v', 'B'), ('v', 's', 'B'), (), ('B',), None, None,
                     ('v',), None, ('B',), ('v', 'B'), ('s',), ('s', 'v'), (), None,
                     (), ('v',), ('v',), ('v',), ('v',), ('v',), ('v',), ('v',),
                     ('v',), ('s',), ('s',), (), (), (), (), ('W',)] + [('v',)] * 64
assert len(FMT) == 128

# engines/sci/engine/static_selectors.cpp (sci0Selectors), para juegos sin vocab 997
STATIC_SCI0_SELECTORS = ('y x view loop cel underBits nsTop nsLeft nsBottom nsRight lsTop lsLeft lsBottom '
                         'lsRight signal illegalBits brTop brLeft brBottom brRight name key time text elements '
                         'color back mode style state font type window cursor max mark who message edit play '
                         'number handle client dx dy b-moveCnt b-i1 b-i2 b-di b-xAxis b-incr xStep yStep '
                         'moveSpeed canBeHere heading mover doit isBlocked looper priority modifiers replay '
                         'setPri at next done width wordFail syntaxFail semanticFail pragmaFail said claimed '
                         'value save restore title button icon draw delete z').split()

SIG_STOPUPDATE, SIG_VIEWUPDATED, SIG_NOUPDATE, SIG_HIDDEN = 1, 2, 4, 8
SIG_FIXEDPRI, SIG_ALWAYSUPDATE, SIG_FORCEUPDATE, SIG_REMOVEVIEW = 0x10, 0x20, 0x40, 0x80
SIG_FROZEN, SIG_HITOBSTACLE, SIG_DOESNTTURN = 0x100, 0x400, 0x800
SIG_IGNOREACTOR, SIG_DISPOSEME = 0x4000, 0x8000

KEY2DIR = {72 << 8: 1, 73 << 8: 2, 77 << 8: 3, 81 << 8: 4, 80 << 8: 5, 79 << 8: 6, 75 << 8: 7, 71 << 8: 8,
           76 << 8: 0}
ARROWS = [72 << 8, 77 << 8, 80 << 8, 75 << 8, 72 << 8, 77 << 8, 80 << 8, 75 << 8, 76 << 8]   # flechas y parar (5)

HEAP_LO, HEAP_HI = 0x0400, 0xF000     # zona del asignador
STACK_LO, STACK_HI = 0xF000, 0x10000  # pila de la PMachine (4 KB)
TICKS_PER_OP = 1.0 / 3000.0           # el reloj tambien avanza con el trabajo


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


class VMError(Exception):
    pass


class Heap:
    """Asignador first-fit con 2 bytes de cabecera por bloque (como SCIV)."""

    def __init__(self, mem):
        self.mem = mem
        self.free = [(HEAP_LO, HEAP_HI - HEAP_LO)]
        self.blocks = {}   # direccion -> (tamanio, etiqueta)
        self.used = 0
        self.peak = 0

    def alloc(self, size, tag):
        size = (size + 1) & ~1
        need = size + 2
        for i, (a, n) in enumerate(self.free):
            if n >= need:
                if n - need >= 4:
                    self.free[i] = (a + need, n - need)
                else:
                    need = n
                    del self.free[i]
                addr = a + 2
                self.blocks[addr] = (need, tag)
                self.used += need
                if self.used > self.peak:
                    self.peak = self.used
                self.mem[addr:addr + size] = bytes(size)
                return addr
        raise VMError('heap lleno: %d B pedidos para %s, usados %d' % (size, tag, self.used))

    def free_block(self, addr):
        if addr not in self.blocks:
            return
        need, tag = self.blocks.pop(addr)
        self.used -= need
        a = addr - 2
        self.free.append((a, need))
        self.free.sort()
        merged = []
        for b, n in self.free:
            if merged and merged[-1][0] + merged[-1][1] == b:
                merged[-1] = (merged[-1][0], merged[-1][1] + n)
            else:
                merged.append((b, n))
        self.free = merged

    def by_tag(self):
        out = {}
        for need, tag in self.blocks.values():
            k = tag[0] if isinstance(tag, tuple) else tag
            out[k] = out.get(k, 0) + need
        return out


class Obj:
    __slots__ = ('addr', 'nvars', 'varsel', 'methods', 'is_class', 'script', 'name', 'clone', 'species')

    def __init__(self):
        self.clone = False


class Script:
    def __init__(self, num, base, size, buf):
        self.num = num
        self.base = base
        self.size = size
        self.buf = buf
        self.exports = []
        self.locals_addr = 0
        self.nlocals = 0
        self.objs = []
        self.code_bytes = 0
        self.lockers = 1


class Frame:
    __slots__ = ('obj', 'locals', 'fp', 'argp', 'argc', 'cat', 'name')


class Cycle:
    """Estadisticas de un ciclo de juego."""
    __slots__ = ('room', 'ops', 'cat', 'kcalls', 'kwork', 'heap', 'hunk', 'cast', 'wait', 'sends', 'ticks')


class VM:
    def __init__(self, path, log=None, seed=1):
        self.rm = ResMan(path)
        self.log = log
        self.mem = bytearray(0x10000)
        self.heap = Heap(self.mem)
        self.rng = random.Random(seed)
        names = vocab_strings(self.rm, 997)
        if not names:
            names = STATIC_SCI0_SELECTORS + ['#%d' % i for i in range(len(STATIC_SCI0_SELECTORS), 1000)]
        self.selname = names
        self.sel = {}
        for i, n in enumerate(names):
            self.sel.setdefault(n, i)
        kn = vocab_strings(self.rm, 999)
        if kn:
            cnt = struct.unpack_from('<H', self.rm.get('vocab', 999), 0)[0]
            kn = kn[:cnt]
            kn = kn + DEFAULT_KERNEL[len(kn):]
        self.kname = kn if kn else DEFAULT_KERNEL
        d = self.rm.get('vocab', 996)
        self.class_script = [struct.unpack_from('<H', d, i + 2)[0] for i in range(0, len(d) - 3, 4)]
        self.class_addr = {}
        self.scripts = {}
        self.objects = {}
        self.clone_count = 0
        self.lists = set()
        self.acc = 0
        self.prev = 0
        self.rest = 0
        self.sp = STACK_LO
        self.sp_peak = STACK_LO
        self.depth = 0
        self.depth_peak = 0
        self.ticks = 0.0
        self.last_wait = 0.0
        self.ops_total = 0
        self.lookup_cache = {}
        self.lookup_cost = {}
        self.hunk = {}           # (tipo, num) -> bytes
        self.hunk_peak = 0
        self.bits = {}           # handle -> bytes
        self.bits_next = 1
        self.ports = {}
        self.port_next = 1
        self.cur_port = 0
        self.screen = sci0pic.Screen()
        self.views = {}
        self.fonts = {}
        self.sounds = {}         # obj -> fin (ticks)
        self.pic_not_valid = 0
        self.old_gfx = 'motionCue' not in self.sel
        self.screen.init_bands(self.old_gfx)
        self.cycles = []
        self.cur = self._new_cycle()
        self.cat_stack = []
        self.kstack = []
        self.in_anim = 0
        self.fstack = []
        self.cyc_ops = 0
        self.walk = False
        self.walk_next = 0
        self.tour = []
        self.tour_next = 0
        self.tour_ticks = 1800
        self.inputs = {}
        self.class_cat = {}
        self.stop = False
        self.max_cycles = 10 ** 9
        self.max_ops = 10 ** 12
        self.trace_kernel = False
        self.pics_drawn = []
        self.kfuncs = self._kernel_table()

    # ------------------------------------------------------------ memoria
    def rw(self, a):
        a &= 0xFFFF
        return self.mem[a] | (self.mem[(a + 1) & 0xFFFF] << 8)

    def ww(self, a, v):
        a &= 0xFFFF
        self.mem[a] = v & 0xFF
        self.mem[(a + 1) & 0xFFFF] = (v >> 8) & 0xFF

    def rstr(self, a):
        a &= 0xFFFF
        e = self.mem.find(b'\0', a)
        if e < 0:
            e = len(self.mem)
        return bytes(self.mem[a:e]).decode('latin-1')

    def wstr(self, a, s):
        b = s.encode('latin-1') + b'\0'
        self.mem[a:a + len(b)] = b

    def text(self, v, index=0):
        """lookupText: puntero al heap o (recurso de texto, indice)."""
        if v >= 1000:
            return self.rstr(v)
        d = self.load_res('text', v)
        if d is None:
            return ''
        parts = d.split(b'\0')
        return parts[index].decode('latin-1') if index < len(parts) else ''

    # ------------------------------------------------------------ hunk
    def load_res(self, t, n):
        k = (t, n)
        if k not in self.hunk:
            d = self.rm.get(t, n)
            if d is None:
                return None
            self.hunk[k] = d
            self._hunk_update()
        return self.hunk[k]

    def _hunk_update(self):
        tot = sum(len(v) for v in self.hunk.values()) + sum(len(v) for v in self.bits.values())
        if tot > self.hunk_peak:
            self.hunk_peak = tot

    def hunk_by_type(self):
        out = {}
        for (t, n), d in self.hunk.items():
            out[t] = out.get(t, 0) + len(d)
        out['bits'] = sum(len(v) for v in self.bits.values())
        return out

    def view(self, n):
        v = self.views.get(n)
        if v is None:
            d = self.load_res('view', n)
            if d is None:
                raise VMError('vista %d no existe' % n)
            v = sci0pic.View(d)
            self.views[n] = v
        return v

    def font(self, n):
        f = self.fonts.get(n)
        if f is None:
            d = self.load_res('font', n)
            f = sci0pic.Font(d) if d else None
            self.fonts[n] = f
        return f

    # ------------------------------------------------------------ scripts
    def load_script(self, n):
        s = self.scripts.get(n)
        if s is not None:
            return s
        buf = self.rm.get('script', n)
        if buf is None:
            raise VMError('script %d no existe' % n)
        base = self.heap.alloc(len(buf), ('script', n))
        self.mem[base:base + len(buf)] = buf
        s = Script(n, base, len(buf), buf)
        self.scripts[n] = s
        blocks = script_blocks(buf)
        for t, p, sz in blocks:
            if t == 8:   # punteros a reubicar
                cnt = struct.unpack_from('<H', buf, p + 4)[0]
                for i in range(cnt):
                    o = struct.unpack_from('<H', buf, p + 6 + i * 2)[0]
                    if o + 1 < len(buf):
                        self.ww(base + o, self.rw(base + o) + base)
            elif t == 7:
                cnt = struct.unpack_from('<H', buf, p + 4)[0]
                s.exports = list(struct.unpack_from('<%dH' % cnt, buf, p + 6))
            elif t == 10:
                s.locals_addr = base + p + 4
                s.nlocals = (sz - 4) // 2
            elif t == 2:
                s.code_bytes += sz
        # objetos y clases
        pend = []
        for t, p, sz in blocks:
            if t not in (1, 6):
                continue
            o = Obj()
            o.addr = base + p + 12
            o.script = n
            o.is_class = (t == 6)
            o.nvars = struct.unpack_from('<H', buf, p + 10)[0]
            funcarea = struct.unpack_from('<H', buf, p + 8)[0]
            mbo = p + 12 + funcarea - 2
            mc = struct.unpack_from('<H', buf, mbo)[0]
            sels = struct.unpack_from('<%dH' % mc, buf, mbo + 2)
            offs = struct.unpack_from('<%dH' % mc, buf, mbo + 4 + mc * 2)
            o.methods = {sl: base + of for sl, of in zip(sels, offs)}
            if o.is_class:
                o.varsel = list(struct.unpack_from('<%dH' % o.nvars, buf, p + 12 + o.nvars * 2))
                sp = struct.unpack_from('<H', buf, p + 12)[0]
                self.class_addr[sp] = o.addr
            else:
                o.varsel = None
            o.species = struct.unpack_from('<H', buf, p + 12)[0]
            s.objs.append(o)
            self.objects[o.addr] = o
            pend.append(o)
        # especie y superclase pasan a direcciones (initSpecies/initBaseObject)
        for o in pend:
            spn = o.species
            sup = self.rw(o.addr + 2)
            ca = self.get_class(spn)
            self.ww(o.addr, ca)
            if o.is_class:
                self.ww(o.addr + 2, self.get_class(sup) if sup != 0xFFFF else 0)
            else:
                self.ww(o.addr + 2, self.get_class(sup) if sup != 0xFFFF else 0)
                o.varsel = self.objects[ca].varsel
            nm = self.rw(o.addr + 6) if o.nvars > 3 else 0
            o.name = self.rstr(nm) if nm else '?'
        return s

    def get_class(self, spn):
        a = self.class_addr.get(spn)
        if a is None:
            if spn >= len(self.class_script):
                raise VMError('clase %d fuera de la tabla' % spn)
            self.load_script(self.class_script[spn])
            a = self.class_addr.get(spn)
            if a is None:
                raise VMError('clase %d no aparece en el script %d' % (spn, self.class_script[spn]))
        return a

    def dispose_script(self, n):
        s = self.scripts.get(n)
        if s is None or n == 0:
            return
        # como los lockers de ScummVM: un script con clases que siguen en uso no se descarga
        lo, hi = s.base, s.base + s.size
        for a, o in self.objects.items():
            if lo <= a < hi:
                continue
            sp, su = self.rw(a), self.rw(a + 2)
            if lo <= sp < hi or lo <= su < hi:
                self.kept_scripts = getattr(self, 'kept_scripts', 0) + 1
                return
        # Las clases de un script descargado se olvidan (se recargan al pedirlas)
        for o in s.objs:
            self.objects.pop(o.addr, None)
            if o.is_class:
                for k, v in list(self.class_addr.items()):
                    if v == o.addr:
                        del self.class_addr[k]
        self.heap.free_block(s.base)
        del self.scripts[n]
        self.lookup_cache.clear()

    def script_of(self, addr):
        for s in self.scripts.values():
            if s.base <= addr < s.base + s.size:
                return s
        return None

    # ------------------------------------------------------------ objetos
    def lookup(self, obj, sel):
        """lookupSelector: ('v', direccion) o ('m', codigo, script del codigo)."""
        o = self.objects.get(obj)
        if o is None:
            raise VMError('send a algo que no es un objeto: %04x (sel %s)' % (obj, self.sname(sel)))
        key = (obj, sel) if o.clone or not o.is_class else (obj, sel)
        r = self.lookup_cache.get(key)
        if r is not None:
            return r
        vs = o.varsel
        cost = 0
        if vs is not None:
            try:
                i = vs.index(sel)
                if i < o.nvars:
                    r = ('v', obj + 2 * i)
                    self.lookup_cache[key] = r
                    self.lookup_cost[key] = (i + 1, 0)
                    return r
            except ValueError:
                pass
            cost = len(vs)
        cur = o
        seen = 0
        while cur is not None and seen < 64:
            m = cur.methods.get(sel)
            if m is not None:
                ml = list(cur.methods)
                cost += ml.index(sel) + 1
                r = ('m', m, cur)
                self.lookup_cache[key] = r
                self.lookup_cost[key] = (cost, seen)
                return r
            cost += len(cur.methods)
            sup = self.rw(cur.addr + 2)
            cur = self.objects.get(sup) if sup else None
            seen += 1
        return None

    def sname(self, sel):
        return self.selname[sel] if sel < len(self.selname) else '#%d' % sel

    def rsel(self, obj, name):
        sl = self.sel.get(name)
        if sl is None:
            return 0
        r = self.lookup(obj, sl)
        if r is None or r[0] != 'v':
            return 0
        return self.rw(r[1])

    def wsel(self, obj, name, v):
        sl = self.sel.get(name)
        if sl is None:
            return
        r = self.lookup(obj, sl)
        if r is None or r[0] != 'v':
            return
        self.ww(r[1], v)

    def has_var(self, obj, name):
        sl = self.sel.get(name)
        if sl is None:
            return False
        r = self.lookup(obj, sl)
        return r is not None and r[0] == 'v'

    def invoke(self, obj, name, args=()):
        """invokeSelector: envia un selector desde el kernel."""
        sl = self.sel.get(name)
        if sl is None:
            return self.acc
        base = self.sp
        self.ww(base, sl)
        self.ww(base + 2, len(args))
        for i, a in enumerate(args):
            self.ww(base + 4 + 2 * i, a)
        self.sp = base + 4 + 2 * len(args)
        self.send(obj, obj, base, 2 + len(args), self.sp)
        self.sp = base
        return self.acc

    def obj_cat(self, o):
        c = self.class_cat.get(o.addr)
        if c is not None:
            return c
        names = []
        cur = o
        n = 0
        while cur is not None and n < 32:
            names.append(cur.name)
            sup = self.rw(cur.addr + 2)
            cur = self.objects.get(sup) if sup else None
            n += 1
        cat = 'otros'
        if 'Motion' in names or 'Jump' in names or 'Avoider' in names:
            cat = 'movimiento'
        elif 'Cycle' in names:
            cat = 'ciclado'
        self.class_cat[o.addr] = cat
        return cat

    # ------------------------------------------------------------ envios
    def send(self, send_obj, work_obj, argp, framesize, top):
        p = argp
        while framesize > 0:
            sel = self.rw(p)
            argc = self.rw(p + 2)
            r = self.lookup(send_obj, sel)
            if r is None:
                raise VMError('selector %s no existe en %s' % (self.sname(sel), self.objname(send_obj)))
            lc = self.lookup_cost.get((send_obj, sel))
            kw = self.cur.kwork
            if lc:
                kw['lookup_cmp'] = kw.get('lookup_cmp', 0) + lc[0]
                kw['lookup_up'] = kw.get('lookup_up', 0) + lc[1]
            if r[0] == 'v':
                kw['send_var'] = kw.get('send_var', 0) + 1
                if argc:
                    self.ww(r[1], self.rw(p + 4))
                else:
                    self.acc = self.rw(r[1])
            else:
                code, owner = r[1], r[2]
                scr = self.scripts[owner.script]
                f = Frame()
                f.obj = work_obj
                f.locals = scr.locals_addr
                f.argp = p + 2
                f.argc = argc
                cat = self.obj_cat(owner)
                f.cat = cat
                f.name = owner.name + '::' + self.sname(sel)
                self.cur.sends += 1
                kw['send_met'] = kw.get('send_met', 0) + 1
                self.execute(f, code, top)
            framesize -= 2 + argc
            p += 2 * (argc + 2)

    def objname(self, a):
        o = self.objects.get(a)
        return o.name if o else '%04x' % a

    # ------------------------------------------------------------ PMachine
    def execute(self, f, pc, sp):
        """run_vm para un marco: devuelve al llegar a su ret."""
        mem = self.mem
        rw = self.rw
        ww = self.ww
        self.depth += 1
        if self.depth > self.depth_peak:
            self.depth_peak = self.depth
        if self.depth > 400:
            raise VMError('anidamiento excesivo')
        f.fp = sp
        sp_ = sp
        self.fstack.append(f.name)
        prev_cat = self.cat_stack[-1] if self.cat_stack else 'otros'
        # categoria inclusiva: el marco de movimiento/ciclado mas externo manda;
        # 'A:' = dentro de los doit que lanza Animate
        base_prev = prev_cat[2:] if prev_cat.startswith('A:') else prev_cat
        cat = base_prev if base_prev in ('movimiento', 'ciclado') else f.cat
        if self.in_anim:
            cat = 'A:' + cat
        self.cat_stack.append(cat)
        ops = self.cur.cat.setdefault(cat, [0] * 128)
        cur = self.cur
        glob = self.scripts[0].locals_addr
        loc = f.locals
        fp = f.fp
        argp = f.argp
        obj = f.obj
        n_ops = 0
        try:
            while True:
                ext = mem[pc]
                op = ext >> 1
                pc += 1
                fm = FMT[op]
                p0 = p1 = p2 = 0
                if fm:
                    vals = []
                    for k in fm:
                        if k == 'B':
                            vals.append(mem[pc])
                            pc += 1
                        elif k == 'W':
                            vals.append(mem[pc] | (mem[pc + 1] << 8))
                            pc += 2
                        elif ext & 1:
                            b = mem[pc]
                            pc += 1
                            vals.append(b - 256 if (k == 's' and b & 0x80) else b)
                        else:
                            w = mem[pc] | (mem[pc + 1] << 8)
                            pc += 2
                            vals.append(w - 0x10000 if (k == 's' and w & 0x8000) else w)
                    p0 = vals[0]
                    if len(vals) > 1:
                        p1 = vals[1]
                    if len(vals) > 2:
                        p2 = vals[2]
                elif fm is None:
                    raise VMError('opcode invalido %02x en %04x' % (ext, pc - 1))
                ops[op] += 1
                n_ops += 1
                if not (n_ops & 0xFF):
                    self.ticks += 256 * TICKS_PER_OP
                    self.cyc_ops += 256
                    if self.cyc_ops > 3000000:
                        raise VMError('bucle sin ciclo de juego (3 M de bytecodes sin Animate) en ' + ' > '.join(self.fstack[-8:]) + ' kernel ' + str(dict(list(self.cur.kcalls.items())[:12])))
                if op >= 0x40:
                    # variables: g l t p
                    vt = op & 3
                    if vt == 0:
                        vb = glob
                    elif vt == 1:
                        vb = loc
                    elif vt == 2:
                        vb = fp
                    else:
                        vb = argp
                    grp = (op >> 2) & 0xF   # 0 la 1 ls 2 lai 3 lsi 4 sa 5 ss 6 sai 7 ssi 8.. plus/minus
                    idx = p0
                    if grp & 2:
                        idx += s16(self.acc)
                    a = vb + 2 * idx
                    if grp < 4:
                        v = rw(a)
                        if grp & 1:
                            ww(sp_, v)
                            sp_ += 2
                        else:
                            self.acc = v
                    elif grp < 8:
                        if grp & 1:
                            sp_ -= 2
                            ww(a, rw(sp_))
                        else:
                            if grp & 2:
                                sp_ -= 2
                                self.acc = rw(sp_)
                            ww(a, self.acc)
                    else:
                        d = 1 if grp < 12 else -1
                        v = (rw(a) + d) & 0xFFFF
                        ww(a, v)
                        if grp & 1:
                            ww(sp_, v)
                            sp_ += 2
                        else:
                            self.acc = v
                    continue
                if op <= 0x16:
                    if op == 0:
                        self.acc ^= 0xFFFF
                    elif op == 0x0b:
                        self.acc = (-self.acc) & 0xFFFF
                    elif op == 0x0c:
                        self.acc = 0 if self.acc else 1
                    else:
                        sp_ -= 2
                        a = rw(sp_)
                        b = self.acc
                        if op == 1:
                            r = (a + b) & 0xFFFF
                        elif op == 2:
                            r = (a - b) & 0xFFFF
                        elif op == 3:
                            r = (s16(a) * s16(b)) & 0xFFFF
                        elif op == 4:
                            r = 0 if b == 0 else int(s16(a) / s16(b)) & 0xFFFF
                        elif op == 5:
                            if b == 0:
                                r = 0
                            else:
                                r = (s16(a) % abs(s16(b))) & 0xFFFF
                        elif op == 6:
                            r = (a >> (b & 15)) & 0xFFFF
                        elif op == 7:
                            r = (a << (b & 15)) & 0xFFFF
                        elif op == 8:
                            r = a ^ b
                        elif op == 9:
                            r = a & b
                        elif op == 10:
                            r = a | b
                        else:
                            self.prev = b
                            sa, sb = s16(a), s16(b)
                            if op == 0x0d:
                                r = a == b
                            elif op == 0x0e:
                                r = a != b
                            elif op == 0x0f:
                                r = sa > sb
                            elif op == 0x10:
                                r = sa >= sb
                            elif op == 0x11:
                                r = sa < sb
                            elif op == 0x12:
                                r = sa <= sb
                            elif op == 0x13:
                                r = a > b
                            elif op == 0x14:
                                r = a >= b
                            elif op == 0x15:
                                r = a < b
                            else:
                                r = a <= b
                            r = 1 if r else 0
                        self.acc = r
                    continue
                if op == 0x17:
                    if self.acc:
                        pc += p0
                elif op == 0x18:
                    if not self.acc:
                        pc += p0
                elif op == 0x19:
                    pc += p0
                elif op == 0x1a:
                    self.acc = p0 & 0xFFFF
                elif op == 0x1b:
                    ww(sp_, self.acc)
                    sp_ += 2
                elif op == 0x1c:
                    ww(sp_, p0)
                    sp_ += 2
                elif op == 0x1d:
                    sp_ -= 2
                elif op == 0x1e:
                    ww(sp_, rw(sp_ - 2))
                    sp_ += 2
                elif op == 0x1f:
                    for i in range(p0):
                        ww(sp_ + 2 * i, 0)
                    sp_ += 2 * p0
                elif op == 0x20:   # call
                    argc = (p1 >> 1) + 1 + self.rest
                    base = sp_ - 2 * argc
                    fa = rw(base) + self.rest
                    ww(base, fa)
                    self.rest = 0
                    g = Frame()
                    g.obj = obj
                    g.locals = loc
                    g.argp = base
                    g.argc = fa
                    g.cat = f.cat
                    g.name = f.name + '/call'
                    self.sp = sp_
                    self._peak(sp_)
                    self.execute(g, pc + p0, sp_)
                    sp_ = base
                    ops = self.cur.cat.setdefault(cat, [0] * 128)
                elif op == 0x21:   # callk
                    sp_ -= 2 * ((p1 >> 1) + 1)
                    sp_ -= 2 * self.rest
                    argc = rw(sp_) + self.rest
                    self.rest = 0
                    self.sp = sp_ + 2 * (argc + 1)
                    self._peak(self.sp)
                    self.callk(p0, argc, sp_ + 2)
                    self.sp = sp_
                    ops = self.cur.cat.setdefault(cat, [0] * 128)
                elif op in (0x22, 0x23):   # callb / calle
                    if op == 0x22:
                        sn, ex, fs = 0, p0, p1
                    else:
                        sn, ex, fs = p0, p1, p2
                    temp = (fs >> 1) + self.rest + 1
                    top = sp_
                    sp_ -= 2 * temp
                    ww(sp_, rw(sp_) + self.rest)
                    self.rest = 0
                    scr = self.load_script(sn)
                    g = Frame()
                    g.obj = obj
                    g.locals = scr.locals_addr
                    g.argp = sp_
                    g.argc = rw(sp_)
                    g.cat = f.cat
                    g.name = 'script%d/export%d' % (sn, ex)
                    self.sp = top
                    self._peak(top)
                    self.execute(g, scr.base + scr.exports[ex], top)
                    glob = self.scripts[0].locals_addr
                    ops = self.cur.cat.setdefault(cat, [0] * 128)
                elif op == 0x24:   # ret
                    return
                elif op in (0x25, 0x2a, 0x2b):   # send / self / super
                    if op == 0x2b:
                        so = self.get_class(p0)
                        fs = p1
                        wo = obj
                    else:
                        so = self.acc if op == 0x25 else obj
                        wo = so
                        fs = p0
                    top = sp_
                    sp_ -= 2 * ((fs >> 1) + self.rest)
                    ww(sp_ + 2, rw(sp_ + 2) + self.rest)
                    n = (fs >> 1) + self.rest
                    self.rest = 0
                    self.sp = top
                    self._peak(top)
                    self.send(so, wo, sp_, n, top)
                    ops = self.cur.cat.setdefault(cat, [0] * 128)
                elif op == 0x28:   # class
                    self.acc = self.get_class(p0)
                elif op == 0x2c:   # rest
                    t = p0 & 0xFFFF
                    argc = f.argc
                    self.rest = max(argc - t + 1, 0)
                    while t <= argc:
                        ww(sp_, rw(argp + 2 * t))
                        sp_ += 2
                        t += 1
                elif op == 0x2d:   # lea
                    t = (p0 & 0xFFFF) >> 1
                    vt = t & 3
                    vb = (glob, loc, fp, argp)[vt]
                    idx = p1
                    if t & 8:
                        idx += s16(self.acc)
                    self.acc = (vb + 2 * idx) & 0xFFFF
                elif op == 0x2e:
                    self.acc = obj
                elif op == 0x30:
                    ww(sp_, self.prev)
                    sp_ += 2
                elif 0x31 <= op <= 0x38:
                    a = obj + p0
                    if op == 0x31:
                        self.acc = rw(a)
                    elif op == 0x32:
                        ww(a, self.acc)
                    elif op == 0x33:
                        ww(sp_, rw(a))
                        sp_ += 2
                    elif op == 0x34:
                        sp_ -= 2
                        ww(a, rw(sp_))
                    else:
                        v = (rw(a) + (1 if op & 1 else -1)) & 0xFFFF
                        ww(a, v)
                        if op in (0x35, 0x36):
                            self.acc = v
                        else:
                            ww(sp_, v)
                            sp_ += 2
                elif op == 0x39:
                    self.acc = (pc + p0) & 0xFFFF
                elif op == 0x3a:
                    ww(sp_, (pc + p0) & 0xFFFF)
                    sp_ += 2
                elif op in (0x3b, 0x3c, 0x3d):
                    ww(sp_, op - 0x3b)
                    sp_ += 2
                elif op == 0x3e:
                    if not (ext & 1):
                        ww(sp_, obj)
                        sp_ += 2
                    else:
                        while mem[pc]:
                            pc += 1
                        pc += 1
                elif op == 0x3f:
                    pass
                else:
                    raise VMError('opcode %02x sin implementar' % op)
                if sp_ > self.sp_peak:
                    self.sp_peak = sp_
                if sp_ >= STACK_HI:
                    raise VMError('desbordamiento de pila')
        finally:
            self.fstack.pop()
            self.depth -= 1
            self.cat_stack.pop()
            self.ops_total += n_ops
            if self.ops_total > self.max_ops:
                self.stop = True

    def _peak(self, sp):
        if sp > self.sp_peak:
            self.sp_peak = sp

    # ------------------------------------------------------------ kernel
    def callk(self, num, argc, argv):
        name = self.kname[num] if num < len(self.kname) else '?%d' % num
        args = [self.rw(argv + 2 * i) for i in range(argc)]
        cur = self.cur
        cur.kcalls[name] = cur.kcalls.get(name, 0) + 1
        fn = self.kfuncs.get(name)
        self.kstack.append(name)
        try:
            if fn is None:
                self.unimpl = getattr(self, 'unimpl', {})
                self.unimpl[name] = self.unimpl.get(name, 0) + 1
                r = self.acc
            else:
                r = fn(args, argv)
            if r is not None:
                self.acc = r & 0xFFFF
        finally:
            self.kstack.pop()
        if self.stop:
            raise StopRun()

    def work(self, key, n=1):
        w = self.cur.kwork
        w[key] = w.get(key, 0) + n

    def _kernel_table(self):
        k = {}
        for n in dir(self):
            if n.startswith('k_'):
                k[n[2:]] = getattr(self, n)
        # nombres alternativos de los vocab 999 de algunos juegos
        alias = {'TimesSin': 'SinMult', 'TimesCos': 'CosMult', 'SinDiv': 'SinDiv', 'CosDiv': 'CosDiv',
                 'FOpen': 'FOpen', 'FPuts': 'FPuts', 'FGets': 'FGets', 'FClose': 'FClose'}
        for a, b in alias.items():
            if b in k and a not in k:
                k[a] = k[b]
        return k

    # recursos y scripts
    def k_Load(self, a, v):
        t = a[0] & 0x7F
        types = ['view', 'pic', 'script', 'text', 'sound', 'memory', 'vocab', 'font', 'cursor', 'patch']
        if t < len(types):
            if types[t] == 'script':
                self.load_script(a[1])
            else:
                self.load_res(types[t], a[1])
        return (t << 11) | a[1]

    def k_UnLoad(self, a, v):
        if len(a) >= 2:
            t = a[0] & 0x7F
            types = ['view', 'pic', 'script', 'text', 'sound', 'memory', 'vocab', 'font', 'cursor', 'patch']
            if t < len(types) and types[t] not in ('script',):
                k = (types[t], a[1])
                if k in self.hunk:
                    del self.hunk[k]
                    self.views.pop(a[1], None) if types[t] == 'view' else None
                    self.fonts.pop(a[1], None) if types[t] == 'font' else None
        return None

    def k_ScriptID(self, a, v):
        s = self.load_script(a[0])
        idx = a[1] if len(a) > 1 else 0
        if idx >= len(s.exports):
            return 0
        return s.base + s.exports[idx]

    def k_DisposeScript(self, a, v):
        n = a[0]
        # ScummVM: no se descarga el script desde el que se llama
        caller = self.script_of(self.cur_pc_hint) if hasattr(self, 'cur_pc_hint') else None
        self.dispose_script(n)
        return None

    def k_Clone(self, a, v):
        src = self.objects.get(a[0])
        if src is None:
            raise VMError('Clone de algo que no es objeto')
        size = 8 + src.nvars * 2
        blk = self.heap.alloc(size, ('clone', src.name))
        addr = blk + 8
        self.mem[addr:addr + src.nvars * 2] = self.mem[src.addr:src.addr + src.nvars * 2]
        o = Obj()
        o.addr = addr
        o.nvars = src.nvars
        o.varsel = src.varsel
        o.methods = src.methods if not src.is_class else {}
        o.is_class = False
        o.script = src.script
        o.name = src.name
        o.clone = True
        o.species = src.species
        self.objects[addr] = o
        info = self.rw(addr + 4)
        self.ww(addr + 4, (info & ~0x8000) | 1)
        if src.is_class:
            self.ww(addr + 2, src.addr)   # superClass = la clase
        self.clone_count += 1
        self.lookup_cache = {k: x for k, x in self.lookup_cache.items() if k[0] != addr}
        return addr

    def k_DisposeClone(self, a, v):
        o = self.objects.get(a[0])
        if o is not None and o.clone:
            del self.objects[a[0]]
            self.heap.free_block(a[0] - 8)
            self.lookup_cache = {k: x for k, x in self.lookup_cache.items() if k[0] != a[0]}
        return None

    def k_IsObject(self, a, v):
        return 1 if a[0] in self.objects else 0

    def k_RespondsTo(self, a, v):
        if a[0] not in self.objects:
            return 0
        return 1 if self.lookup(a[0], a[1]) is not None else 0

    # listas: List = {primero, ultimo}; Node = {pred, succ, clave, valor}
    def k_NewList(self, a, v):
        l = self.heap.alloc(4, 'list')
        self.lists.add(l)
        return l

    def k_DisposeList(self, a, v):
        l = a[0]
        if l in self.lists:
            n = self.rw(l)
            while n:
                nx = self.rw(n + 2)
                self.heap.free_block(n)
                n = nx
            self.heap.free_block(l)
            self.lists.discard(l)
        return None

    def k_NewNode(self, a, v):
        n = self.heap.alloc(8, 'node')
        self.ww(n + 4, a[1] if len(a) > 1 else a[0])
        self.ww(n + 6, a[0])
        return n

    def k_FirstNode(self, a, v):
        return self.rw(a[0]) if a[0] else 0

    def k_LastNode(self, a, v):
        return self.rw(a[0] + 2) if a[0] else 0

    def k_EmptyList(self, a, v):
        return 1 if (not a[0] or self.rw(a[0]) == 0) else 0

    def k_NextNode(self, a, v):
        self.work('nodos')
        return self.rw(a[0] + 2) if a[0] else 0

    def k_PrevNode(self, a, v):
        return self.rw(a[0]) if a[0] else 0

    def k_NodeValue(self, a, v):
        return self.rw(a[0] + 6) if a[0] else 0

    def _link(self, l, n, after):
        if after is None:   # al final
            last = self.rw(l + 2)
            self.ww(n, last)
            self.ww(n + 2, 0)
            if last:
                self.ww(last + 2, n)
            else:
                self.ww(l, n)
            self.ww(l + 2, n)

    def k_AddToEnd(self, a, v):
        l, n = a[0], a[1]
        if len(a) > 2:
            self.ww(n + 4, a[2])
        self._link(l, n, None)
        return n

    def k_AddToFront(self, a, v):
        l, n = a[0], a[1]
        if len(a) > 2:
            self.ww(n + 4, a[2])
        first = self.rw(l)
        self.ww(n, 0)
        self.ww(n + 2, first)
        if first:
            self.ww(first, n)
        else:
            self.ww(l + 2, n)
        self.ww(l, n)
        return n

    def k_AddAfter(self, a, v):
        l, ref, n = a[0], a[1], a[2]
        if len(a) > 3:
            self.ww(n + 4, a[3])
        if not ref:
            return self.k_AddToFront([l, n], v)
        nx = self.rw(ref + 2)
        self.ww(n, ref)
        self.ww(n + 2, nx)
        self.ww(ref + 2, n)
        if nx:
            self.ww(nx, n)
        else:
            self.ww(l + 2, n)
        return n

    def k_FindKey(self, a, v):
        n = self.rw(a[0]) if a[0] else 0
        while n:
            self.work('nodos')
            if self.rw(n + 4) == a[1]:
                return n
            n = self.rw(n + 2)
        return 0

    def k_DeleteKey(self, a, v):
        l = a[0]
        n = self.k_FindKey(a, v)
        if not n:
            return 0
        pr, nx = self.rw(n), self.rw(n + 2)
        if pr:
            self.ww(pr + 2, nx)
        else:
            self.ww(l, nx)
        if nx:
            self.ww(nx, pr)
        else:
            self.ww(l + 2, pr)
        self.heap.free_block(n)
        return 1

    # matematicas
    def k_Random(self, a, v):
        if len(a) >= 2:
            lo, hi = s16(a[0]), s16(a[1])
            if hi < lo:
                lo, hi = hi, lo
            return self.rng.randint(lo, hi)
        return self.rng.randint(0, 0xFFFF)

    def k_Abs(self, a, v):
        return abs(s16(a[0]))

    def k_Sqrt(self, a, v):
        return int(math.sqrt(abs(s16(a[0]))))

    @staticmethod
    def angle(x1, y1, x2, y2):
        # kGetAngleWorker (SCI0/1: tabla de octantes)
        xrel, yrel = x2 - x1, y1 - y2
        if yrel == 0 and xrel == 0:
            return 0
        angle = math.atan2(xrel, yrel) * 180 / math.pi
        a = int(round(angle))
        if a < 0:
            a += 360
        return a % 360

    def k_GetAngle(self, a, v):
        x1, y1, x2, y2 = [s16(x) for x in a[:4]]
        return self.angle(x1, y1, x2, y2)

    def k_GetDistance(self, a, v):
        xd = s16(a[0]) - (s16(a[2]) if len(a) > 2 else 0)
        yd = s16(a[1]) - (s16(a[3]) if len(a) > 3 else 0)
        if len(a) > 4:
            yd = yd * s16(a[4]) // 100
        return int(math.sqrt(xd * xd + yd * yd))

    def k_SinMult(self, a, v):
        return int(math.sin(s16(a[0]) * math.pi / 180) * s16(a[1]))

    def k_CosMult(self, a, v):
        return int(math.cos(s16(a[0]) * math.pi / 180) * s16(a[1]))

    def k_SinDiv(self, a, v):
        s = math.sin(s16(a[0]) * math.pi / 180)
        return int(s16(a[1]) / s) if s else 0

    def k_CosDiv(self, a, v):
        c = math.cos(s16(a[0]) * math.pi / 180)
        return int(s16(a[1]) / c) if c else 0

    # tiempo
    def k_GetTime(self, a, v):
        mode = a[0] if a else 0
        self.ticks += 0.05
        self._sound_tick()
        if mode == 0:
            return int(self.ticks) & 0xFFFF
        t = int(self.ticks / 60) + 10 * 3600   # reloj simulado: empieza a las 10:00:00
        hh, mm, ss = (t // 3600) % 24, (t // 60) % 60, t % 60
        if mode == 1:
            h12 = hh % 12 or 12
            return (h12 << 12) | (mm << 6) | ss
        if mode == 2:
            return (hh << 11) | (mm << 5) | (ss >> 1)
        return 0

    def k_Wait(self, a, v):
        n = a[0]
        target = self.last_wait + n
        if self.ticks < target:
            self.ticks = target
        d = int(self.ticks - self.last_wait)
        self.last_wait = self.ticks
        self.cur.wait = n
        self._sound_tick()
        return d

    # cadenas
    def k_StrLen(self, a, v):
        return len(self.rstr(a[0]))

    def k_StrCpy(self, a, v):
        s = self.text(a[1])
        if len(a) > 2:
            n = s16(a[2])
            if n >= 0:
                s = s[:n] if len(s) >= n else s
                b = s.encode('latin-1')[:n]
                b = b + b'\0' * (n - len(b)) if len(b) < n else b
                self.mem[a[0]:a[0] + len(b)] = b
                return a[0]
            s = s[:-n]
        self.wstr(a[0], s)
        return a[0]

    def k_StrCat(self, a, v):
        self.wstr(a[0], self.rstr(a[0]) + self.text(a[1]))
        return a[0]

    def k_StrCmp(self, a, v):
        x, y = self.text(a[0]), self.text(a[1])
        if len(a) > 2:
            x, y = x[:a[2]], y[:a[2]]
        return (x > y) - (x < y)

    def k_StrEnd(self, a, v):
        return a[0] + len(self.rstr(a[0]))

    def k_StrAt(self, a, v):
        addr = a[0] + a[1]
        old = self.mem[addr & 0xFFFF]
        if len(a) > 2:
            self.mem[addr & 0xFFFF] = a[2] & 0xFF
        return old

    def k_ReadNumber(self, a, v):
        s = self.text(a[0]).strip()
        try:
            return int(s, 16) if s.startswith('$') is False and s.lower().startswith('0x') else int(s or '0')
        except ValueError:
            return 0

    def k_GetFarText(self, a, v):
        self.wstr(a[2], self.text(a[0], a[1]))
        return a[2]

    def k_Format(self, a, v):
        dest = a[0]
        if a[1] >= 1000:
            src = self.rstr(a[1])
            start = 2
        else:
            src = self.text(a[1], a[2])
            start = 3
        args = a[start:]
        out = []
        i = 0
        pi = 0
        while i < len(src):
            c = src[i]
            i += 1
            if c != '%':
                out.append(c)
                continue
            if i < len(src) and src[i] == '%':
                out.append('%')
                i += 1
                continue
            width = ''
            while i < len(src) and (src[i].isdigit() or src[i] in '-='):
                width += src[i]
                i += 1
            if i >= len(src):
                break
            t = src[i]
            i += 1
            if t == 's':
                r = args[pi] if pi < len(args) else 0
                if r >= 1000:
                    s = self.rstr(r)
                    pi += 1
                else:
                    s = self.text(r, args[pi + 1] if pi + 1 < len(args) else 0)
                    pi += 2
            elif t in 'dux':
                val = args[pi] if pi < len(args) else 0
                pi += 1
                s = ('%x' % val) if t == 'x' else ('%d' % (val if t == 'u' else s16(val)))
            elif t == 'c':
                s = chr(args[pi] & 0xFF) if pi < len(args) and args[pi] else ''
                pi += 1
            else:
                s = '%' + t
            w = width.lstrip('=')
            if w and w.lstrip('-').isdigit():
                n = int(w)
                s = s.ljust(-n) if n < 0 else (s.center(n) if width.startswith('=') else s.rjust(n))
            out.append(s)
        self.wstr(dest, ''.join(out))
        return dest

    # sonido (solo duracion y estado, como DoSound de SCI0)
    def k_DoSound(self, a, v):
        sub = a[0]
        o = a[1] if len(a) > 1 else 0
        if sub == 0:     # init
            n = self.rsel(o, 'number')
            self.load_res('sound', n)
            self.wsel(o, 'state', 1)
            self.wsel(o, 'handle', o)
        elif sub == 1:   # play
            n = self.rsel(o, 'number')
            d = self.load_res('sound', n)
            dur = sci0pic.sound_ticks(d) if d else 0
            self.wsel(o, 'handle', o)
            self.wsel(o, 'signal', 0)
            self.wsel(o, 'state', 3)
            loops = s16(self.rsel(o, 'loop'))
            self.sounds[o] = [self.ticks + max(dur, 1), dur, loops]
        elif sub == 3:   # dispose
            self.sounds.pop(o, None)
            self.wsel(o, 'handle', 0)
            self.wsel(o, 'state', 0)
        elif sub == 5:   # stop
            self.sounds.pop(o, None)
            self.wsel(o, 'state', 0)
            self.wsel(o, 'signal', 0xFFFF)
        elif sub == 9:   # update
            pass
        elif sub == 10:  # fade
            if o in self.sounds:
                self.sounds[o][0] = min(self.sounds[o][0], self.ticks + 30)
                self.sounds[o][2] = 1
        elif sub == 11:
            return 8
        elif sub == 4:
            return 1
        return None

    def _sound_tick(self):
        for o, s in list(self.sounds.items()):
            if self.ticks >= s[0]:
                if s[2] == -1 or s[2] > 1:
                    if s[2] > 1:
                        s[2] -= 1
                        self.wsel(o, 'loop', s[2])
                    s[0] = self.ticks + max(s[1], 1)
                    continue
                del self.sounds[o]
                if o in self.objects:
                    self.wsel(o, 'state', 0)
                    self.wsel(o, 'signal', 0xFFFF)

    # eventos y entrada
    def k_GetEvent(self, a, v):
        mask, ev = a[0], a[1]
        self.ticks += 0.05
        self._sound_tick()
        typ, msg = 0, 0
        if mask & 4:
            if self.cur.kcalls.get('GetEvent', 0) % 25 == 24:
                # dialogo modal esperando una tecla: ENTER
                typ, msg = 4, 13
                self.inputs['enter'] = self.inputs.get('enter', 0) + 1
            elif self.walk and len(self.cycles) >= self.walk_next:
                typ, msg = 4, self.rng.choice(ARROWS)
                self.walk_next = len(self.cycles) + self.rng.randint(15, 60)
                self.inputs['flecha'] = self.inputs.get('flecha', 0) + 1
        if self.tour and len(self.cycles) >= self.tour_next and len(self.cycles) > 50:
            g = self.scripts[0].locals_addr
            nxt = self.tour.pop(0)
            self.ww(g + 2 * 13, nxt)
            self.tour_next = len(self.cycles) + self.tour_ticks
            self.inputs['salas'] = self.inputs.get('salas', 0) + 1
        if ev in self.objects:
            self.wsel(ev, 'type', typ)
            self.wsel(ev, 'message', msg)
            self.wsel(ev, 'modifiers', 0)
            self.wsel(ev, 'x', 160)
            self.wsel(ev, 'y', 100)
        return 1 if typ else 0

    def k_MapKeyToDir(self, a, v):
        o = a[0]
        if self.rsel(o, 'type') == 4:
            m = self.rsel(o, 'message')
            if m in KEY2DIR:
                self.wsel(o, 'type', 64)
                self.wsel(o, 'message', KEY2DIR[m])
                return 1
            return 0
        return None

    def k_GlobalToLocal(self, a, v):
        return None

    def k_LocalToGlobal(self, a, v):
        return None

    def k_HaveMouse(self, a, v):
        return 0

    def k_Parse(self, a, v):
        return 0

    def k_Said(self, a, v):
        return 0

    def k_SetSynonyms(self, a, v):
        return None

    def k_GameIsRestarting(self, a, v):
        return 0

    def k_DeviceInfo(self, a, v):
        return 0

    def k_GetCWD(self, a, v):
        self.wstr(a[0], 'C:\\SIERRA\\')
        return a[0]

    def k_GetSaveDir(self, a, v):
        if not hasattr(self, '_savedir'):
            self._savedir = self.heap.alloc(32, 'savedir')
            self.wstr(self._savedir, 'C:/SIERRA/')
        return self._savedir

    def k_ValidPath(self, a, v):
        return 1

    def k_CheckFreeSpace(self, a, v):
        return 1

    def k_GetSaveFiles(self, a, v):
        return 0

    def k_CheckSaveGame(self, a, v):
        return 0

    def k_FOpen(self, a, v):
        return 0xFFFF

    def k_FGets(self, a, v):
        return 0

    def k_FPuts(self, a, v):
        return None

    def k_FClose(self, a, v):
        return None

    def k_MemoryInfo(self, a, v):
        free = (HEAP_HI - HEAP_LO) - self.heap.used
        return max(0, min(free, 0x7FFF))

    def k_FlushResources(self, a, v):
        return None

    def k_SetCursor(self, a, v):
        return None

    def k_SetDebug(self, a, v):
        return None

    def k_Joystick(self, a, v):
        return 0

    def k_StackUsage(self, a, v):
        return 0

    def k_Platform(self, a, v):
        return 0

    def k_Palette(self, a, v):
        return None

    def k_ShakeScreen(self, a, v):
        return None

    def k_Show(self, a, v):
        return None

    def k_Profiler(self, a, v):
        return None

    def k_ShowFree(self, a, v):
        return None

    # menu y estado (sin pantalla)
    def k_AddMenu(self, a, v):
        return None

    def k_SetMenu(self, a, v):
        return None

    def k_GetMenu(self, a, v):
        return 0

    def k_DrawMenuBar(self, a, v):
        return None

    def k_MenuSelect(self, a, v):
        return 0

    def k_DrawStatus(self, a, v):
        return None

    def k_SaveGame(self, a, v):
        return 0

    def k_RestoreGame(self, a, v):
        return 0

    def k_RestartGame(self, a, v):
        self.stop = True
        return None

    # ventanas y texto (solo medidas)
    def k_NewWindow(self, a, v):
        p = self.heap.alloc(42, 'window')     # Window de SCI0: ~42 B en el heap
        self.ports[p] = [s16(x) for x in a[:4]]
        self.cur_port = p
        self.work('ventana_px', max(0, (s16(a[2]) - s16(a[0])) * (s16(a[3]) - s16(a[1]))))
        return p

    def k_DisposeWindow(self, a, v):
        if a[0] in self.ports:
            del self.ports[a[0]]
            self.heap.free_block(a[0])
        return None

    def k_GetPort(self, a, v):
        return self.cur_port

    def k_SetPort(self, a, v):
        if len(a) == 1:
            self.cur_port = a[0]
        return None

    def k_TextSize(self, a, v):
        dest = a[0]
        s = self.text(a[1])
        fnt = self.font(a[2])
        maxw = a[3] if len(a) > 3 else 0
        w, h = sci0pic.text_size(fnt, s, maxw)
        self.ww(dest, 0)
        self.ww(dest + 2, 0)
        self.ww(dest + 4, h)
        self.ww(dest + 6, w)
        return None

    def k_Display(self, a, v):
        if not a:
            return None
        if a[0] >= 1000:
            s = self.rstr(a[0])
            i = 1
        else:
            s = self.text(a[0], a[1] if len(a) > 1 else 0)
            i = 2
        self.work('texto_chars', len(s))
        ret = None
        while i < len(a):
            c = a[i]
            i += 1
            if c in (100,):
                i += 2
            elif c in (101, 102, 103, 104, 105, 106):
                i += 1
            elif c == 107:
                h = self.bits_next
                self.bits_next += 1
                self.bits[h] = b'\0' * 2000
                self._hunk_update()
                ret = h
            elif c == 108:
                if i < len(a):
                    self.bits.pop(a[i], None)
                    i += 1
        return ret

    def k_DrawControl(self, a, v):
        o = a[0]
        if o in self.objects:
            t = self.rsel(o, 'text')
            if t:
                self.work('texto_chars', len(self.text(t)))
        return None

    def k_HiliteControl(self, a, v):
        return None

    def k_EditControl(self, a, v):
        return None

    def k_Graph(self, a, v):
        sub = a[0]
        if sub == 2:
            return 16
        if sub == 7:     # SaveBox
            y, x, y1, x1 = [s16(t) for t in a[1:5]]
            h = self.bits_next
            self.bits_next += 1
            n = max(0, (x1 - x) * (y1 - y))
            planes = bin(a[5] & 7).count('1') if len(a) > 5 else 3
            self.bits[h] = b'\0' * (n * planes // 2 + 8)
            self._hunk_update()
            self.work('graph_px', n)
            return h
        if sub == 8:
            self.bits.pop(a[1], None)
        if sub in (9, 10, 11, 12, 13):
            y, x, y1, x1 = [s16(t) for t in a[1:5]]
            self.work('graph_px', max(0, (x1 - x) * (y1 - y)))
        return None

    # graficos
    def k_DrawPic(self, a, v):
        n = a[0]
        d = self.load_res('pic', n)
        add = False
        if len(a) >= 3:
            add = a[2] != 0
            if not self.old_gfx:
                add = not add
        if d is not None:
            self.screen.draw_pic(d, clear=not add)
            self.pics_drawn.append(n)
        self.work('drawpic')
        self.pic_not_valid = 1
        return None

    def k_PicNotValid(self, a, v):
        old = self.pic_not_valid
        if a:
            self.pic_not_valid = s16(a[0])
        return old

    def cel_rect(self, view, loop, cel, x, y, z):
        vw = self.view(view)
        ci = vw.cel(loop, cel)
        left = x + ci[2] - (ci[0] >> 1)
        bottom = y + ci[3] - z + 1
        return [left, bottom - ci[1], left + ci[0], bottom]

    def k_NumLoops(self, a, v):
        return self.view(self.rsel(a[0], 'view')).nloops()

    def k_NumCels(self, a, v):
        return self.view(self.rsel(a[0], 'view')).ncels(s16(self.rsel(a[0], 'loop')))

    def k_CelWide(self, a, v):
        return self.view(a[0]).cel(s16(a[1]), s16(a[2]) if len(a) > 2 else 0)[0]

    def k_CelHigh(self, a, v):
        return self.view(a[0]).cel(s16(a[1]), s16(a[2]) if len(a) > 2 else 0)[1]

    def k_DrawCel(self, a, v):
        view, loop, cel, x, y = a[0], s16(a[1]), s16(a[2]), s16(a[3]), s16(a[4])
        r = self.cel_rect(view, loop, cel, x, y, 0)
        r[2] = r[0] + (r[2] - r[0])
        self.work('cel_px', max(0, (r[2] - r[0]) * (r[3] - r[1])))
        return None

    def k_SetNowSeen(self, a, v):
        o = a[0]
        r = self.cel_rect(self.rsel(o, 'view'), s16(self.rsel(o, 'loop')), s16(self.rsel(o, 'cel')),
                          s16(self.rsel(o, 'x')), s16(self.rsel(o, 'y')), s16(self.rsel(o, 'z')))
        if self.has_var(o, 'nsTop'):
            self._set_ns(o, r)
        return None

    def _set_ns(self, o, r):
        self.wsel(o, 'nsLeft', r[0])
        self.wsel(o, 'nsTop', r[1])
        self.wsel(o, 'nsRight', r[2])
        self.wsel(o, 'nsBottom', r[3])

    def k_BaseSetter(self, a, v):
        o = a[0]
        if not self.has_var(o, 'brLeft'):
            return None
        x, y = s16(self.rsel(o, 'x')), s16(self.rsel(o, 'y'))
        r = self.cel_rect(self.rsel(o, 'view'), s16(self.rsel(o, 'loop')), s16(self.rsel(o, 'cel')),
                          x, y, s16(self.rsel(o, 'z')))
        bottom = y + 1
        top = bottom - s16(self.rsel(o, 'yStep'))
        self.wsel(o, 'brLeft', r[0])
        self.wsel(o, 'brRight', r[2])
        self.wsel(o, 'brTop', top)
        self.wsel(o, 'brBottom', bottom)
        return None

    def k_DirLoop(self, a, v):
        self.dirloop(a[0], a[1])
        return None

    def dirloop(self, o, angle):
        sig = self.rsel(o, 'signal')
        if sig & SIG_DOESNTTURN:
            return
        use = -1
        if (angle > 315) or (angle < 45):
            use = 3
        elif 135 < angle < 225:
            use = 2
        if use == -1:
            use = 1 if angle >= 180 else 0
        elif self.view(self.rsel(o, 'view')).nloops() < 4:
            return
        self.wsel(o, 'loop', use)

    def k_CoordPri(self, a, v):
        y = s16(a[0])
        return self.screen.coord_to_pri(y)

    def k_OnControl(self, a, v):
        if len(a) in (2, 4):
            mask = 4
            b = 0
        else:
            mask = a[0]
            b = 1
        l, t = s16(a[b]), s16(a[b + 1])
        if len(a) > 3:
            r, bt = s16(a[b + 2]), s16(a[b + 3])
        else:
            r, bt = l + 1, t + 1
        res, n = self.screen.on_control(mask, l, t, r, bt)
        self.work('oncontrol_px', n)
        return res

    def k_CanBeHere(self, a, v):
        o = a[0]
        lst = a[1] if len(a) > 1 else 0
        l, t = s16(self.rsel(o, 'brLeft')), s16(self.rsel(o, 'brTop'))
        r, b = s16(self.rsel(o, 'brRight')), s16(self.rsel(o, 'brBottom'))
        sig = self.rsel(o, 'signal')
        if r < l or b < t:
            return 1
        res, n = self.screen.on_control(4, l, t, r, b)
        self.work('canbehere_px', n)
        res &= self.rsel(o, 'illegalBits')
        if res:
            return 0
        if sig & (SIG_IGNOREACTOR | SIG_REMOVEVIEW):
            return 1
        if not lst:
            return 1
        node = self.rw(lst)
        while node:
            self.work('canbehere_obj')
            c = self.rw(node + 6)
            if c != o and c in self.objects:
                s2 = self.rsel(c, 'signal')
                if not (s2 & (SIG_IGNOREACTOR | SIG_REMOVEVIEW | SIG_NOUPDATE)):
                    cl, ct = s16(self.rsel(c, 'brLeft')), s16(self.rsel(c, 'brTop'))
                    cr, cb = s16(self.rsel(c, 'brRight')), s16(self.rsel(c, 'brBottom'))
                    if cr > l and cl < r and cb > t and ct < b:
                        return 0
            node = self.rw(node + 2)
        return 1

    def k_InitBresen(self, a, v):
        mover = a[0]
        client = self.rsel(mover, 'client')
        sf = s16(a[1]) if len(a) >= 2 else 1
        mx, my = s16(self.rsel(mover, 'x')), s16(self.rsel(mover, 'y'))
        cxs = s16(self.rsel(client, 'xStep')) * sf
        cys = s16(self.rsel(client, 'yStep')) * sf
        cstep = cys * 2 if cxs < cys else cxs * 2
        dX = mx - s16(self.rsel(client, 'x'))
        dY = my - s16(self.rsel(client, 'y'))

        def tdiv(p, q):
            return int(p / q) if q else 0
        while True:
            mdx, mdy, incr = cxs, cys, 1
            if abs(dX) >= abs(dY):
                xa = 1
                if dX < 0:
                    mdx = -mdx
                mdy = tdiv(mdx * dY, dX) if dX else 0
                i1 = ((mdx * dY) - (mdy * dX)) * 2
                if dY < 0:
                    incr = -1
                    i1 = -i1
                i2 = i1 - dX * 2
                di = i1 - dX
                if dX < 0:
                    i1, i2, di = -i1, -i2, -di
            else:
                xa = 0
                if dY < 0:
                    mdy = -mdy
                mdx = tdiv(mdy * dX, dY) if dY else 0
                i1 = ((mdy * dX) - (mdx * dY)) * 2
                if dX < 0:
                    incr = -1
                    i1 = -i1
                i2 = i1 - dY * 2
                di = i1 - dY
                if dY < 0:
                    i1, i2, di = -i1, -i2, -di
                break
            if cxs <= cys or not cxs or cys >= abs(mdy + incr):
                break
            cstep -= 1
            if not cstep:
                break
            cxs -= 1
        for nm, val in (('dx', mdx), ('dy', mdy), ('b-i1', i1), ('b-i2', i2), ('b-di', di),
                        ('b-incr', incr), ('b-xAxis', xa)):
            self.wsel(mover, nm, val)
        return None

    def k_DoBresen(self, a, v):
        mover = a[0]
        client = self.rsel(mover, 'client')
        mc = s16(self.rsel(mover, 'b-moveCnt')) + 1
        speed = s16(self.rsel(client, 'moveSpeed'))
        if speed < mc:
            mc = 0
            cx, cy = s16(self.rsel(client, 'x')), s16(self.rsel(client, 'y'))
            mx, my = s16(self.rsel(mover, 'x')), s16(self.rsel(mover, 'y'))
            xa = s16(self.rsel(mover, 'b-xAxis'))
            mdx, mdy = s16(self.rsel(mover, 'dx')), s16(self.rsel(mover, 'dy'))
            incr = s16(self.rsel(mover, 'b-incr'))
            i1, i2, di = s16(self.rsel(mover, 'b-i1')), s16(self.rsel(mover, 'b-i2')), s16(self.rsel(mover, 'b-di'))
            oi1, oi2, odi = i1, i2, di
            co = self.objects[client]
            backup = bytes(self.mem[client:client + co.nvars * 2])
            done = (abs(mx - cx) < abs(mdx)) if xa else (abs(my - cy) < abs(mdy))
            if done:
                cx, cy = mx, my
            else:
                cx += mdx
                cy += mdy
                if di < 0:
                    di += i1
                else:
                    di += i2
                    if xa == 0:
                        cx += incr
                    else:
                        cy += incr
            self.wsel(client, 'x', cx)
            self.wsel(client, 'y', cy)
            self.acc = 0
            if 'cantBeHere' in self.sel:
                self.invoke(client, 'cantBeHere')
                coll = self.acc != 0
            else:
                self.invoke(client, 'canBeHere')
                coll = self.acc == 0
            if coll:
                self.mem[client:client + co.nvars * 2] = backup
                i1, i2, di = oi1, oi2, odi
                self.wsel(client, 'signal', self.rsel(client, 'signal') | SIG_HITOBSTACLE)
            self.wsel(mover, 'b-i1', i1)
            self.wsel(mover, 'b-i2', i2)
            self.wsel(mover, 'b-di', di)
        self.wsel(mover, 'b-moveCnt', mc)
        return None

    def k_SetJump(self, a, v):
        obj, dx, dy, gy = a[0], s16(a[1]), s16(a[2]), s16(a[3])
        neg = dx < 0
        dx = abs(dx)
        if dx == 0:
            c = 1
        elif dx + dy < 0:
            c = (2 * abs(dy)) // dx
        else:
            c = max(1, int((dx * 3 / 2 - dy) / dx))
        tmp = c * dx + dy
        vx = int(dx * math.sqrt(gy / (2.0 * tmp))) if (tmp > 0 and dx) else 0
        if neg:
            vx = -vx
        vy = int(math.sqrt(gy * abs(2 * dy))) + 1 if (dy < 0 and vx == 0) else c * vx
        vy = -abs(vy)
        self.wsel(obj, 'xStep', vx)
        self.wsel(obj, 'yStep', vy)
        return None

    def k_AddToPic(self, a, v):
        if len(a) == 1 or (len(a) >= 1 and a[0] in self.lists):
            ents = self._sorted(a[0])
            for e in ents:
                o = e['o']
                pri = e['pri']
                if pri == 0xFFFF or s16(pri) == -1:
                    pri = self.screen.coord_to_pri(e['y'])
                r = self.cel_rect(e['view'], e['loop'], e['cel'], e['x'], e['y'], e['z'])
                self.screen.draw_cel_pri(r, pri)
                self.work('addtopic_px', max(0, (r[2] - r[0]) * (r[3] - r[1])))
                if not (e['sig'] & SIG_IGNOREACTOR):
                    top = max(r[1], min(self.screen.pri_to_coord(pri) - 1, r[3] - 1))
                    self.screen.fill_control([r[0], top, r[2], r[3]], 15)
        else:
            view, loop, cel, x, y, pri, ctl = [s16(t) for t in a[:7]]
            if pri == -1:
                pri = self.screen.coord_to_pri(y)
            r = self.cel_rect(view, loop, cel, x, y, 0)
            self.screen.draw_cel_pri(r, pri)
            if ctl != -1:
                top = max(r[1], min(self.screen.pri_to_coord(pri) - 1, r[3] - 1))
                self.screen.fill_control([r[0], top, r[2], r[3]], ctl)
        self.pic_not_valid = 1
        return None

    def _sorted(self, lst):
        ents = []
        node = self.rw(lst)
        i = 0
        while node:
            o = self.rw(node + 6)
            if o in self.objects:
                e = {'o': o, 'i': i,
                     'view': self.rsel(o, 'view'), 'loop': s16(self.rsel(o, 'loop')),
                     'cel': s16(self.rsel(o, 'cel')), 'x': s16(self.rsel(o, 'x')),
                     'y': s16(self.rsel(o, 'y')), 'z': s16(self.rsel(o, 'z')),
                     'pri': self.rsel(o, 'priority'), 'sig': self.rsel(o, 'signal')}
                ents.append(e)
            i += 1
            node = self.rw(node + 2)
        ents.sort(key=lambda e: (e['y'], e['z'], e['i']))
        return ents

    def k_Animate(self, a, v):
        lst = a[0] if a else 0
        cyc = a[1] if len(a) > 1 else 0
        old_pnv = self.pic_not_valid
        if not lst:
            self.pic_not_valid = 0
            self.end_cycle()
            return None
        if cyc:
            self.kstack.append('Animate.doit')
            self.in_anim += 1
            node = self.rw(lst)
            while node:
                o = self.rw(node + 6)
                if o in self.objects:
                    sig = self.rsel(o, 'signal')
                    if not (sig & SIG_FROZEN):
                        self._invoke_doit(o)
                node = self.rw(node + 2) if node in self.heap.blocks else 0
            self.kstack.pop()
            self.in_anim -= 1
        ents = self._sorted(lst)
        # fill
        for e in ents:
            vw = self.view(e['view'])
            nl = vw.nloops()
            if e['loop'] >= nl:
                e['loop'] = 0
                self.wsel(e['o'], 'loop', 0)
            elif e['loop'] < 0:
                e['loop'] = nl - 1
            nc = vw.ncels(e['loop'])
            if e['cel'] >= nc:
                e['cel'] = 0
                self.wsel(e['o'], 'cel', 0)
            elif e['cel'] < 0:
                e['cel'] = nc - 1
            e['r'] = self.cel_rect(e['view'], e['loop'], e['cel'], e['x'], e['y'], e['z'])
            self._set_ns(e['o'], e['r'])
            s = e['sig']
            if not (s & SIG_FIXEDPRI):
                e['pri'] = self.screen.coord_to_pri(e['y'])
                self.wsel(e['o'], 'priority', e['pri'])
            if s & SIG_NOUPDATE:
                if (s & (SIG_FORCEUPDATE | SIG_VIEWUPDATED)) or (s & SIG_HIDDEN and not s & SIG_REMOVEVIEW) \
                        or (not s & SIG_HIDDEN and s & SIG_REMOVEVIEW) or (s & SIG_ALWAYSUPDATE):
                    old_pnv += 1
                s &= ~SIG_STOPUPDATE
            else:
                if (s & SIG_STOPUPDATE) or (s & SIG_ALWAYSUPDATE):
                    old_pnv += 1
                s &= ~SIG_FORCEUPDATE
            e['sig'] = s
        px = 0
        if old_pnv:
            # update(): restaurar fondos de los parados y repintarlos
            for e in reversed(ents):
                s = e['sig']
                if s & SIG_NOUPDATE:
                    if not (s & SIG_REMOVEVIEW):
                        h = self.rsel(e['o'], 'underBits')
                        if self.pic_not_valid != 1:
                            self._bits_restore(h)
                        else:
                            self.bits.pop(h, None)
                        self.wsel(e['o'], 'underBits', 0)
                    s &= ~SIG_FORCEUPDATE
                    if s & SIG_VIEWUPDATED:
                        s &= ~(SIG_VIEWUPDATED | SIG_NOUPDATE)
                elif s & SIG_STOPUPDATE:
                    s &= ~SIG_STOPUPDATE
                    s |= SIG_NOUPDATE
                e['sig'] = s
            for e in ents:
                s = e['sig']
                if s & SIG_ALWAYSUPDATE:
                    px += self._draw(e)
                    e['sig'] = s & ~(SIG_STOPUPDATE | SIG_VIEWUPDATED | SIG_NOUPDATE | SIG_FORCEUPDATE)
                    if not (s & SIG_IGNOREACTOR):
                        self._ctl_box(e, 15)
            for e in ents:
                s = e['sig']
                if s & SIG_NOUPDATE:
                    if s & SIG_HIDDEN:
                        e['sig'] = s | SIG_REMOVEVIEW
                    else:
                        e['sig'] = s & ~SIG_REMOVEVIEW
                        self.wsel(e['o'], 'underBits', self._bits_save(e['r'], 2 if s & SIG_IGNOREACTOR else 3))
            for e in ents:
                s = e['sig']
                if s & SIG_NOUPDATE and not (s & SIG_HIDDEN):
                    px += self._draw(e)
                    if not (s & SIG_IGNOREACTOR):
                        self._ctl_box(e, 15)
        # drawCels
        moving = 0
        for e in ents:
            s = e['sig']
            if not (s & (SIG_NOUPDATE | SIG_HIDDEN | SIG_ALWAYSUPDATE)):
                self.wsel(e['o'], 'underBits', self._bits_save(e['r'], 3))
                px += self._draw(e)
                moving += 1
                if s & SIG_REMOVEVIEW:
                    e['sig'] = s & ~SIG_REMOVEVIEW
        if self.pic_not_valid:
            self.work('showpic')
            self.pic_not_valid = 0
        # updateScreen
        for e in ents:
            s = e['sig']
            ls = [s16(self.rsel(e['o'], k)) for k in ('lsLeft', 'lsTop', 'lsRight', 'lsBottom')]
            r = e['r']
            ux = max(ls[0], r[0]), max(ls[1], r[1]), min(ls[2], r[2]), min(ls[3], r[3])
            if ux[0] < ux[2] and ux[1] < ux[3]:
                area = (max(ls[2], r[2]) - min(ls[0], r[0])) * (max(ls[3], r[3]) - min(ls[1], r[1]))
            else:
                area = max(0, (ls[2] - ls[0]) * (ls[3] - ls[1])) + max(0, (r[2] - r[0]) * (r[3] - r[1]))
            self.work('show_px', area)
            for k, val in zip(('lsLeft', 'lsTop', 'lsRight', 'lsBottom'), r):
                self.wsel(e['o'], k, val)
            if s & SIG_HIDDEN:
                e['sig'] = s | SIG_REMOVEVIEW
        # restoreAndDelete
        for e in ents:
            self.wsel(e['o'], 'signal', e['sig'])
        for e in reversed(ents):
            o = e['o']
            if o not in self.objects:
                continue
            s = self.rsel(o, 'signal')
            if (s & (SIG_NOUPDATE | SIG_REMOVEVIEW)) == 0:
                self._bits_restore(self.rsel(o, 'underBits'))
                self.wsel(o, 'underBits', 0)
            if s & SIG_DISPOSEME:
                self.invoke(o, 'delete')
        # sprites 8x8 a 160 de ancho (formato B): mosaicos visibles y maximo por linea
        tiles = 0
        line = [0] * 200
        for e in ents:
            if e['sig'] & SIG_HIDDEN:
                continue
            r = e['r']
            w = max(0, r[2] - r[0])
            h = max(0, r[3] - r[1])
            if not w or not h:
                continue
            tx = ((r[2] + 1) // 2 + 7) // 8 - (r[0] // 2) // 8 if r[0] >= 0 else (w // 2 + 7) // 8 + 1
            ty = (h + 7) // 8
            tiles += tx * ty
            for y in range(max(0, r[1]), min(200, r[3])):
                line[y] += tx
        kw = self.cur.kwork
        kw['spr_tiles'] = max(kw.get('spr_tiles', 0), tiles)
        kw['spr_linea'] = max(kw.get('spr_linea', 0), max(line))
        self.work('animate_ents', len(ents))
        self.work('animate_moving', moving)
        self.work('cel_px', px)
        self.cur.cast = len(ents)
        self.end_cycle()
        return None

    def _invoke_doit(self, o):
        self.invoke(o, 'doit')

    def _draw(self, e):
        r = e['r']
        n = max(0, (r[2] - r[0]) * (r[3] - r[1]))
        self.screen.draw_cel_pri(r, e['pri'])
        return n

    def _ctl_box(self, e, c):
        r = e['r']
        top = max(r[1], min(self.screen.pri_to_coord(e['pri']) - 1, r[3] - 1))
        self.screen.fill_control([r[0], top, r[2], r[3]], c)

    def _bits_save(self, r, planes):
        h = self.bits_next
        self.bits_next += 1
        n = max(0, (r[2] - r[0]) * (r[3] - r[1]))
        snap = self.screen.save_control(r)
        self.bits[h] = (b'\0' * (n * planes // 2 + 8), snap)
        self.work('bits_save_px', n)
        return h

    def _bits_restore(self, h):
        b = self.bits.pop(h, None)
        if b is not None and isinstance(b, tuple):
            self.screen.restore_control(b[1])
            self.work('bits_restore_px', b[1][4] if b[1] else 0)

    # ------------------------------------------------------------ ciclos
    def _new_cycle(self):
        c = Cycle()
        c.room = 0
        c.ops = 0
        c.cat = {}
        c.kcalls = {}
        c.kwork = {}
        c.cast = 0
        c.wait = 0
        c.sends = 0
        c.ticks = 0
        return c

    def end_cycle(self):
        c = self.cur
        try:
            c.room = self.rw(self.scripts[0].locals_addr + 2 * 11)
        except KeyError:
            c.room = 0
        c.ops = sum(sum(v) for v in c.cat.values())
        c.heap = (self.heap.used, self.heap.by_tag(), self.sp_peak - STACK_LO,
                  {n: (s.size, s.code_bytes) for n, s in self.scripts.items()})
        c.hunk = self.hunk_by_type()
        c.ticks = self.ticks
        self.cycles.append(c)
        self.cur = self._new_cycle()
        self.sp_peak = self.sp
        self.cyc_ops = 0
        if len(self.cycles) >= self.max_cycles:
            self.stop = True

    # ------------------------------------------------------------ arranque
    def run(self):
        s0 = self.load_script(0)
        game = s0.base + s0.exports[0]
        self.game = game
        try:
            self.invoke(game, 'play')
        except StopRun:
            pass


class StopRun(Exception):
    pass


if __name__ == '__main__':
    vm = VM(sys.argv[1])
    vm.max_cycles = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    try:
        vm.run()
    except VMError as e:
        print('ERROR VM:', e)
    print('ciclos', len(vm.cycles), 'ops', vm.ops_total, 'heap pico', vm.heap.peak, 'hunk pico', vm.hunk_peak)
    print('sin implementar:', getattr(vm, 'unimpl', {}))
