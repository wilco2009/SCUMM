#!/usr/bin/env python3
"""Empaqueta los datos NO graficos de Maniac Mansion (scripts, codigo de objetos, cajas y objetos de cada sala,
dueno y estado de los objetos) en DATA.BIN, que el programa del ZX81 carga de la SD al arrancar.

Uso: pack_data.py DIRECTORIO_LFL SALIDA.BIN --game perfil.cfg [--sounds DIR] [--first-page N] [--all]
  --sounds      carpeta de sound2vgm.py (SOUNDS.TXT con prioridad, duracion y bucle de cada sonido)
  --game        perfil del juego (SCUMM/V2/games/*.cfg, ver gameprofile.py): lo unico propio del juego que lee el motor
  --first-page  primera pagina de la RAM extendida que ocupan los datos (16 por omision)
  --all         incluye los scripts y salas sinteticos de las pruebas (ids >= 180 y salas >= 60), con el mismo
                reparto en paginas que world.bin (pruebas del cargador: --first-page 8)

Formato (little endian; las cuatro tablas son tal cual se copian en memoria, ver SCUMM/V2/ENGINE/loader.asm):
  +0      "SDAT"
  +4      u8   version (2)
  +5      u8   numero de paginas
  +6      u8   primera pagina
  +7      u8   0
  +8      u16  bytes de cada pagina (6144: lo que cabe en la ventana de datos $2000-$37FF)
  +10     pagina y direccion de la tabla de sonidos (0: no hay; ver sound2vgm.py), marca de los scripts (+13, 3 bytes: hash de SCRDIR, ODIR y el codigo de entrada/salida de las salas; la usa save.asm)
  +16    SCRDIR  256 x 3   pagina (0 = no hay), direccion
  +784    OBJOWN  780       dueno de cada objeto
  +1564   OBJST   780       estado de cada objeto
  +2344   ROOMDIR 64 x 16   por sala: pagina y direccion del codigo de entrada, id. de salida, ancho (u16),
                            pagina, direccion y tamano (u16) del bloque de cajas y objetos,
                            pagina y direccion de la mascara de profundidad por pixel (0: la sala no tiene; lfl2gfx.mask_blob)
  +3368   ODIR    780 x 3   por objeto: pagina y direccion de su bloque de codigo (pagina 0 = no esta)
  +5708   COSTDIR 64 x 3   por traje: pagina y direccion de sus fotogramas de sprites (TOOLS/costume2.py)
  +5900   PROFILE 256   perfil del juego (gameprofile.py)
  +6156   relleno hasta 6400
  +6400   las paginas, de 6144 bytes cada una
"""
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vmmodel as M
import gameprofile

TABLES = 6400
SYNTH_SCRIPT = 180
SYNTH_ROOM = 60



COST_MAX = 6100                                  # lo que cabe en una pagina de datos


def best_costume(costume2, cost, emap, must=(), walks=(4, 3, 2, 1)):
    """El traje mas completo que cabe en una pagina: primero las dos poses de la boca, luego solo la abierta, luego sin boca; con cada una, las
    poses de caminar (4, 3, 2 o 1 por direccion). Siempre con los fotogramas de overlay `must` (el pelo y el sombrero del vendedor: sin ellos sale a
    medias); luego se anaden los demas que quepan. Si no cabe devuelve el mas pequeno (el que llama lo descarta) o, con `must`, None."""
    blob = None
    for talk, two in ((True, True), (True, False), (False, False)):
        for walk in walks:
            try:
                blob = costume2.costume_blob(cost, emap, talk=talk, two=two, walk=walk, ovl=list(must))
            except (AssertionError, ValueError):       # mas de 256 celdas distintas
                continue
            if len(blob) <= COST_MAX:
                got = list(must)
                for f in costume2.overlay_frames(cost):          # los demas fotogramas de overlay, mientras quepan
                    if f in got:
                        continue
                    try:
                        big = costume2.costume_blob(cost, emap, talk=talk, two=two, walk=walk, ovl=sorted(got + [f]))
                    except (AssertionError, ValueError):
                        continue
                    if len(big) <= COST_MAX:
                        got.append(f)
                        blob = big
                return blob
    return None if must else blob


