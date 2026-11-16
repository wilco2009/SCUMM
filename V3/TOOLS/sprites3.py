#!/usr/bin/env python3
"""sprites3.py: modelo de referencia de los sprites de los actores de v3 (fase 8), en Python.

Dado el estado que el Z80 tiene en memoria (registros de los actores, camara, contadores de poses, caja y mascara de la sala) y el DATA.BIN, calcula la
tabla de sprites que `actors_run` (V3/ENGINE/ovd_act.asm, overlay D) tiene que dejar. `V3/ENGINE/test/check_spr.py` la compara con el volcado del arnes.
No toca la cache de firma (es una optimizacion: no cambia el resultado) ni los contadores (los lleva el Z80 y se leen de la memoria).

Reglas (las mismas que el Z80; ver el encabezado de ovd_act.asm):
  - actores 1..12 de la sala (CURROOM), visibles y con traje; ordenados por la y (byte bajo; empate: el de menor numero primero); el primero recibe los sprites 0, 1...
  - animacion = fotograma * 4 + newDirToOldDir(direccion): blob principal (COSTDIR), si no esta el extra (COSTDIR2); si tampoco, la del fotograma de quieto;
    sin ninguna: no se dibuja. Postura = ((contador * pasos) >> 3) mod pasos.
  - sprite x = x - camara + dx + 32 (0 <= x < 319); sprite y = (y - elevacion + dy) + celda * 8 + HR_TOP - ytop + 32 (0 <= y < 256); si el actor no cabe en los
    63 sprites (63 = cursor), no se dibuja; una celda mas alla del 62 se pierde.
  - mascara de la sala (si la sala la tiene, la caja del actor tiene mascara, el fotograma mide como mucho 6 x 8 celdas y la columna de su borde izquierdo
    no es negativa): a la mascara de cada celda se le quitan los pixeles que tapa la sala. Las lineas de pantalla fuera de [16, 144) no se ven.
"""
import struct
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack_data3 as P3          # noqa: E402

HR_TOP = 16
NACT = 13
ASIZE = 64
A_ROOM, A_X, A_Y, A_COST, A_FACING, A_MOVING, A_VIS, A_FRAME = 0, 1, 3, 5, 7, 9, 10, 11
A_ELEV, A_WBOX, A_STAND = 17, 16, 25
AC_MAXSPR = 63
AC_XMAX = 32                     # sprites extra como mucho


def s16(v):
    return v - 65536 if v & 0x8000 else v


def s8(v):
    return v - 256 if v & 0x80 else v


def new_dir_to_old_dir(d):
    """ScummVM util.cpp newDirToOldDir (el Z80 lo calcula sobre el angulo de 16 bits sin signo)."""
    if 71 <= d <= 109:
        return 1
    if 109 <= d <= 251:
        return 2
    if 251 <= d <= 289:
        return 0
    return 3


class Blobs:
    """Los blobs de trajes de un DATA.BIN."""

    def __init__(self, data):
        self.d = data
        self.cache = {}

    def blob(self, table, cost):
        key = (table, cost)
        if key not in self.cache:
            page, addr = self.d.ptr(table, cost)
            if not page:
                self.cache[key] = None
            else:
                self.cache[key] = self.d.read(page, addr, self.d.page_bytes - (addr - P3.WINDOW))
        return self.cache[key]

    def find(self, cost, anim):
        """(blob, offset de la lista) de la animacion en el principal o el extra; None si no esta."""
        if anim > 255:
            return None
        for table in ('COSTDIR', 'COSTDIR2'):
            b = self.blob(table, cost)
            if not b or anim >= b[0]:
                continue
            o = struct.unpack_from('<H', b, 3 + 2 * anim)[0]
            if o:
                return b, o
        return None

    @staticmethod
    def cell(blob, idx):
        """Celda idx del fondo de celdas: (pix[8], mascara[8], color[8])."""
        pool = struct.unpack_from('<H', blob, 1)[0]
        o = struct.unpack_from('<H', blob, pool + 2 * idx)[0]
        flags = blob[o]
        pix = list(blob[o + 1:o + 9])
        p = o + 9
        if flags & 1:
            mask = [0xFF] * 8
        else:
            mask = list(blob[p:p + 8])
            p += 8
        col = [blob[p]] * 8 if flags & 2 else list(blob[p:p + 8])
        return pix, mask, col


