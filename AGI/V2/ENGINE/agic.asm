; =====================================================================
;  agic.asm - overlay C: restart.game, status (inventario) y show.obj. Pagina PG_OVC, en el bloque 1 solo mientras se ejecuta (call_c). El texto lo dibuja la ventana
;  de mensaje del overlay B (el nucleo pone pr_raw = 3 y el texto, en TMPM).
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_restart            ; OVC_RESTART
                jp t_gfxfix             ; OVC_GFXFIX (antes OVC_INVTXT)
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
                jp t_fixpos             ; OVC_FIXPOS
                jp t_follow             ; OVC_FOLLOW
                jp cycle_cel            ; OVC_CYCEL
                jp t_pre                ; OVC_PRE
                jp t_cycles             ; OVC_CYCLES
                jp clip_view            ; OVC_CLIP
                jp t_cmpstr             ; OVC_CMPSTR
                jp t_newroom            ; OVC_NEWROOM
                jp mv_od                ; OVC_MVOD
                jp t_gameid             ; OVC_GAMEID
                jp t_parsetext          ; OVC_PARSETEXT
                jp t_said               ; OVC_SAID
                jp t_show               ; OVC_SHOW

TXT             equ TMPM

; showSprites (sprite.cpp:352): de los objetos animados, dibujados y con update, los que acaban de dar su paso (stepTimeCount == stepTime) comparan su posicion con la
; previa: igual -> fDidntMove; si no, la previa pasa a ser la actual y se quita fDidntMove. Va despues de mover a todos (updatePosition).
t_show:         ld ix,OBJ
                ld b,NOBJ
ts_l:           ld a,(ix+O_F1)
                and 7
                cp 7
                jr nz,ts_n
                ld a,(ix+O_SCOUNT)
                cp (ix+O_STIME)
                jr nz,ts_n
                push ix
                pop hl
                call op_adr
                ld a,(ix+O_X)
                cp (hl)
                jr nz,ts_mv
                inc hl
                ld a,(ix+O_Y)
                cp (hl)
                jr nz,ts_mv1
                set 3,(ix+O_F2)
                jr ts_n
ts_mv1:         dec hl
ts_mv:          ld a,(ix+O_X)
                ld (hl),a
                inc hl
                ld a,(ix+O_Y)
                ld (hl),a
                res 3,(ix+O_F2)
ts_n:           ld de,32
                add ix,de
                djnz ts_l
                ret

t_said:        ld a,(FLAGS+4)         ; testSaid de ScummVM: f4 (SAID_ACCEPTED_INPUT) o sin f2 (ENTERED_CLI) -> falso; reset(f4) permite otro said
                or a
                jp nz,td_false
                ld a,(FLAGS+2)
                or a
                jp z,td_false
                ld hl,(saidp)
                ld a,(saidk)
                ld b,a                  ; B = nwords
                ld c,0                  ; C = c (palabra de la orden; n = inwcnt - c)
                ld de,0                 ; DE = z, la ultima palabra del said
hz_l:           ld a,b
                or a
                jr z,hz_post
                ld a,(inwcnt)
                cp c
                jr z,hz_post
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                cp $27
                jr nz,hz_n
                ld a,e
                cp $0F
                jr nz,hz_n
                ld b,1                  ; 9999: el resto vale
                jr hz_nx
hz_n:           ld a,d
                or a
                jr nz,hz_cmp
                ld a,e
                cp 1
                jr z,hz_nx              ; 1: cualquier palabra (tambien la desconocida)
hz_cmp:         push hl
                ld a,c
                add a,a
                ld l,a
                ld h,0
                push de
                ld de,INW
                add hl,de
                pop de
                ld a,(hl)
                cp e
                jr nz,hz_f1
                inc hl
                ld a,(hl)
                cp d
                jr nz,hz_f1
                pop hl
hz_nx:          inc c
                dec b
                jr hz_l
hz_f1:          pop hl
                jp td_false
hz_post:        ld a,(inwcnt)           ; if (n && z != 9999) falso
                cp c
                jr z,hz_p2
                call hz_9999
                jp nz,td_false
hz_p2:          ld a,b                  ; if (nwords != 0 && la siguiente != 9999) falso
                or a
                jr z,hz_ok
                ld e,(hl)
                inc hl
                ld d,(hl)
                call hz_9999
                jp nz,td_false
