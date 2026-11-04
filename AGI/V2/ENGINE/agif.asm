; =====================================================================
;  agif.asm - overlay F: menus (set.menu, menu.input) y las listas de guardar / cargar / inventario. Pagina PG_OVF, en el bloque 1 solo mientras se
;  ejecuta (call_f). Antes estaba en el overlay B (agib.asm), que se quedo sin sitio. La linea de texto, el fondo y la ventana (agitx.inc) estan en los dos.
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_setmenu            ; OVF_SETMENU
                jp t_setitem            ; OVF_SETITEM
                jp t_enable             ; OVF_ENABLE
                jp t_disable            ; OVF_DISABLE
                jp t_menuopen           ; OVF_MENUOPEN
                jp t_menunav            ; OVF_MENUNAV
                jp t_menusel            ; OVF_MENUSEL
                jp t_menuclose          ; OVF_MENUCLOSE
                jp t_dlglist            ; OVF_DLGLIST
                jp t_menuon             ; OVF_MENUON
                jp t_dlgdone            ; OVF_DLGDONE
                jp t_menureset          ; OVF_MENURESET
                jp t_dlginv             ; OVF_DLGINV

TXT             equ TMPM
pr_l0:          defb 0
pr_ln:          defb 0
pr_l:           defb 0
pr_k:           defb 0

;  Menus. Los textos (36 caracteres como mucho) se copian a la reserva mp_pool al hacer set.menu / set.menu.item: mn_tab (titulo, primer elemento, cuantos) e it_tab
;  (texto, controlador, activado). menu.input (nucleo) los abre con la barra en la fila 0 (blanco, el titulo elegido en inverso) y, bajo el titulo, una lista de
;  elementos en las filas 1... (el elegido en inverso, los desactivados en gris), alineada a la celda del titulo sin salirse; al cerrar se devuelve la imagen limpia
;  (t_boxclose) y la barra de estado. Mismo resultado que Interp.draw_menu() de TOOLS/agi_vm.py.
; ---------------------------------------------------------------------
MN_MAX          equ 10
IT_MAX          equ 60
MP_SIZE         equ 1500
MP_LIM          equ mp_pool+MP_SIZE-40

; restart.game: los menus que definio el juego, la barra de estado y los colores del texto vuelven al arranque
t_menureset:    ret                     ; (OVB_MENURESET no se llama: los menus sobreviven a restart.game, solo se reactivan sus elementos)

; mensaje ARGS[0] -> a la reserva (mp_last = donde queda); C si no cabe
mp_text:        ld hl,(mp_free)
                ld de,MP_LIM
                or a
                sbc hl,de
                jr c,mt_ok
                scf
                ret
mt_ok:          ld a,(ARGS)
                ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,250
                call build_str
mp_cp:          ld hl,(mp_free)         ; TXT a la reserva
                ld (mp_last),hl
                ld de,TXT
                ld b,36
mt_l:           ld a,(de)
                or a
                jr z,mt_z
                ld (hl),a
                inc hl
                inc de
                djnz mt_l
mt_z:           ld (hl),0
                inc hl
                ld (mp_free),hl
                or a
                ret

; A = numero de menu -> HL = su entrada de mn_tab
mn_pa:          ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,mn_tab
                add hl,de
                ret

; HL = cadena -> A = largo (HL se conserva)
mp_len:         push hl
                ld b,0
ml_l:           ld a,(hl)
                or a
                jr z,ml_d
                inc hl
                inc b
                jr ml_l
ml_d:           pop hl
                ld a,b
                ret

t_setmenu:      ld a,(mn_n)
                cp MN_MAX
                ret nc
                call mp_text
                ret c
                ld a,(mn_n)
                call mn_pa
                ld de,(mp_last)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(it_n)
                ld (hl),a
                inc hl
                ld (hl),0
                ld hl,mn_n
                inc (hl)
                ret

