#!/usr/bin/env python3
"""Junta las tandas de recorrido.sh en una tabla por sala (Markdown) y un resumen.

Uso: combinar.py PREFIJO [JSON_PARTIDA_NORMAL]
"""
import glob
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

MED = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'medidas')
Z80_HZ = 3250000
TICK = Z80_HZ / 60          # T-estados por tick de SCI (1/60 s)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    pre = sys.argv[1]
    rooms = {}
    runs = []
    for fn in sorted(glob.glob(os.path.join(MED, pre + '_*.json')), key=lambda f: int(f.rsplit('_', 1)[1][:-5])):
        d = json.load(open(fn, encoding='utf-8'))
        runs.append(d)
        for s in d['salas']:
            # las salas de la intro salen en todas las tandas: se queda la de mas ciclos
            r = s['sala']
            if r not in rooms or s['ciclos'] > rooms[r]['ciclos']:
                rooms[r] = s
    if len(sys.argv) > 2:
        d = json.load(open(sys.argv[2], encoding='utf-8'))
        for s in d['salas']:
            if s['sala'] not in rooms or s['ciclos'] > rooms[s['sala']]['ciclos']:
                rooms[s['sala']] = s
    rs = [rooms[k] for k in sorted(rooms) if rooms[k]['ciclos'] >= 20]
    print('| Sala | Ciclos | Bytecodes media / p90 / max | Mov.+cicl. (media) | Sends | Z80 T media / p90 | '
          'Heap max (código + datos) | Hunk max | Reparto | Mosaicos / por línea |')
    print('|---:|---:|---|---:|---:|---|---|---:|---:|---|')
    for s in rs:
        cat = s['categoria_media']
        mc = sum(v for k, v in cat.items() if 'movimiento' in k or 'ciclado' in k)
        print('| %d | %d | %d / %d / %d | %d | %.0f | %d / %d | %d (%d + %d) | %d | %.1f | %d / %d |' % (
            s['sala'], s['ciclos'], s['bytecodes_media'], s['bytecodes_p90'], s['bytecodes_max'], mc,
            s['sends_media'], s['z80_T_media'], s['z80_T_p90'], s['heap_max'], s['heap_scripts_codigo'],
            s['heap_scripts_datos'], s['hunk_max'], s['cast_media'], s.get('sprites_mosaicos_max', 0),
            s.get('sprites_linea_max', 0)))
    bc = [s['bytecodes_media'] for s in rs]
    z = [s['z80_T_media'] for s in rs]
    zp = [s['z80_T_p90'] for s in rs]
    hp = [s['heap_max'] for s in rs]
    dat = [s['heap_max'] - s['heap_scripts_codigo'] for s in rs]
    cod = [s['heap_scripts_codigo'] for s in rs]
    hk = [s['hunk_max'] for s in rs]
    print()
    print('salas', len(rs))
    for nm, xs in (('bytecodes/ciclo (media por sala)', bc), ('Z80 T/ciclo media', z), ('Z80 T/ciclo p90', zp),
                   ('heap max', hp), ('heap datos (sin codigo)', dat), ('heap codigo', cod), ('hunk max', hk)):
        print('%-34s media %8.0f  mediana %8.0f  max %8d' % (nm, statistics.mean(xs), statistics.median(xs), max(xs)))
    for speed in (5, 6):
        b = speed * TICK
        print('velocidad %d ticks: presupuesto %d T; salas con media dentro %d/%d, con p90 dentro %d/%d' % (
            speed, b, sum(1 for x in z if x <= b), len(z), sum(1 for x in zp if x <= b), len(zp)))
    errs = [r['error'] for r in runs if r.get('error')]
    print('tandas', len(runs), 'con error', len(errs))
    for e in errs:
        print('  ', e[:150])
    sm = [s.get('sprites_mosaicos_max', 0) for s in rs]
    sl = [s.get('sprites_linea_max', 0) for s in rs]
    print('mosaicos max por sala: mediana %d max %d; salas >64: %d' % (statistics.median(sm), max(sm),
                                                                      sum(1 for x in sm if x > 64)))
    print('mosaicos por linea max: mediana %d max %d; salas >12: %d' % (statistics.median(sl), max(sl),
                                                                       sum(1 for x in sl if x > 12)))
    parts = {}
    for s in rs:
        for k, v in s['z80_partes_media'].items():
            parts[k] = parts.get(k, 0) + v
    tot = sum(parts.values())
    print('reparto del tiempo Z80:', {k: '%.1f%%' % (100 * v / tot) for k, v in sorted(parts.items(), key=lambda x: -x[1])})


if __name__ == '__main__':
    main()
