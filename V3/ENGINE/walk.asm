; =====================================================================
;  walk.asm - caminata de v3 (fase 6), en el overlay D (se incluye desde ovld.asm, despues de geom.asm).
;  Es Actor_v3 de ScummVM (actor.cpp) tal como lo transcribe V3/TOOLS/vmgame3.py: startWalkActor, walkActor, calcMovementFactor,
;  actorWalkStep, remapDirection / updateActorDirection, startWalkAnim, setDirection y turnToDirection.
;  IX = actor en todo el overlay. walkdata.point3.y no cabe en el registro de 64 bytes del actor: va en la tabla P3Y (vm_core.asm).
; =====================================================================
CMX             equ GEOM_END+0          ; calcMovementFactor: el punto siguiente
CMY             equ GEOM_END+2
CMDX            equ GEOM_END+4          ; |diffX|, |diffY| y sus signos (1 = negativo)
CMDY            equ GEOM_END+6
CMSX            equ GEOM_END+8
CMSY            equ GEOM_END+9
CMQY            equ GEOM_END+10         ; palabra: |diffY| / speedy
UDW             equ GEOM_END+12         ; updateActorDirection: is_walking
UDD             equ GEOM_END+13         ; palabra: dir
UDF             equ GEOM_END+15         ; banderas de la caja
UDC             equ GEOM_END+16         ; clases del actor
UDFX            equ GEOM_END+17
UDFY            equ GEOM_END+18
WSNF            equ GEOM_END+19         ; palabra: nextFacing
WALK_END        equ GEOM_END+21
MF_NEW_LEG      equ 0                   ; bits de _moving
MF_IN_LEG       equ 1
MF_TURN         equ 2
MF_LAST_LEG     equ 3

; ---------------------------------------------------------------- utilidades
w_old_dir:      ld a,c                  ; oldDirToNewDir(C & 3) -> HL = 270, 90, 180, 0
                and 3
                add a,a
                ld e,a
                ld d,0
                ld hl,w_dir_tbl
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ret
w_dir_tbl:      defw 270,90,180,0
turn_tbl:       defb 0,2,2,3,2,1,2,3,0,1,2,1,0,1,0,3    ; actorTurnInterpolateTable

w_n2o:          ld de,110               ; newDirToOldDir: HL = angulo -> A = 0 izquierda, 1 derecha, 2 abajo, 3 arriba
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,wn_b
                ld de,71
                or a
                sbc hl,de
                jr c,wn_3
                ld a,1                  ; 71..109
                ret
wn_b:           ld de,252
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,wn_c
                ld a,2                  ; 110..251
                ret
wn_c:           ld de,290
                or a
                sbc hl,de
                jr nc,wn_3
                xor a                   ; 252..289
                ret
wn_3:           ld a,3
                ret

; startAnimActor (version < 7): BC = fotograma pedido. 0x38-0x3C son el fotograma de inicio, caminar, parado, hablar y dejar de hablar
; del actor; 0x3D es un error. Solo cambia el fotograma si el actor esta en la sala y tiene traje (copia de start_anim del overlay B)
w_start_anim:   ld a,b
                or a
                jr nz,wsa_chk
                ld a,c
                cp $38
                jr c,wsa_chk
                cp $3D
                jp z,err_range
                jr nc,wsa_chk
                sub $38
                ld e,a
                ld d,0
                push ix
                pop hl
                add hl,de
                ld de,A_INIT
                add hl,de
                ld c,(hl)
wsa_chk:        call in_room
                ret nz
                ld a,(ix+A_COST)
                or (ix+A_COST+1)
                ret z
                set 0,(ix+A_FLAGS)
                ld (ix+A_FRAME),c
                ret

; turnToDirection(HL = angulo): nada con -1 o con ignoreTurns
w_turn_to:      ld a,h
                and l
                inc a
                ret z
                bit 2,(ix+A_FLAGS)
                ret nz
                ld (ix+A_TFACE),l
                ld (ix+A_TFACE+1),h
                ld (ix+A_MOVING),4      ; MF_TURN
                ret

; Actor::setDirection(HL = angulo ya en 0..359): si cambia, y el actor tiene traje y esta en la sala, hay que redibujarlo
w_set_dir:      ld a,(ix+A_FACING)
                cp l
                jr nz,wsd_1
                ld a,(ix+A_FACING+1)
                cp h
                ret z