t_setitem:      ld a,(mn_n)
                or a
                ret z
                ld a,(it_n)
                cp IT_MAX
                ret nc
                call mp_text
                ret c
                call mi_tag
                ld a,(it_n)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab
                add hl,de
                ld de,(mp_last)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(ARGS+1)
                ld (hl),a
                inc hl
                ld (hl),1
                ld hl,it_n
                inc (hl)
                ld a,(mn_n)
                dec a
                call mn_pa
                inc hl
                inc hl
                inc hl
                inc (hl)
                ret

; el texto de la opcion lleva la tecla del PC (<F5>, <Alt-Z>...): F5 y F7 pasan a <2> y <3> (las teclas del ZX81); las demas se quitan, con los espacios que las separan
mi_tag:         ld hl,(mp_last)
mg_f:           ld a,(hl)
                or a
                ret z
                cp '<'
                jr z,mg_t
                inc hl
                jr mg_f
mg_t:           ld d,h
                ld e,l
                inc hl
                ld a,(hl)
                cp 'F'
                jr nz,mg_cut
                inc hl
                ld a,(hl)
                ld c,'2'
                cp '5'
                jr z,mg_k
                ld c,'3'
                cp '7'
                jr nz,mg_cut
mg_k:           inc hl
                ld a,(hl)
                cp '>'
                jr nz,mg_cut
                ex de,hl
                inc hl
                ld (hl),c
                inc hl
                ld (hl),'>'
                inc hl
                ld (hl),0
                ret
mg_cut:         ex de,hl
mg_s:           dec hl
                ld a,(hl)
                cp ' '
                jr z,mg_s
                inc hl
                ld (hl),0
                ret

t_enable:       ld a,1
                jr en_go
t_disable:      xor a
en_go:          ld (en_v),a
                ld a,(it_n)
                or a
                ret z
                ld b,a
                ld hl,it_tab+2
                ld a,(ARGS)
                ld c,a
en_l:           ld a,(hl)
                cp c
                jr nz,en_n
                inc hl
                ld a,(en_v)
                ld (hl),a
                dec hl
en_n:           inc hl
                inc hl
                inc hl
                inc hl
                djnz en_l
                ret

; Columna del titulo elegido (m_col), elementos (m_first, m_cnt), el texto mas largo (m_max), m_w = ancho en caracteres y el rectangulo de la lista (pr_*)
mn_geom:        xor a
                ld (m_col),a
                ld a,(m_only)
                cp 255
                jr nz,mg_c0
                ld a,(m_sel)
                or a
                jr z,mg_c0
                ld b,a
                ld hl,mn_tab
mg_cl:          push bc
                push hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                call mp_len
                IF GFX4
                inc a
                ELSE
                add a,2
                ENDIF
                ld hl,m_col
                add a,(hl)
                ld (hl),a
                pop hl
                inc hl
                inc hl
                inc hl
                inc hl
                pop bc
                djnz mg_cl
mg_c0:          ld a,(m_sel)
                call mn_pa
                inc hl
                inc hl
                ld a,(hl)
                ld (m_first),a
                inc hl
                ld a,(hl)
                ld (m_cnt),a
                xor a
                ld (m_max),a
                ld a,(m_cnt)
                or a
                jr z,mg_n0
                ld b,a
                ld a,(m_first)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab
                add hl,de
mg_ml:          push bc
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                inc hl
                inc hl                  ; siguiente elemento
                push hl
                ex de,hl
                call mp_len
                ld hl,m_max
                cp (hl)
                jr c,mg_mn
                ld (hl),a
mg_mn:          pop hl
                pop bc
                djnz mg_ml
mg_n0:          ld a,(m_max)
                add a,2
                ld (m_w),a
                IF GFX4
                ld (pr_bw),a            ; 160w: una columna por caracter
                ld a,(m_col)
                ld c,a
                ELSE
                ld b,a
                add a,a
                add a,b
                add a,a                 ; 6 * ancho
                add a,7
                rrca
                rrca
                rrca
                and 31
                ld (pr_bw),a
                ld a,(m_col)
                ld c,a
                add a,a
                add a,c
                add a,a
                rrca
                rrca
                rrca
                and 31
                ld c,a                  ; celda del titulo
                ENDIF
                ld a,TCELL
                ld hl,pr_bw
                sub (hl)
                ld d,a
                ld a,c
                cp d
                jr c,mg_x
                ld a,d
