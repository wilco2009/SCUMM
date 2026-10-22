; walk.asm - movimiento de los actores (se incluye desde game.asm, despues de geom.asm)
;
; Version en Z80 de las funciones de SCUMM/TOOLS/vmgame.py: remapDirection, updateActorDirection,
; actorWalkStep, calcMovementFactor, startWalkActor, walkActor, walkActors y las instrucciones
; walkActorTo / ToObject / ToActor, putActorAtObject, faceActor, waitForActor y los consultores.
; Registro del actor (48 bytes), ademas de los 16 primeros de game.asm:
;   +16 caja en la que esta, +17 elevacion, +18/19 destino x, +20/21 destino y, +22 caja de destino,
;   +23/24 direccion al llegar (-1 = ninguna), +25 caja en curso, +26/27 y +28/29 siguiente punto,
;   +30/31 xfrac, +32/33 yfrac, +34/35 xadd, +36/37 yadd, +38/39 dxf, +40/41 dyf, +42/43 umbral,
;   +44 direccion de la caminata (0..3)

WK_X            equ GSCR+136
WK_Y            equ GSCR+138
WK_DIR          equ GSCR+140
WK_NX           equ GSCR+142
WK_NY           equ GSCR+144
WK_DX           equ GSCR+146
WK_DY           equ GSCR+148
WK_ADX          equ GSCR+150
WK_ADY          equ GSCR+152
WK_N            equ GSCR+154
WK_OP           equ GSCR+155            ; palabra: registro del objeto encontrado
WK_FX           equ GSCR+157
WK_FY           equ GSCR+159
WK_TX           equ GSCR+161
WK_TY           equ GSCR+163
WK_OBJ          equ GSCR+165
WK_OX           equ GSCR+167
WK_OY           equ GSCR+169

MF_NEW_LEG      equ 1
MF_IN_LEG       equ 2
MF_TURN         equ 4
MF_LAST_LEG     equ 8


; ============================================================================================ direcciones
n2o:                                    ; HL = angulo -> A = direccion antigua (0 izq, 1 der, 2 abajo, 3 arriba)
                ld b,h
                ld c,l
                ld de,71
                or a
                sbc hl,de
                jr c,n2o_3
                ld h,b
                ld l,c
                ld de,110
                or a
                sbc hl,de
                jr c,n2o_1              ; 71..109
                ld h,b
                ld l,c
                ld de,252
                or a
                sbc hl,de
                jr c,n2o_2              ; 110..251
                ld h,b
                ld l,c
                ld de,290
                or a
                sbc hl,de
                jr c,n2o_0              ; 252..289
n2o_3:
                ld a,3
                ret
n2o_1:
                ld a,1
                ret
n2o_2:
                ld a,2
                ret
n2o_0:
                xor a
                ret

od_k:                                   ; A = 0..3 -> HL = oldDirToNewDir
                ld l,a
                ld h,0
                add hl,hl
                ld de,old_dir_table
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ret

remap_direction:                        ; IX = actor, HL = direccion -> _targetFacing del actor
                call n2o
                ld (WK_N),a
                ld a,(ix+16)
                call box_flags
                ld c,a
                ld a,(ERR)
                or a
                ret nz
                ld a,c
                and 7
                ld c,a
                ld a,(ix+8)
                and $FB
                jr z,rm_still
                ld a,(ix+44)
                add a,a
                add a,a
                add a,a
                add a,c
                ld e,a
                ld d,0
                ld hl,REMAP1
                add hl,de
                ld c,(hl)
                ld a,(WK_N)
                add a,a
                add a,a
                add a,a
                add a,c
                ld e,a
                ld d,0
                ld hl,REMAP2
                add hl,de
                ld a,(hl)
                jr rm_set
rm_still:
                ld a,(WK_N)
                add a,a
                add a,a
                add a,a
                add a,c
                ld e,a
                ld d,0
                ld hl,REMAP3
                add hl,de
                ld a,(hl)
rm_set:
                call od_k
                ld (ix+12),l
                ld (ix+13),h
                ret

update_actor_direction:                 ; IX = actor -> HL = nueva direccion
                ld l,(ix+12)
                ld h,(ix+13)
                call remap_direction
                ld a,(ERR)
                or a
                ret nz
                ld l,(ix+12)
                ld h,(ix+13)
                call n2o
                ld (WK_N),a
                ld l,(ix+6)
                ld h,(ix+7)
                call n2o
                add a,a
                add a,a
                ld b,a
                ld a,(WK_N)
                or b
                ld e,a
                ld d,0
                ld hl,TURN_TABLE
                add hl,de
                ld a,(hl)
                jp od_k

