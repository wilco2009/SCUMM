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
                ld (pt_src),hl
                ld hl,OVC_PARSETEXT
                call call_c
                xor a
                ld (said_done),a
                ld c,13                 ; el ENTER que la envio: v19 = 13 (si no tiene controlador, como en el ciclo de ScummVM)
                jr kp_m
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
kp_m:           ld a,c                  ; cycle.cpp: v19 solo si la tecla no tiene controlador (handleController)
                and 127
                ld l,a
                ld h,0
                add hl,hl
                ld de,KEYMAP
                add hl,de
                inc hl
                ld a,(hl)
                or a
                jr nz,kp_c
                ld a,c
                ld (VARS+19),a
                ret
kp_c:           dec hl
                ld a,(hl)
                ld l,a
                ld h,CTL>>8
                ld (hl),1
                ret

h_set_key:      ld a,(ARGS)             ; ascii, scan, controlador
                or a
                jr nz,sk_a
                ld a,(ARGS+1)           ; teclas de funcion F4..F10 (62..68, salvo F9 y F3) viven en codigos de control (teclas 2/3 y ENTER+6..9 del ZX81)
                ld hl,sk_fn
                ld b,6
sk_f:           cp (hl)
                inc hl
                jr z,sk_g
                inc hl
                djnz sk_f
                ret
sk_g:           ld a,(hl)
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
sk_fn:          defb 62,29,63,28,64,31,65,30,66,25,68,26   ; F4 F5 F6 F7 F8 F10

hc_controller:  ld a,(ARGS)
                ld l,a
                ld h,CTL>>8
                ld a,(hl)
                or a
                jp z,ret_false
                jp ret_true

; condHaveKey: con la tecla del ciclo (v19) distinta de 0 es cierta, sin consumirla (la logica puede ponerla a 0, p. ej. tras el ENTER de una frase); si no, hay que
; esperar una tecla nueva: en la pantalla de texto un bucle apretado (ayuda: la 2a llamada del ciclo sin tecla) espera la tecla
hc_have_key:    ld a,(VARS+19)
                or a
                jp nz,ret_true
                ld a,(txtm)
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
; A = indice (0-NSTR-1) -> HL = STRS + 41*A
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

h_set_string:   ld a,(ARGS)             ; cmdSetString: el texto sin formato (strlcpy de 40: 39 caracteres)
                cp NSTR
                ret nc
                call strptr
                push hl
                ld a,(ARGS+1)
                ld b,a
                ld a,(curlg)
                ld de,MSGBUF
                call msg_raw
                pop de
                ld hl,MSGBUF
                ld b,39
hs_l:           ld a,(hl)
                ld (de),a
                or a
                ret z
                inc hl
                inc de
                djnz hs_l
                xor a
                ld (de),a
                ret

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
h_graphics:     ld hl,OVC_GFXFIX
                call call_c
hg_go:          xor a
                ld (txtm),a
                ld a,(picvalid)         ; sin imagen dibujada no hay nada que rehacer
                or a
                jp z,sg_t
                call rd_pic
                jp sg_t
; overlay.pic: la imagen de la sala con la que se le superpone ya hecha (PIC/PICAnn.GFX, TOOLS/agi2hr.py), redibujada como graphics
h_overlay_pic:  ld a,1
                ld (ovl_on),a
                jp hg_go
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
h_clear_text_rect: ld hl,OVB_CLRRECT      ; (overlay B)
                jp call_b
h_clear_lines:  ld hl,OVB_CLEAR
                jp call_b
h_set_text_attribute: ld hl,OVB_ATTR
                jp call_b
h_status_line_on: ld hl,OVB_SON
                jp call_b
h_status_line_off: ld hl,OVB_SOFF
                jp call_b
; print: ventana de mensaje (overlay B) y espera de una tecla
; close.window / show.pic (ScummVM closeWindow; show.pic ademas apaga VM_FLAG_OUTPUT_MODE): quita la ventana que dejo un print no bloqueante
h_show_pic:     xor a
                ld (FLAGS+15),a
h_close_window: ld a,(win_act)
                or a
                ret z
                xor a
                ld (win_act),a
                ld hl,OVB_BOXCLOSE
                call call_b
                jp OVL_FORCE
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
pg_w:           ld a,(win_act)          ; bandera 15 (VM_FLAG_OUTPUT_MODE): la ventana queda abierta y no se espera (t_prt)
                or a
                ret nz
                ld a,1
                ld (pw_ent),a
                call pr_wait
                xor a
                ld (pw_ent),a
                ld hl,0
                ld (pw_lim),hl
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
                jr nz,pw_key
                ld a,(gs_on)            ; get.string: tambien acaba cuando llega una linea (aunque no sea por teclado)
                or a
                jr z,pw_nt
                ld a,(tqn)
                or a
                ret nz
