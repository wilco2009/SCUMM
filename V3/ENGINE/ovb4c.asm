; =====================================================================
;  ovb4c.asm - fase 4b-2 en el overlay B (se incluye desde ovlb.asm tras ovb4b.asm): print y printEgo (decodeParseString), el mensaje
;  (convertMessageToString, actorTalk, displayDialog con handleNextCharsetCode) y stopTalk, que esta en ovb4.asm.
;  Semantica: ScummVM tal como la transcribe V3/TOOLS/vmgame3.py (convert_message_to_string, actor_talk, display_dialog, print_string) y
;  vmmodel3.py (decode_parse_string); los limites del Z80 son los del modelo (vmcommon3.py: MSG_MAX, MSG_DEPTH).
;  displayDialog corre cada fotograma: el residente (talk_frame, vm_core.asm) solo salta aqui (OVB_DD) cuando hay mensaje y no queda espera.
;  Fase 5: el nombre de un objeto (FF 6 con un objeto que no es actor ni tiene nombre nuevo) sale de su OBCD (ODIR; inventario o sala).
; =====================================================================

; temporales (SC+n; no sobreviven a un script, y aqui no se arranca ninguno)
PR_WHO          equ SC+0        ; palabra: actor_to_print_str_for
PR_SLOT         equ SC+2        ; ranura de texto 0-3
PR_STR          equ SC+3        ; palabra: inicio de la cadena en la ventana de datos
CM_LEN          equ SC+6        ; palabra: bytes del contenido convertido hasta ahora
CM_MODE         equ SC+8        ; 0: se guarda en MSGBUF; 1: solo se suman (suma y longitud, para el texto suelto de la ranura 1)
CM_REM          equ SC+9        ; palabra: bytes que quedan en la fuente que se lee ($FFFF: hasta su 0 final)
CM_DEP          equ SC+11       ; nivel de anidamiento
CM_SUM          equ SC+12       ; palabra: suma de los bytes (modo 1)
DD_SUM          equ SC+14       ; displayDialog: suma de lo escrito y su longitud (solo vive dentro de displayDialog)
DD_LEN          equ SC+16

; ---------------------------------------------------------------- print / printEgo (decodeParseString)
b_print:        call rd_vb1             ; actor
                jr pm_go
b_printEgo:     ld bc,(VAR_EGO)
                ld b,0
pm_go:          ld (PR_WHO),bc
                ld a,b
                or a
                jr nz,pm_s0
                ld a,c
                cp 252
                jr c,pm_s0
                cp 255
                jr nc,pm_s0
                cpl                     ; 252 -> 3, 253 -> 2, 254 -> 1
                jr pm_sl
pm_s0:          xor a
pm_sl:          ld (PR_SLOT),a
                push de
                call slot_def           ; WRK = los valores por omision de la ranura
                ld de,WRK
                ld bc,11
                ldir
                pop de
pm_l:           ld a,(de)
                inc de
                ld (OPC),a
                cp $FF
                jr z,pm_ff
                and $0F
                jr z,pm_k0
                cp 1
                jr z,pm_k1
                cp 2
                jr z,pm_k2
                cp 4
                jr z,pm_k4
                cp 6
                jr z,pm_k6
                cp 7
                jr z,pm_k7
                cp 15
                jr z,pm_k15
                jp err_badsub
pm_k0:          call rd_vw1             ; xpos, ypos; overhead = 0
                ld (WRK+W_X),bc
                call rd_vw2
                ld (WRK+W_Y),bc
                xor a
                ld (WRK+W_OVH),a
                jr pm_l
pm_k1:          call rd_vb1
                ld a,c
                ld (WRK+W_C),a
                jr pm_l
pm_k2:          call rd_vw1
                ld (WRK+W_R),bc
                jr pm_l
pm_k4:          ld a,1                  ; center = 1, overhead = 0
                ld (WRK+W_CEN),a
                xor a
                ld (WRK+W_OVH),a
                jr pm_l
pm_k6:          call rd_vw1
                ld (WRK+W_H),bc
                jr pm_l
