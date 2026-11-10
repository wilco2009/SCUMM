#!/usr/bin/env python3
"""Corre el modelo sobre un juego SCI0 y saca las medidas del estudio.

Uso: analiza.py CARPETA_JUEGO NOMBRE [CICLOS]  -> SCUMM/SCI/medidas/NOMBRE.json + resumen

El coste en Z80 es una estimacion contada a mano sobre un diseno concreto
(ver ESTUDIO_SCI0.md, seccion 2): no es una medida del Z80.
"""
import collections
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sci0vm import VM, VMError, OPNAMES  # noqa: E402

# ---------------------------------------------------------------- Z80
# T-estados por bytecode (incluye el despacho de ~50 T). Diseno supuesto:
# PC en DE (codigo paginado en una ventana), acumulador en BC, pila SCI con
# puntero en memoria, heap de datos fijo en $8000-$FFFF (sin traduccion).
T_DISPATCH = 50
T_OP = {
    'bnot': 30, 'add': 70, 'sub': 75, 'mul': 450, 'div': 900, 'mod': 900, 'shr': 160, 'shl': 160,
    'xor': 75, 'and': 75, 'or': 75, 'neg': 40, 'not': 45,
    'eq': 95, 'ne': 95, 'gt': 110, 'ge': 110, 'lt': 110, 'le': 110, 'ugt': 95, 'uge': 95, 'ult': 95, 'ule': 95,
    'bt': 55, 'bnt': 55, 'jmp': 45, 'ldi': 30, 'push': 40, 'pushi': 50, 'toss': 20, 'dup': 60,
    'link': 80, 'call': 420, 'callk': 260, 'callb': 480, 'calle': 520, 'ret': 330,
    'send': 300, 'self': 300, 'super': 380, 'class': 140, 'rest': 120, 'lea': 110, 'selfID': 25,
    'pprev': 40, 'pToa': 75, 'aTop': 75, 'pTos': 85, 'sTop': 85, 'ipToa': 105, 'dpToa': 105,
    'ipTos': 115, 'dpTos': 115, 'lofsa': 60, 'lofss': 70, 'push0': 40, 'push1': 40, 'push2': 40,
    'pushSelf': 45, 'line': 25,
}
# variables (g, l, t, p): base en memoria + 2*indice (+acc en las "i")
for _n in OPNAMES[0x40:]:
    if _n.startswith('l'):
        _c = 85 if _n[1] == 'a' else 110      # la* / ls*
    elif _n.startswith('s'):
        _c = 90 if _n[1] == 'a' else 110      # sa* / ss*
    else:
        _c = 140                              # plus/minus
    if _n.endswith('i'):
        _c += 35
    T_OP.setdefault(_n, _c)

T_SEND_VAR = 150     # por selector de variable dentro de un send (sin la busqueda)
T_SEND_MET = 450     # por selector de metodo: marco nuevo + vuelta
T_LOOKUP_CMP = 32    # por comparacion de selector en la busqueda lineal
T_LOOKUP_UP = 60     # por salto a la superclase
T_KSEL = 90          # lectura/escritura de un selector desde el kernel con tabla por clase

# kernel: coste fijo (sin los selectores) y por unidad de trabajo
T_KCALL = {
    'Animate': 2500, 'CanBeHere': 600, 'DoBresen': 900, 'InitBresen': 1800, 'BaseSetter': 600,
    'SetNowSeen': 500, 'DirLoop': 300, 'GetAngle': 900, 'GetDistance': 1500, 'Abs': 60, 'Random': 300,
    'NextNode': 70, 'FirstNode': 60, 'NodeValue': 60, 'LastNode': 60, 'PrevNode': 70, 'IsObject': 250,
    'FindKey': 120, 'AddToEnd': 250, 'AddToFront': 250, 'AddAfter': 300, 'DeleteKey': 400, 'NewNode': 500,
    'NewList': 400, 'DisposeList': 500, 'EmptyList': 70, 'Clone': 2500, 'DisposeClone': 600,
    'GetTime': 150, 'Wait': 200, 'GetEvent': 900, 'DoSound': 600, 'CoordPri': 120, 'OnControl': 400,
    'NumCels': 700, 'NumLoops': 600, 'CelWide': 600, 'CelHigh': 600, 'StrCmp': 800, 'StrLen': 400,
    'StrCpy': 600, 'StrAt': 120, 'Format': 6000, 'RespondsTo': 600, 'GlobalToLocal': 200,
}
T_KCALL_DEFAULT = 800
# selectores que lee/escribe cada kernel (contados en ScummVM)
KSEL = {'CanBeHere': 6, 'DoBresen': 22, 'InitBresen': 14, 'BaseSetter': 11, 'SetNowSeen': 10,
        'DirLoop': 3, 'NumCels': 2, 'NumLoops': 1, 'DoSound': 3, 'GetEvent': 5}