def scaled_costume(costume2, cost, emap, scales, walks=(4, 3, 2, 1)):
    """El traje con la primera escala de la lista (de mayor a menor) en la que caben sus fotogramas de overlay imprescindibles; si en ninguna, con la
    primera sin ellos."""
    must = costume2.overlay_wanted(cost)
    for sc in scales:
        costume2.SCALE = sc
        blob = best_costume(costume2, cost, emap, must, walks)
        if blob is not None:
            return blob
    costume2.SCALE = scales[0]
    return best_costume(costume2, cost, emap, (), walks)


def walk_blob_fit(costume2, cost, emap, f, dr, caps=(8, 6, 4, 3, 2, 1)):
    """Las poses de caminar (con el fotograma de overlay f; 0 = sin overlay) de una direccion: tantas como quepan en una pagina; None si ni una."""
    for wk in caps:
        try:
            wb = costume2.walk_overlay_blob(cost, emap, f, dr, walk=wk)
        except (AssertionError, ValueError):
            continue
        if wb is None:
            return None
        if len(wb) <= COST_MAX:
            return wb
    return None


def walk_pages(costume2, cost, emap, pk):
    """Las poses de caminar de las 4 direcciones en paginas aparte (clave = direccion): bytes del directorio (clave, pagina, direccion)."""
    ent = bytearray()
    for dr in range(4):
        if cost.merged(dr):
            wb = walk_blob_fit(costume2, cost, emap, 0, dr)
            if wb is not None:
                ent += bytes([dr]) + struct.pack('<BH', *pk.add(wb))
    return ent


def old_room_mask(world, rn):
    """La mascara de la sala sola, en el formato de antes de las mascaras de objeto (lfl2gfx.mask_blob): solo su tamano, para dejar el hueco (ver build)."""
    import lfl2gfx
    try:
        b = lfl2gfx.load_lfl(os.path.join(world.dir, '%02d.LFL' % rn))
        w, h = struct.unpack_from('<HH', b, 4)
        raw = []
        lfl2gfx.room_mask_cells(b, w, h, raw)
        return lfl2gfx.mask_blob(raw)
    except Exception:
        return None


MASK_MAX = 6000                  # una mascara de sala con las de sus objetos ha de caber en una pagina de datos (6 KB)


