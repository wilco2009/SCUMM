#!/usr/bin/env python3
"""Empaqueta los datos NO graficos de Indy3 EGA (scripts globales y locales, codigo de salas y de objetos, cajas, mascaras, trajes, tabla
de sonidos, clases/dueno/estado de los 1.000 objetos) en DATA.BIN, que el programa del ZX81 carga de la SD. Es pack_data.py (V2/TOOLS) con
las tablas de v3. Mismo esquema de paginas (6.144 B utiles de cada pagina de 8 KB, bloques que no cruzan paginas, direcciones de la
ventana $2000-$37FF), cabecera con la version 3.

Uso (desde SCUMM/V3/TOOLS):
  pack_data3.py DIR SALIDA.BIN --costumes CARPETA [--sounds CARPETA] [--game perfil.cfg] [--first-page N]
  pack_data3.py DIR SALIDA.BIN check          comprueba SALIDA.BIN contra los recursos originales (y contra los .bin de --costumes si se da)
  --costumes   carpeta de `costume3.py convert` (cost/COSTnnn.bin y COSTnnnX.bin)
  --sounds     carpeta de `sound3vgm.py` (SOUNDS.TXT)
  --game       perfil del juego (V2/TOOLS/gameprofile.py); sin el, el bloque PROFILE va a ceros (lo decide la fase 3)
  --first-page primera pagina virtual de los datos (16 por omision, como v2)

Formato (little endian; las tablas se copian tal cual en memoria, como en V2/ENGINE/loader.asm; los desplazamientos salen de OFFSETS):
  +0      "SDAT"
  +4      u8   version (3)
  +5      u8   numero de paginas
  +6      u8   primera pagina
  +7      u8   0
  +8      u16  bytes de cada pagina (6144)
  +10     pagina y direccion de la tabla de sonidos (0: no hay), 3 bytes
  +13     u16  tamano de las tablas (TABLES: las paginas empiezan ahi)
  +15     u8   0
  +16     SCRDIR   200 x 3      scripts globales 0-199: pagina (0 = no existe; 255 = grande, la direccion es el indice en BIGDIR) y direccion
          OBJOWN   1000         dueno de cada objeto (0-15; 15 = esta en la sala)         (Index.owner)
          OBJST    1000         estado de cada objeto (0-15)                              (Index.state)
          OBJCLS   1000 x 3     las 24 bits de clases de cada objeto, u24 little endian   (Index.classes)
          OBJROOM  1000         sala cuyo recurso lleva el OBCD del objeto (0 = el objeto no esta en ninguna sala)
          ROOMDIR  100 x 32     por sala 0-99 (ver ROOM_ENTRY)
          ODIR     1000 x 3     por objeto: pagina y direccion de su bloque OBCD completo (cabecera de 17 bytes, verbos en ternas
                                (verbo, u16 desplazamiento desde el principio del bloque), nombre y codigo)
          COSTDIR  129 x 3      por traje 0-128: pagina y direccion del blob principal (V3/TOOLS/costume3.py); 0 = sin datos
          COSTDIR2 129 x 3      idem del blob extra (posturas especiales que no caben en el principal); 0 = no hay
          BIGDIR   4 x 8        scripts mayores que una pagina: u8 id, u8 paginas, u8 primera pagina, u8 0, u16 direccion, u16 longitud.
                                D5 (fase 3): paginas CONSECUTIVAS y SOLAPADAS desde la direccion de la ventana: la pagina k lleva los
                                bytes [k * 4096, k * 4096 + 6144) (el script 95 mide 6.711 B: dos paginas). Ver add_big
          PROFILE  256          perfil del juego (gameprofile.py) o ceros
  TABLES  las paginas, de 6144 bytes cada una

ROOMDIR, 32 bytes por sala (todo a 0 en las salas que no existen):
  +0  pagina y direccion del codigo de entrada (ENCD; 0 = no hay)       +3  idem del de salida (EXCD)
  +6  u16 ancho de la sala en pixeles        +8  u8 alto en pixeles (128-200)      +9  u8 numero de scripts locales
  +10 pagina, direccion y u16 tamano del blob de la sala (abajo)       +15 pagina y direccion de la mascara de profundidad (0: no hay)
  +18 pagina y direccion de la tabla de scripts locales: n x (u8 id (>= 200), u8 pagina, u16 direccion)
  +21 u8 numero de objetos de la sala         +22.. ceros
Blob de la sala: u8 numero de cajas, por caja 18 bytes tal cual estan en el recurso (8 x s16 de las esquinas ul, ur, lr, ll en x,y; u8 mascara;
  u8 banderas), u16 bytes de la matriz de cajas y la matriz tal cual (listas por caja de origen de ternas (desde, hasta, siguiente) acabadas
  en 0xFF; ScummEngine::getNextBox; la sala 46 la trae truncada), u8 numero de objetos y por objeto 14 bytes: u16 id, u8 x/8, u8 y/8,
  u8 ancho/8, u8 alto/8, u8 padre, u8 estado del padre (0/1), s16 x de acercamiento, s16 y de acercamiento, u8 direccion del actor (0-7),
  u8 banderas (bit 0: el objeto tiene imagen propia en el .GFX).
Mascara de profundidad: lfl2gfx.mask_blob: u8 tiras, u16 por tira con el desplazamiento de sus tramos y, por tira, tramos (longitud, valor)
  hacia abajo hasta sumar el ALTO DE LA SALA (ROOMDIR +8; en v2 eran siempre 128) o hasta longitud 0. Bit 7 del valor = pixel de la izquierda
  de la tira; 1 = tapa al personaje. Es la mascara de la sala (zplane 1 del fondo); las de los objetos no se empaquetan.
Tabla de sonidos (la apunta +10; desde la fase 5b siempre esta): 256 x 4 (prioridad, banderas (bit 7 existe, 0 reiniciable, 1 bucle, 2 fija el tempo del
  temporizador de musica, 3 es una cancion: el recurso pasa de 1000 bytes), u16 duracion en fotogramas a 50 Hz, 65535 = sin fin) y otros 256 x 4 (u8 0, u8 0, u16 tick de 236 Hz en que el sonido fija el tempo).
  VAR_MUSIC_TIMER: ver sound3vgm.py.
"""
import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import gameprofile           # noqa: E402
import lfl2gfx               # noqa: E402
import scumm3res as R        # noqa: E402
import vmmodel as M          # noqa: E402

