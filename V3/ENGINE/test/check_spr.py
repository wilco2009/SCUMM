#!/usr/bin/env python3
"""check_spr.py (fase 8): compara los sprites de los actores del volcado de test_scumm con la referencia en Python (V3/TOOLS/sprites3.py).
Uso: check_spr.py volcado.bin scumm.sym DATA.BIN"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'TOOLS'))
import pack_data3 as P3          # noqa: E402
import sprites3 as S             # noqa: E402

dump = open(sys.argv[1], 'rb').read()
sym = S.load_sym(sys.argv[2])
data = P3.Data(open(sys.argv[3], 'rb').read())
n, bad, exp = S.check_dump(dump, sym, data)
lg = dump[65536:131072]
print('sala %d, camara %d: sprites esperados %d, comprobados %d, distintos %d' % (lg[sym['CURROOM']], lg[sym['aq_cam']] | (lg[sym['aq_cam'] + 1] << 8), len(exp), n, bad))

# fase 8: la paleta de 16 que programo el motor tiene que ser la de _roomPalette y _shadowPalette (la memoria del volcado)
lgm = dump[65536:131072]
off = 131072 + 64 * 32 + 8 + 2 + 0x400
if len(dump) >= off + 33:
    on, p16 = dump[off], dump[off + 1:off + 33]
    tab = lgm[sym['pal16_tab']:sym['pal16_tab'] + 32]
    room = lgm[sym['ROOMPAL']:sym['ROOMPAL'] + 16]
    shadow = lgm[sym['SHADOWPAL']:sym['SHADOWPAL'] + 16]
    exp = bytearray()
    for k in range(16):
        c = shadow[room[k]]
        exp += tab[2 * c:2 * c + 2]
    if on and bytes(p16) != bytes(exp):
        print('paleta de 16: DISTINTA de la que dan roomPalette %s y shadowPalette %s' % (list(room), list(shadow)))
        bad += 1
    else:
        print('paleta de 16: %s (roomPalette %s, shadowPalette %s)' % ('igual' if on else 'sin programar', list(room), list(shadow)))
sys.exit(1 if bad else 0)
