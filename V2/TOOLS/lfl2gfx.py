#!/usr/bin/env python3
"""Conversor offline de las salas de SCUMM v2 (.LFL de DOS) a graficos del SD81 Booster (ROOMnn.GFX).

Cada fila de 8 pixeles lleva 2 colores (Chroma modo 0) y cada tile 8x8 es un codigo de caracter; se limita
el numero de tiles distintos por ventana de camara (208 por defecto) fundiendo los que menos error causan,
con ajustes por sala en gfx_rooms.cfg (protect, keep, tiles, rarity). Escribe los .GFX y un PNG de tres bandas
por sala (original EGA | original en colores Chroma | resultado) con estadisticas.

Instrucciones completas: SCUMM/V2/TOOLS/LFL2GFX.md

Uso: lfl2gfx.py DIRECTORIO_LFL SALA... | all [--tiles N] [--view COLS] [--rarity F] [-o carpeta]
"""
import argparse
import os
import struct
import sys
import zlib
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scumm2

EGA = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170),
       (170, 85, 0), (170, 170, 170), (85, 85, 85), (85, 85, 255), (85, 255, 85),
       (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255)]


def chroma_rgb(code):
    """Colores de Chroma 0-15: bit3 brillo, bit2 verde, bit1 rojo, bit0 azul (manual, Apendice H).
    SUPUESTO: el brillo se ve como en EGA (170/0 normal, 255/85 brillante). Comprobar en la placa."""
    br = code >> 3
    return tuple((255 if br else 170) if (code >> bit) & 1 else (85 if br else 0) for bit in (1, 2, 0))


CHROMA = [chroma_rgb(c) for c in range(16)]
PAL = CHROMA          # paleta con la que se procesa y se pinta (indices de Chroma)


def default_map(overrides=None):
    """Indice EGA -> codigo Chroma: el mas cercano en RGB, con ajustes.

    El marron del EGA (6) empata entre rojo (2) y amarillo (6) de Chroma; por defecto va al amarillo
    porque con el rojo se confunde con el rojo del EGA (4) y se pierden detalles (p. ej. el foco del suelo
    de la sala 04). Se cambia con --map 6=2.
    """
    m = []
    for e in EGA:
        m.append(min(range(16), key=lambda c: (sum((x - y) ** 2 for x, y in zip(e, CHROMA[c])), c)))
    m[6] = 6
    for k, v in (overrides or {}).items():
        m[k] = v
    return m


def cdist(a, b):
    return sum((x - y) ** 2 for x, y in zip(PAL[a], PAL[b]))


def load_lfl(path):
    with open(path, 'rb') as f:
        return bytes(x ^ 0xFF for x in f.read())


def decode_room(b):
    """Imagen de fondo v2: columnas de 'alto' pixeles, RLE; bit 7 = copiar la columna anterior."""
    w, h = struct.unpack_from('<HH', b, 4)
    src = struct.unpack_from('<H', b, 0x0A)[0]
    run, color, dither = 1, 0, False
    prev = [0] * 128
    img = [[0] * w for _ in range(h)]
    for x in range(w):
        for y in range(h):
            run -= 1
            if run == 0:
                d = b[src]
                src += 1
                if d & 0x80:
                    run, dither = d & 0x7F, True
                else:
                    run, dither = d >> 4, False
                color = d & 0x0F
                if run == 0:
                    run = b[src]
                    src += 1
            if not dither:
                prev[y] = color
            img[y][x] = prev[y]
    return w, h, img


MASK_MIN = 16           # una celda tapa al personaje si tiene mas de MASK_MIN pixeles de mascara (de 64); --mask-min