mg_x:           ld (pr_cxl),a
                ld a,1
                ld (pr_top),a
                ld a,8
                ld (pr_l0),a
                ld a,(m_cnt)
                add a,a
                add a,a
                add a,a
                ld (pr_ln),a
                ret

; La barra de la fila 0
mn_bar:         ld a,1
                ld (dl_nobg),a
                xor a
                ld (dl_row),a
                ld a,15
                call fill_row
                ld a,(mn_n)
                ld (m_je),a
                ld a,(m_only)
                cp 255
                jr z,mb_a
                ld (m_j),a
                inc a
                ld (m_je),a
                jr mb_b
mb_a:           xor a
                ld (m_j),a
mb_b:           xor a
                ld (m_c2),a
mb_l:           ld a,(m_j)
                ld hl,m_je
                cp (hl)
                jr nc,mb_e
                call mn_pa
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,TXT
                IF GFX4=0
                ld (hl),' '
                inc hl
                ENDIF
                ld c,0
mb_cp:          ld a,(de)
                or a
                jr z,mb_z
                ld (hl),a
                inc hl
                inc de
                inc c
                jr mb_cp
mb_z:
                IF GFX4
                ld a,c                  ; 160w (ScummVM): el titulo tal cual, sin espacios de mas
                ELSE
                ld (hl),' '
                ld a,c
                add a,2
                ENDIF
                ld (dl_n),a
                ld a,(m_j)
                ld hl,m_sel
                cp (hl)
                ld b,0
                ld c,15
                jr nz,mb_ns
                ld b,15
                ld c,0
mb_ns:          ld a,b
                call t_chroma
                ld (dl_fg),a
                ld a,c
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
                ld (dl_ptr),hl
                xor a
                ld (dl_row),a
                ld a,(m_c2)
                ld (dl_col),a
                call draw_line
                ld a,(dl_n)
                ld hl,m_c2
                add a,(hl)
                IF GFX4
                inc a                   ; el siguiente titulo, un espacio despues
                ENDIF
                ld (hl),a
                ld hl,m_j
                inc (hl)
                jr mb_l
mb_e:           xor a
                ld (dl_nobg),a
                ret

; La lista del menu elegido (m_it = el marcado)
mn_drop:        call mn_geom
                IF GFX4
                ld a,(mi_dlg)           ; menu principal: los sprites siguen, recortados contra la lista (filas 1 a m_cnt); 2 = hay que rearmarlos (mi_clip). Guardar/cargar e inventario no.
                or a
                jr nz,md_nc
                ld a,2
                ld (clip_on),a
                ld a,32
                ld (clip_y0),a
                ld b,a
                ld a,(m_cnt)
                add a,a
                add a,a
                add a,a
                add a,b
                ld (clip_y1),a
                ld a,(pr_cxl)
                add a,a
                add a,a
                add a,b
                ld (clip_x0),a
                ld b,a
                ld a,(pr_bw)
                add a,a
                add a,a
                add a,b
                ld (clip_x1),a
md_nc:
                ENDIF
                xor a
                ld (m_i),a
md_l:           ld a,(m_i)
                ld hl,m_cnt
                cp (hl)
                ret nc
                call mn_item
                ld hl,m_i
                inc (hl)
                jr md_l

; El elemento m_i de la lista
mn_item:        ld a,(m_first)
                ld hl,m_i
                add a,(hl)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab
                add hl,de
                ld (m_ep),hl
                inc hl
                inc hl
                inc hl
                ld a,(hl)               ; activado
                or a
                ld b,0                  ; tinta
                jr nz,mi_e
                ld b,8
mi_e:           ld a,(m_i)
                ld hl,m_it
                cp (hl)
                ld c,15                 ; papel
                jr nz,mi_ns
                ld c,0
                ld a,b
                cp 8
                jr z,mi_ns
                ld b,15
