"""Prueba de la division de 32 bits de expression (fase 10d: div32s con divisor de 16 bits por el camino corto): 600 escenarios con varias
expression al azar (productos para tener dividendos de 32 bits, divisores de 16 y de 32 bits, con signo, INT_MIN, -1, potencias de 2) que
dejan sus resultados en variables; compara el modelo (vmmodel3) con el Z80 (build/test_vm.exe).
Uso (desde ENGINE/test, tras build_test.sh): python -I exp_test.py
"""
import random
import struct
import subprocess
import sys
sys.path.insert(0, '../../TOOLS')
import vmmodel3 as M

w = M.World('../../Indy Last Crusade')
rng = random.Random(10)
VALS = [0, 1, -1, 2, -2, 3, 7, 10, 255, 256, -256, 1000, -1000, 32767, -32768, 32766, 12345, -12345, 65535 - 65536, 181, 46341 - 65536]


def val():
    return rng.choice(VALS) if rng.random() < 0.5 else rng.randrange(-32768, 32768)


def push(v):
    return bytes([1]) + struct.pack('<h', v)


def term(depth):
    """bytes de expression que dejan un valor en la pila (a veces de 32 bits: productos)."""
    if depth <= 0 or rng.random() < 0.3:
        return push(val())
    k = rng.random()
    if k < 0.35:
        return term(depth - 1) + term(depth - 1) + bytes([4])          # producto
    if k < 0.75:
        d = term(depth - 1)
        return term(depth - 1) + (d if rng.random() < 0.5 else push(rng.choice([v for v in VALS if v] + [rng.randrange(1, 300)]))) + bytes([5])
    return term(depth - 1) + term(depth - 1) + bytes([rng.choice([2, 3])])


sc, ex = [], []
for i in range(600):
    lines = ['INIT']
    code = b''
    for k in range(rng.randrange(1, 5)):
        code += bytes([0xAC]) + struct.pack('<H', 100 + k) + term(rng.randrange(1, 5)) + b'\xFF'
    lines.append('CODE ' + (code + b'\0').hex())
    lines.append('FRAMES 1 1')
    name = 'exp%03d' % i
    out, vm = M.run_scenario_core(w, lines)
    sc.append('SCENARIO ' + name + '\n' + '\n'.join(lines) + '\nEND')
    ex.append('SCENARIO ' + name + '\n' + '\n'.join(out) + '\nEND')
b = 'build'
open(b + '/t4.txt', 'w').write('\n'.join(sc) + '\n')
open(b + '/t4_exp.txt', 'w').write('\n'.join(ex) + '\n')
subprocess.run(['./build/test_vm.exe', b + '/vm.bin', b + '/vm.sym', b + '/ovlb.bin', 'build/DATA.BIN', b + '/t4.txt', b + '/t4_act.txt', b + '/ovlc.bin',
                b + '/ovld.bin'], stdout=subprocess.DEVNULL)
nerr = sum(1 for e in ex if 'ERR' in e)
print('%d escenarios (%d con algun error en el modelo, p. ej. division por 0)' % (len(sc), nerr))
print(subprocess.run([sys.executable, '-I', 'compare_traces.py', b + '/t4_exp.txt', b + '/t4_act.txt', '4'], capture_output=True, text=True).stdout[-1500:])