def mask_bit(mask_blob, rows, X, Y):
    """Pixel (X, Y) de la sala bajo la mascara de profundidad (1 = tapa al actor): lfl2gfx.mask_blob."""
    if not mask_blob or X < 0 or Y < 0 or Y >= rows:
        return 0
    strips = mask_blob[0]
    s = X >> 3
    if s >= strips:
        return 0
    off = struct.unpack_from('<H', mask_blob, 1 + 2 * s)[0]
    if not off:
        return 0
    row = 0
    p = off
    while True:
        ln = mask_blob[p]
        if not ln:
            return 0
        val = mask_blob[p + 1]
        p += 2
        if row <= Y < row + ln:
            return (val >> (7 - (X & 7))) & 1
        row += ln


class Ref:
    def __init__(self, data, blobs=None):
        self.d = data
        self.b = blobs or Blobs(data)

    def room_mask(self, room_entry):
        mp, ma = struct.unpack_from('<BH', room_entry, 15)
        if not mp:
            return None
        # la mascara se lee hasta el final de su pagina
        return self.d.read(mp, ma, self.d.page_bytes - (ma - P3.WINDOW))

    def expected(self, actors, counters, room, cam, ytop, nboxes, boxes, room_entry, rows):
        """actors: lista de 13 registros (bytes de 64); counters: lista de 13 (ultimo fotograma, contador); boxes: lista de (mascara) por caja.
        Devuelve la lista de sprites [(x, y, pix, mask, color)] (los indices son sus posiciones)."""
        mblob = self.room_mask(room_entry)
        lst = []
        for a in range(1, NACT):
            r = actors[a]
            if r[A_ROOM] != room or not r[A_VIS]:
                continue
            if r[A_COST] == 0 and r[A_COST + 1] == 0:
                continue
            lst.append((r[A_Y], a))
        lst.sort(key=lambda t: (t[0], t[1]))
        # pasada 1, de delante a atras: los actores que caben en los 63 normales; el primero que no cabe y todos los que van mas atras, a los extra (hasta XMAX)
        picks = []
        for _, a in lst:
            p = self.pick(actors[a], counters[a])
            picks.append((a, p, p[0][p[1] + 4] if p else 0))
        modes = [None] * len(picks)
        tot = tx = 0
        ovf = False
        for i in range(len(picks) - 1, -1, -1):
            a, p, n = picks[i]
            if p is None:
                modes[i] = 2
                continue
            if not ovf and tot + n <= AC_MAXSPR:
                tot += n
                modes[i] = 0
                continue
            ovf = True
            if tx + n <= AC_XMAX:
                tx += n
                modes[i] = 1
            else:
                modes[i] = 2
        out, xout = [], []
        for i, (a, p, n) in enumerate(picks):                       # normales: de atras adelante
            if modes[i] == 0:
                out += self.draw(actors[a], counters[a], len(out), cam, ytop, nboxes, boxes, mblob, rows)
        for i in range(len(picks) - 1, -1, -1):                     # extra: de delante atras
            a, p, n = picks[i]
            if modes[i] == 1:
                xout += self.draw(actors[a], counters[a], len(xout), cam, ytop, nboxes, boxes, mblob, rows, extra=True)
        self.extra = xout
        return out

    def pick(self, r, cnt):
        """(blob, frame offset) que se dibuja o None."""
        cost = r[A_COST] | (r[A_COST + 1] << 8)
        if cost == 0 or cost >= 129:
            return None
        facing = r[A_FACING] | (r[A_FACING + 1] << 8)
        d = new_dir_to_old_dir(facing)
        frame = r[A_FRAME]
        f = self.b.find(cost, frame * 4 + d)
        if f is None:
            if r[A_STAND] == frame:
                return None
            f = self.b.find(cost, r[A_STAND] * 4 + d)
            if f is None:
                return None
        blob, o = f
        steps = blob[o]
        if steps == 0:
            return None
        pc = cnt[1]
        pose = ((pc * steps) >> 3) & 0xFF
        pose %= steps
        fo = struct.unpack_from('<H', blob, o + 1 + 2 * pose)[0]
        if fo == 0xFFFF:
            return None
        return blob, fo

    def draw(self, r, cnt, first, cam, ytop, nboxes, boxes, mblob, rows, extra=False):
        p = self.pick(r, cnt)
        if p is None:
            return []
        blob, fo = p
        dx, dy, cw, ch, n = s8(blob[fo]), s8(blob[fo + 1]), blob[fo + 2], blob[fo + 3], blob[fo + 4]
        x = s16(r[A_X] | (r[A_X + 1] << 8)) - cam + dx
        ry = s16(r[A_Y] | (r[A_Y + 1] << 8)) - s16(r[A_ELEV] | (r[A_ELEV + 1] << 8)) + dy
        if first + n > (AC_XMAX if extra else AC_MAXSPR):
            return []
        # mascara de profundidad
        use_mask = False
        wbox = r[A_WBOX]
        if mblob and wbox < nboxes and boxes[wbox] and cw < 7 and ch < 9:
            X0 = x + cam
            if X0 >= 0 and (X0 >> 3) <= 255:
                use_mask = True
        out = []
        for i in range(n):
            pos, idx = blob[fo + 5 + 2 * i], blob[fo + 6 + 2 * i]
            cx = ((pos & 15) * 8 + x + 32) & 0xFFFF
            if cx & 0x8000 or s16(cx) >= 319:
                continue
            cy = (pos >> 4) * 8 + ry + HR_TOP + 32 - ytop
            if cy < 0 or cy > 255:
                continue
            if first + len(out) >= (AC_XMAX if extra else AC_MAXSPR):
                continue
            pix, mask, col = self.b.cell(blob, idx)
            mask = list(mask)
            if use_mask:
                for rr in range(8):
                    cov = 0
                    for c in range(8):
                        X = x + cam + (pos & 15) * 8 + c
                        Y = ry + (pos >> 4) * 8 + rr
                        if mask_bit(mblob, rows, X, Y):
                            cov |= 0x80 >> c
                    mask[rr] &= ~cov & 0xFF
            line0 = cy - 32
            for rr in range(8):
                if not (HR_TOP <= line0 + rr < HR_TOP + 128):
                    mask[rr] = 0
            out.append((cx, cy, pix, mask, col))
        return out