mi_ns:          ld a,b
                call t_chroma
                ld (dl_fg),a
                ld b,a
                ld a,c
                call t_chroma
                ld (dl_bg),a
                add a,a
                add a,a
                add a,a
                add a,a
                or b
                ld (m_attr),a
                ld a,(m_i)              ; relleno de las 8 lineas de la fila
                inc a
                add a,a
                add a,a
                add a,a
                ld (m_l),a
                ld a,8
                ld (m_k),a
                IF GFX4
                ld a,(m_attr)           ; relleno de la fila del elemento: espacios blancos (fondo distinto de 0) o negros
                and $F0
                ld c,32
                jr z,mfg_c
                ld c,160
mfg_c:          ld hl,pr_cxl
                ld b,(hl)
                ld a,(pr_bw)
                ld e,a
                ld a,(m_i)
                inc a
                call tp_fill
                ENDIF
                IF GFX4=0
mf_l:           ld a,(m_l)
                call pr_addr
                ld de,HR_BM
                add hl,de
                ld a,(pr_bw)
                ld b,a
                xor a
mf_b:           ld (hl),a
                inc hl
                djnz mf_b
                ld a,(m_l)
                call pr_addr
                ld de,HR_ATT
                add hl,de
                ld a,(pr_bw)
                ld b,a
                ld a,(m_attr)
mf_a:           ld (hl),a
                inc hl
                djnz mf_a
                ld hl,m_l
                inc (hl)
                ld hl,m_k
                dec (hl)
                jr nz,mf_l
                ENDIF
                ld hl,(m_ep)            ; el texto: " " + texto + relleno + " "
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,TXT
                ld (hl),' '
                inc hl
                ld c,0
mi_cp:          ld a,(de)
                or a
                jr z,mi_pd
                ld (hl),a
                inc hl
                inc de
                inc c
                jr mi_cp
mi_pd:          ld a,(m_max)
                sub c
                jr z,mi_en
                ld b,a
mi_pl:          ld (hl),' '
                inc hl
                djnz mi_pl
mi_en:          ld (hl),' '
                ld a,(m_w)
                ld (dl_n),a
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(m_i)
                inc a
                ld (dl_row),a
                ld a,(pr_cxl)
                add a,a
                add a,a
                add a,a
                ld (dl_x0),a
                ld a,1
                ld (dl_nobg),a
                call draw_line_px
                xor a
                ld (dl_nobg),a
                ret

t_menuopen:
                IF GFX4
                ld a,1
                call tp_save            ; lo que habia bajo la barra y la lista
                ENDIF
                ld a,(iv_on)
                or a
                jp nz,iv_open
                ld a,(mn_n)
                or a
                jr nz,mo_ok
                ld a,254
                ld (mn_res),a
                ret
mo_ok:          ld a,255
                ld (mn_res),a
                ld a,(m_start)
                ld (m_it),a
                ld a,(m_only)
                cp 255
                jr nz,mo_sx
                ld a,(mm_sel)           ; el menu principal recuerda el menu de la ultima vez (_lastSelectedMenuNr) y el elemento de cada menu (selectedItemNr)
                ld (m_sel),a
                call mm_ld
                jr mo_gg
mo_sx:          ld (m_sel),a
mo_gg:          call mn_bar
                jp mn_drop

; La imagen limpia bajo la lista
mn_restore:     ld a,(pr_ln)
                or a
                ret z
                jp t_boxclose

; mn_dir = 1 arriba, 3 derecha, 5 abajo, 7 izquierda
t_menunav:      ld a,(iv_on)
                or a
                jp nz,iv_nav
                ld a,(mn_dir)
                cp 7
                jr z,nv_l
                cp 3
                jr z,nv_r
                cp 1
                jr z,nv_u
                cp 5
                ret nz
                ld a,(m_cnt)            ; abajo
                or a
                ret z
                ld b,a
                ld a,(m_it)
                inc a
                cp b
                jr c,nv_i
                ld a,(m_start)
nv_i:           ld hl,m_it              ; la geometria no cambia: solo se repintan el elemento que se deja y el nuevo
                ld c,(hl)
                ld (hl),a
                ld a,c
                ld (m_i),a
                call mn_item
                ld a,(m_it)
                ld (m_i),a
                jp mn_item
