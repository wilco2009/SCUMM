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
                poke16(f, base + 1, ax + rng.randrange(-6, 7))
                poke16(f, base + 3, ay + rng.randrange(0, 20))
                if mbox:
                    bnr = rng.choice(mbox)
            else:
                poke16(f, base + 1, camx + rng.randrange(0, 250))
                poke16(f, base + 3, ys if rng.random() < 0.3 else rng.randrange(40, max(60, min(height, 144))))     # algunos con la misma y
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
        dumps.append(f + 2)
        f += STEP + 2
print(','.join(out))
print(','.join(str(d) for d in dumps))
print(f + 2)