wsd_1:          ld (ix+A_FACING),l
                ld (ix+A_FACING+1),h
                ld a,(ix+A_COST)
                or (ix+A_COST+1)
                ret z
                call in_room
                ret nz
                set 0,(ix+A_FLAGS)
                ret

pos16:          ld a,h                  ; A = 1 si HL > 0 (con signo)
                rla
                jr c,p16_0
                ld a,h
                or l
                ret z
                ld a,1
                ret
p16_0:          xor a
                ret

div16_8:        xor a                   ; HL = HL / C (C != 0); A = resto
                ld b,16
d8_l:           add hl,hl
                rla
                jr c,d8_s
                cp c
                jr c,d8_n
d8_s:           sub c
                inc l
d8_n:           djnz d8_l
                ret

p3y_addr:       call actor_num          ; -> HL = direccion de walkdata.point3.y del actor IX
                add a,a
                ld e,a
                ld d,0
                ld hl,P3Y
                add hl,de
                ret

; ---------------------------------------------------------------- remapDirection + updateActorDirection
; upd_dir: A = is_walking -> HL = la direccion siguiente. _targetFacing tiene que estar en 0..359 (lo esta siempre: E_RANGE si no)
upd_dir:        ld (UDW),a
                ld l,(ix+A_TFACE)
                ld h,(ix+A_TFACE+1)
                ld de,360
                push hl
                or a
                sbc hl,de
                pop hl
                jp nc,err_range
                ld (UDD),hl
                ld c,(ix+A_WBOX)
                ld b,0
                call box_addr           ; (sin cajas o caja invalida: banderas 0)
                ld a,0
                jr c,ud_f
                ld de,17
                add hl,de
                ld a,(hl)
ud_f:           ld (UDF),a
                call actor_cls
                ld (UDC),a
                ld l,(ix+A_DXF)
                ld h,(ix+A_DXF+1)
                call pos16
                ld (UDFX),a
                ld l,(ix+A_DYF)
                ld h,(ix+A_DYF+1)
                call pos16
                ld (UDFY),a
                ld a,(UDF)
                and 8
                jr nz,ud_x
                ld a,(UDC)
                and 4
                jr z,ud_nx
ud_x:           ld hl,360               ; volteo en x
                ld de,(UDD)
                or a
                sbc hl,de
                ld (UDD),hl
                ld a,(UDFX)
                xor 1
                ld (UDFX),a
ud_nx:          ld a,(UDF)
                and $10
                jr nz,ud_y
                ld a,(UDC)
                and 2
                jr z,ud_ny
ud_y:           ld hl,180               ; volteo en y
                ld de,(UDD)
                or a
                sbc hl,de
                ld (UDD),hl
                ld a,(UDFY)
                xor 1
                ld (UDFY),a
ud_ny:          ld a,(UDF)
                and 7
                dec a
                jr z,ud_1
                dec a
                jr z,ud_2
                dec a
                jr z,ud_270
                dec a
                jr z,ud_90
                dec a
                jr z,ud_0
                dec a
                jr z,ud_180
                ld hl,(UDD)             ; sin direccion fija: (dir + 360) % 360 y el giro de un paso desde _facing
                ld de,360
                add hl,de
ud_m:           or a
                sbc hl,de
                jr nc,ud_m
                add hl,de
                call w_n2o
                push af
                ld l,(ix+A_FACING)
                ld h,(ix+A_FACING+1)
                call w_n2o
                add a,a
                add a,a
                pop bc
                or b
                ld e,a
                ld d,0
                ld hl,turn_tbl
                add hl,de
                ld c,(hl)
                jp w_old_dir
ud_1:           ld a,(UDW)
                or a
                jr z,ud_1s
                ld a,(UDFX)
                or a
                jr nz,ud_90
                jr ud_270
ud_1s:          ld hl,(UDD)
                ld de,90
                or a
                sbc hl,de
                jr z,ud_90
ud_270:         ld hl,270
                ret
ud_2:           ld a,(UDW)
                or a
                jr z,ud_2s
                ld a,(UDFY)
                or a
                jr nz,ud_180
                jr ud_0
ud_2s:          ld hl,(UDD)
                ld a,h
                or l
                jr z,ud_0
ud_180:         ld hl,180
                ret
ud_90:          ld hl,90
                ret