turn_to_dir:                            ; IX = actor, HL = direccion (-1: ninguna)
                ld a,h
                and l
                inc a
                ret z
                ld (ix+12),l
                ld (ix+13),h
                set 2,(ix+8)
                ret

; ============================================================================================ caminar
actor_walk_step:                        ; IX = actor
                ld l,(ix+30)
                ld h,(ix+31)
                ld e,(ix+34)
                ld d,(ix+35)
                add hl,de
                ld e,(ix+42)
                ld d,(ix+43)
                or a
                sbc hl,de
                jr c,aw_xlow
                ld a,(ix+1)             ; xfrac >= umbral: un paso en x si todavia no ha llegado
                cp (ix+26)
                jr nz,aw_xmove
                ld a,(ix+2)
                cp (ix+27)
                jr z,aw_xstore
aw_xmove:
                push hl
                ld l,(ix+1)
                ld h,(ix+2)
                ld e,(ix+38)
                ld d,(ix+39)
                add hl,de
                ld (ix+1),l
                ld (ix+2),h
                pop hl
aw_xstore:
                ld (ix+30),l
                ld (ix+31),h
                jr aw_y
aw_xlow:
                add hl,de               ; devuelve la suma sin restar
                ld (ix+30),l
                ld (ix+31),h
aw_y:
                ld l,(ix+32)
                ld h,(ix+33)
                ld e,(ix+36)
                ld d,(ix+37)
                add hl,de
                ld e,(ix+42)
                ld d,(ix+43)
                or a
                sbc hl,de
                jr c,aw_ylow
                ld a,(ix+3)
                cp (ix+28)
                jr nz,aw_ymove
                ld a,(ix+4)
                cp (ix+29)
                jr z,aw_ystore
aw_ymove:
                push hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld e,(ix+40)
                ld d,(ix+41)
                add hl,de
                ld (ix+3),l
                ld (ix+4),h
                pop hl
aw_ystore:
                ld (ix+32),l
                ld (ix+33),h
                jr aw_end
aw_ylow:
                add hl,de
                ld (ix+32),l
                ld (ix+33),h
aw_end:
                ld a,(ix+1)
                cp (ix+26)
                ret nz
                ld a,(ix+2)
                cp (ix+27)
                ret nz
                ld a,(ix+3)
                cp (ix+28)
                ret nz
                ld a,(ix+4)
                cp (ix+29)
                ret nz
                set 1,(ix+8)
                ret

calc_movement_factor:                   ; IX = actor, WK_NX / WK_NY = siguiente punto
                ld hl,(WK_NX)
                ld e,(ix+1)
                ld d,(ix+2)
                or a
                sbc hl,de
                ld (WK_DX),hl
                ld hl,(WK_NY)
                ld e,(ix+3)
                ld d,(ix+4)
                or a
                sbc hl,de
                ld (WK_DY),hl
                ld hl,(WK_DX)
                ld a,h
                or l
                jr nz,cm_go
                ld hl,(WK_DY)
                ld a,h
                or l
                jr nz,cm_go
                set 1,(ix+8)
                ret
cm_go:
                ld hl,(WK_DX)
                call abs_hl
                ld (WK_ADX),hl
                ld (ix+30),l
                ld (ix+31),h
                ld (ix+34),l
                ld (ix+35),h
                ld hl,(WK_DY)
                call abs_hl
                ld (WK_ADY),hl
                ld (ix+32),l
                ld (ix+33),h
                ld (ix+36),l
                ld (ix+37),h
                ld de,(WK_ADX)
                or a
                sbc hl,de               ; |dy| - |dx|
                ld hl,(WK_ADY)
                jr nc,cm_th
                ld hl,(WK_ADX)
cm_th:
                ld (ix+42),l
                ld (ix+43),h
                ld hl,1                 ; dxf
                ld a,(WK_DX+1)
                rla
                jr nc,cm_dx
                ld hl,$FFFF
cm_dx:
                ld (ix+38),l
                ld (ix+39),h
                ld hl,1                 ; dyf
                ld a,(WK_DY+1)
                rla
                jr nc,cm_dy
                ld hl,$FFFF
