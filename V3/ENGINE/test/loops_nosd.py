"""loops_nosd.py (fase 10d): resumen de las lineas "V vuelta T rutina=T ..." de test_scumm.exe (TS_LOOPS=n) sin las vueltas que leen de la SD
(frd_l, mcu_rw: cargas de trajes o de paginas de datos, que en el juego van al entrar en la sala). Uso: python -I loops_nosd.py salida.txt [umbral]
Imprime media, mediana, p90, maxima, las vueltas por encima del umbral (omision 325000) y las rutinas que mas pesan en ellas."""
import sys
th = int(sys.argv[2]) if len(sys.argv) > 2 else 325000
rows = []
for ln in open(sys.argv[1], encoding='latin-1'):
    if not ln.startswith('V '):
        continue
    p = ln.split()
    r = dict(x.split('=') for x in p[3:] if '=' in x)
    rows.append((int(p[2]), int(p[1]), r))
sd = [x for x in rows if 'frd_l' in x[2] or 'mcu_rw' in x[2]]
ok = sorted(x for x in rows if x not in sd)
if not ok:
    print('sin vueltas')
    sys.exit()
t = [x[0] for x in ok]
print('vueltas %d (y %d con lectura de la SD, fuera); media %.0f, mediana %d, p90 %d, maxima %d; > %d: %d' % (
    len(t), len(sd), sum(t) / len(t), t[len(t) // 2], t[len(t) * 9 // 10], t[-1], th, sum(1 for x in t if x > th)))
for tt, v, r in ok[::-1][:6]:
    print('  vuelta %d: %d  %s' % (v, tt, ' '.join('%s=%s' % kv for kv in list(r.items())[:8])))