nv_u:           ld a,(m_cnt)
                or a
                ret z
                ld a,(m_it)
                ld hl,m_start
                cp (hl)
                jr nz,nv_u1
                ld a,(m_cnt)
nv_u1:          dec a
                jr nv_i
nv_l:           ld a,(m_only)
                cp 255
                jr nz,nv_m
                ld a,(mn_n)
                ld b,a
                ld a,(m_sel)
                or a
                jr nz,nv_l1
                ld a,b
nv_l1:          dec a
                jr nv_m
nv_r:           ld a,(m_only)
                cp 255
                jr nz,nv_m
                ld a,(mn_n)
                ld b,a
                ld a,(m_sel)
                inc a
                cp b
                jr c,nv_m
                xor a
nv_m:           push af
                call mn_restore
                ld a,(m_only)
                inc a
                call z,mm_st            ; menu principal: el elemento del menu que se deja se recuerda
                pop af
                ld (m_sel),a
                ld a,(m_start)
                ld (m_it),a
                ld a,(m_only)
                inc a
                call z,mm_ld            ; y el del nuevo vuelve a ser el que tenia
                call mn_bar
                jp mn_drop

; ENTER: si el elemento esta activado, mn_res = su controlador
t_menusel:      ld a,(m_cnt)
                or a
                ret z
                ld a,(m_first)
                ld hl,m_it
                add a,(hl)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab+2
                add hl,de
                ld a,(hl)
                inc hl
                ld b,(hl)
                inc b
                dec b
                ret z
                ld (mn_res),a
                ret

t_menuclose:    ld a,(iv_on)
                or a
                call nz,iv_clr
                ld a,(m_only)
                inc a
                jr nz,mcl_x
                ld a,(m_sel)
                ld (mm_sel),a
                call mm_st
mcl_x:          call mn_restore
                ld a,(st_on)
                or a
                jr z,mc_off
                xor a
                ld (st_valid),a
                ret                     ; (el nucleo redibuja la barra de estado con OVB_STATUS)
mc_off:         xor a
                ld (dl_row),a
                jp fill_row

mm_sel:         defb 0
mm_its:         defs MN_MAX             ; el elemento elegido de cada menu (relativo al primero)
; m_it = el elemento recordado del menu m_sel / lo recuerda
mm_ld:          call mm_p
                ld a,(hl)
                ld (m_it),a
                ret
mm_st:          call mm_p
                ld a,(m_it)
                ld (hl),a
                ret
mm_p:           ld a,(m_sel)
                ld e,a
                ld d,0
                ld hl,mm_its
                add hl,de
                ret
mn_n:           defb 0
it_n:           defb 0
bk_mn:          defb 0
bk_it:          defb 0
bk_mp:          defw 0
en_v:           defb 0
m_sel:          defb 0
m_only:         defb 255                ; menu unico (guardar / cargar) o 255
m_je:           defb 0
m_it:           defb 0
m_col:          defb 0
m_first:        defb 0
m_cnt:          defb 0
m_max:          defb 0
m_w:            defb 0
m_i:            defb 0
m_j:            defb 0
m_c2:           defb 0
m_l:            defb 0
m_k:            defb 0
m_attr:         defb 0
m_ep:           defw 0
mp_free:        defw mp_pool
mp_last:        defw 0
mn_tab:         defs 4*MN_MAX
it_tab:         defs 4*IT_MAX
mp_pool:        defs MP_SIZE

; ---------------------------------------------------------------------
;  Guardar y cargar partida: aqui solo la lista de las 12 ranuras (los ficheros estan en el overlay D, agid.asm; el nucleo orquesta). La lista se arma como un
;  menu de una sola entrada (m_only) al final de las tablas de menus (primero las lineas del titulo, desactivadas; m_start = la primera ranura) y t_dlgdone la quita.
;  Las ranuras (si existen y su descripcion) estan en la pagina PG_SAV, en la ventana.
; ---------------------------------------------------------------------
t_dlglist:      ld a,PG_SAV
                call map_page
                call dg_head
                ld hl,s_ins1
                ld a,(sf_mode)
                or a
                jr z,dl_t
                ld hl,s_ins2
dl_t:           xor a
                ld (m_start),a