cm_dy:
                ld (ix+40),l
                ld (ix+41),h
                ld hl,(WK_NX)
                ld (ix+26),l
                ld (ix+27),h
                ld hl,(WK_NY)
                ld (ix+28),l
                ld (ix+29),h
                ; direccion de la caminata y del giro: B = dy >= 0, C = dx >= 0
                ld a,(WK_DY+1)
                rla
                ccf
                sbc a,a
                and 1
                ld b,a
                ld a,(WK_DX+1)
                rla
                ccf
                sbc a,a
                and 1
                ld c,a
                ld a,c                  ; wfacing = dx >= 0 ? (dy >= 0) : 3 - (dy >= 0)
                or a
                ld a,b
                jr nz,cm_ws
                ld a,3
                sub b
cm_ws:
                ld (ix+44),a
                ld hl,(WK_ADX)          ; |dy| > |dx| ?
                ld de,(WK_ADY)
                or a
                sbc hl,de               ; |dx| - |dy|
                jr nc,cm_horiz          ; |dx| >= |dy|
                ld a,3                  ; k = 3 - (dy >= 0)
                sub b
                jr cm_k
cm_horiz:
                ld a,c                  ; k = dx >= 0
cm_k:
                call od_k
                ld (ix+12),l
                ld (ix+13),h
                res 1,(ix+8)
                ld e,(ix+6)
                ld d,(ix+7)
                or a
                sbc hl,de
                jr z,cm_same
                set 2,(ix+8)
cm_same:
                ld a,(ix+10)            ; fotograma de caminar si no lo es ya o si cambia la direccion
                or a
                jr nz,cm_anim
                ld a,(ix+6)
                cp (ix+12)
                jr nz,cm_anim
                ld a,(ix+7)
                cp (ix+13)
                jr z,cm_step
cm_anim:
                xor a                   ; WALK_FRAME
                call start_anim
cm_step:
                bit 2,(ix+8)
                ret nz
                jp actor_walk_step

; startWalkActor: IX = actor, WK_X / WK_Y = destino, WK_DIR = direccion final (-1: ninguna)
start_walk_actor:
                ld a,(CURROOM)
                cp (ix+0)
                jr z,sw_in
                ld hl,(WK_X)
                ld (ix+1),l
                ld (ix+2),h
                ld hl,(WK_Y)
                ld (ix+3),l
                ld (ix+4),h
                ld hl,(WK_DIR)
                ld a,h
                and l
                inc a
                ret z
                ld (ix+6),l
                ld (ix+7),h
                ret
sw_in:
                ld hl,(WK_X)
                ld (AX_X),hl
                ld hl,(WK_Y)
                ld (AX_Y),hl
                call adjust_xy
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld e,(ix+1)
                ld d,(ix+2)
                or a
                sbc hl,de
                jr nz,sw_go
                ld hl,(AX_RY)
                ld e,(ix+3)
                ld d,(ix+4)
                or a
                sbc hl,de
                jr nz,sw_go
                ld hl,(WK_DIR)
                ld a,h
                and l
                inc a
                ret z                   ; ya esta alli y no hay direccion que tomar
                ld e,(ix+6)
                ld d,(ix+7)
                or a
                sbc hl,de
                ret z                   ; ya esta alli y mirando hacia donde debe
sw_go:
                ld hl,(AX_RX)
                ld (ix+18),l
                ld (ix+19),h
                ld hl,(AX_RY)
                ld (ix+20),l
                ld (ix+21),h
                ld a,(AX_BOX)
                ld (ix+22),a
                ld hl,(WK_DIR)
                ld (ix+23),l
                ld (ix+24),h
                ld a,(ix+16)
                ld (ix+25),a
                ld a,(ix+8)
                and $F7
                or MF_IN_LEG+MF_NEW_LEG
                ld (ix+8),a
                ret

; ---- next_box: B = desde, C = hasta -> HL con signo (-1: no hay camino)
next_box:
                ld a,b
                cp c
                jr nz,nb_1
                ld l,c
                ld h,0
                ret
nb_1:
                ld a,c
                cp $FF
                jr nz,nb_2
                ld hl,$FFFF
                ret
nb_2:
                ld a,b
                cp $FF
                jr nz,nb_3
                ld l,c
                ld h,0
                ret
