"""Prueba de la geometria de la caminata (fase 6) con coordenadas extremas: 600 escenarios con el actor 1 colocado en un punto (dentro de una
caja, cerca, lejos o con coordenadas s16 extremas), siguiendo las cajas o no, y de 1 a 3 walkActorTo a puntos igual de variados, en seis salas;
compara el modelo (vmmodel3) con el Z80. Recorre lo que los escenarios de las salas casi no tocan: desbordamientos de 32 bits de closestPtOnLine
y compareSlope, el tope de sqrDist, adjustXYToBeInBox lejos de todas las cajas y los pasos con posiciones fuera de la sala.
Uso (desde ENGINE/test, tras build_test.sh): python -I wlk_test.py [carpeta con vm.bin, ovl?.bin (omision build)] [arnes (omision build/test_vm.exe)]
"""
import sys, random, struct, subprocess
sys.path.insert(0, '../../TOOLS')
import vmmodel3 as M
import vmsynth3 as VS

b = sys.argv[1] if len(sys.argv) > 1 else 'build'
exe = sys.argv[2] if len(sys.argv) > 2 else 'build/test_vm.exe'
w = M.World('../../Indy Last Crusade')
rng = random.Random(6)
EXT = [-32768, 32767, -1, 0, 4095, 4096, 4097, -4096, 8191, 30000, -30000, 12345, -25536, 65, 320]


def point(bx, width):
    t = rng.random()
    if t < 0.45:
        return VS.walk_point(rng, bx, width, wild=0)
    if t < 0.7:
        return rng.randrange(-200, width + 200), rng.randrange(-100, 300)
    if t < 0.85:
        return rng.randrange(-6000, 6000), rng.randrange(-6000, 6000)
    return rng.choice(EXT), rng.choice(EXT)


def op(name, act, x, y):
    return bytes([VS.BASE[name], act]) + struct.pack('<hh', x, y)


sc = []; ex = []; errs = 0
for i in range(600):
    rn = rng.choice([1, 15, 20, 28, 43, 47])
    r = w.rooms[rn]
    bx, _ = r.boxes()
    x0, y0 = point(bx, r.width)
    lines = ['INIT', 'SETVAR 1 1', 'ROOM %d 1' % rn]
    if rng.random() < 0.2:
        lines.insert(1, 'CLASS 1 %X' % rng.choice([0x40000, 0x20000, 0x400000]))
    code = bytes([VS.BASE['actorOps'], 1, 1, 1]) + (bytes([20]) if rng.random() < 0.12 else b'') + bytes([4, rng.choice([8, 8, 1, 3, 20, 200]),
                 rng.choice([2, 2, 1, 5, 100]), 0xFF]) + op('putActor', 1, x0, y0) + bytes([VS.BASE['putActorInRoom'], 1, rn])
    lines.append('CODE ' + (code + op('walkActorTo', 1, *point(bx, r.width)) + b'\0').hex())
    for k in range(rng.randrange(0, 3)):
        lines += ['FRAMES 4 %d' % rng.choice([1, 3, 10, 30]), 'CODE ' + (op('walkActorTo', 1, *point(bx, r.width)) + b'\0').hex()]
    lines.append('FRAMES 4 %d' % rng.choice([40, 80, 120]))
    name = 'wlk%03d' % i
    out, vm = M.run_scenario_core(w, lines)
    errs += bool(out and out[-1].startswith('ERR'))
    sc.append('SCENARIO ' + name + '\n' + '\n'.join(lines) + '\nEND'); ex.append('SCENARIO ' + name + '\n' + '\n'.join(out) + '\nEND')
open(b + '/t3.txt', 'w').write('\n'.join(sc) + '\n'); open(b + '/t3_exp.txt', 'w').write('\n'.join(ex) + '\n')
subprocess.run(['./' + exe, b + '/vm.bin', b + '/vm.sym', b + '/ovlb.bin', 'build/DATA.BIN', b + '/t3.txt', b + '/t3_act.txt', b + '/ovlc.bin', b + '/ovld.bin'],
               stdout=subprocess.DEVNULL)
print('%d escenarios (%d acaban en error en el modelo)' % (len(sc), errs))
print(subprocess.run([sys.executable, '-I', 'compare_traces.py', b + '/t3_exp.txt', b + '/t3_act.txt', '4'], capture_output=True, text=True).stdout[-1500:])
