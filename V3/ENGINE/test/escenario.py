"""Depuracion: extrae un escenario (por nombre) de build/scenarios.txt y build/expected.txt, lo ejecuta en el Z80 (build/test_vm.exe) y
muestra la primera linea de la traza que difiere, con el contexto del modelo. Uso (desde ENGINE/test, tras build_test.sh): python -I escenario.py cscr025.s0
Con TV_RING=1 el arnes imprime los ultimos PC antes de cada error; con TV_TRACE=1, cada instruccion de script."""
import sys, subprocess, os
name = sys.argv[1]
b = 'build'
sc = []; on = False
for ln in open(b + '/scenarios.txt'):
    ln = ln.rstrip('\n')
    if ln == 'SCENARIO ' + name: on = True; sc.append(ln); continue
    if on:
        sc.append(ln)
        if ln == 'END': break
open(b + '/one.txt', 'w').write('\n'.join(sc) + '\n')
exp = []; on = False
for ln in open(b + '/expected.txt'):
    ln = ln.rstrip('\n')
    if ln == 'SCENARIO ' + name: on = True; exp.append(ln); continue
    if on:
        exp.append(ln)
        if ln == 'END': break
open(b + '/one_exp.txt', 'w').write('\n'.join(exp) + '\n')
env = dict(os.environ)
subprocess.run(['./' + b + '/test_vm.exe', b + '/vm.bin', b + '/vm.sym', b + '/ovlb.bin', b + '/DATA.BIN', b + '/one.txt', b + '/one_act.txt', b + '/ovlc.bin'], env=env, stdout=subprocess.DEVNULL)
a = open(b + '/one_act.txt').read().split('\n'); e = open(b + '/one_exp.txt').read().split('\n')
for i in range(max(len(a), len(e))):
    x = a[i] if i < len(a) else '<fin>'; y = e[i] if i < len(e) else '<fin>'
    if x != y:
        print('linea', i); print(' modelo:', y[:400]); print(' z80   :', x[:400]); 
        for k in range(max(0, i - 4), i): print('   ctx:', e[k][:140])
        break
else:
    print('iguales')
