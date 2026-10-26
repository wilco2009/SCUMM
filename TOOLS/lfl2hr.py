#!/usr/bin/env python3
"""lfl2hr.py: salas de SCUMM v2 -> ROOMnn.GFX para el HiRes 8x1 de 16 colores (sin tiles).

Cada franja de 8x1 pixeles lleva su byte de bitmap y su atributo (papel en el nibble alto, tinta en el bajo, codigos de
Chroma: bit 3 brillo, 2 verde, 1 rojo, 0 azul). Bit del bitmap 1 = tinta, bit 7 = el pixel de la izquierda. No hay limite
de tiles: el unico limite es el de 2 colores por franja. Reutiliza de lfl2gfx.py el decodificador, la paleta y los ajustes por
sala (map, rarity, objcolor, objpng, objhide; protect/keep/pool/tiles/objprio no hacen falta y se ignoran).

Formato (little endian; plan en claude/planning/scumm_hires16.md):
  +0   'HRGF'
  +4   u8 version (1), u8 0
  +6   u16 columnas de la sala (ancho / 8)
  +8   u8 lineas (128), u8 numero de objetos
  +10  u16 donde esta la seccion de objetos (0: no hay)
  +12  4 bytes a 0
  +16  las columnas: por cada una, 128 bytes de bitmap (linea 0..127) y 128 de atributos; 256 bytes por columna
Seccion de objetos: por objeto, en el orden de la sala, 6 bytes: u16 donde estan sus datos (desde el principio del fichero;
FFFF = sin imagen), u8 columna, u8 linea, u8 columnas, u8 lineas. Los datos de un objeto: por columna, `lineas` bytes de bitmap y
`lineas` de atributos (como las columnas de la sala). Los objetos son opacos. Los datos iguales se comparten.

Uso (desde SCUMM/TOOLS):  python lfl2hr.py "../V2/Zak McKracken" all --cfg ../games/zak_rooms.cfg -o ../preview_zak_hr
"""
import argparse
import os
import struct
import sys
from collections import Counter

import lfl2gfx as L
import scumm2

MAGIC = b'HRGF'
HDR = 16
LINES = 128


def cells(img, w, h):
    """img[y][x] -> (bitmap[col][y], atributo[col][y]) y la imagen reconstruida (la que se vera)."""
    cols = w // 8
    bm = [bytearray(h) for _ in range(cols)]
    at = [bytearray(h) for _ in range(cols)]
    render = [[0] * w for _ in range(h)]
    for y in range(h):
        row = img[y]
        for c in range(cols):
            pix = tuple(row[c * 8:c * 8 + 8])
            out, (bits, a, b) = L.row_spec(pix)
            byte = 0
            for k in range(8):                       # row_spec: el bit k (k = 0 el de la izquierda) = el color b
                if (bits >> k) & 1:
                    byte |= 0x80 >> k
            bm[c][y] = byte
            at[c][y] = (a << 4) | b                  # papel = a, tinta = b
            render[y][c * 8:c * 8 + 8] = out
    return bm, at, render


def column_bytes(bm, at):
    return b''.join(bytes(b) + bytes(a) for b, a in zip(bm, at))


