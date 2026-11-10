#!/usr/bin/env python3
"""Imagenes, vistas, fuentes y sonidos de SCI0 (EGA), como ScummVM.

Referencia: engines/sci/graphics/picture.cpp (drawVectorData, flood fill,
patrones), screen.cpp (putPixel, drawLine, dither), ports.cpp (bandas de
prioridad), view.cpp (vistas EGA) y font.cpp.
La pantalla tiene tres capas de 320x200: visual (byte EGA con el tramado
codificado: nibble bajo = color en (x^y) par, alto XOR bajo = el otro),
prioridad y control. La ventana de la imagen empieza en la linea 10.
"""
import struct

W, H = 320, 200
PIC_TOP = 10
MASK_V, MASK_P, MASK_C = 1, 2, 4

DEF_EGAPAL = bytes([
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
    0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x88,
    0x88, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x88,
    0x88, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
    0x08, 0x19, 0x2a, 0x3b, 0x4c, 0x5d, 0x6e, 0x88])
DEF_EGAPRI = bytes(list(range(16)) * 2 + list(range(8)))

CIRCLES = [
    [0x01],
    [0x72, 0x02],
    [0xCE, 0xF7, 0x7D, 0x0E],
    [0x1C, 0x3E, 0x7F, 0x7F, 0x7F, 0x3E, 0x1C, 0x00],
    [0x38, 0xF8, 0xF3, 0xDF, 0x7F, 0xFF, 0xFD, 0xF7, 0x9F, 0x3F, 0x38],
    [0x70, 0xC0, 0x1F, 0xFE, 0xE3, 0x3F, 0xFF, 0xF7, 0x7F, 0xFF, 0xE7, 0x3F, 0xFE, 0xC3, 0x1F, 0xF8, 0x00],
    [0xF0, 0x01, 0xFF, 0xE1, 0xFF, 0xF8, 0x3F, 0xFF, 0xDF, 0xFF, 0xF7, 0xFF, 0xFD, 0x7F, 0xFF, 0x9F, 0xFF,
     0xE3, 0xFF, 0xF0, 0x1F, 0xF0, 0x01],
    [0xE0, 0x03, 0xF8, 0x0F, 0xFC, 0x1F, 0xFE, 0x3F, 0xFE, 0x3F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF,
     0x7F, 0xFF, 0x7F, 0xFE, 0x3F, 0xFE, 0x3F, 0xFC, 0x1F, 0xF8, 0x0F, 0xE0, 0x03]]

_TEX_BYTES = [0x04, 0x29, 0x40, 0x24, 0x09, 0x41, 0x25, 0x45, 0x41, 0x90, 0x50, 0x44, 0x48, 0x08, 0x42, 0x28,
              0x89, 0x52, 0x89, 0x88, 0x10, 0x48, 0xA4, 0x08, 0x44, 0x15, 0x28, 0x24, 0x00, 0x0A, 0x24, 0x20]
# vectorPatternTextures: los bits de cada byte, del menos significativo al mas
TEX = []
for _rep in range(2):
    for _i, _b in enumerate(_TEX_BYTES):
        bits = [bool(_b >> k & 1) for k in range(8)]
        if _i == 31:
            bits = bits[:7]
        TEX.extend(bits)
