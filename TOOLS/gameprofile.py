#!/usr/bin/env python3
"""Perfil de juego: lee un fichero .cfg (ver SCUMM/games/maniac.cfg) y lo convierte en el bloque de 256 bytes que el motor carga de DATA.BIN
en PROF (SCUMM/ENGINE/progdata.inc). Todo lo propio de un juego va ahi y nunca en el codigo del motor.

Formato del bloque (little endian):
  +0   version (1)
  +1   fila del inventario, +2 fila de los verbos, +3 fila de la frase
  +4   columna_mul, +5 columna_sum, +6 columna_desplaza, +7 fila_resta
  +8   posicion de las dos cifras de la sala en el nombre del fichero (la del primer 0 de "00")
  +9   u16 desplazamiento (desde el principio del bloque) de las etiquetas de verbos: (id, texto, 0)... y $FF
  +11  u16 desplazamiento de las preposiciones: cuatro textos acabados en 0
  +13  u16 desplazamiento del nombre de los ficheros de sala
  +16  10 x u16: valor de VAR_KEYPRESS para las teclas 1 2 3 4 5 6 7 8 9 0 (0: sin uso)
  +36  los textos
"""
import struct
import sys

SIZE = 256
FIRST_TEXT = 36
KEYS = '1234567890'


def parse(path):
    sec, cfg = None, {}
    with open(path, encoding='utf-8') as f:
        for ln in f:
            ln = ln.split('#')[0].strip()
            if not ln:
                continue
            if ln.startswith('['):
                sec = ln.strip('[]').strip().lower()
                continue
            k, _, v = ln.partition('=')
            cfg.setdefault(sec, {})[k.strip().lower()] = v.strip()
    return cfg


def text(v):
    v = v.strip()
    return v[1:-1] if len(v) >= 2 and v[0] == v[-1] == '"' else v


def build(path):
    c = parse(path)
    ui, tx, fi, ky = c['interfaz'], c['textos'], c['ficheros'], c.get('teclas', {})
    out = bytearray(SIZE)
    out[0] = 1
    for i, k in enumerate(('inventario_fila', 'verbos_fila', 'frase_fila', 'columna_mul', 'columna_sum', 'columna_desplaza', 'fila_resta')):
        out[1 + i] = int(ui[k])
    tpl = text(fi['sala'])
    out[8] = tpl.index('00')
    pos = FIRST_TEXT
    out[9:11] = struct.pack('<H', pos)
    for k in sorted(tx, key=lambda s: s):
        if k.startswith('verbo_'):
            lab = text(tx[k]).encode('ascii')
            out[pos] = int(k[6:])
            out[pos + 1:pos + 1 + len(lab)] = lab
            pos += len(lab) + 2
    out[pos] = 0xFF
    pos += 1
    out[11:13] = struct.pack('<H', pos)
    for i in range(1, 5):
        t = text(tx['prep_%d' % i]).encode('ascii')
        out[pos:pos + len(t)] = t
        pos += len(t) + 1
    out[13:15] = struct.pack('<H', pos)
    t = tpl.encode('ascii')
    out[pos:pos + len(t)] = t
    pos += len(t) + 1
    assert pos <= SIZE, 'el perfil no cabe en %d bytes (%d)' % (SIZE, pos)
    for i, k in enumerate(KEYS):
        if k in ky:
            struct.pack_into('<H', out, 16 + 2 * i, int(ky[k]))
    return bytes(out)


if __name__ == '__main__':
    b = build(sys.argv[1])
    print(len(b), 'bytes; textos hasta', max(i for i, v in enumerate(b) if v) + 1)
