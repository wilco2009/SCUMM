#!/usr/bin/env python3
"""Prueba del modelo de referencia v3 (vmmodel3.py).

  1. el arranque llega al pasillo (sala 1);
  2. los escenarios son reproducibles: misma semilla, misma traza; semillas distintas, escenarios distintos;
  3. los escenarios de las salas 1, 15, 20 y 28 (sala, objetos, scripts locales, clics, teclas, frases, ESC) se
     ejecutan sin excepciones de Python y sin errores ERR distintos de "sin presupuesto" (bucle que no cede).

Uso: test_vmmodel3.py [DIR_LFL] [SEMILLAS]      (por omision ../Indy Last Crusade y 2 semillas)
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vmmodel3 as M       # noqa: E402

ROOMS = (1, 15, 20, 28)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Indy Last Crusade')
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    t0 = time.time()
    world = M.World(d)
    fails = 0

    vm, first = M.run_boot(world, 3000, 1)
    ok = 1 in first
    print('boot: sala final %d, llega a la sala 1 en el fotograma %s -> %s' % (vm.cur_room, first.get(1), 'OK' if ok else 'FALLO'))
    fails += not ok

    sc_a = M.make_scenarios(world, seeds, ROOMS, scripts=False)
    sc_b = M.make_scenarios(world, seeds, ROOMS, scripts=False)
    same = sc_a == sc_b
    diff = M.make_scenarios(world, 1, ROOMS, scripts=False) != [s for s in sc_a if s[0].endswith('.s1')]
    print('%d escenarios; reproducibles: %s; semillas distintas dan escenarios distintos: %s' % (len(sc_a), same, diff))
    fails += (not same) + (not diff)

    errs = {}
    exc = 0
    nerr = 0
    for name, lines in sc_a:
        try:
            t1, _ = M.run_scenario(world, lines)
            t2, _ = M.run_scenario(world, lines)
        except Exception as e:       # cualquier excepcion de Python es un fallo del modelo
            exc += 1
            print('EXCEPCION en %s: %s: %s' % (name, type(e).__name__, e))
            continue
        if t1 != t2:
            print('TRAZA NO REPRODUCIBLE en', name)
            fails += 1
        if t1 and t1[-1].startswith('ERR') and t1[-1] != 'ERR %d' % M.E_BUDGET:
            errs.setdefault(t1[-1], []).append(name)
            nerr += 1
    print('excepciones de Python: %d; escenarios con ERR (salvo sin presupuesto): %d' % (exc, nerr))
    for k, v in sorted(errs.items()):
        print('  %s: %d (p. ej. %s)' % (k, len(v), ', '.join(v[:3])))
    fails += exc + nerr
    print('%s (%.1f s)' % ('TODO OK' if not fails else 'HAY %d FALLOS' % fails, time.time() - t0))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
