; =====================================================================
;  agiobj.asm - objetos animados y vistas del interprete AGI (se incluye desde agivm.asm)
;
;  Tabla de 32 objetos de 32 bytes en OBJ; IX apunta al objeto en curso. Las medidas de las celdas salen de VIEWS.HDR,
;  que vive en la pagina VIEWPAGE y se mira abriendo un momento la ventana del bloque 4.
;  Todo sigue el modelo de Python (TOOLS/agi_vm.py): movimiento, ciclos de celdas, bordes y choques con otros objetos.
;  Aun sin el plano de prioridad de la imagen (el modelo se prueba con AGI_NOPIC=1).
; =====================================================================

O_F1            equ 0                   ; bits: 0 anim, 1 drawn, 2 upd, 3 cycling, 4 mon, 5 fixpri, 6 fixloop, 7 ignora el horizonte
O_F2            equ 1                   ; bits: 0 ignora bloques, 1 ignora objetos
O_VIEW          equ 2
O_LOOP          equ 3
O_CEL           equ 4
O_X             equ 5
O_Y             equ 6
O_PRI           equ 7
O_CTYPE         equ 8                   ; 0 normal, 1 end.of.loop, 2 reverse.loop, 3 reverse
O_CTIME         equ 9
O_CCOUNT        equ 10
O_CFLAG         equ 11
O_MOTION        equ 12                  ; 0 normal, 1 wander, 2 follow.ego, 3 move.obj
O_STEP          equ 13
O_STIME         equ 14
O_SCOUNT        equ 15
O_DIR           equ 16
O_WATER         equ 17
O_TX            equ 18
O_TY            equ 19
O_MSTEP         equ 20
O_MFLAG         equ 21
O_WANDER        equ 22

; A = numero de objeto -> IX
getobj:         cp NOBJ
                jr nc,go_bad
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,OBJ
                add hl,de
                push hl
                pop ix
                ret
go_bad:         ld a,10
                call fatal
                ld ix,OBJ
                ret

; IX = objeto del argumento 0
argobj:         ld a,(ARGS)
                jr getobj

map_views:      ld b,VIEWPAGE
                ld c,MAP_PORT
                ld a,4
                out (c),a
                ret
unmap_win:      ld a,(curslot)
                cp $FF
                ret z
                jp map_slot

; Mide la celda actual del objeto IX: D = ancho, E = alto; deja en ocn los bucles de la vista y en occ las celdas del bucle.
; obj_cell ajusta bucle y celda a lo que hay (como el modelo); obj_info no toca nada.
obj_cell:       ld a,1
                jr vscan
obj_info:       xor a
vscan:          ld (vclamp),a
                xor a
                ld (ocn),a
                ld (occ),a
                call map_views
                ld l,(ix+O_VIEW)
                ld h,0
                add hl,hl
                ld de,LWIN
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                jr nz,vs_1
                ld a,9
                call fatal
                jp vs_zero
vs_1:           res 7,d                 ; bit 15 = vista congelada (agi2log.py)
                ld hl,LWIN
                add hl,de
                ld a,(hl)
                ld (ocn),a
                or a
                jp z,vs_zero
                ld b,a
                inc hl
                ld a,(ix+O_LOOP)
                cp b
                jr c,vs_2
                ld a,(vclamp)
                or a
                jp z,vs_zero
                ld a,b
                dec a
                ld (ix+O_LOOP),a
vs_2:           ld d,a
                ld c,0
                push hl
                or a
                jr z,vs_3
vs_s:           ld a,(hl)
                add a,c
                ld c,a
                inc hl
                dec d
                jr nz,vs_s
vs_3:           ld a,(hl)
                ld (occ),a
                or a
                jr z,vs_zp
                ld b,a
                ld a,(ix+O_CEL)
                cp b
                jr c,vs_4
                ld a,(vclamp)
                or a
                jr z,vs_zp
                ld a,b
                dec a
                ld (ix+O_CEL),a
vs_4:           add a,c
                add a,a
                ld e,a
                ld d,0
                pop hl
                add hl,de
                ld a,(ocn)
                ld e,a
                ld d,0
                add hl,de
                ld d,(hl)
                inc hl
                ld e,(hl)
                jp unmap_win
vs_zp:          pop hl
vs_zero:        ld de,0
                jp unmap_win