pw_nt:          ld hl,(pw_lim)          ; temporizador de la ventana (v21): al llegar a 0 se cierra sin tecla
                ld a,h
                or l
                jr z,pw_nl
                dec hl
                ld (pw_lim),hl
                ld a,h
                or l
                jr z,pw_d
pw_nl:          ld hl,(ncyc)
                ld a,h
                or l
                call z,wait_frame
                jr pw_l
pw_key:         ld a,(pw_ent)           ; ventana de mensaje (messageBox_KeyPress): solo ENTER y ESC la cierran; las demas teclas se descartan
                or a
                jr z,pw_d
                ld a,(keyn)
                dec a
                ld e,a
                ld d,0
                ld hl,KEYQ
                add hl,de
                ld a,(hl)
                cp 13
                jr z,pw_d
                cp 27
                jr z,pw_d
                ld a,(pw_k)
                ld (keyn),a
                jr pw_nt
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
pw_lim:         defw 0
pw_ent:         defb 0
win_act:        defb 0

; ---------------------------------------------------------------------
;  Menus: set.menu / set.menu.item / enable.item / disable.item guardan en el overlay B (agib.asm); menu.input es modal como print: cada vuelta es un ciclo, las
;  flechas (cambios de dirhold a 1, 3, 5, 7) mueven, ENTER elige (enciende el controlador del elemento) y ESC cierra; la tecla no llega a la logica.
; ---------------------------------------------------------------------
h_set_menu:     ld hl,OVF_SETMENU
                jp call_f
h_set_menu_item: ld hl,OVF_SETITEM
                jp call_f
h_submit_menu:  ret
h_enable_item:  ld hl,OVF_ENABLE
                jp call_f
h_disable_item: ld hl,OVF_DISABLE
                jp call_f

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
                ld hl,OVF_MENUOPEN
                call call_f
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
                ld hl,OVF_MENUNAV
                call call_f
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
                ld a,(mi_dlg)
                cp 2
                jr z,mi_end             ; inventario sin elegir: cualquier tecla
                ld a,c
                cp 27
                jr z,mi_end
                cp 13
                jr nz,mi_idle
                ld hl,OVF_MENUSEL
                call call_f
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
                ld hl,OVF_MENUCLOSE
                call call_f
                ld hl,OVB_STATUS        ; la barra de estado se redibuja ya (puede abrirse una ventana antes de acabar el ciclo)
                call call_b
                jp OVL_FORCE
mn_res:         defb 0
mi_dlg:         defb 0
sv_ok:          defb 0

; save.game / restore.game: la lista de 9 ranuras es un menu de una sola entrada (overlay B, agib.asm) con el mismo bucle de menu.input; B lee y escribe los ficheros
; SAV/GAMEn.SAV (el estado: variables, banderas, inventario, objetos, cadenas...) y aqui se rehace la imagen y los objetos fijos al cargar
h_save_game:    xor a
                jr sg_go
h_restore_game: ld a,1
sg_go:          ld (sf_mode),a
                ld hl,OVD_READ
                call call_d
                ld hl,OVF_DLGLIST
                call call_f
                ld a,1
                ld (mi_dlg),a
                call mi_nk
                xor a
                ld (mi_dlg),a
                ld a,(stopf)
                or a
                ret nz                  ; pruebas: se acabaron los ciclos, la lista se queda
                ld hl,OVF_DLGDONE
                call call_f
                ld a,(mn_res)
                inc a
                ret z                   ; ESC
                ld a,(sf_mode)
                or a
                jr nz,sg_cf
                ld hl,OVD_PREP          ; guardar: la descripcion (get.string con el texto previo y ESC que cancela)
                call call_d
                ld a,1
                ld (gs_cust),a
                ld de,MSGBUF
                call gs_go
                ld a,(stopf)
                or a
                ret nz
                ld hl,OVB_BOXCLOSE      ; la ventana de la descripcion se quita
                call call_b
                ld hl,gs_cust
                ld a,(hl)
                ld (hl),0
                cp 2
                ret z