nb_3:
                ld a,(NBOXES)
                ld d,a
                ld a,b
                cp d
                jr nc,nb_err
                ld a,c
                cp d
                jr nc,nb_err
                ld hl,(MATRIXP)
                ld a,(hl)
                cp $FF
                jr nz,nb_b0
                inc hl
nb_b0:
                push hl
                ld e,b
                ld d,0
                add hl,de
                ld e,(hl)
                ld d,0
                pop hl
                add hl,de
                ld a,(NBOXES)
                ld e,a
                ld d,0
                add hl,de
                ld e,c
                ld d,0
                add hl,de
                ld a,(hl)
                ld l,a
                rla
                sbc a,a
                ld h,a
                ret
nb_err:
                ld a,E_RANGE
                ld (ERR),a
                ld hl,$FFFF
                ret

box_rec_s:                              ; como box_rec, pero una caja que no existe es un error
                call box_rec
                ret nc
                ld a,E_RANGE
                ld (ERR),a
                scf
                ret

; closestPtOnBox: HL = registro de la caja, PB_X / PB_Y -> PB_OX / PB_OY
closest_box:
                push hl
                ld de,PB_BOX
                ld a,(hl)               ; uy
                ld c,a
                inc hl
                ld a,(hl)               ; ly
                ld b,a
                inc hl
                ; ul
                ld a,(hl)
                call cb_x
                ld a,c
                call cb_y
                inc hl
                ld a,(hl)               ; ur
                call cb_x
                ld a,c
                call cb_y
                inc hl
                ld a,(hl)               ; ll
                call cb_x
                ld a,b
                call cb_y
                inc hl
                ld a,(hl)               ; lr
                call cb_x
                ld a,b
                call cb_y
                pop hl
                ld hl,0
                ld (PB_OX),hl
                ld (PB_OY),hl
                ld hl,$FFFF
                ld (PB_BEST),hl
                ld a,$FF
                ld (PB_BEST+2),a
                xor a
                ld (PB_BEST+3),a
                ld hl,(PB_X)
                ld (LN_PX),hl
                ld hl,(PB_Y)
                ld (LN_PY),hl
                xor a
                ld (PB_K),a
cb_loop:
                ld a,(PB_K)
                ld e,a
                ld d,0
                ld hl,PB_S
                add hl,de
                ld a,(hl)
                ld e,a
                ld d,0
                ld hl,PB_BOX
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (LN_SX),de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (LN_SY),de
                ld a,(PB_K)
                ld e,a
                ld d,0
                ld hl,PB_E
                add hl,de
                ld a,(hl)
                ld e,a
                ld d,0
                ld hl,PB_BOX
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (LN_EX),de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (LN_EY),de
                call closest_line
                ld hl,(PB_X)            ; d = (x - rx)^2 + (y - ry)^2
                ld de,(LN_RX)
                or a
                sbc hl,de
                ld d,h
                ld e,l
                call sx32_n1
                ld h,d
                ld l,e
                call sx32_n2
                call mul32
                ld hl,(NR)
                ld (PB_D),hl
                ld hl,(NR+2)
                ld (PB_D+2),hl
                ld hl,(PB_Y)
                ld de,(LN_RY)
                or a
                sbc hl,de
                ld d,h
                ld e,l
                call sx32_n1
                ld h,d
                ld l,e
                call sx32_n2
                call mul32
                ld hl,(PB_D)
                ld de,(NR)
                add hl,de
                ld (PB_D),hl
                ld hl,(PB_D+2)
                ld de,(NR+2)
                adc hl,de
                ld (PB_D+2),hl
                ld hl,(PB_D)            ; d < mejor ?
                ld de,(PB_BEST)
                or a
                sbc hl,de
                ld hl,(PB_D+2)
                ld de,(PB_BEST+2)
                sbc hl,de
                jr nc,cb_next
                ld hl,(PB_D)
                ld (PB_BEST),hl
                ld hl,(PB_D+2)
                ld (PB_BEST+2),hl
                ld hl,(LN_RX)
                ld (PB_OX),hl
                ld hl,(LN_RY)
                ld (PB_OY),hl
cb_next:
                ld a,(PB_K)
                inc a
                ld (PB_K),a
                cp 4
                jp nz,cb_loop
                ret
