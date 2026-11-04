#!/usr/bin/env python3
"""agi2spr.py: celdas de las vistas de AGI v2 -> sprites por hardware del SD81 Booster (8x8, color por fila, mascara).

Cada celda (w x h pixeles de AGI) se estira al HiRes (el pixel a ocupa los pixeles (8a+4)//5 .. (8(a+1)+4)//5 - 1 de la celda, 1 o 2) y se corta en
mosaicos de 8x8. De cada fila de 8 pixeles de un mosaico se guardan: mascara (pixel opaco), dato (1 = tinta) y color (tinta*16 + papel, codigos de
Chroma). Si la fila tiene mas de dos colores se quedan los dos mas frecuentes y los demas pasan al mas cercano (agi2hr.sdist). Los mosaicos sin
ningun pixel opaco no se guardan. Los bucles espejados (bit 7 del byte de la celda y bucle distinto del de origen) ya vienen invertidos.

Fichero Nvvvl.SPR (vvv = vista, l = bucle), little endian:
  +0   u16 tamano del resto
  +2   u8  numero de celdas
  +3   u8  maximo de mosaicos de una celda del bucle (los sprites que reserva un objeto)
  +4   u16 por celda: desplazamiento de su registro desde +2
  registro de celda: u8 mosaicos, u8 ancho HiRes, u8 alto, u8 banderas (bit 0 = software), u16 huella de las mascaras, y por mosaico: u8 tx, u8 ty,
  8 bytes de color, 8 de dato y 8 de mascara (los 24 bytes van tal cual a 2105-2128: color, forma, mascara)
  Con AGI_GFX4=1 (modo 160w, AGI/PLAN160W.md) los mosaicos son de 8 pixeles nativos (1 pixel de AGI = 1 pixel) y el fichero lleva ademas, tras los registros, el bloque de cada celda
  con sus pixeles exactos (los 16 colores) para lo que se pinta por software (rotulos anchos, add.to.pic y el dibujo de show.obj); una segunda tabla de u16 (tras la de desplazamientos
  de los registros, que pasan a empezar en 2 + 4 * celdas) da el desplazamiento de cada bloque (0 = no cabe en la pagina: se usan los mosaicos). Bloque: u8 transparente (codigo de
  Chroma), u8 0, u16 desplazamientos de las filas (alto + 1, desde el principio del bloque) y las filas: runs de (codigo de Chroma << 4 | longitud 1-15), 0 al final de la fila;
  el espejo ya esta hecho y el color transparente de la cola de la fila se omite.
Las celdas con mas de SW_TILES mosaicos en una fila (rotulos anchos) no caben en los sprites (12 por linea): las dibuja el Z80 en el bitmap, por celdas;
  la huella (FNV-1a de las mascaras) dice si dos celdas tienen la misma forma (solo cambian los colores).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi2hr
import agi_read as ag


GFX4 = os.environ.get('AGI_GFX4') == '1'      # modo 160w (AGI/PLAN160W.md): 1 pixel de AGI = 1 pixel del sprite, sin estirar


def lo(a):
    return a if GFX4 else (8 * a + 4) // 5


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


def has_desc(d):
    """La vista tiene descripcion (show.obj): su celda 0 del bucle 0 es un dibujo con marco, que se muestra entero en un cuadro de dialogo."""
    off = d[3] | (d[4] << 8)
    return 0 < off < len(d)


def cel_tiles(d, loop, cel, framed=False):
    """(ancho HiRes, alto, [(tx, ty, color[8], dato[8], mascara[8]), ...]) o None si no existe la celda.
    framed: el ancho se rellena hasta un mosaico entero (el ultimo pixel, el del marco, pasa al final y el hueco repite el de su izquierda): en una celda con
    parte transparente el papel es el blanco del cuadro y el interior negro del dibujo se veia blanco."""
    c = cel_pixels(d, loop, cel)
    if c is None:
        return None
    w, h, trans, rows = c
    hrw = lo(w)
    inv = [0] * hrw
    for a in range(w):
        for x in range(lo(a), lo(a + 1)):
            inv[x] = a
    if framed and hrw % 8:
        inv = inv[:hrw - 1] + [inv[hrw - 2]] * (-hrw % 8) + [inv[hrw - 1]]
        hrw += -hrw % 8
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


# Vistas que se dibujan por software (como los rotulos anchos) aunque quepan en los sprites, porque en su sala pasan de los 12 sprites por linea y el hardware
# deja sin dibujar a los de abajo del orden (una cupula y la mitad del ego): {juego: {vista}}. SQ1, sala 6: tres cupulas de 5 mosaicos por fila (vista 175) y el ego.
# SQ2, sala 56 (capsulas de escape): las puertas de las cuatro capsulas (vista 139, bucles 0 a 2, 12 objetos) reservaban 112 sprites y el robot (vista 141,
# se dibuja despues) se quedaba sin ninguno: invisible aunque persigue y mata; ahora van por software (los tres bucles juntos: un sprite del interior se dibujaria por encima de la puerta cerrada, que esta en el bitmap) y el robot tiene sitio; sus movimientos de abrir y cerrar se saltan (ADAPT en agi_read.py) (el interior y las luces, sin animacion: FIXED_CEL).
# SQ2, sala 93 (la capsula del final): la capsula por fuera (vista 175, prioridad 15) pasa de SW_TILES y se pinta en la imagen, y la camara de hibernacion (o2, vista 181, bucles 0 y 1, prioridad 5)
# como sprite salia por delante: un sprite siempre tapa a lo pintado por software. Por software las dos, se componen por prioridad (el bucle 2, el ego tumbado, sigue con sprites: o3 no esta al final).
FORCE_SW = {'SQ1': {175}, 'SQ2': {(147, 1), (147, 2), (139, 0), (139, 1), (139, 2), (181, 0), (181, 1)}}
# Vistas cuya animacion se congela al dibujarlas (tiempo de ciclo 127: casi no cambian de celda y conservan la de set.cel): sus cambios de celda, dibujadas por
# software, recomponen lineas cada ciclo y eran el 60 % del tiempo de la sala. SQ1, sala 6: las luces de las cupulas (vista 175); sala 31: los pistones de la maquina (vista 78).
# KQ1, salas 1 y 2 (castillo): la bandera de la torre (vista 97, 8-9 mosaicos por fila: por software) y los cocodrilos del foso (vista 107, dos objetos) cambiaban de
# celda cada ciclo y el ego iba muy lento; ahora casi no ciclan (solo esas dos salas usan estas vistas).
FREEZE_VIEWS = {'SQ1': {175, 78}, 'KQ1': {97, 107}}
# (vista, bucle) en lugar de una vista: solo ese bucle. SQ1, sala 37: el despegue de la nave (vista 109, bucle 1, 12 mosaicos por fila) por software iba
# muy lento; su bucle 0 (58 mosaicos) se queda en software porque con el ego y lo demas no cabe en los 64 sprites.
# Vistas que van por hardware aunque tengan mas de SW_TILES mosaicos en una fila (hasta 12 por linea): SQ1, sala 33 (esquivar rocas): la nave (vistas 75, 95 y
# 102, 7 mosaicos de ancho) por software recomponia lineas en cada paso y la animacion iba a 1/5 de la velocidad. Sala 70 (bar): el alienigena del mostrador
# (vistas 73 y 251, 7 mosaicos), animado, recomponia lineas en cada ciclo; solo comparte linea con el ego y poco mas (menos de 12 sprites).
FORCE_HW = {'SQ1': {75, 95, 102, 73, 251, 62, (109, 1)}}
# Vistas cuya animacion se salta: todas sus celdas dibujan la ultima del bucle (la huella es igual y no se recompone nada; el ciclo y sus banderas, los de
# siempre). SQ1, sala 29: el holograma que se compone (vista 63, 9 mosaicos x 8 filas, no cabe en los 64 sprites) por software tardaba muchisimo.
# SQ1, sala 67 (intro, adaptacion estetica decidida por el usuario): los nombres de los creditos (vistas 204 y 206) ciclaban blanco, blanco, rojo claro y rojo final;
# ahora salen ya con el rojo final y el ciclo (mismas celdas, tiempos y banderas) sigue igual.
FINAL_CEL = {'SQ1': {63, 204, 206}}
# Vistas que no dibujan nada (sus celdas conservan tamano y bucles; la logica no cambia): SQ1, sala 29: las dos mitades del holograma (vista 64, 72 mosaicos cada
# una) se deslizan 2 pixeles por ciclo hasta juntarse y por software recomponian 9 x 8 mosaicos por mitad en cada ciclo; ahora aparece la cabeza (vista 63).
# (vista, bucle) en lugar de una vista: solo ese bucle. SQ2, sala 9 (desierto): los arboles negros de fondo (vista 44, bucle 0, objetos 2 a 5) no caben en los
# sprites junto a los verdes (bucle 1); decision del usuario: solo se ven los verdes.
BLANK_VIEWS = {'SQ1': {64}, 'SQ2': {(44, 0)}}
# (vista, bucle) en lugar de una vista: solo ese bucle. Animacion de dos fotogramas (estado inicial y estado final): la celda 0 se queda como es y todas las demas
# dibujan la ultima del bucle; ciclo, tiempos y banderas siguen igual. SQ2, sala 66: las dos paredes que se levantan a los lados (vista 147, bucles 1 y 2, 19
# mosaicos cada una) crecian en 5 celdas con sprites y la de la derecha salia incompleta (limite de 64); ahora van por software (FORCE_SW) y no recomponen nada.
TWO_FRAMES = {'SQ2': {(147, 1), (147, 2)}}
# {(vista, bucle): celda}: ese bucle dibuja siempre esa celda, sin animacion (el ciclo, los tiempos y las banderas de la logica siguen igual). SQ2, sala 56: la
# capsula abierta ciclaba entre dos celdas (el interior, vista 139 bucle 2) y parpadeaban sus luces (bucle 3): ahora fijas, en la celda con la que la logica las pone.
FIXED_CEL = {'SQ2': {(139, 2): 0, (139, 3): 0}}
_force = set()
_two = set()
_fixed = {}
_freeze = set()
_hw = set()
_final = set()
_blank = set()


def set_game(path):
    """Elige las vistas forzadas a software del juego (carpeta `path`)."""
    global _fixed, _two, _force, _freeze, _hw, _final, _blank
    name = os.path.basename(os.path.normpath(path)).upper()
    _force = FORCE_SW.get(name, set())
    _two = TWO_FRAMES.get(name, set())
    _fixed = FIXED_CEL.get(name, {})
    _freeze = FREEZE_VIEWS.get(name, set())
    _hw = FORCE_HW.get(name, set())
    _final = FINAL_CEL.get(name, set())
    _blank = BLANK_VIEWS.get(name, set())


def final_cel(view, d, loop, cel):
    """Celda que se dibuja: la ultima del bucle en FINAL_CEL; en TWO_FRAMES, la 0 o la ultima; en FIXED_CEL, la indicada."""
    if (view, loop) in _fixed:
        return min(_fixed[(view, loop)], d[d[5 + 2 * loop] | (d[6 + 2 * loop] << 8)] - 1)
    if view in _final or ((view, loop) in _two and cel > 0):
        return d[d[5 + 2 * loop] | (d[6 + 2 * loop] << 8)] - 1
    return cel


def cel_of(view, d, loop, cel, framed=False):
    """cel_tiles de la celda que se dibuja: en las vistas de FINAL_CEL, siempre la ultima del bucle."""
    cel = final_cel(view, d, loop, cel)
    r = cel_tiles(d, loop, cel, framed)
    return (r[0], r[1], []) if view in _blank or (view, loop) in _blank else r


def frozen(view):
    return view in _freeze


def meta(tiles, view=None, loop=None):
    """(software, huella de 16 bits) de los mosaicos de una celda."""
    per = {}
    h = 0x811C
    for tx, ty, col, pix, msk in tiles:
        per[ty] = per.get(ty, 0) + 1
        for b in (tx, ty) + tuple(msk):
            h = ((h ^ b) * 0x0101) & 0xFFFF
    return (1 if per and view not in _hw and (view, loop) not in _hw and (max(per.values()) > SW_TILES or view in _force or (view, loop) in _force) else 0), h


def loop_maxt(d, loop):
    """Maximo de mosaicos de las celdas de un bucle."""
    ncels = d[d[5 + 2 * loop] | (d[6 + 2 * loop] << 8)]
    return max((len(cel_tiles(d, loop, c)[2]) for c in range(ncels)), default=0)


def raw_cel(view, d, loop, cel):
    """GFX4: (transparente, ancho, alto, filas) de la celda que se dibuja, con codigos de Chroma y el espejo hecho; None en las vistas en blanco."""
    if view in _blank or (view, loop) in _blank:
        return None
    cel = final_cel(view, d, loop, cel)
    c = cel_pixels(d, loop, cel)
    if c is None:
        return None
    w, h, trans, rows = c
    return agi2hr.to_chroma(trans), w, h, [[agi2hr.to_chroma(v) for v in row] for row in rows]


def raw_block(rc):
    """GFX4: el bloque de pixeles exactos de una celda (ver la cabecera)."""
    t, w, h, rows = rc
    data = []
    for row in rows:
        while row and row[-1] == t:
            row = row[:-1]
        out = bytearray()
        i = 0
        while i < len(row):
            n = 1
            while i + n < len(row) and row[i + n] == row[i] and n < 15:
                n += 1
            out.append((row[i] << 4) | n)
            i += n
        out.append(0)
        data.append(bytes(out))
    base = 2 + 2 * (h + 1)
    offs = []
    p = base
    for r in data:
        offs.append(p)
        p += len(r)
    offs.append(p)
    b = bytearray((t, 0))
    for o in offs:
        b.extend((o & 255, o >> 8))
    for r in data:
        b.extend(r)
    return bytes(b)


def build_loop_raw(d, loop, view=None):
    """build_loop y, en GFX4, la lista (por celda) de si lleva el bloque de pixeles exactos."""
    ncels = d[d[5 + 2 * loop] | (d[6 + 2 * loop] << 8)]
    recs = []
    raws = []
    for cel in range(ncels):
        hrw, h, tiles = cel_of(view, d, loop, cel, framed=(not GFX4) and loop == 0 and cel == 0 and has_desc(d))
        sw, hh = meta(tiles, view, loop)
        r = bytearray((len(tiles), hrw, h, sw, hh & 255, hh >> 8))
        for tx, ty, col, pix, msk in tiles:
            r.extend((tx, ty))
            r.extend(col)
            r.extend(pix)
            r.extend(msk)
        recs.append(bytes(r))
        if GFX4:
            rc = raw_cel(view, d, loop, cel)
            raws.append(raw_block(rc) if rc else b'')
    maxt = max((r[0] for r in recs), default=0)
    ntab = 2 if GFX4 else 1
    out = bytearray((ncels, maxt))
    off = 2 + 2 * ntab * ncels
    for r in recs:
        out.extend((off & 255, off >> 8))
        off += len(r)
    has = []
    if GFX4:
        rawoff = []
        for b in raws:
            if b and off + len(b) <= 8190:
                rawoff.append(off)
                off += len(b)
                has.append(True)
            else:
                rawoff.append(0)
                has.append(False)
        for o in rawoff:
            out.extend((o & 255, o >> 8))
    for r in recs:
        out.extend(r)
    if GFX4:
        for b, hv in zip(raws, has):
            if hv:
                out.extend(b)
    return bytes(out), has


def build_loop(d, loop, view=None):
    """Contenido de Nvvvl.SPR para el bucle `loop` de la vista d (sin el u16 del tamano)."""
    return build_loop_raw(d, loop, view)[0]


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = ag.Game(argv[1])
    set_game(argv[1])
    os.makedirs(os.path.join(argv[2], 'SPR'), exist_ok=True)
    sel = [int(a) for a in argv[3:]] or g.present('VIEW')
    n = big = 0
    for v in sel:
        d = g.resource('VIEW', v)
        if not d:
            continue
        try:
            nl = d[2]
            for lp in range(nl):
                data = build_loop(d, lp, v)
                if len(data) > 8190:
                    big += 1
                    print('VIEW %d bucle %d: %d bytes, no cabe en una pagina' % (v, lp, len(data)))
                    continue
                with open(os.path.join(argv[2], 'SPR', 'N%03d%d.SPR' % (v, lp)), 'wb') as f:
                    f.write(bytes((len(data) & 255, len(data) >> 8)) + data)
                n += 1
        except (IndexError, ValueError) as e:
            print('VIEW %d: error %s' % (v, e))
    print('%s: %d bucles convertidos, %d demasiado grandes' % (os.path.basename(argv[1].rstrip('/\\')), n, big))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
