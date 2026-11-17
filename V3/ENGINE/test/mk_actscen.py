#!/usr/bin/env python3
"""mk_actscen.py (fase 8): escenas de actores para spr_run.sh. Para cada sala pedida carga la sala (DBG_ROOM) y despues, cada STEP fotogramas, escribe en la
memoria (TS_POKE) los registros de hasta 6 actores al azar (sala, x, y, traje, direccion, fotograma, caja, visible) y pide un volcado (TS_DUMPS).
La referencia (sprites3.py) lee los actores del propio volcado, asi que da igual lo que hagan los scripts de la sala con ellos.
Uso: mk_actscen.py scumm.sym DATA.BIN semilla "salas" escenas_por_sala > escenas.txt   (salas: 1,15,20,28; la salida son dos lineas: TS_POKE y TS_DUMPS, y el ultimo fotograma)"""
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'TOOLS'))
import pack_data3 as P3          # noqa: E402

sym = {}
for ln in open(sys.argv[1]):
    p = ln.split()
    if len(p) == 3 and p[1] == 'EQU':
        sym[p[0]] = int(p[2].rstrip('Hh'), 16)
data = P3.Data(open(sys.argv[2], 'rb').read())
rng = random.Random(int(sys.argv[3]))
rooms = [int(x) for x in sys.argv[4].split(',')]
per_room = int(sys.argv[5])
STEP = 4
ACTORS = sym['ACTORS']
out = []
dumps = []
scene_actors = []


def poke(f, addr, v):
    out.append('%d:%X:%X' % (f, addr, v & 255))


def poke16(f, addr, v):
    poke(f, addr, v)
    poke(f, addr + 1, v >> 8)