cb_x:                                   ; A -> palabra (DE)
                ld (de),a
                inc de
                xor a
                ld (de),a
                inc de
                ret
cb_y:
                jr cb_x
PB_S:           defb 0,4,12,8
PB_E:           defb 4,12,8,0
PB_D            equ GSCR+171

; dos pasadas de closestPtOnBox: HL = caja, (PB_X, PB_Y) -> (PB_OX, PB_OY)
closest_of_box:                         ; A = caja
                call box_rec_s
                ret c
                jp closest_box

; ============================================================================================ walkActor
walk_actor:                             ; IX = actor
                bit 2,(ix+8)
                jr z,wa_notturn
                call update_actor_direction
                ld a,(ERR)
                or a
                ret nz
                ld e,(ix+12)
                ld d,(ix+13)
                ld (ix+6),l
                ld (ix+7),h
                or a
                sbc hl,de
                ret nz
                res 2,(ix+8)
                ret
wa_notturn:
                bit 0,(ix+8)
                ret z
                bit 1,(ix+8)
                jr nz,wa_inleg
                jp actor_walk_step
wa_inleg:
                bit 3,(ix+8)
                jr z,wa_notlast
                ld (ix+8),MF_TURN
                ld a,STAND
                call start_anim
                ld l,(ix+23)
                ld h,(ix+24)
                jp turn_to_dir
wa_notlast:
                ld a,(ix+25)
                ld (ix+16),a            ; caja en la que esta = caja en curso
                cp (ix+22)
                jr nz,wa_next
                ld l,(ix+18)
                ld h,(ix+19)
                ld (WK_FX),hl
                ld l,(ix+20)
                ld h,(ix+21)
                ld (WK_FY),hl
                set 3,(ix+8)
                jp wa_calc
wa_next:
                ld b,a
                ld c,(ix+22)
                call next_box
                ld a,(ERR)
                or a
                ret nz
                bit 7,h
                jr z,wa_nb
                set 3,(ix+8)            ; no hay camino
                ret
wa_nb:
                ld a,l
                ld (WK_N),a
                call box_flags
                ld c,a
                ld a,(ERR)
                or a
                ret nz
                bit 6,c                 ; cerrada con llave?
                jr z,wa_unlocked
                bit 5,c                 ; y solo para el jugador: se bloquea solo si lo es
                jr z,wa_lock
                push bc
                call is_player
                pop bc
                jr nc,wa_unlocked
wa_lock:
                set 3,(ix+8)
                ld hl,$FFFF
                ld (ix+23),l
                ld (ix+24),h
wa_unlocked:
                ld a,(WK_N)
                ld (ix+25),a
                ld l,(ix+1)             ; punto de la caja siguiente mas cercano a la posicion
                ld h,(ix+2)
                ld (PB_X),hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld (PB_Y),hl
                ld a,(ix+25)
                call closest_of_box
                ld a,(ERR)
                or a
                ret nz
                ld hl,(PB_OX)
                ld (PB_X),hl
                ld hl,(PB_OY)
                ld (PB_Y),hl
                ld a,(ix+16)
                call closest_of_box
                ld a,(ERR)
                or a
                ret nz
                ld hl,(PB_OX)
                ld (WK_FX),hl
                ld hl,(PB_OY)
                ld (WK_FY),hl
wa_calc:
                ld hl,(WK_FX)
                ld (WK_NX),hl
                ld hl,(WK_FY)
                ld (WK_NY),hl
                jp calc_movement_factor

walk_actors:
                ld ix,ACTORS+48
                ld b,NACTORS-1
wk_loop:
                push bc
                ld a,(CURROOM)
                cp (ix+0)
                call z,walk_actor
                pop bc
                ld a,(ERR)
                or a
                ret nz
                ld de,48
                add ix,de
                djnz wk_loop
                ret

; ============================================================================================ objetos
; whereIsObject: HL = objeto -> A = 0 no esta, 1 en la sala (WK_OP = su registro), 2 en un inventario
where_is_object:
                ld a,h
                or l
                jr z,wo_none
                ld de,NOBJ
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,wo_none
                push hl
                ld de,OBJOWN
                add hl,de
                ld a,(hl)
                pop hl
                cp $0F
                jr z,wo_room
                or a
                jr z,wo_none
                ld a,2
                ret
wo_room:
                ld a,(NOBJS)
                or a
                jr z,wo_none
                ld b,a
                ld ix,(OBJSP)
