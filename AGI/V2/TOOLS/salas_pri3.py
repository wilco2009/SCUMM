"""Imagenes cuyo plano de prioridad de sprites cambio al tratar solo 0-2 como control (el 3 es prioridad real, p. ej. el agua), por juego:
salas que las dibujan (logica N con draw.pic(v0): sala N = imagen N) y un punto con prioridad 3 donde situar al ego.
  python salas_pri3.py [JUEGO ...]      (carpeta del juego en AGI/V2/JUEGO)
Para ir a la sala y ponerse en el punto (AGI_BOOT al compilar, ver agi_read.testboot): AGI_BOOT="room=N,cyc=3,cmd=position:0:X:Y" compilavm4.bat JUEGO"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi_read as ag
import agi2hr

W, H = 160, 168
HERE = os.path.dirname(os.path.abspath(__file__))


def old_priority(pri):
    out = list(pri)
    below = [4] * W
    for y in range(H - 1, -1, -1):
        for x in range(W):
            v = out[y * W + x]
            if v < 4:
                v = below[x]
                out[y * W + x] = v
            below[x] = v
    return out


def draws_v0(game, n):
    r = subprocess.run([sys.executable, os.path.join(HERE, 'agi_logic.py'), game, str(n)], capture_output=True, text=True, cwd=os.path.join(HERE, '..'))
    return 'draw.pic(v0)' in r.stdout


def main(argv):
    games = argv[1:] or ['SQ1', 'SQ2', 'KQ1', 'KQ2', 'PQ1']
    for gn in games:
        g = ag.Game(os.path.join(HERE, '..', gn))
        print('== %s' % gn)
        for n in range(256):
            try:
                d = g.resource('PIC', n)
                if d is None:
                    continue
                a = ag.Picture(d).pri
            except Exception:
                continue
            if 3 not in a:
                continue
            new = agi2hr.sprite_priority(a)
            old = old_priority(a)
            ch = [i for i in range(len(a)) if old[i] != new[i]]
            if not ch:
                continue
            cx = sum(i % W for i in ch) / len(ch)
            cy = sum(i // W for i in ch) / len(ch)
            # punto con prioridad 3 mas cercano al centro de lo que cambia (el ego se situa por los pies: y; x es el borde izquierdo)
            p = min(ch, key=lambda i: (i % W - cx) ** 2 + (i // W - cy) ** 2)
            room = 'sala %d' % n if draws_v0(gn, n) else 'imagen sin sala directa (la elige otra variable)'
            print('  imagen %3d: %5d px  %s  punto x=%d y=%d  AGI_BOOT="room=%d,cyc=3,cmd=position:0:%d:%d"' % (n, len(ch), room, p % W, p // W, n, p % W, p // W))


if __name__ == '__main__':
    main(sys.argv)