VERSION = 3
NUM_SCRIPTS = R.NUM_GLOBAL_SCRIPTS          # 200
NUM_OBJECTS = 1000
NUM_ROOMS = 100
NUM_COSTUMES = 129
ROOM_ENTRY = 32
BIG_ENTRIES = 4
BOX_SIZE = 18
OBJ_REC = 14
BLOB_MAX = 2048                              # lo que el motor reservara para el blob de una sala (v2: 1024; la fase 3 lo ajusta)
PAGE_USABLE = M.PAGE_USABLE
WINDOW = M.WINDOW
PAGE = M.PAGE

SIZES = [('SCRDIR', NUM_SCRIPTS * 3), ('OBJOWN', NUM_OBJECTS), ('OBJST', NUM_OBJECTS), ('OBJCLS', NUM_OBJECTS * 3),
         ('OBJROOM', NUM_OBJECTS), ('ROOMDIR', NUM_ROOMS * ROOM_ENTRY), ('ODIR', NUM_OBJECTS * 3), ('COSTDIR', NUM_COSTUMES * 3),
         ('COSTDIR2', NUM_COSTUMES * 3), ('BIGDIR', BIG_ENTRIES * 8), ('PROFILE', 256)]
OFFSETS = {}
_o = 16
for _n, _s in SIZES:
    OFFSETS[_n] = _o
    _o += _s
TABLES = (_o + 255) // 256 * 256


def room_blob(room):
    boxes, matrix = room.boxes()
    b = bytearray([len(boxes)])
    for bx in boxes:
        b += struct.pack('<8hBB', *bx)
    b += struct.pack('<H', len(matrix)) + bytes(matrix)
    b.append(len(room.objects))
    for o in room.objects:
        has = room.object_image(o) is not None
        b += struct.pack('<HBBBBBBhhBB', o.id, o.x // 8, o.y // 8, o.width // 8, o.height // 8, o.parent, o.parentstate,
                         o.walk_x - 0x10000 if o.walk_x & 0x8000 else o.walk_x, o.walk_y - 0x10000 if o.walk_y & 0x8000 else o.walk_y,
                         o.actordir, 1 if has else 0)
    if len(b) > BLOB_MAX:
        raise ValueError('sala %d: blob de %d bytes' % (room.num, len(b)))
    return bytes(b)


