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
    ('local sin doblar el indice', 'vm_core.asm', '                jp nc,err_range\n                add a,a\n                ld l,a\n                ld a,(CUR)', '                jp nc,err_range\n                ld l,a\n                ld a,(CUR)'),
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
    # (las mutaciones del anfitrion con resultado y con salto -- h_host_r, h_host_j -- se retiraron en la fase 5: ya no hay ningun opcode que use esas rutas)
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
    ('getStringWidth cuenta el 0', 'ovb4b.asm', '                dec b\n                or a\n                jr z,gw_e\n                cp 10', '                dec b\n                or a\n                jr z,gw_n\n                cp 10'),
    ('cursor: sumar como restar', 'ovb4b.asm', '                bit 0,a\n                jr nz,cc_dec', '                bit 0,a\n                jr z,cc_dec'),
    ('verbo nuevo sin color', 'ovb4b.asm', '                ld (ix+V_COL),2\n                ld (ix+V_HI),14', '                ld (ix+V_COL),3\n                ld (ix+V_HI),14'),
    ('restaurar verbos deja el saveid', 'ovb4b.asm', '                call verb_ix\n                ld (ix+V_SAVE),0\n                call vd_draw', '                call verb_ix\n                ld (ix+V_SAVE),1\n                call vd_draw'),
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
    # ---- fase 5 (ovc5.asm, vm_core.asm, ovb4.asm, ovb4b.asm, ovb4c.asm): salas, objetos y frases
    ('frases: el verbo se pasa como preposicion', 'ovc5.asm', 'os_run:         ld a,(ix+SQ_VERB)', 'os_run:         ld a,(ix+SQ_PREP)'),
    ('frases: preposicion mal calculada', 'ovc5.asm', 'ld a,1                  ; preposicion = (b <> 0)', 'ld a,2                  ; preposicion = (b <> 0)'),
    ('frases: con preposicion y b == a se ejecuta', 'ovc5.asm', 'ret z                   ; con preposicion y b == a: nada', 'nop                     ; con preposicion y b == a: nada'),
    ('waitForSentence: la frase no congelada no espera', 'ovc5.asm', 'jr z,ws_wait            ; la ultima no esta congelada: esperar', 'jr nz,ws_wait           ; la ultima no esta congelada: esperar'),
    ('freeze no congela la cola de frases', 'vm_core.asm', 'fz_sl:          inc (hl)', 'fz_sl:          nop'),
    ('findObject: UNTOUCHABLE mal', 'ovc5.asm', 'bit 7,(hl)              ; UNTOUCHABLE (clase 32 -> bit 23)', 'bit 6,(hl)              ; UNTOUCHABLE (clase 32 -> bit 23)'),
    ('findObject: estado del padre al reves', 'ovc5.asm', 'fo_cmp:         ld hl,SC+6\n                cp (hl)\n                jr nz,fo_next', 'fo_cmp:         ld hl,SC+6\n                cp (hl)\n                jr z,fo_next'),
    ('findObject: el ancho lee la altura', 'ovc5.asm', 'ld c,(ix+OB_W)\n                ld hl,(SC+0)', 'ld c,(ix+OB_H)\n                ld hl,(SC+0)'),
    ('drawObject: walk_x no multiplica por 8', 'ovc5.asm', 'add hl,hl\n                add hl,hl\n                add hl,hl               ; (x - x0) * 8', 'add hl,hl\n                add hl,hl               ; (x - x0) * 8'),
    ('drawObject: el rectangulo no mira la altura', 'ovc5.asm', 'cp (ix+OB_H)\n                jr nz,dr_n', 'cp (ix+OB_W)\n                jr nz,dr_n'),
    ('pickupObject: sin UNTOUCHABLE', 'ovc5.asm', 'call cls_open\n                set 7,(hl)\n                call cls_close', 'call cls_open\n                set 6,(hl)\n                call cls_close'),
    ('pickupObject: inventario con argumento 0', 'ovc5.asm', 'ld c,1                  ; runInventoryScript(1)', 'ld c,0                  ; runInventoryScript(1)'),
    ('startObject: el verbo $FF no es comodin', 'ovc5.asm', 'ros_l:          ld a,(hl)\n                or a\n                jr z,ros_nw\n                inc a\n                jr z,ros_f', 'ros_l:          ld a,(hl)\n                or a\n                jr z,ros_nw\n                inc a\n                jr z,ros_nw'),
    ('getVerbEntrypoint: devuelve el offset + 1', 'ovc5.asm', 'gve_f:          inc hl\n                ld e,(hl)\n                inc hl\n                ld d,(hl)\n                ex de,hl', 'gve_f:          inc hl\n                ld e,(hl)\n                inc hl\n                ld d,(hl)\n                inc de\n                ex de,hl'),
    ('startScene: no mata los scripts locales', 'ovc5.asm', 'ks_l:           ld a,(ix+SL_WHERE)\n                cp WIO_ROOM\n                jr z,ks_k\n                cp WIO_LOCAL', 'ks_l:           ld a,(ix+SL_WHERE)\n                cp WIO_ROOM\n                jr z,ks_k\n                cp WIO_GLOBAL'),
    ('startScene: VAR_CAMERA_MAX_X con 161', 'ovc5.asm', 'ld de,-160\n                add hl,de\n                ld (VAR_CAMERA_MAX_X),hl', 'ld de,-161\n                add hl,de\n                ld (VAR_CAMERA_MAX_X),hl'),
    ('startScene: no muestra los actores', 'ovc5.asm', 'ld hl,OVB_SHOWACT\n                call call_ovb\n                ', 'nop\n                nop\n                '),
    ('startScene: pseudosala mal enmascarada', 'ovc5.asm', 'and $7F                 ; _resourceMapper', 'and $3F                 ; _resourceMapper'),
    ('loadRoomWithEgo: direccion al reves', 'ovc5.asm', 'lw_dirs:        defw 90,270,0,180', 'lw_dirs:        defw 270,90,0,180'),
    ('isActorInBox: desigualdad al reves (positivos)', 'ovc5.asm', 'ld a,1\n                ret nc\n                xor a\n                ret\neo_neg:', 'ld a,1\n                ret c\n                xor a\n                ret\neo_neg:'),
    ('isActorInBox: rechazo rapido con 3 esquinas', 'ovc5.asm', '                call arj_mm\n                ld l,(iy+12)\n                ld a,(iy+13)\n                xor $80\n                ld h,a\n                call arj_mm\n                pop hl', '                call arj_mm\n                pop hl'),
    ('setBoxFlags: escribe en el byte 16', 'ovc5.asm', 'ld de,17\n                add hl,de\n                pop af\n                ld (hl),a', 'ld de,16\n                add hl,de\n                pop af\n                ld (hl),a'),
    ('nombre de objeto: desplazamiento de 15', 'ovb4c.asm', 'ld de,16\n                add hl,de\n                ld e,(hl)               ; el desplazamiento del nombre', 'ld de,15\n                add hl,de\n                ld e,(hl)               ; el desplazamiento del nombre'),
    ('getObjectXYPos: x e y de acercamiento cruzadas', 'ovb4.asm', 'walk_x, walk_y)\n                ld de,OB_WX', 'walk_x, walk_y)\n                ld de,OB_WY'),
    ('setClass: no cierra la ventana de clases', 'ovb4b.asm', 'pc_off:         cpl\n                and (hl)\n                ld (hl),a\n                call cls_close', 'pc_off:         cpl\n                and (hl)\n                ld (hl),a\n                nop\n                nop\n                nop'),
    # ---- fase 6 (geom.asm y walk.asm en el overlay D, ovc6.asm, walk_frame de vm_core.asm, ovb4.asm, ovb4b.asm): caminata
    ('closestPtOnLine: eje mayor al reves', 'geom.asm', 'ld a,0\n                jr c,cpl_ns', 'ld a,0\n                jr nc,cpl_ns'),
    ('closestPtOnLine: no recorta al inicio del segmento', 'geom.asm', 'jr c,cpl_rs\n                ld hl,(LNE)\n                ld de,(LNR)', 'jr c,cpl_done\n                ld hl,(LNE)\n                ld de,(LNR)'),
    ('closestPtOnLine: pv se resta', 'geom.asm', 'ld bc,(LNP+2)\n                call adds16', 'ld bc,(LNP+2)\n                call subs16'),
    # (el tope de 0x1000 de sqrDist no se puede mutar a mas: con una diferencia de 0x1000 la suma ya pasa de 0xFFFFFF y da lo mismo)
    ('sqrDist: no suma dy', 'geom.asm', 'call mul16u             ; dx * dx\n                pop bc\n                add hl,bc', 'call mul16u             ; dx * dx\n                pop bc\n                or a'),
    ('getClosestPtOnBox: solo 3 aristas', 'geom.asm', 'cpb_n:          ld a,(CBK)\n                inc a\n                ld b,a\n                and 3\n                ld a,b\n                jr nz,cpb_l', 'cpb_n:          ld a,(CBK)\n                inc a\n                ld b,a\n                and 3\n                cp 3\n                ld a,b\n                jr c,cpb_l'),
    ('compareSlope: factores cruzados', 'geom.asm', 'ld hl,(C3)\n                ld de,(C1)\n                call cs_mul\n                ld (CL),hl', 'ld hl,(C2)\n                ld de,(C1)\n                call cs_mul\n                ld (CL),hl'),
    ('adjustXY: el umbral 30 vale para todo', 'geom.asm', 'ld hl,900               ; umbral al cuadrado', 'ld hl,65535             ; umbral al cuadrado'),
    ('adjustXY: las cajas invisibles no se saltan', 'geom.asm', 'jp z,ax_next            ; invisible\n', 'jp z,ax_vis             ; invisible\n'),
    ('adjustXY: no guarda la mejor caja', 'geom.asm', 'ld a,(AXBOX)\n                ld (AXBB),a\nax_next:', 'ld a,(AXBOX)\n                ld (AXBOX),a\nax_next:'),
    ('adjustXY: dentro de la caja no actualiza las coordenadas validas', 'geom.asm', 'ld hl,(BP)              ; dentro de la caja\n                ld (ix+A_LVX),l', 'ld hl,(BP)              ; dentro de la caja\n                ld (ix+A_LVY),l'),
    ('getGates: la esquina va segunda', 'geom.asm', 'cp 4\n                jr nc,sg_1\n                ex (sp),hl', 'cp 4\n                jr c,sg_1\n                ex (sp),hl'),
    ('getGates: sin raiz', 'geom.asm', 'call isqrt16\n                ld c,a', 'ld a,l\n                ld c,a'),
    ('getGates: sin la regla de los dos puntos de la misma caja', 'geom.asm', 'ld hl,GBX+1\n                cp (hl)\n                jr nz,gs_3', 'ld hl,GBX+1\n                cp (hl)\n                jr gs_3'),
    ('getGates: |d0 - d1| < 2', 'geom.asm', 'call absd\n                cp 4\n                jr c,gs_01\ngs_3:', 'call absd\n                cp 2\n                jr c,gs_01\ngs_3:'),
    ('findPathTowardsOld: p2 siempre', 'geom.asm', 'call fp_cs3\n                pop bc\n                cp b\n                ret nz', 'call fp_cs3\n                pop bc\n                cp b\n                nop'),
    ('findPathTowardsOld: sin el atajo de la caja final', 'geom.asm', 'ld hl,FFIN\n                cp (hl)\n                jr nz,fp_1', 'ld hl,FFIN\n                cp (hl)\n                jr fp_1'),
    ('getNextBox: sin el limite superior de la terna', 'geom.asm', 'jr c,gnb_n              ; ultima < hasta', 'or a                    ; ultima < hasta'),
    ('getNextBox: no salta las filas anteriores', 'geom.asm', 'gnb_re:         inc hl\n                dec b', 'gnb_re:         inc hl\n                ld b,0'),
    ('calcMovementFactor: stepX siempre speedx', 'walk.asm', 'ld a,(ix+A_SPEEDX)\n                jr nc,cm_3', 'ld a,(ix+A_SPEEDX)\n                jr cm_3'),
    ('calcMovementFactor: el umbral es el menor', 'walk.asm', 'jr nc,cm_4\n                ex de,hl', 'jr c,cm_4\n                ex de,hl'),
    ('calcMovementFactor: proporcion 2 en vez de 3', 'walk.asm', 'ld c,3\n                call div16_8', 'ld c,2\n                call div16_8'),
    ('calcMovementFactor: sin el arreglo del tramo corto', 'walk.asm', 'bit MF_LAST_LEG,(ix+A_MOVING)\n                jr nz,cm_2', 'bit MF_LAST_LEG,(ix+A_MOVING)\n                jr cm_2'),
    ('calcMovementFactor: walkdata.facing sin el signo de y', 'walk.asm', 'ld a,(CMSY)\n                xor 1\n                jr cm_w2', 'ld a,1\n                xor 1\n                jr cm_w2'),
    ('actorWalkStep: no pasa a la caja siguiente', 'walk.asm', 'call cxb_num\n                or a\n                jr z,ws_nb', 'call cxb_num\n                or a\n                jr ws_nb'),
    ('actorWalkStep: ajuste al punto con un paso menos', 'walk.asm', 'ld a,c\n                cp l\n                ret c', 'ld a,c\n                dec a\n                cp l\n                ret c'),
    ('actorWalkStep: frac no resta el umbral', 'walk.asm', 'wf_1:           pop de\n                push hl', 'wf_1:           pop hl\n                push hl'),
    ('actorWalkStep: no arranca la animacion de andar', 'walk.asm', 'ld c,(ix+A_WALK)\n                call w_start_anim', 'ld c,(ix+A_STAND)\n                call w_start_anim'),
    ('walkActor: al llegar no gira a la direccion final', 'walk.asm', 'ld l,(ix+A_DESTDIR)\n                ld h,(ix+A_DESTDIR+1)\n                ld a,(ix+A_TFACE)', 'ld l,(ix+A_TFACE)\n                ld h,(ix+A_TFACE+1)\n                ld a,(ix+A_TFACE)'),
    ('walkActor: point3 se olvida', 'walk.asm', 'ld hl,(P3)              ; point3 = p3: el tramo siguiente', 'ld hl,32000             ; point3 = p3: el tramo siguiente'),
    ('walkActor: el giro no termina', 'walk.asm', 'jp nz,w_set_dir\n                ld (ix+A_MOVING),0\n                ret', 'jp nz,w_set_dir\n                ld (ix+A_MOVING),4\n                ret'),
    ('walkActor: sin camino no marca el ultimo tramo', 'walk.asm', 'set MF_LAST_LEG,(ix+A_MOVING)   ; no hay camino', 'set MF_IN_LEG,(ix+A_MOVING)     ; no hay camino'),
    ('remapDirection: caja de direccion 1 al reves', 'walk.asm', 'ld a,(UDFX)\n                or a\n                jr nz,ud_90\n                jr ud_270', 'ld a,(UDFX)\n                or a\n                jr z,ud_90\n                jr ud_270'),
    ('remapDirection: el volteo en x del actor no cuenta', 'walk.asm', 'ld a,(UDC)\n                and 4\n                jr z,ud_nx', 'ld a,(UDC)\n                and 0\n                jr z,ud_nx'),
    ('updateActorDirection: tabla de giros', 'walk.asm', 'turn_tbl:       defb 0,2,2,3', 'turn_tbl:       defb 0,2,2,2'),
    ('setDirection: no marca el redibujo', 'walk.asm', 'call in_room\n                ret nz\n                set 0,(ix+A_FLAGS)\n                ret\n\npos16:', 'call in_room\n                ret nz\n                ret\n\npos16:'),
    ('startWalkActor: curbox no se pone', 'walk.asm', 'ld a,(ix+A_WBOX)\n                ld (ix+A_CBOX),a\n                ld a,(ix+A_MOVING)', 'ld a,(ix+A_WBOX)\n                nop\n                ld a,(ix+A_MOVING)'),
    ('startWalkActor: el mismo destino se vuelve a empezar', 'walk.asm', 'sbc hl,de\n                ret z\nsw_eq:', 'sbc hl,de\n                nop\nsw_eq:'),
    ('startWalkActor: ya en el destino no gira', 'walk.asm', 'ld hl,(WKDIR)           ; ya esta en el destino: solo girar', 'ld hl,$FFFF             ; ya esta en el destino: solo girar'),
    ('startWalkActor: fuera de la sala no lo mueve', 'walk.asm', 'ld hl,(WKX)             ; fuera de la sala: se le pone alli\n                ld (ix+A_X),l', 'ld hl,(WKX)             ; fuera de la sala: se le pone alli\n                ld (ix+A_Y),l'),
    ('walkActorToActor: distancia $FF sin la mitad del otro', 'ovc6.asm', 'ld l,(ix+A_WIDTH)\n                srl l', 'ld l,(ix+A_WIDTH)\n                nop'),
    ('walkActorToActor: por el otro lado', 'ovc6.asm', 'jr c,wta_add\n                or a', 'jr nc,wta_add\n                or a'),
    ('walkActorToActor: sin ajustar a las cajas', 'ovc6.asm', 'ld hl,OVD_ADJUST\n                call call_ovd           ; adjustXYToBeInBox(a, x, y)', 'ld hl,OVD_ADJUST\n                nop                     ; adjustXYToBeInBox(a, x, y)'),
    ('walkActorToObject: sin direccion final', 'ovc6.asm', 'ld (WKDIR),de\n                jr wk_start', 'ld (WKDIR),de\n                jr wk_go'),
    ('waitForActor: no espera', 'ovc6.asm', 'or a\n                ret z\n                ld (SPTR),hl\n                jp break_here', 'or a\n                ret\n                ld (SPTR),hl\n                jp break_here'),
    ('walk_frame: solo mira al actor 1', 'vm_core.asm', 'ld b,NACT-1\nwfr_l:', 'ld b,1\nwfr_l:'),
    ('adjustActorPos: sin giro en las cajas con direccion', 'ovb4.asm', 'and 7\n                ret z\n                ld l,(ix+A_FACING)', 'and 0\n                ret z\n                ld l,(ix+A_FACING)'),
    ('animateActor: cambiar de direccion no marca el redibujo', 'ovb4.asm', 'call in_room\n                ret nz\n                set 0,(ix+A_FLAGS)\n                ret\nan_gen:', 'call in_room\n                ret nz\n                ret\nan_gen:'),
    ('actorOps 2: sin recalcular la caminata', 'ovb4b.asm', 'jp z,ao_l\n                push de                 ; el puntero del script', 'jp ao_l\n                push de                 ; el puntero del script'),
    ('loadRoomWithEgo: la caminata no empieza', 'ovc5.asm', 'ld hl,OVD_STARTWALK\n                jp call_ovd             ; startWalkActor(ego, x, y, -1)', 'ld hl,OVD_STARTWALK\n                ret                     ; startWalkActor(ego, x, y, -1)'),
    # ---- fase 5b (ovc7.asm: moveCamera y camera_moved; vm_frame de vm_core.asm)
    ('moveCamera: la camara no se alinea a 8', 'ovc7.asm', 'and $F8\n                ld l,a\n                ld (CAMCUR),hl', 'and $FF\n                ld l,a\n                ld (CAMCUR),hl'),
    ('moveCamera: fuera del minimo avanza 7', 'ovc7.asm', 'mc_a:           ld de,8', 'mc_a:           ld de,7'),
    ('moveCamera: fuera del maximo no retrocede', 'ovc7.asm', 'mc_b:           ld de,-8', 'mc_b:           ld de,0'),
    ('moveCamera: tras acotar al minimo no mira el maximo', 'ovc7.asm', 'ld (CAMDEST),hl\nmc_5:', 'ld (CAMDEST),hl\n                jr mc_6\nmc_5:'),
    ('moveCamera: no acota el destino al minimo', 'ovc7.asm', 'mc_4:           ld hl,(CAMDEST)\n                ld de,(VAR_CAMERA_MIN_X)\n                call sless\n                jr nc,mc_5',
     'mc_4:           ld hl,(CAMDEST)\n                ld de,(VAR_CAMERA_MIN_X)\n                call sless\n                jr mc_5'),
    ('moveCamera: no acota el destino al maximo', 'ovc7.asm', 'mc_5:           ld hl,(VAR_CAMERA_MAX_X)\n                ld de,(CAMDEST)\n                call sless\n                jr nc,mc_6',
     'mc_5:           ld hl,(VAR_CAMERA_MAX_X)\n                ld de,(CAMDEST)\n                call sless\n                jr mc_6'),
    ('moveCamera: no sube hacia el destino', 'ovc7.asm', 'mc_7:           ld hl,(CAMCUR)\n                ld de,(CAMDEST)\n                call sless\n                jr nc,mc_7b',
     'mc_7:           ld hl,(CAMCUR)\n                ld de,(CAMDEST)\n                call sless\n                jr mc_7b'),
    ('moveCamera: no baja hacia el destino', 'ovc7.asm', 'mc_7b:          ld hl,(CAMDEST)\n                ld de,(CAMCUR)\n                call sless\n                jr nc,mc_8',
     'mc_7b:          ld hl,(CAMDEST)\n                ld de,(CAMCUR)\n                call sless\n                jr mc_8'),
    ('moveCamera: el modo seguir no marca _movingToActor', 'ovc7.asm', 'mc_mov:         ld a,1\n                ld (CAMMOV),a', 'mc_mov:         ld a,0\n                ld (CAMMOV),a'),
    ('moveCamera: llegar al actor no apaga _movingToActor', 'ovc7.asm', '                jr nz,mc_done\n                xor a\n                ld (CAMMOV),a', '                jr nz,mc_done\n                nop\n                nop'),
    ('moveCamera: el margen izquierdo es 9', 'vm_core.asm', 'CAM_LEFT        equ 10', 'CAM_LEFT        equ 9'),
    ('camera_moved: sin el limite izquierdo', 'ovc7.asm', 'call sless\n                jr nc,cmv_1\n                ld hl,160', 'call sless\n                jr cmv_1\n                ld hl,160'),
    ('camera_moved: _screenStartStrip con -19', 'ovc7.asm', 'ld de,-20\n                add hl,de\n                ld (SSTRIP),hl', 'ld de,-19\n                add hl,de\n                ld (SSTRIP),hl'),
]
sys.path.insert(0, HERE)
from mut_fase7 import M7                   # noqa: E402  (la fase 7)
M += M7

