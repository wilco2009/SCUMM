#!/usr/bin/env python3
"""Convierte un guion de eventos (el de agi_vm.py: ciclo:tipo:valor ...) en EVENTS.BIN para el Z80.

Uso: mkevents.py SALIDA CICLOS "guion"

EVENTS.BIN: u16 ciclos a ejecutar, y por evento u16 ciclo, u8 tipo (1 text, 2 str, 3 key, 4 ctrl, 5 dir), u8 longitud y los bytes
(text/str: la cadena; key/ctrl/dir: un byte con el numero); acaba en $FFFF; relleno hasta 8192 bytes.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi_vm

KINDS = {'text': 1, 'str': 2, 'key': 3, 'ctrl': 4, 'dir': 5}


def build(cycles, script):
    ev = []
    for item in agi_vm.parse_script(script):
        c, k, v = item.split(':', 2)
        ev.append((int(c), k, v))
    ev.sort(key=lambda e: e[0])                   # estable: el orden dentro de un ciclo se conserva
    out = bytearray([cycles & 255, cycles >> 8])
    for c, k, v in ev:
        if k in ('text', 'str'):
            b = v.encode('latin-1')[:60]
        else:
            b = bytes([int(v) & 255])
        out += bytes([c & 255, c >> 8, KINDS[k], len(b)]) + b
    out += b'\xff\xff'
    assert len(out) <= 8192
    return bytes(out) + bytes(8192 - len(out))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    with open(argv[1], 'wb') as f:
        f.write(build(int(argv[2]), argv[3] if len(argv) > 3 else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
