; =====================================================================
;  ovc5.asm - fase 5 en el overlay C (se incluye desde ovlc.asm tras ovc1.asm): salas, objetos y frases.
;  Semantica: V3/TOOLS/vmmodel3.py (CoreVM) + vmgame3.py (start_scene, find_object, ...). Entran por ovc_op con DE = puntero tras el opcode
;  (SPTR antes de nada que pueda correr otro script); lo que corre scripts (startScene, run_script...) no puede guardar nada en SC: todo va en la
;  pila. Los puntos de entrada de B (OVB_xxx, vm.asm) dan stop_talk, hide_actor, showActors, setCameraFollows y put_actor.
; =====================================================================

chk_obj_hl:     ld de,NOBJ              ; HL = objeto: E_BADOBJ si no esta en 0..NOBJ-1 (conserva HL)
                or a
                sbc hl,de
                jp nc,err_badobj
                add hl,de
                ret

; ---------------------------------------------------------------- cola de frases
; sent_add (doSentence): A = verbo, HL = a, DE = b. E_RANGE si la cola esta llena
sent_add:       push af
                push hl
                push de
                ld a,(SENTN)
                cp NSENT
                jp nc,err_range
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                or a
                sbc hl,de               ; 7 * n
                ld de,SENTQ
                add hl,de
                pop de                  ; b
                pop bc                  ; a
                pop af                  ; verbo
                ld (hl),a
                inc hl
                ld (hl),c
                inc hl
                ld (hl),b
                inc hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,d
                or e
                jr z,sa_p
                ld a,1                  ; preposicion = (b <> 0)
sa_p:           ld (hl),a
                inc hl
                ld (hl),0               ; congelada
                ld hl,SENTN
                inc (hl)
                ret

ovc_sentadd:    ld a,(APIVERB)
                ld hl,(APIN)
                ld de,(APIA)
                jp sent_add

; doSentence: B1 Q W2 W3. El verbo $FE vacia la cola y para el script de frases. Un verbo fuera de 0..255 es E_RANGE (el Z80 lo guarda en un byte)
b_doSentence:   call rd_vb1
                ld a,b
                or a
                jp nz,err_range
                ld a,c
                cp $FE
                jr z,ds_clr
                push bc
                call rd_vw2
                push bc
                call rd_vw3
                ld (SPTR),de
                ld d,b
                ld e,c                  ; DE = b
                pop hl                  ; HL = a
                pop bc
                ld a,c                  ; verbo
                jp sent_add
ds_clr:         ld (SPTR),de
                xor a
                ld (SENTN),a
                ld hl,(VAR_SENTENCE_SCRIPT)
                jp stop_script

; script_in_use: HL = numero -> A = 1 si hay una ranura con ese numero (de cualquier estado), si no 0. Conserva DE
script_in_use:  ld ix,SLOTS
                ld b,NSLOT
                push de
                ld de,16
siu_l:          ld a,(ix+SL_NUM)
                cp l
                jr nz,siu_n
                ld a,(ix+SL_NUM+1)
                cp h
                jr z,siu_y
siu_n:          add ix,de
                djnz siu_l
                pop de
                xor a
                ret
siu_y:          pop de
                ld a,1
                ret

; waitForSentence: espera mientras haya una frase en cola (no congelada) o el script de frases este en uso
b_waitForSentence:
                ld a,(SENTN)
                or a
                jr z,ws_e
                dec a
                ld l,a
                ld h,0
                ld b,h
                ld c,l
                add hl,hl
                add hl,hl
                add hl,hl
                or a
                sbc hl,bc               ; 7 * (n - 1)
                ld bc,SENTQ+SQ_FRZ
                add hl,bc
                ld a,(hl)
                or a
                jr z,ws_wait            ; la ultima no esta congelada: esperar
ws_e:           ld hl,(VAR_SENTENCE_SCRIPT)
                call script_in_use
                or a
                jr z,ws_go
ws_wait:        dec de
                ld (SPTR),de
                jp break_here
ws_go:          ld (SPTR),de
                ret

; checkAndRunSentenceScript (cada fotograma con frases en cola)
ovc_sent:       ld hl,(VAR_SENTENCE_SCRIPT)
                ld ix,SLOTS
                ld b,NSLOT
                ld de,16
os_l:           ld a,(ix+SL_NUM)
                cp l
                jr nz,os_n
                ld a,(ix+SL_NUM+1)
                cp h
                jr nz,os_n
                ld a,(ix+SL_STAT)
                or a
                jr z,os_n
                ld a,(ix+SL_FREEZE)
                or a
                ret z                   ; el script de frases esta vivo y sin congelar: aun no