def read_sounds(path):
    """Tabla de sonidos desde el SOUNDS.TXT de sound3vgm.py."""
    t = bytearray(256 * 8)
    with open(path) as f:
        for ln in f:
            if ln.startswith('#') or len(ln.split()) < 7:
                continue
            sid, prio, rest, ticks, loop, tempo, ttick = (int(x) for x in ln.split()[:7])
            dur = 65535 if loop >= 0 else min(65534, -(-ticks * 50 // 236))
            t[4 * sid:4 * sid + 4] = struct.pack('<BBH', prio, 0x80 | (1 if rest else 0) | (2 if loop >= 0 else 0) | (4 if tempo else 0), dur)
            if tempo:
                t[1024 + 4 * sid:1028 + 4 * sid] = struct.pack('<BBH', 0, 0, min(65535, ttick))
    return bytes(t)


SONG_BYTES = 1000                            # un sonido de mas de 1000 bytes es una cancion (vmgame3.SOUND_SONG_BYTES)
BIG_STRIDE = 4096                            # D5: la pagina k de un script grande lleva los bytes [k * 4096, k * 4096 + 6144)


def add_big(pk, code):
    """Un script mayor que una pagina (D5, V3/FASE3.md): paginas consecutivas desde la direccion de la ventana, SOLAPADAS. La pagina k
    lleva los bytes [k * BIG_STRIDE, k * BIG_STRIDE + 6144): una instruccion que empieza en [k * 4096, (k + 1) * 4096) tiene todos sus
    bytes en la pagina k (ninguna instruccion pasa de 2.048 B; la mayor de Indy3 mide 205). El Z80 cambia de pagina al empezar una
    instruccion fuera de esa franja (vm_core.asm, es_cross). Devuelve (primera pagina, paginas)."""
    n = 1 + max(0, -(-(len(code) - PAGE_USABLE) // BIG_STRIDE))
    first = None
    for k in range(n):
        pg = pk._new_page()
        if first is None:
            first = pg
        elif pg != first + k:
            raise ValueError('las paginas de un script grande tienen que ser consecutivas')
        chunk = code[k * BIG_STRIDE:k * BIG_STRIDE + PAGE_USABLE]
        pk.pages[pg][:len(chunk)] = chunk
        pk.fill[pg] = PAGE_USABLE
    return first, n


def build(ix, costumes_dir=None, sounds=None, game=None, first_page=16):
    pk = M.Packer(first_page=first_page)
    stats = {}

    def add(kind, data):
        stats[kind] = stats.get(kind, 0) + len(data)
        return pk.add(data)

    t = {n: bytearray(s) for n, s in SIZES}
    big = []
    for i in range(NUM_SCRIPTS):
        r = ix.resource('script', i)
        if r is None:
            continue
        code = r[4:]
        if len(code) > PAGE_USABLE:
            if len(big) >= BIG_ENTRIES:
                raise ValueError('mas de %d scripts grandes' % BIG_ENTRIES)
            first, n = add_big(pk, code)
            stats['scripts grandes'] = stats.get('scripts grandes', 0) + len(code)
            t['BIGDIR'][8 * len(big):8 * len(big) + 8] = struct.pack('<BBBBHH', i, n, first, 0, WINDOW, len(code))
            t['SCRDIR'][3 * i:3 * i + 3] = struct.pack('<BH', 0xFF, len(big))
            big.append((i, len(code), n, first))
        else:
            t['SCRDIR'][3 * i:3 * i + 3] = struct.pack('<BH', *add('scripts globales', code))
    synth = os.environ.get('SCUMM_SYNTH')          # fase 9 (solo pruebas): un script global 199 (hexadecimal en ese fichero), que Indy3 no usa; el modelo lo lee igual (World)
    if synth:
        code = bytes.fromhex(open(synth).read().strip())
        if ix.resource('script', 199) is not None:
            raise ValueError('el script 199 existe en el juego')
        t['SCRDIR'][3 * 199:3 * 199 + 3] = struct.pack('<BH', *add('scripts globales', code))
    for oid in range(NUM_OBJECTS):
        t['OBJOWN'][oid] = ix.owner[oid]
        t['OBJST'][oid] = ix.state[oid]
        t['OBJCLS'][3 * oid:3 * oid + 3] = ix.classes[oid].to_bytes(3, 'little')
    maxblob, dup = 0, []
    for rn in ix.rooms():
        if rn == 0 or rn >= NUM_ROOMS:
            continue
        room = R.Room(ix, rn)
        e = bytearray(ROOM_ENTRY)
        if room.encd_off:
            struct.pack_into('<BH', e, 0, *add('codigo de entrada', room.entry_script()))
        if room.excd_off:
            struct.pack_into('<BH', e, 3, *add('codigo de salida', room.exit_script()))
        struct.pack_into('<HBB', e, 6, room.width, room.height, len(room.local_scripts))
        blob = room_blob(room)
        maxblob = max(maxblob, len(blob))
        page, addr = add('cajas y objetos de sala', blob)
        struct.pack_into('<BHH', e, 10, page, addr, len(blob))
        mask = lfl2gfx.mask_blob(room.image()[2])
        if mask:
            struct.pack_into('<BH', e, 15, *add('mascaras de profundidad', mask))
        if room.local_scripts:
            loc = bytearray()
            for sid, _ in room.local_scripts:
                p, a = add('scripts locales', room.local_code[sid])
                loc += struct.pack('<BBH', sid, p, a)
            struct.pack_into('<BH', e, 18, *add('tablas de scripts locales', bytes(loc)))
        e[21] = len(room.objects)
        t['ROOMDIR'][ROOM_ENTRY * rn:ROOM_ENTRY * rn + ROOM_ENTRY] = e
        for o in room.objects:
            if o.id >= NUM_OBJECTS:
                raise ValueError('sala %d: objeto %d fuera de la tabla' % (rn, o.id))
            if t['OBJROOM'][o.id]:
                dup.append((o.id, t['OBJROOM'][o.id], rn))
                continue
            t['ODIR'][3 * o.id:3 * o.id + 3] = struct.pack('<BH', *add('bloques de objetos (OBCD)', o.block))
            t['OBJROOM'][o.id] = rn
    ncost = nextra = 0
    if costumes_dir:
        for cid in range(NUM_COSTUMES):
            for tag, table in (('', 'COSTDIR'), ('X', 'COSTDIR2')):
                path = os.path.join(costumes_dir, 'cost', 'COST%03d%s.bin' % (cid, tag))
                if os.path.exists(path):
                    with open(path, 'rb') as f:
                        blob = f.read()
                    t[table][3 * cid:3 * cid + 3] = struct.pack('<BH', *add('trajes' if not tag else 'trajes (extra)', blob))
                    ncost += 1 if not tag else 0
                    nextra += 1 if tag else 0
    # tabla de sonidos: siempre (la fase 5b la necesita para el temporizador de musica del arranque): con SOUNDS.TXT trae duraciones y banderas; sin el, solo
    # las banderas que salen del recurso: bit 7 existe y bit 3 "es una cancion" (el recurso pasa de SONG_BYTES: la regla del modelo, vmgame3.SOUND_SONG_BYTES)
    snd_tab = bytearray(read_sounds(sounds) if sounds else bytes(256 * 8))
    for sid in range(256):
        r = ix.resource('sound', sid)
        if r:
            snd_tab[4 * sid + 1] |= 0x80 | (8 if len(r) > SONG_BYTES else 0)
    snd_ref = struct.pack('<BH', *add('tabla de sonidos', bytes(snd_tab)))
    prof = bytearray(gameprofile.build(game) if game else bytes(256))
    if game:                                  # extension de v3: PROF+255 = 1 si el perfil pide saltar la proteccion anticopia ([juego] proteccion = 0; D2)
        cfg = gameprofile.parse(game).get('juego', {})
        prof[255] = 1 if cfg.get('proteccion', '1').strip() == '0' else 0
    t['PROFILE'][:] = bytes(prof)
    npages = len(pk.pages)
    head = b'SDAT' + struct.pack('<BBBBH', VERSION, npages, first_page, 0, PAGE_USABLE) + snd_ref + struct.pack('<HB', TABLES, 0)
    tables = bytearray(head)
    for n, s in SIZES:
        assert len(tables) == OFFSETS[n], (n, len(tables), OFFSETS[n])
        tables += bytes(t[n])
    tables += bytes(TABLES - len(tables))
    out = bytes(tables)
    for pg in sorted(pk.pages):
        out += bytes(pk.pages[pg][:PAGE_USABLE])
    info = dict(stats=stats, big=big, maxblob=maxblob, dup=dup, ncost=ncost, nextra=nextra, npages=npages)
    return out, info


# ---------------------------------------------------------------------------------------------------------------------- lectura
class Data:
    """DATA.BIN ya empaquetado: lo que el Z80 hace con las tablas."""

    def __init__(self, b):
        self.b = b
        assert b[:4] == b'SDAT' and b[4] == VERSION, 'no es un DATA.BIN de v3'
        self.npages, self.first, _, self.page_bytes = struct.unpack_from('<BBBH', b, 5)
        self.tables = struct.unpack_from('<H', b, 13)[0]

    def tab(self, name, i, n):
        o = OFFSETS[name] + i * n
        return self.b[o:o + n]

    def read(self, page, addr, n):
        assert self.first <= page < self.first + self.npages, 'pagina %d fuera de rango' % page
        assert WINDOW <= addr and addr - WINDOW + n <= self.page_bytes, 'el bloque cruza la pagina'
        o = self.tables + (page - self.first) * self.page_bytes + addr - WINDOW
        return self.b[o:o + n]

    def ptr(self, name, i):
        return struct.unpack('<BH', self.tab(name, i, 3))


def check(ix, path, costumes_dir=None):
    with open(path, 'rb') as f:
        d = Data(f.read())
    bad = []
    n = {'scripts': 0, 'objetos': 0, 'salas': 0, 'locales': 0, 'trajes': 0, 'mascaras': 0}

    def eq(what, got, want):
        if got != want:
            bad.append('%s: leido %d bytes, esperado %d' % (what, len(got), len(want)))

    for i in range(NUM_SCRIPTS):
        r = ix.resource('script', i)
        page, addr = d.ptr('SCRDIR', i)
        if r is None:
            if page:
                bad.append('script %d: no existe y tiene entrada' % i)
            continue
        code = r[4:]
        if page == 0xFF:
            sid, pages, first, _, a0, ln = struct.unpack('<BBBBHH', d.tab('BIGDIR', addr, 8))
            got = b''.join(d.read(first + k, a0, min(BIG_STRIDE if k + 1 < pages else PAGE_USABLE, ln - k * BIG_STRIDE))
                           for k in range(pages))
            for k in range(pages - 1):              # el solape: los 2 KB de despues de la franja, repetidos en la pagina siguiente
                eq('script %d, solape de la pagina %d' % (i, k), d.read(first + k, a0 + BIG_STRIDE, PAGE_USABLE - BIG_STRIDE),
                   code[(k + 1) * BIG_STRIDE:k * BIG_STRIDE + PAGE_USABLE])
            if sid != i or ln != len(code):
                bad.append('script grande %d: BIGDIR mal' % i)
        else:
            got = d.read(page, addr, len(code))
        eq('script %d' % i, got, code)
        n['scripts'] += 1
    for oid in range(NUM_OBJECTS):
        if d.tab('OBJOWN', oid, 1)[0] != ix.owner[oid] or d.tab('OBJST', oid, 1)[0] != ix.state[oid] or \
                int.from_bytes(d.tab('OBJCLS', oid, 3), 'little') != ix.classes[oid]:
            bad.append('objeto %d: dueno, estado o clases distintos' % oid)
    for rn in ix.rooms():
        if rn == 0 or rn >= NUM_ROOMS:
            continue
        room = R.Room(ix, rn)
        e = d.tab('ROOMDIR', rn, ROOM_ENTRY)
        if room.encd_off:
            eq('sala %d entrada' % rn, d.read(e[0], struct.unpack_from('<H', e, 1)[0], len(room.entry_script())), room.entry_script())
        if room.excd_off:
            eq('sala %d salida' % rn, d.read(e[3], struct.unpack_from('<H', e, 4)[0], len(room.exit_script())), room.exit_script())
        w, h, nloc = struct.unpack_from('<HBB', e, 6)
        if (w, h, nloc) != (room.width, room.height, len(room.local_scripts)):
            bad.append('sala %d: medidas o locales distintos' % rn)
        bp, ba, bl = struct.unpack_from('<BHH', e, 10)
        eq('sala %d blob' % rn, d.read(bp, ba, bl), room_blob(room))
        mask = lfl2gfx.mask_blob(room.image()[2])
        mp, ma = struct.unpack_from('<BH', e, 15)
        if mask:
            eq('sala %d mascara' % rn, d.read(mp, ma, len(mask)), mask)
            n['mascaras'] += 1
        elif mp:
            bad.append('sala %d: mascara que no existe' % rn)
        if nloc:
            lp, la = struct.unpack_from('<BH', e, 18)
            tab = d.read(lp, la, 4 * nloc)
            for k, (sid, _) in enumerate(room.local_scripts):
                s2, p2, a2 = struct.unpack_from('<BBH', tab, 4 * k)
                eq('sala %d local %d' % (rn, sid), d.read(p2, a2, len(room.local_code[sid])), room.local_code[sid]) if s2 == sid else bad.append(
                    'sala %d: local %d mal en la tabla' % (rn, sid))
                n['locales'] += 1
        if e[21] != len(room.objects):
            bad.append('sala %d: numero de objetos' % rn)
        for o in room.objects:
            if d.tab('OBJROOM', o.id, 1)[0] == rn:
                p, a = d.ptr('ODIR', o.id)
                eq('objeto %d' % o.id, d.read(p, a, len(o.block)), o.block)
                n['objetos'] += 1
        n['salas'] += 1
    if costumes_dir:
        for cid in range(NUM_COSTUMES):
            for tag, table in (('', 'COSTDIR'), ('X', 'COSTDIR2')):
                pth = os.path.join(costumes_dir, 'cost', 'COST%03d%s.bin' % (cid, tag))
                page, addr = d.ptr(table, cid)
                if os.path.exists(pth):
                    with open(pth, 'rb') as f:
                        want = f.read()
                    eq('traje %d%s' % (cid, tag), d.read(page, addr, len(want)), want)
                    n['trajes'] += 1 if not tag else 0
                elif page:
                    bad.append('traje %d%s: entrada sin fichero' % (cid, tag))
    sp, sa = struct.unpack_from('<BH', d.b, 10)
    if sp:
        st = d.read(sp, sa, 2048)
        n['sonidos'] = sum(1 for k in range(256) if st[4 * k + 1] & 0x80)
    print('leido de vuelta: %s' % n)
    if bad:
        print('%d DIFERENCIAS:' % len(bad))
        for x in bad[:30]:
            print('  ', x)
        return 1
    print('DATA.BIN correcto: %d paginas, %d bytes' % (d.npages, len(d.b)))
    return 0


def summary(info, data):
    print('DATA.BIN: %d bytes (tablas %d + %d paginas de %d), primera pagina virtual segun cabecera' % (len(data), TABLES, info['npages'], PAGE_USABLE))
    tot = sum(info['stats'].values())
    for k, v in sorted(info['stats'].items(), key=lambda kv: -kv[1]):
        print('  %-30s %8d B (%4.1f %%)' % (k, v, 100.0 * v / tot))
    print('  %-30s %8d B (relleno de paginas: %d B)' % ('total de datos', tot, info['npages'] * PAGE_USABLE - tot))
    print('mayor blob de sala: %d B (limite de este empaquetador %d)' % (info['maxblob'], BLOB_MAX))
    print('scripts grandes (id, bytes, paginas, primera pagina): %s' % info['big'])
    if info['dup']:
        print('objetos repetidos en dos salas (id, primera, otra): %s' % info['dup'])
    print('trajes: %d con blob principal, %d con extra' % (info['ncost'], info['nextra']))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dir')
    ap.add_argument('out')
    ap.add_argument('cmd', nargs='?', choices=['check'])
    ap.add_argument('--costumes')
    ap.add_argument('--sounds')
    ap.add_argument('--game')
    ap.add_argument('--first-page', type=int, default=16)
    a = ap.parse_args()
    ix = R.Index(a.dir)
    if a.cmd == 'check':
        return check(ix, a.out, a.costumes)
    sounds = os.path.join(a.sounds, 'SOUNDS.TXT') if a.sounds else None
    data, info = build(ix, a.costumes, sounds, a.game, a.first_page)
    with open(a.out, 'wb') as f:
        f.write(data)
    summary(info, data)
    return 0


if __name__ == '__main__':
    sys.exit(main())