ud_0:           ld hl,0
                ret

; ---------------------------------------------------------------- Actor_v3::actorWalkStep
; walk_step: -> A = 1 si el actor sigue en el tramo, 0 si ha llegado al punto siguiente
walk_step:      set 0,(ix+A_FLAGS)
                ld a,1
                call upd_dir
                ld (WSNF),hl
                ld e,(ix+A_FACING)
                ld d,(ix+A_FACING+1)
                or a
                sbc hl,de
                ld c,0
                jr z,ws_1
                inc c                   ; C = 1: _facing != nextFacing
ws_1:           bit MF_IN_LEG,(ix+A_MOVING)
                jr z,ws_start
                ld a,c
                or a
                jr z,ws_go
ws_start:       ld a,c
                or a
                jr nz,ws_anim
                ld a,(ix+A_WALK)
                cp (ix+A_FRAME)
                jr z,ws_noan
ws_anim:        ld hl,(WSNF)            ; startWalkAnim(1, nextFacing)
                call w_set_dir
                ld b,0
                ld c,(ix+A_WALK)
                call w_start_anim
ws_noan:        set MF_IN_LEG,(ix+A_MOVING)
                ld a,1
                ret
ws_go:          push ix
                pop iy
                ld c,(ix+A_STEPX)
                call ws_snap
                inc iy
                inc iy
                ld c,(ix+A_SPEEDY)
                call ws_snap
                ld a,(ix+A_CBOX)        ; al entrar en la caja siguiente, el actor pasa a ella
                cp (ix+A_WBOX)
                jr z,ws_nb
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld (BP),hl
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld (BP+2),hl
                ld a,(ix+A_CBOX)
                call cxb_num
                or a
                jr z,ws_nb
                ld a,(ix+A_CBOX)
                ld (ix+A_WBOX),a
ws_nb:          ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld e,(ix+A_NEXTX)
                ld d,(ix+A_NEXTX+1)
                or a
                sbc hl,de
                jr nz,ws_mv
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld e,(ix+A_NEXTY)
                ld d,(ix+A_NEXTY+1)
                or a
                sbc hl,de
                jr nz,ws_mv
                res MF_IN_LEG,(ix+A_MOVING)
                xor a
                ret
ws_mv:          push ix
                pop iy
                call ws_frac
                inc iy
                inc iy
                call ws_frac
                ld a,1
                ret

; ws_snap: IY = IX (eje x) o IX + 2 (eje y), C = paso: si la coordenada esta a `paso` o menos de la del punto siguiente, se pone en ella
ws_snap:        push bc
                ld l,(iy+A_X)
                ld h,(iy+A_X+1)
                ld e,(iy+A_NEXTX)
                ld d,(iy+A_NEXTX+1)
                call sdiff
                pop bc
                ld a,h
                or a
                ret nz
                ld a,c
                cp l
                ret c
                ld a,(iy+A_NEXTX)
                ld (iy+A_X),a
                ld a,(iy+A_NEXTX+1)
                ld (iy+A_X+1),a
                ret

; ws_frac: IY = eje: frac += add (uint16); si llega al umbral, la coordenada avanza deltaFactor (si no esta ya en la del punto siguiente)
ws_frac:        ld l,(iy+A_XFRAC)
                ld h,(iy+A_XFRAC+1)
                ld e,(iy+A_XADD)
                ld d,(iy+A_XADD+1)
                add hl,de
                ld e,(ix+A_STHR)
                ld d,(ix+A_STHR+1)
                push hl
                or a
                sbc hl,de
                jr nc,wf_1
                pop hl
                jr wf_w
wf_1:           pop de
                push hl                 ; frac - umbral
                ld l,(iy+A_X)
                ld h,(iy+A_X+1)
                ld e,(iy+A_NEXTX)
                ld d,(iy+A_NEXTX+1)
                push hl
                or a
                sbc hl,de
                pop hl
                jr z,wf_2
                ld e,(iy+A_DXF)
                ld d,(iy+A_DXF+1)
                add hl,de
                ld (iy+A_X),l
                ld (iy+A_X+1),h
wf_2:           pop hl
wf_w:           ld (iy+A_XFRAC),l
                ld (iy+A_XFRAC+1),h
                ret