pm_k7:          ld a,1
                ld (WRK+W_OVH),a
                jr pm_l
pm_ff:          ld (SPTR),de            ; por omision = la copia de trabajo
                call slot_def
                ex de,hl
                ld hl,WRK
                ld bc,11
                ldir
                ret
pm_k15:         ld (PR_STR),de          ; la cadena (con su 0 final y sus codigos $FF): el puntero acaba tras ella (resStrLen)
                call scan_len
                ld (SPTR),de
                ld hl,(PR_STR)
                ld a,(PR_SLOT)
                or a
                jr z,pm_talk
                dec a
                jr nz,pm_dflt           ; ranuras 2 y 3: no hacen nada
                call print_free         ; ranura 1: texto suelto
                jr pm_dflt
pm_talk:        call actor_talk         ; ranura 0: voz del actor
pm_dflt:        call slot_def           ; por omision: xpos, ypos, height y color (no right, center ni overhead)
                ex de,hl
                ld hl,WRK
                ld bc,4
                ldir
                inc hl                  ; (se salta right)
                inc hl
                inc de
                inc de
                ld bc,3
                ldir
                ret

slot_def:       ld a,(PR_SLOT)          ; HL = STRSL + 11 * ranura (destruye A y DE)
                ld hl,STRSL
                ld de,11
sd_l:           or a
                ret z
                add hl,de
                dec a
                jr sd_l

; ranura 1 de print: EV_TEXT [1, xpos, ypos, color, center | overhead * 2, str_value(texto convertido)] sin tocar el bufer del mensaje.
; HL = la cadena del script
print_free:
                IF PROGRAM
                ld a,2                  ; fase 9: el programa pinta el texto suelto (txtlayer.asm): se convierte a UIBUF
                ELSE
                ld a,1
                ENDIF
                call convert_all
                ld hl,1
                ld (EVARGS),hl
                ld hl,(WRK+W_X)
                ld (EVARGS+2),hl
                ld hl,(WRK+W_Y)
                ld (EVARGS+4),hl
                ld a,(WRK+W_C)
                ld l,a
                ld h,0
                ld (EVARGS+6),hl
                ld a,(WRK+W_OVH)
                add a,a
                ld hl,WRK+W_CEN
                or (hl)
                ld l,a
                ld h,0
                ld (EVARGS+8),hl
                IF PROGRAM
                ld hl,(CM_LEN)          ; (programa) la longitud del texto de UIBUF
                ELSE
                ld hl,(CM_SUM)          ; valor = suma + longitud * 257
                ld de,(CM_LEN)
                add hl,de
                ld a,h
                add a,e
                ld h,a
                ENDIF
                ld (EVARGS+10),hl
                ld a,EV_TEXT
                jp ev_emit

; ---------------------------------------------------------------- convertMessageToString
; convert_all: HL = fuente (terminada en 0), A = modo (0: MSGBUF, 1: solo suma). Modo 0 deja el 0 final y MSGEND
convert_all:    ld (CM_MODE),a
                ld de,0
                ld (CM_LEN),de
                ld (CM_SUM),de
                xor a
                ld (CM_DEP),a
                dec de
                ld (CM_REM),de          ; $FFFF
                call cm_run
                ld a,(CM_MODE)
                or a
                ret nz
                ld hl,(CM_LEN)
                ld de,MSGBUF
                add hl,de
                ld (hl),0
                ld (MSGEND),hl
                ret

; emit_a: A = byte de la salida (conserva todo salvo A y las banderas). CM_LEN >= MSG_MAX: E_RANGE
emit_a:         push hl
                push de
                ld e,a
                ld hl,(CM_LEN)
                inc hl
                ld (CM_LEN),hl
                ld a,h
                cp MSG_MAX/256
                jr c,ea_ok
                jp nz,err_range
                ld a,l
                cp MSG_MAX & 255
                jp nc,err_range