; IX: prioridad por la posicion Y, salvo que este fijada
set_pri:        bit 5,(ix+O_F1)
                ret nz
                ld a,(ix+O_Y)
                call pri_y
                ld (ix+O_PRI),a
                ret
pri_y:          cp 48                   ; A = y -> A = prioridad por la posicion
                jr nc,sp_1
                ld a,4
                ret
sp_1:           sub 48
                ld c,0
sp_l:           cp 12
                jr c,sp_d
                sub 12
                inc c
                jr sp_l
sp_d:           ld a,c
                add a,5
                cp 16
                ret c
                ld a,15
                ret

; ---------------------------------------------------------------------
;  Comandos de objetos
; ---------------------------------------------------------------------
h_animate_obj:  ld hl,OVC_ANIM          ; en el overlay C (el nucleo no tiene sitio)
                jp call_c

h_unanimate_all: ld ix,OBJ
                ld de,32
                ld b,NOBJ
ua_l:           res 0,(ix+O_F1)
                res 1,(ix+O_F1)
                add ix,de
                djnz ua_l
                ret

h_draw:         ld hl,OVC_DRAW          ; en el overlay C (el nucleo no tiene sitio)
                jp call_c

h_erase:        call argobj
                res 1,(ix+O_F1)
                ret

h_position:     call argobj
                ld a,(ARGS+1)
                ld (ix+O_X),a
                ld a,(ARGS+2)
                ld (ix+O_Y),a
                jp set_pri
h_position_v:   call argobj
                ld a,(ARGS+1)
                call getv
                ld (ix+O_X),a
                ld a,(ARGS+2)
                call getv
                ld (ix+O_Y),a
                jp set_pri
h_reposition_to: call h_position
                set 5,(ix+O_F2)
                jr h_fixpos
h_reposition_to_v: call h_position_v
                set 5,(ix+O_F2)
h_fixpos:       ld a,(ARGS)
                ld (curk),a             ; can_be_here distingue al ego por curk
                ld hl,OVC_FIXPOS        ; fixPosition de ScummVM, en el overlay C
                jp call_c
h_reposition:   call argobj
                ld a,(ARGS+1)
                call getv
                push ix
                pop hl
                ld de,O_X
                add hl,de
                call rp_add
                ld a,(ARGS+2)
                call getv
                push ix
                pop hl
                ld de,O_Y
                add hl,de
                call rp_add
                set 5,(ix+O_F2)         ; fUpdatePos: el paso de este ciclo no avanza
                jr h_fixpos
; (HL) += A (con signo); un desplazamiento negativo que pasa de 0 lo deja en 0 (cmdReposition)
rp_add:         bit 7,a
                jr z,rpa_p
                neg
                ld b,a
                ld a,(hl)
                cp b
                jr nc,rpa_s
                ld (hl),0
                ret
rpa_s:          sub b
                ld (hl),a
                ret
rpa_p:          add a,(hl)
                ld (hl),a
                ret
h_get_posn:     call argobj
                ld a,(ARGS+1)
                ld l,a
                ld h,VARS>>8
                ld a,(ix+O_X)
                ld (hl),a
                ld a,(ARGS+2)
                ld l,a
                ld a,(ix+O_Y)
                ld (hl),a
                ret

h_set_view:     call argobj
                ld a,(ARGS+1)
sv_set:         ld (ix+O_VIEW),a
                ld c,a
                ld a,(ARGS)
                or a
                jr nz,sv_nv
                ld a,c                  ; v16 = la vista del ego
                ld (VARS+16),a
sv_nv:          jp clipv             ; el bucle y la celda se conservan (obj_cell los ajusta si la vista nueva no los tiene), como en AGI: SQ1 pone set.loop y luego set.view
h_set_view_v:   call argobj
                ld a,(ARGS+1)
                call getv
                jr sv_set
h_set_loop:     call argobj
                ld a,(ARGS+1)
sl_set:         ld (ix+O_LOOP),a
                jp clipv
h_set_loop_v:   call argobj
                ld a,(ARGS+1)
                call getv
                jr sl_set
h_fix_loop:     call argobj
                set 6,(ix+O_F1)
                ret
h_release_loop: call argobj
                res 6,(ix+O_F1)
                ret
h_set_cel:      call argobj
                ld a,(ARGS+1)
sc_set:         ld (ix+O_CEL),a
                res 4,(ix+O_F2)         ; set.cel quita el fDontUpdate
                jp clipv
h_set_cel_v:    call argobj
                ld a,(ARGS+1)
                call getv
                jr sc_set
