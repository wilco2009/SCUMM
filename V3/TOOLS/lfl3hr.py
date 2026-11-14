#!/usr/bin/env python3
"""lfl3hr.py: salas de SCUMM v3 (Indy3 EGA) -> ROOMnn.GFX para el HiRes 8x1 de 16 colores.

Es lfl2hr.py (V2/TOOLS) con el lector de v3 (scumm3res.Room) y el formato .GFX version 2, que admite salas de cualquier alto
(Indy3 tiene de 128 a 200 lineas). La conversion a franjas de 8x1 (row_spec), el mapa EGA -> Chroma y los ajustes por sala (map,
objcolor, objpng, objhide, rarity) son los de lfl2hr.py / lfl2gfx.py, importados tal cual. Formato completo: LFL3HR.md.

Uso (desde SCUMM/V3/TOOLS):
  python lfl3hr.py "../Indy Last Crusade" all -o ../preview_hr            # todas las salas
  python lfl3hr.py "../Indy Last Crusade" 1 15 20 28 79 -o ../preview_hr   # solo algunas
  python lfl3hr.py "../Indy Last Crusade" all --png 1,15,20,28,79          # PNG solo de esas (por omision; 'all' = todas)
Salida: gfx/ROOMnn.GFX, salaNN.png y resumen.md en la carpeta -o (ignorada por git: son datos derivados del juego).
"""
import argparse
import os
import struct
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import lfl2gfx as L          # noqa: E402
import lfl2hr as H           # noqa: E402
import scumm3res as R        # noqa: E402

MAGIC = b'HRGF'
VERSION = 2
HDR = 256                    # los datos empiezan en el byte 256
PAGE = 8192                  # una pagina de la RAM extendida: las columnas no la cruzan
MAX_OBJECTS = 84             # HR_OBJREC del motor (hr.asm)
MAX_FILE = 48 * 1024         # 6 paginas fisicas para la sala (la 8-13); las salas mayores piden una septima
DEFAULT_PNG = '1,15,20,28,79'


def cols_per_page(h):
    return PAGE // (2 * h)


