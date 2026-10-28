; =====================================================================
;  agiin.asm - entrada, parser y cadenas del interprete AGI (se incluye desde agivm.asm)
;
;  Eventos de entrada guionizados (EVENTS.BIN, para las pruebas contra el modelo de Python): texto, cadena para get.string,
;  tecla, controlador y direccion del ego. El parser sale de WORDS.BIN (el WORDS.TOK original con su longitud delante),
;  los mensajes de LOGnnn.MSG. Las cadenas son 12 de 40 caracteres. Todo sigue TOOLS/agi_vm.py.
; =====================================================================

; A = pagina -> bloque 4
map_page:       ld b,a
                ld c,MAP_PORT
                ld a,4
                out (c),a
                ret

; ---------------------------------------------------------------------
;  Eventos
; ---------------------------------------------------------------------
do_events:      ld a,(evend)
                or a
                ret nz
                ld a,PG_EVT
                call map_page
                ld hl,(evp)
                ld de,LWIN
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                and e
                inc a
                jr nz,de_chk
                ld a,1
                ld (evend),a
                jp unmap_win
de_chk:         ld bc,(cyc)
                ld a,e
                cp c
                jr nz,de_no
                ld a,d
                cp b
                jr nz,de_no
                ld a,(hl)
                inc hl
                ld (ev_kind),a
                ld c,(hl)
                inc hl
                ld de,EVBUF
                ld a,c
                or a
                jr z,de_c0
                ld b,0
                ldir
de_c0:          xor a
                ld (de),a
                ld de,LWIN
                or a
                sbc hl,de
                ld (evp),hl
                call unmap_win
                call ev_dispatch
                jr do_events
de_no:          jp unmap_win

ev_dispatch:    ld a,(ev_kind)
                cp 1
                jr z,ev_text
                cp 2
                jr z,ev_str
                cp 3
                jr z,ev_key
                cp 4
                jr z,ev_ctrl
                cp 5
                jr z,ev_dir
                ret
ev_text:        ld a,(gs_on)            ; get.string: la linea es la cadena pedida
                or a
                jr nz,ev_str
                ld hl,EVBUF             ; la linea tambien se guarda para echo.line
                ld de,LASTLN
                ld bc,41
                ldir
                ld hl,EVBUF
                call parse_text
                xor a
                ld (said_done),a
                ld (VARS+19),a
                inc a
                ld (FLAGS+2),a
                ret
ev_str:         ld hl,EVBUF
                jp tq_push
ev_key:         ld a,(EVBUF)
                jp key_push
ev_ctrl:        ld a,(EVBUF)
                ld l,a
                ld h,CTL>>8
                ld (hl),1
                ret
ev_dir:         ld a,(EVBUF)
                ld (dirhold),a
                ret

; ---------------------------------------------------------------------
;  Teclas y controladores
; ---------------------------------------------------------------------
key_push:       ld c,a
                ld (VARS+19),a
                ld a,(keyn)
                cp 8
                jr nc,kp_m
                ld e,a
                ld d,0
                ld hl,KEYQ
                add hl,de
                ld (hl),c
                inc a
                ld (keyn),a
kp_m:           ld a,c
                and 127
                ld l,a
                ld h,0
                add hl,hl
                ld de,KEYMAP
                add hl,de
                inc hl
                ld a,(hl)
                or a
                ret z
                dec hl
                ld a,(hl)
                ld l,a
                ld h,CTL>>8
                ld (hl),1
                ret

h_set_key:      ld a,(ARGS)             ; ascii, scan, controlador
                or a
                jr nz,sk_a
                ld a,(ARGS+1)           ; teclas de funcion: F5 (63) y F7 (65) viven en los codigos de control 28 y 30 (teclas 2 y 3 del ZX81)
                cp 63
                ld a,28
                jr z,sk_a
                ld a,(ARGS+1)
                cp 65
                ret nz
                ld a,30
sk_a:           and 127
                ld l,a
                ld h,0
                add hl,hl
                ld de,KEYMAP
                add hl,de
                ld a,(ARGS+2)
                ld (hl),a
                inc hl
                ld (hl),1
                ret

hc_controller:  ld a,(ARGS)
                ld l,a
                ld h,CTL>>8
                ld a,(hl)
                or a
                jp z,ret_false
                jp ret_true

hc_have_key:    ld a,(keyn)
                or a
                jr nz,hk_k
                ld a,(txtm)             ; en la pantalla de texto, un bucle apretado (ayuda: la 2a llamada del ciclo sin tecla) espera la tecla
                or a
                jp z,ret_false
                ld a,(hk_seen)
                or a
                jr nz,hk_w
                inc a
                ld (hk_seen),a
                jp ret_false