wo_loop:
                ld a,(ix+0)
                cp l
                jr nz,wo_next
                ld a,(ix+1)
                cp h
                jr nz,wo_next
                ld (WK_OP),ix
                ld a,1
                ret
wo_next:
                ld de,OBJREC
                add ix,de
                djnz wo_loop
wo_none:
                xor a
                ret

; getObjectXYPos de v2: HL = objeto en la sala -> WK_OX, WK_OY y A = direccion (0..3); error si no esta
object_xy_pos:
                call where_is_object
                cp 1
                jr z,ox_ok
                ld a,E_BADOBJ
                ld (ERR),a
                ret
ox_ok:
                ld ix,(WK_OP)
                ld l,(ix+2)
                ld h,0
                ld (WK_OX),hl
                ld l,(ix+3)
                ld (WK_OY),hl
                ld a,(ix+4)
                and 3
                ret

; getObjectOrActorXY: HL = objeto o actor -> carry si no hay posicion; si no, WK_OX, WK_OY
object_or_actor_xy:
                ld a,h
                or a
                jr nz,oa_obj
                ld a,l
                cp NACTORS
                jr nc,oa_obj
                call actor_addr
                jr oa_pos
oa_obj:
                push hl
                call where_is_object
                pop hl
                or a
                jr z,oa_none
                cp 2
                jr z,oa_inv
                call object_xy_pos
                or a
                ret
oa_inv:
                ld de,OBJOWN
                add hl,de
                ld a,(hl)
                cp NACTORS
                jr nc,oa_none
                call actor_addr
oa_pos:
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,oa_none
                ld l,(ix+1)
                ld h,(ix+2)
                ld (WK_OX),hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld (WK_OY),hl
                or a
                ret
oa_none:
                scf
                ret

; ============================================================================================ posicion
adjust_actor_pos:                       ; IX = actor
                ld l,(ix+1)
                ld h,(ix+2)
                ld (AX_X),hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld (AX_Y),hl
                call adjust_xy
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld (ix+1),l
                ld (ix+2),h
                ld hl,(AX_RY)
                ld (ix+3),l
                ld (ix+4),h
                ld a,(AX_BOX)
                ld (ix+22),a
                ld (ix+16),a
                ld hl,$FFFF
                ld (ix+18),l
                ld (ix+19),h
                ld (ix+8),0
                ld a,(ix+16)
                cp $FF
                ret z
                call box_flags
                and 7
                ret z
                ld l,(ix+6)
                ld h,(ix+7)
                jp turn_to_dir

; ============================================================================================ instrucciones
h_o2_walkActorTo:                       ; ARGS: actor, x, y
                ld de,(ARGS)
                call deref_actor
                ret c
                ld hl,(ARGS+2)
                ld (WK_X),hl
                ld hl,(ARGS+4)
                ld (WK_Y),hl
                ld hl,$FFFF
                ld (WK_DIR),hl
                jp start_walk_actor

h_o2_walkActorToObject:                 ; ARGS: actor, objeto
                ld hl,(ARGS+2)
                call where_is_object
                or a
                ret z
                ld hl,(ARGS+2)
                call object_xy_pos
                push af
                ld a,(ERR)
                or a
                jr z,wt_ok
                pop af
                ret
wt_ok:
                pop af
                call od_k
                ld (WK_DIR),hl
                ld de,(ARGS)
                call deref_actor
                ret c
                ld hl,(WK_OX)
                ld (AX_X),hl
                ld hl,(WK_OY)
                ld (AX_Y),hl
                call adjust_xy
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld (WK_X),hl
                ld hl,(AX_RY)
                ld (WK_Y),hl
                jp start_walk_actor

h_o5_walkActorToActor:                  ; ARGS: actor, actor de destino, distancia
                ld de,(ARGS)
                ld a,d
                or a
                ret nz
                ld a,e
                cp NACTORS
                ret nc
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                push ix
                pop iy                  ; IY = el que camina
                ld de,(ARGS+2)
                ld a,d
                or a
                ret nz
                ld a,e
                cp NACTORS
                ret nc
                call actor_addr         ; IX = el destino
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                ld l,(ix+1)
                ld h,(ix+2)
                ld e,(iy+1)
                ld d,(iy+2)
                call sless              ; destino a la izquierda del que camina?
                ld a,(ARGS+4)
                ld e,a
                ld d,0
                jr nc,wa2_minus
                add hl,de
                jr wa2_x
