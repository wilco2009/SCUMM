#!/usr/bin/env python3
"""Compara dos ficheros de trazas (formato SCENARIO nombre ... END) y cuenta las diferencias."""
import sys


def load(path):
    out, name, cur = {}, None, []
    for ln in open(path, encoding='utf-8'):
        ln = ln.rstrip('\n')
        if ln.startswith('SCENARIO '):
            name, cur = ln[9:], []
        elif ln == 'END':
            out[name] = cur
        else:
            cur.append(ln)
    return out


def main():
    exp, act = load(sys.argv[1]), load(sys.argv[2])
    bad = []
    for name in exp:
        if name not in act:
            bad.append((name, 'falta en la traza del Z80'))
        elif exp[name] != act[name]:
            a, b = exp[name], act[name]
            k = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
            bad.append((name, 'linea %d: modelo %r, Z80 %r' % (k, a[k] if k < len(a) else None, b[k] if k < len(b) else None)))
    print('escenarios: %d, iguales: %d, distintos: %d' % (len(exp), len(exp) - len(bad), len(bad)))
    for name, why in bad[:int(sys.argv[3]) if len(sys.argv) > 3 else 10]:
        print('  %s: %s' % (name, why))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
