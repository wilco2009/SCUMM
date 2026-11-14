#!/usr/bin/env python3
"""Pruebas de mutacion del nucleo v3: se estropea el Z80 a proposito y se cuenta cuantos escenarios cambian.

Una mutacion que no cambia ningun escenario quiere decir que los escenarios no cubren ese codigo (o que la mutacion no cambia nada
que se vea). Usa los escenarios del nucleo de las salas 1 y 15 (y los scripts globales y los del script 95), que genera en
build/mut/ la primera vez. Uso (tras build_test.sh, que compila test_vm.exe): python mutaciones.py [salas]
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.dirname(HERE)
TOOLS = os.path.join(ENGINE, '..', 'TOOLS')
GAME = os.path.join(ENGINE, '..', 'Indy Last Crusade')
B = os.path.join(HERE, 'build')
MUT = os.path.join(B, 'mut')

# (descripcion, fichero, texto original, texto nuevo)
M = [
    # ---- nucleo (fase 3)
    ('isEqual invertido', 'vm_ops.asm', 'call cmp_ab             ; b == a\n                jp z,no_jump',
     'call cmp_ab             ; b == a\n                jp nz,no_jump'),
    ('increment resta', 'vm_ops.asm', 'call var_rd\n                inc bc\n                jp set_res',
     'call var_rd\n                dec bc\n                jp set_res'),
    ('comparacion sin signo', 'vm_core.asm', 'scmp:           ld a,h\n                xor $80', 'scmp:           ld a,h\n                xor $00'),
    ('local sin doblar el indice', 'vm_core.asm', '                ld a,l\n                add a,a\n                ld l,a\n                ld h,0\n                push de\n                ld de,(LOCP)',
     '                ld a,l\n                ld l,a\n                ld h,0\n                push de\n                ld de,(LOCP)'),
    ('bit de variable: byte alto desde el 9', 'vm_core.asm', '                cp 8\n                jr c,ba_lo', '                cp 9\n                jr c,ba_lo'),
    ('indice 0x2000 de 3 bits', 'vm_core.asm', 'ri_c:           ld a,h\n                and $0F', 'ri_c:           ld a,h\n                and $07'),
    ('retardo se decrementa de mas', 'vm_core.asm', '                ld a,(ix+SL_DELAY)\n                sub c',
     '                ld a,(ix+SL_DELAY)\n                dec a\n                sub c'),
    ('delta sin limitar a 15', 'vm_core.asm', '                cp 16\n                jr c,vf_ok', '                cp 255\n                jr c,vf_ok'),
    ('padre no se restaura', 'vm_core.asm', '                ld a,c\n                jp load_slot            ; el padre sigue donde estaba',
     '                jr rn_none'),
    ('freeze ignora freezeResistant', 'vm_core.asm', '                and $20\n                jr z,fz_y', '                and $00\n                jr z,fz_y'),
    ('unfreeze no descongela', 'vm_core.asm', '                jr nz,uf_n\n                res 7,(ix+SL_STAT)', '                jr nz,uf_n\n                res 6,(ix+SL_STAT)'),
    ('stopScript no limpia los anidados', 'vm_core.asm', '                call sa_where\n                jr nz,sn_n', '                call sa_where\n                jr sn_n'),
    ('runAllScripts sin didexec', 'vm_core.asm', '                ld a,(hl)\n                or a\n                jr nz,ra_n', '                xor a\n                or a\n                jr nz,ra_n'),
    ('vararg de 2 valores', 'vm_core.asm', '                cp NLOCAL\n                jr nc,rva_l', '                cp 2\n                jr nc,rva_l'),
    ('D5: pagina mal calculada', 'vm_core.asm', '                add a,WINDOW/256\n                ld d,a', '                add a,WINDOW/256+1\n                ld d,a'),
    ('endCutscene no baja el override', 'vm_ops.asm', '                jr z,he_1\n                dec (ix+SL_CUTOV)', '                jr z,he_1\n                dec (ix+SL_FREEZE)'),
    ('beginOverride no salta el jump', 'vm_ops.asm',
     '                inc de                  ; se salta el jumpRelative que sigue (fetchScriptByte + fetchScriptWord)\n                inc de\n                inc de',
     '                nop'),
    ('abort sin VAR_OVERRIDE', 'vm_core.asm', 'ac_v:           ld hl,1', 'ac_v:           ld hl,0'),
    ('getRandomNr sin +1', 'vm_ops.asm', '                add hl,de\n                inc hl\n                ld (RNDST),hl', '                add hl,de\n                ld (RNDST),hl'),
    ('divide: signo mal', 'vm_ops.asm', '                ld a,h\n                xor b\n                push af', '                ld a,h\n                or b\n                push af'),
    ('cadena: $FF 8 lleva bytes', 'vm_core.asm', '                cp 8\n                jr z,ss_l', '                cp 9\n                jr z,ss_l'),
    ('anfitrion: salto al reves', 'vm_core.asm', '                ld a,(HFLAG)\n                or a\n                ret nz', '                ld a,(HFLAG)\n                or a\n                ret z'),
    ('anfitrion: resultado + 1', 'vm_core.asm', '                ld bc,(HRES)\n                jp set_res', '                ld bc,(HRES)\n                inc bc\n                jp set_res'),
    ('expression: resta al reves', 'ovlb.asm', 'ex_sub:         ld hl,(N1)\n                ld de,(N2)', 'ex_sub:         ld hl,(N2)\n                ld de,(N1)'),
    # ---- fase 4a (ovb4.asm)
    ('getActorRoom + 1', 'ovb4.asm', '                ld c,(ix+A_ROOM)\n                ld b,0\n                jp set_res', '                ld c,(ix+A_ROOM)\n                inc c\n                ld b,0\n                jp set_res'),
    ('getActorX lee la y', 'ovb4.asm', 'b_getActorX:    ld a,A_X', 'b_getActorX:    ld a,A_Y'),
    ('startSound no pone el temporizador a 0', 'ovb4.asm', '                ld hl,0\n                ld (VAR_MUSIC_TIMER),hl\n                jr snd_go', '                jr snd_go'),
    ('startMusic sin VAR_LAST_SOUND', 'ovb4.asm', 'snd_go:         ld (VAR_LAST_SOUND),bc', 'snd_go:         nop'),
    # ---- fase 4b-1 (ovb4b.asm), una o dos por grupo
    ('ifState invertido', 'ovb4b.asm', 'b_ifState:      call get_st_cmp\n                jp z,no_jump', 'b_ifState:      call get_st_cmp\n                jp nz,no_jump'),
    ('clase 29 mal traducida', 'ovb4b.asm', '                sub 11\n                ret\ncx_h2', '                sub 10\n                ret\ncx_h2'),
    ('clase se apaga sin cpl', 'ovb4b.asm', 'pc_off:         cpl\n                and (hl)', 'pc_off:         nop\n                and (hl)'),
    ('findInventory: el contador no sube', 'ovb4b.asm', '                ld hl,(SC+0)\n                inc hl\n                ld (SC+0),hl\n                ld bc,(SC+2)',
     '                ld hl,(SC+0)\n                nop\n                ld (SC+0),hl\n                ld bc,(SC+2)'),
    ('setStringChar no limita el crecimiento', 'ovb4b.asm', '                ret nc                  ; b >= longitud + 2: nada', '                nop                     ; b >= longitud + 2: nada'),
    ('str_resize no corre las demas cadenas', 'ovb4b.asm', '                jr nc,sr_up\n                ld hl,(SC+14)', '                jr sr_up\n                ld hl,(SC+14)'),
    ('getStringWidth cuenta el 0', 'ovb4b.asm', 'gw_l:           ld a,(hl)\n                inc hl\n                or a\n                jr z,gw_n', 'gw_l:           ld a,(hl)\n                inc hl\n                or a\n                jr z,gw_x\ngw_x:'),
    ('cursor: sumar como restar', 'ovb4b.asm', '                bit 0,a\n                jr nz,cc_dec', '                bit 0,a\n                jr z,cc_dec'),
    ('verbo nuevo sin color', 'ovb4b.asm', '                ld (ix+V_COL),2\n                ld (ix+V_HI),14', '                ld (ix+V_COL),3\n                ld (ix+V_HI),14'),
    ('restaurar verbos deja el saveid', 'ovb4b.asm', '                call verb_ix\n                ld (ix+V_SAVE),0\n                jr sr_next', '                call verb_ix\n                ld (ix+V_SAVE),1\n                jr sr_next'),
    ('actorOps elevacion sin redibujar', 'ovb4b.asm', 'k9_ch:          ld (ix+A_ELEV),c\n                ld (ix+A_ELEV+1),b\n                set 0,(ix+A_FLAGS)', 'k9_ch:          ld (ix+A_ELEV),c\n                ld (ix+A_ELEV+1),b\n                set 1,(ix+A_FLAGS)'),
    ('actorOps talk start/stop cruzados', 'ovb4b.asm', '                ld (ix+A_TSTART),c\n                call rd_vb2\n                ld (ix+A_TSTOP),c', '                ld (ix+A_TSTOP),c\n                call rd_vb2\n                ld (ix+A_TSTART),c'),
    ('initActor cambia el ancho', 'ovb4b.asm', '                ld (ix+A_WIDTH),24\n                ld (ix+A_TALKC),15', '                ld (ix+A_WIDTH),25\n                ld (ix+A_TALKC),15'),
    ('roomOps 1 sin tope superior', 'ovc1.asm', '                ld hl,(SC+16)\n                ret\nrc_3', '                ld hl,(SC+14)\n                ret\nrc_3'),
    ('lights no cambia VAR_CURRENT_LIGHTS', 'ovc1.asm', '                ld hl,(ARGS)\n                ld (VAR_CURRENT_LIGHTS),hl', '                ld hl,(ARGS)\n                ld (VAR_CURRENT_LIGHTS+2),hl'),
    ('saveLoadGame: 3 por 4', 'ovc1.asm', '                ld l,3\n                jr z,sg_ok', '                ld l,4\n                jr z,sg_ok'),
    ('resourceRoutines: el 17 lee operando', 'ovc1.asm', '                cp 17\n                jr z,rr_nr', '                cp 18\n                jr z,rr_nr'),
    # ---- fase 4b-2 (ovb4c.asm y talk_frame de vm_core.asm): mensajes
    ('displayDialog: talk_delay no usa VAR_CHARINC', 'ovb4c.asm', '                ld de,(VAR_CHARINC)\n                add hl,de\n                ld (TALKDLY),hl',
     '                ld de,4\n                add hl,de\n                ld (TALKDLY),hl'),
    ('convertMessage: la arroba se imprime', 'ovb4c.asm', "                cp $40\n                jr z,cm_run             ; '@' no se imprime",
     "                cp $41\n                jr z,cm_run             ; '@' no se imprime"),
    ('emit_dec: sin signo menos', 'ovb4c.asm', "                bit 7,b\n                jr z,ed_p\n                ld a,'-'", "                bit 6,b\n                jr z,ed_p\n                ld a,'-'"),
    ('actorTalk: color de la ranura en vez del del actor', 'ovb4c.asm', '                ld a,(ix+A_TALKC)\n                jr at_cs', '                ld a,(WRK+W_C)\n                jr at_cs'),
    ('print: subopcode 2 (right) escribe height', 'ovb4c.asm', 'pm_k2:          call rd_vw1\n                ld (WRK+W_R),bc', 'pm_k2:          call rd_vw1\n                ld (WRK+W_H),bc'),
    ('print: no actualiza los valores por omision', 'ovb4c.asm', 'pm_dflt:        call slot_def', 'pm_dflt:        ret\n                call slot_def'),
    ('displayDialog: $FF 14 salta 2', 'ovb4c.asm', 'dg_c14:         ld de,3', 'dg_c14:         ld de,2'),
    ('talk_frame: el talk_delay negativo no se pone a 0', 'vm_core.asm', 'tf_clr:         ld hl,0\ntf_set:', 'tf_clr:         ld hl,-1\ntf_set:'),
    ('print slot 1: center y overhead cruzados', 'ovb4c.asm', '                ld a,(WRK+W_OVH)\n                add a,a\n                ld hl,WRK+W_CEN\n                or (hl)',
     '                ld a,(WRK+W_CEN)\n                add a,a\n                ld hl,WRK+W_OVH\n                or (hl)'),
]


def run(cmd, cwd=HERE):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


def main():
    rooms = sys.argv[1] if len(sys.argv) > 1 else '1,15'
    os.makedirs(MUT, exist_ok=True)
    if not os.path.exists(os.path.join(MUT, 'expected.txt')):
        r = run([sys.executable, '-I', os.path.join(TOOLS, 'vmmodel3.py'), GAME, 'scenarios-core', MUT, '1', rooms])
        print(r.stdout.strip())
    src = {}
    for fn in os.listdir(ENGINE):
        if fn.endswith(('.asm', '.inc')):
            with open(os.path.join(ENGINE, fn), 'rb') as fh:
                src[fn] = fh.read().decode('utf-8').replace('\r\n', '\n')
    detected = 0
    missed = []
    only = sys.argv[2].split('|') if len(sys.argv) > 2 else None        # (opcional) solo las mutaciones cuyo nombre contenga alguna de estas palabras
    for name, f, old, new in M:
        if only and not any(w in name for w in only):
            continue
        if old not in src[f]:
            print('%-45s PATRON NO ENCONTRADO' % name)
            missed.append(name + ' (patron)')
            continue
        for fn, txt in src.items():
            with open(os.path.join(MUT, fn), 'wb') as fh:
                fh.write((txt.replace(old, new, 1) if fn == f else txt).encode('utf-8'))
        r = run(['pasmo', 'vm.asm', 'vm.bin', 'vm.sym'], MUT)
        r2 = run(['pasmo', 'ovlb.asm', 'ovlb.bin', 'ovlb.sym'], MUT) if not r.returncode else r
        r3 = run(['pasmo', 'ovlc.asm', 'ovlc.bin', 'ovlc.sym'], MUT) if not r2.returncode else r2
        if r.returncode or r2.returncode or r3.returncode:
            print('%-45s NO ENSAMBLA: %s' % (name, (r.stderr + r2.stderr + r3.stderr).strip().splitlines()[-1:]))
            missed.append(name + ' (no ensambla)')
            continue
        run([os.path.join(B, 'test_vm.exe'), os.path.join(MUT, 'vm.bin'), os.path.join(MUT, 'vm.sym'), os.path.join(MUT, 'ovlb.bin'),
             os.path.join(B, 'DATA.BIN'), os.path.join(MUT, 'scenarios.txt'), os.path.join(MUT, 'actual.txt'), os.path.join(MUT, 'ovlc.bin')])
        r = run([sys.executable, '-I', 'compare_traces.py', os.path.join(MUT, 'expected.txt'), os.path.join(MUT, 'actual.txt'), '0'])
        n = int(r.stdout.strip().split('\n')[0].split('distintos: ')[1])
        print('%-45s %5d escenarios distintos' % (name, n))
        if n:
            detected += 1
        else:
            missed.append(name)
    nm = len([1 for m in M if not only or any(w in m[0] for w in only)])
    print('\nmutaciones: %d, detectadas: %d, sin detectar: %d' % (nm, detected, nm - detected))
    for m in missed:
        print('  sin detectar:', m)
    return 1 if missed else 0


if __name__ == '__main__':
    sys.exit(main())