wa2_minus:
                or a
                sbc hl,de
wa2_x:
                ld (AX_X),hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld (AX_Y),hl
                push iy
                pop ix
                call adjust_xy
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld (WK_X),hl
                ld hl,(AX_RY)
                ld (WK_Y),hl
                ld hl,$FFFF
                ld (WK_DIR),hl
                jp start_walk_actor

h_o2_putActorAtObject:                  ; ARGS: actor, objeto
                ld de,(ARGS)
                call deref_actor
                ret c
                ld hl,(ARGS+2)
                push ix
                call where_is_object
                pop ix
                or a
                jr z,pao_def
                push ix
                ld hl,(ARGS+2)
                call object_xy_pos
                pop ix
                ld a,(ERR)
                or a
                ret nz
                ld hl,(WK_OX)
                ld (AX_X),hl
                ld hl,(WK_OY)
                ld (AX_Y),hl
                call adjust_xy
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld (PA_X),hl
                ld hl,(AX_RY)
                ld (PA_Y),hl
                jr pao_put
pao_def:
                ld hl,30
                ld (PA_X),hl
                ld hl,60
                ld (PA_Y),hl
pao_put:
                ld a,(ix+0)
                ld (PA_ROOM),a
                jp put_actor

h_o5_faceActor:                         ; ARGS: actor, objeto
                ld de,(ARGS)
                ld a,d
                or a
                ret nz
                ld a,e
                cp NACTORS
                ret nc
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                ld hl,(ARGS+2)
                push ix
                call object_or_actor_xy
                pop ix
                ret c
                ld a,(ERR)
                or a
                ret nz
                ld l,(ix+1)             ; d = 1 si a.x < x2, si no 0
                ld h,(ix+2)
                ld de,(WK_OX)
                call sless
                ld b,0
                jr nc,fa_1
                inc b
fa_1:
                or a
                sbc hl,de               ; |a.x - x2| < 2 ?
                call abs_hl
                ld de,2
                or a
                sbc hl,de
                jr nc,fa_turn
                ld l,(ix+3)             ; d = 3 si a.y > y2, si no 2
                ld h,(ix+4)
                ld de,(WK_OY)
                ex de,hl
                call sless              ; y2 < a.y ?
                ld b,2
                jr nc,fa_turn
                inc b
fa_turn:
                ld a,b
                call od_k
                jp turn_to_dir

h_o2_waitForActor:                      ; ARGS: actor
                ld de,(ARGS)
                call deref_actor
                ret c
                ld a,(ix+8)
                or a
                ret z
                ld hl,(SPTR)
                dec hl
                dec hl
                ld (SPTR),hl
                jp break_here

; consultores: ARGS: resultado, actor
getter_actor:                           ; -> IX, o carry (ERR puesto)
                ld de,(ARGS+2)
                jp deref_actor

h_o2_getActorX:
                xor a
                jr gx_go
h_o2_getActorY:
                ld a,1
gx_go:
                ld (WK_N),a
                ld hl,(ARGS+2)
                ld a,h
                or a
                jr nz,gx_obj
                ld a,l
                cp NACTORS
                jr nc,gx_obj
                ld bc,0
                or a
                jr z,gx_w               ; el actor 0 siempre da 0
                call actor_addr
                ld a,(WK_N)
                or a
                jr nz,gx_y
                ld c,(ix+1)
                ld b,(ix+2)
                jr gx_w
gx_y:
                ld c,(ix+3)
                ld b,(ix+4)
                jr gx_w
gx_obj:
                call object_or_actor_xy
                jr c,gx_none
                ld a,(ERR)
                or a
                ret nz
                ld hl,(WK_OX)
                ld a,(WK_N)
                or a
                jr z,gx_s
                ld hl,(WK_OY)
gx_s:
                ld b,h
                ld c,l
                jr gx_w
gx_none:
                ld bc,$FFFF
gx_w:
                ld a,(ARGS)
                jp write_var

h_o5_getActorMoving:
                call getter_actor
                ret c
                ld c,(ix+8)
                jr gt_b
h_o5_getActorFacing:
                call getter_actor
                ret c
                ld l,(ix+6)
                ld h,(ix+7)
                call n2o
                ld c,a
                jr gt_b
