"""Prueba de la geometria de isActorInBox (fase 5): 600 escenarios con el actor 3 en un punto al azar (dentro, cerca, lejos y con
coordenadas extremas de 16 bits) y una caja al azar (o invalida) de seis salas; compara el modelo (vmmodel3) con el Z80 (build/test_vm.exe).
Uso (desde ENGINE/test, tras build_test.sh): python -I ibx_test.py
"""
import sys, random, subprocess
sys.path.insert(0,'../../TOOLS'); sys.path.insert(0,'../../../V2/TOOLS')
import vmmodel3 as M
w=M.World('../../Indy Last Crusade')
rng=random.Random(5)
sc=[];ex=[]
for i in range(600):
    rn=rng.choice([1,15,20,28,43,47])
    r=w.rooms[rn]; bx,_=r.boxes(); nb=len(bx)
    b=rng.randrange(0,nb+1) if rng.random()<0.9 else rng.choice([255,254,nb+1,200])
    box=bx[rng.randrange(nb)]
    t=rng.random()
    if t<0.5:
        px=rng.randrange(min(box[0],box[2],box[4],box[6])-3,max(box[0],box[2],box[4],box[6])+3)
        py=rng.randrange(min(box[1],box[3],box[5],box[7])-3,max(box[1],box[3],box[5],box[7])+3)
    elif t<0.9:
        px=rng.randrange(-100,700); py=rng.randrange(-50,250)
    else:
        px=rng.choice([-32768,32767,-1,-25536]); py=rng.choice([-32768,32767,0,12345])
    lines=['INIT','ACTORSET 3 %d %d %d 1 1 1'%(rn,px,py),'ROOM %d 1'%rn,'CODE 1F03%02X05001AE000070000'%(b&255),'FRAMES 3 1']
    name='ibx%03d'%i
    out,vm=M.run_scenario_core(w,lines)
    sc.append('SCENARIO '+name+'\n'+'\n'.join(lines)+'\nEND'); ex.append('SCENARIO '+name+'\n'+'\n'.join(out)+'\nEND')
open('build/t2.txt','w').write('\n'.join(sc)+'\n'); open('build/t2_exp.txt','w').write('\n'.join(ex)+'\n')
subprocess.run(['./build/test_vm.exe','build/vm.bin','build/vm.sym','build/ovlb.bin','build/DATA.BIN','build/t2.txt','build/t2_act.txt','build/ovlc.bin'],stdout=subprocess.DEVNULL)
print(subprocess.run(['python','-I','compare_traces.py','build/t2_exp.txt','build/t2_act.txt','4'],capture_output=True,text=True).stdout[-1200:])
