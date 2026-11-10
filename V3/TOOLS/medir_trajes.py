#!/usr/bin/env python3
"""Tamaño de los personajes: trajes de Indy3 (v3) frente a Zak y Maniac (v2), con costume2.py (formato 0x58, el mismo).

Para cada traje y direccion se compone la postura quieta (la animacion de inicio y encima la de quieto, como
ScummVM: una animacion solo cambia los miembros que nombra) y el primer paso de la de andar, y se mide:
  - el rectangulo del personaje (ancho x alto en pixeles de 320x200),
  - los sprites de 8x8 que necesita en el modo del interprete v2 (escala 3/4, como cells_of de costume2.py),
  - los pixeles de celda que hay que descomprimir (suma de ancho x alto de los miembros).
Frames: v3 init 1, andar 2, quieto 3 (Actor::initActor, version >= 3); v2 init 2, andar 0, quieto 1 (Actor_v2).
Los codigos de celda 0x79 y mayores no son imagenes (ScummVM los salta en las versiones de 256 colores) y se ignoran.

Uso: python medir_trajes.py "../Indy Last Crusade" "../../V2/Zak McKracken" "../../V2/ManiacMansionDOS" ../medidas/trajes.json
"""
import json
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import costume2 as C       # noqa: E402
import scumm2              # noqa: E402
import scumm3res as R3     # noqa: E402


def compose(c, anims):
    limbs = {}
    for a in anims:
        for k, v in c.anim_limbs(a).items():
            if v is None:
                limbs.pop(k, None)
            else:
                limbs[k] = v
    xm = ym = 0
    rects = []
    area = 0
    for limb in range(16):
        if limb not in limbs:
            continue
        s, e, h = limbs[limb]
        code = c.b[c.cmds + s] & 0x7F
        if code >= 0x79:
            continue
        p = C.u16(c.b, c.limb_tab[limb] + code * 2)
        if p + 12 > len(c.b):
            continue
        w, hh = C.u16(c.b, p), C.u16(c.b, p + 2)
        if w > 255 or hh > 255 or w == 0 or hh == 0:
            continue
        rx, ry, mx, my = C.s16(c.b, p + 4), C.s16(c.b, p + 6), C.s16(c.b, p + 8), C.s16(c.b, p + 10)
        x0, y0 = xm + rx, ym + ry
        xm += mx
        ym -= my
        rects.append((x0, y0, x0 + w, y0 + hh))
        area += w * hh
    if not rects:
        return None
    x0 = min(r[0] for r in rects)
    y0 = min(r[1] for r in rects)
    x1 = max(r[2] for r in rects)
    y1 = max(r[3] for r in rects)
    w, h = x1 - x0, y1 - y0
    cw, ch = -(-(w * 3 // 4) // 8) + 1, -(-(h * 3 // 4) // 8) + 1     # a 3/4 y en cualquier pixel: una fila/columna mas
    return dict(w=w, h=h, sprites=cw * ch, sprites_1a1=(-(-w // 8) + 1) * (-(-h // 8) + 1), cel_px=area, limbs=len(rects))


def measure(get, n, frames):
    init, walk, stand = frames
    out = []
    for i in range(n):
        data = get(i)
        if not data:
            continue
        try:
            c = C.Costume(data)
        except Exception:
            continue
        poses = []
        for d in range(4):
            for anims in ((init * 4 + d, stand * 4 + d), (init * 4 + d, walk * 4 + d)):
                try:
                    m = compose(c, anims)
                except Exception:
                    m = None
                if m and m['h'] >= 24:          # solo personajes (no efectos ni objetos pequeños)
                    poses.append(m)
        if poses:
            out.append(dict(costume=i, bytes=len(data), anims=c.num_anim,
                            w=max(p['w'] for p in poses), h=max(p['h'] for p in poses),
                            sprites=max(p['sprites'] for p in poses), sprites_1a1=max(p['sprites_1a1'] for p in poses),
                            cel_px=round(st.mean(p['cel_px'] for p in poses)), limbs=max(p['limbs'] for p in poses)))
    return out


def summ(rows):
    def c(k):
        v = [r[k] for r in rows]
        return dict(mediana=st.median(v), p90=sorted(v)[int(0.9 * len(v))], max=max(v))
    return dict(trajes=len(rows), w=c('w'), h=c('h'), sprites=c('sprites'), sprites_1a1=c('sprites_1a1'),
                cel_px=c('cel_px'), limbs=c('limbs'), bytes=c('bytes'), anims=c('anims'))


def main():
    d3, dz, dm, out = sys.argv[1:5]
    ix3 = R3.Index(d3)
    res = {'indy3': measure(lambda i: ix3.resource('costume', i), len(ix3.res['costume']), (1, 2, 3))}
    for name, d in (('zak', dz), ('maniac', dm)):
        ix = scumm2.Index(d)
        res[name] = measure(lambda i, d=d, ix=ix: scumm2.resource(d, ix, 'costume', i) if scumm2.resource_ok(d, ix, 'costume', i) else None,
                            len(ix.res['costume']), (2, 0, 1))
    res['resumen'] = {k: summ(v) for k, v in res.items()}
    with open(out, 'w') as f:
        json.dump(res, f, indent=1)
    for k, v in res['resumen'].items():
        print(k, json.dumps(v))


if __name__ == '__main__':
    main()