TEX_OFF = [
    0x00, 0x18, 0x30, 0xc4, 0xdc, 0x65, 0xeb, 0x48, 0x60, 0xbd, 0x89, 0x04, 0x0a, 0xf4, 0x7d, 0x6d,
    0x85, 0xb0, 0x8e, 0x95, 0x1f, 0x22, 0x0d, 0xdf, 0x2a, 0x78, 0xd5, 0x73, 0x1c, 0xb4, 0x40, 0xa1,
    0xb9, 0x3c, 0xca, 0x58, 0x92, 0x34, 0xcc, 0xce, 0xd7, 0x42, 0x90, 0x0f, 0x8b, 0x7f, 0x32, 0xed,
    0x5c, 0x9d, 0xc8, 0x99, 0xad, 0x4e, 0x56, 0xa6, 0xf7, 0x68, 0xb7, 0x25, 0x82, 0x37, 0x3a, 0x51,
    0x69, 0x26, 0x38, 0x52, 0x9e, 0x9a, 0x4f, 0xa7, 0x43, 0x10, 0x80, 0xee, 0x3d, 0x59, 0x35, 0xcf,
    0x79, 0x74, 0xb5, 0xa2, 0xb1, 0x96, 0x23, 0xe0, 0xbe, 0x05, 0xf5, 0x6e, 0x19, 0xc5, 0x66, 0x49,
    0xf0, 0xd1, 0x54, 0xa9, 0x70, 0x4b, 0xa4, 0xe2, 0xe6, 0xe5, 0xab, 0xe4, 0xd2, 0xaa, 0x4c, 0xe3,
    0x06, 0x6f, 0xc6, 0x4a, 0x75, 0xa3, 0x97, 0xe1]