hz_ok:          ld a,1
                ld (said_done),a
                ld (FLAGS+4),a
                jp td_true
hz_9999:        ld a,d                  ; Z si DE = 9999
                cp $27
                ret nz
                ld a,e
                cp $0F
                ret

td_true:        ld a,1
                ld (said_res),a
                ret
td_false:       xor a
                ld (said_res),a
                ret

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
                ld hl,slot_sip
                ld de,slot_sip+1
                ld bc,NSLOTS*2-1
                ld (hl),0
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
                ld a,(rs_warm)          ; agiInit con _restartGame no toca las teclas de los controladores (controllerKeyMapping): sobreviven al reinicio
                or a
                jr nz,rs_nk
                ld hl,KEYMAP
                ld de,KEYMAP+1
                ld bc,511
                ld (hl),0
                ldir
rs_nk:          ld a,(rs_warm)          ; agiInit con _restartGame no borra las cadenas
                or a
                jr nz,rs_w
                ld hl,ARGS
                ld de,ARGS+1
                ld bc,CLR_END-ARGS-1
                ld (hl),0
                ldir
                jr rs_wd
rs_w:           ld hl,ARGS
                ld de,ARGS+1
                ld bc,STRS-ARGS-1
                ld (hl),0
                ldir
                ld hl,STRS+NSTR*41
                ld de,STRS+NSTR*41+1
                ld bc,CLR_END-STRS-NSTR*41-1
                ld (hl),0
                ldir
rs_wd:          ld a,1
                ld (rs_warm),a
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
                ld a,PG_OVL             ; sin add.to.pic (esta en la pagina del A1, que se asoma por el bloque 7)
                call map7
                xor a
                ld (st_n+$C000),a
                call map7_back
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
t_objpic:
                IF GFX4
                ret
                ENDIF
                call pic_open
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
t_textscr:
                IF GFX4
                ret
                ENDIF
                ld hl,HR_BM             ; cmdTextScreen: clearLines(0, 24, fondo): las 24 filas, con la barra de estado y el pie
                ld de,HR_BM+1
                ld bc,6143
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
                ld hl,HR_ATT
                ld de,HR_ATT+1
                ld bc,6143
                ld (hl),a
                ldir
                ret

; graphics (redrawScreen): clearDisplay(0) borra la barra de estado (fila 0) y el pie (filas 22 y 23); la barra y el prompt se redibujan en el ciclo siguiente
t_gfxfix:
                IF GFX4=0
       ld hl,HR_BM
                ld de,HR_BM+1
                ld bc,255
                ld (hl),0
                ldir
                ld hl,HR_BM+22*256
                ld de,HR_BM+22*256+1
                ld bc,511
                ld (hl),0
                ldir
                ld a,(ega2ch)
                ld c,a
                rlca
                rlca
                rlca
                rlca
                or c
                ld hl,HR_ATT
                ld de,HR_ATT+1
                ld bc,255
                ld (hl),a
                ldir
                ld hl,HR_ATT+22*256
                ld de,HR_ATT+22*256+1
                ld bc,511
                ld (hl),a
                ldir
                ENDIF
                xor a
                ld (st_valid),a
                inc a
                ld (kb_dirty),a
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
                call dd_cx              ; centro en x del segundo
                ld (dd_a),a
                push ix
                push iy
                pop ix
                call dd_cx              ; y el del primero
                pop ix
                ld hl,dd_a
                ld b,(hl)
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
                ld b,254                ; cmdDistance: tope 254
                ld a,h
                or a
                jr nz,dd_put
                ld a,l
                cp 254
                jr nc,dd_put
                ld b,l
dd_put:         ld a,(ARGS+2)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret
dd_cx:          call obj_cell
                ld a,d
                srl a
                add a,(ix+O_X)
                ret
dd_a:           defb 0

; animate.obj(o)
t_animate:  call argobj
                bit 0,(ix+O_F1)
                ret nz
                ld a,%00011101          ; anim, upd, cycling, mon (cmdAnimateObj borra todo lo demas, drawn incluido)
                ld (ix+O_F1),a
                xor a                   ; (no toca paso ni tiempos: los pone new.room)
                ld (ix+O_F2),a
                ld (ix+O_MOTION),a
                ld (ix+O_DIR),a
                ld (ix+O_CTYPE),a
                ld (ix+O_WATER),a
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