ea_ok:          ld a,(CM_MODE)
                or a
                jr nz,ea_m1
                ld a,e
                ld de,MSGBUF-1
                add hl,de
                ld (hl),a
                pop de
                pop hl
                ret
ea_m1:          cp 2
                jr nz,ea_sum
                ld a,h                  ; modo 2 (fase 7): a UIBUF (48 bytes; el resto se cuenta pero no se guarda)
                or a
                jr nz,ea_ux
                ld a,l
                cp 49
                jr nc,ea_ux
                ld a,e
                ld de,UIBUF-1
                add hl,de
                ld (hl),a
ea_ux:          pop de
                pop hl
                ret
ea_sum:         ld hl,(CM_SUM)
                ld d,0
                add hl,de
                ld (CM_SUM),hl
                pop de
                pop hl
                ret

; rd_src: HL = fuente -> A = su byte (0 si ya no quedan: CM_REM) y HL + 1
rd_src:         push de
                ld de,(CM_REM)
                ld a,d
                or e
                jr z,rs_end
                dec de
                ld (CM_REM),de
                ld a,(hl)
                inc hl
                pop de
                ret
rs_end:         pop de
                xor a
                ret

; cm_run: HL = fuente; escribe en la salida hasta su 0 final (o su limite)
cm_run:         call rd_src
                or a
                ret z
                cp $FF
                jr z,cm_esc
                cp $40
                jr z,cm_run             ; '@' no se imprime
                call emit_a
                jr cm_run
cm_esc:         call rd_src
                ld b,a
                or a
                jr z,cm_run             ; codigo invalido: se salta solo el $FF y el codigo
                cp 4
                jr c,cm_two             ; 1, 2, 3
                cp 8
                jr z,cm_two
                jr nc,cm_hi
                call rd_src             ; 4-7: la variable (palabra)
                ld e,a
                call rd_src
                ld d,a
                bit 5,d
                jp nz,err_range         ; 0x2000: leeria el indice del script
                ld a,b
                push af
                push hl
                ex de,hl
                call var_rd             ; BC = valor (conserva DE)
                pop hl
                pop af
                cp 4
                jr nz,cm_n5
                call emit_dec
                jr cm_run
cm_n5:          ld d,a                  ; codigo 5, 6 o 7: con 0 no hace nada
                ld a,b
                or c
                jr z,cm_run
                ld a,d
                cp 5
                jp z,cm_verb
                cp 6
                jp z,cm_name
                jp cm_str
cm_two:         ld a,$FF                ; 1, 2, 3, 8: $FF y el codigo
                call emit_a
                ld a,b
                call emit_a
                jr cm_run
cm_hi:          cp 15                   ; 9, 10, 12, 13, 14: $FF, el codigo y dos bytes; el resto, nada
                jr nc,cm_run
                cp 11
                jr z,cm_run
                ld a,$FF
                call emit_a
                ld a,b
                call emit_a
                call rd_src
                call emit_a
                call rd_src
                call emit_a
                jr cm_run

cm_verb:        ld a,b                  ; BC = verbo: el primero con ese id que no sea imagen ni guardado (el id es de un byte)
                or a
                jp nz,cm_run
                push hl
                ld ix,VERBS+VSZ
                ld de,VSZ
                ld b,NVERB-1
cv_l:           ld a,(ix+V_ID)
                cp c
                jr nz,cv_n
                ld a,(ix+V_SAVE)
                or a
                jr nz,cv_n
                bit 1,(ix+V_FLG)
                jr nz,cv_n
                ld a,(ix+V_NPG)         ; su nombre: pagina y direccion del texto en el script
                or a
                jr z,cv_e
                ld e,a
                ld l,(ix+V_NAD)
                ld h,(ix+V_NAD+1)
                ld bc,$FFFF
                call cm_nest
                jr cv_e
cv_n:           add ix,de
                djnz cv_l
cv_e:           pop hl
                jp cm_run