hk_w:           call pr_wait
                ld a,(stopf)
                or a
                jp nz,ret_false
                ld a,(pw_last)
                ld (VARS+19),a
                jp ret_true
hk_k:
                ld a,(KEYQ)
                ld (VARS+19),a
                ld hl,KEYQ+1
                ld de,KEYQ
                ld bc,7
                ldir
                ld hl,keyn
                dec (hl)
                jp ret_true

; ---------------------------------------------------------------------
;  Cola de cadenas para get.string / get.num (4 de 41 bytes)
; ---------------------------------------------------------------------
; HL = cadena -> al final de la cola (se trunca a 40)
tq_push:        ld a,(tqn)
                cp 4
                ret nc
                ld b,a
                ld a,(tqh)
                add a,b
                and 3
                push hl
                call tq_addr
                ex de,hl
                pop hl
                ld b,40
tp_l:           ld a,(hl)
                or a
                jr z,tp_e
                ld (de),a
                inc hl
                inc de
                djnz tp_l
tp_e:           xor a
                ld (de),a
                ld hl,tqn
                inc (hl)
                ret

; DE = destino de 41 bytes -> saca el primero de la cola; A = 1 si habia
tq_pop:         ld a,(tqn)
                or a
                jr nz,tq_1
                xor a
                ld (de),a
                ret
tq_1:           ld a,(tqh)
                push de
                call tq_addr            ; HL = TQ + 41*A
                pop de
                ld bc,41
                ldir
                ld a,(tqh)
                inc a
                and 3
                ld (tqh),a
                ld hl,tqn
                dec (hl)
                ld a,1
                ret

; HL = TQ + 41*A (A <= 3)
tq_addr:        ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl               ; 8A
                ld b,h
                ld c,l
                add hl,hl
                add hl,hl               ; 32A
                add hl,bc               ; 40A
                add hl,de               ; 41A
                ld bc,TQ
                add hl,bc
                ret

; ---------------------------------------------------------------------
;  Cadenas
; ---------------------------------------------------------------------
; A = indice (0-11) -> HL = STRS + 41*A
strptr:         ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                ld b,h
                ld c,l
                add hl,hl
                add hl,hl
                add hl,bc
                add hl,de
                ld bc,STRS
                add hl,bc
                ret

h_set_string:   ld a,(ARGS)
                cp 12
                ret nc
                call strptr
                ex de,hl
                ld a,(curlg)
                ld (bs_lg),a
                ld a,(ARGS+1)
                ld b,a
                ld c,40
                jp build_str

; texto: el codigo esta en el overlay (agitxt.asm, bloque 1)
h_display:      ld hl,OVB_DISPLAY
                jp call_b
h_display_v:    ld hl,OVB_DISPLAY_V
                jp call_b
; text.screen: la pantalla se queda en blanco (overlay C) y sin sprites; graphics la devuelve (la imagen se vuelve a dibujar)
h_text_screen:  ld a,1
                ld (txtm),a
                call OVL_SPRINIT
                ld hl,OVC_TEXTSCR
                jp call_c
h_graphics:     xor a
                ld (txtm),a
                call rd_pic
                jp sg_t
; overlay.pic: la imagen de la sala con la que se le superpone ya hecha (PIC/PICAnn.GFX, TOOLS/agi2hr.py), redibujada como graphics
h_overlay_pic:  ld a,1
                ld (ovl_on),a
                jp h_graphics
txtm:           defb 0
hk_seen:        defb 0
; shake.screen(n): n sacudidas de 8 fotogramas con el fino X (POKE 2090) y el fino Y (registro 8 del puerto $3FEF) del hardware; al acabar, a 0. Esta en el
; nucleo porque wait_frame llama al overlay A (con otro overlay en el bloque 1 se perderia). En las pruebas (ncyc > 0) no espera fotogramas.
h_shake_screen: ld a,(ARGS)
                or a
                ret z
                ld (sh_n),a
sh_l:           ld hl,sh_pat
                ld b,8
sh_f:           ld a,(hl)
                inc hl
                ld (2090),a
                ld a,(hl)
                inc hl
                push hl
                push bc
                call sh_y
                ld hl,(ncyc)
                ld a,h
                or l
                call z,wait_frame
                pop bc
                pop hl
                djnz sh_f
                ld hl,sh_n
                dec (hl)
                jr nz,sh_l
                xor a
                ld (2090),a
sh_y:           ld d,a
                ld bc,$3FEF
                ld a,$40
                out (c),a
                ld a,d
                out (c),a
                ret