; parse(s): cmdParse de ScummVM: v9, f2 y f4 a 0 y se analiza la cadena (una cadena vacia deja f2 a 0)
t_parse:        ld a,(ARGS)
                cp NSTR
                ret nc
                call strptr
                xor a
                ld (VARS+9),a
                ld (said_done),a
                jp parse_text

t_parsetext:    ld hl,(pt_src)

; Words::parseUsingDictionary de ScummVM. HL = texto (acabado en 0). 1) cleanUpInput: los separadores ( ,.?!();:[]{}) separan palabras, ' ` - \ " se quitan
; sin separar, en minusculas; el resultado (palabras con un solo espacio) queda en TOKS. 2) por cada palabra, findWordInDictionary: INW = numero de cada palabra
; (0 la desconocida, que acaba el analisis y pone v9 = su posicion), WTEXT = su texto. f2 = hay palabras, f4 = 0.
parse_text:     xor a
                ld (FLAGS+2),a
                ld (FLAGS+4),a
                ld (inwcnt),a
                ld (wcount),a
                inc a
                ld (inwvalid),a
                ld de,TOKS
                ld b,0                  ; B = 1 dentro de una palabra
pc_l:           ld a,(hl)
                inc hl
                or a
                jr z,pc_e
                cp 'A'
                jr c,pc_k
                cp 'Z'+1
                jr nc,pc_k
                add a,32
pc_k:           cp 39
                jr z,pc_l
                cp 96
                jr z,pc_l
                cp 45
                jr z,pc_l
                cp 92
                jr z,pc_l
                cp 34
                jr z,pc_l
                push hl
                ld c,a
                ld hl,pc_sep
pc_s:           ld a,(hl)
                or a
                jr z,pc_w
                inc hl
                cp c
                jr nz,pc_s
                pop hl                  ; separador
                ld a,b
                or a
                jr z,pc_l
                ld a,' '
                ld (de),a
                inc de
                ld b,0
                jr pc_l
pc_w:           pop hl
                ld a,c
                ld (de),a
                inc de
                ld b,1
                jr pc_l
pc_e:           ld a,b
                or a
                jr nz,pc_z
                ld hl,TOKS              ; acaba en espacio: se quita
                or a
                sbc hl,de
                jr nc,pc_z
                dec de
pc_z:           xor a
                ld (de),a
                ld hl,WTEXT
                ld (wtp),hl
                ld hl,TOKS
pm_l:           ld a,(hl)
                or a
                jp z,pm_end
                cp ' '
                jr nz,pm_w
                inc hl
pm_w:           ld (pm_pos),hl
                call fw_find
                ld a,(fw_unk)
                or a
                jr nz,pm_add
                ld hl,(fw_num)
                ld a,h
                or l
                jr z,pm_adv             ; numero 0: se ignora
pm_add:         ld a,(inwcnt)
                cp 16
                jr nc,pm_end
                add a,a
                ld e,a
                ld d,0
                ld hl,INW
                add hl,de
                ld de,(fw_num)
                ld a,(fw_unk)
                or a
                jr z,pm_st
                ld de,0
pm_st:          ld (hl),e
                inc hl
                ld (hl),d
                ld hl,(pm_pos)
                ld a,(fw_len)
                ld c,a
                ld b,0
                ld de,(wtp)
                ldir
                xor a
                ld (de),a
                inc de
                ld (wtp),de
                ld hl,inwcnt
                inc (hl)
                ld hl,wcount
                inc (hl)
                ld a,(fw_unk)
                or a
                jr z,pm_adv
                ld a,(inwcnt)           ; palabra desconocida: v9 = su posicion y se acaba
                ld (VARS+9),a
                jr pm_end
pm_adv:         ld hl,(pm_pos)
                ld a,(fw_len)
                ld e,a
                ld d,0
                add hl,de
                jr pm_l
pm_end:         ld a,(inwcnt)
                or a
                ret z
                ld a,1
                ld (FLAGS+2),a
                ret
pc_sep:         defb " ,.?!();:[]{}",0