cm_name:        bit 7,b                 ; BC = objeto o actor; negativo (< NACT con signo): deref_actor da error
                jp nz,err_badactor
                ld a,b
                or a
                jr nz,cn_obj
                ld a,c
                cp NACT
                jr nc,cn_obj
                push hl                 ; un actor: ACTNAMES + 3 * numero
                ld l,a
                ld h,0
                add hl,hl
                add hl,bc
                ld bc,ACTNAMES
                add hl,bc
                jr cn_go
cn_obj:         push hl                 ; un objeto con nombre nuevo (setObjectName): NEWNAMES; si no, el de su OBCD
                ld hl,NEWNAMES
                ld d,NNAMES
cn_l:           ld a,(hl)
                inc hl
                cp c
                jr nz,cn_n
                ld a,(hl)
                cp b
                jr z,cn_f
cn_n:           inc hl
                dec d
                jr nz,cn_l
                ld h,b                  ; sin nombre nuevo: el del OBCD (inventario o sala; obcd_of del modelo)
                ld l,c
                ld de,NOBJ
                or a
                sbc hl,de
                jr nc,cn_e
                ld a,b
                or c
                jr z,cn_e
                call inv_find
                jr z,cn_have
                ld hl,OBJOWN
                add hl,bc
                ld a,(hl)
                cp OWNER_ROOM
                jr nz,cn_e
                call obj_index
                jr nz,cn_e
cn_have:        call odir               ; A = pagina de su OBCD (0: no tiene) y HL = direccion
                or a
                jr z,cn_e
                push af
                call map_page           ; (conserva HL y DE)
                push hl
                ld de,16
                add hl,de
                ld e,(hl)               ; el desplazamiento del nombre desde el principio del OBCD
                ld d,0
                pop hl
                add hl,de
                pop af
                ld e,a
                ld bc,$FFFF
                call cm_nest            ; (devuelve la ventana a la pagina del script en curso)
                jr cn_e
cn_f:           ld a,NNAMES
                sub d
                ld e,a
                add a,a
                add a,e
                ld e,a
                ld d,0
                ld hl,NEWNAMES+NNAMES*2
                add hl,de
cn_go:          ld a,(hl)               ; pagina (0: sin nombre) y direccion
                or a
                jr z,cn_e
                ld e,a
                inc hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld bc,$FFFF
                call cm_nest
cn_e:           pop hl
                jp cm_run

cm_str:         ld a,b                  ; BC = cadena: STRHEAP, con su longitud como limite
                or a
                jp nz,cm_run
                ld a,c
                cp NSTR
                jp nc,cm_run
                push hl
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld b,(hl)
                ld a,b
                or a
                jr z,cs_e
                ld a,e
                call str_ptr            ; HL = su direccion (destruye A y DE)
                ld c,b
                ld b,0
                ld e,0                  ; (sin cambiar de pagina)
                call cm_nest
cs_e:           pop hl
                jp cm_run

; cm_nest: convierte una fuente anidada. HL = fuente, BC = bytes que se pueden leer, E = pagina de datos que hay que poner en la ventana
; (0: la que hay). Al volver, la ventana vuelve a tener la pagina del script en curso
cm_nest:        ld a,(CM_DEP)
                cp MSG_DEPTH
                jp nc,err_range
                inc a
                ld (CM_DEP),a
                push de
                ld a,(CM_REM)
                push af
                ld a,(CM_REM+1)
                push af
                ld (CM_REM),bc
                ld a,e
                or a
                jr z,cnst_r
                call map_page           ; (conserva HL y DE)
cnst_r:         call cm_run
                pop af
                ld (CM_REM+1),a
                pop af
                ld (CM_REM),a
                ld hl,CM_DEP
                dec (hl)
                pop de
                ld a,e
                or a
                ret z
                ld ix,(CURSLOT)         ; la ventana vuelve a la pagina del script en curso (por la cache, no por el numero fisico)
                ld a,(ix+SL_PAGE)
                jp map_page

; emit_dec: BC = valor con signo de 16 bits -> sus cifras decimales (con el '-'); conserva HL
emit_dec:       push hl
                bit 7,b
                jr z,ed_p
                ld a,'-'
                call emit_a
                xor a
                sub c
                ld c,a
                sbc a,a
                sub b
                ld b,a