sg_cf:          ld hl,OVD_CONF
                call call_d
                ld a,3
                call pr_rawgo
                ld a,(stopf)
                or a
                ret nz
                ld a,(pw_last)
                cp 13
                ret nz
                ld hl,OVD_DO
                call call_d
                ld a,(sv_ok)
                or a
                ret z
                ld hl,OVF_MENUON
                call call_f
                call rd_pic             ; se carga: la imagen, los rangos de los objetos fijos y se sale de la logica
                ld a,1
                ld (exitall),a
sg_t:           call OVL_SPRINIT
                jp OVL_FORCE
; la imagen y los add.to.pic otra vez (cargar partida, graphics)
rd_pic:         call OVL_SPCLR
                ld a,(lastpic)
                call dp_num
                ld a,(st_n)
                or a
                ret z
                ld b,a
                ld hl,STL
rp_l:           push bc
                push hl
                ld de,SCR+O_VIEW
                ld bc,6
                ldir
                call add_pic_go
                pop hl
                ld de,6
                add hl,de
                pop bc
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
                cp NSTR
                ret nc
                call strptr
                ex de,hl
                ld a,(ARGS+4)           ; stringMaxLen (ed_ nunca pasa de 40, TEXT_STRING_MAX_SIZE)
                ld (il_max),a
                xor a
                ld (il_n),a
                ld (INBUF),a
gs_go:          ld (gs_dst),de          ; DE = donde va la linea (il_n e INBUF ya preparados)
                ld a,(accin)
                ld (gs_acc),a
                ld a,1
                ld (accin),a
                ld (gs_on),a
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
                jr z,gs_k
                ret
gs_k:           ld a,(gs_cust)          ; descripcion de una partida: ESC cancela
                or a
                jr z,gs_l
                ld a,(tqn)
                or a
                jr nz,gs_l
                ld a,(pw_last)
                cp 27
                jr nz,gs_l
                ld a,2
                ld (gs_cust),a
                jr gs_f
gs_d:           ld de,(gs_dst)
                call tq_pop
gs_f:           ld a,IL_MAX
                ld (il_max),a
                xor a
                ld (gs_on),a
                ld a,(gs_acc)
                ld (accin),a
                inc a
                ld (kb_dirty),a
                ret
gs_on:          defb 0
gs_acc:         defb 0
gs_cust:        defb 0
gs_dst:         defw 0
sf_mode:        defb 0
st_on:          defb 0
st_valid:       defb 0

; get.num(m, v): modal como get.string (el mensaje en la fila de entrada, hasta 3 caracteres); v = atoi de lo escrito (modulo 256), cmdGetNum
h_get_num:      ld a,(ARGS+1)
                ld (gn_v),a
                ld a,(ARGS)
                ld (ARGS+1),a
                ld a,22
                ld (ARGS+2),a
                xor a
                ld (ARGS+3),a
                ld (il_n),a
                ld (INBUF),a
                ld (STMP),a
                ld a,3
                ld (il_max),a
                ld de,STMP
                call gs_go
                ld a,(stopf)
                or a
                ret nz
                ld hl,STMP
                ld b,0
gn_l:           ld a,(hl)
                sub '0'
                cp 10
                jr nc,gn_e
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
                jr gn_l
gn_e:           ld a,(gn_v)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret
gn_v:           defb 0

h_word_to_string: ld a,(ARGS+1)
                cp NSTR
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

h_parse:        ld hl,OVC_PARSE         ; en el overlay C (el nucleo no tiene sitio)
                jp call_c

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

hc_compare_strings: ld hl,OVC_CMPSTR    ; en el overlay C (NZ = iguales)
                call call_c
                jp nz,ret_true
                jp ret_false

; ---------------------------------------------------------------------
;  Parser
; ---------------------------------------------------------------------
; (el parser, parse_text, esta en el overlay C: agic.asm)
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

; ---------------------------------------------------------------------
;  said
; ---------------------------------------------------------------------
; said(...): el codigo (testSaid de ScummVM) esta en el overlay C; el resultado vuelve en said_res
hc_said:        ld hl,OVC_SAID
                call call_c
                ld a,(said_res)
                ret
said_res:       defb 0

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
bs_fmt:         ld hl,MSGBUF
                ld (bs_sp),hl
                xor a
                ld (bs_fd),a
                inc a
                ld (bs_md),a            ; bufer de mensaje ocupado: el de la raiz (MSGBUF); %m usa SUBBUF
bl_l:           ld hl,(bs_sp)
                ld a,(hl)
                inc hl
                or a
                jr z,bl_pop
                cp '%'
                jr z,bl_pct
                cp 92                   ; \ : el siguiente caracter va tal cual
                jr nz,bl_c
                ld a,(hl)
                or a
                jr z,bl_pop
                inc hl