sh_n:           defb 0
sh_pat:         defb 4,2, 4,2, 0,0, 0,0, 2,3, 2,3, 0,0, 0,0
h_clear_lines:  ld hl,OVB_CLEAR
                jp call_b
h_set_text_attribute: ld hl,OVB_ATTR
                jp call_b
h_status_line_on: ld hl,OVB_SON
                jp call_b
h_status_line_off: ld hl,OVB_SOFF
                jp call_b
; print: ventana de mensaje (overlay B) y espera de una tecla
h_print:        ld a,(ARGS)
hp_s:           ld (pr_msg),a
                ld a,255
                ld (pr_row),a
                xor a
                ld (pr_w),a
                jr pr_go
h_print_v:      ld a,(ARGS)
                call getv
                jr hp_s
h_print_at:     ld a,(ARGS)
                ld (pr_msg),a
                ld a,(ARGS+1)
                ld (pr_row),a
                ld a,(ARGS+2)
                ld (pr_col),a
                ld a,(ARGS+3)
                ld (pr_w),a
                jr pr_go
h_print_at_v:   ld a,(ARGS)
                call getv
                ld (pr_msg),a
                ld a,(ARGS+1)
                call getv
                ld (pr_row),a
                ld a,(ARGS+2)
                call getv
                ld (pr_col),a
                ld a,(ARGS+3)
                call getv
                ld (pr_w),a
pr_go:          call OVL_SPRINIT        ; con la ventana abierta los sprites se apagan
                ld hl,OVB_PRINT
                call call_b
                ld a,(oc_pw)            ; show.obj: el dibujo del objeto dentro de la ventana
                or a
                jr z,pg_w
                ld hl,OVC_OBJPIC
                call call_c
                xor a
                ld (oc_pw),a
pg_w:           call pr_wait
                ld a,(stopf)
                or a
                ret nz                  ; se acabaron los ciclos (pruebas): la ventana se queda
                ld hl,OVB_BOXCLOSE
                call call_b
                jp OVL_FORCE

; Espera una tecla: cada vuelta es un ciclo (con sus eventos y las teclas del ZX81); la tecla no llega a la logica
pr_wait:        ld a,(keyn)
                ld (pw_k),a
                ld a,(VARS+19)
                ld (pw_v),a
pw_l:           ld hl,(cyc)
                inc hl
                ld (cyc),hl
                ld de,(ncyc)
                ld a,d
                or e
                jr z,pw_run             ; modo real: sin limite
                ld a,e
                sub l
                ld a,d
                sbc a,h
                jr nc,pw_run
                ld a,1                  ; pruebas: se acabaron los ciclos
                ld (stopf),a
                ret
pw_run:         call OVL_KDELIV
                call do_events
                ld a,(keyn)
                ld hl,pw_k
                cp (hl)
                jr nz,pw_d
                ld a,(gs_on)            ; get.string: tambien acaba cuando llega una linea (aunque no sea por teclado)
                or a
                jr z,pw_nt
                ld a,(tqn)
                or a
                ret nz
pw_nt:          ld hl,(ncyc)
                ld a,h
                or l
                call z,wait_frame
                jr pw_l
pw_d:           ld a,(pw_k)             ; la tecla que cierra, para quien la quiera (restart.game)
                ld e,a
                ld d,0
                ld hl,KEYQ
                add hl,de
                ld a,(hl)
                ld (pw_last),a
                ld a,(pw_k)
                ld (keyn),a
                ld a,(pw_v)
                ld (VARS+19),a
                ret
pr_msg:         defb 0
pr_row:         defb 0
pr_col:         defb 0
pr_w:           defb 0
pw_k:           defb 0
pw_last:        defb 0
pw_v:           defb 0

; ---------------------------------------------------------------------
;  Menus: set.menu / set.menu.item / enable.item / disable.item guardan en el overlay B (agib.asm); menu.input es modal como print: cada vuelta es un ciclo, las
;  flechas (cambios de dirhold a 1, 3, 5, 7) mueven, ENTER elige (enciende el controlador del elemento) y ESC cierra; la tecla no llega a la logica.
; ---------------------------------------------------------------------
h_set_menu:     ld hl,OVB_SETMENU
                jp call_b
h_set_menu_item: ld hl,OVB_SETITEM
                jp call_b
h_submit_menu:  ret
h_enable_item:  ld hl,OVB_ENABLE
                jp call_b
h_disable_item: ld hl,OVB_DISABLE
                jp call_b

