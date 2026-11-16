#!/usr/bin/env python3
"""sprbudget3.py (fase 8, D6): sprites que piden los actores de una sala. Carga la sala con el modelo (LOADROOM + fotogramas con sus scripts), mira que actores hay
visibles y con que traje y fotograma, y cuenta las celdas de su postura (un sprite por celda) y el maximo de celdas que cortan una linea de pantalla (la FPGA carga 12 por
linea). Uso: sprbudget3.py DIR_DEL_JUEGO DATA.BIN salas [fotogramas por muestra] [muestras]   (salas: 32,35,...)
     sprbudget3.py DIR_DEL_JUEGO DATA.BIN estatico salas       peor caso: los trajes que el recorrido del estudio vio en cada sala (V3/medidas/indy3_salas.json), cada uno con su postura mas grande"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vmmodel3 as M            # noqa: E402
import pack_data3 as P3         # noqa: E402
import sprites3 as S            # noqa: E402


def actor_pack(a):
    return a.pack()


def analyse(world, data, rooms, step=20, samples=6, verbose=True):
    ref = S.Ref(data)
    res = {}
    for rn in rooms:
        rng = random.Random(5000)
        lines = M.init_lines_core(rng, world, rn, True) + ['LOADROOM %d' % rn]
        for k in range(samples):
            lines.append('FRAMES 4 %d' % step)
        # el modelo no da una vista intermedia: se corre cada muestra por separado (misma semilla: mismo recorrido)
        worst = (0, 0, None)
        seen = []
        for k in range(1, samples + 1):
            ln = M.init_lines_core(random.Random(5000), world, rn, True) + ['LOADROOM %d' % rn] + ['FRAMES 4 %d' % step] * k
            trace, vm = M.run_scenario_core(world, ln)
            if trace and trace[-1].startswith('ERR'):
                continue
            tot, per = 0, []
            lines_cov = {}
            for a in vm.actors[1:]:
                if not (a.in_room() and a.visible and a.costume):
                    continue
                rec = a.pack()
                p = ref.pick(rec, (a.frame, 0))
                if p is None:
                    per.append((a.num, a.costume, a.frame, 0))
                    continue
                blob, fo = p
                n = blob[fo + 4]
                per.append((a.num, a.costume, a.frame, n))
                tot += n
                dy = S.s8(blob[fo + 1])
                ry = a.y - a.elevation + dy
                for i in range(n):
                    pos = blob[fo + 5 + 2 * i]
                    y0 = ry + (pos >> 4) * 8
                    for yy in range(y0, y0 + 8):
                        lines_cov[yy] = lines_cov.get(yy, 0) + 1
            mx = max(lines_cov.values()) if lines_cov else 0
            seen.append((tot, mx, per))
            if tot > worst[0]:
                worst = (tot, mx, per)
        res[rn] = (worst, seen)
        if verbose:
            tot, mx, per = worst
            print('sala %3d: %d muestras, el maximo pide %2d sprites (de 63) y %2d celdas en una linea (de 12); actores (n, traje, fotograma, sprites): %s' % (
                rn, len(seen), tot, mx, per))
    return res


def static(data, rooms):
    """D6: el peor caso de cada sala = la suma de las celdas de la postura mas grande (andar/quieto y cualquiera) de los trajes vistos en la sala."""
    import json
    import struct
    ref = S.Ref(data)
    d = json.load(open(os.path.join(HERE, '..', 'medidas', 'indy3_salas.json')))
    rows = {r['room']: r for r in d['summary']}
    out = {}
    for rn in rooms:
        per = []
        for c in rows[rn]['costumes']:
            walk = anyp = 0
            for table in ('COSTDIR', 'COSTDIR2'):
                b = ref.b.blob(table, c)
                if not b:
                    continue
                for a in range(b[0]):
                    o = struct.unpack_from('<H', b, 3 + 2 * a)[0]
                    if not o:
                        continue
                    for st in range(b[o]):
                        fo = struct.unpack_from('<H', b, o + 1 + 2 * st)[0]
                        if fo != 0xFFFF:
                            anyp = max(anyp, b[fo + 4])
                            if a // 4 in (2, 3):
                                walk = max(walk, b[fo + 4])
            per.append((c, walk, anyp))
        out[rn] = (rows[rn]['actors_max'], per, sum(p[1] for p in per), sum(p[2] for p in per))
        print('sala %3d: %d actores a la vez como mucho; trajes (traje, sprites de andar/quieto, de la postura mas grande) %s; suma andar/quieto %d, suma de las mas grandes %d (disponibles: 63)' % (
            (rn,) + out[rn]))
    return out


def dynamic(world, data, rooms, frames=250):
    """Sprites que piden los actores de verdad: la sala se carga con el modelo (estado de despues del arranque, como el estudio) y se corre `frames` fotogramas con sus scripts; en cada
    fotograma se mira, de los actores de la sala visibles y con traje, la postura de su fotograma (la mas grande de sus pasos) y se cuentan los sprites en total y por linea de pantalla."""
    import struct
    ref = S.Ref(data)
    out = {}
    for rn in rooms:
        lines = [l for l in M.boot_snapshot(world) if l.startswith(('SETVAR ', 'PSEUDO '))]
        trace, vm = M.run_scenario_core(world, ['INIT'] + lines + ['LOADROOM %d' % rn])
        if trace and trace[-1].startswith('ERR'):
            print('sala %3d: error al cargarla (%s)' % (rn, trace[-1]))
            continue
        mx_tot = mx_line = over = frames_with = 0
        worst = None
        try:
            for k in range(frames):
                vm.frame += 1
                vm.step_frame(max(1, vm.vars[M.VAR_TIMER_NEXT]))
                acts = [a for a in vm.actors[1:] if a.in_room() and a.visible and a.costume]
                if not acts:
                    continue
                frames_with += 1
                tot, cov, per = 0, {}, []
                for a in acts:
                    rec = a.pack()
                    best = None
                    p0 = ref.pick(rec, (a.frame, 0))
                    if p0 is None:
                        per.append((a.num, a.costume, a.frame, 0))
                        continue
                    blob, fo0 = p0
                    # la postura mas grande entre los pasos de su animacion (la lista de pasos esta antes del fotograma elegido: se busca en el blob)
                    cost = a.costume
                    f = ref.b.find(cost, a.frame * 4 + S.new_dir_to_old_dir(a.facing)) or ref.b.find(cost, a.stand_frame * 4 + S.new_dir_to_old_dir(a.facing))
                    bl, o = f
                    for st in range(bl[o]):
                        fo = struct.unpack_from('<H', bl, o + 1 + 2 * st)[0]
                        if fo != 0xFFFF and (best is None or bl[fo + 4] > bl[best + 4]):
                            best = fo
                    n = bl[best + 4]
                    tot += n
                    per.append((a.num, a.costume, a.frame, n))
                    ry = a.y - a.elevation + S.s8(bl[best + 1])
                    for i in range(n):
                        pos = bl[best + 5 + 2 * i]
                        for yy in range(ry + (pos >> 4) * 8, ry + (pos >> 4) * 8 + 8):
                            cov[yy] = cov.get(yy, 0) + 1
                line = max(cov.values()) if cov else 0
                mx_tot, mx_line = max(mx_tot, tot), max(mx_line, line)
                over += tot > 63
                if worst is None or tot > worst[0]:
                    worst = (tot, line, per)
        except M.VMError as e:
            pass
        out[rn] = (frames_with, mx_tot, mx_line, over, worst)
        print('sala %3d: %3d fotogramas con actores; max %2d sprites (>63 en %d fotogramas); max %2d celdas en una linea (limite 12); peor fotograma (actor, traje, fotograma, sprites): %s' % (
            rn, frames_with, mx_tot, over, mx_line, worst[2] if worst else '-'))
    return out


if __name__ == '__main__':
    if len(sys.argv) > 3 and sys.argv[3] == 'dinamico':
        dynamic(M.World(sys.argv[1]), P3.Data(open(sys.argv[2], 'rb').read()), [int(x) for x in sys.argv[4].split(',')], int(sys.argv[5]) if len(sys.argv) > 5 else 250)
        sys.exit(0)
    if len(sys.argv) > 3 and sys.argv[3] == 'estatico':
        static(P3.Data(open(sys.argv[2], 'rb').read()), [int(x) for x in sys.argv[4].split(',')])
        sys.exit(0)
    d = sys.argv[1]
    world = M.World(d)
    data = P3.Data(open(sys.argv[2], 'rb').read())
    rooms = [int(x) for x in sys.argv[3].split(',')]
    step = int(sys.argv[4]) if len(sys.argv) > 4 else 20
    samples = int(sys.argv[5]) if len(sys.argv) > 5 else 6
    analyse(world, data, rooms, step, samples)