os_n:           add ix,de
                djnz os_l
                ld a,(SENTN)
                or a
                ret z
                dec a
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                or a
                sbc hl,de
                ld de,SENTQ
                add hl,de
                push hl
                pop ix                  ; IX = la ultima frase
                ld a,(ix+SQ_FRZ)
                or a
                ret nz                  ; congelada: no se ejecuta
                ld a,(SENTN)
                dec a
                ld (SENTN),a            ; pop
                ld a,(ix+SQ_PREP)
                or a
                jr z,os_run
                ld l,(ix+SQ_A)
                ld h,(ix+SQ_A+1)
                ld e,(ix+SQ_B)
                ld d,(ix+SQ_B+1)
                or a
                sbc hl,de
                ret z                   ; con preposicion y b == a: nada
os_run:         ld a,(ix+SQ_VERB)
                ld (VARARG),a
                xor a
                ld (VARARG+1),a
                ld l,(ix+SQ_A)
                ld h,(ix+SQ_A+1)
                ld (VARARG+2),hl
                ld l,(ix+SQ_B)
                ld h,(ix+SQ_B+1)
                ld (VARARG+4),hl
                ld a,3
                ld (VACNT),a
                ld a,$FF
                ld (CUR),a
                ld hl,(VAR_SENTENCE_SCRIPT)
                ld a,h
                or l
                jr z,os_nos
                xor a
                jp run_script
os_nos:         xor a
                ld (VACNT),a
                ret

; ---------------------------------------------------------------- pseudosalas
b_pseudoRoom:   ld a,(de)
                inc de
                ld c,a                  ; i: la sala
pr_l:           ld a,(de)
                inc de
                or a
                jr z,pr_end
                cp $80
                jr c,pr_l
                and $7F
                ld l,a
                ld h,0
                push de
                ld de,RESMAP
                add hl,de
                pop de
                ld a,c
                or a
                jp z,err_range          ; 0 es "sin asignar" en el Z80
                ld (hl),a
                jr pr_l
pr_end:         ld (SPTR),de
                ret

; ---------------------------------------------------------------- cajas
; (box_addr esta en el residente desde la fase 6: lo usan tambien B y D)
; setBoxFlags: B1 b. Las banderas son el byte +17 de la caja
b_setBoxFlags:  call rd_vb1
                ld a,(de)
                inc de
                ld (SPTR),de
                push af
                call box_addr
                jr c,sbf_n
                ld de,17
                add hl,de
                pop af
                ld (hl),a
                ret
sbf_n:          pop af
                ret

; sdiff: HL - DE con signo (s16, resultado de 17 bits) -> HL = valor absoluto (16 bits), A = 1 si era negativo
sdiff:          ld a,h
                rla
                sbc a,a
                ld b,a
                ld a,d
                rla
                sbc a,a
                ld c,a
                or a
                sbc hl,de
                ld a,b
                sbc a,c
                rla
                ld a,0
                rla                     ; A = bit de signo
                or a
                ret z
                xor a
                sub l
                ld l,a
                ld a,0
                sbc a,h
                ld h,a
                ld a,1
                ret

; mul16: BC * DE -> DE:HL (32 bits sin signo)
mul16:          ld hl,0
                ld a,16
m16_l:          add hl,hl
                rl e
                rl d
                jr nc,m16_n
                add hl,bc
                jr nc,m16_n
                inc de
m16_n:          dec a
                jr nz,m16_l
                ret

; edge_ok: HL = &esquina A, DE = &esquina B (cada una x, y: 4 bytes); el punto en SC+0 (x), SC+2 (y). compare_slope(A, B, p):
; (By - Ay) * (px - Ax) <= (py - Ay) * (Bx - Ax), con productos de 32 bits (signo y modulo). A = 1 si se cumple
edge_ok:        ld (SC+4),hl
                ld (SC+6),de
                ld hl,(SC+4)
                ld de,SC+8
                ld bc,4
                ldir                    ; SC+8: Ax, SC+10: Ay
                ld hl,(SC+6)
                ld bc,4
                ldir                    ; SC+12: Bx, SC+14: By
                ld hl,(SC+14)
                ld de,(SC+10)
                call sdiff              ; dy1
                ld (SC+16),a
                push hl
                ld hl,(SC+0)
                ld de,(SC+8)
                call sdiff              ; dx2
                ld b,h
                ld c,l
                ld hl,SC+16
                xor (hl)
                ld (SC+16),a            ; el signo del producto
                pop de
                call mul16
                ld (N1),hl
                ld (N1+2),de
                ld a,d
                or e
                or h
                or l
                jr nz,eo_1
                ld (SC+16),a            ; producto 0: positivo
eo_1:           ld hl,(SC+2)
                ld de,(SC+10)
                call sdiff              ; dy2
                ld (SC+17),a
                push hl
                ld hl,(SC+12)
                ld de,(SC+8)
                call sdiff              ; dx1
                ld b,h
                ld c,l
                ld hl,SC+17
                xor (hl)
                ld (SC+17),a
                pop de
                call mul16
                ld (NR),hl
                ld (NR+2),de
                ld a,d
                or e
                or h
                or l
                jr nz,eo_2
                ld (SC+17),a
eo_2:           ld a,(SC+16)            ; L <= R ?
                ld b,a
                ld a,(SC+17)
                cp b
                jr z,eo_same
                ld a,b                  ; signos distintos: L <= R si L es negativo
                ret
