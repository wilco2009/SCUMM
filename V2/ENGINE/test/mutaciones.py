#!/usr/bin/env python3
"""Pruebas de mutacion del nucleo: se estropea el Z80 a proposito y se cuenta cuantos escenarios cambian.

Una mutacion que no cambia ningun escenario significa que los escenarios no cubren ese codigo (o que la
mutacion no cambia el comportamiento observable). Uso (tras build_test.sh): python mutaciones.py
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.dirname(HERE)
B = os.path.join(HERE, 'build')

# (descripcion, fichero, texto original, texto nuevo)
M = [
    # ---- nucleo
    ('isEqual invertido', 'vm.asm',
     'ld de,(ARGS)\n                or a\n                sbc hl,de\n                ret z\n                jr do_jump3',
     'ld de,(ARGS)\n                or a\n                sbc hl,de\n                ret nz\n                jr do_jump3'),
    ('increment resta', 'vm.asm', '                inc bc\n                pop af\n                jp write_var',
     '                dec bc\n                pop af\n                jp write_var'),
    ('variables 14-16 sin redireccion', 'vm.asm', '                cp 14\n                jr c,rv_done',
     '                cp 15\n                jr c,rv_done'),
    ('stopScript no limpia los anidados', 'vm.asm',
     '                ld a,(ix+2)\n                cp WIO_GLOBAL\n                jr z,sn_kill',
     '                ld a,(ix+2)\n                cp 9\n                jr z,sn_kill'),
    ('startScript 155', 'vm.asm', '                cp 155', '                cp 156'),
    ('startScript 87', 'vm.asm', '                cp 87', '                cp 86'),
    ('delay: un byte sin invertir', 'vm.asm',
     '                ld a,(ARGS+2)\n                cpl\n                ld (ix+8),a',
     '                ld a,(ARGS+2)\n                ld (ix+8),a'),
    ('retardo se decrementa de mas', 'vm.asm', '                ld a,(DELTA)\n                ld c,a',
     '                ld a,(DELTA)\n                inc a\n                ld c,a'),
    ('padre no se restaura', 'vm.asm', '                ld a,c\n                jp load_slot            ; el padre sigue donde estaba',
     '                jr rn_none'),
    ('stop_object_code de objeto no mata', 'vm.asm',
     '                pop hl                  ; objeto o sala: numero 0 y muerta\n                xor a\n                ld (hl),a',
     '                pop hl\n                xor a\n                inc a'),
    ('getBitVar mal desplazado', 'vm.asm', '                djnz gbv_l\ngbv_0:', '                djnz gbv_l\n                srl e\ngbv_0:'),
    ('cadena sin byte extra', 'vm.asm',
     '                cp 8\n                jr nc,ss_l\n                ld a,(hl)\n                inc hl\n                call ss_acc',
     '                cp 8\n                jr nc,ss_l'),
    ('doSentence: FB no corta', 'vm.asm', '                cp $FB\n                ret z', '                cp $FA\n                ret z'),
    ('variable 40 sin la correccion', 'vm.asm', '                cp 40                   ;', '                cp 41                   ;'),
    ('estado 182/193', 'vm.asm', '                cp 182', '                cp 183'),
    ('frame: delta sin limitar', 'vm.asm', '                cp 16\n                jr c,vf_ok\n                ld a,15\n                ld (DELTA),a',
     '                cp 16\n                jr c,vf_ok'),
    ('frame: VAR_HAVE_MSG sin actualizar', 'vm.asm', '                ld (VARS+6),hl          ; VAR_HAVE_MSG\n                jp run_all',
     '                jp run_all'),
    # ---- capa de juego
    ('retardo por caracter 5', 'game.asm', '                ld de,6\n                add hl,de\n                ld (TALKDLY),hl',
     '                ld de,5\n                add hl,de\n                ld (TALKDLY),hl'),
    ('retardo base 59', 'game.asm', '                ld hl,60\n                ld (TALKDLY),hl', '                ld hl,59\n                ld (TALKDLY),hl'),
    ('stop_talk no limpia keepText', 'game.asm', 'stk_end:\n                xor a\n                ld (KEEPTXT),a',
     'stk_end:\n                xor a'),
    ('codigo 2 no activa keepText', 'game.asm', '                inc a\n                ld (KEEPTXT),a\n                jr dt_done',
     '                ld (KEEPTXT),a\n                jr dt_done'),
    ('arroba no se descarta', 'game.asm', '                cp $40\n                jr z,cm_space           ; la arroba',
     '                cp $41\n                jr z,cm_space           ; la arroba'),
    ('espacio con el bit 7', 'game.asm', '                bit 7,b\n                jr z,cm_loop', '                bit 6,b\n                jr z,cm_loop'),
    ('emit_dec sin signo', 'game.asm', "                ld a,'-'\n                call emit_a", '                nop'),
    ('show_actor sin dejar de hablar', 'game.asm',
     '                ld a,TALK_STOP\n                call start_anim\n                ld (ix+8),0\n                ld (ix+9),1',
     '                ld (ix+8),0\n                ld (ix+9),1'),
    ('hide_actor no para el movimiento', 'game.asm',
     '                ld a,(ix+8)\n                or a\n                jr z,ha_1\n                ld (ix+8),0\n                ld a,STAND\n                call start_anim\nha_1:',
     'ha_1:'),
    ('put_actor no oculta al cambiar de sala', 'game.asm', 'pa_hide:\n                jp hide_actor', 'pa_hide:\n                ret'),
    ('put_actor no muestra', 'game.asm', 'pa_hidden:\n                ld a,(CURROOM)\n                cp (ix+0)\n                ret nz\n                jp show_actor',
     'pa_hidden:\n                ret'),
    ('put_actor no calla al hablante', 'game.asm',
     '                sbc hl,bc\n                jr nz,pa_set\n                push ix\n                call stop_talk\n                pop ix',
     '                sbc hl,bc\n                jr nz,pa_set'),
    ('set_costume sin ocultar', 'game.asm',
     '                push bc\n                call hide_actor\n                pop bc\n                ld (ix+5),c\n                jp show_actor',
     '                ld (ix+5),c\n                ret'),
    ('start_anim sin redireccion', 'game.asm', 'sa_table:       defb INIT_FRAME,WALK_FRAME,STAND,TALK_START,TALK_STOP',
     'sa_table:       defb INIT_FRAME,WALK_FRAME,STAND,TALK_STOP,TALK_START'),
    ('animateActor no borra el giro', 'game.asm', '                and $FB\n                ld (ix+8),a\n                call old_dir',
     '                ld (ix+8),a\n                call old_dir'),
    ('tabla de direcciones', 'game.asm', 'old_dir_table:  defw 270,90,180,0', 'old_dir_table:  defw 270,180,90,0'),
    ('loadRoom no mata los scripts de sala', 'game.asm', '                call kill_scripts\n                call reset_sentence',
     '                call reset_sentence'),
    ('loadRoom no oculta actores', 'game.asm', '                ld ix,ACTORS+16\n                ld b,NACTORS-1\nss_hide:',
     '                ld ix,ACTORS+16\n                ld b,1\nss_hide:'),
    ('loadRoom sin el script 5', 'game.asm', '                ld de,5\n                jp run_script           ; v1 y v2',
     '                ret                     ; v1 y v2'),
    ('loadRoom: camara maxima', 'game.asm', '                or a\n                sbc hl,de\n                ld (VARS+48),hl',
     '                or a\n                ld (VARS+48),hl'),
    ('startSound sin VAR_LAST_SOUND', 'game.asm', '                ld (VARS+74),hl         ; VAR_LAST_SOUND\n',
     ''),
    ('stopMusic no borra LASTSND', 'game.asm', 'h_o5_stopMusic:\n                ld hl,0\n                ld (LASTSND),hl',
     'h_o5_stopMusic:\n                ld hl,0'),
    ('talker_ix no valida', 'game.asm', '                cp NACTORS\n                jr nc,tk_none\n                call actor_addr',
     '                call actor_addr'),
    ('run_talk_script ignora el fotograma', 'game.asm', '                ld a,(ix+10)\n                cp c\n                ret z\n                ld a,c\n                jp start_anim',
     '                ld a,c\n                jp start_anim'),
    # ---- movimiento
    ('remap: banderas sin mascara', 'walk.asm', '                ld a,c\n                and 7\n                ld c,a', '                ld a,c\n                and 15\n                ld c,a'),
    ('REMAP1', 'walk.asm', 'REMAP1:         defb $04,$01,$02,$00,$01,$02,$03,$00,$06,', 'REMAP1:         defb $04,$01,$02,$00,$01,$02,$03,$00,$05,'),
    ('REMAP2', 'walk.asm', 'REMAP2:         defb $00,$01,$03,$02,$03,$00,$02,$00,$00,', 'REMAP2:         defb $00,$01,$03,$02,$03,$00,$02,$01,$00,'),
    ('REMAP3', 'walk.asm', 'REMAP3:         defb $00,$00,$02,$00,$01,$03,$02,$00,$01,$01,', 'REMAP3:         defb $00,$01,$02,$00,$01,$03,$02,$00,$01,$01,'),
    ('TURN_TABLE', 'walk.asm', 'TURN_TABLE:     defb 0,2,2,3,2,1,2,3,0,1,2,1,0,1,0,3', 'TURN_TABLE:     defb 0,2,2,3,2,1,2,3,0,1,2,1,0,1,3,3'),
    ('giro: no limpia la bandera', 'walk.asm', '                res 2,(ix+8)\n                ret\nwa_notturn:', '                ret\nwa_notturn:'),
    ('paso: x sin tope', 'walk.asm', '                cp (ix+26)\n                jr nz,aw_xmove', '                cp (ix+26)\n                jr aw_xmove'),
    ('paso: y sin tope', 'walk.asm', '                cp (ix+28)\n                jr nz,aw_ymove', '                cp (ix+28)\n                jr aw_ymove'),
    ('paso: x sin restar el umbral', 'walk.asm', 'aw_xstore:\n                ld (ix+30),l', 'aw_xstore:\n                add hl,de\n                ld (ix+30),l'),
    ('paso: llegada', 'walk.asm', '                set 1,(ix+8)\n                ret\n\ncalc_movement_factor:', '                ret\n\ncalc_movement_factor:'),
    ('calc: dxf', 'walk.asm', 'cm_dx:\n                ld (ix+38),l', 'cm_dx:\n                inc hl\n                ld (ix+38),l'),
    ('calc: umbral minimo', 'walk.asm', '                jr nc,cm_th\n                ld hl,(WK_ADX)', '                jr c,cm_th\n                ld hl,(WK_ADX)'),
    ('calc: wfacing', 'walk.asm', '                ld a,3\n                sub b\ncm_ws:', '                ld a,2\n                sub b\ncm_ws:'),
    ('calc: direccion vertical', 'walk.asm', '                ld a,3                  ; k = 3 - (dy >= 0)', '                ld a,2                  ; k = 3 - (dy >= 0)'),
    ('calc: sin giro', 'walk.asm', '                jr z,cm_same\n                set 2,(ix+8)', '                jr z,cm_same\n                nop'),
    ('calc: sin fotograma de caminar', 'walk.asm', 'cm_anim:\n                xor a                   ; WALK_FRAME', 'cm_anim:\n                ld a,STAND'),
    ('start_walk: ya esta alli', 'walk.asm', '                ret z                   ; ya esta alli y mirando hacia donde debe', '                nop'),
    ('start_walk: fuera de la sala', 'walk.asm', '                ld (ix+6),l\n                ld (ix+7),h\n                ret\nsw_in:', '                ret\nsw_in:'),
    ('start_walk: sin tramo nuevo', 'walk.asm', '                or MF_IN_LEG+MF_NEW_LEG', '                or MF_IN_LEG'),
    ('walk: ultimo tramo sin giro final', 'walk.asm', '                ld h,(ix+24)\n                jp turn_to_dir', '                ld h,(ix+24)\n                ret'),
    ('walk: caja cerrada no pone destdir', 'walk.asm', '                ld (ix+23),l\n                ld (ix+24),h\nwa_unlocked:', 'wa_unlocked:'),
    ('walk: cerrada solo jugador', 'walk.asm', '                jr nc,wa_unlocked\nwa_lock:', '                jr c,wa_unlocked\nwa_lock:'),
    ('walk: cerrada ignora la bandera', 'walk.asm', '                bit 6,c                 ; cerrada con llave?', '                bit 5,c                 ; cerrada con llave?'),
    ('walk: sin camino', 'walk.asm', '                set 3,(ix+8)            ; no hay camino\n                ret', '                ret'),
    ('next_box: base', 'walk.asm', '                cp $FF\n                jr nz,nb_b0', '                cp $FE\n                jr nz,nb_b0'),
    ('next_box: destino invalido', 'walk.asm', 'nb_1:\n                ld a,c\n                cp $FF', 'nb_1:\n                ld a,c\n                cp $FE'),
    ('next_box: origen invalido', 'walk.asm', 'nb_2:\n                ld a,b\n                cp $FF', 'nb_2:\n                ld a,b\n                cp $FE'),
    ('caja: tabla de aristas', 'walk.asm', 'PB_E:           defb 4,12,8,0', 'PB_E:           defb 4,12,8,4'),
    ('caja: mas cercano', 'walk.asm', '                sbc hl,de\n                jr nc,cb_next', '                sbc hl,de\n                jr c,cb_next'),
    ('recta: recorte inicio', 'geom.asm', '                ld hl,(LN_RX)           ; lx > 0\n                ld de,(LN_SX)\n                call sless\n                jr c,cc_start', '                ld hl,(LN_RX)           ; lx > 0\n                ld de,(LN_SX)\n                call sless\n                jr nc,cc_start'),
    ('recta: recorte final', 'geom.asm', '                ld hl,(LN_EX)\n                ld de,(LN_RX)\n                call sless\n                jr c,cc_end\n                ret\ncc_xneg:', '                ld hl,(LN_EX)\n                ld de,(LN_RX)\n                call sless\n                jr nc,cc_end\n                ret\ncc_xneg:'),
    ('recta: rama vertical', 'geom.asm', '                ld hl,(LN_SX)           ; recta vertical\n                ld (LN_RX),hl', '                ld hl,(LN_EX)           ; recta vertical\n                ld (LN_RX),hl'),
    ('recta: rama horizontal', 'geom.asm', '                ld hl,(LN_SY)\n                ld (LN_RY),hl\n                jp cl_clamp', '                ld hl,(LN_EY)\n                ld (LN_RY),hl\n                jp cl_clamp'),
    ('recta: a de la rama x', 'geom.asm', '                ld hl,(LN_SX)\n                ld de,(LN_LY)\n                ld bc,(LN_LX)\n                call muldiv', '                ld hl,(LN_SX)\n                ld de,(LN_LY)\n                ld bc,(LN_LY)\n                call muldiv'),
    ('recta: c sin py', 'geom.asm', 'calc_c_sy_py:\n                ld hl,(LN_SY)\n                ld de,(LN_PY)', 'calc_c_sy_py:\n                ld hl,(LN_SY)\n                ld de,(LN_PX)'),
    ('recta: y de la rama x', 'geom.asm', '                ld de,(LN_SY)\n                add hl,de\n                ld (LN_RY),hl', '                ld de,(LN_SX)\n                add hl,de\n                ld (LN_RY),hl'),
    ('recta: x de la rama y', 'geom.asm', '                ld de,(LN_SX)\n                add hl,de\n                ld (LN_RX),hl', '                ld de,(LN_SY)\n                add hl,de\n                ld (LN_RX),hl'),
    ('division con signo', 'geom.asm', '                ld a,(DSGN)\n                rla\n                ret nc', '                ld a,(DSGN)\n                rla\n                or a\n                ret'),
    ('checkXY: recorte superior', 'geom.asm', '                ld hl,(CK_UY)           ; y < uy\n                ld (CK_DY),hl', '                ld hl,(CK_LY)           ; y < uy\n                ld (CK_DY),hl'),
    ('checkXY: caja inferior', 'geom.asm', '                ld hl,(CK_LLX)\n                ld (CK_XMIN),hl\n                ld hl,(CK_LRX)', '                ld hl,(CK_ULX)\n                ld (CK_XMIN),hl\n                ld hl,(CK_LRX)'),
    ('checkXY: dentro', 'geom.asm', '                ld de,(CK_URX)\n                call sless\n                jr nc,cx_search', '                ld de,(CK_URX)\n                call sless\n                jr c,cx_search'),
    ('checkXY: busqueda', 'geom.asm', 'cx_up:\n                ld (CK_TOP),hl', 'cx_up:\n                ld (CK_BOT),hl'),
    ('checkXY: distancia', 'geom.asm', '                add hl,de\n                ret\ncx_d1:', '                add hl,de\n                inc hl\n                ret\ncx_d1:'),
    ('checkXY: yd', 'geom.asm', '                srl h\n                rr l\n                srl h\n                rr l\n                ex de,hl                ; DE = yd', '                srl h\n                rr l\n                ex de,hl                ; DE = yd'),
    ('adjust: invisibles', 'geom.asm', '                and $80\n                jr z,ax_ok              ; no es invisible', '                and $40\n                jr z,ax_ok              ; no es invisible'),
    ('adjust: solo jugador', 'geom.asm', '                jr z,ax_ok              ; solo del jugador y no lo es: se usa', '                jr nz,ax_ok             ; solo del jugador y no lo es: se usa'),
    ('adjust: mejor distancia', 'geom.asm', '                jr z,ax_next\n                jr c,ax_next            ; dist >= best', '                jr z,ax_next\n                jr nc,ax_next           ; dist >= best'),
    ('adjust: caja encontrada', 'geom.asm', 'ax_found:\n                ld hl,(CK_DX)', 'ax_found:\n                ld hl,(CK_DY)'),
    ('caja n se lee como n-1', 'geom.asm', '                dec a                   ; la caja n se lee como la n-1', '                nop                     ; la caja n se lee como la n-1'),
    ('es jugador: limite', 'geom.asm', '                ld hl,(VARS+86)\n                ld e,(ix+15)', '                ld hl,(VARS+84)\n                ld e,(ix+15)'),
    ('posicion: sin ajustar', 'walk.asm', 'adjust_actor_pos:                       ; IX = actor\n', 'adjust_actor_pos:                       ; IX = actor\n                ret\n'),
    ('posicion: sin giro', 'walk.asm', '                and 7\n                ret z\n                ld l,(ix+6)', '                and 7\n                ret\n                ld l,(ix+6)'),
    ('putActorAtObject: por defecto', 'walk.asm', '                ld hl,30\n                ld (PA_X),hl', '                ld hl,31\n                ld (PA_X),hl'),
    ('walkActorToActor: signo', 'walk.asm', '                jr nc,wa2_minus\n                add hl,de', '                jr c,wa2_minus\n                add hl,de'),
    ('faceActor: eje', 'walk.asm', '                ld b,2\n                jr nc,fa_turn', '                ld b,3\n                jr nc,fa_turn'),
    ('faceActor: umbral', 'walk.asm', '                ld de,2\n                or a\n                sbc hl,de\n                jr nc,fa_turn', '                ld de,3\n                or a\n                sbc hl,de\n                jr nc,fa_turn'),
    ('waitForActor no espera', 'walk.asm', '                ld a,(ix+8)\n                or a\n                ret z\n                ld hl,(SPTR)', '                ld a,(ix+8)\n                or a\n                ret\n                ld hl,(SPTR)'),
    ('getActorX de un objeto', 'walk.asm', 'gx_none:\n                ld bc,$FFFF', 'gx_none:\n                ld bc,$FFFE'),
    ('getActorFacing', 'walk.asm', '                call n2o\n                ld c,a\n                jr gt_b', '                call n2o\n                inc a\n                ld c,a\n                jr gt_b'),
    ('getActorWalkBox fuera de la sala', 'walk.asm', '                ld c,$FF\n                ld a,(CURROOM)', '                ld c,$FE\n                ld a,(CURROOM)'),
    ('elevacion sin signo', 'walk.asm', '                ld c,a\n                rla\n                sbc a,a\n                ld b,a\n                jr gt_w', '                ld c,a\n                ld b,0\n                jr gt_w'),
    ('objeto: busca por id', 'walk.asm', '                ld a,(ix+1)\n                cp h\n                jr nz,wo_next', '                ld a,(ix+1)\n                cp 0\n                jr nz,wo_next'),
    ('objeto: dueno', 'walk.asm', '                cp $0F\n                jr z,wo_room', '                cp $0E\n                jr z,wo_room'),
    ('objeto: inventario', 'walk.asm', '                ld a,2\n                ret\nwo_room:', '                xor a\n                ret\nwo_room:'),
    ('cargar sala: matriz', 'game.asm', 'lb_mul:\n                add hl,de', 'lb_mul:\n                add hl,de\n                inc hl'),
    ('mostrar actor sin ajustar', 'game.asm', '                call adjust_actor_pos\n                ld a,(ERR)\n                or a\n                ret nz\n                ld a,STAND', '                ld a,STAND'),
    ('vm_frame sin caminar', 'vm.asm', '                ld a,(CURROOM)\n                or a\n                ret z\n                jp walk_actors', '                ret'),
    ('walk_actors: solo en la sala', 'walk.asm', '                cp (ix+0)\n                call z,walk_actor', '                cp (ix+0)\n                call walk_actor'),
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=HERE)


def main():
    detected = 0
    missed = []
    for name, f, old, new in M:
        d = {}
        for fn in ('vm.asm', 'game.asm', 'geom.asm', 'walk.asm', 'tables.inc'):
            with open(os.path.join(ENGINE, fn), 'rb') as fh:
                d[fn] = fh.read().decode('utf-8').replace('\r\n', '\n')
        if old not in d[f]:
            print('%-45s PATRON NO ENCONTRADO' % name)
            continue
        d[f] = d[f].replace(old, new, 1)
        for fn, txt in d.items():
            with open(os.path.join(B, 'mut.asm' if fn == 'vm.asm' else fn), 'wb') as fh:
                fh.write(txt.encode('utf-8'))
        r = subprocess.run(['pasmo', 'mut.asm', 'mut.bin', 'mut.sym'], capture_output=True, text=True, cwd=B)
        if r.returncode:
            print('%-45s NO ENSAMBLA: %s' % (name, r.stderr.strip()))
            continue
        run([os.path.join(B, 'test_vm.exe'), os.path.join(B, 'mut.bin'), os.path.join(B, 'mut.sym'), os.path.join(B, 'world.bin'),
             os.path.join(B, 'scenarios.txt'), os.path.join(B, 'actual_mut.txt')])
        r = run([sys.executable, '-I', 'compare_traces.py', os.path.join(B, 'expected.txt'), os.path.join(B, 'actual_mut.txt'), '0'])
        line = r.stdout.strip().split('\n')[0]
        n = int(line.split('distintos: ')[1])
        print('%-45s %5d escenarios distintos' % (name, n))
        if n:
            detected += 1
        else:
            missed.append(name)
    print('\nmutaciones: %d, detectadas: %d, sin detectar: %d' % (len(M), detected, len(M) - detected))
    for m in missed:
        print('  sin detectar:', m)


if __name__ == '__main__':
    main()