; findWordInDictionary: HL = inicio de la palabra en TOKS -> fw_unk (1 = desconocida), fw_num, fw_len (lo que ocupa). Entre las entradas que coinciden hasta un espacio o el
; final gana la ultima (salvo que una ocupe todo lo que queda); una letra sola, "a" o "i", sin entrada propia se ignora (numero 0)
fw_find:        xor a
                ld (fw_len),a
                ld (fw_num),a
                ld (fw_num+1),a
                inc a
                ld (fw_unk),a
                ld (fw_p),hl
                ld a,(hl)
                cp '0'
                jp c,fw_dist
                cp '9'+1
                jr c,fw_ok
                cp 'a'
                jp c,fw_dist
                cp 'z'+1
                jp nc,fw_dist
fw_ok:          cp 'a'
                jr z,fw_ai
                cp 'i'
                jr nz,fw_sc
fw_ai:          inc hl
                ld a,(hl)
                cp ' '
                jr nz,fw_sc
                xor a
                ld (fw_unk),a
fw_sc:          ld a,PG_WORDS
                call map_page
                xor a
                ld (WBUF),a
                ld hl,(LWIN)            ; longitud del WORDS.TOK
                ld de,LWIN+2
                add hl,de
                dec hl
                dec hl
                ld (fw_end),hl          ; mientras p < longitud-2
                ld hl,LWIN+2+52
fw_l:           ld de,(fw_end)
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,fw_done
                ld a,(hl)               ; caracteres compartidos con la anterior
                inc hl
                ld c,a
                ld b,0
                push hl
                ld hl,WBUF
                add hl,bc
                ex de,hl
                pop hl
fw_c:           ld a,(hl)
                inc hl
                ld b,a
                and $7F
                xor $7F
                ld (de),a
                inc de
                bit 7,b
                jr z,fw_c
                xor a
                ld (de),a
                ld d,(hl)               ; numero, big endian
                inc hl
                ld e,(hl)
                inc hl
                push hl
                push de
                ld hl,WBUF
                ld de,(fw_p)
fw_cm:          ld a,(hl)
                or a
                jr z,fw_ce
                ld a,(de)
                cp (hl)
                jr nz,fw_ne
                inc hl
                inc de
                jr fw_cm
fw_ce:          ld a,(de)               ; la entrada acaba aqui: coincide si la orden tambien o sigue un espacio
                or a
                jr z,fw_eq
                cp ' '
                jr nz,fw_ne
fw_eq:          push af                 ; el terminador: 0 = la entrada ocupa todo lo que queda
                ld hl,(fw_p)
                ex de,hl                ; HL = fin de lo que coincide, DE = inicio
                or a
                sbc hl,de
                ld a,l
                ld (fw_len),a
                pop af
                pop de
                ld (fw_num),de
                ld b,a
                xor a
                ld (fw_unk),a
                pop hl
                ld a,b
                or a
                jr nz,fw_l              ; queda orden: sigue buscando una entrada mas larga
                jr fw_done
fw_ne:          pop de
                pop hl
                jr fw_l
fw_done:        call unmap_win
                ld a,(fw_len)
                or a
                ret nz
fw_dist:        ld hl,(fw_p)            ; sin entrada: hasta el siguiente espacio
                ld b,0
fw_d1:          ld a,(hl)
                or a
                jr z,fw_d2
                cp ' '
                jr z,fw_d2
                inc hl
                inc b
                jr fw_d1
fw_d2:          ld a,b
                ld (fw_len),a
                ret

; draw(o): el objeto pasa a dibujado; si su vista esta congelada (bit 15 de su desplazamiento en VIEWS.HDR), su tiempo de ciclo pasa a 127 (el maximo que no cicla enseguida)
t_draw:         call argobj
                bit 1,(ix+O_F1)
                ret nz
                set 1,(ix+O_F1)
                set 2,(ix+O_F1)        ; cmdDraw: fUpdate
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
td_nf:          res 4,(ix+O_F2)         ; draw quita el fDontUpdate
                ld a,(ARGS)
                ld (curk),a
                call t_fixpos
                ld a,(ARGS)             ; cmdDraw: xPos_prev = xPos tras fixPosition
                call getobj
                jp set_prev