T_WORK = {
    'canbehere_px': 22,        # mapa de control en nibbles, fila contigua
    'canbehere_obj': 4 * T_KSEL + 120,
    'oncontrol_px': 22,
    'nodos': 0,
    'animate_ents': 34 * T_KSEL + 600,   # ~34 selectores por objeto + orden + rectangulos
    'animate_moving': 1500,              # actualizar sprites por hardware (registros que cambian)
    'bits_save_px': 0, 'bits_restore_px': 0, 'show_px': 0, 'cel_px': 0,   # con sprites hardware
    'lookup_cmp': T_LOOKUP_CMP, 'lookup_up': T_LOOKUP_UP,
    'send_var': T_SEND_VAR, 'send_met': T_SEND_MET,
}


def z80_cycle(c):
    """T-estados de un ciclo, por partes."""
    parts = collections.Counter()
    for cat, ops in c.cat.items():
        t = 0
        for i, n in enumerate(ops):
            if n:
                t += n * (T_DISPATCH + T_OP.get(OPNAMES[i], 80))
        base = cat[2:] if cat.startswith('A:') else cat
        parts['bc_' + base] += t
    for k, n in c.kcalls.items():
        if k == 'Animate':
            parts['k_Animate'] += n * T_KCALL['Animate']
        else:
            parts['kernel'] += n * (T_KCALL.get(k, T_KCALL_DEFAULT) + KSEL.get(k, 0) * T_KSEL)
    for k, n in c.kwork.items():
        t = T_WORK.get(k, 0) * n
        if k in ('lookup_cmp', 'lookup_up', 'send_var', 'send_met'):
            parts['send'] += t
        elif k.startswith('spr_'):
            continue
        elif k.startswith('animate') or k in ('bits_save_px', 'bits_restore_px', 'show_px', 'cel_px'):
            parts['k_Animate'] += t
        elif k.startswith('canbehere'):
            parts['k_CanBeHere'] += t
        else:
            parts['kernel'] += t
    return parts


def salas(vm):
    """Scripts con una instancia de Rm (las salas), en orden."""
    import struct
    from sci0res import script_blocks, script_objects, cstr
    rm_sp = None
    for k in vm.rm.keys('script'):
        b = vm.rm.get(k)
        for o in script_objects(b):
            if o['type'] == 'class' and o['nvars'] > 3:
                nm = o['vars'][3]
                if nm < len(b) and cstr(b, nm) == 'Rm':
                    rm_sp = o['vars'][0]
    out = []
    for k in vm.rm.keys('script'):
        b = vm.rm.get(k)
        for o in script_objects(b):
            if o['type'] == 'object' and o['vars'][0] == rm_sp:
                out.append(k[1])
                break
    return [r for r in out if r not in (0,)]


def pct(xs, p):
    if not xs:
        return 0
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p))]