clipv:          call obj_cell           ; y clipViewCoordinates (overlay C)
                ld hl,OVC_CLIP
                jp call_c
h_last_cel:     call argobj
                call obj_cell
                ld a,(occ)
                dec a
                jr ov_put
h_current_cel:  call argobj
                ld a,(ix+O_CEL)
                jr ov_put
h_current_loop: call argobj
                ld a,(ix+O_LOOP)
                jr ov_put
h_current_view: call argobj
                ld a,(ix+O_VIEW)
                jr ov_put
h_number_of_loops: call argobj
                call obj_info
                ld a,(ocn)
ov_put:         ld b,a                  ; v[arg1] = A
                ld a,(ARGS+1)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret

h_set_priority: call argobj
                ld a,(ARGS+1)
sp_set:         ld (ix+O_PRI),a
                set 5,(ix+O_F1)
                ret
h_set_priority_v: call argobj
                ld a,(ARGS+1)
                call getv
                jr sp_set
h_release_priority: call argobj
                res 5,(ix+O_F1)
                jp set_pri
h_get_priority: call argobj
                ld a,(ix+O_PRI)
                jr ov_put

h_stop_update:  call argobj
                res 2,(ix+O_F1)
                ret
h_start_update: call argobj
                set 2,(ix+O_F1)
                ret
h_ignore_horizon: call argobj
                set 7,(ix+O_F1)
                ret
h_observe_horizon: call argobj
                res 7,(ix+O_F1)
                ret
h_set_horizon:  ld a,(ARGS)
                ld (horizon),a
                ret
h_object_on_water: call argobj
                ld (ix+O_WATER),1
                ret
h_object_on_land: call argobj
                ld (ix+O_WATER),2
                ret
h_object_on_anything: call argobj
                ld (ix+O_WATER),0
                ret
h_ignore_objs:  call argobj
                set 1,(ix+O_F2)
                ret
h_observe_objs: call argobj
                res 1,(ix+O_F2)
                ret
h_ignore_blocks: call argobj
                set 0,(ix+O_F2)
                ret
h_observe_blocks: call argobj
                res 0,(ix+O_F2)
                ret
; add.to.pic(vista, bucle, celda, x, y, prioridad, margen): como addToPic de ScummVM, la celda se pinta en la imagen (en la copia de fondo, t_bake del overlay A2) y su
; prioridad queda en los rangos (t_addhdr del A1): no ocupa un objeto, asi que no hay limite de 8. Se recuerda en el registro STL (lo que se guarda y lo que rehacen
; graphics y cargar partida) hasta draw.pic o new.room. Un margen 0, 1 o 2 pone una linea de control bajo la celda (can_be_here la mira: mg_probe).
; SCR es el objeto de trabajo (en la pagina del A1): vista, bucle, celda, x, y y prioridad en el mismo orden que los argumentos.
h_add_to_pic_v: ld hl,ARGS
                ld b,7
atv_l:          ld a,(hl)
                push hl
                push bc
                call getv
                pop bc
                pop hl
                ld (hl),a
                inc hl
                djnz atv_l
h_add_to_pic:   ld a,(st_n)
                cp ST_MAX
                ret nc
                ld hl,ARGS
                ld de,SCR+O_VIEW
                ld bc,5
                ldir
                ld a,(ARGS+5)
                or a
                jr nz,ap_q
                ld a,(ARGS+4)           ; prioridad 0: la de la y
                call pri_y
ap_q:           ld (SCR+O_PRI),a
                ld ix,SCR
                call obj_cell           ; bucle y celda ajustados a la vista; D = ancho, E = alto
                ld a,(ARGS+6)
                cp 3
                jr nc,ap_log            ; solo las lineas 0, 1 y 2
                ld a,(mg_n)
                cp MG_MAX
                jr nc,ap_log
                ld a,(ix+O_Y)           ; alto de la caja: el de la banda de prioridad de y, acotado por el de la celda
                cp 48
                jr nc,aq_b
                inc a
                jr aq_h
aq_b:           sub 48
                ld b,12
                call rem8
                inc a
aq_h:           cp e
                jr c,aq_k
                ld a,e
aq_k:           cp 64
                jr c,aq_k2
                ld a,63