eo_same:        ld a,b
                or a
                jr nz,eo_neg
                ld hl,(NR)              ; ambos positivos: N1 <= NR
                ld de,(N1)
                or a
                sbc hl,de
                ld hl,(NR+2)
                ld de,(N1+2)
                sbc hl,de
                ld a,1
                ret nc
                xor a
                ret
eo_neg:         ld hl,(N1)              ; ambos negativos: |L| >= |R|
                ld de,(NR)
                or a
                sbc hl,de
                ld hl,(N1+2)
                ld de,(NR+2)
                sbc hl,de
                ld a,1
                ret nc
                xor a
                ret

; axis_rej: HL = v (s16), A = 0 (x) o 2 (y), IY = caja -> A = 1 si v es menor que las 4 esquinas o mayor que las 4 (fase 10d: es decir,
; fuera de [la menor, la mayor]; se compara sin signo con el bit de signo invertido)
axis_rej:       or a
                jr z,arj_x
                inc iy
                inc iy
                call arj_x
                dec iy
                dec iy
                ret
arj_x:          ld a,h
                xor $80
                ld h,a
                push hl
                ld e,(iy+0)
                ld a,(iy+1)
                xor $80
                ld d,a                  ; DE = la menor
                ld b,d
                ld c,e                  ; BC = la mayor
                ld l,(iy+4)
                ld a,(iy+5)
                xor $80
                ld h,a
                call arj_mm
                ld l,(iy+8)
                ld a,(iy+9)
                xor $80
                ld h,a
                call arj_mm
                ld l,(iy+12)
                ld a,(iy+13)
                xor $80
                ld h,a
                call arj_mm
                pop hl
                ld a,l
                sub e
                ld a,h
                sbc a,d
                jr c,arj_y              ; v < la menor
                ld a,c
                sub l
                ld a,b
                sbc a,h
                jr c,arj_y              ; v > la mayor
                xor a
                ret
arj_y:          ld a,1
                ret
arj_mm:         ld a,l                  ; HL = una esquina: DE = min(DE, HL), BC = max(BC, HL)
                sub e
                ld a,h
                sbc a,d
                jr nc,arm_1
                ld d,h
                ld e,l
                ret
arm_1:          ld a,c
                sub l
                ld a,b
                sbc a,h
                ret nc
                ld b,h
                ld c,l
                ret

; checkXYInBoxBounds (version < 7): BC = caja, IX = actor -> A = 1 si el actor esta dentro
check_xy_box:   bit 7,b
                jr nz,cxb_f             ; caja negativa
                ld a,c
                cp $FF
                jr nz,cxb_g
                ld a,b
                or a
                jr z,cxb_f              ; caja invalida
cxb_g:          call box_addr
                jp c,err_range          ; sin cajas
                push hl
                pop iy
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld (SC+0),hl
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld (SC+2),hl
                ld hl,(SC+0)
                xor a
                call axis_rej
                or a
                jr nz,cxb_f
                ld hl,(SC+2)
                ld a,2
                call axis_rej
                or a
                jr nz,cxb_f
                push iy
                pop hl
                ld d,h
                ld e,l
                inc de
                inc de
                inc de
                inc de                  ; ul -> ur
                call edge_ok
                or a
                jr z,cxb_f
                push iy
                pop hl
                ld de,4
                add hl,de
                ld d,h
                ld e,l
                inc de
                inc de
                inc de
                inc de                  ; ur -> lr
                call edge_ok
                or a
                jr z,cxb_f
                push iy
                pop hl
                ld de,8
                add hl,de
                ld d,h
                ld e,l
                inc de
                inc de
                inc de
                inc de                  ; lr -> ll
                call edge_ok
                or a
                jr z,cxb_f
                push iy
                pop hl
                ld de,12
                add hl,de
                push iy
                pop de                  ; ll -> ul
                call edge_ok
                ret                     ; A = 1 si se cumple la ultima (y las demas lo hicieron)
cxb_f:          xor a
                ret

; isActorInBox: B1 B2 J. La condicion verdadera no salta
b_isActorInBox: call rd_vb1
                push bc
                call rd_vb2
                pop hl
                push de                 ; puntero del script (check_xy_box usa DE)
                push bc                 ; caja
                ld b,h
                ld c,l
                call chk_actor          ; IX = actor
                pop bc
                call check_xy_box
                pop de
                or a
                jp nz,no_jump
                jp do_jump

; ---------------------------------------------------------------- objetos de la sala
; rec_addr: A = indice (1..) -> HL = su registro de RBLOB. Destruye A, DE; conserva BC
rec_addr:       dec a
                ld l,a
                ld h,0
                add hl,hl
                ld d,h
                ld e,l                  ; 2x
                add hl,hl               ; 4x
                add hl,de               ; 6x
                add hl,hl               ; 12x
                add hl,de               ; 14x
                ld de,(OBJP)
                add hl,de
                ret