def main():
    path, name = sys.argv[1], sys.argv[2]
    ncyc = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
    vm = VM(path)
    vm.max_cycles = ncyc
    modo = sys.argv[4] if len(sys.argv) > 4 else ''
    if 'andar' in modo:
        vm.walk = True
    if 'salas' in modo:
        vm.tour = salas(vm)
        d0 = int(os.environ.get('TOUR_DESDE', '0'))
        vm.tour = vm.tour[d0:d0 + int(os.environ.get('TOUR_N', '1000'))]
        vm.max_cycles = 300 + (len(vm.tour) + 1) * int(os.environ.get('TOUR_CICLOS', '250'))
        vm.tour_ticks = int(os.environ.get('TOUR_CICLOS', '250'))
    err = None
    orig_end = vm.end_cycle
    state = {'room': None}
    def end_cycle():
        orig_end()
        c = vm.cycles[-1]
        if c.room != state['room']:
            state['room'] = c.room
            print('  -> sala %d en el ciclo %d (%.0f s)' % (c.room, len(vm.cycles), vm.ticks / 60), flush=True)
    vm.end_cycle = end_cycle
    try:
        vm.run()
    except VMError as e:
        err = str(e)
    cycles = vm.cycles
    res = {'juego': name, 'ciclos': len(cycles), 'bytecodes': vm.ops_total, 'error': err,
           'segundos_simulados': round(vm.ticks / 60, 1), 'imagenes': vm.pics_drawn,
           'heap_pico': vm.heap.peak, 'pila_pico_B': max((c.heap[2] for c in cycles), default=0),
           'hunk_pico': vm.hunk_peak, 'anidamiento_pico': vm.depth_peak,
           'scripts_retenidos': getattr(vm, 'kept_scripts', 0), 'entradas': vm.inputs, 'salas': []}
    # ciclos "modales": bucles de espera dentro de un ciclo (Print con tiempo, dialogos)
    def modal(c):
        return c.kcalls.get('GetEvent', 0) > 3
    hist = [0] * 128
    hist_cat = collections.Counter()
    rooms = collections.OrderedDict()
    for c in cycles:
        rooms.setdefault(c.room, []).append(c)
        for cat, ops in c.cat.items():
            for i, n in enumerate(ops):
                hist[i] += n
            hist_cat[cat] += sum(ops)
    res['opcodes'] = {OPNAMES[i]: n for i, n in sorted(enumerate(hist), key=lambda x: -x[1]) if n}
    res['bytecodes_por_categoria'] = dict(hist_cat.most_common())
    for r, cs in rooms.items():
        normal = [c for c in cs if not modal(c)]
        if not normal:
            continue
        ops = [c.ops for c in normal]
        z = [z80_cycle(c) for c in normal]
        zt = [sum(p.values()) for p in z]
        cat = collections.Counter()
        kc = collections.Counter()
        kw = collections.Counter()
        zp = collections.Counter()
        for c, p in zip(normal, z):
            for k, v in c.cat.items():
                cat[k] += sum(v)
            kc.update({k: v for k, v in c.kcalls.items() if not k.startswith('_')})
            kw.update(c.kwork)
            zp.update(p)
        n = len(normal)
        heap = [c.heap[0] for c in cs]
        imax = max(range(len(cs)), key=lambda i: cs[i].heap[0])
        hpk = cs[imax].heap
        scode = sum(v[1] for v in hpk[3].values())
        sdat = sum(v[0] - v[1] for v in hpk[3].values())
        waits = [c.wait for c in normal if c.wait]
        room = {
            'sala': r, 'ciclos': len(cs), 'ciclos_modales': len(cs) - n,
            'bytecodes_media': round(statistics.mean(ops)), 'bytecodes_p50': pct(ops, 0.5),
            'bytecodes_p90': pct(ops, 0.9), 'bytecodes_max': max(ops),
            'categoria_media': {k: round(v / n) for k, v in cat.most_common()},
            'sends_media': round(sum(c.sends for c in normal) / n, 1),
            'kernel_media': {k: round(v / n, 2) for k, v in kc.most_common()},
            'trabajo_media': {k: round(v / n, 1) for k, v in kw.most_common()},
            'sprites_mosaicos_max': max(c.kwork.get('spr_tiles', 0) for c in normal),
            'sprites_linea_max': max(c.kwork.get('spr_linea', 0) for c in normal),
            'cast_media': round(sum(c.cast for c in normal) / n, 1), 'cast_max': max(c.cast for c in normal),
            'wait_tipico': statistics.mode(waits) if waits else None,
            'heap_max': max(heap), 'heap_media': round(statistics.mean(heap)),
            'heap_al_max': hpk[1], 'heap_scripts_codigo': scode, 'heap_scripts_datos': sdat,
            'scripts_al_max': sorted(hpk[3]), 'pila_max': max(c.heap[2] for c in cs),
            'hunk_max': max(sum(v for k, v in c.hunk.items()) for c in cs),
            'hunk_al_max': max((c.hunk for c in cs), key=lambda h: sum(h.values())),
            'z80_T_media': round(statistics.mean(zt)), 'z80_T_p90': pct(zt, 0.9), 'z80_T_max': max(zt),
            'z80_partes_media': {k: round(v / n) for k, v in zp.most_common()},
        }
        res['salas'].append(room)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'medidas')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, name + '.json'), 'w', encoding='utf-8') as f:
        json.dump(res, f, indent=1, ensure_ascii=False)
    print('%s: %d ciclos, %d bytecodes, %.0f s, heap pico %d, hunk pico %d, pila %d, error %s' % (
        name, len(cycles), vm.ops_total, vm.ticks / 60, vm.heap.peak, vm.hunk_peak, res['pila_pico_B'], err))
    for s in res['salas']:
        print('  sala %3d: %5d ciclos (%d modales) bc media %5d p90 %5d max %6d | Z80 media %7d p90 %7d | '
              'cast %.1f | heap %5d (cod %5d dat %5d) | wait %s' % (
                  s['sala'], s['ciclos'], s['ciclos_modales'], s['bytecodes_media'], s['bytecodes_p90'],
                  s['bytecodes_max'], s['z80_T_media'], s['z80_T_p90'], s['cast_media'], s['heap_max'],
                  s['heap_scripts_codigo'], s['heap_scripts_datos'], s['wait_tipico']))


if __name__ == '__main__':
    main()
