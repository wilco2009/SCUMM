#!/usr/bin/env python3
"""Convierte las logicas de un juego AGI v2 a ficheros para el Z80.

Uso:  agi2log.py JUEGO SALIDA [n ...]

LOGnnn.AGL  u16 tamano del codigo + el codigo (el bytecode tal cual)
LOGnnn.MSG  la seccion de mensajes descifrada: u8 cuantos, u16 desplazamientos + 1 (0 = no hay) desde el principio del texto, y el texto con 0 final
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi_read as ag
import agi2spr


def convert(d, ov=None):
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
        q = 0 if p == 0 else p + ms + 1 - tstart + 1
        offs += bytes((q & 255, q >> 8))
    if ov:                                  # textos sustitutos (agi_read.HELP): el bloque de texto se rehace
        ms = ag.help_override(ov[0], ov[1], ag.logic_messages(d))
        offs = bytearray()
        text = bytearray()
        for m in ms:
            q = 0 if m is None else len(text) + 1
            offs += bytes((q & 255, q >> 8))
            if m is not None:
                text += m.encode('latin-1') + b'\0'
        n = len(ms)
    return agl, bytes([n]) + bytes(offs) + bytes(text)


def sub(base, folder, name):
    """Ruta de un fichero de salida en su carpeta por tipo (LOG, VIEW, DATA...), que se crea si hace falta."""
    d = os.path.join(base, folder)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, name)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = ag.Game(argv[1])
    agi2spr.set_game(argv[1])
    os.makedirs(argv[2], exist_ok=True)
    sel = [int(a) for a in argv[3:]] or g.present('LOG')
    tot = 0
    for n in sel:
        d = g.resource('LOG', n)
        if d is None:
            continue
        d = ag.testboot(n, ag.game_fix(argv[1], n, d))
        agl, msg = convert(d, (argv[1], n))
        with open(sub(argv[2], 'LOG', 'LOG%03d.AGL' % n), 'wb') as f:
            f.write(agl)
        with open(sub(argv[2], 'LOG', 'LOG%03d.MSG' % n), 'wb') as f:
            f.write(msg)
        tot += len(agl) + len(msg)
    # inventario (sala de cada objeto) y duracion de los sonidos (1/60 s), para el Z80
    inv = bytearray(256)
    for i, room, _ in ag.objects(argv[1]):
        if str(i) in os.environ.get('AGI_INV255', '').split(','):
            room = 255                      # solo para pruebas: objetos que lleva el ego desde el principio
        if i < 256:
            inv[i] = room
    with open(sub(argv[2], 'DATA', 'INVROOM.BIN'), 'wb') as f:
        f.write(inv)
    snd = bytearray(512)
    vm = None
    import agi_vm
    vm = agi_vm.Interp(argv[1], True)
    for n in g.present('SND'):
        t = vm.sound_ticks(n)
        snd[2 * n] = t & 255
        snd[2 * n + 1] = t >> 8
    names = [n[:36] for n in vm.inv_names][:255]
    blob = bytes([len(names)]) + b''.join(n.encode('latin-1', 'replace') + b'\x00' for n in names)
    assert len(blob) <= 8192
    with open(sub(argv[2], 'DATA', 'INVNAMES.BIN'), 'wb') as f:     # el numero de objetos y sus nombres, para la pantalla del inventario (status)
        f.write(blob + bytes(8192 - len(blob)))
    with open(sub(argv[2], 'DATA', 'SNDLEN.BIN'), 'wb') as f:
        f.write(snd)
    # cabeceras de las vistas: 256 desplazamientos u16 (0 = no hay) y, por vista, nloops, celdas de cada bucle y (ancho, alto) de cada celda
    idx = bytearray(512)
    blob = bytearray()
    for n in g.present('VIEW'):
        d = g.resource('VIEW', n)
        if not d:
            continue
        loops = ag.view_cells(d)[1]
        if len(d) <= 8190:
            with open(sub(argv[2], 'VIEW', 'VIEW%03d.GFX' % n), 'wb') as f:   # u16 tamano + el recurso tal cual (los sprites lo leen de aqui)
                f.write(bytes((len(d) & 255, len(d) >> 8)) + bytes(d))
        else:
            print('VIEW %d: %d bytes, no cabe en una pagina' % (n, len(d)))
        off = 512 + len(blob)
        idx[2 * n] = off & 255
        idx[2 * n + 1] = (off >> 8) | (0x80 if agi2spr.frozen(n) else 0)       # bit 15: vista congelada (agi2spr.FREEZE_VIEWS)
        blob.append(len(loops))
        blob.extend(len(l) for l in loops)
        for l in loops:
            for c in l:
                blob.extend((c[0], c[1]))
    hdr = bytes(idx) + bytes(blob)
    assert len(hdr) <= 8192, 'VIEWS.HDR no cabe en una pagina: %d' % len(hdr)
    with open(sub(argv[2], 'DATA', 'VIEWS.HDR'), 'wb') as f:
        f.write(hdr + bytes(8192 - len(hdr)))
    import agi_read
    tok = agi_read.words_tok(argv[1])
    assert len(tok) <= 8190
    with open(sub(argv[2], 'DATA', 'WORDS.BIN'), 'wb') as f:
        f.write(bytes((len(tok) & 255, len(tok) >> 8)) + tok + bytes(8190 - len(tok)))
    print('%d logicas, %d bytes' % (len(sel), tot))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