h_menu_input:   ld a,(FLAGS+14)         ; f14: menus disponibles
                or a
                ret z
                ld a,(keyn)             ; la tecla que lo abre (un controlador) no llega a have.key
                or a
                jr z,mi_nk
                dec a
                ld e,a
                ld d,0
                ld hl,KEYQ
                add hl,de
                ld a,(hl)
                and 127
                ld l,a
                ld h,0
                add hl,hl
                ld de,KEYMAP
                add hl,de
                inc hl
                ld a,(hl)
                or a
                jr z,mi_nk
                ld hl,keyn
                dec (hl)
                xor a
                ld (VARS+19),a
mi_nk:          call OVL_SPRINIT        ; con el menu abierto los sprites se apagan
                ld hl,OVB_MENUOPEN
                call call_b
                ld a,(mn_res)
                cp 254
                jp z,OVL_FORCE          ; no hay menus
                ld a,(keyn)
                ld (mi_k),a
                ld a,(VARS+19)
                ld (mi_v),a
                ld a,(dirhold)
                ld (mi_d),a
mi_l:           ld hl,(cyc)
                inc hl
                ld (cyc),hl
                ld de,(ncyc)
                ld a,d
                or e
                jr z,mi_run             ; modo real: sin limite
                ld a,e
                sub l
                ld a,d
                sbc a,h
                jr nc,mi_run
                ld a,1                  ; pruebas: se acabaron los ciclos, el menu se queda
                ld (stopf),a
                ret
mi_run:         call OVL_KDELIV
                call do_events
                ld a,(dirhold)
                ld hl,mi_d
                cp (hl)
                jr z,mi_nd
                ld (hl),a
                or a
                jr z,mi_nd
                ld (mn_dir),a
                ld hl,OVB_MENUNAV
                call call_b
mi_nd:          ld a,(keyn)
                ld hl,mi_k
                cp (hl)
                jr z,mi_idle
                ld e,(hl)
                ld d,0
                ld hl,KEYQ
                add hl,de
                ld c,(hl)               ; la primera tecla nueva
                ld a,(mi_k)
                ld (keyn),a             ; se tira
                ld a,c
                cp 27
                jr z,mi_end
                cp 13
                jr nz,mi_idle
                ld hl,OVB_MENUSEL
                call call_b
                ld a,(mn_res)
                cp 255
                jr z,mi_idle            ; elemento desactivado
                ld l,a
                ld a,(mi_dlg)
                or a
                jr nz,mi_end            ; guardar/cargar: el resultado se queda en mn_res
                ld h,CTL>>8
                ld (hl),1
                jr mi_end
mi_idle:        ld hl,(ncyc)
                ld a,h
                or l
                call z,wait_frame
                jp mi_l
mi_end:         ld a,(mi_k)
                ld (keyn),a
                ld a,(mi_v)
                ld (VARS+19),a
                ld hl,OVB_MENUCLOSE
                call call_b
                jp OVL_FORCE
mn_res:         defb 0
mi_dlg:         defb 0
sv_ok:          defb 0

; save.game / restore.game: la lista de 9 ranuras es un menu de una sola entrada (overlay B, agib.asm) con el mismo bucle de menu.input; B lee y escribe los ficheros
; SAV/GAMEn.SAV (el estado: variables, banderas, inventario, objetos, cadenas...) y aqui se rehace la imagen y los objetos fijos al cargar
h_save_game:    ld hl,OVB_DLGSAVE
                jr sg_go
h_restore_game: ld hl,OVB_DLGLOAD
sg_go:          call call_b
                ld a,1
                ld (mi_dlg),a
                call mi_nk
                xor a
                ld (mi_dlg),a
                ld a,(stopf)
                or a
                ret nz                  ; pruebas: se acabaron los ciclos, la lista se queda
                ld hl,OVB_DLGDONE
                call call_b
                ld a,(sv_ok)
                or a
                ret z
                call rd_pic             ; se carga: la imagen, los rangos de los objetos fijos y se sale de la logica
                ld a,1
                ld (exitall),a
sg_t:           call OVL_SPRINIT
                jp OVL_FORCE
; la imagen y los objetos fijos otra vez (cargar partida, graphics)
rd_pic:         call OVL_SPCLR
                ld a,(lastpic)
                call dp_num
                ld ix,OBJ+24*32
                ld b,8
rp_l:           bit 2,(ix+O_F2)
                jr z,rp_n
                bit 0,(ix+O_F1)
                jr z,rp_n
                push bc
                call OVL_ADDPIC
                pop bc
rp_n:           ld de,32
                add ix,de
                djnz rp_l
                ret
mn_dir:         defb 0
mi_k:           defb 0
mi_v:           defb 0
mi_d:           defb 0

; echo.line: la ultima orden vuelve a la linea de entrada; cancel.line la borra; set.cursor.char: el caracter del cursor (solo se ve en modo real)
h_echo_line:    ld hl,OVC_ECHO
                jp call_c
