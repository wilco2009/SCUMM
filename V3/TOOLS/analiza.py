#!/usr/bin/env python3
"""Junta las medidas de SCUMM v3 (Indy3): memoria por sala, CPU estimada del Z80 y alturas de sala. Escribe una tabla.

Memoria por sala (lo que tendria que estar en la RAM paginada mientras se juega en ella):
  - .GFX en el formato HiRes 8x1 del interprete v2 (TOOLS/LFL2HR.md): 256 B de cabecera + por columna de 8 px,
    alto x 2 bytes (bitmap + atributos) + imagenes de objetos (columnas x alto x 2). Es una estimacion: lfl2hr.py
    comparte datos iguales y los objetos sin imagen no ocupan.
  - codigo de la sala (scripts locales, entrada, salida, verbos de objetos) y scripts globales que corren en ella
    (recorrido de scumm3vm.py), trajes visibles y sonidos que suenan.
CPU: bytecodes por fotograma (recorrido y arranque) por un coste por bytecode. v2: 150-400 T (estimacion de
claude/planning/scumm_interprete.md, sin medir); v3: 200-500 T (operandos de variable de 16 bits con locales, bits e
indirectas). Presupuesto: delta 6 (10 vueltas por segundo) a 3,25 MHz = 325.000 T.

Uso: python analiza.py "../Indy Last Crusade" ../medidas
"""
import json
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scumm3res as R      # noqa: E402

BUDGET = 3250000 // 10


def gfx_size(r):
    cols = r.width // 8
    size = 256 + cols * r.height * 2
    for o in r.objects:
        if r.object_image(o) is not None:
            size += (o.width // 8) * o.height * 2
    return size


def main():
    d, med = sys.argv[1], sys.argv[2]
    ix = R.Index(d)
    tour = json.load(open(os.path.join(med, 'indy3_salas.json')))
    boot = json.load(open(os.path.join(med, 'indy3_arranque.json')))
    rows = []
    heights = {}
    for s in tour['summary']:
        rn = s['room']
        if rn == 0 or s['frames'] < 20:
            continue
        r = R.Room(ix, rn)
        heights[r.height] = heights.get(r.height, 0) + 1
        code = r.by_kind.get('local', 0) + r.by_kind.get('encd', 0) + r.by_kind.get('excd', 0) + r.by_kind.get('obcd', 0)
        glob = sum(len(ix.resource('script', g) or b'') for g in s['globals'])
        cost = sum(len(ix.resource('costume', c) or b'') for c in s['costumes'] if c)
        snd = sum(len(ix.resource('sound', c) or b'') for c in s['sounds'])
        g = gfx_size(r)
        rows.append(dict(room=rn, w=r.width, h=r.height, recurso=r.size, gfx=g, codigo_sala=code, globales=glob,
                         ntrajes=len([c for c in s['costumes'] if c]), trajes=cost, sonidos=snd,
                         total=g + code + glob + cost + snd,
                         ops_mean=s['ops_mean'], ops_p90=s['ops_p90'], ops_max=s['ops_max'],
                         actores=s['actors_max'], mov=s['moving_mean'], cel_px=s['cel_px_mean'],
                         t_mean=round(s['ops_mean'] * 350), t_p90=round(s['ops_p90'] * 350)))
    allf = sorted(f['ops'] for f in tour['frames'] if f['room'] and not f['err'])
    bootf = sorted(f['ops'] for f in boot['frames'] if f['room'] == 1)

    def stat(k):
        v = [r[k] for r in rows]
        return dict(media=round(st.mean(v)), mediana=round(st.median(v)), max=max(v))
    res = dict(salas=len(rows), alturas=heights,
               memoria={k: stat(k) for k in ('gfx', 'codigo_sala', 'globales', 'trajes', 'sonidos', 'total', 'ntrajes')},
               cpu=dict(ops_sala=stat('ops_mean'), fotograma_p50=allf[len(allf) // 2], fotograma_p90=allf[int(.9 * len(allf))],
                        fotograma_p99=allf[int(.99 * len(allf))], fotograma_max=allf[-1],
                        pasillo_media=round(st.mean(bootf), 1), pasillo_p99=bootf[int(.99 * len(bootf))],
                        T_p99_500=allf[int(.99 * len(allf))] * 500, T_max_500=allf[-1] * 500, presupuesto=BUDGET),
               salas_gfx_mas_48k=[r['room'] for r in rows if r['gfx'] > 48 * 1024],
               filas=rows)
    with open(os.path.join(med, 'analisis.json'), 'w') as f:
        json.dump(res, f, indent=1)
    lines = ['| Sala | Ancho x alto | .GFX HiRes | Codigo sala | Globales | Trajes (n) | Sonidos | Total | Bytecodes media / p90 / max | Actores max | Pixeles de celda |',
             '|---:|---|---:|---:|---:|---|---:|---:|---|---:|---:|']
    for r in rows:
        lines.append('| %d | %dx%d | %d | %d | %d | %d (%d) | %d | %d | %s / %d / %d | %d | %d |' % (
            r['room'], r['w'], r['h'], r['gfx'], r['codigo_sala'], r['globales'], r['trajes'], r['ntrajes'], r['sonidos'],
            r['total'], r['ops_mean'], r['ops_p90'], r['ops_max'], r['actores'], r['cel_px']))
    with open(os.path.join(med, 'indy3_tabla.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print(json.dumps({k: v for k, v in res.items() if k != 'filas'}, indent=1))


if __name__ == '__main__':
    main()