# 10e: mutaciones equivalentes (con los datos de Indy3 no pueden cambiar nada que se vea): nombre -> motivo. No se pasan salvo con MUT_EQUIV=1.
EQUIV = {
    'cadena: $FF 8 lleva bytes':
        'scan_str (resStrLen) solo cambia con $FF 8 o $FF 9 y ninguna cadena de los 1.003 scripts de Indy3 los lleva (solo $FF 1-7; 2026-11-17)',
    'fase 7 checkExecVerbs: el clic derecho no cuenta':
        'MKSTAT solo vale 0, $8000, una tecla (<= 319) o VAR_CUTSCENEEXIT_KEY, e Indy3 solo escribe 27 en esa variable: el bit 14 sin el 15 no se da (el boton derecho es ESC en v3)',
    'moveCamera: tras acotar al minimo no mira el maximo':
        'a mc_4 solo se llega con MIN <= cur <= MAX (si no, mc_a / mc_b y vuelve), asi que MIN <= MAX y tras dest = MIN nunca se cumple MAX < dest (cualquier dato)',
    'fase 7 drawVerb: un verbo guardado se dibuja':
        'vd_draw solo se llama al final de verbOps (la ranura con saveid 0 o una nueva) y al restaurar, despues de poner saveid a 0: nunca con un verbo guardado',
}