def col_offset(k, h):
    """Posicion de la columna k (bitmap y atributos de `h` lineas, 2h bytes) en el fichero: cpp columnas por pagina de 8 KB."""
    cpp = cols_per_page(h)
    return HDR + (k // cpp) * PAGE + (k % cpp) * 2 * h


def build(w, h, img, objs):
    """objs: lista, en el orden de la sala, de None o (col, linea, columnas, lineas, imagen en codigos de Chroma).
    Devuelve (bytes, imagen reconstruida, renders de los objetos)."""
    assert 8 <= h <= 200 and w % 8 == 0
    cols = w // 8
    bm, at, render = H.cells(img, w, h)
    cpp = cols_per_page(h)
    data = bytearray(MAGIC)
    data += struct.pack('<BBHBBHB', VERSION, 0, cols, h, len(objs), 0, cpp)
    data += bytes(HDR - len(data))
    for k in range(cols):
        off = col_offset(k, h)
        data += bytes(off - len(data))              # relleno de fin de pagina
        data += bytes(bm[k]) + bytes(at[k])
    recs, blobs, share, orender = [], bytearray(), {}, []
    secoff = len(data)
    base = secoff + 6 * len(objs)
    for o in objs:
        if o is None:
            recs.append(struct.pack('<HBBBB', 0xFFFF, 0, 0, 0, 0))
            orender.append(None)
            continue
        col, line, nc, nl, im = o
        obm, oat, orr = H.cells(im, nc * 8, nl)
        blob = H.column_bytes(obm, oat)
        if blob not in share:
            share[blob] = base + len(blobs)
            blobs += blob
        recs.append(struct.pack('<HBBBB', share[blob], col, line, nc, nl))
        orender.append(orr)
    if objs:
        struct.pack_into('<H', data, 10, secoff)
        data += b''.join(recs) + blobs
    if len(data) >= 65536:
        raise ValueError('el fichero no cabe en 64 KB (%d): los desplazamientos de los objetos son u16' % len(data))
    return bytes(data), render, orender


def verify(b, w, h, render, objs, orender):
    """Lee el fichero con las reglas del formato y reconstruye la sala y los objetos."""
    assert b[:4] == MAGIC and b[4] == VERSION
    cols, hh, nobj, sec, cpp = struct.unpack_from('<HBBHB', b, 6)
    if cols != w // 8 or hh != h or nobj != len(objs) or cpp != cols_per_page(h):
        return False

    def decode(offs, nl):
        nc = len(offs)
        out = [[0] * (nc * 8) for _ in range(nl)]
        for c, p in enumerate(offs):
            for y in range(nl):
                byte, att = b[p + y], b[p + nl + y]
                paper, ink = att >> 4, att & 15
                for k in range(8):
                    out[y][c * 8 + k] = ink if (byte >> (7 - k)) & 1 else paper
        return out
    if decode([col_offset(k, h) for k in range(cols)], h) != render:
        return False
    for i, o in enumerate(objs):
        off, col, line, nc, nl = struct.unpack_from('<HBBBB', b, sec + 6 * i)
        if o is None:
            if off != 0xFFFF:
                return False
            continue
        if (col, line, nc, nl) != o[:4] or decode([off + c * 2 * nl for c in range(nc)], nl) != orender[i]:
            return False
    return True


def object_images(room, emap, opt, w, h):
    """Por objeto, en el orden de la sala: None o (columna, linea, columnas, lineas, imagen en Chroma). Sin imagen propia (comparten OBIM,
    object_image devuelve None), fuera de la sala o ocultado por el cfg: None. Lo que sobresale por abajo o por la derecha se recorta."""
    out, skipped, masked = [], 0, 0
    for o in room.objects:
        if o.id in opt.get('objhide', ()):
            out.append(None)
            continue
        got = room.object_image(o)
        if got is None:
            out.append(None)
            continue
        im, _, omask, _ = got
        if any(any(r) for r in omask):
            masked += 1
        fix = opt.get('objcolor', {}).get(o.id, {})
        png = opt.get('objpng', {}).get(o.id)
        if png:
            im = L.png_to_chroma(png, o.width, o.height)
        else:
            im = [[fix.get(emap[v], emap[v]) for v in row] for row in im]
        y0 = o.y
        nc = o.width // 8
        if o.x < 0 or o.x % 8 or y0 < 0 or y0 >= h or o.x >= w:
            skipped += 1
            out.append(None)
            continue
        nl = min(o.height, h - y0)
        nc = min(nc, (w - o.x) // 8)
        out.append((o.x // 8, y0, nc, nl, [row[:nc * 8] for row in im[:nl]]))
    return out, skipped, masked


def prepare(room, a_map, cfg_opt, rarity):
    """Imagen de la sala en codigos de Chroma y el mapa usado; deja listos los pesos de color de lfl2gfx."""
    img0 = room.image()[0]
    emap = list(a_map)
    for de, a2 in cfg_opt.get('map', {}).items():
        emap[de] = a2
    img = [[emap[p] for p in row] for row in img0]
    rar = cfg_opt.get('rarity', rarity)
    L.COLW.clear()
    if rar > 0:
        freq = Counter(p for row in img for p in row)
        top = max(freq.values())
        L.COLW.update({c: min(L.RARITY_CAP, (top / n) ** rar) for c, n in freq.items()})
    L._cd.clear(); L._rowd.clear(); L._con.clear()
    return img0, img, emap


def room_png(path, img0, img, render, objs, orender, mask):
    w, h = len(img[0]), len(img)
    sep = [[(255, 0, 255)] * w]
    withobj = [list(row) for row in render]
    for o, orr in zip(objs, orender):
        if o:
            col, line, nc, nl, _ = o
            for yy in range(nl):
                withobj[line + yy][col * 8:col * 8 + nc * 8] = orr[yy]
    bands = ([[L.EGA[p] for p in row] for row in img0] + sep + [[L.CHROMA[p] for p in row] for row in img] + sep
             + [[L.CHROMA[p] for p in row] for row in render])
    if any(objs):
        bands += sep + [[L.CHROMA[p] for p in row] for row in withobj]
    # ultima banda: la mascara de profundidad (lo que tapa al personaje) en rojo sobre el resultado
    mk = []
    for y in range(h):
        row = []
        for x in range(w):
            c = L.CHROMA[render[y][x]]
            if (mask[y][x >> 3] >> (7 - (x & 7))) & 1:
                c = ((c[0] // 3 + 170), c[1] // 3, c[2] // 3)
            row.append(c)
        mk.append(row)
    bands += sep + mk
    L.write_png(path, bands)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dir')
    ap.add_argument('rooms', nargs='+', help="numeros de sala o 'all'")
    ap.add_argument('--map', default='', help='ajustes EGA->Chroma, p. ej. "6=14"')
    ap.add_argument('--rarity', type=float, default=0.5, help='peso de los colores raros de la sala (0 = ninguno)')
    ap.add_argument('--cfg', default=None, help='ajustes por sala (formato de gfx_rooms.cfg); por omision ninguno')
    ap.add_argument('--no-objects', action='store_true')
    ap.add_argument('--png', default=DEFAULT_PNG, help="salas de las que se escribe el PNG: lista, 'all' o 'none' (por omision %s)" % DEFAULT_PNG)
    ap.add_argument('-o', '--outdir', default=os.path.join(HERE, '..', 'preview_hr'))
    a = ap.parse_args()
    cfg = L.read_cfg(a.cfg) if a.cfg else {}
    gdir = os.path.join(a.outdir, 'gfx')
    os.makedirs(gdir, exist_ok=True)
    a_map = L.default_map(L.parse_map(a.map))
    ix = R.Index(a.dir)
    rooms = [r for r in ix.rooms() if r != 0] if a.rooms == ['all'] else [int(r) for r in a.rooms]
    png_all = a.png == 'all'
    png_set = set() if a.png == 'none' or png_all else {int(x) for x in a.png.split(',')}
    lines = ['| Sala | Ancho x alto | Error | .GFX (bytes) | Objetos | Con mascara | Verif. |', '|---|---|---|---|---|---|---|']
    bad = 0
    sizes = []
    for r in rooms:
        try:
            room = R.Room(ix, r)
            w, h = room.width, room.height
            if w % 8 or h > 200:
                raise ValueError('medidas %dx%d' % (w, h))
            img0, img, emap = prepare(room, a_map, cfg.get(r, {}), a.rarity)
            objs, skipped, masked = ([], 0, 0) if a.no_objects else object_images(room, emap, cfg.get(r, {}), w, h)
            if len(objs) > MAX_OBJECTS:
                print('sala %d: %d objetos (el motor admite %d)' % (r, len(objs), MAX_OBJECTS))
            gfx, render, orender = build(w, h, img, objs)
        except Exception as e:                       # una sala que falla no para a las demas
            print('sala %2d: ERROR %s: %s' % (r, type(e).__name__, e))
            lines.append('| %02d | - | - | - | - | - | ERROR %s |' % (r, e))
            bad += 1
            continue
        ok = verify(gfx, w, h, render, objs, orender)
        err = sum(render[y][x] != img[y][x] for y in range(h) for x in range(w)) / (w * h)
        with open(os.path.join(gdir, 'ROOM%02d.GFX' % r), 'wb') as f:
            f.write(gfx)
        if png_all or r in png_set:
            room_png(os.path.join(a.outdir, 'sala%02d.png' % r), img0, img, render, objs, orender, room.image()[2])
        nobj = sum(1 for o in objs if o)
        big = ' (>48 KB)' if len(gfx) > MAX_FILE else ''
        lines.append('| %02d | %dx%d | %.1f%% | %d%s | %d%s | %d | %s |' % (r, w, h, err * 100, len(gfx), big, nobj,
                                                                         ' (+%d omitidos)' % skipped if skipped else '', masked,
                                                                         'OK' if ok else 'FALLA'))
        bad += 0 if ok else 1
        sizes.append((len(gfx), r, w, h))
        print(lines[-1], flush=True)
    sizes.sort()
    with open(os.path.join(a.outdir, 'resumen.md'), 'w') as f:
        f.write('HiRes 8x1, .GFX version 2 (LFL3HR.md). Bandas de cada PNG: original EGA | original en Chroma | resultado | resultado con '
                'los objetos puestos | mascara de profundidad (rojo)\n\n')
        f.write('\n'.join(lines) + '\n')
        if sizes:
            f.write('\n%d salas, .GFX: mediana %d B, maximo %d B (sala %d, %dx%d), total %d B; mas de 48 KB: %s\n' % (
                len(sizes), sizes[len(sizes) // 2][0], sizes[-1][0], sizes[-1][1], sizes[-1][2], sizes[-1][3], sum(s[0] for s in sizes),
                ', '.join('%d' % s[1] for s in sizes if s[0] > MAX_FILE) or 'ninguna'))
    print('%d salas, %d con problemas' % (len(rooms), bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