; rng8: HL = v (s16), B = inicio / 8, C = tamano / 8 -> carry si inicio * 8 <= v < (inicio + tamano) * 8. Usa SC+8..13
rng8:           ld (SC+8),hl
                ld l,b
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld (SC+10),hl           ; inicio
                ld e,c
                ld d,0
                ex de,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(SC+10)
                add hl,de
                ld (SC+12),hl           ; fin
                ld hl,(SC+8)
                ld de,(SC+10)
                call sless
                jr c,rg_no
                ld hl,(SC+8)
                ld de,(SC+12)
                call sless
                ret                     ; carry = v < fin
rg_no:          or a
                ret

; findObject: R B1 B2. x en SC+0, y en SC+2, indice en SC+4, padre en SC+5, estado del padre en SC+6 (no corren scripts)
b_findObject:   call rd_res
                call rd_vb1
                push bc
                call rd_vb2
                ld (SPTR),de
                ld (SC+2),bc
                pop bc
                ld (SC+0),bc
                call find_object
                ld b,h
                ld c,l
                jp set_res
find_object:    ld a,(NROBJ)
                or a
                jp z,fo_none
                call cls_open
                ld a,1
                ld (SC+4),a
fo_i:           ld a,(SC+4)
                call rec_addr
                ld e,(hl)
                inc hl
                ld d,(hl)
                bit 7,d
                jp nz,fo_next
                ld a,d
                or e
                jp z,fo_next
                ld h,d
                ld l,e
                ld bc,NOBJ
                or a
                sbc hl,bc
                jp nc,err_badobj
                ld h,d
                ld l,e
                call cls_ptr            ; HL = sus clases en la ventana
                inc hl
                inc hl
                bit 7,(hl)              ; UNTOUCHABLE (clase 32 -> bit 23)
                jp nz,fo_next
                ld a,(SC+4)
                ld (SC+5),a             ; b = i
fo_p:           ld a,(SC+5)
                ld hl,NROBJ
                cp (hl)
                jr c,fo_pr
                jr z,fo_pr
                xor a                   ; b > n: un registro vacio (estado 0, padre 0)
                ld (SC+6),a
                ld (SC+5),a
                jr fo_b0
fo_pr:          call rec_addr
                push hl
                ld de,OB_PST
                add hl,de
                ld a,(hl)
                ld (SC+6),a
                pop hl
                ld de,OB_PAR
                add hl,de
                ld a,(hl)
                ld (SC+5),a
fo_b0:          or a
                jr z,fo_rect
                cp 200
                jr nc,fo_next
                ld hl,NROBJ
                cp (hl)
                jr c,fo_sb
                jr z,fo_sb
                xor a
                jr fo_cmp
fo_sb:          call rec_addr
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,OBJST
                add hl,de
                ld a,(hl)
                and $0F
fo_cmp:         ld hl,SC+6
                cp (hl)
                jr nz,fo_next
                jr fo_p
fo_rect:        ld a,(SC+4)
                call rec_addr
                push hl
                pop ix
                ld b,(ix+OB_X)
                ld c,(ix+OB_W)
                ld hl,(SC+0)
                call rng8
                jr nc,fo_next
                ld b,(ix+OB_Y)
                ld c,(ix+OB_H)
                ld hl,(SC+2)
                call rng8
                jr nc,fo_next
                ld l,(ix+OB_ID)
                ld h,(ix+OB_ID+1)
                push hl
                call cls_close
                pop hl
                ret
fo_next:        ld a,(SC+4)
                inc a
                ld (SC+4),a
                ld hl,NROBJ
                cp (hl)
                jp c,fo_i
                jp z,fo_i
                call cls_close
fo_none:        ld hl,0
                ret

; drawObject: W1 W2 W3 (objeto, x, y). Con x <> 255 mueve el objeto a (x * 8, y * 8) (el Z80 guarda x/8 e y/8 en un byte: 0..254 y 0..255, si no E_RANGE)
b_drawObject:   call rd_vw1
                ld (SC+0),bc
                call rd_vw2
                ld (SC+2),bc
                call rd_vw3
                ld (SPTR),de
                ld (SC+4),bc
                ld bc,(SC+0)
                call obj_index
                ret nz                  ; el objeto no esta en la sala
                push hl
                pop ix                  ; IX = su registro
                ld hl,(SC+2)
                ld de,255
                or a
                sbc hl,de
                jp z,do_state           ; x = 255: sin mover
                ld a,(SC+3)
                ld b,a
                ld a,(SC+5)
                or b
                jp nz,err_range
                ld a,(SC+2)
                sub (ix+OB_X)
                ld l,a
                sbc a,a
                ld h,a
                add hl,hl
                add hl,hl
                add hl,hl               ; (x - x0) * 8
                ld e,(ix+OB_WX)
                ld d,(ix+OB_WX+1)
                add hl,de
                ld (ix+OB_WX),l
                ld (ix+OB_WX+1),h
                ld a,(SC+2)
                ld (ix+OB_X),a
                ld a,(SC+4)
                sub (ix+OB_Y)
                ld l,a
                sbc a,a
                ld h,a
                add hl,hl
                add hl,hl
                add hl,hl
                ld e,(ix+OB_WY)
                ld d,(ix+OB_WY+1)
                add hl,de
                ld (ix+OB_WY),l
                ld (ix+OB_WY+1),h
                ld a,(SC+4)
                ld (ix+OB_Y),a