aq_k2:          add a,a
                add a,a
                ld c,a                  ; C = alto << 2
                ld a,(mg_n)
                add a,a
                add a,a
                ld l,a
                ld h,0
                push bc
                ld bc,mg_tab
                add hl,bc
                pop bc
                ld a,(ix+O_X)
                ld (hl),a
                inc hl
                ld a,(ix+O_Y)
                ld (hl),a
                inc hl
                ld (hl),d
                inc hl
                ld a,(ARGS+6)
                or c
                ld (hl),a
                ld hl,mg_n
                inc (hl)
ap_log:         ld a,(st_n)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl               ; 6 * n
                ld de,STL
                add hl,de
                ex de,hl
                ld hl,SCR+O_VIEW
                ld bc,6
                ldir
                ld hl,st_n
                inc (hl)
                jp add_pic_go

; SCR con los datos de un add.to.pic -> pintado en la imagen y sus rangos de prioridad (A1: busca la pagina de la vista, A2: pinta, A1: cabecera)
add_pic_go:     ld a,7
                ld (SCR+O_F2),a         ; fijo: ignora bloques y objetos; es un rotulo para el dibujo por software
                ld a,(picvalid)
                or a
                ret z
                call OVL_ADDPIC
                ret c
                ld hl,OVE_BAKE
                call call_e
                jp OVL_ADDHDR

; draw.pic: los add.to.pic y sus margenes se van con la imagen
clr_static:     xor a
                ld (mg_n),a
                ld (st_n),a
                jp OVL_SPCLR

h_block:        ld hl,ARGS
                ld de,blk
                ld bc,4
                ldir
                ld a,1
                ld (blkf),a
                ret
h_unblock:      xor a
                ld (blkf),a
                ret

h_distance:     ld hl,OVC_DIST          ; el calculo esta en el overlay C (el nucleo no tiene sitio)
                jp call_c

; A = |A - B|
absd:           ld c,a
                sub b
                ret nc
                ld a,b
                sub c
                ret

h_stop_cycling: call argobj
                res 3,(ix+O_F1)
                ret
h_start_cycling: call argobj
                set 3,(ix+O_F1)
                ret
h_normal_cycling: call argobj
                set 3,(ix+O_F1)
                ld (ix+O_CTYPE),0
                ret
h_end_of_loop:  ld b,1
eol_set:        call argobj
                ld (ix+O_CTYPE),b
                ld a,(ARGS+1)
                ld (ix+O_CFLAG),a
                set 3,(ix+O_F1)
                set 2,(ix+O_F1)         ; cmdEndOfLoop: fDontUpdate | fUpdate | fCycling
                set 4,(ix+O_F2)
                res 6,(ix+O_F2)         ; (cyclerActivated: el ignoreLoopFlag se quita)
                ld l,a
                ld h,FLAGS>>8
                ld (hl),0
                ret
h_reverse_loop: ld b,2
                jr eol_set
h_reverse_cycle: call argobj
                ld (ix+O_CTYPE),3
                set 3,(ix+O_F1)
                ret
h_cycle_time:   call argobj
                ld a,(ARGS+1)
                call getv
                or a
                jr nz,ct_1
                inc a
ct_1:           ld (ix+O_CTIME),a
                ld (ix+O_CCOUNT),a
                ret

h_stop_motion:  call argobj
                xor a
                ld (ix+O_MOTION),a      ; como cmdStopMotion: sin movimiento y direccion 0
                ld (ix+O_DIR),a
                ld a,(ARGS)
                or a
                ret nz
                ld (VARS+6),a
                ld (pctl),a
                ret
h_start_motion: call argobj
                xor a
                ld (ix+O_MOTION),a
                ld a,(ARGS)
                or a
                ret nz
                ld (VARS+6),a
                inc a
                ld (pctl),a
                ret
h_step_size:    call argobj
                ld a,(ARGS+1)
                call getv
                ld (ix+O_STEP),a
                ret
h_step_time:    call argobj
                ld a,(ARGS+1)
                call getv
                or a
                jr nz,st_1
                inc a
st_1:           ld (ix+O_STIME),a
                ld (ix+O_SCOUNT),a
                ret

h_move_obj:     call argobj
                ld a,(ARGS+1)
                ld b,a
                ld a,(ARGS+2)
                ld c,a
                ld a,(ARGS+3)
mo_go:          push af
                call motact
                pop af
                ld (ix+O_MOTION),3
                ld (ix+O_TX),b
                ld (ix+O_TY),c
                ld d,a                  ; paso pedido
                ld a,(ix+O_STEP)
                ld (ix+O_MSTEP),a
                ld a,d
                or a
                jr z,mo_1
                ld (ix+O_STEP),a
