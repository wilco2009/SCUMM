#!/usr/bin/env python3
"""Convierte las logicas de un juego AGI v2 a ficheros para el Z80.

Uso:  agi2log.py JUEGO SALIDA [n ...]

LOGnnn.AGL  u16 tamano del codigo + el codigo (el bytecode tal cual)
LOGnnn.MSG  la seccion de mensajes descifrada: u8 cuantos, u16 desplazamientos (0 = no hay) desde el principio del texto, y el texto con 0 final
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi_read as ag


def convert(d):
    size = d[0] | (d[1] << 8)
    agl = bytes(d[:2 + size])
    ms = size + 2
    n = d[ms]
    tstart = ms + 3 + 2 * n
    text = bytearray(d[tstart:])
    for i in range(len(text)):
        text[i] ^= ag.KEY[i % len(ag.KEY)]
    offs = bytearray()
    for i in range(n):
        p = d[ms + 3 + 2 * i] | (d[ms + 4 + 2 * i] << 8)
        q = 0 if p == 0 else p + ms + 1 - tstart
        offs += bytes((q & 255, q >> 8))
    return agl, bytes([n]) + bytes(offs) + bytes(text)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = ag.Game(argv[1])
    os.makedirs(argv[2], exist_ok=True)
    sel = [int(a) for a in argv[3:]] or g.present('LOG')
    tot = 0
    for n in sel:
        d = g.resource('LOG', n)
        if d is None:
            continue
        agl, msg = convert(d)
        with open(os.path.join(argv[2], 'LOG%03d.AGL' % n), 'wb') as f:
            f.write(agl)
        with open(os.path.join(argv[2], 'LOG%03d.MSG' % n), 'wb') as f:
            f.write(msg)
        tot += len(agl) + len(msg)
    # inventario (sala de cada objeto) y duracion de los sonidos (1/60 s), para el Z80
    inv = bytearray(256)
    for i, room, _ in ag.objects(argv[1]):
        if i < 256:
            inv[i] = room
    with open(os.path.join(argv[2], 'INVROOM.BIN'), 'wb') as f:
        f.write(inv)
    snd = bytearray(512)
    vm = None
    import agi_vm
    vm = agi_vm.Interp(argv[1], True)
    for n in g.present('SND'):
        t = vm.sound_ticks(n)
        snd[2 * n] = t & 255
        snd[2 * n + 1] = t >> 8
    with open(os.path.join(argv[2], 'SNDLEN.BIN'), 'wb') as f:
        f.write(snd)
    # cabeceras de las vistas: 256 desplazamientos u16 (0 = no hay) y, por vista, nloops, celdas de cada bucle y (ancho, alto) de cada celda
    idx = bytearray(512)
    blob = bytearray()
    for n in g.present('VIEW'):
        d = g.resource('VIEW', n)
        if not d:
            continue
        loops = ag.view_cells(d)[1]
        off = 512 + len(blob)
        idx[2 * n] = off & 255
        idx[2 * n + 1] = off >> 8
        blob.append(len(loops))
        blob.extend(len(l) for l in loops)
        for l in loops:
            for c in l:
                blob.extend((c[0], c[1]))
    hdr = bytes(idx) + bytes(blob)
    assert len(hdr) <= 8192, 'VIEWS.HDR no cabe en una pagina: %d' % len(hdr)
    with open(os.path.join(argv[2], 'VIEWS.HDR'), 'wb') as f:
        f.write(hdr + bytes(8192 - len(hdr)))
    print('%d logicas, %d bytes' % (len(sel), tot))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