do_state:       ld a,(NROBJ)            ; los que ocupan el mismo rectangulo pasan al estado 0
                or a
                jr z,dr_done
                ld b,a                  ; fase 10b: del ultimo al primero recorriendo los registros (14 bytes) sin rec_addr en cada uno
                call rec_addr
dr_l:           push hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                jr z,dr_n
                inc hl
                ld a,(hl)
                cp (ix+OB_X)
                jr nz,dr_n
                inc hl
                ld a,(hl)
                cp (ix+OB_Y)
                jr nz,dr_n
                inc hl
                ld a,(hl)
                cp (ix+OB_W)
                jr nz,dr_n
                inc hl
                ld a,(hl)
                cp (ix+OB_H)
                jr nz,dr_n
                ld h,d
                ld l,e
                call chk_obj_hl         ; (si da error, vm_err restaura SP)
                ld de,OBJST
                add hl,de
                ld (hl),0
dr_n:           pop hl
                ld de,-14
                add hl,de
                djnz dr_l
dr_done:        xor a
                ld (SC+6),a             ; como antes: el contador acaba en 0
                ld hl,(SC+0)
                call chk_obj_hl
                ld de,OBJST
                add hl,de
                ld (hl),1
                ld hl,(SC+0)
                ld (EVARGS),hl
                ld l,(ix+OB_X)
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld (EVARGS+2),hl
                ld l,(ix+OB_Y)
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld (EVARGS+4),hl
                ld hl,1
                ld (EVARGS+6),hl
                ld a,EV_DRAWOBJ
                jp ev_emit

; pickupObject: W1
b_pickupObject: call rd_vw1
                ld (SPTR),de
                bit 7,b
                jp nz,err_badobj
                ld a,b
                or c
                jp z,err_badobj
                call obj_index
                ret nz                  ; no esta en la sala
                call wio
                or a
                ret z                   ; ya esta en el inventario
                ld hl,INVSL
                ld d,NINV
po_f:           ld a,(hl)
                inc hl
                or (hl)
                jr z,po_set
                inc hl
                dec d
                jr nz,po_f
                jp err_range            ; inventario lleno
po_set:         ld (hl),b
                dec hl
                ld (hl),c
                ld hl,(VAR_EGO)         ; putOwner(obj, VAR_EGO): 0..255
                ld a,h
                or a
                jp nz,err_range
                ld a,l
                ld hl,OBJOWN
                add hl,bc
                ld (hl),a
                ld h,b                  ; putClass(obj, UNTOUCHABLE): clase 32 = bit 23
                ld l,c
                call cls_ptr
                inc hl
                inc hl
                call cls_open
                set 7,(hl)
                call cls_close
                ld hl,OBJST
                add hl,bc
                ld (hl),1
                ld (EVARGS),bc
                ld hl,1
                ld (EVARGS+2),hl
                ld a,EV_OBJSTATE
                call ev_emit
                ld c,1                  ; runInventoryScript(1)
                jp run_inv

; ---------------------------------------------------------------- verbos de un objeto: getVerbEntrypoint, startObject
; gve: BC = objeto, DE = verbo (palabra) -> HL = la direccion de la terna (desde el principio del OBCD) o 0. E_BADOBJ si el objeto esta pero no tiene OBCD
gve:            push de
                call wio
                inc a
                jr z,gve_0
                call odir
                or a
                jp z,err_badobj
                call map_page
                ld de,17
                add hl,de
                pop de
gve_l:          ld a,(hl)
                or a
                jr z,gve_z
                inc a
                jr z,gve_f
                dec a
                cp e
                jr nz,gve_n
                ld a,d
                or a
                jr z,gve_f
gve_n:          inc hl
                inc hl
                inc hl
                jr gve_l
gve_f:          inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                jr gve_r
gve_z:          ld hl,0
gve_r:          push hl
                call restore_win
                pop hl
                ret
gve_0:          pop de
                ld hl,0
                ret

b_getVerbEntrypoint:
                call rd_res
                call rd_vw1
                push bc
                call rd_vw2
                ld (SPTR),de
                ld d,b
                ld e,c
                pop bc
                call gve
                ld b,h
                ld c,l
                jp set_res

; runObjectScript: HL = objeto, DE = verbo (palabra); los argumentos estan en VARARG (VACNT). Si no arranca nada, VACNT = 0
run_object_script:
                ld a,h
                or l
                jr z,ros_none
                push de                 ; verbo
                push hl
                call stop_object_script
                pop bc                  ; BC = objeto
                call wio
                inc a
                jr z,ros_nf
                dec a
                ld (APIW),a             ; donde: 0 inventario, 1 sala
                push bc
                call alloc_slot         ; (destruye BC)
                pop bc
                ld (RNTMP),a
                call odir
                or a
                jp z,err_badobj
                ld (APIP),a
                ld (APIA),hl
                ld (APIN),bc
                call map_page
                ld de,17
                add hl,de
                pop de                  ; verbo