mo_1:           ld a,(ARGS+4)
                ld (ix+O_MFLAG),a
                ld l,a
                ld h,FLAGS>>8
                ld (hl),0
                set 4,(ix+O_F1)
                ld a,(ARGS)
                ld (curk),a             ; (el update_objects lo vuelve a poner en cada objeto)
                or a
                jr nz,mo_2
                ld (pctl),a
mo_2:           jp mv_od                ; cmdMoveObj: la direccion se calcula ya
h_move_obj_v:   call argobj
                ld a,(ARGS+1)
                call getv
                ld b,a
                ld a,(ARGS+2)
                call getv
                ld c,a
                ld a,(ARGS+3)
                call getv
                jr mo_go
h_follow_ego:   call argobj
                call motact
                ld (ix+O_MOTION),2
                ld a,(ARGS+2)
                ld (ix+O_MFLAG),a
                ld l,a
                ld h,FLAGS>>8
                ld (hl),0
                ld a,(ARGS+1)           ; follow_stepSize (en MSTEP) = el mayor de los dos pasos; follow_count (en WANDER) = 255
                cp (ix+O_STEP)
                jr z,fe_s
                jr nc,fe_1
fe_s:           ld a,(ix+O_STEP)
fe_1:           ld (ix+O_MSTEP),a
                ld (ix+O_WANDER),255
                set 4,(ix+O_F1)
                ret
h_wander:       call argobj
                call motact
                ld (ix+O_MOTION),1
                set 4,(ix+O_F1)
                ld a,(ARGS)
                or a
                ret nz
                ld (pctl),a
                ret
; motionActivated: si hay un end.of.loop / reverse.loop en curso, su bandera se pierde (ignoreLoopFlag, F2 bit 6)
motact:         res 6,(ix+O_F2)
                bit 3,(ix+O_F1)
                ret z
                ld a,(ix+O_CTYPE)
                cp 1
                jr z,ma_s
                cp 2
                ret nz
ma_s:           set 6,(ix+O_F2)
                ret
h_normal_motion: call argobj
                ld (ix+O_MOTION),0
                ret
h_set_dir:      call argobj
                ld a,(ARGS+1)
                call getv
                ld (ix+O_DIR),a
                ret
h_get_dir:      call argobj
                ld a,(ix+O_DIR)
                jp ov_put

; ---------------------------------------------------------------------
;  Condiciones de posicion: el objeto (arg 0) y la caja (x1, y1, x2, y2)
; ---------------------------------------------------------------------
; IX = objeto; D = ancho, E = alto (0 si no esta dibujado)
cond_obj:       call argobj
                ld de,0
                bit 1,(ix+O_F1)
                ret z
                jp obj_cell

; HL = X minimo, DE = X maximo; la Y es la del objeto (IX). x1 <= HL, DE <= x2, y1 <= y <= y2
boxtest:        push de
                ld a,(ARGS+1)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                pop hl
                jp m,ret_false
                ld a,(ARGS+3)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                jr z,bt_y
                jp p,ret_false
bt_y:           ld a,(ARGS+2)
                ld b,a
                ld a,(ix+O_Y)
                cp b
                jp c,ret_false
                ld a,(ARGS+4)
                ld b,a
                ld a,(ix+O_Y)
                cp b
                jp z,ret_true
                jp c,ret_true
                jp ret_false

hc_posn:        call cond_obj
                ld l,(ix+O_X)
                ld h,0
                ld d,h
                ld e,l
                jr boxtest
hc_obj_in_box:  call cond_obj
                ld c,d
                ld b,0
                ld l,(ix+O_X)
                ld h,0
                push hl
                add hl,bc
                dec hl
                ex de,hl
                pop hl
                jr boxtest
hc_center_posn: call cond_obj
                ld a,d
                srl a
                ld c,a
                ld b,0
                ld l,(ix+O_X)
                ld h,0
                add hl,bc
                ld d,h
                ld e,l
                jr boxtest
hc_right_posn:  call cond_obj
                ld c,d
                ld b,0
                ld l,(ix+O_X)
                ld h,0
                add hl,bc
                dec hl
                ld d,h
                ld e,l
                jr boxtest

