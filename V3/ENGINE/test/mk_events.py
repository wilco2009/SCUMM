#!/usr/bin/env python3
"""Fase 7: un fichero de sucesos de entrada ("fotograma tipo [a b]": click, move, rclick, key, esc; a, b en pixeles de la pantalla del ZX81; para key, a = la tecla) ->
la variable TS_POKE de test_scumm (IT_KIND, IT_X, IT_Y, IT_KEY de ui3.asm: el suceso de prueba que in_poll usa en lugar del teclado y el raton). Uso: mk_events.py eventos.txt scumm.sym"""
import sys

KIND = {'click': 1, 'rclick': 2, 'key': 3, 'esc': 4, 'move': 5, 'restart': 6}
sym = {}
for ln in open(sys.argv[2]):
    p = ln.split()
    if len(p) == 3 and p[1] == 'EQU':
        sym[p[0]] = int(p[2].rstrip('Hh'), 16)
out = []
last = (0, 0)                                            # 10f: una tecla no mueve el raton (in_poll copia IT_X/IT_Y a cur_x/cur_y con cualquier suceso)
for ln in open(sys.argv[1]):
    if not ln.strip() or ln.startswith('#'):
        continue
    p = ln.split()
    f, kind, a = int(p[0]), p[1], [int(x) for x in p[2:]]
    if kind == 'room':                                   # cargar una sala (DBG_ROOM de scumm.asm)
        out.append('%d:%X:%X' % (f, sym['DBG_ROOM'], a[0] & 255))
        out.append('%d:%X:%X' % (f, sym['DBG_ROOM'] + 1, a[0] >> 8))
        continue
    if kind == 'snd':                                    # fase 8: un sonido de depuracion (DBG_SND de scumm.asm): operacion (1 empezar, 2 parar, 3 parar todo) y sonido
        out.append('%d:%X:%X' % (f, sym['DBG_SND'], a[1] & 255))
        out.append('%d:%X:%X' % (f, sym['DBG_SND'] + 1, a[0]))
        continue
    if kind in ('save', 'load'):                         # fase 9: guardar / cargar la ranura a[0] (DBG_SAVE de scumm.asm): operacion (1 guardar, 2 cargar) y ranura
        out.append('%d:%X:%X' % (f, sym['DBG_SAVE'], a[0] & 31))
        out.append('%d:%X:%X' % (f, sym['DBG_SAVE'] + 1, 1 if kind == 'save' else 2))
        continue
    if kind == 'script':                                 # un script global (DBG_START de scumm.asm)
        out.append('%d:%X:%X' % (f, sym['DBG_START'], a[0] & 255))
        out.append('%d:%X:%X' % (f, sym['DBG_START'] + 1, a[0] >> 8))
        continue
    if kind in ('click', 'move'):
        last = tuple((a + [0, 0])[:2])
    x, y = last
    key = a[0] if kind == 'key' else 0
    for off, val in ((sym['IT_X'], x & 255), (sym['IT_X'] + 1, x >> 8), (sym['IT_Y'], y & 255), (sym['IT_Y'] + 1, y >> 8),
                     (sym['IT_KEY'], key & 255), (sym['IT_KEY'] + 1, key >> 8), (sym['IT_KIND'], KIND[kind])):
        out.append('%d:%X:%X' % (f, off, val))
print(','.join(out))
