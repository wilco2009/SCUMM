#!/usr/bin/env python3
"""Empaqueta los datos NO graficos de Maniac Mansion (scripts, codigo de objetos, cajas y objetos de cada sala,
dueno y estado de los objetos) en DATA.BIN, que el programa del ZX81 carga de la SD al arrancar.

Uso: pack_data.py DIRECTORIO_LFL SALIDA.BIN --game perfil.cfg [--sounds DIR] [--first-page N] [--all]
  --sounds      carpeta de sound2vgm.py (SOUNDS.TXT con prioridad, duracion y bucle de cada sonido)
  --game        perfil del juego (SCUMM/games/*.cfg, ver gameprofile.py): lo unico propio del juego que lee el motor
  --first-page  primera pagina de la RAM extendida que ocupan los datos (16 por omision)
  --all         incluye los scripts y salas sinteticos de las pruebas (ids >= 180 y salas >= 60), con el mismo
                reparto en paginas que world.bin (pruebas del cargador: --first-page 8)

Formato (little endian; las cuatro tablas son tal cual se copian en memoria, ver SCUMM/ENGINE/loader.asm):
  +0      "SDAT"
  +4      u8   version (2)
  +5      u8   numero de paginas
  +6      u8   primera pagina
  +7      u8   0
  +8      u16  bytes de cada pagina (6144: lo que cabe en la ventana de datos $2000-$37FF)
  +10     pagina y direccion de la tabla de sonidos (0: no hay; ver sound2vgm.py), 3 bytes sin uso
  +16     SCRDIR  256 x 3   pagina (0 = no hay), direccion
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vmmodel as M
import gameprofile

TABLES = 6400
SYNTH_SCRIPT = 180
SYNTH_ROOM = 60


def room_mask(world, rn):
    import lfl2gfx
    try:
        b = lfl2gfx.load_lfl(os.path.join(world.dir, '%02d.LFL' % rn))
        w, h = struct.unpack_from('<HH', b, 4)
        raw = []
        lfl2gfx.room_mask_cells(b, w, h, raw)
        return lfl2gfx.mask_blob(raw)
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
        mk = room_mask(world, rn) if not include_test else None
        if mk:
            struct.pack_into('<BH', e, 13, *pk.add(mk))      # mascara de profundidad por pixel (lfl2gfx.mask_blob)
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
            if 'escala' in tr:
                costume2.SCALE = tuple(int(x) for x in tr['escala'].split('/'))
            for cid in range(1, 64):                          # los trajes que existan en el juego (hasta los 64 del COSTDIR)
                try:
                    costume2.SCALE = tuple(int(x) for x in tr.get('escala_%d' % cid, tr.get('escala', '3/4')).split('/'))     # escala_N = n/d: un traje concreto
                    cost = costume2.Costume(scumm2.resource(world.dir, ixd, 'costume', cid))
                    blob = costume2.costume_blob(cost, emap)
                    if len(blob) > 6100:                      # con las dos poses de la boca no cabe en una pagina: solo la abierta
                        blob = costume2.costume_blob(cost, emap, two=False)
                    if len(blob) > 6100:                      # ni asi: sin boca
                        blob = costume2.costume_blob(cost, emap, talk=False)
                except Exception:
                    continue
                if len(blob) > 6100:                      # no cabe en una pagina: ese traje se queda con el rectangulo
                    continue
                costdir[3 * cid:3 * cid + 3] = struct.pack('<BH', *pk.add(blob))
    snd_ref = struct.pack('<BH', *pk.add(sound_table(sounds))) if sounds else bytes(3)
    npages = len(pk.pages)
    head = b'SDAT' + struct.pack('<BBBBH', 2, npages, first_page, 0, M.PAGE_USABLE) + snd_ref + bytes(3)
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