h_cancel_line:  ld hl,OVC_CANCEL
                jp call_c
h_set_cursor_char: ld hl,OVC_CURSOR
                jp call_c
curchar:        defb '_'
LASTLN:         defs 41

h_accept_input: jp OVL_ACCEPT
h_prevent_input: jp OVL_PREVENT

; get.string(s, m, fila, columna, largo): modal. El mensaje y lo que se escribe salen en (fila, columna) (overlay B, solo en modo real); la linea que acaba con ENTER
; va a la cola de cadenas (ev_text lo redirige mientras gs_on) y de ahi a la cadena s. Cada vuelta es un ciclo (como las ventanas: pr_wait).
h_get_string:   ld a,(ARGS)
                cp 12
                ret nc
                ld a,(accin)
                ld (gs_acc),a
                ld a,1
                ld (accin),a
                ld (gs_on),a
                xor a
                ld (il_n),a
                ld (INBUF),a
gs_l:           ld a,(tqn)
                or a
                jr nz,gs_d
                ld hl,(ncyc)
                ld a,h
                or l
                jr nz,gs_w
                ld hl,OVB_GSDRAW
                call call_b
gs_w:           call pr_wait
                ld a,(stopf)
                or a
                jr z,gs_l
                ret
gs_d:           ld a,(ARGS)
                call strptr
                ex de,hl
                call tq_pop
                xor a
                ld (gs_on),a
                ld a,(gs_acc)
                ld (accin),a
                inc a
                ld (kb_dirty),a
                ret
gs_on:          defb 0
gs_acc:         defb 0

h_get_num:      ld hl,OVC_GETNUM
                jp call_c

h_word_to_string: ld a,(ARGS+1)
                cp 12
                ret nc
                call strptr
                ex de,hl
                push de
                ld a,(ARGS)
                call wt_get
                pop de
                jr c,ws_e
                ld b,40
ws_l:           ld a,(hl)
                or a
                jr z,ws_e
                ld (de),a
                inc hl
                inc de
                djnz ws_l
ws_e:           xor a
                ld (de),a
                ret

h_parse:        ld a,(ARGS)
                cp 12
                ret nc
                call strptr
                call parse_text
                xor a
                ld (said_done),a
                inc a
                ld (FLAGS+2),a
                ret

; HL = cadena -> DE (normalizada: minusculas, palabras separadas por un espacio)
norm:           ld bc,0                 ; B = espacio pendiente, C = ya hay una palabra
n_l:            ld a,(hl)
                inc hl
                or a
                jr z,n_e
                cp 33
                jr nc,n_c
                ld b,1
                jr n_l
n_c:            push af
                ld a,b
                and c
                jr z,n_ns
                ld a,' '
                ld (de),a
                inc de
n_ns:           pop af
                ld b,0
                ld c,1
                cp 'A'
                jr c,n_w
                cp 'Z'+1
                jr nc,n_w
                add a,32
n_w:            ld (de),a
                inc de
                jr n_l
n_e:            xor a
                ld (de),a
                ret

hc_compare_strings: ld a,(ARGS)
                cp 12
                jp nc,ret_false
                call strptr
                ld de,STMP
                call norm
                ld a,(ARGS+1)
                cp 12
                jp nc,ret_false
                call strptr
                ld de,STMP2
                call norm
                ld hl,STMP
                ld de,STMP2
cs_l:           ld a,(de)
                cp (hl)
                jp nz,ret_false
                or a
                jp z,ret_true
                inc hl
                inc de
                jr cs_l

; ---------------------------------------------------------------------
;  Parser
; ---------------------------------------------------------------------
; HL = texto (acabado en 0). Deja las palabras reconocidas en INW, su texto en WTEXT y v9 = la primera desconocida (1-based)
parse_text:     ld (pt_src),hl
                xor a
                ld (inwcnt),a
                ld (wcount),a
                ld (VARS+9),a
                ld (ntok),a
                ld (intok),a
                inc a
                ld (inwvalid),a
                ld hl,WTEXT
                ld (wtp),hl
                ld hl,(pt_src)
                ld de,TOKS
pt_l:           ld a,(hl)
                inc hl
                or a
                jp z,pt_end
                cp 'A'
                jr c,pt_n1
                cp 'Z'+1
                jr nc,pt_n1
                add a,32
pt_n1:          cp 39                   ; ' ` - \" . se quitan sin separar (dont = don't; el vocabulario va igual, agi_read.norm_word)
                jr z,pt_l
                cp 96
                jr z,pt_l
                cp 45
                jr z,pt_l
                cp 34
                jr z,pt_l
                cp 46
                jr z,pt_l
                cp '0'
                jr c,pt_sep
                cp '9'+1
                jr c,pt_ch
                cp 'a'
                jr c,pt_sep
                cp 'z'+1
                jr nc,pt_sep