; ---------------------------------------------------------------------
;  Movimiento y ciclos (una vez por ciclo del interprete, tras la logica 0)
; ---------------------------------------------------------------------
DIRTAB:         defb 8,1,2, 7,0,3, 6,5,4        ; (sy+1)*3 + (sx+1) -> direccion
DXTAB:          defb 0,0,1,1,1,0,255,255,255
DYTAB:          defb 0,255,255,0,1,1,1,0,255
LOOP4:          defb 4,3,0,0,0,2,1,1,1
LOOP2:          defb 4,4,0,0,0,4,1,1,1

update_objects: ld hl,OVC_CYCLES        ; por objeto: bucle y ciclo (overlay C)
                call call_c
                ld ix,OBJ               ; y despues la posicion de todos (updatePosition)
                xor a
                ld (curk),a
                ld (uo_chg),a
uo_l:           ld a,(ix+O_F1)
                and 7
                cp 7
                jr nz,uo_next
                ld (uo_chg),a           ; hay algun objeto que actualizar
                ld a,(ix+O_SCOUNT)
                cp 2
                jr c,uo_mv
                dec (ix+O_SCOUNT)
                jr uo_next
uo_mv:          ld a,(ix+O_STIME)
                ld (ix+O_SCOUNT),a
                ld e,(ix+O_X)
                ld d,(ix+O_Y)
                push de
                call mv_pos
                pop de
                res 5,(ix+O_F2)         ; fUpdatePos gastado
                res 3,(ix+O_F2)         ; fDidntMove: el paso no lo movio
                ld a,(ix+O_X)
                cp e
                jr nz,uo_next
                ld a,(ix+O_Y)
                cp d
                jr nz,uo_next
                set 3,(ix+O_F2)
uo_next:        ld de,32
                add ix,de
                ld a,(curk)
                inc a
                ld (curk),a
                cp NOBJ
                jp c,uo_l
                ld a,(uo_chg)           ; updateScreenObjTable: el ego deja de observar agua / tierra al acabar el ciclo
                or a
                ret z
                xor a
                ld (OBJ+O_WATER),a
                ret
uo_chg:         defb 0

; A = 0, 1 o 2 segun el signo de (A - B) (menos, cero, mas)... aqui: comparacion de A con (HL)
sign3:          cp (hl)
                jr z,s3_0
                jr c,s3_n
                ld a,2
                ret
s3_0:           ld a,1
                ret
s3_n:           xor a
                ret

neg_hl:         ld a,l
                cpl
                ld l,a
                ld a,h
                cpl
                ld h,a
                inc hl
                ret

; B = indice de signo de X (0-2), C = el de Y -> (ix+O_DIR)
setdir:         ld a,c
                add a,a
                add a,c
                add a,b
                ld e,a
                ld d,0
                ld hl,DIRTAB
                add hl,de
                ld a,(hl)
                ld (ix+O_DIR),a
                ret

; updatePosition de ScummVM para el objeto IX que da su paso (curk = su numero): avanza (salvo fUpdatePos), recorta en los bordes y mira si vale el sitio
mv_pos:         ld a,(ix+O_DIR)
                bit 5,(ix+O_F2)         ; fUpdatePos: este paso no avanza
                jr z,mg_d
                xor a
mg_d:           ld (mgd),a
                ld e,a                  ; nx = x + DX*paso, ny = y + DY*paso (16 bits con signo)
                ld d,0
                ld hl,DXTAB
                add hl,de
                ld a,(hl)
                call mulstep
                ld e,(ix+O_X)
                ld d,0
                add hl,de
                ld (nx),hl
                ld a,(mgd)
                ld e,a
                ld d,0
                ld hl,DYTAB
                add hl,de
                ld a,(hl)
                call mulstep
                ld e,(ix+O_Y)
                ld d,0
                add hl,de
                ld (ny),hl
                call obj_cell           ; D = ancho, E = alto
                ld a,d
                ld (ow),a
                ld a,e
                ld (oh),a
                xor a
                ld (bdr),a
                ld hl,(nx)
                bit 7,h
                jr z,mg_x2
                ld hl,0
                ld (nx),hl
                ld a,4
                ld (bdr),a
                jr mg_y
mg_x2:          ld a,(ow)
                ld e,a
                ld d,0
                add hl,de               ; nx + w > 160 ?
                ld de,160
                or a
                sbc hl,de
                jr z,mg_y
                jr c,mg_y
                ld a,160
                ld hl,ow
                sub (hl)
                ld l,a
                ld h,0
                ld (nx),hl
                ld a,2
                ld (bdr),a