dl_tl:          ld a,(hl)
                or a
                jr z,dl_ts
                call dg_cp
                push hl
                call mp_cp
                xor a
                ld (dg_ctl),a
                call dg_add
                ld hl,m_start
                inc (hl)
                pop hl
                jr dl_tl
dl_ts:          xor a
                ld (dg_i),a
dg_il:          ld a,(dg_i)
                ld hl,TXT
                inc a
                ld b,'0'
                cp 10
                jr c,dg_d1
                sub 10
                inc b
dg_d1:          add a,'0'
                ld (hl),b
                inc hl
                ld (hl),a
                inc hl
                ld (hl),':'
                inc hl
                ex de,hl
                ld a,(dg_i)
                ld c,a
                ld b,0
                ld hl,SAV_EX
                add hl,bc
                ld a,(hl)
                push af
                ld a,(dg_i)
                inc a
                call dg_dptr
                pop af
                or a
                jr nz,dg_c
                ld hl,s_empty
dg_c:           ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,dg_c
                call mp_cp
                ld a,(dg_i)
                inc a
                ld (dg_ctl),a
                ld a,(sf_mode)
                or a
                ld a,1
                jr z,dg_e
                ld a,(dg_i)
                ld c,a
                ld b,0
                ld hl,SAV_EX
                add hl,bc
                ld a,(hl)
dg_e:           call dg_add
                ld hl,dg_i
                inc (hl)
                ld a,(hl)
                cp 12
                jr c,dg_il
                jp unmap_win

; A = ranura (1-12) -> HL = SAV_DESC + 32 * (A - 1)
dg_dptr:        dec a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,SAV_DESC
                add hl,bc
                ret

; HL = cadena acabada en 0 -> TXT (HL queda tras el 0)
dg_cp:          ld de,TXT
dg_c2:          ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,dg_c2
                ret

; la copia de las tablas de menus y el menu unico de la lista (titulo segun sf_mode: 0 guardar, 1 cargar, 2 inventario)
dg_head:        ld a,(mn_n)
                ld (bk_mn),a
                ld a,(it_n)
                ld (bk_it),a
                ld hl,(mp_free)
                ld (bk_mp),hl
                ld hl,s_sav
                ld a,(sf_mode)
                or a
                jr z,dg_t
                ld hl,s_rst
                cp 1
                jr z,dg_t
                ld hl,s_inv
dg_t:           call dg_cp
                call mp_cp
                ld a,(mn_n)
                ld (m_only),a
                call mn_pa
                ld de,(mp_last)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(it_n)
                ld (hl),a
                inc hl
                ld (hl),0
                ld hl,mn_n
                inc (hl)
                ret

; un elemento al menu unico: el texto esta en la reserva (mp_last), dg_ctl = su controlador, A = activado
dg_add:         ld (dg_en),a
                ld a,(it_n)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab
                add hl,de
                ld de,(mp_last)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(dg_ctl)
                ld (hl),a
                inc hl
                ld a,(dg_en)
                ld (hl),a
                ld hl,it_n
                inc (hl)
                ld a,(mn_n)
                dec a
                call mn_pa
                inc hl
                inc hl
                inc hl
                inc (hl)
                ret

; status (InventoryMgr::show, inv.cpp): los objetos del ego son un menu de una sola entrada que se dibuja con iv_open (pantalla de texto: dos columnas desde la fila 2,
; "You are carrying:" en (0,11) y el pie en la fila 24). El atributo de texto pasa a 0/15 (cmdStatus: charAttrib_Push / Set(0,15)) hasta t_dlgdone.
; iv_sel = bandera 13 (elegir); iv_act = el elemento marcado (el de v25; 255 si no se elige)
t_dlginv:       ld a,(tfg)
                ld (iv_ofg),a
                ld a,(tbg)
                ld (iv_obg),a
                xor a
                ld (tfg),a
                ld (iv_act),a
                ld (iv_empty),a
                ld a,15
                ld (tbg),a
                ld a,(FLAGS+13)
                ld (iv_sel),a
                ld a,1
                ld (iv_on),a
                ld a,PG_INV
                call map_page
                ld a,(LWIN)
                ld (di_cnt),a
                ld b,a
                or a
                jr z,dv_x
                ld hl,INV
