; =====================================================================
;  agic.asm - overlay C: restart.game, status (inventario) y show.obj. Pagina PG_OVC, en el bloque 1 solo mientras se ejecuta (call_c). El texto lo dibuja la ventana
;  de mensaje del overlay B (el nucleo pone pr_raw = 3 y el texto, en TMPM).
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_restart            ; OVC_RESTART
                jp t_invtxt             ; OVC_INVTXT
                jp t_objdesc            ; OVC_OBJDESC
                jp t_echo               ; OVC_ECHO
                jp t_cancel             ; OVC_CANCEL
                jp t_curchar            ; OVC_CURSOR

TXT             equ TMPM

; El estado del juego vuelve al del arranque (lo de init que no son ficheros ni los punteros de pruebas); la logica en curso se sale sola (exitall)
t_restart:      call h_stop_sound
                ld hl,LGSLOT
                ld de,LGSLOT+1
                ld bc,255
                ld (hl),$FF
                ldir
                ld hl,slot_lg
                ld de,slot_lg+1
                ld bc,NSLOTS-1
                ld (hl),$FF
                ldir
                ld hl,VARS
                ld de,VARS+1
                ld bc,511
                ld (hl),0
                ldir
                ld a,255
                ld (VARS+8),a
                ld a,2
                ld (VARS+10),a
                ld a,3
                ld (VARS+15),a
                ld a,15
                ld (VARS+22),a
                ld a,41
                ld (VARS+24),a
                ld a,3
                ld (VARS+26),a
                ld a,1
                ld (FLAGS+9),a
                ld (FLAGS+5),a
                ld (FLAGS+11),a
                ld (pctl),a
                ld (accin),a
                ld hl,SNDP
                ld b,8
rs_s:           ld (hl),$FF
                inc hl
                inc hl
                inc hl
                djnz rs_s
                ld hl,KEYMAP
                ld de,KEYMAP+1
                ld bc,511
                ld (hl),0
                ldir
                ld hl,ARGS
                ld de,ARGS+1
                ld bc,CLR_END-ARGS-1
                ld (hl),0
                ldir
                ld hl,OBJ
                ld de,OBJ+1
                ld bc,NOBJ*32-1
                ld (hl),0
                ldir
                ld a,36
                ld (horizon),a
                xor a
                ld (picvalid),a
                ld (lastpic),a
                ld (mg_n),a
                ld (blkf),a
                ld (nr_pend),a
                ld (keyn),a
                ld hl,nm_inv
                ld de,INV
                ld bc,256
                call load_aux
                jp video_init

; TXT = "You are carrying:" y los objetos que lleva el ego (uno por linea; "Nothing" si no lleva ninguno) y "Press any key to return to the game."
t_invtxt:       ld a,PG_INV
                call map_page
                ld hl,TXT
                ld (oc_dp),hl
                ld de,s_have
                call oc_cp
                ld a,(LWIN)             ; numero de objetos; luego sus nombres, uno tras otro
                ld (oc_n),a
                ld hl,LWIN+1
                ld (oc_sp),hl
                xor a
                ld (oc_i),a
                ld (oc_any),a
                ld a,(oc_n)
                or a
                jr z,iv_e
iv_l:           ld a,(oc_i)
                ld e,a
                ld d,INV>>8
                ld a,(de)
                cp 255
                ld hl,(oc_sp)
                jr nz,iv_skip
                ld de,(oc_dp)
                push hl
                ld hl,TXT+190
                or a
                sbc hl,de
                pop hl
                jr c,iv_skip            ; no cabe mas
                ld a,1
                ld (oc_any),a
                ld de,(oc_dp)
iv_c:           ld a,(hl)
                inc hl
                or a
                jr z,iv_cd
                ld (de),a
                inc de
                jr iv_c
iv_cd:          ld a,10
                ld (de),a
                inc de
                ld (oc_dp),de
                jr iv_n
iv_skip:        ld a,(hl)
                inc hl
                or a
                jr nz,iv_skip
iv_n:           ld (oc_sp),hl
                ld hl,oc_i
                inc (hl)
                ld a,(hl)
                ld hl,oc_n
                cp (hl)
                jr c,iv_l
iv_e:           call unmap_win
                ld a,(oc_any)
                or a
                jr nz,iv_f
                ld de,s_none
                call oc_cp
iv_f:           ld de,s_foot
                call oc_cp
                ld hl,(oc_dp)
                ld (hl),0
                ret

; (oc_dp) += la cadena DE sin su 0
oc_cp:          ld hl,(oc_dp)
oc_c2:          ld a,(de)
                or a
                jr z,oc_cd
                ld (hl),a
                inc hl
                inc de
                jr oc_c2
oc_cd:          ld (oc_dp),hl
                ret

; TXT = la descripcion de la vista ARGS[0] (en el recurso, a partir del desplazamiento de los bytes 3-4); oc_res = 1 si la tiene
t_objdesc:      xor a
                ld (oc_res),a
                ld a,(ARGS)
                ld hl,ov_nm+9
                call mk_dig
                ld hl,ov_nm
                call f_open
                cp $FF
                ret z
                ld (oc_h),a
                ld hl,MSGBUF
                ld bc,8
                call f_read_n
                ld a,(MSGBUF+5)
                ld l,a
                ld a,(MSGBUF+6)
                ld h,a
                or l
                jr z,od_c
                inc hl
                inc hl                  ; el fichero lleva delante el tamano (2 bytes)
                ld a,(oc_h)
                call f_seek
                ld a,(oc_h)
                ld hl,TXT
                ld bc,100
                call f_read_n
                xor a
                ld (TXT+99),a
                ld a,(TXT)
                or a
                jr z,od_c
                ld a,1
                ld (oc_res),a
od_c:           ld a,(oc_h)
                jp f_close

s_have:         defb "You are carrying:",10,10,0
s_none:         defb "Nothing",10,0
s_foot:         defb 10,"Press any key to return",10,"to the game.",0
ov_nm:          defb "VIEW/VIEW000.GFX",0
oc_dp:          defw 0
oc_sp:          defw 0
oc_n:           defb 0
oc_i:           defb 0
oc_any:         defb 0
oc_h:           defb 0

; echo.line: la ultima orden (LASTLN, la guarda ev_text) vuelve a la linea de entrada; cancel.line la borra; set.cursor.char: el caracter del cursor (solo en modo real)
t_echo:         ld hl,LASTLN
                ld de,INBUF
                ld bc,41
                ldir
                ld hl,INBUF
                ld b,0
ec_l:           ld a,(hl)
                or a
                jr z,ec_d
                inc hl
                inc b
                jr ec_l
ec_d:           ld a,b
                ld (il_n),a
                ld a,1
                ld (kb_dirty),a
                ret
t_cancel:       xor a
                ld (il_n),a
                ld (INBUF),a
                inc a
                ld (kb_dirty),a
                ret
t_curchar:      ld a,(ARGS)
                ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,250
                call build_str
                ld a,(TXT)
                or a
                jr nz,cc_s
                ld a,' '
cc_s:           ld (curchar),a
                ld a,1
                ld (kb_dirty),a
                ret
