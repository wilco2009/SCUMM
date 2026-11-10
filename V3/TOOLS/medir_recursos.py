#!/usr/bin/env python3
"""Tamaños de los recursos por sala: SCUMM v3 (Indy3 EGA) frente a v2 (Zak, Maniac Mansion), con el mismo criterio.

Cada recurso de sala se parte en bloques (cada uno llega hasta el siguiente que empieza): cabecera, cajas, imagen
(franjas + mascara en v3; columnas en v2, y su mascara), imagenes de objetos (OBIM), codigo de objetos (OBCD),
entrada (ENCD), salida (EXCD) y, solo en v3, scripts locales. Ademas: los recursos globales (scripts, trajes, sonidos)
y la conversion al HiRes 8x1 (2 colores por franja de 8x1, la regla del modo actual), con row_spec de lfl2gfx.py.

Uso (desde SCUMM/V3/TOOLS):
  python medir_recursos.py "../Indy Last Crusade" "../../V2/Zak McKracken" "../../V2/ManiacMansionDOS" ../medidas/recursos.json
"""
import json
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import scumm3res as S3          # noqa: E402
import scumm2 as S2             # noqa: E402
import lfl2gfx as L             # noqa: E402

EMAP = L.default_map({})


def hires_loss(img, w, h):
    """(% de pixeles que cambian, % de franjas 8x1 con mas de 2 colores) al pasar a 2 colores por franja."""
    changed = cells3 = ncell = 0
    for y in range(h):
        row = [EMAP[p] for p in img[y]]
        for x in range(0, w - w % 8, 8):
            pix = tuple(row[x:x + 8])
            out = L.row_spec(pix)[0]
            changed += sum(a != b for a, b in zip(out, pix))
            ncell += 1
            if len(set(pix)) > 2:
                cells3 += 1
    return 100.0 * changed / max(1, ncell * 8), 100.0 * cells3 / max(1, ncell)


def colors(img):
    return len(set(p for row in img for p in row))


def v3_rooms(d):
    ix = S3.Index(d)
    out = []
    for rn in ix.rooms():
        r = S3.Room(ix, rn)
        img, n_img, mask, n_mask = r.image()
        loss, c3 = hires_loss(img, r.width, r.height)
        nobjimg = sum(1 for o in r.objects if r.object_image(o) is not None)
        code = r.by_kind.get('obcd', 0) + r.by_kind.get('encd', 0) + r.by_kind.get('excd', 0) + r.by_kind.get('local', 0)
        bx, matrix = r.boxes()
        out.append(dict(room=rn, w=r.width, h=r.height, size=r.size, file=len(r.file),
                        blocks=r.by_kind, img_bytes=n_img, mask_bytes=n_mask, objects=r.num_objects,
                        objects_with_image=nobjimg, local_scripts=len(r.local_scripts),
                        verbs=sum(len(o.verbs) for o in r.objects), code=code, boxes=len(bx), matrix=len(matrix),
                        colors=colors(img), hires_px_loss=round(loss, 2), hires_cells3=round(c3, 2)))
    return ix, out


def v2_rooms(d):
    ix = S2.Index(d)
    out = []
    for rn in range(len(ix.res['room'])):
        if not os.path.exists(os.path.join(d, '%02d.LFL' % rn)):
            continue
        try:
            r = S2.Room(d, rn)
        except Exception:
            continue
        b = r.file
        starts = [(0, 'cabecera'), (r.image_off, 'imagen')]
        if r.box_off:
            starts.append((r.box_off, 'cajas'))
        mo = S2.u16(b, 0x0C)
        if mo and mo < r.size:
            starts.append((mo, 'mascara'))
        for o in r.objects:
            if o.obim:
                starts.append((o.obim, 'obim'))
            starts.append((o.obcd, 'obcd'))
        if r.excd_off:
            starts.append((r.excd_off, 'excd'))
        if r.encd_off:
            starts.append((r.encd_off, 'encd'))
        starts = sorted(set(starts))
        kinds = {}
        for k, (a, kind) in enumerate(starts):
            e = starts[k + 1][0] if k + 1 < len(starts) else r.size
            kinds[kind] = kinds.get(kind, 0) + (e - a)
        try:
            w, h, img = L.decode_room(b)
            loss, c3 = hires_loss(img, w, h)
            ncol = colors(img)
        except Exception:
            loss = c3 = ncol = None
        code = kinds.get('obcd', 0) + kinds.get('encd', 0) + kinds.get('excd', 0)
        out.append(dict(room=rn, w=r.width, h=r.height, size=r.size, file=len(b), blocks=kinds,
                        objects=r.num_objects, verbs=sum(len(o.verbs) for o in r.objects), code=code,
                        boxes=len(r.boxes), colors=ncol,
                        hires_px_loss=None if loss is None else round(loss, 2),
                        hires_cells3=None if c3 is None else round(c3, 2)))
    return ix, out


def globals_sizes(ix, kinds, resource):
    res = {}
    for k in kinds:
        sizes = [len(x) for x in (resource(k, i) for i in range(len(ix.res[k]))) if x is not None]
        res[k] = dict(n=len(sizes), total=sum(sizes), median=st.median(sizes) if sizes else 0,
                      max=max(sizes) if sizes else 0)
    return res


def summary(name, rooms):
    def col(f):
        v = [f(r) for r in rooms if f(r) is not None]
        return dict(media=round(st.mean(v)), mediana=round(st.median(v)), max=max(v)) if v else None
    return dict(
        juego=name, salas=len(rooms),
        recurso_sala=col(lambda r: r['size']),
        fichero_sala=col(lambda r: r['file']),
        imagen_y_mascara=col(lambda r: r['blocks'].get('imagen', 0) + r['blocks'].get('mascara', 0)),
        obim=col(lambda r: r['blocks'].get('obim', 0)),
        codigo_sala=col(lambda r: r['code']),
        locales=col(lambda r: r['blocks'].get('local', 0)),
        objetos=col(lambda r: r['objects']),
        verbos=col(lambda r: r['verbs']),
        cajas=col(lambda r: r['boxes']),
        ancho=col(lambda r: r['w']),
        colores=col(lambda r: r['colors']),
        hires_px=col(lambda r: r['hires_px_loss']),
        hires_franjas3=col(lambda r: r['hires_cells3']),
    )


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 1
    d3, dz, dm, out = sys.argv[1:5]
    ix3, r3 = v3_rooms(d3)
    res = dict(indy3=dict(rooms=r3, globals=globals_sizes(ix3, ('script', 'costume', 'sound'), ix3.resource),
                          summary=summary('Indy3 EGA', r3)))
    for name, d in (('zak', dz), ('maniac', dm)):
        ix2, r2 = v2_rooms(d)

        def res2(k, i, d=d, ix2=ix2):
            return S2.resource(d, ix2, k, i) if S2.resource_ok(d, ix2, k, i) else None
        res[name] = dict(rooms=r2, globals=globals_sizes(ix2, ('script', 'costume', 'sound'), res2),
                         summary=summary(name, r2))
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(res, f, indent=1)
    for k in ('indy3', 'zak', 'maniac'):
        print(json.dumps(res[k]['summary'], ensure_ascii=False))
        print(json.dumps(res[k]['globals']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