; fixPosition de ScummVM para el objeto IX: si su sitio no vale (fuera de la pantalla, horizonte, objetos, lineas de control) busca el mas cercano en espiral O, S, E, N
; (sin la zona de block); si la espiral cubre toda la pantalla lo deja como estaba. Acaba con set_pri. La posicion de entrada hace de posicion previa en la colision.
t_fixpos:       ld a,(blkf)
                push af
                xor a
                ld (blkf),a
                bit 7,(ix+O_F1)         ; no ignora el horizonte: y <= horizonte -> y = horizonte + 1
                jr nz,fx_a
                ld a,(horizon)
                cp (ix+O_Y)
                jr c,fx_a
                inc a
                ld (ix+O_Y),a
fx_a:           ld e,(ix+O_X)
                ld d,0
                ld (nx),de
                ld e,(ix+O_Y)
                ld (ny),de
                xor a
                ld (fxd),a
                inc a
                ld (fxc),a
                ld (fxs),a
fx_l:           call fx_ok
                jr nz,fx_ok2
                ld a,(fxs)
                cp 171
                jr nc,fx_end            ; vuelta a toda la pantalla: se queda donde estaba
                ld a,(fxd)
                ld hl,(nx)
                ld de,(ny)
                or a
                jr z,fs0
                dec a
                jr z,fs1
                dec a
                jr z,fs2
                dec de                  ; N
                ld bc,$0001
                jr fs_e
fs0:            dec hl                  ; O
                ld bc,$0100
                jr fs_h
fs1:            inc de                  ; S
                ld bc,$0201
                jr fs_e
fs2:            inc hl                  ; E
                ld bc,$0300
fs_h:           ld (nx),hl
fs_e:           ld (ny),de
                ld a,(fxc)
                dec a
                ld (fxc),a
                jr nz,fx_l
                ld a,b
                ld (fxd),a
                ld a,(fxs)
                add a,c
                ld (fxs),a
                ld (fxc),a
                jr fx_l
fx_ok2:         ld a,(nx)
                ld (ix+O_X),a
                ld a,(ny)
                ld (ix+O_Y),a
fx_end:         pop af
                ld (blkf),a
                jp set_pri

; Z = no vale; checkPosition (dentro de la pantalla) y despues can_be_here (horizonte, objetos, lineas de control)
fx_ok:          call obj_cell
                ld a,d
                ld (ow),a
                ld hl,(nx)
                bit 7,h
                jr nz,fo_no
                ld e,a
                ld d,0
                add hl,de
                ld de,161
                or a
                sbc hl,de               ; x + w > 160
                jr nc,fo_no
                ld hl,(ny)
                ld de,168
                or a
                sbc hl,de
                jr nc,fo_no
                ld hl,(ny)
                bit 7,h
                jr nz,fo_no
                call obj_cell
                ld d,0
                ld hl,(ny)
                or a
                sbc hl,de               ; y - h < -1
                inc hl
                bit 7,h
                jr nz,fo_no
                call can_be_here
                or a
                ret
fo_no:          xor a
                ret

fxd:            defb 0
fxc:            defb 0
fxs:            defb 0

; motionFollowEgo de ScummVM para el objeto IX (follow_stepSize en MSTEP, follow_count en WANDER): pone O_DIR (centros en x; llega con dir 0 y bandera;
; si no se movio en el paso anterior (F2 bit 3) tira al azar un rato) y el nucleo sigue con el paso
t_follow:       push ix
                ld ix,OBJ
                call obj_cell
                ld a,d
                srl a
                add a,(ix+O_X)
                ld (tf_ex),a
                ld a,(ix+O_Y)
                ld (tf_ey),a
                pop ix
                call obj_cell
                ld a,d
                srl a
                add a,(ix+O_X)
                ld (tf_ox),a
                ld a,(ix+O_Y)
                ld (tf_oy),a
                ld a,(tf_ex)
                ld hl,tf_ox
                sub (hl)
                ld e,(ix+O_MSTEP)
                call mo_cs2
                ld b,a
                ld a,(tf_ey)
                ld hl,tf_oy
                sub (hl)
                ld e,(ix+O_MSTEP)
                call mo_cs2
                ld c,a
                ld a,(ix+O_DIR)
                push af
                call setdir
                ld a,(ix+O_DIR)
                ld (tf_d),a             ; direccion hacia el ego
                pop af
                ld (ix+O_DIR),a
                ld a,(tf_d)
                or a
                jr nz,tf_n0
                ld (ix+O_DIR),a         ; ya esta: para y pone la bandera
                ld (ix+O_MOTION),a
                ld a,(ix+O_MFLAG)
                ld l,a
                ld h,FLAGS>>8
                ld (hl),1
                ret
