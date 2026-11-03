"""Referencia independiente (port literal de ScummVM engines/agi, commit f7403b6): picture.cpp (PictureMgr), GfxMgr::putPixel/checkControlPixel/priorityFromY/priorityToY y
SpritesMgr::drawCel/addToPic/addToPicDrawPriorityBox. No usa agi_read.Picture ni agi_vm.py: solo los bytes de la imagen y de la vista.
Pantalla 160x168; vis = codigos AGI 0-15; pri = plano de prioridad."""
W, H = 160, 168


class Ref:
    cov = None                           # si es una lista de 160 x 168, drawCel marca en ella los pixeles que pinta (para comparar la cobertura de los sprites)

    def __init__(self):
        self.clear()
        # initPriorityTable por defecto (set.pri.base no modelado)
        self.ptable = [4 if y < 48 else min(15, (y - 48) // 12 + 5) for y in range(H)]

    def clear(self, color=15, pri=4):
        self.vis = [color] * (W * H)
        self.pri = [pri] * (W * H)

    # ---- GfxMgr
    def priority_from_y(self, y):
        return self.ptable[y]

    def priority_to_y(self, p):          # _priorityTableSet == false (sin set.pri.base): (priority - 5) * 12 + 48
        return (p - 5) * 12 + 48

    def check_control_pixel(self, x, y, vp):
        while True:
            y += 1
            if y >= H:
                return True
            cp = self.pri[y * W + x]
            if cp > 2:
                break
        return cp <= vp

    # ---- PictureMgr
    def put_virt(self, x, y):
        if not (0 <= x < W and 0 <= y < H):
            return
        if self.pri_on:
            self.pri[y * W + x] = self.pri_color
        if self.scr_on:
            self.vis[y * W + x] = self.scr_color

    def nb(self):
        v = self.d[self.p] if self.p < len(self.d) else 0xFF
        self.p += 1
        return v

    def param(self):
        v = self.nb()
        if v >= 0xF0:
            self.p -= 1
            return None
        return v

    def coords(self):
        x = self.param()
        if x is None:
            return None
        y = self.param()
        if y is None:
            return None
        return x, y

    def line(self, x1, y1, x2, y2):
        x1 = max(0, min(W - 1, x1)); x2 = max(0, min(W - 1, x2))
        y1 = max(0, min(H - 1, y1)); y2 = max(0, min(H - 1, y2))
        if x1 == x2:
            if y1 > y2:
                y1, y2 = y2, y1
            for y in range(y1, y2 + 1):
                self.put_virt(x1, y)
            return
        if y1 == y2:
            if x1 > x2:
                x1, x2 = x2, x1
            for x in range(x1, x2 + 1):
                self.put_virt(x, y1)
            return
        sx = 1; dx = x2 - x1
        if dx < 0:
            sx = -1; dx = -dx
        sy = 1; dy = y2 - y1
        if dy < 0:
            sy = -1; dy = -dy
        if dy > dx:
            i = dy; det = dy; ex = dy // 2; ey = 0
        else:
            i = dx; det = dx; ex = 0; ey = dx // 2
        x, y = x1, y1
        self.put_virt(x, y)
        while True:
            ey += dy
            if ey >= det:
                ey -= det; y += sy
            ex += dx
            if ex >= det:
                ex -= det; x += sx
            self.put_virt(x, y)
            i -= 1
            if i <= 0:
                break

    def x_corner(self):
        c = self.coords()
        if c is None:
            return
        x1, y1 = c
        self.put_virt(x1, y1)
        while True:
            x2 = self.param()
            if x2 is None:
                break
            self.line(x1, y1, x2, y1)
            x1 = x2
            y2 = self.param()
            if y2 is None:
                break
            self.line(x1, y1, x1, y2)
            y1 = y2

    def y_corner(self):
        c = self.coords()
        if c is None:
            return
        x1, y1 = c
        self.put_virt(x1, y1)
        while True:
            y2 = self.param()
            if y2 is None:
                break
            self.line(x1, y1, x1, y2)
            y1 = y2
            x2 = self.param()
            if x2 is None:
                break
            self.line(x1, y1, x2, y1)
            x1 = x2

    def line_abs(self):
        c = self.coords()
        if c is None:
            return
        x1, y1 = c
        self.put_virt(x1, y1)
        while True:
            c = self.coords()
            if c is None:
                break
            self.line(x1, y1, c[0], c[1])
            x1, y1 = c

    def line_short(self):
        c = self.coords()
        if c is None:
            return
        x1, y1 = c
        self.put_virt(x1, y1)
        while True:
            disp = self.param()
            if disp is None:
                break
            dx = (disp & 0xF0) >> 4
            dy = disp & 0x0F
            if dx & 8:
                dx = -(dx & 7)
            if dy & 8:
                dy = -(dy & 7)
            self.line(x1, y1, x1 + dx, y1 + dy)
            x1 += dx; y1 += dy

    BIN = [0x8000 >> i for i in range(16)]
    CIRCLE_LIST = [0, 1, 4, 9, 16, 25, 37, 50]
    CIRCLE_DATA = [
        0x8000,
        0x0000, 0xE000, 0x0000,
        0x7000, 0xF800, 0xF800, 0xF800, 0x7000,
        0x3800, 0x7C00, 0xFE00, 0xFE00, 0xFE00, 0x7C00, 0x3800,
        0x1C00, 0x7F00, 0xFF80, 0xFF80, 0xFF80, 0xFF80, 0xFF80, 0x7F00, 0x1C00,
        0x0E00, 0x3F80, 0x7FC0, 0x7FC0, 0xFFE0, 0xFFE0, 0xFFE0, 0x7FC0, 0x7FC0, 0x3F80, 0x1F00, 0x0E00,
        0x0F80, 0x3FE0, 0x7FF0, 0x7FF0, 0xFFF8, 0xFFF8, 0xFFF8, 0xFFF8, 0xFFF8, 0x7FF0, 0x7FF0, 0x3FE0, 0x0F80,
        0x07C0, 0x1FF0, 0x3FF8, 0x7FFC, 0x7FFC, 0xFFFE, 0xFFFE, 0xFFFE, 0xFFFE, 0xFFFE, 0x7FFC, 0x7FFC, 0x3FF8, 0x1FF0, 0x07C0]

    def plot_pattern(self, x, y):
        pen_size = self.pat_code & 7
        cp = self.CIRCLE_LIST[pen_size]
        pen_x = x * 2 - pen_size
        if pen_x < 0:
            pen_x = 0
        t16 = W * 2 - 2 * pen_size
        if pen_x >= t16:
            pen_x = t16
        pen_x //= 2
        final_x = pen_x
        pen_y = y - pen_size
        if pen_y < 0:
            pen_y = 0
        t16 = 167 - 2 * pen_size
        if pen_y >= t16:
            pen_y = t16
        final_y = pen_y
        t = (self.pat_num | 1) & 0xFF
        t16 = (pen_size << 1) + 1
        final_y += t16
        pen_width = t16 << 1
        circle_cond = (self.pat_code & 0x10) != 0
        while pen_y < final_y:
            word = self.CIRCLE_DATA[cp]; cp += 1
            counter = 0
            while counter <= pen_width:
                if circle_cond or (self.BIN[counter >> 1] & word):
                    if self.pat_code & 0x20:
                        t8 = t % 2
                        t >>= 1
                        if t8:
                            t ^= 0xB8
                    if not (self.pat_code & 0x20) or (t & 3) == 2:
                        self.put_virt(pen_x, pen_y)
                pen_x += 1
                counter += 4
            pen_x = final_x
            pen_y += 1

    def plot_brush(self):
        while True:
            if self.pat_code & 0x20:
                n = self.param()
                if n is None:
                    break
                self.pat_num = n
            c = self.coords()
            if c is None:
                break
            self.plot_pattern(*c)

    def fill_check(self, x, y):
        if not (0 <= x < W and 0 <= y < H):
            return False
        sc = self.vis[y * W + x]
        sp = self.pri[y * W + x]
        if not self.pri_on and self.scr_on and self.scr_color != 15:
            return sc == 15
        if self.pri_on and not self.scr_on and self.pri_color != 4:
            return sp == 4
        return self.scr_on and sc == 15 and self.scr_color != 15

    def fill(self, x, y):
        if not self.scr_on and not self.pri_on:
            return
        st = [(x, y)]
        while st:
            px, py = st.pop()
            if not self.fill_check(px, py):
                continue
            c = px - 1
            while self.fill_check(c, py):
                c -= 1
            up = down = True
            c += 1
            while self.fill_check(c, py):
                self.put_virt(c, py)
                if self.fill_check(c, py - 1):
                    if up:
                        st.append((c, py - 1)); up = False
                else:
                    up = True
                if self.fill_check(c, py + 1):
                    if down:
                        st.append((c, py + 1)); down = False
                else:
                    down = True
                c += 1

    def draw_picture(self, data, clear=True):
        """decodePicture (AGI v2, sin nibbles). clear=False: superpone (overlay)."""
        if clear:
            self.clear()
        self.d = data
        self.p = 0
        self.pat_code = self.pat_num = 0
        self.pri_on = self.scr_on = False
        self.scr_color, self.pri_color = 15, 4
        while self.p < len(data):
            b = self.nb()
            if b == 0xF0:
                self.scr_color = self.nb(); self.scr_on = True
            elif b == 0xF1:
                self.scr_on = False
            elif b == 0xF2:
                self.pri_color = self.nb(); self.pri_on = True
            elif b == 0xF3:
                self.pri_on = False
            elif b == 0xF4:
                self.y_corner()
            elif b == 0xF5:
                self.x_corner()
            elif b == 0xF6:
                self.line_abs()
            elif b == 0xF7:
                self.line_short()
            elif b == 0xF8:
                while True:
                    c = self.coords()
                    if c is None:
                        break
                    self.fill(*c)
            elif b == 0xF9:
                self.pat_code = self.nb()
            elif b == 0xFA:
                self.plot_brush()
            elif b == 0xFF:
                return

    # ---- SpritesMgr
    def draw_cel(self, cel, x, y, vp, wp=True):
        """drawCel: cel = (w, h, clearkey, bitmap plano w*h). y = abajo-izquierda. Devuelve isViewHidden (True = no se pinto ningun pixel)."""
        w, h, key, bm = cel
        hidden = True
        cy = y - h + 1
        i = 0
        for _ in range(h):
            cx = x
            for _ in range(w):
                c = bm[i]; i += 1
                if c != key and 0 <= cx < W and 0 <= cy < H:
                    sp = self.pri[cy * W + cx]
                    if sp <= 2:
                        if self.check_control_pixel(cx, cy, vp):
                            self.vis[cy * W + cx] = c
                            hidden = False
                            if self.cov is not None:
                                self.cov[cy * W + cx] = True
                    elif sp <= vp:
                        self.vis[cy * W + cx] = c
                        if wp:
                            self.pri[cy * W + cx] = vp
                        hidden = False
                        if self.cov is not None:
                            self.cov[cy * W + cx] = True
                cx += 1
            cy += 1
        return hidden

    def eff_pri(self, x, y):
        """Prioridad con la que cuenta un pixel del plano para un sprite: la suya, o (linea de control 0-2) la primera > 2 que haya debajo (4 si no hay)."""
        v = self.pri[y * W + x]
        if v > 2:
            return v
        for yy in range(y + 1, H):
            v = self.pri[yy * W + x]
            if v > 2:
                return v
        return 4

    def add_to_pic(self, cel, x, y, pri, border, spans=False):
        """addToPic (fixPosition no modelada: x,y ya ajustados) + addToPicDrawPriorityBox.
        spans=True: lo que hace el Z80 por falta de memoria (PLAN.md, SPH/SPP): en vez de escribir la prioridad de cada pixel pintado, sube la prioridad de cada fila de la
        celda, del primer al ultimo pixel opaco, a la del objeto (si es menor), y no dibuja la caja de linea de control en el plano de los sprites; se usa para separar esa limitacion documentada de los fallos de verdad."""
        w, h, key, bm = cel
        if pri == 0:
            pri = self.priority_from_y(y)
        self.draw_cel(cel, x, y, pri, not spans)
        if spans:
            top = y - h + 1
            for j in range(h):
                py = top + j
                if not 0 <= py < H:
                    continue
                xs = [x + i for i in range(w) if bm[j * w + i] != key and 0 <= x + i < W]
                cols = [i for i in range(w) if bm[j * w + i] != key and 0 <= x + i < W]
                # hueco (agihws.asm, GAPMIN): el mayor entre dos mosaicos (de 8 columnas de la celda) consecutivos de la fila; ahi no se sube la prioridad
                gap = None
                if cols:
                    runs = {}
                    for i in cols:
                        a = runs.setdefault(i // 8, [i, i])
                        a[1] = i
                    ks = sorted(runs)
                    best = 0
                    for k1, k2 in zip(ks, ks[1:]):
                        g = runs[k2][0] - runs[k1][1] - 1
                        if g >= 8 and g > best:
                            best, gap = g, (x + runs[k1][1] + 1, x + runs[k2][0] - 1)
                for px in range(min(xs), max(xs) + 1) if xs else ():
                    if gap is not None and gap[0] <= px <= gap[1]:
                        continue
                    if self.eff_pri(px, py) < pri:
                        self.pri[py * W + px] = pri
        if border <= 3 and not spans:      # (el Z80 no pone la caja de prioridad en el plano de los sprites: solo vale para el paso del ego)
            pfy = self.priority_from_y(y)
            ph = 0
            cy = y
            while True:
                ph += 1
                if cy <= 0:
                    break
                cy -= 1
                if self.priority_from_y(cy) != pfy:
                    break
            if h < ph:
                ph = h
            for cx in range(x, x + w):
                self._ppix(cx, y, border)
            if ph > 1:
                cy = y
                for _ in range(ph - 1):
                    cy -= 1
                    self._ppix(x, cy, border)
                    self._ppix(x + w - 1, cy, border)
                for cx in range(x + 1, x + w - 1):
                    self._ppix(cx, cy, border)

    def _ppix(self, x, y, v):
        if 0 <= x < W and 0 <= y < H:
            self.pri[y * W + x] = v


def decode_view_cel(d, loop_nr, cel_nr):
    """view.cpp loadView/unpackViewCelData: (w, h, clearKey, bitmap plano w*h) de la celda; loop y cel fuera de rango se acotan a 0 (setLoop/setCel).
    Devuelve None si la vista no tiene bucles o celdas."""
    nloops = d[2]
    if nloops == 0:
        return None
    if loop_nr >= nloops:
        loop_nr = 0
    lo = d[5 + 2 * loop_nr] | (d[6 + 2 * loop_nr] << 8)
    ncel = d[lo]
    if ncel == 0:
        return None
    if cel_nr >= ncel:
        cel_nr = 0
    co = lo + (d[lo + 1 + 2 * cel_nr] | (d[lo + 2 + 2 * cel_nr] << 8))
    w, h, tm = d[co], d[co + 1], d[co + 2]
    key = tm & 0x0F
    mirrored = bool(tm & 0x80) and ((tm >> 4) & 7) != loop_nr
    bm = [0] * (w * h)
    p = co + 3
    for row in range(h):
        base = row * w
        rem = w
        pos = 0                      # posiciones ya escritas en la fila
        while True:
            b = d[p]; p += 1
            if b == 0:
                col, ln = key, rem
            else:
                col, ln = b >> 4, b & 15
            for k in range(ln):
                # sin espejo se escribe de izquierda a derecha; con espejo, de derecha a izquierda
                bm[base + (w - 1 - pos if mirrored else pos)] = col
                pos += 1
            rem -= ln
            if b == 0:
                break
    return (w, h, key, bm)