ed_p:           ld h,b
                ld l,c
                ld d,0
                ld bc,-10000
                call ed_d
                ld bc,-1000
                call ed_d
                ld bc,-100
                call ed_d
                ld bc,-10
                call ed_d
                ld a,l
                add a,'0'
                call emit_a
                pop hl
                ret
ed_d:           ld e,'0'-1              ; una cifra: HL = valor, BC = -divisor, D = ya se escribio alguna
ed_dl:          inc e
                add hl,bc
                jr c,ed_dl
                or a
                sbc hl,bc
                ld a,e
                cp '0'
                jr nz,ed_pr
                ld a,d
                or a
                ret z
                ld a,'0'
                jp emit_a
ed_pr:          ld d,1
                jp emit_a

; ---------------------------------------------------------------- actorTalk
; actor_talk: HL = el mensaje del script, PR_WHO = actor. Convierte al bufer (se pisa aunque el mensaje se descarte)
actor_talk:     xor a
                call convert_all
                ld bc,(PR_WHO)
                ld a,b
                or a
                jr nz,at_act
                ld a,c
                cp $FF
                jr nz,at_act
                ld a,(KEEPTXT)          ; sin actor: mensaje del sistema
                or a
                call z,stop_talk
                ld hl,$FF
                ld (VAR_TALK_ACTOR),hl
                jr at_col
at_act:         call chk_actor          ; derefActor: E_BADACTOR
                call in_room
                ret nz                  ; el actor no esta en la sala: el mensaje se pierde
                ld a,(KEEPTXT)
                or a
                jr nz,at_set
                push ix
                call stop_talk
                pop ix
at_set:         call actor_num
                ld l,a
                ld h,0
                ld (VAR_TALK_ACTOR),hl
                ld c,(ix+A_TSTART)
                call run_talk_script
                ld a,1
                ld (USETALK),a
at_col:         ld hl,(VAR_TALK_ACTOR)  ; charset_color: la del actor que habla, o la de la ranura 0 si no hay
                ld a,h
                or a
                jr nz,at_c0
                ld a,l
                cp $80
                jr nc,at_c0
                ld b,h
                ld c,l
                call chk_actor
                ld a,(ix+A_TALKC)
                jr at_cs
at_c0:          ld a,(WRK+W_C)
at_cs:          ld (CHARCOL),a
                ld hl,MSGBUF
                ld (MSGPTR),hl
                ld hl,0
                ld (TALKDLY),hl
                ld a,$FF
                ld (HAVEMSG),a
                ld l,a
                ld (VAR_HAVE_MSG),hl
                ; sigue en displayDialog

; ---------------------------------------------------------------- displayDialog (cada fotograma, desde talk_frame)
ovb_dd:
display_dialog: ld a,(HAVEMSG)
                or a
                ret z
                ld hl,(TALKDLY)
                ld a,h
                or l
                ret nz
                ld a,(HAVEMSG)
                cp 1
                jp z,stop_talk
                call talker_ix
                jr c,dg_noact
                ld c,(ix+A_TSTART)
                call run_talk_script
                ld a,1
                ld (USETALK),a
dg_noact:       ld hl,60
                ld (TALKDLY),hl
                ld a,(KEEPTXT)
                or a
                jr nz,dg_keep
                call restore_bg
                ld hl,0
                ld (MSGCNT),hl
dg_keep:        ld hl,0
                ld (DD_SUM),hl
                ld (DD_LEN),hl
dg_loop:        call dg_rd
                cp $FF
                jr z,dg_esc
                cp $FE
                jr z,dg_esc
                or a
                jp z,dg_end
                cp 13
                jr z,dg_nl
                call dg_sum
                ld hl,(MSGCNT)
                inc hl
                ld (MSGCNT),hl
                ld hl,(TALKDLY)         ; talk_delay += VAR_CHARINC (16 bits)
                ld de,(VAR_CHARINC)
                add hl,de
                ld (TALKDLY),hl
                jr dg_loop
