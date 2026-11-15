#!/usr/bin/env python3
"""Compara el resumen por fotograma del modelo (boot-core) con el del programa completo en el arnes (TS_DIGEST). Uso: compare_boot.py esperado actual [n_diferencias_a_mostrar]"""
import sys

exp = [ln.rstrip('\n') for ln in open(sys.argv[1])]
act = [ln.rstrip('\n') for ln in open(sys.argv[2])]
n = min(len(exp), len(act))
bad = [i for i in range(n) if exp[i] != act[i]]
print('fotogramas comparados: %d (modelo %d, Z80 %d), iguales: %d, distintos: %d' % (n, len(exp), len(act), n - len(bad), len(bad)))
for i in bad[:int(sys.argv[3]) if len(sys.argv) > 3 else 3]:
    a, b = exp[i].split(' '), act[i].split(' ')
    d = [(x, y) for x, y in zip(a, b) if x != y]
    print('  linea %d: %s' % (i, d[:6]))
sys.exit(1 if bad or len(exp) != len(act) else 0)