def room_mask_cells(b, w, h, raw=None):
    """Mascara de profundidad de la sala (v2): tras los datos de color, bytes de 8 pixeles por tira y fila (RLE: bit 7 = repetir un
    byte). Devuelve una palabra por columna de celdas (bit r = la celda de la fila r tapa al personaje: mas de la mitad de sus pixeles)."""
    src = struct.unpack_from('<H', b, 0x0A)[0]
    run = 1
    for _ in range(w * h):
        run -= 1
        if run == 0:
            d = b[src]
            src += 1
            run = d & 0x7F if d & 0x80 else d >> 4
            if run == 0:
                run = b[src]
                src += 1
    strips = w // 8
    m = [[0] * strips for _ in range(h)]
    sx = y = cnt = 0
    total = strips * h
    while cnt < total:
        r = b[src]
        src += 1
        flag = r & 0x80
        r &= 0x7F
        if flag:
            v = b[src]
            src += 1
        for _ in range(r):
            if not flag:
                v = b[src]
                src += 1
            m[y][sx] = v
            y += 1
            cnt += 1
            if y == h:
                y = 0
                sx += 1
            if cnt >= total:
                break
    cols = []
    for cx in range(strips):
        word = 0
        for cy in range(h // 8):
            if sum(bin(m[cy * 8 + k][cx]).count('1') for k in range(8)) > MASK_MIN:
                word |= 1 << cy
        cols.append(word)
    if raw is not None:
        raw.extend(m)
    return cols


def mask_blob(m):
    """Mascara de profundidad por pixel para el Z80 (va en DATA.BIN, ver pack_data.py): u8 tiras, u16 por tira con el desplazamiento
    de sus tramos desde el principio del bloque (0: la tira esta vacia) y, por tira, tramos (longitud, valor) hacia abajo hasta sumar 128
    filas o hasta la longitud 0. El bit 7 de cada valor es el pixel de la izquierda de la tira; 1 = tapa al personaje."""
    h, strips = len(m), len(m[0])
    if not any(any(r) for r in m):
        return None
    out = bytearray([strips]) + bytearray(2 * strips)
    for sx in range(strips):
        col = [m[y][sx] for y in range(h)]
        if not any(col):
            continue
        struct.pack_into('<H', out, 1 + 2 * sx, len(out))
        i = 0
        while i < h:
            j = i
            while j < h and col[j] == col[i] and j - i < 127:
                j += 1
            out += bytes([j - i, col[i]])
            i = j
        out.append(0)
    return bytes(out)


def cell_pixels(img, cx, cy):
    return [img[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]


def best_two(pix):
    """Dos colores dominantes y mascara de bits (1 = segundo color)."""
    top = [k for k, _ in Counter(pix).most_common(2)]
    if len(top) == 1:
        return top[0], top[0], 0
    a, b = top
    bits = 0
    for i, p in enumerate(pix):
        if cdist(p, b) < cdist(p, a):
            bits |= 1 << i
    return a, b, bits


FULL = (1 << 64) - 1


def pop(v):
    return bin(v).count('1')


def canon(bits):
    """Patron normalizado por inversion: devuelve (patron, invertido?)."""
    inv = bits ^ FULL
    return (inv, True) if inv < bits else (bits, False)


def pick_tiles(counts, n):
    """Elige n patrones: el mas frecuente y luego el que mas error ponderado se lleva."""
    pats = list(counts)
    if len(pats) <= n:
        return pats
    kept = [max(pats, key=lambda p: counts[p])]
    mind = {p: min(pop(p ^ kept[0]), 64 - pop(p ^ kept[0])) for p in pats}
    while len(kept) < n:
        nxt = max(pats, key=lambda p: counts[p] * mind[p])
        if mind[nxt] == 0:
            break
        kept.append(nxt)
        for p in pats:
            d = pop(p ^ nxt)
            d = min(d, 64 - d)
            if d < mind[p]:
                mind[p] = d
    return kept


def nearest(p, kept):
    best, bd, binv = None, 99, False
    for k in kept:
        d = pop(p ^ k)
        if d < bd:
            best, bd, binv = k, d, False
        if 64 - d < bd:
            best, bd, binv = k, 64 - d, True
    return best, binv, bd


def convert(w, h, img, ntiles):
    cols, rows = w // 8, h // 8
    cells = []
    for cy in range(rows):
        for cx in range(cols):
            pix = cell_pixels(img, cx, cy)
            a, b, bits = best_two(pix)
            cells.append((pix, a, b, bits))
    counts = Counter(canon(bits)[0] for _, _, _, bits in cells)
    kept = pick_tiles(counts, ntiles)
    keptset = set(kept)
    cache = {}
    bitmap = [[None] * w for _ in range(h)]
    tiles = [[None] * w for _ in range(h)]
    err_bitmap = err_tiles = 0
    for i, (pix, a, b, bits) in enumerate(cells):
        cx, cy = i % cols, i // cols
        # bitmap ideal
        for j in range(64):
            c = b if (bits >> j) & 1 else a
            bitmap[cy * 8 + j // 8][cx * 8 + j % 8] = PAL[c]
            err_bitmap += pix[j] != c
        # tiles: patron del juego de tiles mas cercano; colores recalculados para ese patron
        cb, inv = canon(bits)
        if cb in keptset:
            t, tinv = cb, inv
        else:
            if cb not in cache:
                cache[cb] = nearest(cb, kept)[:2]
            t, rel = cache[cb]
            tinv = inv ^ rel
        tb = t ^ FULL if tinv else t
        s0 = Counter(pix[j] for j in range(64) if not (tb >> j) & 1)
        s1 = Counter(pix[j] for j in range(64) if (tb >> j) & 1)
        c0 = s0.most_common(1)[0][0] if s0 else (s1.most_common(1)[0][0])
        c1 = s1.most_common(1)[0][0] if s1 else c0
        for j in range(64):
            c = c1 if (tb >> j) & 1 else c0
            tiles[cy * 8 + j // 8][cx * 8 + j % 8] = PAL[c]
            err_tiles += pix[j] != c
    total = w * h
    return bitmap, tiles, len(counts), len(kept), err_bitmap / total, err_tiles / total


# ---- Chroma modo 0: color por codigo de caracter y por scanline (8 bytes de color por tile) ----

_rowd = {}


def row_spec(row):
    """Mejor par (a<=b) de colores para 8 pixeles; bit=1 -> b. Devuelve (render, spec)."""
    present = sorted(set(row))
    if len(present) == 1:
        c = present[0]
        return (c,) * 8, (0, c, c)
    best = None
    for i, a in enumerate(present):
        for b in present[i:]:
            err = 0
            bits = 0
            for k, p in enumerate(row):
                wp = COLW.get(p, 1.0)                  # un color raro de la sala pesa mas: se prefiere conservarlo
                if cdist(p, b) < cdist(p, a):
                    err += cdist(p, b) * wp
                    bits |= 1 << k
                else:
                    err += cdist(p, a) * wp
            if best is None or err < best[0]:
                best = (err, bits, a, b)
    _, bits, a, b = best
    return tuple(b if (bits >> k) & 1 else a for k in range(8)), (bits, a, b)


METRIC = 'count'        # 'count': pixeles distintos; 'color': distancia de color entre los pixeles
POWER = 1.0             # el coste de fundir un tile es  apariciones ** POWER * distancia
_cd = {}
SAL = 0.0               # proteccion de los tiles de mucho contraste (rotulos, personajes): el coste se multiplica por 1 + SAL * contraste
_con = {}
RARITY = 0.0            # peso de los colores raros de la sala (el blanco de un esqueleto, el color de un rotulo): (maxima frecuencia / frecuencia) ** RARITY
RARITY_CAP = 8.0
COLW = {}
LLOYD = 3
PROTECT = []            # rectangulos (x0, y0, x1, y1) en pixeles de la sala cuyos tiles casi no se funden (rotulos, personajes)
PROTECT_MULT = 100.0
KEEP = []               # (color de Chroma, rectangulo o None): ese color no se pierde en las filas de los tiles de la zona
KEEP_WEIGHT = 1e6
CENTROID = False        # tras fundir, cada tile final pasa a ser el representante (por filas) de todos los que se han fundido en el


def pix_dist(x, y):
    """Distancia perceptual entre dos colores de la paleta (euclidea en RGB, 0..1)."""
    k = (x, y)
    d = _cd.get(k)
    if d is None:
        d = _cd[k] = 0.0 if x == y else (cdist(x, y) ** 0.5) / 441.7 * max(COLW.get(x, 1.0), COLW.get(y, 1.0))
    return d


def contrast(t):
    """Mayor distancia de color entre dos pixeles del tile (0..1)."""
    c = _con.get(t)
    if c is None:
        cols = {x for row in t for x in row}
        c = _con[t] = max([pix_dist(x, y) for x in cols for y in cols] or [0.0])
    return c


def row_dist(r1, r2):
    k = (r1, r2)
    d = _rowd.get(k)
    if d is None:
        if METRIC == 'color':
            d = _rowd[k] = sum(pix_dist(x, y) for x, y in zip(r1, r2))
        else:
            d = _rowd[k] = sum(x != y for x, y in zip(r1, r2))
    return d


def tile_dist(t1, t2):
    return sum(row_dist(a, b) for a, b in zip(t1, t2))


def convert_rows(w, h, img, ntiles):
    """Modo 0 de Chroma: tile = 8 filas renderizadas (cada una con 2 colores). Sin limite y con limite."""
    cols, rows = w // 8, h // 8
    keys = []
    for cy in range(rows):
        for cx in range(cols):
            keys.append(tuple(row_spec([img[cy * 8 + y][cx * 8 + x] for x in range(8)])[0]
                              for y in range(8)))
    counts = Counter(keys)
    pats = list(counts)
    kept = pats
    if len(pats) > ntiles:
        kept = [max(pats, key=lambda p: counts[p])]
        mind = {p: tile_dist(p, kept[0]) for p in pats}
        while len(kept) < ntiles:
            nxt = max(pats, key=lambda p: counts[p] * mind[p])
            if mind[nxt] == 0:
                break
            kept.append(nxt)
            for p in pats:
                d = tile_dist(p, nxt)
                if d < mind[p]:
                    mind[p] = d
    keptset = set(kept)
    cache = {}
    full = [[None] * w for _ in range(h)]
    lim = [[None] * w for _ in range(h)]
    err_full = err_lim = 0
    for i, key in enumerate(keys):
        cx, cy = i % cols, i // cols
        if key in keptset:
            t = key
        else:
            if key not in cache:
                cache[key] = min(kept, key=lambda k: tile_dist(key, k))
            t = cache[key]
        for y in range(8):
            for x in range(8):
                full[cy * 8 + y][cx * 8 + x] = PAL[key[y][x]]
                lim[cy * 8 + y][cx * 8 + x] = PAL[t[y][x]]
                err_full += key[y][x] != img[cy * 8 + y][cx * 8 + x]
                err_lim += t[y][x] != img[cy * 8 + y][cx * 8 + x]
    total = w * h
    return full, lim, len(counts), len(kept), err_full / total, err_lim / total


def write_png(path, rows):
    h, w = len(rows), len(rows[0])
    raw = b''.join(b'\0' + bytes(c for p in r for c in p) for r in rows)

    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d))
    data = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    import time
    for _ in range(10):                   # en Windows el visor de imagenes o el antivirus a veces bloquean el fichero un instante
        try:
            with open(path, 'wb') as f:
                f.write(data)
            return
        except OSError:
            time.sleep(0.5)
    print('no se puede escribir', path)


def room_tiles(w, h, img):
    """Rejilla [columna][fila] de tiles del modo 0 (8 filas renderizadas, 2 colores por fila)."""
    grid = []
    for cx in range(w // 8):
        col = []
        for cy in range(h // 8):
            sacred = [c for c, r in KEEP if r is None or (r[0] < cx * 8 + 8 and cx * 8 <= r[2] and r[1] < cy * 8 + 8 and cy * 8 <= r[3])]
            saved = {c: COLW.get(c) for c in sacred}
            for c in sacred:
                COLW[c] = KEEP_WEIGHT                   # en esta celda ese color siempre es uno de los dos de cada fila
            col.append(tuple(row_spec([img[cy * 8 + y][cx * 8 + x] for x in range(8)])[0] for y in range(8)))
            for c, v in saved.items():
                if v is None:
                    COLW.pop(c, None)
                else:
                    COLW[c] = v
        grid.append(col)
    return grid


def window_sets(grid, view):
    """Para cada posicion de camara (en columnas) el conjunto de tiles visibles."""
    cols = len(grid)
    out = []
    cnt = Counter()
    for s in range(max(1, cols - view + 1)):
        if s == 0:
            for c in grid[:view]:
                cnt.update(c)
        else:
            cnt.subtract(grid[s - 1])
            cnt.update(grid[s + view - 1])
        out.append({t for t, n in cnt.items() if n > 0})
    return out


def refine_centroids(grid, cur):
    """Sustituye cada tile final por el representante de los tiles originales que han acabado en el:
    para cada fila, el par de colores y el reparto que menos error ponderado dan (peso = apariciones y rareza)."""
    members = {}
    for gc, cc in zip(grid, cur):
        for t0, t1 in zip(gc, cc):
            members.setdefault(t1, Counter())[t0] += 1
    new = {}
    for t1, mem in members.items():
        if len(mem) == 1:
            new[t1] = t1
            continue
        rows = []
        for y in range(8):
            pix = [Counter() for _ in range(8)]       # por columna: color -> peso
            for t0, n in mem.items():
                for x in range(8):
                    c = t0[y][x]
                    pix[x][c] += n * COLW.get(c, 1.0)
            present = sorted({c for pc in pix for c in pc})
            best = None
            for i, a in enumerate(present):
                for b in present[i:]:
                    err, out = 0.0, []
                    for x in range(8):
                        ea = sum(wt * pix_dist(c, a) for c, wt in pix[x].items())
                        eb = sum(wt * pix_dist(c, b) for c, wt in pix[x].items())
                        if eb < ea:
                            err += eb
                            out.append(b)
                        else:
                            err += ea
                            out.append(a)
                    if best is None or err < best[0]:
                        best = (err, tuple(out))
            rows.append(best[1])
        new[t1] = tuple(rows)
    return [[new[t] for t in c] for c in cur]


def convert_windowed(w, h, img, budget, view):
    """Modo 0 de Chroma con presupuesto por ventana de camara.

    Cada celda de la sala tiene un tile fijo (mapa de la sala). Mientras alguna posicion de camara
    (ventana de `view` columnas) use mas de `budget` tiles distintos, se funden en toda la sala los
    tiles de la peor ventana que menos error ponderado causan. Devuelve (render, tiles_sala,
    max_ventana, error).
    """
    alias = {}
    if RARITY > 0:
        freq = Counter(p for row in img for p in row)
        top = max(freq.values())
        COLW.clear()
        COLW.update({c: min(RARITY_CAP, (top / n) ** RARITY) for c, n in freq.items()})
    else:
        COLW.clear()
    _cd.clear(); _rowd.clear(); _con.clear()
    grid = room_tiles(w, h, img)                    # los pares de colores de cada fila ya usan los pesos
    prot = set()
    for (x0, y0, x1, y1) in PROTECT:
        for cx in range(max(0, x0 // 8), min(len(grid), x1 // 8 + 1)):
            for cy in range(max(0, y0 // 8), min(len(grid[0]), y1 // 8 + 1)):
                prot.add(grid[cx][cy])

    def res(t):
        while t in alias:
            t = alias[t]
        return t
    for _ in range(200):
        cur = [[res(t) for t in c] for c in grid]
        sets = window_sets(cur, view)
        worst = max(sets, key=len)
        if len(worst) <= budget:
            break
        counts = Counter(t for c in cur for t in c)
        cand = []
        wl = list(worst)
        for a in wl:
            bd, bb = None, None
            for b in wl:
                if b is a:
                    continue
                d = tile_dist(a, b)
                if bd is None or d < bd:
                    bd, bb = d, b
            cand.append((counts[a] ** POWER * bd * (1 + SAL * contrast(a)) * (PROTECT_MULT if a in prot else 1.0), a, bb))
        cand.sort(key=lambda x: x[0])
        excess = len(worst) - budget
        removed, targets = set(), set()
        for _, a, b in cand:
            if len(removed) >= excess:
                break
            if a in targets or b in removed:
                continue
            alias[a] = b
            removed.add(a)
            targets.add(b)
    cur = [[res(t) for t in c] for c in grid]
    if CENTROID:
        cur = refine_centroids(grid, cur)
        for _ in range(LLOYD):                          # k-medias: reasignar cada tile original al representante mas cercano
            finals = list({t for c in cur for t in c})
            near = {}
            for gc in grid:
                for t0 in gc:
                    if t0 not in near:
                        near[t0] = min(finals, key=lambda f: tile_dist(t0, f))
            nxt = [[near[t0] for t0 in gc] for gc in grid]
            if max(len(x) for x in window_sets(nxt, view)) > budget:
                break
            nxt = refine_centroids(grid, nxt)
            if max(len(x) for x in window_sets(nxt, view)) > budget:
                break
            cur = nxt
    sets = window_sets(cur, view)
    render = [[None] * w for _ in range(h)]
    err = 0
    for cx, col in enumerate(cur):
        for cy, t in enumerate(col):
            for y in range(8):
                for x in range(8):
                    render[cy * 8 + y][cx * 8 + x] = PAL[t[y][x]]
                    err += t[y][x] != img[cy * 8 + y][cx * 8 + x]
    return render, cur, len({t for c in cur for t in c}), max(len(s) for s in sets), err / (w * h)


# ---- Slots (codigos de caracter), cargas de tiles y fichero .GFX ----------------------------------

class Inst:
    """Un tile mientras es visible: mismo codigo de caracter en todas sus celdas."""
    __slots__ = ('tile', 'first', 'last', 'start', 'end', 'slot')

    def __init__(self, tile, first, last, start, end):
        self.tile, self.first, self.last, self.start, self.end, self.slot = tile, first, last, start, end, None


def build_instances(cur, view):
    """Agrupa las columnas de cada tile en instancias (huecos <= view-1 columnas = visibles a la vez).

    start/end son posiciones de camara (columna izquierda de la ventana) entre las que la instancia
    esta visible. Devuelve (instancias ordenadas por (start,end), npos).
    """
    cols = len(cur)
    npos = max(1, cols - view + 1)
    occ = {}
    for cx, col in enumerate(cur):
        for t in set(col):
            occ.setdefault(t, []).append(cx)
    insts = []
    for t, cl in occ.items():
        grp = [cl[0]]
        for c in cl[1:] + [None]:
            if c is not None and c - grp[-1] <= view - 1:
                grp.append(c)
                continue
            insts.append(Inst(t, grp[0], grp[-1], max(0, grp[0] - view + 1), min(npos - 1, grp[-1])))
            grp = [c]
    insts.sort(key=lambda i: (i.start, i.end))
    return insts, npos


def assign_slots(insts):
    """Coloreado voraz de intervalos: usa exactamente tantos slots como instancias vivas a la vez."""
    import heapq
    active, free, nslots = [], [], 0
    for i in insts:
        while active and active[0][0] < i.start:
            heapq.heappush(free, heapq.heappop(active)[1])
        if free:
            i.slot = heapq.heappop(free)
        else:
            i.slot = nslots
            nslots += 1
        heapq.heappush(active, (i.end, i.slot))
    return nslots


def tile_bytes(t):
    """8 bytes de forma y 8 de color (papel en el nibble alto, tinta en el bajo; bit 1 = tinta)."""
    shape, color = bytearray(), bytearray()
    for row in t:
        cs = sorted(set(row))
        a, b = cs[0], cs[-1]
        shape.append(sum(1 << (7 - k) for k, p in enumerate(row) if p == b and a != b))
        color.append((a << 4) | b)
    return bytes(shape), bytes(color)


PROTECT_POOL = 12       # reserva de objetos de las salas con protect o keep (el resto de tiles es para el fondo)
# Cambios de color de objetos concretos (para que no se pierdan por falta de contraste en la placa, p. ej. el Chroma 8 se ve negro). Nunca se hace nada
# por norma general: solo lo que se indique en gfx_rooms.cfg con 'objcolor=ID,de,a' (codigos de Chroma 0-15; se puede repetir para varios colores).
OBJ_COLOR = {}              # id de objeto -> {Chroma de: Chroma a}
OBJ_HIDE = set()            # objetos cuya imagen no se dibuja (cfg: 'objhide=ID'): p. ej. la imagen retocada de otro objeto ya los incluye
OBJ_PNG = {}                # id de objeto -> codigos de Chroma de una imagen retocada a mano (cfg: 'objpng=ID,fichero.png')


def read_png(path):
    """Lector minimo de PNG (8 bits, sin entrelazado; RGB, RGBA, paleta o gris): devuelve [fila][columna] de tuplas RGB."""
    import zlib
    b = open(path, 'rb').read()
    assert b[:8] == b'\x89PNG\r\n\x1a\n', 'no es un PNG: ' + path
    p, idat, pal = 8, b'', None
    while p < len(b):
        n = struct.unpack('>I', b[p:p + 4])[0]
        t = b[p + 4:p + 8]
        d = b[p + 8:p + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', d)
            assert depth == 8 and inter == 0, 'solo PNG de 8 bits sin entrelazado'
        elif t == b'PLTE':
            pal = [tuple(d[i:i + 3]) for i in range(0, len(d), 3)]
        elif t == b'IDAT':
            idat += d
        p += 12 + n
    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    q = 0
    for _ in range(h):
        f = raw[q]
        cur = bytearray(raw[q + 1:q + 1 + stride])
        q += 1 + stride
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            c = prev[i - bpp] if i >= bpp else 0
            up = prev[i]
            if f == 1:
                cur[i] = (cur[i] + a) & 255
            elif f == 2:
                cur[i] = (cur[i] + up) & 255
            elif f == 3:
                cur[i] = (cur[i] + (a + up) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(up - c), abs(a - c), abs(a + up - 2 * c)
                cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else up if pb <= pc else c)) & 255
        rows.append(cur)
        prev = cur
    out = []
    for cur in rows:
        row = []
        for x in range(w):
            px = cur[x * bpp:(x + 1) * bpp]
            if ctype == 3:
                row.append(pal[px[0]])
            elif ctype in (0, 4):
                row.append((px[0],) * 3)
            else:
                row.append(tuple(px[:3]))
        out.append(row)
    return out


def png_to_chroma(path, w, h):
    """Imagen retocada -> codigos de Chroma (el color mas cercano de la paleta de Chroma a cada pixel)."""
    im = read_png(path)
    assert len(im) == h and len(im[0]) == w, '%s mide %dx%d y el objeto %dx%d' % (path, len(im[0]), len(im), w, h)
    return [[min(range(16), key=lambda c: (sum((x - y) ** 2 for x, y in zip(px, CHROMA[c])), c)) for px in row] for row in im]
POOL_MAX = 64           # tiles de la reserva de objetos (los codigos de arriba de los slots): imagenes de objetos de la sala
SLOT_TOP = 208          # los codigos 208-209 son las flechas del inventario y 210-255 la fuente


def decode_obim(b, src, w, h):
    """Imagen de un objeto de v2: el mismo RLE por columnas que el fondo, desde el principio de su bloque OBIM."""
    run, color, dither = 1, 0, False
    prev = [0] * h
    img = [[0] * w for _ in range(h)]
    for x in range(w):
        for y in range(h):
            run -= 1
            if run == 0:
                d = b[src]
                src += 1
                if d & 0x80:
                    run, dither = d & 0x7F, True
                else:
                    run, dither = d >> 4, False
                color = d & 0x0F
                if run == 0:
                    run = b[src]
                    src += 1
            if not dither:
                prev[y] = color
            img[y][x] = prev[y]
    return img


def object_grids(room, emap):
    """Por cada objeto de la sala, en orden: None (sin imagen) o la rejilla [columna][fila] de sus tiles."""
    out = []
    keep, KEEP[:] = list(KEEP), []
    try:
        for o in room.objects:
            if not o.obim or o.width == 0 or o.height == 0 or o.width % 8 or o.height % 8:
                out.append(None)
                continue
            try:
                im = decode_obim(room.file, o.obim, o.width, o.height)
            except IndexError:
                out.append(None)
                continue
            if o.id in OBJ_HIDE:
                out.append(None)
                continue
            if o.id in OBJ_PNG:
                out.append(room_tiles(o.width, o.height, png_to_chroma(OBJ_PNG[o.id], o.width, o.height)))
                continue
            fix = OBJ_COLOR.get(o.id, {})
            out.append(room_tiles(o.width, o.height, [[fix.get(emap[v], emap[v]) for v in row] for row in im]))
    finally:
        KEEP[:] = keep
    return out


def plan_pool(room, emap, want):
    """Tiles de la reserva de objetos de una sala: los que pide `want` o, si hay menos tiles distintos, esos."""
    if room is None or not room.objects or want <= 0:
        return 0
    COLW.clear()
    _cd.clear(); _rowd.clear(); _con.clear()
    pre = object_grids(room, emap)
    return min(want, len({t for g in pre if g for col in g for t in col}))


def limit_pool(grids, pool, weights=None):
    """Reduce los tiles de todos los objetos a `pool` como mucho (el mas frecuente y luego el que mas error ponderado
    se llevaria) y devuelve (lista de tiles de la reserva, rejillas con el indice del tile de la reserva)."""
    counts = Counter()
    for k, g in enumerate(grids):
        for col in (g or []):
            for t in col:
                counts[t] += weights[k] if weights else 1
    pats = list(counts)
    if len(pats) > pool:
        kept = [max(pats, key=lambda p: counts[p])]
        mind = {p: tile_dist(p, kept[0]) for p in pats}
        while len(kept) < pool:
            nxt = max(pats, key=lambda p: counts[p] ** POWER * mind[p])
            if mind[nxt] == 0:
                break
            kept.append(nxt)
            for p in pats:
                d = tile_dist(p, nxt)
                if d < mind[p]:
                    mind[p] = d
    else:
        kept = pats
    index = {t: i for i, t in enumerate(kept)}
    cache = {}
    out = []
    for g in grids:
        if g is None:
            out.append(None)
            continue
        cols = []
        for col in g:
            cc = []
            for t in col:
                if t not in index:
                    if t not in cache:
                        cache[t] = min(range(len(kept)), key=lambda i: tile_dist(t, kept[i]))
                    cc.append(cache[t])
                else:
                    cc.append(index[t])
            cols.append(cc)
        out.append(cols)
    return kept, out


def build_gfx(cur, view, code_base=0, layer=None, mask=None):
    """Devuelve (bytes del .GFX, nslots, ninst). Formato en claude/planning/scumm_plan.md."""
    rows = len(cur[0])
    cols = len(cur)
    insts, npos = build_instances(cur, view)
    nslots = assign_slots(insts)
    by_tile = {}
    for i in insts:
        by_tile.setdefault(i.tile, []).append(i)
    cellmap = bytearray(cols * rows)
    for cx in range(cols):
        for cy in range(rows):
            for i in by_tile[cur[cx][cy]]:
                if i.first <= cx <= i.last:
                    cellmap[cy * cols + cx] = code_base + i.slot
                    break
    n = len(insts)
    rstart = [0] * (npos + 1)
    for i in insts:
        rstart[i.start + 1] += 1
    for s in range(npos):
        rstart[s + 1] += rstart[s]
    order = sorted(range(n), key=lambda k: (insts[k].end, k))
    lstart = [0] * (npos + 1)
    for i in insts:
        lstart[i.end + 1] += 1
    for s in range(npos):
        lstart[s + 1] += lstart[s]
    has_mask = bool(layer and mask and any(mask))
    out = bytearray(b'SGFX')
    out += struct.pack('<BBHBBHHH', (3 if has_mask else 2) if layer else 1, nslots, cols, rows, view, npos, n, code_base)
    out += cellmap
    out += b''.join(struct.pack('<H', v) for v in rstart)
    for i in insts:
        sh, co = tile_bytes(i.tile)
        if code_base + i.slot >= 128:          # el bit 7 del codigo invierte el video: se guarda la forma al reves
            sh = bytes(v ^ 0xFF for v in sh)
        out += bytes([code_base + i.slot]) + sh + co
    out += b''.join(struct.pack('<H', v) for v in lstart)
    out += b''.join(struct.pack('<H', k) for k in order)
    if layer:
        sec = object_section(len(out), layer)
        if has_mask:                           # version 3: tras la seccion de objetos, una palabra por columna de celdas y, al final, el puntero
            sec = sec[:-2] + b''.join(struct.pack('<H', v) for v in mask) + sec[-2:]
        out += sec
    return bytes(out), nslots, n


def object_section(start, layer):
    """Seccion de objetos (version 2): al final del fichero; los dos ultimos bytes dicen donde empieza.

        u8 P (tiles de la reserva), u8 codigo del primero, u8 numero de objetos, u8 0
        P x 16: forma y color de cada tile (los codigos >= 128 con la forma al reves)
        u16 por objeto: donde estan sus celdas desde el principio de la seccion (FFFF: no tiene imagen)
        las celdas de cada objeto: su ancho x su alto codigos de caracter, por filas
    """
    tiles, grids = layer
    P = len(tiles)
    base = SLOT_TOP - P
    sec = bytearray([P, base, len(grids), 0])
    for i, t in enumerate(tiles):
        sh, co = tile_bytes(t)
        if base + i >= 128:
            sh = bytes(v ^ 0xFF for v in sh)
        sec += sh + co
    offs_at = len(sec)
    sec += bytes(2 * len(grids))
    for k, g in enumerate(grids):
        if g is None:
            struct.pack_into('<H', sec, offs_at + 2 * k, 0xFFFF)
            continue
        struct.pack_into('<H', sec, offs_at + 2 * k, len(sec))
        for r in range(len(g[0])):
            for cc in range(len(g)):
                sec.append(base + g[cc][r])
    return bytes(sec) + struct.pack('<H', start)


def parse_gfx(b):
    assert b[:4] == b'SGFX'
    ver, nslots, cols, rows, view, npos, n, base = struct.unpack_from('<BBHBBHHH', b, 4)
    p = 16
    cellmap = b[p:p + cols * rows]
    p += cols * rows
    rstart = struct.unpack_from('<%dH' % (npos + 1), b, p)
    p += 2 * (npos + 1)
    insts = [b[p + 17 * k:p + 17 * k + 17] for k in range(n)]
    p += 17 * n
    lstart = struct.unpack_from('<%dH' % (npos + 1), b, p)
    p += 2 * (npos + 1)
    llist = struct.unpack_from('<%dH' % n, b, p)
    return dict(nslots=nslots, cols=cols, rows=rows, view=view, npos=npos, n=n, base=base,
                cellmap=cellmap, rstart=rstart, insts=insts, lstart=lstart, llist=llist, ver=ver,
                objstart=struct.unpack_from('<H', b, len(b) - 2)[0] if ver >= 2 else None)


def verify_objects(b, grids_expected, pool_tiles):
    """Comprueba la seccion de objetos: cada celda lleva el codigo de un tile de la reserva con la forma y el color que toca."""
    g = parse_gfx(b)
    st = g['objstart']
    P, base, nobj = b[st], b[st + 1], b[st + 2]
    if P != len(pool_tiles) or nobj != len(grids_expected):
        return False
    tiles = []
    for i in range(P):
        sh = bytes(b[st + 4 + 16 * i:st + 12 + 16 * i])
        if base + i >= 128:
            sh = bytes(v ^ 0xFF for v in sh)
        tiles.append((sh, bytes(b[st + 12 + 16 * i:st + 20 + 16 * i])))
    ok = True
    offs_at = st + 4 + 16 * P
    for k, ge in enumerate(grids_expected):
        off = struct.unpack_from('<H', b, offs_at + 2 * k)[0]
        if ge is None:
            ok &= off == 0xFFFF
            continue
        cols, rows = len(ge), len(ge[0])
        p = st + off
        for r in range(rows):
            for cc in range(cols):
                code = b[p]
                p += 1
                ok &= base <= code < base + P and tiles[code - base] == tile_bytes(pool_tiles[ge[cc][r]])
    return ok


def verify_gfx(b, cur):
    """Simula el Z80: camina a la derecha desde 0, a la izquierda desde la ultima posicion y da saltos
    (paso a paso); en cada posicion comprueba que cada celda visible tiene en su slot los bytes de su tile."""
    import random
    g = parse_gfx(b)
    cols, rows, view, npos = g['cols'], g['rows'], g['view'], g['npos']
    mem = {}                       # codigo de caracter -> (forma, color)

    def load(k):
        e = g['insts'][k]
        sh = bytes(v ^ 0xFF for v in e[1:9]) if e[0] >= 128 else bytes(e[1:9])
        mem[e[0]] = (sh, bytes(e[9:17]))

    def check(s):
        for cx in range(s, s + view):
            for cy in range(rows):
                if mem.get(g['cellmap'][cy * cols + cx]) != tile_bytes(cur[cx][cy]):
                    return False
        return True

    def to_right(s):               # de s-1 a s
        for k in range(g['rstart'][s], g['rstart'][s + 1]):
            load(k)

    def to_left(s):                # de s+1 a s
        for j in range(g['lstart'][s], g['lstart'][s + 1]):
            load(g['llist'][j])
    ok = True
    for s in range(npos):
        to_right(s)
        ok &= check(s)
    mem.clear()
    for s in range(npos - 1, -1, -1):
        to_left(s)
        ok &= check(s)
    rnd = random.Random(1)
    mem.clear()
    cam = 0
    to_right(0)
    for _ in range(60):
        dst = rnd.randrange(npos)
        while cam < dst:
            cam += 1
            to_right(cam)
        while cam > dst:
            cam -= 1
            to_left(cam)
        ok &= check(cam)
    return ok


def parse_map(text):
    m = {}
    for part in (text or '').split(','):
        if part.strip():
            k, v = part.split('=')
            m[int(k)] = int(v)
    return m


def read_cfg(path):
    path_cfg = path
    """Ajustes por sala: lineas 'sala: protect=x0,y0,x1,y1 protect=... tiles=N rarity=F' (# comenta)."""
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path, encoding='utf-8'):
        line = line.split('#')[0].strip()
        if not line or ':' not in line:
            continue
        room, rest = line.split(':', 1)
        o = out.setdefault(int(room), {})
        for tok in rest.split():
            k, v = tok.split('=', 1)
            if k == 'protect':
                o.setdefault('protect', []).append(tuple(int(q) for q in v.split(',')))
            elif k == 'keep':
                q = [int(t) for t in v.split(',')]
                o.setdefault('keep', []).append((q[0], tuple(q[1:5]) if len(q) == 5 else None))
            elif k == 'tiles':
                o['tiles'] = int(v)
            elif k == 'objpng':
                oid, path = v.split(',', 1)
                o.setdefault('objpng', {})[int(oid)] = path if os.path.isabs(path) else os.path.join(os.path.dirname(os.path.abspath(path_cfg)), path)
            elif k == 'objhide':
                o.setdefault('objhide', set()).add(int(v))
            elif k == 'objcolor':
                oid, de, a = (int(t) for t in v.split(','))
                o.setdefault('objcolor', {}).setdefault(oid, {})[de] = a
            elif k == 'pool':
                o['pool'] = int(v)
            elif k == 'objprio':              # objprio=ID: los tiles de ese objeto pesan mucho al repartir la reserva (se funden los ultimos)
                o.setdefault('objprio', set()).add(int(v))
            elif k == 'map':                  # map=EGA,Chroma: cambia la correspondencia de un color en esa sala
                de, a2 = (int(t) for t in v.split(','))
                o.setdefault('map', {})[de] = a2
            elif k == 'rarity':
                o['rarity'] = float(v)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dir', help='carpeta con los NN.LFL')
    ap.add_argument('rooms', nargs='+', help="numeros de sala o 'all'")
    ap.add_argument('--tiles', type=int, default=208, help='maximo de tiles distintos por ventana de camara')
    ap.add_argument('--view', type=int, default=33, help='columnas de la ventana de camara (33 = 32 visibles + la que asoma con el scroll fino; 40 = original)')
    ap.add_argument('--map', default='', help='ajustes EGA->Chroma, p. ej. "6=14,8=0" (EGA 6 = marron)')
    ap.add_argument('--code-base', type=int, default=0, help='primer codigo de caracter de los slots')
    ap.add_argument('--metric', choices=('count', 'color'), default='color', help='como se mide el error al fundir tiles')
    ap.add_argument('--power', type=float, default=0.5, help='exponente de las apariciones del tile en el coste de fundirlo (0 = no cuentan)')
    ap.add_argument('--rarity', type=float, default=0.5, help='peso de los colores raros de la sala (0 = ninguno, 0.5 razonable)')
    ap.add_argument('--centroid', action='store_true', help='tras fundir, cada tile pasa a ser el representante de su grupo')
    ap.add_argument('--protect', default='', help="rectangulos de pixeles 'x0,y0,x1,y1;x0,y0,x1,y1' cuyos tiles se protegen (solo con UNA sala)")
    ap.add_argument('--sal', type=float, default=0.0, help='proteccion de los tiles de mucho contraste')
    ap.add_argument('--pool', type=int, default=POOL_MAX, help='tiles de la reserva de objetos (0 = sin objetos)')
    ap.add_argument('--dump-objects', default='', metavar='DIR', help='escribe en DIR un PNG por objeto de cada sala (colores de Chroma, 1:1) para retocarlo y devolverlo con objpng=ID,fichero.png')
    ap.add_argument('--mask-min', type=int, default=16, help='pixeles de mascara (de 64) a partir de los que una celda tapa al personaje')
    ap.add_argument('--no-objects', action='store_true', help='no incluir las imagenes de los objetos')
    ap.add_argument('--cfg', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gfx_rooms.cfg'),
                    help='ajustes por sala (protect, tiles, rarity); ver el propio fichero')
    ap.add_argument('-o', '--outdir', default='preview')
    a = ap.parse_args()
    global METRIC, POWER, SAL, RARITY, CENTROID, PROTECT, KEEP, OBJ_COLOR, OBJ_PNG, OBJ_HIDE
    METRIC, POWER, SAL, RARITY, CENTROID = a.metric, a.power, a.sal, a.rarity, a.centroid
    PROTECT = [tuple(int(v) for v in r.split(',')) for r in a.protect.split(';') if r.strip()]
    cfg = read_cfg(a.cfg)

    os.makedirs(a.outdir, exist_ok=True)
    gdir = os.path.join(a.outdir, 'gfx')
    os.makedirs(gdir, exist_ok=True)
    emap0 = default_map(parse_map(a.map))
    if a.rooms == ['all']:
        rooms = sorted(int(f[:2]) for f in os.listdir(a.dir) if f.upper().endswith('.LFL') and f[:2].isdigit())
    else:
        rooms = [int(r) for r in a.rooms]
    lines = ['| Sala | Ancho | Tiles | Max ventana | Slots | Error | .GFX (bytes) | Verif. |',
             '|---|---|---|---|---|---|---|---|']
    for r in rooms:
        b = load_lfl(os.path.join(a.dir, '%02d.LFL' % r))
        try:
            w, h, img0 = decode_room(b)
        except (IndexError, struct.error):
            continue
        if h != 128 or w % 8 or w > 2000:
            continue
        opt = cfg.get(r, {})
        emap = list(emap0)
        for de, a2 in opt.get('map', {}).items():
            emap[de] = a2
        img = [[emap[p] for p in row] for row in img0]
        PROTECT = opt.get('protect', []) + [tuple(int(v) for v in q.split(',')) for q in a.protect.split(';') if q.strip()]
        RARITY = opt.get('rarity', a.rarity)
        KEEP = opt.get('keep', [])
        OBJ_COLOR = opt.get('objcolor', {})
        OBJ_PNG = opt.get('objpng', {})
        OBJ_HIDE = opt.get('objhide', set())
        budget = opt.get('tiles', a.tiles)
        try:
            room = scumm2.Room(a.dir, r)
        except Exception:
            room = None
        want = opt.get('pool', min(a.pool, PROTECT_POOL) if PROTECT or KEEP else a.pool)   # las salas con zonas protegidas ceden menos tiles
        if a.dump_objects and room is not None:
            os.makedirs(a.dump_objects, exist_ok=True)
            for o in room.objects:
                if not o.obim or o.width == 0 or o.height == 0:
                    continue
                try:
                    im = decode_obim(room.file, o.obim, o.width, o.height)
                except IndexError:
                    continue
                fix = OBJ_COLOR.get(o.id, {})
                write_png(os.path.join(a.dump_objects, 'sala%02d_obj%03d.png' % (r, o.id)),
                          [[CHROMA[fix.get(emap[v], emap[v])] for v in row] for row in im])
        pool = 0 if a.no_objects else plan_pool(room, emap, want)
        render, cur, ntiles, maxwin, err0 = convert_windowed(w, h, img, budget - pool, a.view)
        layer = None
        grids = None
        if pool:
            grids = object_grids(room, emap)             # con los pesos de color de esta sala
            tiles, idx = limit_pool(grids, pool, [30 if ob.id in opt.get('objprio', ()) else 1 for ob in room.objects])
            layer = (tiles, idx)
        global MASK_MIN
        MASK_MIN = a.mask_min
        mraw = []
        mcols = room_mask_cells(b, w, h, mraw)
        gfx, nslots, ninst = build_gfx(cur, a.view, a.code_base, layer)
        ok = verify_gfx(gfx, cur)
        if layer:
            ok = ok and verify_objects(gfx, idx, tiles)
        with open(os.path.join(gdir, 'ROOM%02d.GFX' % r), 'wb') as f:
            f.write(gfx)
        sep = [[(255, 0, 255)] * w]
        orig = [[EGA[p] for p in row] for row in img0]
        for (x0, y0, x1, y1) in PROTECT:          # zonas protegidas: marco magenta en la banda del original
            for x in range(max(0, x0), min(w, x1 + 1)):
                for y in (y0, y1):
                    if 0 <= y < h:
                        orig[y][x] = (255, 0, 255)
            for y in range(max(0, y0), min(h, y1 + 1)):
                for x in (x0, x1):
                    if 0 <= x < w:
                        orig[y][x] = (255, 0, 255)
        mapped = [[CHROMA[p] for p in row] for row in img]
        withobj = None
        if room is not None and not a.no_objects:       # cuarta banda: la sala con las imagenes de sus objetos puestas en su sitio (las escenas de la intro son objetos)
            withobj = [list(row) for row in render]
            for o in room.objects:
                if not o.obim or o.width == 0 or o.height == 0 or o.id in OBJ_HIDE:
                    continue
                try:
                    im = decode_obim(room.file, o.obim, o.width, o.height)
                except IndexError:
                    continue
                fix = OBJ_COLOR.get(o.id, {})
                for yy in range(o.height):
                    for xx in range(o.width):
                        if 0 <= o.y + yy < h and 0 <= o.x + xx < w:
                            withobj[o.y + yy][o.x + xx] = CHROMA[fix.get(emap[im[yy][xx]], emap[im[yy][xx]])]
            if withobj == [list(row) for row in render]:
                withobj = None
        write_png(os.path.join(a.outdir, 'sala%02d.png' % r), orig + sep + mapped + sep + render + (sep + withobj if withobj else []))
        if any(mcols):                         # mascaraNN.png: la sala en grises; arriba en rojo los pixeles de la mascara original, abajo las celdas que tapan al personaje
            def gris(v):
                g = sum(EGA[v]) // 6 + 40
                return (g, g, g)
            pix = [[(255, 0, 0) if (mraw[y][x >> 3] >> (7 - (x & 7))) & 1 else gris(img0[y][x]) for x in range(w)] for y in range(h)]
            cel = [[(255, 0, 0) if (mcols[x >> 3] >> (y >> 3)) & 1 else gris(img0[y][x]) for x in range(w)] for y in range(h)]
            write_png(os.path.join(a.outdir, 'mascara%02d.png' % r), pix + sep + cel)
        lines.append('| %02d | %d | %d | %d | %d | %.1f%% | %d | %s |'
                     % (r, w, ntiles, maxwin, nslots, err0 * 100, len(gfx), 'OK' if ok else 'FALLA'))
        print(lines[-1], flush=True)
    with open(os.path.join(a.outdir, 'resumen.md'), 'w') as f:
        f.write('Presupuesto %d tiles por ventana de %d columnas, mapa EGA->Chroma "%s". Bandas de cada PNG: '
                'original EGA | original en colores Chroma | modo 0 limitado\n\n' % (a.tiles, a.view, a.map))
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    sys.exit(main())