class Screen:
    def __init__(self):
        self.vis = bytearray([15]) * (W * H)
        self.pri = bytearray(W * H)
        self.ctl = bytearray(W * H)
        self.bands = [0] * 200
        self.band_bottom = 190
        self.stats = {}

    # ---------------------------------------------------- bandas de prioridad
    def init_bands(self, old_gfx):
        if old_gfx:
            self._bands(15, 42, 200)
        else:
            self._bands(14, 42, 190)

    def _bands(self, count, top, bottom):
        self.band_count = count
        self.band_top = top
        size = ((bottom - top) * 2000) // count
        b = [0] * 200
        for y in range(top, bottom):
            b[y] = 1 + ((y - top) * 2000) // size
        if count == 15:
            y = bottom
            while True:
                y -= 1
                if b[y] == count:
                    b[y] -= 1
                else:
                    break
        for y in range(bottom, 200):
            b[y] = count
        if bottom == 200:
            bottom = 199
        self.bands = b
        self.band_bottom = bottom

    def _bands_data(self, data):
        i = 0
        b = [0] * 200
        inx = 0
        for inx in range(14):
            p = data[inx]
            while i < p and i < 200:
                b[i] = inx
                i += 1
        while i < 200:
            b[i] = 14
            i += 1
        self.bands = b

    def coord_to_pri(self, y):
        if y < 0:
            return self.bands[0]
        if y > self.band_bottom:
            return self.bands[self.band_bottom]
        return self.bands[y]

    def pri_to_coord(self, p):
        if p <= self.band_count:
            for y in range(self.band_bottom + 1):
                if self.bands[y] == p:
                    return y
        return self.band_bottom

    # ------------------------------------------------- consultas del kernel
    def on_control(self, mask, l, t, r, b):
        """isOnControl sobre un rectangulo en coordenadas de la ventana."""
        t += PIC_TOP
        b += PIC_TOP
        l, r = max(0, l), min(W, r)
        t, b = max(0, t), min(H, b)
        if l >= r or t >= b:
            return 0, 0
        plane = self.pri if mask & MASK_P else self.ctl
        res = 0
        for y in range(t, b):
            row = plane[y * W + l:y * W + r]
            for v in set(row):
                res |= 1 << v
        return res, (r - l) * (b - t)

    def fill_control(self, rect, c):
        l, t, r, b = rect
        t += PIC_TOP
        b += PIC_TOP
        l, r = max(0, l), min(W, r)
        t, b = max(0, t), min(H, b)
        if l >= r:
            return
        for y in range(t, b):
            self.ctl[y * W + l:y * W + r] = bytes([c]) * (r - l)

    def save_control(self, rect):
        l, t, r, b = rect
        t += PIC_TOP
        b += PIC_TOP
        l, r = max(0, l), min(W, r)
        t, b = max(0, t), min(H, b)
        if l >= r or t >= b:
            return None
        rows = [bytes(self.ctl[y * W + l:y * W + r]) for y in range(t, b)]
        return (l, t, r, b, (r - l) * (b - t), rows)

    def restore_control(self, snap):
        if not snap:
            return
        l, t, r, b, n, rows = snap
        for i, y in enumerate(range(t, b)):
            self.ctl[y * W + l:y * W + r] = rows[i]

    def draw_cel_pri(self, rect, pri):
        # Las celdas no tocan la capa de control; para medir no hace falta pintarlas.
        return

    # ------------------------------------------------------------- imagen
    def put(self, x, y, mask, c, p, k):
        o = y * W + x
        if mask & MASK_V:
            self.vis[o] = c
        if mask & MASK_P:
            self.pri[o] = p
        if mask & MASK_C:
            self.ctl[o] = k

    def line(self, x0, y0, x1, y1, c, p, k):
        mask = (MASK_V if c != 255 else 0) | (MASK_P if p != 255 else 0) | (MASK_C if k != 255 else 0)
        y0 += PIC_TOP
        y1 += PIC_TOP
        l = min(max(x0, 0), W - 1)
        t = min(max(y0, 0), H - 1)
        r = min(max(x1, 0), W - 1)
        b = min(max(y1, 0), H - 1)
        if t == b:
            if r < l:
                l, r = r, l
            for i in range(l, r + 1):
                self.put(i, t, mask, c, p, k)
            return
        if l == r:
            if t > b:
                t, b = b, t
            for i in range(t, b + 1):
                self.put(l, i, mask, c, p, k)
            return
        dy = b - t
        dx = r - l
        sy = -1 if dy < 0 else 1
        sx = -1 if dx < 0 else 1
        dy = abs(dy) << 1
        dx = abs(dx) << 1
        self.put(l, t, mask, c, p, k)
        self.put(r, b, mask, c, p, k)
        if dx > dy:
            fr = dy - (dx >> 1)
            while l != r:
                if fr >= 0:
                    t += sy
                    fr -= dx
                l += sx
                fr += dy
                self.put(l, t, mask, c, p, k)
        else:
            fr = dx - (dy >> 1)
            while t != b:
                if fr >= 0:
                    l += sx
                    fr -= dy
                t += sy
                fr += dx
                self.put(l, t, mask, c, p, k)

    def _match(self, x, y, mm, sc, sp, sk):
        o = y * W + x
        if mm == MASK_V:
            e = self.vis[o]
            e = ((e ^ (e >> 4)) & 0x0F) if (x ^ y) & 1 else (e & 0x0F)
            return e == sc
        if mm == MASK_P:
            return self.pri[o] == sp
        return self.ctl[o] == sk

    def fill(self, x, y, c, p, k):
        mask = (MASK_V if c != 255 else 0) | (MASK_P if p != 255 else 0) | (MASK_C if k != 255 else 0)
        px, py = x, y + PIC_TOP
        if not (0 <= px < W and 0 <= py < H):
            return
        o = py * W + px
        sc = self.vis[o]
        sp = self.pri[o]
        sk = self.ctl[o]
        sc = ((sc ^ (sc >> 4)) & 0x0F) if (x ^ y) & 1 else (sc & 0x0F)
        if mask & MASK_V:
            if c == 15 or sc != 15:
                return
        elif mask & MASK_P:
            if p == 0 or sp != 0:
                return
        elif mask & MASK_C:
            if k == 0 or sk != 0:
                return
        if mask & MASK_V and sc == c:
            mask &= ~MASK_V
        if mask & MASK_P and sp == p:
            mask &= ~MASK_P
        if mask & MASK_C and sk == k:
            mask &= ~MASK_C
        if not mask:
            return
        mm = MASK_V if mask & MASK_V else (MASK_P if mask & MASK_P else MASK_C)
        bl, bt, br, bb = 0, PIC_TOP, W - 1, H - 1
        stack = [(px, py)]
        n = 0
        while stack:
            x0, y0 = stack.pop()
            if not self._match(x0, y0, mm, sc, sp, sk):
                continue
            self.put(x0, y0, mask, c, p, k)
            n += 1
            lft = rgt = x0
            while lft > bl and self._match(lft - 1, y0, mm, sc, sp, sk):
                lft -= 1
                self.put(lft, y0, mask, c, p, k)
                n += 1
            while rgt < br and self._match(rgt + 1, y0, mm, sc, sp, sk):
                rgt += 1
                self.put(rgt, y0, mask, c, p, k)
                n += 1
            a_set = b_set = False
            xx = lft
            while xx <= rgt:
                if y0 > bt and self._match(xx, y0 - 1, mm, sc, sp, sk):
                    if not a_set:
                        stack.append((xx, y0 - 1))
                        a_set = True
                else:
                    a_set = False
                if y0 < bb and self._match(xx, y0 + 1, mm, sc, sp, sk):
                    if not b_set:
                        stack.append((xx, y0 + 1))
                        b_set = True
                else:
                    b_set = False
                xx += 1
        self.stats['fill_px'] = self.stats.get('fill_px', 0) + n

    def _pat_px(self, x, y, mask, c, p, k):
        if not (0 <= x and 0 <= y < H):
            return
        if x < W:
            self.put(x, y, mask, c, p, k)
        elif y < H - 1:
            if c != 255 and c & 0xF0:
                c ^= (c << 4) & 0xFF
                c = ((c << 4) | (c >> 4)) & 0xFF
                c ^= (c << 4) & 0xFF
            self.put(0, y + 1, mask, c, p, k)

    def pattern(self, x, y, c, p, k, code, tex):
        size = code & 7
        l, t, r, b = x - size, y - size, x + size + 2, y + size + 1
        if l < 0:
            r -= l
            l = 0
        if t < 0:
            b -= t
            t = 0
        t += PIC_TOP
        b += PIC_TOP
        if r > W + 1:
            l -= r - (W + 1)
            r = W + 1
        if b > H:
            t -= b - H
            b = H
        mask = (MASK_V if c != 255 else 0) | (MASK_P if p != 255 else 0) | (MASK_C if k != 255 else 0)
        if code & 0x10:
            ti = TEX_OFF[tex]
            for yy in range(t, b):
                for xx in range(l, r):
                    if code & 0x20:
                        if TEX[ti]:
                            self._pat_px(xx, yy, mask, c, p, k)
                        ti += 1
                    else:
                        self._pat_px(xx, yy, mask, c, p, k)
        else:
            data = CIRCLES[size]
            di = 0
            bm = data[0]
            bit = 0
            ti = TEX_OFF[tex]
            for yy in range(t, b):
                for xx in range(l, r):
                    if bit == 8:
                        di += 1
                        bm = data[di] if di < len(data) else 0
                        bit = 0
                    if bm & 1:
                        if code & 0x20:
                            if TEX[ti] and 0 <= xx < W and 0 <= yy < H:
                                self.put(xx, yy, mask, c, p, k)
                            ti += 1
                        elif 0 <= xx < W and 0 <= yy < H:
                            self.put(xx, yy, mask, c, p, k)
                    bit += 1
                    bm >>= 1

    def draw_pic(self, data, clear=True, palno=0):
        if clear:
            self.vis[:] = bytes([15]) * (W * H)
            self.pri[:] = bytes(W * H)
            self.ctl[:] = bytes(W * H)
        pals = bytearray(DEF_EGAPAL * 4)
        epri = DEF_EGAPRI
        pal_off = (palno if palno < 4 else 0) * 40
        c, p, k = 0, 255, 255
        x = y = 0
        pos = 0
        pcode = ptex = 0
        n = len(data)
        ops = {}

        def absc():
            nonlocal pos
            b = data[pos]
            xx = data[pos + 1] + ((b & 0xF0) << 4)
            yy = data[pos + 2] + ((b & 0x0F) << 8)
            pos += 3
            return xx, yy

        def relc(xx, yy):
            nonlocal pos
            b = data[pos]
            pos += 1
            if b & 0x80:
                xx -= (b >> 4) & 7
            else:
                xx += b >> 4
            if b & 0x08:
                yy -= b & 7
            else:
                yy += b & 7
            return xx, yy

        def relmed(xx, yy):
            nonlocal pos
            b = data[pos]
            pos += 1
            if b & 0x80:
                yy -= b & 0x7F
            else:
                yy += b
            b = data[pos]
            pos += 1
            if b & 0x80:
                xx -= 128 - (b & 0x7F)
            else:
                xx += b
            return xx, yy

        def gettex():
            nonlocal pos, ptex
            if pcode & 0x20:
                ptex = (data[pos] >> 1) & 0x7F
                pos += 1

        while pos < n:
            op = data[pos]
            pos += 1
            ops[op] = ops.get(op, 0) + 1
            if op == 0xF0:
                c = pals[pal_off + data[pos]]
                pos += 1
                c = (c ^ (c << 4)) & 0xFF
            elif op == 0xF1:
                c = 255
            elif op == 0xF2:
                p = epri[data[pos] & 0x0F]
                pos += 1
            elif op == 0xF3:
                p = 255
            elif op == 0xFB:
                k = data[pos] & 0x0F
                pos += 1
            elif op == 0xFC:
                k = 255
            elif op in (0xF7, 0xF5, 0xF6):
                x, y = absc()
                while pos < n and data[pos] < 0xF0:
                    ox, oy = x, y
                    if op == 0xF7:
                        x, y = relc(x, y)
                    elif op == 0xF5:
                        x, y = relmed(x, y)
                    else:
                        x, y = absc()
                    self.line(ox, oy, x, y, c, p, k)
            elif op == 0xF8:
                while pos < n and data[pos] < 0xF0:
                    x, y = absc()
                    self.fill(x, y, c, p, k)
            elif op == 0xF9:
                pcode = data[pos]
                pos += 1
            elif op in (0xF4, 0xFD):
                gettex()
                x, y = absc()
                self.pattern(x, y, c, p, k, pcode, ptex)
                while pos < n and data[pos] < 0xF0:
                    gettex()
                    if op == 0xF4:
                        x, y = relc(x, y)
                    else:
                        x, y = relmed(x, y)
                    self.pattern(x, y, c, p, k, pcode, ptex)
            elif op == 0xFA:
                while pos < n and data[pos] < 0xF0:
                    gettex()
                    x, y = absc()
                    self.pattern(x, y, c, p, k, pcode, ptex)
            elif op == 0xFE:
                sub = data[pos]
                pos += 1
                if sub == 0:
                    while pos < n and data[pos] < 0xF0:
                        i = data[pos]
                        pals[i] = data[pos + 1]
                        pos += 2
                elif sub == 1:
                    i = data[pos] * 40
                    pos += 1
                    pals[i:i + 40] = data[pos:pos + 40]
                    pos += 40
                elif sub == 2:
                    pos += 41
                elif sub in (3, 5):
                    pos += 1
                elif sub in (4, 6):
                    pass
                elif sub == 7:
                    pos += 3
                    sz = struct.unpack_from('<H', data, pos)[0]
                    pos += 2 + sz
                elif sub == 8:
                    self._bands_data(data[pos:pos + 14])
                    pos += 14
                else:
                    break
            elif op == 0xFF:
                break
            else:
                break
        return ops

    # ------------------------------------------------ salida para analisis
    def visual_ega(self):
        """Pantalla tramada como la EGA (4 bits por pixel)."""
        out = bytearray(W * H)
        v = self.vis
        for y in range(H):
            for x in range(W):
                c = v[y * W + x]
                if c & 0xF0:
                    c ^= (c << 4) & 0xFF
                    c = (c >> 4) if (x ^ y) & 1 else (c & 0x0F)
                out[y * W + x] = c & 0x0F
        return out

    def visual_pairs(self):
        """Pareja de colores (c1, c2) de cada pixel antes de tramar."""
        out = []
        v = self.vis
        for o in range(W * H):
            c = v[o]
            if c & 0xF0:
                d = c ^ ((c << 4) & 0xFF)
                out.append((d & 0x0F, d >> 4))
            else:
                out.append((c & 0x0F, c & 0x0F))
        return out