tf_n0:          ld a,(ix+O_WANDER)
                cp 255
                jr nz,tf_c1
                xor a
                ld (ix+O_WANDER),a
                jr tf_cnt
tf_c1:          bit 3,(ix+O_F2)
                jr z,tf_cnt
                call rand8              ; no se movio: rumbo al azar (1-8) durante un rato
                and 7
                inc a
                ld (ix+O_DIR),a
                ld a,(tf_oy)
                ld b,a
                ld a,(tf_ey)
                call absd
                ld l,a
                ld a,(tf_ox)
                ld b,a
                ld a,(tf_ex)
                call absd
                add a,l
                rra                     ; (|dy| + |dx|) / 2 (el acarreo es el bit 9)
                ld c,(ix+O_STEP)
                cp c
                jr nc,tf_r
                ld (ix+O_WANDER),c
                ret
tf_r:           sub c
                inc a
                ld c,a                  ; rand8 deja B a 0: el modulo se pasa a B despues
                call rand8
                ld b,c
                call rem8
                add a,(ix+O_STEP)
                ld (ix+O_WANDER),a
                ret
tf_cnt:         ld a,(ix+O_WANDER)
                or a
                jr nz,tf_dec
                ld a,(tf_d)
                ld (ix+O_DIR),a
                ret
tf_dec:         sub (ix+O_STEP)
                jp p,tf_s
                xor a
tf_s:           ld (ix+O_WANDER),a
                ret

tf_ex:          defb 0
tf_ey:          defb 0
tf_ox:          defb 0
tf_oy:          defb 0
tf_d:           defb 0

; updateView de ScummVM: un paso de ciclo del objeto IX
cycle_cel:      call obj_info
                ld a,(occ)
                or a
                ret z
                ld b,a                  ; B = celdas del bucle
                ld a,(ix+O_CTYPE)
                or a
                jr z,cc_0
                cp 3
                jr z,cc_3
                cp 1
                jr z,cc_1
                ld a,(ix+O_CEL)         ; 2: reverse.loop (la bandera se pone al llegar a la celda 0)
                or a
                jr z,cc_end
                dec a
                ld (ix+O_CEL),a
                ret nz
                jr cc_end
cc_1:           ld a,(ix+O_CEL)
                inc a
                cp b
                jr nc,cc_end
                ld (ix+O_CEL),a
                inc a
                cp b
                ret nz                  ; end.of.loop: la bandera se pone al llegar a la ultima celda
cc_end:         bit 6,(ix+O_F2)         ; ignoreLoopFlag: no se pone la bandera
                jr nz,cc_nf
                ld a,(ix+O_CFLAG)
                ld l,a
                ld h,FLAGS>>8
                ld (hl),1
cc_nf:                res 3,(ix+O_F1)
                xor a
                ld (ix+O_CTYPE),a
                ld (ix+O_DIR),a
                ret
cc_0:           ld a,(ix+O_CEL)
                inc a
                call rem8
                ld (ix+O_CEL),a
                ret
cc_3:           ld a,(ix+O_CEL)
                or a
                jr nz,cc_3b
                ld a,b
                dec a
                ld (ix+O_CEL),a
                ret
cc_3b:          dec a
                call rem8
                ld (ix+O_CEL),a
                ret


; interpretCycle (antes de la logica): la direccion del ego sale de v6 con el jugador al mando (si no, v6 es la suya) y checkAllMotions
t_pre:          ld a,(pctl)
                or a
                jr z,ov_tp_a
                ld a,(VARS+6)
                ld (OBJ+O_DIR),a
                jr ov_tp_b
ov_tp_a:           ld a,(OBJ+O_DIR)
                ld (VARS+6),a
ov_tp_b:           ld ix,OBJ
                xor a
                ld (curk),a
ov_tp_l:           ld a,(ix+O_F1)
                and 7
                cp 7
                jr nz,ov_tp_n
                ld a,(ix+O_SCOUNT)
                cp 1
                call z,t_motion         ; solo en el ciclo en que el objeto da su paso
ov_tp_n:           ld de,32
                add ix,de
                ld a,(curk)
                inc a
                ld (curk),a
                cp NOBJ
                jr c,ov_tp_l
                ret