def bestpose(c):
    """(sprites de la postura mas grande del traje, su fotograma)."""
    page, addr = data.ptr('COSTDIR', c)
    b = data.read(page, addr, data.page_bytes - (addr - P3.WINDOW))
    m = (0, 3, 2)
    for an in range(b[0]):
        o = struct.unpack_from('<H', b, 3 + 2 * an)[0]
        if o:
            for st in range(b[o]):
                fo = struct.unpack_from('<H', b, o + 1 + 2 * st)[0]
                if fo != 0xFFFF and b[fo + 4] > m[0]:
                    m = (b[fo + 4], an // 4, an % 4)
    return m


def maxcells(c):
    return bestpose(c)[0]


# trajes que existen (blob principal) y fotogramas que tiene cada uno
costs = []
for c in range(1, 129):
    page, _ = data.ptr('COSTDIR', c)
    if page:
        costs.append(c)


# ---- 10e: escenas fijas al final de cada sala (sin azar: no cambian las de antes). ACT_FIXED=0 las quita.
def anims(c):
    """{animacion: (pasos, celdas del primer paso, offset)} del traje c (blob principal)."""
    page, addr = data.ptr('COSTDIR', c)
    b = data.read(page, addr, data.page_bytes - (addr - P3.WINDOW))
    r = {}
    for an in range(b[0]):
        o = struct.unpack_from('<H', b, 3 + 2 * an)[0]
        if o and b[o]:
            fo = struct.unpack_from('<H', b, o + 1)[0]
            if fo != 0xFFFF:
                r[an] = (b[o], b[fo + 4], o)
    return r


ANIMS = {c: anims(c) for c in costs}
ANGLE = (270, 90, 180, 0)                                       # direccion antigua -> angulo (0 izquierda, 1 derecha, 2 de frente, 3 de espaldas)
# un traje y un fotograma con la animacion de espaldas y la de la derecha distintas (el angulo 70 es de espaldas; con "cp 70" seria derecha)
DIR70 = next((c, an // 4) for c in costs for an in sorted(ANIMS[c]) if an % 4 == 3 and an - 2 in ANIMS[c] and ANIMS[c][an][2] != ANIMS[c][an - 2][2] and an // 4 > 0)
# trajes y fotogramas de un solo paso (postura fija): (celdas, traje, animacion)
ONE = sorted(set((v[1], c, an) for c in costs for an, v in ANIMS[c].items() if v[0] == 1 and 0 < v[1] <= 32 and an // 4 > 0))


def extra_pick():
    """Un traje de dos paginas y una animacion que solo esta en el blob extra (COSTDIR2): (traje, fotograma, angulo)."""
    for c in costs:
        page, addr = data.ptr('COSTDIR2', c)
        if not page:
            continue
        b = data.read(page, addr, data.page_bytes - (addr - P3.WINDOW))
        for an in range(4, b[0]):
            o = struct.unpack_from('<H', b, 3 + 2 * an)[0]
            if o and b[o] and an not in ANIMS[c]:
                return c, an // 4, ANGLE[an % 4]
    return None


EXTRA = extra_pick()


def cache_pick():
    """Un traje con dos fotogramas de frente (angulo 180) de un solo paso y pocas celdas: (traje, fotograma a, fotograma b)."""
    for c in costs:
        fr = sorted(set(an // 4 for (cells, cc, an) in ONE if cc == c and an % 4 == 2 and cells <= 12))
        if len(fr) >= 2:
            return c, fr[0], fr[1]
    return None


CACHE = cache_pick()


def exact64():
    """Hasta 6 actores de un solo paso cuyas celdas sumen exactamente 64 (AC_MAXSPR = 63: el de mas atras no cabe y va a los extra)."""
    best = {0: []}
    for _ in range(6):
        nxt = dict(best)
        for s, lst in best.items():
            for e in ONE:
                if s + e[0] <= 64 and s + e[0] not in nxt and (s + e[0] < 64 or e[0] <= 32):
                    nxt[s + e[0]] = lst + [e]
        best = nxt
        if 64 in best:
            return best[64]
    return None


def put(f, a, room, x, y, cost, angle, fr):
    base = ACTORS + 64 * a
    poke(f, base + 0, room)
    poke16(f, base + 1, x)
    poke16(f, base + 3, y)
    poke16(f, base + 5, cost)
    poke16(f, base + 7, angle)
    poke(f, base + 9, 0)
    poke(f, base + 10, 1)
    poke(f, base + 11, fr)
    poke(f, base + 16, 0)
    poke16(f, base + 17, 0)


def prepoke(f, room, acts, big):
    """El fotograma de estos actores cambia (a uno que no tiene ningun traje): asi el de la escena siguiente reinicia su contador de poses."""
    for a in acts:
        base = ACTORS + 64 * a
        poke(f, base + 0, room)
        poke16(f, base + 5, big[0])
        poke(f, base + 10, 1)
        poke(f, base + 11, 255)
    return f + 2


def fixed_scenes(room, width, height, camx, big, f):
    ylo, yhi = 60, max(70, min(height, 144) - 20)
    if width > 320:                                             # la camara en otro sitio (x - camara: "x sin la camara")
        cam = width - 320 if camx != width - 320 else 0
        poke16(f, sym['CAMCUR'], cam + 160)
        f += 70
    else:
        cam = 0
    c1 = costs[0]
    # X0: el actor 1 con traje y el fotograma 5
    f = prepoke(f, room, range(1, 13), big)
    for a in range(2, 13):
        poke(f, ACTORS + 64 * a + 10, 0)
    put(f, 1, room, cam + 100, ylo + 20, c1, 180, 5)
    dumps.append(f + 2)
    scene_actors.append('1')
    f += STEP + 2
    # X1: el actor 1 visible SIN traje y con el fotograma 3 (su contador de poses no se toca: no se dibuja)
    put(f, 1, room, cam + 100, ylo + 20, 0, 180, 3)
    dumps.append(f + 2)
    scene_actors.append('0')
    f += STEP + 2
    # X2: el actor 1 con traje y el mismo fotograma 3 (su contador vuelve a 0: el ultimo fotograma dibujado era el 5); el 2 con el angulo 70;
    # el 3 y el 4 con la misma y (empate: el de numero menor va detras)
    f = prepoke(f, room, range(2, 13), big)
    for a in range(5 if not EXTRA else 6, 13):
        poke(f, ACTORS + 64 * a + 10, 0)
    if EXTRA:                                                   # el 5 con una animacion que solo esta en el blob extra
        put(f, 5, room, cam + 140, ylo + 40, EXTRA[0], EXTRA[2], EXTRA[1])
        poke(f, ACTORS + 64 * 5 + 25, EXTRA[1])                # A_STAND = el mismo fotograma: sin el blob extra no se dibujaria nada
    put(f, 1, room, cam + 100, ylo + 20, c1, 180, 3)
    put(f, 2, room, cam + 180, ylo + 30, DIR70[0], 70, DIR70[1])
    put(f, 3, room, cam + 40, ylo + 10, c1, 180, 3)
    put(f, 4, room, cam + 240, ylo + 10, c1, 180, 3)
    dumps.append(f + 2)
    scene_actors.append('1.2.3.4' + ('.5' if EXTRA else ''))
    f += STEP + 2
    # X3: actores de un solo paso con 64 celdas en total: 63 sprites normales y el de mas atras (la y mas pequena), a los extra
    sel = exact64()
    if sel:
        sel = sel[::-1]                                         # el ultimo que se anadio (el que llega a 64, <= 32 celdas) va el primero: el de mas atras
        f = prepoke(f, room, range(1, 13), big)
        for a in range(len(sel) + 1, 13):
            poke(f, ACTORS + 64 * a + 10, 0)
        for k, (cells, c, an) in enumerate(sel):
            put(f, k + 1, room, cam + 20 + 45 * k, ylo + 8 * k, c, ANGLE[an % 4], an // 4)
        dumps.append(f + 2)
        scene_actors.append('.'.join(str(k + 1) for k in range(len(sel))))
        f += STEP + 2
    # X4-X10: la cache de firma (un actor que no cambia no se reescribe). Dos actores de un solo paso (la postura no cambia con el contador) y en cada
    # escena cambia UNA cosa; los actores que no cambian de fotograma no se miran en el contador de poses (sigue contando: es lo esperado)
    if CACHE:
        c, fa, fb = CACHE
        f = prepoke(f, room, range(1, 13), big)
        for a in range(3, 13):
            poke(f, ACTORS + 64 * a + 10, 0)
        put(f, 1, room, cam + 60, ylo + 10, c, 180, fa)
        put(f, 2, room, cam + 150, ylo + 30, c, 180, fa)
        dumps.append(f + 2)                                     # X4: los dos
        scene_actors.append('1.2')
        f += STEP + 2
        poke16(f, ACTORS + 64 * 2 + 1, cam + 166)              # X5: el 2 solo cambia de x
        dumps.append(f + 2)
        scene_actors.append('0')
        f += STEP + 2
        if width > 320:                                         # X6: solo la camara (8 px: el hardware llega en un fotograma)
            cam2 = cam + 8 if cam + 8 <= width - 320 else cam - 8
            poke16(f, sym['CAMCUR'], cam2 + 160)
            dumps.append(f + 4)
            scene_actors.append('0')
            f += STEP + 4
        poke(f, ACTORS + 64 * 2 + 11, fb)                       # X7: el 2 solo cambia de fotograma
        dumps.append(f + 2)
        scene_actors.append('2')
        f += STEP + 2
        poke(f, ACTORS + 64 * 1 + 10, 0)                        # X8: el 1 (detras) se va: el primer sprite del 2 pasa a ser el 0
        dumps.append(f + 2)
        scene_actors.append('0')
        f += STEP + 2
        poke(f, ACTORS + 64 * 2 + 10, 0)                        # X9: el 2 tambien se va (sus sprites se apagan)
        dumps.append(f + 2)
        scene_actors.append('0')
        f += STEP + 2
        poke(f, ACTORS + 64 * 2 + 10, 1)                        # X10: el 2 vuelve igual: su entrada de la cache es de hace mas de un fotograma
        dumps.append(f + 2)
        scene_actors.append('0')
        f += STEP + 2
    # X11: la mascara de la sala con un fotograma de 6 celdas de ancho (8 tiras en MKBUF) y, en la ultima tira, un tramo que acaba mas de 64 filas por
    # debajo del borde de arriba del fotograma: el fin del tramo se acota al alto de la ventana (si no, la tira 8 se sale de MKBUF y pisa ASEL/AC2V)
    x11 = mask_pick(room, width, cam)
    if x11:
        x, y, c, an, box = x11
        f = prepoke(f, room, range(1, 13), big)
        for a in range(3, 13):
            poke(f, ACTORS + 64 * a + 10, 0)
        put(f, 1, room, x, y, c, ANGLE[an % 4], an // 4)
        poke(f, ACTORS + 64 * 1 + 16, box)
        if CACHE:                                               # el 2, delante (mas y): se dibuja despues y lee su entrada de ASEL (la 1)
            put(f, 2, room, cam + 20, y + 12, CACHE[0], 180, CACHE[1])
        poke16(f + 1, ACTORS + 64 * 1 + 3, y + 1)               # el 1 cambia de y en cada fotograma hasta el volcado: la cache no lo salta y la mascara se
        poke16(f + 2, ACTORS + 64 * 1 + 3, y)                   # descodifica en el mismo fotograma del volcado (el desbordamiento solo dura ese fotograma)
        dumps.append(f + 2)
        scene_actors.append('1.2' if CACHE else '1')
        f += STEP + 2
        nomask = [k for k in range(nboxes(room)) if not box_mask(room, k)]
        if nomask:                                              # X12: el mismo actor en una caja sin mascara: la sala no lo tapa
            poke(f, ACTORS + 64 * 1 + 16, nomask[0])
            dumps.append(f + 2)
            scene_actors.append('0')
            f += STEP + 2
    # X13: un actor que asoma por arriba de la sala mas de 16 lineas (la linea de pantalla de sus primeras celdas es negativa: acl_neg)
    if CACHE:
        c, fa, fb = CACHE
        dx, dy, w, h, cells = frame_hdr(c, ANIMS[c][fa * 4 + 2][2])
        ytop = 16 if height >= 144 else 0
        f = prepoke(f, room, range(1, 13), big)
        for a in range(2, 13):
            poke(f, ACTORS + 64 * a + 10, 0)
        put(f, 1, room, cam + 100, ytop - 24 - dy, c, 180, fa)
        dumps.append(f + 2)
        scene_actors.append('1')
        f += STEP + 2
    return f


def room_blob(room):
    ent = data.tab('ROOMDIR', room, P3.ROOM_ENTRY)
    bp, ba, bl = struct.unpack_from('<BHH', ent, 10)
    return data.read(bp, ba, bl)


def nboxes(room):
    return room_blob(room)[0]


def box_mask(room, k):
    return room_blob(room)[1 + 18 * k + 16]


def mask_pick(room, width, cam):
    """(x, y, traje, animacion, caja) para X11, o None si la sala no tiene un tramo asi (o ninguna caja con mascara)."""
    ent = data.tab('ROOMDIR', room, P3.ROOM_ENTRY)
    bp, ba, bl = struct.unpack_from('<BHH', ent, 10)
    blob = data.read(bp, ba, bl)
    mbox = [k for k in range(blob[0]) if blob[1 + 18 * k + 16]]
    mp, ma = struct.unpack_from('<BH', ent, 15)
    if not mp or not mbox:
        return None
    mb = data.read(mp, ma, data.page_bytes - (ma - P3.WINDOW))
    wide = [(c, an, fr) for c in costs for an, (st, cells, o) in ANIMS[c].items() if st == 1 and an // 4 > 0
            for fr in [frame_hdr(c, o)] if fr[2] == 6 and fr[3] <= 8]
    if not wide:
        return None
    c, an, (dx, dy, w, h, cells) = wide[0]
    for st in range(7, mb[0]):
        off = struct.unpack_from('<H', mb, 1 + 2 * st)[0]
        if not off:
            continue
        p, row = off, 0
        while mb[p]:
            ln, v = mb[p], mb[p + 1]
            top = max(0, row + ln - 80)                          # la ventana empieza 80 filas por encima del fin del tramo: 16 bytes de mas, la entrada
            if v and row < top + 8 * h and top + 8 * h <= row + ln and row + ln - top > 72:     # de ASEL del actor siguiente
                col = (st - 7) * 8                               # la tira 0 de la ventana: la ultima (la 7) es la del tramo
                x = col - dx
                y = top - dy
                if cam <= col and col + 8 * 8 <= cam + 320 and 0 <= y < 240:
                    return x, y, c, an, mbox[0]
            row += ln
            p += 2
    return None


def frame_hdr(c, o):
    """(dx, dy, ancho, alto, celdas) del primer paso de la lista de animacion en o."""
    page, addr = data.ptr('COSTDIR', c)
    b = data.read(page, addr, data.page_bytes - (addr - P3.WINDOW))
    fo = struct.unpack_from('<H', b, o + 1)[0]
    dx, dy = struct.unpack_from('<bb', b, fo)
    return dx, dy, b[fo + 2], b[fo + 3], b[fo + 4]


# 10f: el arnes salta el arranque, asi que RESMAP (pseudoRoom) estaba a cero y el script 60 de la sala 20 (loadRoom $84) daba E_BADROOM; se pone el que deja el arranque
import vmmodel3 as M                                            # noqa: E402
for ln in M.boot_snapshot(M.World(os.path.join(HERE, '..', '..', 'Indy Last Crusade'))):
    if ln.startswith('PSEUDO '):
        _, k_, v_ = ln.split()
        poke(1, sym['RESMAP'] + int(k_), int(v_))
f = 2
for room in rooms:
    ent = data.tab('ROOMDIR', room, P3.ROOM_ENTRY)
    width, height = struct.unpack_from('<HB', ent, 6)
    bp, ba, bl = struct.unpack_from('<BHH', ent, 10)
    blob = data.read(bp, ba, bl)
    nb = blob[0]
    for a in range(1, 13):                                      # los actores de la sala anterior se van antes de cargar la nueva
        poke(f, ACTORS + 64 * a + 10, 0)
        poke(f, ACTORS + 64 * a, 0)
    f += 1
    out.append('%d:%X:%X' % (f, sym['DBG_ROOM'], room))
    out.append('%d:%X:0' % (f, sym['DBG_ROOM'] + 1))
    f += 14
    if room == 20:                                               # 10f: la sala 20 lanza al entrar una cutscene (script 77 -> 58: el guardia camina hasta Indy y 60 hace loadRoom $84, la prision); sin esto
        for i in range(24):                                      # la escena que cae despues de ese momento se hace en la sala 132. Se matan todas las ranuras (NSLOT x 16 en SLOTS)
            poke(f, sym['SLOTS'] + 16 * i, 0)
        f += 2
    big = sorted(costs, key=lambda c: -maxcells(c))[:10]
    # puntos tapados por la mascara de la sala (para poner actores detras) y cajas con mascara
    mp, ma = struct.unpack_from('<BH', ent, 15)
    spots, mbox = [], [k for k in range(nb) if blob[1 + 18 * k + 16]]
    if mp:
        mb = data.read(mp, ma, data.page_bytes - (ma - P3.WINDOW))
        for st in range(mb[0]):
            off = struct.unpack_from('<H', mb, 1 + 2 * st)[0]
            if off:
                p, row = off, 0
                while mb[p]:
                    ln, v = mb[p], mb[p + 1]
                    if v:
                        spots.append((st * 8 + 4, row + ln // 2))
                    row += ln
                    p += 2
    camx = 0
    anchor = rng.choice(spots) if spots else None
    if width > 400:                                              # sala ancha: la camara se pone en otro sitio (CAMCUR) y se espera a que el hardware llegue
        camx = rng.randrange(0, width - 320) if not anchor else max(0, min(width - 320, anchor[0] - 100)) // 8 * 8
        poke16(f, sym['CAMCUR'], camx + 160)
        f += 70
    prev = {}
    angles = (0, 90, 180, 270, 70, 71, 109, 110, 251, 252, 255, 256, 289, 290, 359)
    for k in range(per_room):
        n = rng.choice((1, 1, 2, 3, 4, 5, 6))
        crowd = k % 4 == 3                                       # una escena con los trajes mas grandes: no caben en 63 sprites
        if crowd:
            n = 6
        if crowd:                                                # antes, todos al fotograma 1: asi el de la escena grande es siempre un cambio
            for a in range(1, 13):                               # (con traje, en la sala y visibles: asi su contador se actualiza)
                poke(f, ACTORS + 64 * a + 0, room)
                poke16(f, ACTORS + 64 * a + 5, big[0])
                poke(f, ACTORS + 64 * a + 10, 1)
                poke(f, ACTORS + 64 * a + 11, 255)                 # (un fotograma que ningun traje tiene: dibuja el de quieto y cuenta aparte)
            f += 2
        ys = rng.randrange(40, max(60, min(height, 144)))
        mine = []
        for a in range(1, 13):
            base = ACTORS + 64 * a
            if a > n:
                poke(f, base + 10, 0)              # oculto
                continue
            cost = rng.choice(big if crowd else costs)
            bnr = rng.randrange(nb) if nb else 0
            other = rng.random() < 0.12 and not crowd                          # en otra sala (visible, pero no se dibuja)
            poke(f, base + 0, 0 if other else room)
            ax, ay = rng.choice(spots) if spots and rng.random() < 0.7 else (None, None)
            if ax is not None and camx <= ax < camx + 250:       # detras de un trozo de la mascara de la sala
                px, py = ax + rng.randrange(-6, 7), ay + rng.randrange(0, 20)
                if mbox:
                    bnr = rng.choice(mbox)
            else:
                px = camx + rng.randrange(0, 250)
                py = ys if rng.random() < 0.3 else rng.randrange(40, max(60, min(height, 144)))     # algunos con la misma y
            poke16(f, base + 1, px)
            poke16(f, base + 3, py)
            nocost = rng.random() < 0.06 and not crowd
            poke16(f, base + 5, 0 if nocost else cost)                                                       # alguno sin traje
            poke16(f, base + 7, (270, 90, 180, 0)[bestpose(cost)[2]] if crowd else rng.choice(angles))
            poke(f, base + 9, 0)
            poke(f, base + 10, 1)
            fr = bestpose(cost)[1] if crowd else rng.choice((1, 2, 3, 3, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 18, 22, 30))
            while prev.get(a) == fr and not crowd:                             # el fotograma cambia en cada escena: el contador de poses vuelve a 0
                fr = rng.choice((1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 18, 22, 30))
            if not other and not nocost:                         # solo el contador de un actor que se dibuja se actualiza
                prev[a] = fr
            poke(f, base + 11, fr)
            poke(f, base + 16, bnr)
            poke16(f, base + 17, rng.choice((0, 0, 0, 4, 8)))
            if not other and not nocost:
                mine.append(a)
        dumps.append(f + 2)
        scene_actors.append('.'.join(str(a) for a in mine) or '0')
        f += STEP + 2
    if os.environ.get('ACT_FIXED', '1') != '0':
        f = fixed_scenes(room, width, height, camx, big, f)
print(','.join(out))
print(','.join(str(d) for d in dumps))
print(f + 2)
print(';'.join(scene_actors))      # 10e: los actores que pone cada escena (actscen.sh -> EXPECT_ACT: solo a ellos se les mira el contador de poses)