def run(cmd, cwd=HERE):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


def main():
    rooms = sys.argv[1] if len(sys.argv) > 1 else '1,15,20'
    os.makedirs(MUT, exist_ok=True)
    # 10e: los escenarios esperados se rehacen si el modelo (o las salas pedidas) son mas nuevos que ellos; antes se reusaban aunque el modelo hubiera cambiado
    exp = os.path.join(MUT, 'expected.txt')
    stamp = os.path.join(MUT, 'rooms.txt')
    model = [os.path.join(TOOLS, f) for f in ('vmmodel3.py', 'vmgame3.py', 'vmcommon3.py', 'pack_data3.py') if os.path.exists(os.path.join(TOOLS, f))]
    old_rooms = open(stamp).read().strip() if os.path.exists(stamp) else ''
    if not os.path.exists(exp) or old_rooms != rooms or any(os.path.getmtime(m) > os.path.getmtime(exp) for m in model):
        r = run([sys.executable, '-I', os.path.join(TOOLS, 'vmmodel3.py'), GAME, 'scenarios-core', MUT, '1', rooms])
        print(r.stdout.strip())
        open(stamp, 'w').write(rooms)
    src = {}
    for fn in os.listdir(ENGINE):
        if fn.endswith(('.asm', '.inc')):
            with open(os.path.join(ENGINE, fn), 'rb') as fh:
                src[fn] = fh.read().decode('utf-8').replace('\r\n', '\n')
    detected = 0
    missed = []
    equiv = []
    only = sys.argv[2].split('|') if len(sys.argv) > 2 else None        # (opcional) solo las mutaciones cuyo nombre contenga alguna de estas palabras
    run_equiv = os.environ.get('MUT_EQUIV') == '1'                     # MUT_EQUIV=1: pasa tambien las equivalentes
    todo = [('(sin mutar: tiene que dar 0)', 'vm_core.asm', '', '')]
    todo += [m for m in M if not only or any(w in m[0] for w in only)]
    for name, f, old, new in todo:
        if name in EQUIV and not run_equiv:
            print('%-45s equivalente: %s' % (name, EQUIV[name]))
            equiv.append(name)
            continue
        if old not in src[f]:
            print('%-45s PATRON NO ENCONTRADO' % name)
            missed.append(name + ' (patron)')
            continue
        for fn, txt in src.items():
            with open(os.path.join(MUT, fn), 'wb') as fh:
                fh.write((txt.replace(old, new, 1) if fn == f and old else txt).encode('utf-8'))
        r = run(['pasmo', 'vm.asm', 'vm.bin', 'vm.sym'], MUT)
        r2 = run(['pasmo', 'ovlb.asm', 'ovlb.bin', 'ovlb.sym'], MUT) if not r.returncode else r
        r3 = run(['pasmo', 'ovlc.asm', 'ovlc.bin', 'ovlc.sym'], MUT) if not r2.returncode else r2
        r4 = run(['pasmo', 'ovld.asm', 'ovld.bin', 'ovld.sym'], MUT) if not r3.returncode else r3
        if r.returncode or r2.returncode or r3.returncode or r4.returncode:
            print('%-45s NO ENSAMBLA: %s' % (name, (r.stderr + r2.stderr + r3.stderr + r4.stderr).strip().splitlines()[-1:]))
            missed.append(name + ' (no ensambla)')
            continue
        run([os.path.join(B, 'test_vm.exe'), os.path.join(MUT, 'vm.bin'), os.path.join(MUT, 'vm.sym'), os.path.join(MUT, 'ovlb.bin'),
             os.path.join(B, 'DATA.BIN'), os.path.join(MUT, 'scenarios.txt'), os.path.join(MUT, 'actual.txt'), os.path.join(MUT, 'ovlc.bin'),
             os.path.join(MUT, 'ovld.bin')])
        r = run([sys.executable, '-I', 'compare_traces.py', os.path.join(MUT, 'expected.txt'), os.path.join(MUT, 'actual.txt'), '0'])
        n = int(r.stdout.strip().split('\n')[0].split('distintos: ')[1])
        print('%-45s %5d escenarios distintos' % (name, n))
        if not old:
            if n:
                print('EL NUCLEO SIN MUTAR NO DA LO MISMO QUE EL MODELO: no vale la pena seguir')
                return 2
            continue
        if n:
            detected += 1
        else:
            missed.append(name)
    nm = len(todo) - 1 - len(equiv)
    print('\nmutaciones: %d, detectadas: %d, sin detectar: %d (equivalentes, sin pasar: %d)' % (nm, detected, nm - detected, len(equiv)))
    for m in missed:
        print('  sin detectar:', m)
    return 1 if missed else 0


if __name__ == '__main__':
    sys.exit(main())
