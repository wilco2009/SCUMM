#!/usr/bin/env python3
"""Base v2 para comparar: bytecodes por fotograma de Zak y Maniac Mansion con el modelo de referencia del interprete v2
(SCUMM/V2/TOOLS/vmmodel.py + vmgame.py, la misma semantica que el Z80), con el mismo metodo que scumm3vm.py:
arranque (script 1), clics al azar en las cajas cada 15-60 fotogramas y recorrido por todas las salas (250 fotogramas cada una).

Uso (desde SCUMM/V3/TOOLS):  python v2base.py "../../V2/Zak McKracken" FOTOGRAMAS salida.json
"""
import json
import os
import random
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import vmmodel             # noqa: E402
from vmcommon import *     # noqa: E402,F401


def main():
    d, nframes, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    rng = random.Random(1)
    w = vmmodel.World(d)
    vm = vmmodel.VM(w)
    frames = []
    errors = Counter()

    def click():
        if not vm.boxes:
            return
        k = rng.randrange(len(vm.boxes))
        (ulx, uy), (urx, _), (llx, ly), (lrx, _) = vm.box_coords(k)
        t, u = rng.random(), rng.random()
        y = int(uy + (ly - uy) * u)
        x = int((ulx + (urx - ulx) * t) * (1 - u) + (llx + (lrx - llx) * t) * u)
        vm.vars[VAR_VIRT_MOUSE_X] = x // 8          # v2: coordenadas en franjas / 2 lineas (ScummVM v2)
        vm.vars[VAR_VIRT_MOUSE_Y] = y // 2
        vm.pending.append((CLICK_SCENE, 0))

    state = dict(next=30)

    def frame(label):
        state['next'] -= 1
        if state['next'] <= 0:
            click()
            state['next'] = rng.randint(15, 60)
        before = vm.insn
        err = None
        try:
            vm.insn = 0
            vm.step_frame(max(1, vm.vars[19] if vm.vars[19] else 6))
        except Exception as e:
            err = '%s %s' % (type(e).__name__, e)
            errors[err[:60]] += 1
            vm.cur = 0xFF
            vm.nest = []
        ops = vm.insn
        vm.insn = 0
        act = [a for a in vm.actors[1:] if a.room == vm.cur_room and vm.cur_room]
        frames.append(dict(room=vm.cur_room, ops=ops, actors=len(act), moving=sum(1 for a in act if a.moving),
                           err=err, label=label))

    try:
        vm.run_script(1)
    except Exception as e:
        errors['boot ' + str(e)] += 1
    for _ in range(nframes):
        frame('boot')
    rooms = sorted(w.rooms)
    for rn in rooms:
        try:
            vm.cur = 0xFF
            vm.nest = []
            ego = vm.actors[vm.vars[VAR_EGO]] if 0 < vm.vars[VAR_EGO] < len(vm.actors) else None
            vm.start_scene(rn)
            if ego is not None and vm.boxes:
                (ulx, uy), (urx, _), (llx, ly), (lrx, _) = vm.box_coords(0)
                vm.put_actor(ego, (ulx + urx) // 2, (uy + ly) // 2, rn)
        except Exception as e:
            errors['sala %d %s' % (rn, e)] += 1
            continue
        for _ in range(250):
            if vm.cur_room != rn:
                break
            frame('sala %d' % rn)
    by = {}
    for f in frames:
        by.setdefault(f['room'], []).append(f)
    summ = []
    for rn, fs in sorted(by.items()):
        ops = sorted(f['ops'] for f in fs)
        n = len(ops)
        summ.append(dict(room=rn, frames=n, ops_mean=round(sum(ops) / n, 1), ops_p90=ops[min(n - 1, int(0.9 * n))],
                         ops_max=ops[-1], actors_max=max(f['actors'] for f in fs),
                         moving_mean=round(sum(f['moving'] for f in fs) / n, 2), errors=sum(1 for f in fs if f['err'])))
    with open(out, 'w') as f:
        json.dump(dict(summary=summ, errors=errors.most_common(20), frames=frames), f)
    for s in summ:
        print(s)
    print('errores', errors.most_common(8))


if __name__ == '__main__':
    main()
