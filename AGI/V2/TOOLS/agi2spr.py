#!/usr/bin/env python3
"""agi2spr.py: celdas de las vistas de AGI v2 -> sprites por hardware del SD81 Booster (8x8, color por fila, mascara).

Cada celda (w x h pixeles de AGI) se estira al HiRes (el pixel a ocupa los pixeles (8a+4)//5 .. (8(a+1)+4)//5 - 1 de la celda, 1 o 2) y se corta en
mosaicos de 8x8. De cada fila de 8 pixeles de un mosaico se guardan: mascara (pixel opaco), dato (1 = tinta) y color (tinta*16 + papel, codigos de
Chroma). Si la fila tiene mas de dos colores se quedan los dos mas frecuentes y los demas pasan al mas cercano (agi2hr.sdist). Los mosaicos sin
ningun pixel opaco no se guardan. Los bucles espejados (bit 7 del byte de la celda y bucle distinto del de origen) ya vienen invertidos.

Fichero Nvvvl.SPR (vvv = vista, l = bucle), little endian:
  +0   u16 tamano del resto
  +2   u8  numero de celdas
  +3   u16 por celda: desplazamiento de su registro desde +2
  registro de celda: u8 mosaicos, u8 ancho HiRes, u8 alto, u8 banderas (bit 0 = software), u16 huella de las mascaras, y por mosaico: u8 tx, u8 ty,
  8 bytes de color, 8 de dato y 8 de mascara (los 24 bytes van tal cual a 2105-2128: color, forma, mascara)
  Las celdas con mas de SW_TILES mosaicos en una fila (rotulos anchos) no caben en los sprites (12 por linea): las dibuja el Z80 en el bitmap, por celdas;
  la huella (FNV-1a de las mascaras) dice si dos celdas tienen la misma forma (solo cambian los colores).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi2hr
import agi_read as ag


def lo(a):
    return (8 * a + 4) // 5


def cel_pixels(d, loop, cel):
    """(w, h, transparente, filas de colores EGA con la inversion del espejo ya hecha) o None."""
    if loop >= d[2]:
        return None
    lo_ = d[5 + 2 * loop] | (d[6 + 2 * loop] << 8)
    if cel >= d[lo_]:
        return None
    co = lo_ + (d[lo_ + 1 + 2 * cel] | (d[lo_ + 2 + 2 * cel] << 8))
    w, h, tm = d[co], d[co + 1], d[co + 2]
    trans = tm & 15
    p = co + 3
    rows = []
    for _ in range(h):
        row = []
        while d[p]:
            row.extend([d[p] >> 4] * (d[p] & 15))
            p += 1
        p += 1
        row = (row + [trans] * w)[:w]
        if (tm & 0x80) and ((tm >> 4) & 7) != loop:
            row.reverse()
        rows.append(row)
    return w, h, trans, rows


def tile_row(colors):
    """8 colores de Chroma (None = transparente) -> (mascara, dato, color) de la fila."""
    mask = 0
    cnt = {}
    for i, c in enumerate(colors):
        if c is not None:
            mask |= 0x80 >> i
            cnt[c] = cnt.get(c, 0) + 1
    if not cnt:
        return 0, 0, 0
    order = sorted(cnt, key=lambda c: (-cnt[c], c))
    paper = order[0]
    ink = order[1] if len(order) > 1 else paper
    pix = 0
    for i, c in enumerate(colors):
        if c is None:
            continue
        if c == ink:
            use_ink = True
        elif c == paper:
            use_ink = False
        else:
            use_ink = agi2hr.sdist(c, ink) < agi2hr.sdist(c, paper)
        if use_ink:
            pix |= 0x80 >> i
    return mask, pix, (ink << 4) | paper


def cel_tiles(d, loop, cel):
    """(ancho HiRes, alto, [(tx, ty, color[8], dato[8], mascara[8]), ...]) o None si no existe la celda."""
    c = cel_pixels(d, loop, cel)
    if c is None:
        return None
    w, h, trans, rows = c
    hrw = lo(w)
    inv = [0] * hrw
    for a in range(w):
        for x in range(lo(a), lo(a + 1)):
            inv[x] = a
    tiles = []
    for ty in range((h + 7) // 8):
        for tx in range((hrw + 7) // 8):
            col, pix, msk = [], [], []
            for r in range(8):
                y = ty * 8 + r
                colors = []
                for k in range(8):
                    x = tx * 8 + k
                    if y >= h or x >= hrw or rows[y][inv[x]] == trans:
                        colors.append(None)
                    else:
                        colors.append(agi2hr.to_chroma(rows[y][inv[x]]))
                m, p, cl = tile_row(colors)
                msk.append(m)
                pix.append(p)
                col.append(cl)
            if any(msk):
                tiles.append((tx, ty, col, pix, msk))
    return hrw, h, tiles


SW_TILES = 6


def meta(tiles):
    """(software, huella de 16 bits) de los mosaicos de una celda."""
    per = {}
    h = 0x811C
    for tx, ty, col, pix, msk in tiles:
        per[ty] = per.get(ty, 0) + 1
        for b in (tx, ty) + tuple(msk):
            h = ((h ^ b) * 0x0101) & 0xFFFF
    return (1 if per and max(per.values()) > SW_TILES else 0), h


def build_loop(d, loop):
    """Contenido de Nvvvl.SPR para el bucle `loop` de la vista d (sin el u16 del tamano)."""
    ncels = d[d[5 + 2 * loop] | (d[6 + 2 * loop] << 8)]
    recs = []
    for cel in range(ncels):
        hrw, h, tiles = cel_tiles(d, loop, cel)
        sw, hh = meta(tiles)
        r = bytearray((len(tiles), hrw, h, sw, hh & 255, hh >> 8))
        for tx, ty, col, pix, msk in tiles:
            r.extend((tx, ty))
            r.extend(col)
            r.extend(pix)
            r.extend(msk)
        recs.append(bytes(r))
    out = bytearray((ncels,))
    off = 1 + 2 * ncels
    for r in recs:
        out.extend((off & 255, off >> 8))
        off += len(r)
    for r in recs:
        out.extend(r)
    return bytes(out)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = ag.Game(argv[1])
    os.makedirs(argv[2], exist_ok=True)
    sel = [int(a) for a in argv[3:]] or g.present('VIEW')
    n = big = 0
    for v in sel:
        d = g.resource('VIEW', v)
        if not d:
            continue
        try:
            nl = d[2]
            for lp in range(nl):
                data = build_loop(d, lp)
                if len(data) > 8190:
                    big += 1
                    print('VIEW %d bucle %d: %d bytes, no cabe en una pagina' % (v, lp, len(data)))
                    continue
                with open(os.path.join(argv[2], 'N%03d%d.SPR' % (v, lp)), 'wb') as f:
                    f.write(bytes((len(data) & 255, len(data) >> 8)) + data)
                n += 1
        except (IndexError, ValueError) as e:
            print('VIEW %d: error %s' % (v, e))
    print('%s: %d bucles convertidos, %d demasiado grandes' % (os.path.basename(argv[1].rstrip('/\\')), n, big))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