h_o2_getActorWalkBox:
                call getter_actor
                ret c
                ld c,$FF
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,gt_b
                ld c,(ix+16)
                jr gt_b
h_o5_getActorCostume:
                call getter_actor
                ret c
                ld c,(ix+5)
                jr gt_b
h_o2_getActorElevation:
                call getter_actor
                ret c
                ld a,(ix+17)
                ld c,a
                rla
                sbc a,a
                ld b,a
                jr gt_w
gt_b:
                ld b,0
gt_w:
                ld a,(ARGS)
                jp write_var

h_o2_setActorElevation:                 ; ARGS: actor, elevacion
                ld de,(ARGS)
                call deref_actor
                ret c
                ld a,(ARGS+2)
                ld (ix+17),a
                ret

; o2_loadRoomWithEgo: ARGS: objeto, sala, x, y (x e y son bytes con signo). El protagonista cambia de sala, aparece en el punto de caminar
; del objeto destino (dentro de una caja y mirando hacia el lado contrario), la camara lo sigue (anfitrion), se reinicia la frase y,
; si x e y son >= 0, echa a andar; al final se arranca el script 5.
h_o2_loadRoomWithEgo:
                ld de,(VARS)            ; VAR_EGO
                call deref_actor
                ret c
                ld l,(ix+1)             ; putActor(x, y, sala): conserva la posicion
                ld h,(ix+2)
                ld (PA_X),hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld (PA_Y),hl
                ld a,(ARGS+2)
                ld (PA_ROOM),a
                call put_actor
                ld a,(ERR)
                or a
                ret nz
                ld a,(OPC)              ; start_scene pisa los operandos: se guardan
                push af
                ld a,(ARGN)
                push af
                ld hl,(ARGS+6)
                push hl
                ld hl,(ARGS+4)
                push hl
                ld hl,(ARGS+2)
                push hl
                ld hl,(ARGS)
                push hl
                ld a,(ARGS+2)
                ld l,a
                ld h,0
                call start_scene        ; (siempre: ScummVM no comprueba si ya esta en esa sala)
                pop hl
                ld (ARGS),hl
                pop hl
                ld (ARGS+2),hl
                pop hl
                ld (ARGS+4),hl
                pop hl
                ld (ARGS+6),hl
                pop af
                ld (ARGN),a
                pop af
                ld (OPC),a
                ld a,(ERR)
                or a
                ret nz
                ld de,(VARS)
                call deref_actor
                ret c
                ld hl,(ARGS)            ; si el objeto esta en la sala nueva: va a su punto de caminar
                push ix
                call where_is_object
                pop ix
                cp 1
                jr nz,lre_cam
                ld hl,(ARGS)
                push ix
                call object_xy_pos
                pop ix
                ld c,a
                ld a,(ERR)
                or a
                ret nz
                ld hl,(WK_OX)
                ld (AX_X),hl
                ld hl,(WK_OY)
                ld (AX_Y),hl
                push bc
                call adjust_xy
                pop bc
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld (PA_X),hl
                ld hl,(AX_RY)
                ld (PA_Y),hl
                ld a,(CURROOM)
                ld (PA_ROOM),a
                push bc
                call put_actor
                pop bc
                ld a,(ERR)
                or a
                ret nz
                ld a,c                  ; direccion = oldDirToNewDir(direccion del objeto) + 180
                call od_k
                ld de,180
                add hl,de
                ld de,360
                or a
                sbc hl,de
                jr nc,lre_d
                add hl,de
lre_d:          ld de,(VARS)            ; (put_actor puede haber tocado IX)
                push hl
                call deref_actor
                pop hl
                ld (ix+6),l
                ld (ix+7),h
lre_cam:        call h_host             ; la camara pasa a seguirlo
                call reset_sentence
                ld a,(ARGS+4)
                bit 7,a
                jr nz,lre_run
                ld a,(ARGS+6)
                bit 7,a
                jr nz,lre_run
                ld de,(VARS)
                call deref_actor
                ret c
                ld hl,(ARGS+4)
                ld (WK_X),hl
                ld hl,(ARGS+6)
                ld (WK_Y),hl
                ld hl,$FFFF
                ld (WK_DIR),hl
                call start_walk_actor
                ld a,(ERR)
                or a
                ret nz
lre_run:        ld de,5
                jp run_script