mg_y:           ld hl,(ny)              ; ny - alto < -1 ?
                inc hl
                ld a,(oh)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                jp p,mg_y2
                dec e
                ld d,0
                ld (ny),de              ; y = alto - 1
                ld a,1
                ld (bdr),a
                jr mg_p
mg_y2:          ld hl,(ny)              ; ny > 167 ?
                bit 7,h
                jr nz,mg_hz
                ld de,167
                or a
                sbc hl,de
                jr z,mg_hz
                jr c,mg_hz
                ld hl,167
                ld (ny),hl
                ld a,3
                ld (bdr),a
                jr mg_p
mg_hz:          bit 7,(ix+O_F1)         ; no ignora el horizonte y ny <= horizonte
                jr nz,mg_p
                ld hl,(ny)
                bit 7,h
                jr nz,mg_h1
                ld a,(horizon)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                jr z,mg_h1
                jr c,mg_h1
                jr mg_p
mg_h1:          ld a,(horizon)
                inc a
                ld l,a
                ld h,0
                ld (ny),hl
                ld a,1
                ld (bdr),a
mg_p:           call can_be_here
                or a
                jr z,mg_no
                ld a,(nx)
                ld (ix+O_X),a
                ld a,(ny)
                ld (ix+O_Y),a
                call set_pri
                jr mg_b
mg_no:          xor a
                ld (bdr),a              ; paso rechazado: el borde se descarta
                ld hl,OVC_FIXPOS
                call call_c             ; y se arregla el sitio por si el actual ya no vale (fixPosition)
mg_b:           ld a,(bdr)
                or a
                ret z
                ld b,a
                ld a,(curk)
                or a
                jr nz,mg_o
                ld a,b
                ld (VARS+2),a
                jp mg_st
mg_o:           ld a,(curk)
                ld (VARS+4),a
                ld a,b
                ld (VARS+5),a
                jp mg_st

; A = -1, 0 o 1 (en DX/DYTAB) -> HL = A * paso del objeto, con signo
mulstep:        ld l,(ix+O_STEP)
                ld h,0
                or a
                jr z,ms_z
                cp 1
                ret z
                jp neg_hl
ms_z:           ld hl,0
                ret

; motionMoveObj de ScummVM: direccion hacia (tx, ty) con checkStep en cada eje (no aterriza exacto); con 0 acaba el move.obj
mv_od:          ld a,(ix+O_TX)
                sub (ix+O_X)
                call mo_cs
                ld b,a
                ld a,(ix+O_TY)
                sub (ix+O_Y)
                call mo_cs
                ld c,a
                call setdir
                ld a,(curk)
                or a
                ld a,(ix+O_DIR)
                jr nz,mo_nv
                ld (VARS+6),a
mo_nv:          or a
                ret nz
                jr mv_stop

; A = diferencia (8 bits sin signo con acarreo = negativa) -> A = checkStep(delta, paso): 0 si delta <= -paso, 2 si delta >= paso, 1 en otro caso
mo_cs:          ld e,(ix+O_STEP)
mo_cs2:         ld l,a                  ; (E = paso)
                ld h,0
                jr nc,cs_p
                dec h
cs_p:           ld d,0
                push hl
                add hl,de
                bit 7,h
                jr nz,cs_0
                ld a,h
                or l
                jr z,cs_0
                pop hl
                or a
                sbc hl,de
                ld a,1
                ret m
                inc a
                ret
cs_0:           pop hl
                xor a
                ret

; Acaba el move.obj del objeto IX (motionMoveObjStop): recupera el paso, pone la bandera y el ego recupera el control del jugador
mg_st:          ld a,(ix+O_MOTION)
                cp 3
                ret nz
mv_stop:        ld a,(ix+O_MSTEP)
                ld (ix+O_STEP),a
                ld a,(ix+O_MFLAG)
                ld l,a
                ld h,FLAGS>>8
                ld (hl),1
                xor a
                ld (ix+O_MOTION),a
                ld a,(curk)
                or a
                ret nz
                ld (VARS+6),a
                inc a                   ; SQ1 no llama a player.control despues del move.obj
                ld (pctl),a
                ret