dv_c:           ld a,(hl)
                cp 255
                jr z,dv_y
                inc hl
                djnz dv_c
dv_x:           ld a,2                  ; inventario vacio (InventoryMgr::getPlayerInventory): un unico elemento, "nothing", con el objeto 0
                ld (sf_mode),a
                ld (iv_empty),a
                call dg_head
                ld hl,s_nothing
                call dg_cp
                call mp_cp
                xor a
                ld (dg_ctl),a
                inc a
                call dg_add
                call unmap_win
                jr dv_e
s_nothing:      defb "nothing",0
dv_y:           ld a,2
                ld (sf_mode),a
                call dg_head
                ld hl,LWIN+1
                ld (di_sp),hl
                xor a
                ld (di_i),a
dv_l:           ld a,(di_i)
                ld e,a
                ld d,INV>>8
                ld a,(de)
                cp 255
                ld hl,(di_sp)
                jr nz,dv_skip
                ld a,(VARS+25)          ; el objeto de v25 empieza marcado
                ld c,a
                ld a,(di_i)
                cp c
                jr nz,dv_nm
                ld a,(it_n)
                ld c,a
                ld a,(bk_it)
                ld b,a
                ld a,c
                sub b
                ld (iv_act),a
dv_nm:          call dg_cp
                ld (di_sp),hl
                call mp_cp
                ld a,(di_i)
                ld (dg_ctl),a
                ld a,1
                call dg_add
                jr dv_n
dv_skip:        ld a,(hl)
                inc hl
                or a
                jr nz,dv_skip
                ld (di_sp),hl
dv_n:           ld hl,di_i
                inc (hl)
                ld a,(hl)
                ld hl,di_cnt
                cp (hl)
                jr c,dv_l
                call unmap_win
dv_e:           ld a,(iv_sel)
                or a
                ret nz
                ld a,255                ; sin la bandera 13 no hay elemento marcado (_activeItemNr = -1)
                ld (iv_act),a
                ret

; HL = texto, B = fila, C = columna, D = tinta, E = papel (EGA): una linea de texto como display (la fila 24 va a la 23)
iv_out:         ld a,b
                cp 25
                ret nc
                cp 24
                jr c,io_r
                ld a,23
io_r:           ld (dl_row),a
                ld a,c
                ld (dl_col),a
                ld (dl_ptr),hl
                call mp_len
                ld a,b
                or a
                ret z
                ld (dl_n),a
                ld a,d
                push de
                call t_chroma
                ld (dl_fg),a
                pop de
                ld a,e
                call t_chroma
                ld (dl_bg),a
                jp draw_line

; A = elemento (0...): su texto en dos columnas (los pares a la izquierda, en la columna 1; los impares acaban en la 39), marcado si es iv_act
iv_item:        ld (iv_k),a
                ld hl,bk_it
                add a,(hl)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                call mp_len
                ld e,a
                ld a,(iv_k)
                srl a
                add a,2
                ld b,a                  ; fila
                ld a,(iv_k)
                and 1
                ld c,1
                jr z,ii_c
                ld a,39                 ; a la derecha: la columna 39 - largo
                sub e
                ld c,a
ii_c:           ld a,(iv_empty)
                or a
                jr z,ii_a
                ld c,16                 ; 19 - strlen("nothing") / 2
ii_a:           ld a,(iv_act)
                ld d,a
                ld a,(iv_k)
                cp d
                ld de,$000F             ; tinta 0, papel 15
                jr nz,ii_d
                ld de,$0F00             ; el marcado: tinta 15, papel 0
ii_d:           jp iv_out