; ---------------------------------------------------------------- Actor_v3::calcMovementFactor
; cmf: el punto siguiente en CMX, CMY -> A = 0 si no hay tramo (ya esta alli o esta demasiado cerca), o lo que devuelva actorWalkStep
cmf:            ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld de,(CMX)
                or a
                sbc hl,de
                jr nz,cm_1
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld de,(CMY)
                or a
                sbc hl,de
                jr nz,cm_1
                xor a
                ret
cm_1:           ld hl,(CMX)
                ld e,(ix+A_X)
                ld d,(ix+A_X+1)
                call sdiff
                ld (CMDX),hl
                ld (CMSX),a
                ld hl,(CMY)
                ld e,(ix+A_Y)
                ld d,(ix+A_Y+1)
                call sdiff
                ld (CMDY),hl
                ld (CMSY),a
                bit MF_LAST_LEG,(ix+A_MOVING)
                jr nz,cm_2
                ld hl,(CMDX)            ; (arreglo del fallo #1052 de ScummVM, solo v3): mas cerca que un paso en los dos ejes
                ld a,h
                or a
                jr nz,cm_2
                ld a,l
                cp (ix+A_SPEEDX)
                jr nc,cm_2
                ld hl,(CMDY)
                ld a,h
                or a
                jr nz,cm_2
                ld a,l
                cp (ix+A_SPEEDY)
                jr nc,cm_2
                xor a
                ret
cm_2:           ld a,(ix+A_SPEEDX)      ; (ScummVM dividiria por cero)
                or a
                jp z,err_range
                ld a,(ix+A_SPEEDY)
                or a
                jp z,err_range
                ld hl,(CMDY)
                ld c,(ix+A_SPEEDY)
                call div16_8
                ld (CMQY),hl
                ld hl,(CMDX)
                ld c,(ix+A_SPEEDX)
                call div16_8
                ex de,hl                ; DE = |dx| / speedx
                ld hl,(CMQY)
                srl h
                rr l
                ex de,hl
                or a
                sbc hl,de               ; carry: (|dy| / speedy) >> 1 > |dx| / speedx
                ld a,(ix+A_SPEEDX)
                jr nc,cm_3
                ld a,(ix+A_SPEEDY)
                inc a
                jp z,err_range          ; _stepX no cabe en un byte
cm_3:           ld (ix+A_STEPX),a
                ld c,a
                ld hl,(CMDX)
                call div16_8            ; xAdd = |dx| / stepX
                ld (ix+A_XADD),l
                ld (ix+A_XADD+1),h
                ld (ix+A_XFRAC),l
                ld (ix+A_XFRAC+1),h
                ld de,(CMQY)            ; yAdd = |dy| / speedy
                ld (ix+A_YADD),e
                ld (ix+A_YADD+1),d
                ld (ix+A_YFRAC),e
                ld (ix+A_YFRAC+1),d
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,cm_4
                ex de,hl
cm_4:           ld (ix+A_STHR),l        ; _stepThreshold = el mayor
                ld (ix+A_STHR+1),h
                ld l,(ix+A_STEPX)
                ld a,(CMSX)
                call cm_sgn
                ld (ix+A_DXF),l
                ld (ix+A_DXF+1),h
                ld l,(ix+A_SPEEDY)
                ld a,(CMSY)
                call cm_sgn
                ld (ix+A_DYF),l
                ld (ix+A_DYF+1),h
                ld hl,(CMX)
                ld (ix+A_NEXTX),l
                ld (ix+A_NEXTX+1),h
                ld hl,(CMY)
                ld (ix+A_NEXTY),l
                ld (ix+A_NEXTY+1),h
                ld a,(CMSX)             ; walkdata.facing
                or a
                jr nz,cm_w1
                ld a,(CMSY)
                xor 1
                jr cm_w2
cm_w1:          ld a,(CMSY)
                add a,2
cm_w2:          ld (ix+A_WFAC),a
                ld hl,(CMDX)            ; _targetFacing: |dy| * 3 > |dx| (= |dy| > |dx| / 3) -> arriba o abajo; si no, a los lados
                ld c,3
                call div16_8
                ld de,(CMDY)
                or a
                sbc hl,de
                jr nc,cm_h
                ld a,(CMSY)
                add a,2
                jr cm_t
cm_h:           ld a,(CMSX)
                xor 1
cm_t:           ld c,a
                call w_old_dir
                ld (ix+A_TFACE),l
                ld (ix+A_TFACE+1),h
                jp walk_step
cm_sgn:         ld h,0                  ; HL = L con el signo de A (1 = negativo)
                or a
                ret z
                xor a
                sub l
                ld l,a
                sbc a,a
                ld h,a
                ret

; ---------------------------------------------------------------- Actor_v3::walkActor
walk_actor:     ld a,(ix+A_MOVING)
                or a
                ret z
                bit MF_NEW_LEG,a
                jp nz,wa_new
                bit MF_IN_LEG,a
                jr z,wa_1
                call walk_step
                or a
                ret nz
wa_1:           bit MF_LAST_LEG,(ix+A_MOVING)
                jr z,wa_2
                ld (ix+A_MOVING),0      ; ha llegado
                ld b,0
                ld c,(ix+A_STAND)
                call w_start_anim
                ld l,(ix+A_DESTDIR)
                ld h,(ix+A_DESTDIR+1)
                ld a,(ix+A_TFACE)
                cp l
                jp nz,w_turn_to
                ld a,(ix+A_TFACE+1)
                cp h
                jp nz,w_turn_to
                ret
wa_2:           bit MF_TURN,(ix+A_MOVING)
                jr z,wa_3
                xor a
                call upd_dir
                ld a,(ix+A_FACING)
                cp l
                jp nz,w_set_dir
                ld a,(ix+A_FACING+1)
                cp h
                jp nz,w_set_dir
                ld (ix+A_MOVING),0
                ret
wa_3:           ld l,(ix+A_P3X)
                ld h,(ix+A_P3X+1)
                ld de,32000
                or a
                sbc hl,de
                jr z,wa_4
                add hl,de               ; el segundo punto de la puerta
                ld (CMX),hl
                call p3y_addr
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (CMY),de
                call cmf
                ld (ix+A_P3X),$00       ; 32000
                ld (ix+A_P3X+1),$7D
                or a
                ret nz
wa_4:           ld a,(ix+A_CBOX)
                ld (ix+A_WBOX),a
                ld a,(ix+A_MOVING)
                and 2                   ; MF_IN_LEG
                ld (ix+A_MOVING),a
wa_new:         res MF_NEW_LEG,(ix+A_MOVING)
wa_l:           ld a,(ix+A_WBOX)
                cp $FF
                jr nz,wa_5
                ld a,(ix+A_DBOX)
                ld (ix+A_WBOX),a
                ld (ix+A_CBOX),a
                jp wa_last
wa_5:           cp (ix+A_DBOX)
                jp z,wa_last
                ld b,a
                ld c,(ix+A_DBOX)
                call gnb
                jr nc,wa_6
                set MF_LAST_LEG,(ix+A_MOVING)   ; no hay camino
                ret
wa_6:           ld (ix+A_CBOX),a
                ld (FBX2),a
                ld c,(ix+A_WBOX)
                ld b,0
                call box_addr
                jp c,err_range
                ld (GB1P),hl
                ld a,(FBX2)
                ld c,a
                ld b,0
                call box_addr
                jp c,err_range
                ld (GB2P),hl
                ld a,(ix+A_DBOX)
                ld (FFIN),a
                call fpo
                ld hl,(P2)
                ld de,32000
                or a
                sbc hl,de
                jr nz,wa_p2
                ld hl,(P3)
                or a
                sbc hl,de
                jr z,wa_last            ; ninguno de los dos: directo al destino
                jr wa_p3
wa_p2:          ld hl,(P2)
                ld (CMX),hl
                ld hl,(P2+2)
                ld (CMY),hl
                call cmf
                or a
                jr z,wa_p3
                ld hl,(P3)              ; point3 = p3: el tramo siguiente
                ld (ix+A_P3X),l
                ld (ix+A_P3X+1),h
                call p3y_addr
                ld de,(P3+2)
                ld (hl),e
                inc hl
                ld (hl),d
                ret
wa_p3:          ld hl,(P3)
                ld (CMX),hl
                ld hl,(P3+2)
                ld (CMY),hl
                call cmf
                or a
                ret nz
                ld a,(ix+A_CBOX)
                ld (ix+A_WBOX),a
                jp wa_l
wa_last:        set MF_LAST_LEG,(ix+A_MOVING)
                ld l,(ix+A_DESTX)
                ld h,(ix+A_DESTX+1)
                ld (CMX),hl
                ld l,(ix+A_DESTY)
                ld h,(ix+A_DESTY+1)
                ld (CMY),hl
                jp cmf

; ScummEngine::walkActors: los actores 1..NACT-1 que estan en la sala
ovd_walk:       ld a,1
ow_l:           push af
                call actor_ix
                call in_room
                call z,walk_actor
                pop af
                inc a
                cp NACT
                jr c,ow_l
                ret

; calcMovementFactor(_walkdata.next): setActorWalkSpeed con el actor en movimiento (actorOps 2, overlay B)
ovd_calcmf:     ld l,(ix+A_NEXTX)
                ld h,(ix+A_NEXTX+1)
                ld (CMX),hl
                ld l,(ix+A_NEXTY)
                ld h,(ix+A_NEXTY+1)
                ld (CMY),hl
                jp cmf

; ---------------------------------------------------------------- Actor::startWalkActor (version 3)
; start_walk: IX = actor, WKX, WKY = destino, WKDIR = direccion final (-1: ninguna)
start_walk:     call in_room
                jr z,sw_in
                ld hl,(WKX)             ; fuera de la sala: se le pone alli
                ld (ix+A_X),l
                ld (ix+A_X+1),h
                ld hl,(WKY)
                ld (ix+A_Y),l
                ld (ix+A_Y+1),h
                bit 2,(ix+A_FLAGS)
                ret nz
                ld hl,(WKDIR)
                ld a,h
                and l
                inc a
                ret z
                ld (ix+A_FACING),l
                ld (ix+A_FACING+1),h
                ret
sw_in:          ld a,(ix+A_IGNB)
                or a
                jr z,sw_bx
                ld a,$FF
                ld (ix+A_WBOX),a
                ld (WKBOX),a
                jr sw_eq
sw_bx:          ld hl,(WKX)
                ld (BP),hl
                ld hl,(WKY)
                ld (BP+2),hl
                ld a,(ix+A_DBOX)
                call cxb_num            ; el destino sigue en la caja de destino de antes?
                or a
                jr z,sw_adj
                ld a,(ix+A_DBOX)
                ld (WKBOX),a
                jr sw_mv
sw_adj:         call adjust_xy
sw_mv:          ld a,(ix+A_MOVING)
                or a
                jr z,sw_eq
                ld hl,(WKDIR)           ; ya va hacia alli con la misma direccion final: nada
                ld e,(ix+A_DESTDIR)
                ld d,(ix+A_DESTDIR+1)
                or a
                sbc hl,de
                jr nz,sw_eq
                ld hl,(WKX)
                ld e,(ix+A_DESTX)
                ld d,(ix+A_DESTX+1)
                or a
                sbc hl,de
                jr nz,sw_eq
                ld hl,(WKY)
                ld e,(ix+A_DESTY)
                ld d,(ix+A_DESTY+1)
                or a
                sbc hl,de
                ret z
sw_eq:          ld hl,(WKX)
                ld e,(ix+A_X)
                ld d,(ix+A_X+1)
                or a
                sbc hl,de
                jr nz,sw_go
                ld hl,(WKY)
                ld e,(ix+A_Y)
                ld d,(ix+A_Y+1)
                or a
                sbc hl,de
                jr nz,sw_go
                ld hl,(WKDIR)           ; ya esta en el destino: solo girar
                ld a,(ix+A_FACING)
                cp l
                jp nz,w_turn_to
                ld a,(ix+A_FACING+1)
                cp h
                jp nz,w_turn_to
                ret
sw_go:          ld hl,(WKX)
                ld (ix+A_DESTX),l
                ld (ix+A_DESTX+1),h
                ld hl,(WKY)
                ld (ix+A_DESTY),l
                ld (ix+A_DESTY+1),h
                ld a,(WKBOX)
                ld (ix+A_DBOX),a
                ld hl,(WKDIR)
                ld (ix+A_DESTDIR),l
                ld (ix+A_DESTDIR+1),h
                ld (ix+A_P3X),$00       ; 32000
                ld (ix+A_P3X+1),$7D
                ld a,(ix+A_WBOX)
                ld (ix+A_CBOX),a
                ld a,(ix+A_MOVING)
                and 2                   ; MF_IN_LEG
                or 1                    ; MF_NEW_LEG
                ld (ix+A_MOVING),a
                ret