# ------------------------------------------------------------------------------------------------------------------ comprobacion con un volcado
def load_sym(path):
    sym = {}
    for ln in open(path):
        p = ln.split()
        if len(p) == 3 and p[1] == 'EQU':
            sym[p[0]] = int(p[2].rstrip('Hh'), 16)
    return sym


def check_dump(dump, sym, data, verbose=True):
    """Compara los sprites de un volcado de test_scumm con la referencia. Devuelve (comprobados, distintos, esperados)."""
    lg = dump[65536:131072]
    rd = lambda a, n=1: lg[a:a + n]
    w16 = lambda a: lg[a] | (lg[a + 1] << 8)
    actors_at = sym['ACTORS']
    actors = [bytes(lg[actors_at + i * ASIZE:actors_at + (i + 1) * ASIZE]) for i in range(NACT)]
    acc = sym['ACCNT']
    counters = [(lg[acc + 2 * i], lg[acc + 2 * i + 1]) for i in range(NACT)]
    room = lg[sym['CURROOM']]
    cam = w16(sym['aq_cam'])
    ytop = lg[sym['hv_ytop']]
    nboxes = lg[sym['NBOXES']]
    rb = sym['RBLOB']
    boxes = [lg[rb + 1 + 18 * k + 16] for k in range(nboxes)]
    entry = bytes(lg[sym['CURRD']:sym['CURRD'] + 32])
    rows = entry[8]
    ref = Ref(data)
    exp = ref.expected(actors, counters, room, cam, ytop, nboxes, boxes, entry, rows)
    sprites = dump[131072:131072 + 64 * 32]
    xbase, xm = (dump[131072 + 64 * 32 + 8], dump[131072 + 64 * 32 + 9]) if len(dump) > 131072 + 64 * 32 + 10 else (0, 0)
    x0 = dump[131072 + 64 * 32 + 10:131072 + 64 * 32 + 10 + 0x400]
    bad = 0
    if os.environ.get('EXPECT_PC'):                       # escenas de actscen.sh: el fotograma de cada actor cambia en cada escena y el volcado se hace 2 vueltas despues
        for a in range(1, NACT):
            r = actors[a]
            if r[A_ROOM] == room and r[A_VIS] and (r[A_COST] or r[A_COST + 1]):
                pf, pc = counters[a]
                if pf != r[A_FRAME] or pc > 2:
                    bad += 1
                    if verbose:
                        print('actor %d: contador de poses (ultimo fotograma %d, contador %d) no vale para el fotograma %d' % (a, pf, pc, r[A_FRAME]))
    for i in range(AC_MAXSPR):
        b = sprites[32 * i:32 * i + 32]
        on, x, y = b[0], b[1] | (b[2] << 8), b[3]
        col, pix, mask = list(b[4:12]), list(b[12:20]), list(b[20:28])
        if i < len(exp):
            ex = exp[i]
            if not on or (x, y) != (ex[0], ex[1]) or pix != ex[2] or mask != ex[3] or col != ex[4]:
                bad += 1
                if verbose and bad <= 5:
                    print('sprite %d: Z80 on=%d x=%d y=%d pix=%s mask=%s col=%s; esperado x=%d y=%d pix=%s mask=%s col=%s' % (
                        i, on, x, y, pix, mask, col, ex[0], ex[1], ex[2], ex[3], ex[4]))
        elif on:
            bad += 1
            if verbose and bad <= 5:
                print('sprite %d encendido (x=%d y=%d) y no se espera ninguno' % (i, x, y))
    xexp = getattr(ref, 'extra', [])
    if xm != len(xexp) or (xexp and xbase != 0):
        bad += 1
        if verbose:
            print('sprites extra: POKE 2131 = %d (hoja %d), esperados %d' % (xm, xbase, len(xexp)))
    for j, ex in enumerate(xexp):
        b = x0[32 * j:32 * j + 32]
        x, y = b[1] | (b[2] << 8), b[3]
        if (x, y) != (ex[0], ex[1]) or list(b[12:20]) != ex[2] or list(b[20:28]) != ex[3] or list(b[4:12]) != ex[4] or b[29] != 0:
            bad += 1
            if verbose and bad <= 5:
                print('extra %d: Z80 x=%d y=%d pix=%s mask=%s col=%s fmt=%d; esperado x=%d y=%d pix=%s mask=%s col=%s' % (
                    j, x, y, list(b[12:20]), list(b[20:28]), list(b[4:12]), b[29], ex[0], ex[1], ex[2], ex[3], ex[4]))
    return AC_MAXSPR + len(xexp), bad, exp + xexp


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print('uso: sprites3.py volcado.bin scumm.sym DATA.BIN')
        sys.exit(1)
    dump = open(sys.argv[1], 'rb').read()
    sym = load_sym(sys.argv[2])
    data = P3.Data(open(sys.argv[3], 'rb').read())
    n, bad, exp = check_dump(dump, sym, data)
    print('sprites esperados %d; comprobados %d, distintos %d' % (len(exp), n, bad))
    sys.exit(1 if bad else 0)