bl_c:           ld (bs_sp),hl
                call bs_put
                jr bl_l
bl_pop:         ld a,(bs_fd)            ; acaba esta fuente: sigue la que la llamo
                or a
                jp z,bs_end
                dec a
                ld (bs_fd),a
                add a,a
                add a,a
                ld l,a
                ld h,0
                ld de,BSFR
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (bs_sp),de
                ld a,(hl)
                ld (bs_lg),a
                inc hl
                ld a,(hl)
                ld (bs_md),a
                jr bl_l
; stringPrintf de ScummVM: %vN[|W], %mN, %sN (ambos con formato, recursivos), %gN y %wN (tal cual); otro: se traga la letra y las cifras
bl_pct:         ld a,(hl)
                or a
                jr z,bl_pop
                inc hl
                ld (bs_kind),a
                call bs_dig
                ld a,99
                ld (bs_w),a
                ld a,(bs_kind)
                cp 'v'
                jr nz,bl_d2
                ld a,(hl)
                cp '|'
                jr nz,bl_d2
                inc hl
                ld a,b
                ld (bs_num),a
                call bs_dig
                ld a,b
                ld (bs_w),a
                ld a,(bs_num)
                ld b,a
bl_d2:          ld (bs_sp),hl
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
                cp 'm'
                jr z,sv_m
                jp bl_l
sv_g:           ld a,(bs_md)
                cp 2
                jp nc,bl_l
                xor a
                jr sv_m2
sv_m:           ld a,(bs_md)
                cp 2
                jp nc,bl_l              ; no hay otro bufer de mensaje: se ignora
                ld a,(bs_lg)
sv_m2:          ld de,SUBBUF
                ld hl,bs_num
                ld b,(hl)
                call msg_raw
                ld hl,SUBBUF
                ld a,(bs_kind)
                cp 'g'
                jr z,bs_puts            ; %g: el mensaje de la logica 0 sin formato
                call bs_push
                jp c,bl_l
                ld a,2
                ld (bs_md),a
                jp bl_l
sv_s:           ld a,(bs_num)
                cp NSTR
                jp nc,bl_l
                call strptr
                call bs_push
                jp bl_l
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
; %vN|W: los W ultimos digitos del valor con 15 cifras (ceros a la izquierda); sin |W, sin ceros
sv_v:           ld a,(bs_num)
                call getv
                ld (pd_v),a
                ld a,(bs_w)
                cp 99
                jr nz,sd_w
                ld a,(pd_v)
                call put_dec
                jp bl_l
sd_w:           ld hl,bs_dg
                ld a,(pd_v)
                ld c,0
sd_1:           cp 100
                jr c,sd_2
                sub 100
                inc c
                jr sd_1
sd_2:           ld (hl),c
                inc hl
                ld c,0
sd_3:           cp 10
                jr c,sd_4
                sub 10
                inc c
                jr sd_3
sd_4:           ld (hl),c
                inc hl
                ld (hl),a
                ld a,(bs_w)
                cp 16
                jr c,sd_5
                ld a,15
sd_5:           ld b,a
sd_e:           ld a,b
                or a
                jp z,bl_l
                dec b
                ld a,b
                cp 3
                ld a,'0'
                jr nc,sd_p
                ld a,b
                ld e,a
                ld d,0
                ld hl,bs_dg+2
                or a
                sbc hl,de
                ld a,(hl)
                add a,'0'
sd_p:           push bc
                call bs_put
                pop bc
                jr sd_e
; HL = cifras -> B = su valor (strtoul, modulo 256) y HL tras ellas
bs_dig:         ld b,0
bd_l:           ld a,(hl)
                sub '0'
                cp 10
                ret nc
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
                jr bd_l
; HL = nueva fuente de texto (con formato): se apunta la actual (bs_sp, bs_lg, bs_md) en la pila de fuentes; acarreo si no cabe
bs_push:        ld a,(bs_fd)
                cp BSFRN
                jr c,bp_ok
                scf
                ret
bp_ok:          push hl
                add a,a
                add a,a
                ld l,a
                ld h,0
                ld de,BSFR
                add hl,de
                ld de,(bs_sp)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(bs_lg)
                ld (hl),a
                inc hl
                ld a,(bs_md)
                ld (hl),a
                ld hl,bs_fd
                inc (hl)
                pop hl
                ld (bs_sp),hl
                or a
                ret
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
                cp NSTR
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
