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
                jp t_objpic             ; OVC_OBJPIC
                jp t_textscr            ; OVC_TEXTSCR
                jp t_distance           ; OVC_DIST
                jp t_animate            ; OVC_ANIM
                jp t_getnum             ; OVC_GETNUM
                jp t_parse              ; OVC_PARSE
                jp t_draw               ; OVC_DRAW

TXT             equ TMPM

; El estado del juego vuelve al del arranque (lo de init que no son ficheros ni los punteros de pruebas); la logica en curso se sale sola (exitall)
t_restart:      ld hl,$ACE1             ; la semilla de los numeros aleatorios, la del arranque: el reinicio repite lo mismo que la primera vez
                ld (lfsr),hl
                xor a
                ld (ovl_on),a
                call h_stop_sound
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
                ld (oc_pw),a
                ld a,(ARGS)
                ld (oc_vw),a
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
                ld bc,240
                call f_read_n
                xor a
                ld (TXT+239),a
                ld a,(TXT)
                or a
                jr z,od_c
                ld a,1
                ld (oc_res),a
                ld a,(oc_h)
                call f_close
                call pic_open           ; el dibujo (bucle 0, celda 0): si cabe, el texto lleva delante filas en blanco para el
                ret z
                ld a,(oc_h)
                call f_close
                ld a,(MSGBUF)
                or a
                ret z
                ld a,(MSGBUF+1)
                cp 201
                ret nc
                ld a,(MSGBUF+2)
                cp 57
                ret nc
                ld a,(MSGBUF+1)
                ld (oc_pw),a
                ld a,(MSGBUF+2)
                add a,7
                rrca
                rrca
                rrca
                and 31
                inc a
                ld (od_k),a
                ld e,a
                ld d,0
                ld hl,TXT+239
                push hl
                add hl,de
                ex de,hl
                pop hl
                ld bc,240
                lddr
                ld a,(od_k)
                ld b,a
                ld hl,TXT
                ld a,10
od_f:           ld (hl),a
                inc hl
                djnz od_f
                ret
od_c:           ld a,(oc_h)
                jp f_close

; abre SPR/Nvvv0.SPR y lee en MSGBUF el registro de la celda 0 (mosaicos, ancho, alto...); Z si no hay fichero
pic_open:       ld a,(oc_vw)
                ld hl,pc_nm+5
                call mk_dig
                ld hl,pc_nm
                call f_open
                cp $FF
                ret z
                ld (oc_h),a
                ld hl,MSGBUF
                ld bc,6
                call f_read_n
                ld hl,(MSGBUF+4)
                inc hl
                inc hl
                ld a,(oc_h)
                call f_seek
                ld a,(oc_h)
                ld hl,MSGBUF
                ld bc,6
                call f_read_n
                ld a,1
                or a
                ret

; el dibujo del objeto en la ventana ya pintada: los mosaicos de la celda sobre el bitmap (fila completa: sus colores; fila con huecos: solo la tinta sobre papel blanco)
t_objpic:       call pic_open
                ret z
                ld a,(MSGBUF+1)
                add a,7
                rrca
                rrca
                rrca
                and 31
                ld b,a
                ld a,(pr_bw)
                sub 2
                sub b
                srl a
                ld b,a
                ld a,(pr_cxl)
                inc a
                add a,b
                ld (op_c),a
                ld a,(pr_top)
                inc a
                add a,a
                add a,a
                add a,a
                ld (op_y),a
                ld a,(MSGBUF)
                ld (op_n),a
op_l:           ld a,(op_n)
                or a
                jr z,op_x
                dec a
                ld (op_n),a
                ld a,(oc_h)
                ld hl,MSGBUF+16
                ld bc,26
                call f_read_n
                ld a,(MSGBUF+17)        ; ty
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(op_y)
                add a,b
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(op_c)
                ld b,a
                ld a,(MSGBUF+16)        ; tx
                add a,b
                ld c,a
                ld b,0
                add hl,bc
                ld (op_o),hl
                ld ix,MSGBUF+18
                ld b,8
op_r:           push bc
                ld a,(ix+16)            ; mascara
                or a
                jr z,op_nx
                ld c,a
                ld a,(ix+8)
                and c
                ld d,a                  ; bitmap
                ld a,(ix+0)             ; color: tinta * 16 + papel
                ld e,a
                ld a,c
                inc a
                ld a,e
                jr z,op_f
                and $F0
                rrca
                rrca
                rrca
                rrca
                or $F0
                jr op_w
op_f:           rrca
                rrca
                rrca
                rrca
op_w:           ld hl,(op_o)
                ld bc,HR_ATT
                add hl,bc
                ld (hl),a
                ld hl,(op_o)
                ld bc,HR_BM
                add hl,bc
                ld (hl),d