ros_l:          ld a,(hl)
                or a
                jr z,ros_nw
                inc a
                jr z,ros_f
                dec a
                cp e
                jr nz,ros_n
                ld a,d
                or a
                jr z,ros_f
ros_n:          inc hl
                inc hl
                inc hl
                jr ros_l
ros_f:          inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                jr z,ros_nw
                ld hl,(APIA)
                add hl,de
                ld (APIA),hl
                xor a
                ld (APIBIG),a
                ld (APIFL),a
                ld a,(RNTMP)
                jp start_slot_at
ros_nw:         call restore_win
                jr ros_none
ros_nf:         pop de
ros_none:       xor a
                ld (VACNT),a
                ret

; startObject: W1 B2 L
b_startObject:  call rd_vw1
                push bc
                call rd_vb2
                push bc
                call rd_vararg
                ld (SPTR),de
                pop de                  ; verbo
                pop hl                  ; objeto
                jp run_object_script

; ---------------------------------------------------------------- salas
; load_room_state: C = recurso de sala, B = 1: con cajas. CURRD = su entrada de ROOMDIR (ceros si no existe), su blob en RBLOB, OBJP, OBJEND, NROBJ, MATP
; y NBOXES. No toca scripts ni actores. La ventana de datos vuelve a la pagina del script en curso
ovc_room:       push bc
                ld a,c
                cp 100
                jr c,lr_a
                xor a
lr_a:           ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,CURRD
                ld bc,32
                call cold_rd
                xor a
                ld (NROBJ),a
                ld (NBOXES),a
                ld (ROOMRES),a
                ld hl,(CURRD+6)         ; ancho: 0 = la sala no existe
                ld a,h
                or l
                jr nz,lr_e
                pop bc
                ret
lr_e:           pop bc
                push bc
                ld a,c
                ld (ROOMRES),a          ; fase 6: el recurso de la sala cargada
                ld bc,(CURRD+13)        ; bytes del blob
                ld hl,RB_MAX
                or a
                sbc hl,bc
                jp c,err_range
                ld a,(CURRD+10)
                call map_page
                ld hl,(CURRD+11)
                ld de,RBLOB
                ldir
                call restore_win
                ld a,(RBLOB)            ; cajas
                ld e,a
                ld d,0
                ld l,e
                ld h,d
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,de
                add hl,de               ; 18 * n
                ld bc,RBLOB+1
                add hl,bc
                ld (MATP),hl            ; u16 con el tamano de la matriz, y la matriz
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                add hl,bc
                ld a,(hl)               ; numero de objetos
                inc hl
                ld (NROBJ),a
                ld (OBJP),hl
                ld e,a
                ld d,0
                ld l,e
                ld h,d
                add hl,hl
                ld b,h
                ld c,l                  ; 2 n
                add hl,hl               ; 4 n
                add hl,bc               ; 6 n
                add hl,hl               ; 12 n
                add hl,bc               ; 14 n
                ld de,(OBJP)
                add hl,de
                ld (OBJEND),hl
                pop bc
                ld a,b
                or a
                ret z
                ld a,(RBLOB)
                ld (NBOXES),a
                jp gt_load

; gt_load (fase 10d): la tabla de puertas de la sala (ROOMDIR +22 en CURRD: pagina, direccion y bytes; pack_data3.gate_table) a GT_OFF + 1 en
; la pagina CLS_PG, por la ventana y de 256 en 256 bytes por GW (libre fuera de la caminata), con la sala (ROOMRES) en GT_OFF; sin tabla, 0
; entradas. La ventana vuelve a la pagina del script en curso (o, sin script, a la que tenia). La llaman ovc_room y la carga de partidas
gt_load:        ld a,(WINPG)
                ld (CLSSV),a
                ld a,CLS_PG
                call map_phys
                ld a,(ROOMRES)
                ld (GT_OFF+WINDOW),a
                xor a
                ld (GT_OFF+WINDOW+1),a
                ld bc,(CURRD+25)
                ld hl,(CURRD+23)
                ld de,GT_OFF+WINDOW+1
lg_l:           ld a,b
                or c
                jr z,lg_e
                push bc                 ; lo que queda
                ld a,b
                or a
                jr z,lg_c               ; menos de 256: BC
                ld bc,256
lg_c:           push bc                 ; el trozo
                ld a,(CURRD+22)
                call map_page           ; (conserva BC, DE y HL)
                push de
                ld de,GW
                ldir                    ; HL: el siguiente de la tabla
                pop de
                pop bc
                push hl
                push bc
                ld a,CLS_PG
                call map_phys
                ld hl,GW
                ldir                    ; DE: el siguiente de GT
                pop bc                  ; el trozo
                pop hl
                ex (sp),hl              ; HL = lo que quedaba; en la pila, la fuente
                or a
                sbc hl,bc
                ld b,h
                ld c,l
                pop hl
                jr lg_l