pt_ch:          ld c,a
                ld a,(intok)
                or a
                jr nz,pt_cp
                ld a,(ntok)
                cp 16
                jr nc,pt_end
                push hl
                ld l,a
                ld h,0
                add hl,hl
                push de
                ld de,TOKP
                add hl,de
                pop de
                ld (hl),e
                inc hl
                ld (hl),d
                pop hl
                ld a,(ntok)
                inc a
                ld (ntok),a
                ld a,1
                ld (intok),a
pt_cp:          ld a,c
                ld (de),a
                inc de
                ld a,e
                cp TOKLIM
                jr nc,pt_end
                jr pt_l
pt_sep:         ld a,(intok)
                or a
                jr z,pt_l
                xor a
                ld (de),a
                inc de
                ld (intok),a
                jr pt_l
pt_end:         xor a
                ld (de),a
                ld (mi),a
pm_i:           ld a,(ntok)
                ld b,a
                ld a,(mi)
                cp b
                ret nc                  ; no quedan palabras
                ld c,a
                ld a,b
                sub c                   ; las que quedan
                cp MAXW+1
                jr c,pm_k
                ld a,MAXW
pm_k:           ld (mk),a
pm_try:         call build_phr
                call find_word
                or a
                jr nz,pm_hit
                ld hl,mk
                dec (hl)
                jr nz,pm_try
                ld a,(inwcnt)           ; ninguna: palabra desconocida, el analisis acaba
                inc a
                ld (VARS+9),a
                ld a,(mi)
                call tok_ptr
                jp wt_append
pm_hit:         ld hl,(fw_num)
                ld a,h
                or l
                jr z,pm_adv
                ld a,(inwcnt)
                cp 16
                jr nc,pm_w
                add a,a
                ld e,a
                ld d,0
                ld hl,INW
                add hl,de
                ld de,(fw_num)
                ld (hl),e
                inc hl
                ld (hl),d
                ld hl,inwcnt
                inc (hl)
pm_w:           ld hl,PHR
                call wt_append
pm_adv:         ld a,(mi)
                ld hl,mk
                add a,(hl)
                ld (mi),a
                jr pm_i

; A = indice de palabra -> HL = su texto (DE y B se conservan)
tok_ptr:        ld l,a
                ld h,0
                add hl,hl
                push de
                ld de,TOKP
                add hl,de
                pop de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ret

; PHR = las palabras mi .. mi+mk-1 separadas por un espacio
build_phr:      ld a,(mi)
                ld (bp_j),a
                ld a,(mk)
                ld b,a
                ld de,PHR
bp_l:           push bc
                ld a,(bp_j)
                call tok_ptr
bp_c:           ld a,(hl)
                or a
                jr z,bp_e
                ld (de),a
                inc hl
                inc de
                jr bp_c
bp_e:           ld hl,bp_j
                inc (hl)
                pop bc
                dec b
                jr z,bp_d
                ld a,' '
                ld (de),a
                inc de
                jr bp_l
bp_d:           xor a
                ld (de),a
                ret

; HL = cadena -> al final de WTEXT
wt_append:      ld de,(wtp)
wa_l:           ld a,(hl)
                ld (de),a
                inc de
                inc hl
                or a
                jr nz,wa_l
                ld (wtp),de
                ld hl,wcount
                inc (hl)
                ret

; A = indice -> HL = esa palabra; acarreo si no hay
wt_get:         ld hl,wcount
                cp (hl)
                jr nc,wg_none
                ld b,a
                ld hl,WTEXT
wg_l:           ld a,b
                or a
                ret z
wg_s:           ld a,(hl)
                inc hl
                or a
                jr nz,wg_s
                dec b
                jr wg_l
wg_none:        scf
                ret

; Busca PHR en WORDS.BIN (la ultima coincidencia manda, como el diccionario del modelo) -> A = 1 si esta; fw_num = su numero
find_word:      ld a,PG_WORDS
                call map_page
                xor a
                ld (fw_found),a
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
                ld de,PHR
fw_cm:          ld a,(de)
                cp (hl)
                jr nz,fw_ne
                or a
                jr z,fw_eq
                inc hl
                inc de
                jr fw_cm
fw_eq:          pop de
                ld (fw_num),de
                ld a,1
                ld (fw_found),a
                pop hl
                jr fw_l
fw_ne:          pop de
                pop hl
                jr fw_l
