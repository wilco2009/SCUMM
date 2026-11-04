#!/usr/bin/env python3
"""Agrupa el perfil del arnes (TS_PROF) por areas del interprete."""
import re, sys
G = [('pri', r'A:(pd_|hg_|hk_|hn_|hs_|hv_|pv_|vh_|vis_hide|hw_mask|hm_|hw_group|ps_|pd_patch)'),
     ('spr', r'A:(h[wpqfr]_|hq|so_|sob_|spr_|si_|od_|ts_|sort|t_draw|t_sort|vg_|vc_|co_|cel_)'),
     ('kbd', r'A:'), ('B', r'B:'), ('C', r'C:'), ('D', r'D:'), ('E', r'E:'), ('F', r'F:'),
     ('if',  r'(do_if|di_|hc_|su_|skip_until)'),
     ('rl',  r'(rl_|run_logic|cb_)')]
tot = {}; all_ = 0; rows = []
for l in open(sys.argv[1], errors='replace'):
    m = re.match(r'\s+(\S+)\s+(\d+)\s+([\d.]+)%', l)
    if m:
        n, v = m.group(1), int(m.group(2)); all_ += v; rows.append((v, n))
        for k, p in G:
            if re.match(p, n):
                tot[k] = tot.get(k, 0) + v; break
        else:
            tot['otro'] = tot.get('otro', 0) + v
    elif l.startswith(('PERFIL', 'instrucciones por', 'fotogramas', 'el programa', 'atascado')):
        print(l.strip()[:100])
for k, v in sorted(tot.items(), key=lambda x: -x[1]):
    print('  %-5s %9d %5.1f%%' % (k, v, 100.0 * v / max(all_, 1)))
d = open('../dump/perf160.bin', 'rb').read()[65536:131072]
sym = {}
for l in open('../ENGINE/agivm.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-F]+)H', l)
    if m: sym[m.group(1)] = int(m.group(2), 16)
o = sym['OBJ']
print('  ciclo final %d, ego en %d,%d; T-estados por ciclo: %d' % (d[sym['cyc']] | d[sym['cyc'] + 1] << 8, d[o + 5], d[o + 6], all_ / (float(sys.argv[2]) if len(sys.argv) > 2 else 25)))
print('  top:', ' '.join('%s=%.1f' % (n, 100.0 * v / all_) for v, n in sorted(rows, reverse=True)[:45]))