def room_mask(world, rn):
    """Mascara de profundidad de la sala y de sus objetos (lfl2gfx.mask_blob_objs). Un objeto lleva la suya si tiene imagen y, o la mascara no es
    toda ceros, o cubre algo de la mascara de la sala o de la de otro objeto (en ScummVM la de un objeto dibujado sustituye a la de la sala bajo el)."""
    import lfl2gfx
    import scumm2
    try:
        b = lfl2gfx.load_lfl(os.path.join(world.dir, '%02d.LFL' % rn))
        w, h = struct.unpack_from('<HH', b, 4)
        raw = []
        lfl2gfx.room_mask_cells(b, w, h, raw)
        room = scumm2.Room(world.dir, rn)
        info = []
        for o in room.objects:
            if not o.obim or o.width == 0 or o.height == 0 or o.width % 8 or o.x % 8 or o.y + o.height > h or o.height > 128 or o.x + o.width > w:
                info.append(None)
                continue
            try:
                info.append((o.x // 8, o.y, lfl2gfx.decode_obim_mask(room.file, o.obim, o.width, o.height)))
            except Exception:
                info.append(None)

        def covers(o, p):
            sx0, y0, om = o
            return any(om[y][x] for y in range(len(om)) for x in range(len(om[0]))) if p is None else (
                p[0] < sx0 + len(om[0]) and sx0 < p[0] + len(p[2][0]) and p[1] < y0 + len(om) and y0 < p[1] + len(p[2]))
        objs = []
        for i, o in enumerate(info):
            keep = False
            if o is not None:
                sx0, y0, om = o
                keep = covers(o, None) or any(raw[y][x] for y in range(y0, y0 + len(om)) for x in range(sx0, sx0 + len(om[0])))
                if not keep:
                    keep = any(p is not None and j != i and covers(p, None) and covers(o, p) for j, p in enumerate(info))
            objs.append(o if keep else None)
        blob = lfl2gfx.mask_blob_objs(raw, objs)
        while blob and len(blob) > MASK_MAX:         # no cabe en una pagina de datos: se quitan las mascaras de objeto mas grandes (la sala sigue con la suya)
            sizes = [(sum(len(r) for r in o[2]) * len(o[2]), i) for i, o in enumerate(objs) if o is not None]
            if not sizes:
                break
            objs[max(sizes)[1]] = None
            blob = lfl2gfx.mask_blob_objs(raw, objs)
        return blob
    except Exception:
        return None


def sound_table(path):
    """256 x 4 bytes (y otros 256 x 4 detras para VAR_MUSIC_TIMER): prioridad, banderas (bit 0 reiniciable, bit 1 bucle, bit 7 existe) y duracion en fotogramas a 50 Hz (65535: sin fin)."""
    t = bytearray(256 * 8)
    with open(path) as f:
        for ln in f:
            v = ln.split()
            if len(v) < 5:
                continue
            sid, prio, rest, ticks, loop = (int(x) for x in v[:5])
            dur = 65535 if loop >= 0 else min(65534, -(-ticks * 50 // 236))
            t[4 * sid:4 * sid + 4] = struct.pack('<BBH', prio, 0x80 | (1 if rest else 0) | (2 if loop >= 0 else 0), dur)
            if len(v) >= 7 and int(v[6]):       # VAR_MUSIC_TIMER: valor inicial, 0 y el intervalo en 1/8 de fotograma a 50 Hz
                t[1024 + 4 * sid:1028 + 4 * sid] = struct.pack('<BBH', int(v[5]), 0, max(1, round(int(v[6]) * 50 * 8 / 236)))
    return bytes(t)


def build(world, game, first_page=16, include_test=False, sounds=None):
    pk = M.Packer(first_page=first_page)
    scripts = {i: c for i, c in world.scripts.items() if include_test or i < SYNTH_SCRIPT}
    rooms = {n: r for n, r in world.rooms.items() if include_test or n < SYNTH_ROOM}
    scrdir = bytearray(256 * 3)
    for i, code in sorted(scripts.items()):
        page, addr = pk.add(code)
        scrdir[3 * i:3 * i + 3] = struct.pack('<BH', page, addr)
    odir = bytearray(M.NUM_OBJECTS * 3)
    for oid, (rn, block) in sorted(world.objects.items()):
        page, addr = pk.add(block)
        odir[3 * oid:3 * oid + 3] = struct.pack('<BH', page, addr)
    roomdir = bytearray(64 * 16)
    late = []
    for rn, r in sorted(rooms.items()):
        ent = r.entry_script() if r.encd_off else b''
        ext = r.exit_script() if r.excd_off else b''
        blob = M.room_blob(r)
        e = bytearray(16)
        struct.pack_into('<H', e, 6, r.width)
        if ent:
            struct.pack_into('<BH', e, 0, *pk.add(ent))
        if ext:
            struct.pack_into('<BH', e, 3, *pk.add(ext))
        bp, ba = pk.add(blob)
        struct.pack_into('<BHH', e, 8, bp, ba, len(blob))
        if not include_test:
            old = old_room_mask(world, rn)
            if old:
                pk.add(bytes(len(old)))          # sitio de la mascara de la sala de antes (ver masks_late): los scripts siguen donde estaban y las partidas guardadas valen
            late.append(rn)
        roomdir[16 * rn:16 * rn + 16] = e
    costdir = bytearray(64 * 3)                       # trajes: pagina y direccion de cada uno (0 = sin datos)
    if not include_test:
        import costume2
        import lfl2gfx
        import scumm2
        ixd = scumm2.Index(world.dir) if hasattr(world, 'dir') else None
        if ixd is not None:
            emap = lfl2gfx.default_map({})
            tr = gameprofile.parse(game).get('trajes', {})            # [trajes] escala = n/d (por omision 3/4)
            for cid in range(1, 64):                          # los trajes que existan en el juego (hasta los 64 del COSTDIR)
                try:
                    scales = [tuple(int(x) for x in e.split('/')) for e in tr.get('escala_%d' % cid, tr.get('escala', '3/4')).split(',')]     # escala_N = n/d[,n/d...]: un traje concreto; con varias, la primera en la que quepa entero
                    cost = costume2.Costume(scumm2.resource(world.dir, ixd, 'costume', cid))
                    blob = scaled_costume(costume2, cost, emap, scales, (1,))       # el traje de reposo solo con una pose de caminar: las de caminar van en paginas aparte (abajo)
                    ent = walk_pages(costume2, cost, emap, pk)
                    if len(ent) < 4 * len([1 for dr in range(4) if cost.merged(dr)]):
                        blob = scaled_costume(costume2, cost, emap, scales)      # alguna direccion no cabe aparte: el traje de siempre, con sus poses de caminar dentro
                except Exception:
                    continue
                if len(blob) > 6100:                      # no cabe en una pagina: ese traje se queda con el rectangulo
                    continue
                dr_ent = bytearray(ent)
                for f, dr in sorted(set(costume2.sticky_overlays(cost))):          # las poses de caminar con el overlay que se conserva (casco de Melissa): una pagina por fotograma y direccion (clave 4 * fotograma + direccion)
                    wb = walk_blob_fit(costume2, cost, emap, f, dr)
                    if wb is not None:
                        dr_ent += bytes([4 * f + dr]) + struct.pack('<BH', *pk.add(wb))
                if dr_ent:                                 # directorio (u8 n y n x clave, pagina, direccion) enlazado en la cabecera del traje
                    blob = bytearray(blob)
                    struct.pack_into('<BH', blob, 3 + 2 * blob[0], *pk.add(bytes([len(dr_ent) // 4]) + bytes(dr_ent)))
                    blob = bytes(blob)
                costdir[3 * cid:3 * cid + 3] = struct.pack('<BH', *pk.add(blob))
    snd_ref = struct.pack('<BH', *pk.add(sound_table(sounds))) if sounds else bytes(3)
    # Las mascaras de profundidad (la de la sala y las de sus objetos, room_mask) van al final: asi no desplazan los scripts, que son a lo que apuntan las
    # partidas guardadas (save.asm). En el sitio donde iban las de antes (solo la de la sala) queda un hueco del mismo tamano.
    for rn in late:
        mk = room_mask(world, rn)
        if mk:
            struct.pack_into('<BH', roomdir, 16 * rn + 13, *pk.add(mk))      # mascara de profundidad por pixel (lfl2gfx.mask_blob_objs)
    npages = len(pk.pages)
    # marca de los scripts (+13..+15): hash de donde esta cada script en las paginas (SCRDIR, ODIR y el codigo de entrada y salida de las salas),
    # que es lo unico de DATA.BIN a lo que apuntan las partidas guardadas (save.asm). Graficos, paleta, trajes, mascaras y sonidos no la cambian
    # salvo que desplacen los scripts (por eso las mascaras van al final y dejan un hueco donde iban las de antes).
    sig = bytes(scrdir) + bytes(odir) + b''.join(bytes(roomdir[16 * i:16 * i + 6]) for i in range(64)) + struct.pack('<B', first_page)
    stamp = struct.pack('<I', zlib.crc32(sig) & 0xFFFFFFFF)[:3]
    head = b'SDAT' + struct.pack('<BBBBH', 2, npages, first_page, 0, M.PAGE_USABLE) + snd_ref + stamp
    tables = head + bytes(scrdir) + bytes(world.owner) + bytes(world.state) + bytes(roomdir) + bytes(odir) + bytes(costdir) + gameprofile.build(game)
    assert len(tables) <= TABLES, len(tables)
    out = bytearray(tables + bytes(TABLES - len(tables)))
    for pg in sorted(pk.pages):
        out += bytes(pk.pages[pg][:M.PAGE_USABLE])
    return bytes(out), npages


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 1
    first = 16
    test = '--all' in args
    if '--first-page' in args:
        first = int(args[args.index('--first-page') + 1])
    if '--game' not in args:
        print('falta --game perfil.cfg')
        return 1
    game = args[args.index('--game') + 1]
    d, out = args[0], args[1]
    world = M.World(d)
    sounds = args[args.index('--sounds') + 1] + '/SOUNDS.TXT' if '--sounds' in args else None
    data, npages = build(world, game, first, test, sounds)
    with open(out, 'wb') as f:
        f.write(data)
    print('%s: %d paginas de %d bytes desde la %d, %d bytes' % (out, npages, M.PAGE_USABLE, first, len(data)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
