#!/usr/bin/env python3
"""Medidas de graficos y texto de SCI0 frente a los modos del SD81.

Uso: graficos.py CARPETA_JUEGO NOMBRE [salida_png]
- Imagenes: se dibujan como ScummVM (sci0pic) y se cuentan, para 160x200 a 8 bpp
  con "undithering" (cada pareja de tramado = un color mezclado, como
  GfxPalette::setEGA de ScummVM): colores distintos por imagen y cuantas
  celdas de 2x1 pixeles tienen dos colores distintos (lo que se pierde al
  pasar de 320 a 160 columnas).
- Vistas: celdas reducidas a 160 de ancho; mosaicos de 8x8 y filas de 8 con mas
  de 2 colores (limite de los sprites por hardware del SD81).
- Texto: ancho medio de los glifos de las fuentes con el texto real del juego.
"""
import collections
import json
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sci0res import ResMan  # noqa: E402
import sci0pic  # noqa: E402

EGA = [(0, 0, 0), (0, 0, 0xAA), (0, 0xAA, 0), (0, 0xAA, 0xAA), (0xAA, 0, 0), (0xAA, 0, 0xAA), (0xAA, 0x55, 0),
       (0xAA, 0xAA, 0xAA), (0x55, 0x55, 0x55), (0x55, 0x55, 0xFF), (0x55, 0xFF, 0x55), (0x55, 0xFF, 0xFF),
       (0xFF, 0x55, 0x55), (0xFF, 0x55, 0xFF), (0xFF, 0xFF, 0x55), (0xFF, 0xFF, 0xFF)]


