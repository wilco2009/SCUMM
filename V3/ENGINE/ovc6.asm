; =====================================================================
;  ovc6.asm - fase 6, overlay C (se incluye desde ovlc.asm): los cuatro opcodes de caminata. Leen sus operandos aqui y entran en el overlay D
;  (ovld.asm: geom.asm + walk.asm) por call_ovd, con el actor en IX y los argumentos en WKX, WKY y WKDIR.
;  Semantica: ScummVM (script_v5.cpp, script_v3.cpp) como la transcribe V3/TOOLS/vmmodel3.py.
; =====================================================================

; walkActorTo: B1 W2 W3
b_walkActorTo:  call rd_vb1
                call chk_actor          ; IX (derefActor antes de leer lo demas, como el modelo)
                call rd_vw2
                ld (WKX),bc
                call rd_vw3
                ld (WKY),bc
                ld (SPTR),de
wk_go:          ld hl,$FFFF             ; sin direccion final
                ld (WKDIR),hl
wk_start:       ld hl,OVD_STARTWALK
                jp call_ovd

; walkActorToObject: B1 W2. Si el objeto esta (en la sala o en el inventario), camina a su punto de acercamiento y acaba mirando en su
; direccion (getObjectXYPos: un objeto del inventario sin registro en la sala es E_BADOBJ)
b_walkActorToObject:
                call rd_vb1
                call chk_actor
                call rd_vw2
                ld (SPTR),de
                call wio
                inc a
                ret z                   ; WIO_NOT_FOUND
                call obj_index
                jp nz,err_badobj
                ld de,OB_WX
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (WKX),de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (WKY),de
                ld a,(hl)               ; direccion del actor (0-7)
                and 3
                add a,a
                ld e,a
                ld d,0
                ld hl,wk_dirs
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (WKDIR),de
                jr wk_start
wk_dirs:        defw 270,90,180,0       ; oldDirToNewDir

; walkActorToActor: B1 B2 b. Los dos tienen que ser actores validos y estar en la sala. Camina hasta `dist` del otro por el lado en que
; esta (dist $FF: la anchura del que anda mas la mitad de la del otro), con el punto ajustado a las cajas (v3)
b_walkActorToActor:
                call rd_vb1
                push bc
                call rd_vb2
                ld a,(de)
                inc de
                ld (SPTR),de
                ld (SC+0),a             ; dist
                pop hl                  ; HL = el que anda, BC = el otro
                push bc
                ld b,h
                ld c,l
                call is_act13
                or a
                jr z,wta_x
                ld a,c
                call actor_ix
                call in_room
                jr nz,wta_x
                push ix
                pop iy                  ; IY = el que anda
                pop bc
                call is_act13
                or a
                ret z
                ld a,c
                call actor_ix           ; IX = el otro
                call in_room
                ret nz
                ld a,(SC+0)
                ld l,a
                ld h,0
                cp $FF
                jr nz,wta_d
                ld l,(ix+A_WIDTH)
                srl l
                ld a,(iy+A_WIDTH)
                add a,l
                ld l,a
                ld a,0
                adc a,0
                ld h,a
wta_d:          ex de,hl                ; DE = dist
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld (WKY),hl
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                push hl
                push de
                ld e,(iy+A_X)
                ld d,(iy+A_X+1)
                call sless              ; el otro esta a la izquierda?
                pop de
                pop hl
                jr c,wta_add
                or a
                sbc hl,de
                jr wta_s
wta_add:        add hl,de
wta_s:          ld (WKX),hl
                push iy
                pop ix
                ld hl,OVD_ADJUST
                call call_ovd           ; adjustXYToBeInBox(a, x, y)
                jp wk_go
wta_x:          pop bc
                ret

; waitForActor (o3_waitForActor, Indy3): B1. Si el actor se esta moviendo, la instruccion se repite en el fotograma siguiente
b_waitForActor: ld h,d
                ld l,e
                dec hl
                push hl                 ; el opcode
                call rd_vb1
                ld (SPTR),de
                call chk_actor
                pop hl
                ld a,(ix+A_MOVING)
                or a
                ret z
                ld (SPTR),hl
                jp break_here