lg_e:           ld a,(CUR)
                inc a
                jp nz,restore_win
                ld a,(CLSSV)
                jp map_phys

; start_enc: HL = numero (10001 EXCD / 10002 ENCD), A = pagina, DE = direccion: arranca el codigo de salida o de entrada de la sala (donde = sala)
start_enc:      ld (APIN),hl
                ld (APIP),a
                ld (APIA),de
                ld a,WIO_ROOM
                ld (APIW),a
                xor a
                ld (APIBIG),a
                ld (APIFL),a
                ld (VACNT),a
                jp start_slot_new

; runExitScript / runEntryScript
run_exit:       xor a
                ld (VACNT),a
                ld hl,(VAR_EXIT_SCRIPT)
                ld a,h
                or l
                jr z,rx_1
                xor a
                call run_script
rx_1:           ld a,(CURRD+3)
                or a
                jr z,rx_2
                ld de,(CURRD+4)
                ld hl,SCRIPT_NUM_EXCD
                call start_enc
rx_2:           xor a
                ld (VACNT),a
                ld hl,(VAR_EXIT_SCRIPT2)
                ld a,h
                or l
                ret z
                xor a
                jp run_script
run_entry:      xor a
                ld (VACNT),a
                ld hl,(VAR_ENTRY_SCRIPT)
                ld a,h
                or l
                jr z,rn1
                xor a
                call run_script
rn1:            ld a,(CURRD+0)
                or a
                jr z,rn2
                ld de,(CURRD+1)
                ld hl,SCRIPT_NUM_ENCD
                call start_enc
rn2:            xor a
                ld (VACNT),a
                ld hl,(VAR_ENTRY_SCRIPT2)
                ld a,h
                or l
                ret z
                xor a
                jp run_script

; killScriptsAndResources: las ranuras de sala, locales y FLObject mueren (conservan su numero, como en el modelo) y los nombres nuevos de objetos
; de la sala o sin dueno se borran
kill_scripts:   ld ix,SLOTS
                ld b,NSLOT
                ld de,16
ks_l:           ld a,(ix+SL_WHERE)
                cp WIO_ROOM
                jr z,ks_k
                cp WIO_LOCAL
                jr z,ks_k
                cp WIO_FLOBJECT
                jr nz,ks_n
ks_k:           xor a
                ld (ix+SL_CUTOV),a
                ld (ix+SL_STAT),a
ks_n:           add ix,de
                djnz ks_l
                ld hl,NEWNAMES
                ld e,NNAMES
ks_nm:          ld c,(hl)
                inc hl
                ld b,(hl)
                ld a,b
                or c
                jr z,ks_nn
                push hl
                push de
                ld h,b
                ld l,c
                call chk_obj_hl
                ld de,OBJOWN
                add hl,de
                ld a,(hl)
                pop de
                pop hl
                or a
                jr z,ks_c
                cp OWNER_ROOM
                jr nz,ks_nn
ks_c:           xor a
                ld (hl),a
                dec hl
                ld (hl),a
                inc hl
ks_nn:          inc hl
                dec e
                jr nz,ks_nm
                ret

; startScene (version 3): C = sala (byte)
ovc_start:      ld a,c
                ld b,a
                cp $80
                jr c,ss_a
                and $7F                 ; _resourceMapper
                ld l,a
                ld h,0
                ld de,RESMAP
                add hl,de
                ld a,(hl)
                or a
                jr z,ss_a
                ld b,a
ss_a:           push bc                 ; B = recurso, C = sala
                ld a,b
                or a
                jr z,ss_ok
                cp 100
                jr nc,ss_bad
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,COLD_ROOMDIR+6
                add hl,de
                ld de,ODTMP
                ld bc,2
                call cold_rd
                ld hl,(ODTMP)
                ld a,h
                or l
                jr nz,ss_ok
ss_bad:         ld a,E_BADROOM
                jp vm_err
ss_ok:          ld hl,OVB_STOPTALK
                call call_ovb
                ld a,(CUR)              ; si el script en curso es de sala, local o de FLObject, se abandona
                inc a
                jr z,ss_nc
                ld ix,(CURSLOT)
                ld a,(ix+SL_WHERE)
                cp WIO_ROOM
                jr z,ss_kc
                cp WIO_LOCAL
                jr z,ss_kc
                cp WIO_FLOBJECT
                jr nz,ss_nc
ss_kc:          ld a,$FF
                ld (CUR),a
ss_nc:          call run_exit
                call kill_scripts
                ld a,1                  ; se ocultan los actores 1..NACT-1