dg_nl:          call dg_sum
                jr dg_loop
dg_esc:         call dg_rd
                cp 1
                jr z,dg_c1
                cp 2
                jr z,dg_c2
                cp 3
                jr z,dg_c3
                cp 8
                jr z,dg_loop
                cp 9
                jr z,dg_c9
                cp 10
                jr z,dg_c10
                cp 12
                jr z,dg_c12
                cp 13
                jr z,dg_c12
                cp 14
                jr z,dg_c14
                jp err_range
dg_c1:          ld hl,320               ; _msgCount = _screenWidth; el codigo se escribe como un salto de linea
                ld (MSGCNT),hl
                ld a,13
                call dg_sum
                jr dg_loop
dg_c2:          xor a                   ; seguir escribiendo con el siguiente mensaje (keepText)
                ld (HAVEMSG),a
                inc a
                ld (KEEPTXT),a
                jr dg_done
dg_c3:          ld a,$FF                ; esperar
                ld (HAVEMSG),a
                xor a
                ld (KEEPTXT),a
                ld h,a
                ld l,a
                ld (MSGCNT),hl
                jr dg_done
dg_c9:          call dg_rd              ; startAnimActor(talking, palabra)
                ld c,a
                call dg_rd
                ld b,a
                push bc
                call talker_ix
                pop bc                  ; (actor_ix destruye BC)
                jp c,dg_loop
                call start_anim
                jp dg_loop
dg_c10:         ld de,14
                jr dg_skip
dg_c12:         ld de,2
                jr dg_skip
dg_c14:         ld de,3
dg_skip:        ld hl,(MSGPTR)
                add hl,de
                ld (MSGPTR),hl
                jp dg_loop
dg_end:         ld a,1                  ; fin del mensaje
                ld (HAVEMSG),a
                xor a
                ld (KEEPTXT),a
                ld h,a
                ld l,a
                ld (MSGCNT),hl
dg_done:        ld hl,0                 ; EV_TEXT [0, actor que habla, color, 0, longitud, valor]
                ld (EVARGS),hl
                ld (EVARGS+6),hl
                ld hl,(VAR_TALK_ACTOR)
                ld (EVARGS+2),hl
                ld a,(CHARCOL)
                ld l,a
                ld h,0
                ld (EVARGS+4),hl
                ld hl,(DD_SUM)          ; valor = suma + longitud * 257
                ld de,(DD_LEN)
                ld (EVARGS+8),de
                add hl,de
                ld a,h
                add a,e
                ld h,a
                ld (EVARGS+10),hl
                ld a,EV_TEXT
                jp ev_emit

dg_rd:          ld hl,(MSGPTR)          ; A = el siguiente byte del bufer (0 mas alla de su 0 final); MSGPTR + 1
                ld de,(MSGEND)
                inc hl
                ld (MSGPTR),hl
                dec hl
                ex de,hl
                or a
                sbc hl,de
                ld a,0
                ret c
                ld a,(de)
                ret

dg_sum:         ld hl,(DD_SUM)          ; A = un caracter escrito: suma y longitud (y, fase 7, el caracter va a PGBUF, 96 como mucho, para que el programa lo pinte)
                ld e,a
                ld d,0
                add hl,de
                ld (DD_SUM),hl
                ld hl,(DD_LEN)
                ld a,h
                or a
                jr nz,ds_n
                ld a,l
                cp 96
                jr nc,ds_n
                push hl
                ld bc,PGBUF
                add hl,bc
                ld (hl),e
                pop hl
ds_n:           inc hl
                ld (DD_LEN),hl
                ret

talker_ix:      ld hl,(VAR_TALK_ACTOR)  ; getTalkingActor + derefActorSafe: IX = el actor (0..NACT-1), o carry si no hay
                ld a,h
                or a
                jr nz,tk_none
                ld a,l
                cp NACT
                jr nc,tk_none
                call actor_ix
                or a
                ret
tk_none:        scf
                ret