; abre el inventario: filas 0, 22 y 23 en blanco (cmdTextScreen), titulo, elementos y pie
iv_open:        ld a,255
                ld (mn_res),a
                ld a,(bk_it)
                ld (m_first),a
                ld a,(it_n)
                ld hl,bk_it
                sub (hl)
                ld (m_cnt),a
                ld a,(iv_act)
                ld (m_it),a
                xor a
                ld (pr_ln),a
                ld (dl_row),a
                ld a,15
                call fill_row
                ld a,22
                ld (dl_row),a
                ld a,15
                call fill_row
                ld a,23
                ld (dl_row),a
                ld a,15
                call fill_row
                ld hl,s_carry
                ld bc,$000B
                ld de,$000F
                call iv_out
                xor a
                ld (iv_i),a
io_il:          ld a,(iv_i)
                ld hl,m_cnt
                cp (hl)
                jr nc,io_ft
                call iv_item
                ld hl,iv_i
                inc (hl)
                jr io_il
io_ft:          ld a,(iv_sel)
                or a
                ld hl,s_isel
                ld bc,$1802
                jr nz,io_p
                ld hl,s_iret
                ld bc,$1804
io_p:           ld de,$000F
                jp iv_out

; mn_dir = 1 arriba (-2), 5 abajo (+2), 7 izquierda (-1), 3 derecha (+1): dentro de los limites, sin dar la vuelta (changeActiveItem)
iv_nav:         ld a,(iv_sel)
                or a
                ret z
                ld a,(mn_dir)
                ld d,-2
                cp 1
                jr z,in_d
                ld d,2
                cp 5
                jr z,in_d
                ld d,-1
                cp 7
                jr z,in_d
                ld d,1
                cp 3
                ret nz
in_d:           ld a,(iv_act)
                ld c,a
                add a,d
                ld hl,m_cnt
                cp (hl)
                ret nc
                ld (iv_act),a
                ld (m_it),a
                ld a,c
                call iv_item
                ld a,(iv_act)
                jp iv_item

iv_clr:         ld a,22
                ld (dl_row),a
                xor a
                call fill_row
                ld a,23
                ld (dl_row),a
                xor a
                jp fill_row

iv_on:          defb 0
iv_sel:         defb 0
iv_act:         defb 0
iv_empty:       defb 0
iv_ofg:         defb 0
iv_obg:         defb 0
iv_k:           defb 0
iv_i:           defb 0
s_carry:        defb "You are carrying:",0
s_isel:         defb "Press ENTER to select, ESC to cancel",0
s_iret:         defb "Press a key to return to the game",0

; despues del bucle de menu: se quita la lista (si se eligio una ranura, el resultado se queda en mn_res)
t_dlgdone:      ld a,(iv_on)
                or a
                jr z,dd_n
                xor a
                ld (iv_on),a
                ld a,(iv_ofg)
                ld (tfg),a
                ld a,(iv_obg)
                ld (tbg),a
                ld a,(iv_sel)
                or a
                jr z,dd_n
                ld a,(mn_res)           ; v25 = el objeto elegido (ENTER) o 255 (ESC)
                ld (VARS+25),a
dd_n:           xor a
                ld (m_start),a
                ld a,(bk_mn)
                ld (mn_n),a
                ld a,(bk_it)
                ld (it_n),a
                ld hl,(bk_mp)
                ld (mp_free),hl
                ld a,255
                ld (m_only),a
                ret

; despues de cargar una partida: los menus vuelven a estar activados
t_menuon:       ld a,(it_n)
                or a
                ret z
                ld b,a
                ld hl,it_tab+3
mu_e:           ld (hl),1
                inc hl
                inc hl
                inc hl
                inc hl
                djnz mu_e
                ret

s_sav:          defb "Save game",0
s_inv:          defb "You are carrying",0
s_rst:          defb "Restore game",0
s_empty:        defb "(empty)",0
s_ins1:         defb "Use the arrow keys to select the",0,"slot in which you wish to save",0,"the game.",0
                defb "Press ENTER to save in the slot,",0,"ESC to not save a game.",0,0
s_ins2:         defb "Use the arrow keys to select the",0,"game which you wish to restore.",0
                defb "Press ENTER to restore the game,",0,"ESC to not restore a game.",0,0
dg_i:           defb 0
dg_ctl:         defb 0
dg_en:          defb 0
di_cnt:         defb 0
di_i:           defb 0
di_sp:          defw 0
m_start:        defb 0


                include "agitx.inc"