ss_h:           push af
                call actor_ix
                ld hl,OVB_HIDE
                call call_ovb
                pop af
                inc a
                cp NACT
                jr c,ss_h
                pop bc
                push bc
                ld a,c
                ld (CURROOM),a
                ld l,a
                ld h,0
                ld (VAR_ROOM),hl
                ld l,b
                ld (VAR_ROOM_RESOURCE),hl
                ld c,b
                ld b,1
                call ovc_room
                pop bc
                ld a,b
                or a
                ret z                   ; sala 0: sin ENCD ni EXCD, sin camara, sin evento
                ld l,c
                ld h,0
                ld (EVARGS),hl
                ld a,EV_ROOM_LOAD
                call ev_emit
                ld hl,160
                ld (VAR_CAMERA_MIN_X),hl
                ld (CAMCUR),hl
                ld (CAMDEST),hl
                ld hl,(CURRD+6)
                ld de,-160
                add hl,de
                ld (VAR_CAMERA_MAX_X),hl
                ld a,CAM_NORMAL
                ld (CAMMODE),a
                ld hl,OVB_SHOWACT
                call call_ovb
                xor a
                ld (EGOPOS),a
                jp run_entry

; loadRoom: B1
b_loadRoom:     call rd_vb1
                ld (SPTR),de
                ld a,b
                or a
                jp nz,err_range         ; la sala tiene que ser un byte (el modelo igual)
                ld a,(CURROOM)
                cp c
                ret z
                jp ovc_start

; loadRoomWithEgo: W1 B2 w w (objeto, sala, x, y de la caminata despues de entrar)
; pila durante startScene: ego, direccion antigua, y, x, objeto
b_loadRoomWithEgo:
                call rd_vw1
                push bc                 ; objeto
                call rd_vb2
                ld a,b
                or a
                jp nz,err_range
                push bc                 ; sala
                ld a,(de)
                inc de
                ld c,a
                ld a,(de)
                inc de
                ld b,a
                push bc                 ; x
                ld a,(de)
                inc de
                ld c,a
                ld a,(de)
                inc de
                ld b,a
                push bc                 ; y
                ld (SPTR),de
                ld bc,(VAR_EGO)
                call chk_actor          ; IX = ego
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld (SC+0),hl
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld (SC+2),hl
                ld hl,4
                add hl,sp
                ld c,(hl)               ; sala
                ld hl,OVB_PUTACT
                call call_ovb           ; putActor(ego, ego.x, ego.y, sala)
                pop hl                  ; y
                pop de                  ; x
                pop bc                  ; sala
                pop bc                  ; objeto
                push bc
                push de
                push hl
                ld l,(ix+A_FACING)
                ld h,(ix+A_FACING+1)
                push hl                 ; direccion antigua
                xor a
                ld (EGOPOS),a
                ld (VAR_WALKTO_OBJ),bc
                call actor_num
                ld l,a
                ld h,0
                push hl                 ; ego
                ld c,(ix+A_ROOM)
                call ovc_start
                ld hl,0
                ld (VAR_WALKTO_OBJ),hl
                pop hl                  ; ego
                ld a,l
                call actor_ix           ; IX = ego
                ld hl,6
                add hl,sp
                ld c,(hl)
                inc hl
                ld b,(hl)               ; objeto (la pila: direccion antigua, y, x, objeto)
                call wio
                dec a
                jp nz,err_badobj        ; no esta en la sala
                ld a,(EGOPOS)
                or a
                jr nz,lw_pos
                call obj_index          ; getObjectXYPos: x e y de acercamiento y direccion del actor
                ld de,OB_WX
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,(hl)               ; direccion (0-7)
                ld (SC+4),a
                ld (SC+0),de
                ld (SC+2),bc
                ld a,(CURROOM)
                ld c,a
                ld hl,OVB_PUTACT
                call call_ovb
                ld hl,0
                add hl,sp
                ld e,(hl)
                inc hl
                ld d,(hl)               ; direccion antigua
                ld l,(ix+A_FACING)
                ld h,(ix+A_FACING+1)
                or a
                sbc hl,de
                jr nz,lw_pos
                ld a,(SC+4)
                and 3
                add a,a
                ld e,a
                ld d,0
                ld hl,lw_dirs
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ix+A_FACING),e
                ld (ix+A_FACING+1),d
lw_pos:         ld (ix+A_MOVING),0
                call actor_num          ; (fase 6: setCameraFollows no conserva IX y despues viene startWalkActor)
                push af
                ld c,(ix+A_X)
                ld b,(ix+A_X+1)
                ld (CAMCUR),bc
                ld (CAMDEST),bc
                ld hl,OVB_FOLLOW
                call call_ovb           ; setCameraFollows(ego)
                pop af
                call actor_ix           ; IX = ego
                pop hl                  ; direccion antigua
                pop hl                  ; y
                pop de                  ; x
                pop bc                  ; objeto
                ld a,d
                and e
                inc a
                ret z                   ; x = -1: sin caminata
                ld (WKX),de
                ld (WKY),hl
                ld hl,$FFFF
                ld (WKDIR),hl
                ld hl,OVD_STARTWALK
                jp call_ovd             ; startWalkActor(ego, x, y, -1)
lw_dirs:        defw 90,270,0,180       ; (oldDirToNewDir(d & 3) + 180) % 360