; checkMotion de ScummVM para el objeto IX: wander / follow.ego / move.obj, y la zona de block (changePos) anula la direccion si se cruza
t_motion:       ld a,(ix+O_MOTION)
                or a
                jr z,ov_tm_blk
                cp 3
                jr z,ov_tm_3
                cp 2
                jr z,ov_tm_2
                ld a,(ix+O_WANDER)      ; motionWander
                ld c,a
                dec a
                ld (ix+O_WANDER),a
                ld a,c
                or a
                jr z,ov_tm_wr
                bit 3,(ix+O_F2)
                jr z,ov_tm_blk
ov_tm_wr:          call rand8
                ld b,9
                call rem8
                ld (ix+O_DIR),a
                ld c,a
                ld a,(curk)
                or a
                jr nz,ov_tm_wl
                ld a,c
                ld (VARS+6),a
ov_tm_wl:          ld a,(ix+O_WANDER)
                cp 6
                jr nc,ov_tm_blk
                call rand8
                ld b,51
                call rem8
                ld (ix+O_WANDER),a
                jr ov_tm_wl
ov_tm_2:           call t_follow
                jr ov_tm_blk
ov_tm_3:           call mv_od
ov_tm_blk:         ld a,(blkf)
                or a
                ret z
                bit 0,(ix+O_F2)
                ret nz
                ld a,(ix+O_DIR)
                or a
                ret z
                ld e,(ix+O_X)
                ld d,0
                push de
                ld a,(ix+O_DIR)
                ld e,a
                ld d,0
                ld hl,DXTAB
                add hl,de
                ld a,(hl)
                call mulstep
                pop de
                add hl,de
                ld a,l
                push af
                ld a,(ix+O_DIR)
                ld e,a
                ld d,0
                ld hl,DYTAB
                add hl,de
                ld a,(hl)
                call mulstep
                ld e,(ix+O_Y)
                ld d,0
                add hl,de
                ld e,l                  ; E = y nueva
                pop af
                ld d,a                  ; D = x nueva
                call bk_in
                ld c,a
                ld d,(ix+O_X)
                ld e,(ix+O_Y)
                call bk_in
                cp c
                ret z
                xor a                   ; se cruza: direccion 0 (y v6 si es el ego)
                ld (ix+O_DIR),a
                ld a,(curk)
                or a
                ret nz
                ld (VARS+6),a
                ret

; updateScreenObjTable (primera mitad): por cada objeto, elegir bucle y ciclar
t_cycles:       ld ix,OBJ
                xor a
                ld (curk),a
ov_tc_l:           ld a,(ix+O_F1)
                and 7
                cp 7
                jr nz,ov_tc_n
                xor a                   ; updatePosition (hay algun objeto que actualizar) pone a 0 el borde del ego
                ld (VARS+2),a
                call t_pick
                bit 3,(ix+O_F1)
                jr z,ov_tc_n
                ld a,(ix+O_CCOUNT)
                or a
                jr z,ov_tc_n
                dec a
                ld (ix+O_CCOUNT),a
                jr nz,ov_tc_n
                bit 4,(ix+O_F2)         ; fDontUpdate: se come este paso
                jr z,ov_tc_c
                res 4,(ix+O_F2)
                jr ov_tc_t
ov_tc_c:           call cycle_cel
                call clip_view
ov_tc_t:           ld a,(ix+O_CTIME)
                ld (ix+O_CCOUNT),a
ov_tc_n:           ld de,32
                add ix,de
                ld a,(curk)
                inc a
                ld (curk),a
                cp NOBJ
                jr c,ov_tc_l
                ret

; bucle segun la direccion: 2 o 3 bucles -> LOOP2, 4 -> LOOP4, mas: ninguno; solo si el objeto da su paso este ciclo
t_pick:         bit 6,(ix+O_F1)
                ret nz
                ld a,(ix+O_SCOUNT)
                cp 1
                ret nz
                call obj_info
                ld a,(ocn)
                cp 4
                ld hl,LOOP4
                jr z,ov_tpk_t
                ret nc
                cp 2
                ret c
                ld hl,LOOP2
ov_tpk_t:          ld e,(ix+O_DIR)
                ld d,0
                add hl,de
                ld a,(hl)
                cp 4
                ret z
                cp (ix+O_LOOP)
                ret z
                ld (ix+O_LOOP),a