def build(w, h, img, objs):
    """objs: lista, en el orden de la sala, de None o (col, linea, columnas, lineas, imagen). Devuelve (bytes, render, renders de objetos)."""
    bm, at, render = cells(img, w, h)
    data = bytearray(MAGIC)
    data += struct.pack('<BBHBBH4x', 1, 0, w // 8, h, len(objs), 0)
    data += column_bytes(bm, at)
    recs, blobs, share, orender = [], bytearray(), {}, []
    secoff = len(data)
    base = secoff + 6 * len(objs)
    for o in objs:
        if o is None:
            recs.append(struct.pack('<HBBBB', 0xFFFF, 0, 0, 0, 0))
            orender.append(None)
            continue
        col, line, nc, nl, im = o
        obm, oat, orr = cells(im, nc * 8, nl)
        blob = column_bytes(obm, oat)
        if blob not in share:
            share[blob] = base + len(blobs)
            blobs += blob
        recs.append(struct.pack('<HBBBB', share[blob], col, line, nc, nl))
        orender.append(orr)
    if objs:
        struct.pack_into('<H', data, 10, secoff)
        data += b''.join(recs) + blobs
    assert len(data) < 65536, 'el fichero no cabe en 64 KB (%d)' % len(data)
    return bytes(data), render, orender


def parse(b):
    assert b[:4] == MAGIC and b[4] == 1
    cols, h, nobj, sec = struct.unpack_from('<HBBH', b, 6)
    return cols, h, nobj, sec


def verify(b, w, h, render, objs, orender):
    """Lee el fichero y reconstruye la sala y los objetos desde los bytes; comparan con lo que se esperaba."""
    cols, hh, nobj, sec = parse(b)
    if cols != w // 8 or hh != h or nobj != len(objs):
        return False

    def decode(off, nc, nl):
        out = [[0] * (nc * 8) for _ in range(nl)]
        for c in range(nc):
            p = off + c * 2 * nl
            for y in range(nl):
                byte, att = b[p + y], b[p + nl + y]
                paper, ink = att >> 4, att & 15
                for k in range(8):
                    out[y][c * 8 + k] = ink if (byte >> (7 - k)) & 1 else paper
        return out
    if decode(HDR, cols, h) != render:
        return False
    for i, o in enumerate(objs):
        off, col, line, nc, nl = struct.unpack_from('<HBBBB', b, sec + 6 * i)
        if o is None:
            if off != 0xFFFF:
                return False
            continue
        if (col, line, nc, nl) != o[:4] or decode(off, nc, nl) != orender[i]:
            return False
    return True


def object_images(room, emap, opt, w, h):
    """Por objeto: None o (columna, linea, columnas, lineas, imagen en codigos de Chroma). Sin imagen o fuera de la sala: None."""
    out = []
    skipped = 0
    for o in room.objects:
        if not o.obim or o.width == 0 or o.height == 0 or o.id in opt.get('objhide', ()):
            out.append(None)
            continue
        if o.width % 8:
            skipped += 1
            out.append(None)
            continue
        try:
            im = L.decode_obim(room.file, o.obim, o.width, o.height)
        except IndexError:
            out.append(None)
            continue
        fix = opt.get('objcolor', {}).get(o.id, {})
        png = opt.get('objpng', {}).get(o.id)
        if png:
            im = L.png_to_chroma(png, o.width, o.height)
        else:
            im = [[fix.get(emap[v], emap[v]) for v in row] for row in im]
        # el objeto se recorta a la sala (la sala son 128 lineas)
        y0, nl = o.y, o.height
        nc = o.width // 8
        if o.x < 0 or o.x % 8 or y0 < 0 or y0 >= h or o.x >= w:
            skipped += 1
            out.append(None)
            continue
        nl = min(nl, h - y0)                         # lo que sobresale por abajo (la interfaz) se recorta
        nc = min(nc, (w - o.x) // 8)
        out.append((o.x // 8, y0, nc, nl, [row[:nc * 8] for row in im[:nl]]))
    return out, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dir')
    ap.add_argument('rooms', nargs='+', help="numeros de sala o 'all'")
    ap.add_argument('--map', default='', help='ajustes EGA->Chroma, p. ej. "6=14"')
    ap.add_argument('--rarity', type=float, default=0.5, help='peso de los colores raros de la sala (0 = ninguno)')
    ap.add_argument('--cfg', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gfx_rooms.cfg'))
    ap.add_argument('--no-objects', action='store_true')
    ap.add_argument('-o', '--outdir', default='preview_hr')
    a = ap.parse_args()
    cfg = L.read_cfg(a.cfg)
    gdir = os.path.join(a.outdir, 'gfx')
    os.makedirs(gdir, exist_ok=True)
    emap0 = L.default_map(L.parse_map(a.map))
    if a.rooms == ['all']:
        rooms = sorted(int(f[:2]) for f in os.listdir(a.dir) if f.upper().endswith('.LFL') and f[:2].isdigit())
    else:
        rooms = [int(r) for r in a.rooms]
    lines = ['| Sala | Ancho | Error | .GFX (bytes) | Objetos | Verif. |', '|---|---|---|---|---|---|']
    for r in rooms:
        b = L.load_lfl(os.path.join(a.dir, '%02d.LFL' % r))
        try:
            w, h, img0 = L.decode_room(b)
        except (IndexError, struct.error):
            continue
        if h != LINES or w % 8 or w > 2000:
            continue
        opt = cfg.get(r, {})
        emap = list(emap0)
        for de, a2 in opt.get('map', {}).items():
            emap[de] = a2
        img = [[emap[p] for p in row] for row in img0]
        rar = opt.get('rarity', a.rarity)
        L.COLW.clear()
        if rar > 0:
            freq = Counter(p for row in img for p in row)
            top = max(freq.values())
            L.COLW.update({c: min(L.RARITY_CAP, (top / n) ** rar) for c, n in freq.items()})
        L._cd.clear(); L._rowd.clear(); L._con.clear()
        try:
            room = scumm2.Room(a.dir, r)
        except Exception:
            room = None
        objs, skipped = ([], 0) if room is None or a.no_objects else object_images(room, emap, opt, w, h)
        gfx, render, orender = build(w, h, img, objs)
        ok = verify(gfx, w, h, render, objs, orender)
        err = sum(render[y][x] != img[y][x] for y in range(h) for x in range(w)) / (w * h)
        with open(os.path.join(gdir, 'ROOM%02d.GFX' % r), 'wb') as f:
            f.write(gfx)
        sep = [[(255, 0, 255)] * w]
        withobj = [list(row) for row in render]
        for o, orr in zip(objs, orender):
            if o:
                col, line, nc, nl, _ = o
                for yy in range(nl):
                    withobj[line + yy][col * 8:col * 8 + nc * 8] = orr[yy]
        bands = ([[L.EGA[p] for p in row] for row in img0] + sep + [[L.CHROMA[p] for p in row] for row in img] + sep
                 + [[L.CHROMA[p] for p in row] for row in render])
        if any(o for o in objs):
            bands += sep + [[L.CHROMA[p] for p in row] for row in withobj]
        L.write_png(os.path.join(a.outdir, 'sala%02d.png' % r), bands)
        lines.append('| %02d | %d | %.1f%% | %d | %d%s | %s |' % (r, w, err * 100, len(gfx), sum(1 for o in objs if o),
                                                                  ' (+%d omitidos)' % skipped if skipped else '', 'OK' if ok else 'FALLA'))
        print(lines[-1], flush=True)
    with open(os.path.join(a.outdir, 'resumen.md'), 'w') as f:
        f.write('HiRes 8x1. Bandas de cada PNG: original EGA | original en Chroma | resultado | resultado con los objetos puestos\n\n')
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    sys.exit(main())