class View:
    def __init__(self, d):
        self.d = d
        nl = d[0]
        self.loops = []
        mirror = struct.unpack_from('<H', d, 2)[0]
        for i in range(nl):
            lo = struct.unpack_from('<H', d, 8 + i * 2)[0]
            nc = struct.unpack_from('<H', d, lo)[0]
            cels = []
            for c in range(nc):
                co = struct.unpack_from('<H', d, lo + 4 + c * 2)[0]
                w, h = struct.unpack_from('<HH', d, co)
                dx = struct.unpack_from('<b', d, co + 4)[0]
                dy = d[co + 5]
                cels.append((w, h, dx, dy, d[co + 6], co + 7))
            self.loops.append(cels)
            mirror >>= 1

    def nloops(self):
        return len(self.loops)

    def ncels(self, loop):
        if not self.loops:
            return 0
        loop = min(max(loop, 0), len(self.loops) - 1)
        return len(self.loops[loop])

    def cel(self, loop, cel):
        if not self.loops:
            return (0, 0, 0, 0, 0, 0)
        loop = min(max(loop, 0), len(self.loops) - 1)
        cels = self.loops[loop]
        if not cels:
            return (0, 0, 0, 0, 0, 0)
        cel = min(max(cel, 0), len(cels) - 1)
        return cels[cel]

    def pixels(self, loop, cel):
        w, h, dx, dy, key, off = self.cel(loop, cel)
        out = bytearray()
        n = w * h
        p = off
        d = self.d
        while len(out) < n and p < len(d):
            b = d[p]
            p += 1
            out.extend(bytes([b & 0x0F]) * (b >> 4))
        return bytes(out[:n]), w, h, key


