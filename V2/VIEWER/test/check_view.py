#!/usr/bin/env python3
"""Comprueba el volcado de memoria de test_view contra lo que debe verse.

Uso: check_view.py volcado.bin DIR_LFL [guion]    (el guion de test_view, para comprobar la camara y el scroll fino)
Lee de las variables del visor la sala, la camara y el scroll fino; vuelve a convertir esa sala con
lfl2gfx (el mismo procedimiento que genero el .GFX) y comprueba que cada una de las 32 x 16 celdas
visibles apunta a un codigo cuya forma y color en las tablas son los del tile que toca.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'TOOLS'))
import lfl2gfx as L

DFILE, TILES, COLORS, V = 0x8000, 0x3800, 0xC000, 0x7F00
GFX_DIR = os.environ.get('GFX_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'preview', 'gfx'))


def main():
    dump = open(sys.argv[1], 'rb').read()
    d = sys.argv[2]
    room = dump[V]
    cam = struct.unpack_from('<H', dump, V + 1)[0]
    fine = dump[V + 3]
    print('sala %d  camara %d  fino %d' % (room, cam, fine))
    if len(sys.argv) > 3:
        npos = struct.unpack_from('<H', open(os.path.join(GFX_DIR, 'ROOM%02d.GFX' % room), 'rb').read(), 10)[0]
        px = 0
        for k, item in enumerate(sys.argv[3].split(',')):
            keys, n = item.split(':')
            n = int(n) - (1 if k == 0 else 0)           # el primer paso pierde un fotograma (el del arranque)
            if 'N' in keys or 'B' in keys:
                px = 0                                  # al cambiar de sala la camara vuelve a 0
            if 'P' in keys:
                px = min(px + n, npos * 8)
            if 'O' in keys:
                px = max(0, px - n)
        if (cam, fine) != (px // 8, px % 8):
            print('FALLA: esperaba camara %d fino %d' % (px // 8, px % 8))
            return 1
    b = L.load_lfl(os.path.join(d, '%02d.LFL' % room))
    w, h, img0 = L.decode_room(b)
    emap = L.default_map({})
    img = [[emap[p] for p in row] for row in img0]
    cfg = L.read_cfg(os.path.join(os.path.dirname(L.__file__), 'gfx_rooms.cfg')).get(room, {})
    L.METRIC, L.POWER, L.SAL, L.CENTROID = 'color', 0.5, 0.0, False         # los valores por omision de lfl2gfx.py
    L.RARITY = cfg.get('rarity', 0.5)
    L.PROTECT = cfg.get('protect', [])
    L.KEEP = cfg.get('keep', [])
    try:
        room_obj = L.scumm2.Room(d, room)
    except Exception:
        room_obj = None
    pool = L.plan_pool(room_obj, emap, cfg.get('pool', L.POOL_MAX))      # la reserva de objetos le quita tiles al fondo
    render, cur, ntiles, maxwin, err0 = L.convert_windowed(w, h, img, cfg.get('tiles', 210) - pool, 33)
    bad = 0
    for r in range(16):
        for c in range(32):
            code = dump[DFILE + 1 + 33 * r + c]
            shape = bytes(dump[TILES + 8 * code:TILES + 8 * code + 8])
            if code >= 128:
                shape = bytes(v ^ 0xFF for v in shape)     # el hardware invierte los codigos >= 128
            color = bytes(dump[COLORS + 8 * code:COLORS + 8 * code + 8])
            if (shape, color) != L.tile_bytes(cur[cam + c][r]):
                bad += 1
                if bad <= 5:
                    print('  celda (%d,%d) codigo %d distinta' % (c, r, code))
    # la columna 33 (la que asoma con el scroll fino): su tile, o el blanco en la ultima posicion
    npos = struct.unpack_from('<H', open(os.path.join(GFX_DIR, 'ROOM%02d.GFX' % room), 'rb').read(), 10)[0]
    for r in range(16):
        code = dump[DFILE + 1 + 33 * r + 32]
        if cam >= npos:
            bad += code != 216
            continue
        shape = bytes(dump[TILES + 8 * code:TILES + 8 * code + 8])
        if code >= 128:
            shape = bytes(v ^ 0xFF for v in shape)
        color = bytes(dump[COLORS + 8 * code:COLORS + 8 * code + 8])
        if (shape, color) != L.tile_bytes(cur[cam + 32][r]):
            bad += 1
    txt = ''.join(chr(dump[DFILE + 1 + 17 * 33 + 1 + k] - 216) for k in range(24))
    print('  estado (codigos ROM):', [dump[DFILE + 1 + 17 * 33 + 1 + k] - 216 for k in range(21)])
    print('OK' if not bad else 'FALLA: %d celdas' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