def png(path, w, h, rgb):
    raw = b''.join(b'\0' + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def pair_key(a, b):
    return (min(a, b), max(a, b))


def mix(k):
    a, b = EGA[k[0]], EGA[k[1]]
    return tuple((x + y) // 2 for x, y in zip(a, b))


def pics(rm, outdir=None, name=''):
    res = []
    for k in rm.keys('pic'):
        d = rm.get(k)
        sc = sci0pic.Screen()
        sc.draw_pic(d)
        pairs = sc.visual_pairs()
        W = sci0pic.W
        y0, y1 = sci0pic.PIC_TOP, sci0pic.H
        cols = collections.Counter()
        dith = 0
        diff = 0
        diff_dith_ok = 0
        cells = 0
        for y in range(y0, y1):
            for x in range(0, W, 2):
                a = pairs[y * W + x]
                b = pairs[y * W + x + 1]
                ka, kb = pair_key(*a), pair_key(*b)
                cols[ka] += 1
                cells += 1
                if a[0] != a[1]:
                    dith += 1
                if ka != kb:
                    diff += 1
        ega = sc.visual_ega()
        # colores EGA puros si se reduce 320->160 tomando el pixel izquierdo
        res.append({'pic': k[1], 'parejas': len(cols), 'tramado_%': round(100 * dith / cells, 1),
                    'celdas_2x1_distintas_%': round(100 * diff / cells, 2),
                    'mezcla_px_bytes': len(d)})
        if outdir:
            rgb = bytearray()
            for y in range(H0, sci0pic.H):
                for x in range(W):
                    rgb += bytes(EGA[ega[y * W + x]])
            png(os.path.join(outdir, '%s_pic%03d_ega.png' % (name, k[1])), W, sci0pic.H - H0, rgb)
            rgb = bytearray()
            for y in range(H0, sci0pic.H):
                for x in range(0, W, 2):
                    c = mix(pair_key(*pairs[y * W + x]))
                    rgb += bytes(c) * 2
            png(os.path.join(outdir, '%s_pic%03d_160.png' % (name, k[1])), W, sci0pic.H - H0, rgb)
    return res


H0 = sci0pic.PIC_TOP


def views(rm):
    tot = collections.Counter()
    per = []
    for k in rm.keys('view'):
        v = sci0pic.View(rm.get(k))
        vt = collections.Counter()
        for li, loop in enumerate(v.loops):
            for ci in range(len(loop)):
                px, w, h, key = v.pixels(li, ci)
                w2 = (w + 1) // 2
                # reduccion a 160: pixel izquierdo de cada pareja
                small = [[px[y * w + 2 * x] for x in range(w2) if 2 * x < w] for y in range(h)]
                tw = (w2 + 7) // 8
                th = (h + 7) // 8
                tiles = 0
                for ty in range(th):
                    for tx in range(tw):
                        if any(small[y][x] != key for y in range(ty * 8, min(h, ty * 8 + 8))
                               for x in range(tx * 8, min(w2, tx * 8 + 8))):
                            tiles += 1
                rows = rows3 = 0
                for y in range(h):
                    for tx in range(tw):
                        seg = [c for c in small[y][tx * 8:tx * 8 + 8] if c != key]
                        if seg:
                            rows += 1
                            if len(set(seg)) > 2:
                                rows3 += 1
                vt['celdas'] += 1
                vt['mosaicos'] += tiles
                vt['filas8'] += rows
                vt['filas8_mas2col'] += rows3
                vt['ancho160_max'] = max(vt['ancho160_max'], w2)
                vt['mosaicos_max'] = max(vt['mosaicos_max'], tiles)
                vt['bytes_160_4bpp'] += (w2 * h + 1) // 2
        per.append((k[1], dict(vt)))
        for kk in ('celdas', 'mosaicos', 'filas8', 'filas8_mas2col', 'bytes_160_4bpp'):
            tot[kk] += vt[kk]
        tot['mosaicos_max'] = max(tot['mosaicos_max'], vt['mosaicos_max'])
    return dict(tot), per


def fonts_text(rm):
    out = {}
    texts = []
    for k in rm.keys('text'):
        texts += [t.decode('latin-1') for t in rm.get(k).split(b'\0') if t]
    for k in rm.keys('script'):
        b = rm.get(k)
        p = 0
        while p + 4 <= len(b):
            t, sz = struct.unpack_from('<HH', b, p)
            if t == 0 or sz == 0:
                break
            if t == 5:
                texts += [s.decode('latin-1') for s in b[p + 4:p + sz].split(b'\0') if len(s) > 3]
            p += sz
    chars = ''.join(texts)
    for k in rm.keys('font'):
        f = sci0pic.Font(rm.get(k))
        ws = [f.cw(c) for c in chars if ord(c) < f.n and c != '\n']
        out[k[1]] = {'alto': f.h, 'ancho_medio': round(sum(ws) / len(ws), 2) if ws else 0,
                     'caracteres_en_320': round(320 / (sum(ws) / len(ws)), 1) if ws else 0}
    lens = [len(t) for t in texts]
    return out, {'cadenas': len(texts), 'caracteres': len(chars),
                 'longitud_media': round(sum(lens) / len(lens), 1) if lens else 0}


def main():
    path, name = sys.argv[1], sys.argv[2]
    outdir = sys.argv[3] if len(sys.argv) > 3 else None
    if outdir:
        os.makedirs(outdir, exist_ok=True)
    rm = ResMan(path)
    p = pics(rm, outdir, name)
    vt, vp = views(rm)
    f, t = fonts_text(rm)
    res = {'juego': name, 'imagenes': p, 'vistas': vt, 'fuentes': f, 'texto': t}
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'medidas')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, name + '_graficos.json'), 'w', encoding='utf-8') as fh:
        json.dump(res, fh, indent=1, ensure_ascii=False)
    pa = [x['parejas'] for x in p]
    dd = [x['celdas_2x1_distintas_%'] for x in p]
    tr = [x['tramado_%'] for x in p]
    print('%s: %d imagenes; colores mezclados por imagen media %.1f max %d; tramado %.1f %%; '
          'celdas 2x1 distintas media %.2f %% max %.2f %%' % (
              name, len(p), sum(pa) / len(pa), max(pa), sum(tr) / len(tr), sum(dd) / len(dd), max(dd)))
    print('  vistas:', vt)
    print('  fuentes:', f, t)


if __name__ == '__main__':
    main()