fw_done:        call unmap_win
                ld a,(fw_found)
                ret

; ---------------------------------------------------------------------
;  said
; ---------------------------------------------------------------------
hc_said:        ld a,(inwvalid)
                or a
                jp z,ret_false
                ld a,(said_done)
                or a
                jp nz,ret_false
                ld a,(VARS+9)
                or a
                jp nz,ret_false
                ld hl,(saidp)
                ld a,(saidk)
                ld b,a
                ld c,0                  ; C = posicion en la orden
hz_l:           ld a,b
                or a
                jr z,hz_end
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                cp $27
                jr nz,hz_n
                ld a,e
                cp $0F
                jr z,hz_ok              ; 9999: el resto vale
hz_n:           ld a,(inwcnt)
                cp c
                jp c,ret_false
                jp z,ret_false          ; la orden es mas corta
                ld a,d
                or a
                jr nz,hz_cmp
                ld a,e
                cp 1
                jr z,hz_nx              ; 1: cualquier palabra
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
                jp ret_false
hz_end:         ld a,(inwcnt)
                cp c
                jp nz,ret_false
hz_ok:          ld a,1
                ld (said_done),a
                ld (FLAGS+4),a
                jp ret_true

; ---------------------------------------------------------------------
;  Mensajes (LOGnnn.MSG) y su formato
; ---------------------------------------------------------------------
; A = logica, B = mensaje (1..), DE = destino de 256 bytes -> el texto sin formato (vacio si no hay)
msg_raw:        ld (mr_dst),de
                ld c,a
                ld a,b
                ld (mr_m),a
                ld a,c
                call mk_nm2
                ld hl,nm2
                call f_open
                cp $FF
                jr nz,mr_o
                ld de,(mr_dst)
                xor a
                ld (de),a
                ret
mr_o:           ld (fh2),a
                ld hl,mrb
                ld bc,1
                call f_read_n
                ld a,(mr_m)
                or a
                jr z,mr_empty
                ld b,a
                ld a,(mrb)
                ld (mrn),a
                cp b
                jr c,mr_empty
                ld l,b                  ; desplazamiento 1 + 2*(m-1)
                ld h,0
                dec hl
                add hl,hl
                inc hl
                ld a,(fh2)
                call f_seek
                ld hl,mrb
                ld bc,2
                ld a,(fh2)
                call f_read_n
                ld hl,(mrb)
                ld a,h
                or l
                jr z,mr_empty
                ex de,hl                ; DE = desplazamiento del texto
                ld a,(mrn)
                ld l,a
                ld h,0
                add hl,hl
                add hl,de               ; 1 + 2n + (off-1)
                ld a,(fh2)
                call f_seek
                ld hl,(mr_dst)
                ld bc,255
                ld a,(fh2)
                call f_read_n
                ld hl,(mr_dst)
                ld de,255
                add hl,de
                ld (hl),0
                ld a,(fh2)
                jp f_close
mr_empty:       ld de,(mr_dst)
                xor a
                ld (de),a
                ld a,(fh2)
                jp f_close

; "LOGnnn.MSG" para la logica A
mk_nm2:         ld b,'0'-1
mq_h:           inc b
                sub 100
                jr nc,mq_h
                add a,100
                ld hl,nm2+7
                ld (hl),b
                ld b,'0'-1
mq_t:           inc b
                sub 10
                jr nc,mq_t
                add a,10+'0'
                inc hl
                ld (hl),b
                inc hl
                ld (hl),a
                ret

; Mensaje B de la logica (bs_lg), con el formato (%vN %mN %sN %gN %wN), en DE (como mucho C caracteres + 0)
build_str:      ld (bs_dp),de
                ld a,c
                ld (bs_max),a
                xor a
                ld (bs_n),a
                ld a,(bs_lg)
                ld de,MSGBUF
                call msg_raw
                ld hl,MSGBUF
                ld (bs_sp),hl
bl_l:           ld hl,(bs_sp)
                ld a,(hl)
                inc hl
                ld (bs_sp),hl
                or a
                jp z,bs_end
                cp '%'
                jr z,bl_pct
                call bs_put
                jr bl_l
bl_pct:         ld a,(hl)
                cp 'v'
                jr z,bl_k
                cp 'm'
                jr z,bl_k
                cp 's'
                jr z,bl_k
                cp 'g'
                jr z,bl_k
                cp 'w'
                jr z,bl_k
bl_lit:         ld a,'%'
                call bs_put
                jr bl_l
bl_k:           ld (bs_kind),a
                inc hl
                ld a,(hl)
                sub '0'
                cp 10
                jr nc,bl_lit
                ld b,0