; clipViewCoordinates (tras cambiar de celda): dentro de la pantalla y por debajo del horizonte; cada correccion pone fUpdatePos
clip_view:      call obj_cell           ; D = ancho, E = alto
                ld a,(ix+O_X)
                add a,d
                jr c,ov_cv_x
                cp 161
                jr c,ov_cv_y
ov_cv_x:           set 5,(ix+O_F2)
                ld a,160
                sub d
                ld (ix+O_X),a
ov_cv_y:           ld a,e
                dec a
                ld b,a                  ; B = alto - 1
                ld a,(ix+O_Y)
                cp b
                jr nc,ov_cv_h
                set 5,(ix+O_F2)
                ld (ix+O_Y),b
ov_cv_h:           bit 7,(ix+O_F1)
                ret nz
                ld a,(horizon)
                cp (ix+O_Y)
                ret c
                inc a
                ld (ix+O_Y),a
                set 5,(ix+O_F2)
                ret

; compare.strings (cmdCompareStrings): sin espacios, tabuladores ni puntuacion (- . , : ; ! '), en minusculas; NZ = iguales
t_cmpstr:       ld a,(ARGS)
                cp NSTR
                jr nc,tcs_f
                call strptr
                ld de,STMP
                call ov_norm
                ld a,(ARGS+1)
                cp NSTR
                jr nc,tcs_f
                call strptr
                ld de,STMP2
                call ov_norm
                ld hl,STMP
                ld de,STMP2
tcs_l:          ld a,(de)
                cp (hl)
                jr nz,tcs_f
                or a
                jr z,tcs_t
                inc hl
                inc de
                jr tcs_l
tcs_t:          or 1
                ret
tcs_f:          xor a
                ret
ov_norm:        ld a,(hl)
                inc hl
                or a
                jr z,on_e
                cp 33
                jr c,ov_norm
                cp '-'
                jr z,ov_norm
                cp '.'
                jr z,ov_norm
                cp ','
                jr z,ov_norm
                cp ':'
                jr z,ov_norm
                cp ';'
                jr z,ov_norm
                cp '!'
                jr z,ov_norm
                cp 39
                jr z,ov_norm
                cp 'A'
                jr c,on_w
                cp 'Z'+1
                jr nc,on_w
                add a,32
on_w:           ld (de),a
                inc de
                jr ov_norm
on_e:           xor a
                ld (de),a
                ret

; newRoom: todos los objetos (tambien el ego) actualizan, con paso y tiempos a 1; las logicas que no son la 0 vuelven a empezar por el principio (set.scan.start)
t_newroom:      ld ix,OBJ
                ld de,32
                ld b,NOBJ
                ld a,1
tn_l:           set 2,(ix+O_F1)         ; (fUpdate)
                ld (ix+O_STEP),a
                ld (ix+O_STIME),a
                ld (ix+O_SCOUNT),a
                ld (ix+O_CTIME),a
                ld (ix+O_CCOUNT),a
                add ix,de
                djnz tn_l
                ld hl,slot_sip+2
                ld de,slot_sip+3
                ld bc,NSLOTS*2-3
                xor a
                ld (hl),a
                ldir
                ld a,(gfix)             ; apano de ScummVM (Larry 1): la bandera 36 se borra en cada sala nueva
                cp 2
                jr nz,tn_g
                xor a
                ld (FLAGS+36),a
tn_g:           ld a,(OBJ+O_VIEW)       ; VM_VAR_EGO_VIEW_RESOURCE
                ld (VARS+16),a
                ret

; set.game.id: SQ1 -> 1, Larry 1 -> 2 (los apanos de ScummVM por juego)
t_gameid:       ld a,(ARGS)
                ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,8
                call build_str
                ld hl,TXT
                ld de,g_sq
                call g_cmp
                ld a,1
                jr z,tg_set
                ld hl,TXT
                ld de,g_ll
                call g_cmp
                ld a,2
                jr z,tg_set
                xor a
tg_set:         ld (gfix),a
                ret
g_cmp:          ld a,(de)
                cp (hl)
                ret nz
                or a
                ret z
                inc de
                inc hl
                jr g_cmp
g_sq:           defb "SQ",0
g_ll:           defb "LLLLL",0

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
                jp mv_stop

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