op_nx:          ld hl,(op_o)
                ld bc,32
                add hl,bc
                ld (op_o),hl
                inc ix
                pop bc
                djnz op_r
                jp op_l
op_x:           ld a,(oc_h)
                jp f_close

s_have:         defb "You are carrying:",10,10,0
s_none:         defb "Nothing",10,0
s_foot:         defb 10,"Press any key to return",10,"to the game.",0
ov_nm:          defb "VIEW/VIEW000.GFX",0
pc_nm:          defb "SPR/N0000.SPR",0
oc_vw:          defb 0
od_k:           defb 0
op_c:           defb 0
op_y:           defb 0
op_n:           defb 0
op_o:           defw 0
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

; text.screen: las filas de texto 1-21 (lineas 8-175) con el color de fondo del texto (set.text.attribute): bitmap a 0 y papel = tinta = ese color
t_textscr:      ld hl,HR_BM+256
                ld de,HR_BM+257
                ld bc,5375
                ld (hl),0
                ldir
                ld a,(tbg)
                and 15
                ld e,a
                ld d,0
                ld hl,ega2ch
                add hl,de
                ld a,(hl)
                ld c,a
                rlca
                rlca
                rlca
                rlca
                or c
                ld hl,HR_ATT+256
                ld de,HR_ATT+257
                ld bc,5375
                ld (hl),a
                ldir
                ret

; distance(o1, o2, v): distancia entre dos objetos (suma de |dx| y |dy|; 255 si alguno no esta dibujado o pasa de 254)
t_distance:     call argobj
                push ix
                ld a,(ARGS+1)
                call getobj
                pop iy
                ld b,255
                bit 1,(iy+O_F1)
                jr z,dd_put
                bit 1,(ix+O_F1)
                jr z,dd_put
                ld a,(ix+O_X)
                ld b,a
                ld a,(iy+O_X)
                call absd
                ld e,a
                ld d,0
                ld a,(ix+O_Y)
                ld b,a
                ld a,(iy+O_Y)
                call absd
                ld l,a
                ld h,0
                add hl,de
                ld b,255
                ld a,h
                or a
                jr nz,dd_put
                ld b,l
dd_put:         ld a,(ARGS+2)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret

; animate.obj(o)
t_animate:  call argobj
                bit 0,(ix+O_F1)
                ret nz
                ld a,(ix+O_F1)
                and %00000010           ; conserva drawn
                or %00011101            ; anim, upd, cycling, mon
                ld (ix+O_F1),a
                xor a
                ld (ix+O_F2),a
                ld (ix+O_MOTION),a
                ld (ix+O_DIR),a
                ld (ix+O_CTYPE),a
                ld (ix+O_WATER),a
                inc a
                ld (ix+O_STEP),a
                ld (ix+O_STIME),a
                ld (ix+O_SCOUNT),a
                ld (ix+O_CTIME),a
                ld (ix+O_CCOUNT),a
                ret

; get.num(m, v): el numero de la cola de cadenas (solo cifras; si no, 0)
t_getnum:      ld de,STMP
                call tq_pop
                ld hl,STMP              ; solo cifras (y no vacia) -> valor mod 256; si no, 0
                ld a,(hl)
                or a
                jr z,tg_0
                ld b,0
tg_l:           ld a,(hl)
                or a
                jr z,tg_ok
                sub '0'
                cp 10
                jr nc,tg_0
                ld c,a
                ld a,b
                add a,a
                ld d,a
                add a,a
                add a,a
                add a,d
                add a,c
                ld b,a
                inc hl
                jr tg_l
tg_0:           ld b,0
tg_ok:          ld a,(ARGS+1)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret

; parse(s): la cadena como si se hubiera tecleado (bandera 2); una cadena vacia no es una orden (f2 a 0)
t_parse:        ld a,(ARGS)
                cp 12
                ret nc
                call strptr
                ld a,(hl)
                or a
                jr nz,tpa_p
                ld (FLAGS+2),a
                ret
tpa_p:          call parse_text
                xor a
                ld (said_done),a
                inc a
                ld (FLAGS+2),a
                ret

; draw(o): el objeto pasa a dibujado; si su vista esta congelada (bit 15 de su desplazamiento en VIEWS.HDR), su tiempo de ciclo pasa a 127 (el maximo que no cicla enseguida)
t_draw:         call argobj
                bit 1,(ix+O_F1)
                ret nz
                set 1,(ix+O_F1)
                call obj_cell
                call map_views
                ld l,(ix+O_VIEW)
                ld h,0
                add hl,hl
                ld de,LWIN+1
                add hl,de
                ld a,(hl)
                push af
                call unmap_win
                pop af
                bit 7,a
                jr z,td_nf
                ld a,127
                ld (ix+O_CTIME),a
                ld (ix+O_CCOUNT),a
td_nf:          jp set_pri
