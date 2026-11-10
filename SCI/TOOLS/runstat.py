#!/usr/bin/env python3
"""Ejecuta el modelo y resume por sala: bytecodes, kernel, memoria."""
import sys, os, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sci0vm import VM, VMError, OPNAMES

def main():
    path, ncyc = sys.argv[1], int(sys.argv[2])
    vm = VM(path)
    vm.max_cycles = ncyc
    err = None
    try:
        vm.run()
    except VMError as e:
        err = str(e)
    cyc = vm.cycles
    print('ciclos', len(cyc), 'ops', vm.ops_total, 'error:', err)
    print('imagenes', vm.pics_drawn)
    print('sin implementar', getattr(vm, 'unimpl', {}))
    rooms = collections.OrderedDict()
    for c in cyc:
        rooms.setdefault(c.room, []).append(c)
    for r, cs in rooms.items():
        ops = [c.ops for c in cs]
        print('sala %3d: %4d ciclos, ops/ciclo media %6.0f max %6d, cast media %.1f, heap max %d' % (
            r, len(cs), sum(ops) / len(ops), max(ops), sum(c.cast for c in cs) / len(cs), max(c.heap[0] for c in cs)))
    return vm

if __name__ == '__main__':
    main()