class Font:
    def __init__(self, d):
        self.n = struct.unpack_from('<H', d, 2)[0]
        self.h = struct.unpack_from('<H', d, 4)[0]
        self.w = []
        for i in range(self.n):
            o = struct.unpack_from('<H', d, 6 + i * 2)[0]
            self.w.append(d[o] if o < len(d) else 0)

    def cw(self, ch):
        o = ord(ch)
        return self.w[o] if o < self.n else 0


def text_size(font, s, maxw):
    """kernelTextSize aproximado: ajusta por palabras a maxw."""
    if font is None:
        return len(s) * 8, 8
    h = font.h
    if not s:
        return 0, 0
    if maxw <= 0:
        return sum(font.cw(c) for c in s), h
    lines = 0
    widest = 0
    for para in s.split('\n'):
        cur = 0
        for word in para.split(' '):
            ww = sum(font.cw(c) for c in word)
            sp = font.cw(' ')
            if cur and cur + sp + ww > maxw:
                lines += 1
                widest = max(widest, cur)
                cur = ww
            else:
                cur = cur + (sp if cur else 0) + ww
        lines += 1
        widest = max(widest, cur)
    return min(widest, maxw), lines * h


def sound_ticks(d):
    """Duracion (ticks de 60 Hz) de un sonido SCI0: cabecera de 33 bytes y MIDI con deltas."""
    if not d or len(d) < 34:
        return 0
    p = 33
    if d[0] == 2:
        p += 2
    t = 0
    run = 0
    n = len(d)
    while p < n:
        dl = 0
        while p < n and d[p] == 0xF8:
            dl += 240
            p += 1
        if p >= n:
            break
        dl += d[p]
        p += 1
        t += dl
        if p >= n:
            break
        st = d[p]
        if st & 0x80:
            p += 1
            run = st
        else:
            st = run
        if st == 0xFC:
            break
        hi = st & 0xF0
        if hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
            p += 2
        elif hi in (0xC0, 0xD0):
            p += 1
        elif st == 0xF0:
            while p < n and d[p] != 0xF7:
                p += 1
            p += 1
        else:
            p += 0
    return t