bl_d:           ld a,(hl)
                sub '0'
                cp 10
                jr nc,bl_dend
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
                jr bl_d
bl_dend:        ld a,(hl)
                cp '|'
                jr nz,bl_sub
                inc hl
                ld a,(hl)
                sub '0'
                cp 10
                jr c,bl_bd
                dec hl
                jr bl_sub
bl_bd:          ld a,(hl)
                sub '0'
                cp 10
                jr nc,bl_sub
                inc hl
                jr bl_bd
bl_sub:         ld (bs_sp),hl
                ld a,b
                ld (bs_num),a
                ld a,(bs_kind)
                cp 'v'
                jr z,sv_v
                cp 's'
                jr z,sv_s
                cp 'w'
                jr z,sv_w
                cp 'g'
                jr z,sv_g
                ld a,(bs_lg)
                jr sv_m
sv_g:           xor a
sv_m:           ld de,TMPM
                ld hl,bs_num
                ld b,(hl)
                call msg_raw
                ld hl,TMPM
                jr bs_puts
sv_v:           ld a,(bs_num)
                call getv
                call put_dec
                jp bl_l
sv_s:           ld a,(bs_num)
                cp 12
                jp nc,bl_l
                call strptr
                jr bs_puts
sv_w:           ld a,(bs_num)
                or a
                jp z,bl_l
                dec a
                call wt_get
                jp c,bl_l
bs_puts:        ld a,(hl)
                or a
                jp z,bl_l
                push hl
                call bs_put
                pop hl
                inc hl
                jr bs_puts
bs_end:         ld hl,(bs_dp)
                ld (hl),0
                ret

; A = caracter -> al texto de salida si cabe
bs_put:         ld c,a
                ld a,(bs_n)
                ld b,a
                ld a,(bs_max)
                cp b
                ret z
                ret c
                ld hl,(bs_dp)
                ld (hl),c
                inc hl
                ld (bs_dp),hl
                ld a,b
                inc a
                ld (bs_n),a
                ret

; A = numero 0-255 -> cifras sin ceros a la izquierda
put_dec:        ld (pd_v),a
                xor a
                ld (pd_s),a
                ld b,100
                call pd_d
                ld b,10
                call pd_d
                ld a,(pd_v)
                add a,'0'
                jp bs_put
pd_d:           ld a,(pd_v)
                ld c,0
pd_1:           cp b
                jr c,pd_o
                sub b
                inc c
                jr pd_1
pd_o:           ld (pd_v),a
                ld a,c
                or a
                jr nz,pd_p
                ld a,(pd_s)
                or a
                ret z
pd_p:           ld a,1
                ld (pd_s),a
                ld a,c
                add a,'0'
                jp bs_put

; ---------------------------------------------------------------------
;  Resumen de las cadenas, el parser y las teclas (para comparar con el modelo)
; ---------------------------------------------------------------------
; HL = suma de (caracter + 1) de las 12 cadenas
strsum:         ld de,0
                xor a
                ld (ss_i),a
ss_n:           ld a,(ss_i)
                push de
                call strptr
                pop de
ss_c:           ld a,(hl)
                inc hl
                or a
                jr z,ss_e
                inc a
                add a,e
                ld e,a
                jr nc,ss_c
                inc d
                jr ss_c
ss_e:           ld a,(ss_i)
                inc a
                ld (ss_i),a
                cp 12
                jr c,ss_n
                ex de,hl
                ret

; HL = suma de lo que dependa de la orden pendiente, el parser y las teclas
miscsum:        ld hl,0
                ld a,(inwvalid)
                or a
                jr z,ms_1
                ld a,(inwcnt)
                inc a
                call adda
                ld a,(inwcnt)
                or a
                jr z,ms_1
                add a,a
                ld b,a
                ld de,INW
ms_w:           ld a,(de)
                inc de
                call adda
                djnz ms_w
ms_1:           ld a,(said_done)
                or a
                jr z,ms_2
                ld a,97
                call adda
ms_2:           ld a,(keyn)
                ld b,a
                or a
                jr z,ms_3
ms_k:           ld a,13
                call adda
                djnz ms_k
ms_3:           ld a,(tqn)
                ld b,a
                or a
                jr z,ms_4
ms_t:           ld a,5
                call adda
                djnz ms_t
ms_4:           ld a,(wcount)
                ld b,a
                or a
                jr z,ms_5
ms_x:           ld a,3
                call adda
                djnz ms_x
ms_5:           ld de,CTL
                ld b,0
ms_c:           ld a,(de)
                or a
                jr z,ms_c1
                ld a,7
                call adda
ms_c1:          inc e
                djnz ms_c
                ret