; bucle de la celda segun la direccion (vistas de 2 o mas bucles)
pick_loop:      bit 6,(ix+O_F1)
                ret nz
                ld a,(ix+O_DIR)
                or a
                ret z
                ld (pk_d),a
                call obj_info
                ld a,(ocn)
                cp 2
                ret c
                ld c,a
                ld a,(pk_d)
                ld e,a
                ld d,0
                ld hl,LOOP4
                ld a,c
                cp 4
                jr nc,pk_t
                ld hl,LOOP2
pk_t:           add hl,de
                ld a,(hl)
                cp 4
                ret z
                cp c
                ret nc
                ld (ix+O_LOOP),a
                ret

; siguiente celda segun el tipo de ciclo
; A = 1 si el punto (D, E) cae dentro de la zona de block, con los limites excluidos (checkBlock de ScummVM): x1 < x < x2 y y1 < y < y2 (blk = x1, y1, x2, y2)
bk_in:          ld hl,blk
                ld a,(hl)
                cp d
                jr nc,bk_no
                inc hl
                ld a,(hl)
                cp e
                jr nc,bk_no
                inc hl
                ld a,d
                cp (hl)
                jr nc,bk_no
                inc hl
                ld a,e
                cp (hl)
                jr nc,bk_no
                ld a,1
                ret
bk_no:          xor a
                ret

; Puede el objeto IX estar en (nx, ny)? -> A = 1 si
can_be_here:    call obj_cell
                ld a,d
                ld (ow),a
                ; y - h < -1  ->  se deja pasar (los bordes se tratan aparte)
                ld hl,(ny)
                ld d,0                  ; E = alto
                or a
                sbc hl,de
                inc hl
                bit 7,h
                jp nz,ret_true
                bit 7,(ix+O_F1)         ; horizonte
                jr nz,cb_blk
                ld hl,(ny)
                bit 7,h
                jp nz,ret_false
                ld a,(horizon)
                ld e,a
                ld d,0
                or a
                sbc hl,de               ; ny <= horizonte -> no
                jp z,ret_false
                jp c,ret_false
cb_blk:
cb_obj:         bit 1,(ix+O_F2)         ; ignora a los demas objetos
                jp nz,cb_pic
                push ix
                ld iy,OBJ
                ld b,NOBJ
cb_l:           push bc
                push iy
                pop hl
                push ix
                pop de
                or a
                sbc hl,de
                jr z,cb_skip            ; el mismo objeto
                ld a,(iy+O_F1)
                and 3
                cp 3
                jr nz,cb_skip           ; no animado y dibujado
                bit 1,(iy+O_F2)
                jr nz,cb_skip
                push ix
                push iy
                pop ix
                call obj_cell           ; D = ancho, E = alto de q
                pop ix
                ld a,d
                ld (qw),a
                ; x < qx + qw  y  qx < x + w
                ld e,(iy+O_X)
                ld d,0
                ld a,(qw)
                ld l,a
                ld h,0
                add hl,de
                ex de,hl                ; DE = qx + qw + 1 (solape inclusivo)
                inc de
                ld hl,(nx)
                or a
                sbc hl,de
                jr nc,cb_skip           ; nx >= qx+qw
                ld a,(ow)
                ld e,a
                ld d,0
                ld hl,(nx)
                add hl,de               ; nx + w
                ld e,(iy+O_X)
                ld d,0
                or a
                sbc hl,de               ; (nx + w) - qx >= 0  <=>  qx <= nx + w
                jp m,cb_skip
                ; y == qy  o  oy < qy <= ny  o  ny < qy <= oy
                ld hl,(ny)
                ld e,(iy+O_Y)
                ld d,0
                or a
                sbc hl,de
                jr z,cb_hit             ; ny == qy
                ld a,(ix+O_Y)           ; oy < qy ?
                cp (iy+O_Y)
                jr nc,cb_b
                ld hl,(ny)              ; qy <= ny ?  (ny - qy >= 0)
                or a
                sbc hl,de
                jp p,cb_hit
cb_b:           ld hl,(ny)              ; ny < qy <= oy
                or a
                sbc hl,de               ; ny - qy < 0
                jp p,cb_skip
                ld a,(iy+O_Y)
                cp (ix+O_Y)
                jr z,cb_hit
                jr c,cb_hit
cb_skip:        pop bc
                ld de,32
                add iy,de
                dec b
                jp nz,cb_l
                pop ix
cb_pic:         call pic_check          ; la imagen se mira despues de los objetos (checkCollision antes que checkPriority)
                or a
                jp z,ret_false
                jp ret_true
cb_hit:         pop bc
                pop ix
                jp ret_false
