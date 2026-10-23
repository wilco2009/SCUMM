#!/usr/bin/env python3
"""Decodificador de trajes (costumes) de Maniac Mansion v2 (formato 0x58, 16 colores EGA) a partir del codigo de ScummVM
(engines/scumm/costume.cpp: ClassicCostumeLoader / ClassicCostumeRenderer).

Recurso (offsets desde el principio del recurso, con su cabecera de 4 bytes):
  +4 numero de animaciones   +5 formato (&0x7F; bit 7 = espejo)   +6 byte de paleta
  +7 u16 offset de los comandos de animacion (animCmds)
  +9 16 x u16 offsets de la tabla de imagenes de cada miembro (limb)
  +41 u16 por animacion: offset de sus datos (anim = direccion + fotograma * 4)
Datos de una animacion: u16 mascara de miembros (bit 15 = miembro 0); por cada bit (el bit 15 es el miembro 0): u8 j (0xFF: miembro apagado) y, si no es 0xFF, u8 extra:
  curpos = inicio = j, fin = j + (extra & 0x7F). animCmds[curpos] & 0x7F = numero de imagen del miembro (0x7B: nada).
Imagen: u16 ancho, u16 alto, s16 relX, s16 relY, s16 moveX, s16 moveY (12 bytes) y RLE por columnas: byte = color << 4 | cuenta
  (cuenta 0: la cuenta es el byte siguiente); color 0 transparente. Los miembros se dibujan en orden 0..15, acumulando moveX / -moveY.

Uso: costume2.py DIRECTORIO_LFL traje [salida.png]   (hoja de contacto: una fila por direccion/fotograma, una columna por paso de animacion)
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scumm2

EGA = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170),
       (170, 85, 0), (170, 170, 170), (85, 85, 85), (85, 85, 255), (85, 255, 85),
       (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255)]


def u16(b, o):
    return b[o] | (b[o + 1] << 8)


def s16(b, o):
    v = u16(b, o)
    return v - 0x10000 if v & 0x8000 else v


class Costume:
    def __init__(self, data):
        self.b = data
        self.num_anim = data[4]
        self.format = data[5] & 0x7F
        self.mirror = bool(data[5] & 0x80)
        if self.format != 0x58:
            raise ValueError('formato %02X sin soporte' % self.format)
        self.cmds = u16(data, 7)
        self.limb_tab = [u16(data, 9 + 2 * i) for i in range(16)]
        self.anim_tab = [u16(data, 41 + 2 * i) for i in range(self.num_anim + 1)]

    def anim_limbs(self, anim):
        """Miembros activos de la animacion: {miembro: (inicio, fin)} (posiciones en animCmds)."""
        b = self.b
        if anim > self.num_anim:
            return {}
        r = self.anim_tab[anim]
        if r == 0:
            return {}
        mask = u16(b, r)
        r += 2
        out = {}
        i = 0
        while mask:
            if mask & 0x8000:
                j = b[r]
                r += 1
                if j == 0xFF:
                    out[i] = None
                else:
                    extra = b[r]
                    r += 1
                    out[i] = (j, j + (extra & 0x7F), bool(extra & 0x80))
            mask = (mask << 1) & 0xFFFF
            i += 1
        return out

    def picture(self, limb, code):
        """(ancho, alto, relX, relY, moveX, moveY, pixeles[y][x]) de la imagen `code` del miembro; pixeles 0 = transparente."""
        b = self.b
        fp = self.limb_tab[limb]
        p = u16(b, fp + code * 2)
        w, h = u16(b, p), u16(b, p + 2)
        rx, ry, mx, my = s16(b, p + 4), s16(b, p + 6), s16(b, p + 8), s16(b, p + 10)
        src = p + 12
        pix = [[0] * w for _ in range(h)]
        x = y = 0
        while x < w:
            d = b[src]
            src += 1
            color, run = d >> 4, d & 15
            if run == 0:
                run = b[src]
                src += 1
            for _ in range(run):
                if x < w:
                    pix[y][x] = color
                y += 1
                if y >= h:
                    y = 0
                    x += 1
        return w, h, rx, ry, mx, my, pix

    def render(self, anim, pos=None, mirror=False):
        """Compone la animacion en el paso `pos` ({miembro: posicion en animCmds}); devuelve la lista de (x, y, pixeles) y el rectangulo."""
        limbs = anim if isinstance(anim, dict) else self.anim_limbs(anim)
        xm = ym = 0
        parts = []
        for limb in range(16):
            if limb not in limbs or limbs[limb] is None:
                continue
            start, end, high = limbs[limb]
            cur = start if pos is None else pos.get(limb, start)
            code = self.b[self.cmds + cur] & 0x7F
            if code == 0x7B:
                continue
            w, h, rx, ry, mx, my, pix = self.picture(limb, code)
            x0, y0 = xm + rx - 80, ym + ry - 100      # el origen del traje esta en (80, 100): el centro de los pies
            xm += mx
            ym -= my
            if mirror:
                x0 = -x0 - w
                pix = [row[::-1] for row in pix]
            parts.append((x0, y0, pix))
        return parts

    def merged(self, anim):
        """Miembros de una animacion de caminar o quieto sobre los de la animacion de inicio de la misma direccion (la cabeza viene de ella, como en
        ScummVM: una animacion solo cambia los miembros que nombra)."""
        limbs = dict(self.anim_limbs(8 + anim % 4))
        limbs.update(self.anim_limbs(4 + anim % 4))     # quieto
        limbs.update(self.anim_limbs(anim))
        return {k: v for k, v in limbs.items() if v}

    def steps(self, anim):
        """Posiciones de cada miembro en los pasos sucesivos de la animacion (hasta que se repiten): lista de {miembro: posicion}."""
        limbs = {k: v for k, v in (anim if isinstance(anim, dict) else self.anim_limbs(anim)).items() if v}
        cur = {k: v[0] for k, v in limbs.items()}
        seq = []
        seen = set()
        for _ in range(64):
            key = tuple(sorted(cur.items()))
            if key in seen:
                break
            seen.add(key)
            seq.append(dict(cur))
            for k, (s, e, high) in limbs.items():
                i = cur[k]
                if not high:
                    i += 1
                    if i >= e + 1 and True:
                        i = s
                elif i != e:
                    i += 1
                # los comandos 0x7C / 0x78 del siguiente paso se saltan solo con start != end (no se usan para dibujar)
                cur[k] = i
        return seq


SCALE = (3, 4)        # factor de escala de los personajes (numerador, denominador)
MIRROR_OLD_DIR = (True, False)   # anim % 4 == 0 (izquierda) se dibuja en espejo y 1 (derecha) tal cual (_drawActorToRight = direccion != 0 de ScummVM)


def cells_of(parts, emap):
    """Compone las partes y las trocea en celdas de 8x8: (dx, dy, cw, ch, [celdas]); celda = (pix[8], mascara[8], color[8]) para un sprite
    de la placa (tinta en el nibble alto del color, papel en el bajo; pix 1 = tinta; mascara 1 = opaco)."""
    x0, y0, x1, y1 = bounds(parts)
    if x1 <= x0 or y1 <= y0:
        return None
    full = [[0] * (x1 - x0) for _ in range(y1 - y0)]
    for px, py, pix in parts:
        for y, row in enumerate(pix):
            for x, c in enumerate(row):
                if c:
                    full[py + y - y0][px + x - x0] = c
    # escalado a SCALE (con 64 sprites hay que repartir ~21 por personaje: tres personajes caben): cada pixel nuevo toma el color mas frecuente de su bloque
    # de origen si al menos la mitad de este es opaco
    num, den = SCALE
    sx0, sx1 = (x0 * num) // den, -((-x1 * num) // den)
    sy0, sy1 = (y0 * num) // den, -((-y1 * num) // den)
    gx, gy = sx0, sy0                     # los sprites se colocan en cualquier pixel: la rejilla parte de la esquina de la imagen
    cw, ch = (sx1 - gx + 7) // 8, (sy1 - gy + 7) // 8
    canvas = [[0] * (cw * 8) for _ in range(ch * 8)]
    for Y in range(sy0, sy1):
        ya, yb = -((-Y * den) // num), -((-(Y + 1) * den) // num)
        for X in range(sx0, sx1):
            xa, xb = -((-X * den) // num), -((-(X + 1) * den) // num)
            cnt, tot = {}, 0
            for yy in range(max(ya, y0), min(max(yb, ya + 1), y1)):
                for xx in range(max(xa, x0), min(max(xb, xa + 1), x1)):
                    tot += 1
                    c = full[yy - y0][xx - x0]
                    if c:
                        cnt[c] = cnt.get(c, 0) + 1
            if tot and sum(cnt.values()) * 2 >= tot:
                canvas[Y - gy][X - gx] = max(cnt, key=lambda c: cnt[c])
    rgb = lambda m: tuple((255 if m >> 3 else 170) if (m >> bit) & 1 else (85 if m >> 3 else 0) for bit in (1, 2, 0))
    cells = []
    for cy in range(ch):
        for cx in range(cw):
            pix, mask, col = [], [], []
            for y in range(8):
                row = canvas[cy * 8 + y][cx * 8:cx * 8 + 8]
                cnt = {}
                for c in row:
                    if c:
                        cnt[emap[c]] = cnt.get(emap[c], 0) + 1
                order = sorted(cnt, key=lambda m: -cnt[m])
                ink = order[0] if order else 0
                paper = order[1] if len(order) > 1 else ink
                p = m = 0
                for c in row:
                    p <<= 1
                    m <<= 1
                    if c:
                        m |= 1
                        k = emap[c]
                        if k == ink or (k != paper and sum((a - b) ** 2 for a, b in zip(rgb(k), rgb(ink))) <= sum((a - b) ** 2 for a, b in zip(rgb(k), rgb(paper)))):
                            p |= 1
                pix.append(p)
                mask.append(m)
                col.append((ink << 4) | paper)
            if any(mask):
                cells.append((cx | (cy << 4), pix, mask, col))
    return gx, gy, cw, ch, cells


def costume_blob(cost, emap, talk=True, two=True):
    """Datos de un traje para el Z80: u8 numero de animaciones; por animacion u16 offset de su lista (0: no existe); la lista: u8 pasos y, por paso,
    u16 offset del fotograma; fotograma: s8 dx, s8 dy, u8 cw, u8 ch, u8 n y n celdas no vacias: u8 cx | cy << 4, u8 banderas (bit 0: mascara completa, no se guarda; bit 1: color uniforme, un solo byte), pix[8], [mascara[8]], color (1 u 8 bytes)."""
    # 0-3 caminar (dos poses; quieto = la primera); 4-7 hablando (cabeza de inicio + quieto + TALK_START = anim 20 + dir; segunda pose con TALK_STOP), si el traje lo tiene
    na = 8 if talk and cost.num_anim >= 20 else min(cost.num_anim + 1, 4)
    head = bytearray(1 + 2 * na)
    head[0] = na
    body = bytearray()
    frames = {}
    base = len(head)
    lists = {}
    for anim in range(na):
        if anim >= 4:
            if 16 + anim > cost.num_anim:
                continue
            base_l = dict(cost.anim_limbs(8 + anim % 4))      # cabeza de inicio + quieto
            base_l.update(cost.anim_limbs(anim))
            poses = []
            for extra in ((16 + anim, 12 + anim) if two else (16 + anim,)):   # TALK_START (boca abierta) y TALK_STOP (cerrada): dos poses que se alternan; si no caben, solo la abierta
                limbs = dict(base_l)
                limbs.update(cost.anim_limbs(extra))
                limbs = {k: v for k, v in limbs.items() if v}
                if limbs:
                    seq = cost.steps(limbs)
                    if seq:
                        poses.append((limbs, seq[0]))
        else:
            limbs = cost.merged(anim)
            seq = cost.steps(limbs) if limbs else []
            if len(seq) > 2:
                seq = [seq[0], seq[len(seq) // 2]]             # dos poses de caminar
            poses = [(limbs, pos) for pos in seq]
        if not poses:
            continue
        mir = MIRROR_OLD_DIR[anim % 4] if anim % 4 < 2 else False
        offs = []
        for limbs, pos in poses:
            parts = cost.render(limbs, pos, mirror=mir)
            fr = cells_of(parts, emap)
            if fr is None:
                offs.append(0xFFFF)
                continue
            gx, gy, cw, ch, cells = fr
            key = (gx, gy, cw, ch, tuple((p, tuple(a), tuple(m), tuple(c)) for p, a, m, c in cells))
            if key not in frames:
                frames[key] = len(body)
                body += struct.pack('<bbBBB', max(-128, min(127, gx)), max(-128, min(127, gy)), cw, ch, len(cells))
                for p, pix, mask, col in cells:
                    full = all(m == 0xFF for m in mask)
                    uni = len(set(col)) == 1
                    body += bytes([p, (1 if full else 0) | (2 if uni else 0)]) + bytes(pix)
                    if not full:
                        body += bytes(mask)
                    body += bytes(col[:1]) if uni else bytes(col)
            offs.append(frames[key])
        lists[anim] = offs
    lst = bytearray()
    list_base = base + len(body)
    for anim, offs in lists.items():
        struct.pack_into('<H', head, 1 + 2 * anim, list_base + len(lst))
        lst.append(len(offs))
        for o in offs:
            lst += struct.pack('<H', o if o == 0xFFFF else base + o)
    return bytes(head) + bytes(body) + bytes(lst)


def bounds(parts):
    xs = [x for x, y, p in parts] + [x + len(p[0]) for x, y, p in parts if p]
    ys = [y for x, y, p in parts] + [y + len(p) for x, y, p in parts]
    return (min(xs), min(ys), max(xs), max(ys)) if xs else (0, 0, 0, 0)


def paint(parts, canvas, ox, oy):
    for x0, y0, pix in parts:
        for y, row in enumerate(pix):
            for x, c in enumerate(row):
                if c:
                    X, Y = ox + x0 + x, oy + y0 + y
                    if 0 <= Y < len(canvas) and 0 <= X < len(canvas[0]):
                        canvas[Y][X] = EGA[c]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    d = sys.argv[1]
    cid = int(sys.argv[2])
    ix = scumm2.Index(d)
    cost = Costume(scumm2.resource(d, ix, 'costume', cid))
    print('traje %d: %d animaciones, formato %02X, espejo %s' % (cid, cost.num_anim, cost.format, cost.mirror))
    cell = 56
    rows = []
    for anim in range(cost.num_anim + 1):
        seq = cost.steps(anim)
        rows.append((anim, seq))
    cols = max((len(s) for a, s in rows), default=1)
    cols = min(cols, 8)
    W, H = cell * max(cols, 1), cell * len(rows)
    canvas = [[(40, 40, 40)] * W for _ in range(H)]
    for r, (anim, seq) in enumerate(rows):
        for c, pos in enumerate(seq[:cols]):
            parts = cost.render(anim, pos)
            paint(parts, canvas, c * cell + cell // 2, r * cell + cell - 8)
    if len(sys.argv) > 4 and sys.argv[4] == 'blob':
        import lfl2gfx as L
        emap = L.default_map({})
        blob = costume_blob(cost, emap)
        print('blob', len(blob), 'bytes')
        return 0
    out = sys.argv[3] if len(sys.argv) > 3 else 'costume%02d.png' % cid
    import lfl2gfx
    lfl2gfx.write_png(out, canvas)
    print('escrito', out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
