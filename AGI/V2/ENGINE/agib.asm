; =====================================================================
;  agib.asm - overlay B: texto (display, clear.lines, barra de estado, linea de entrada). Pagina PG_OVB, en el bloque 1 solo mientras se ejecuta
;  (el nucleo la mapea con call_b y devuelve la A). Ver agitxt.asm (antes un solo overlay) para el funcionamiento:
;  fuente de 6x8 (font6.bin), 42 columnas por 24 filas, fila 0 = barra de estado, 1-21 = imagen, 22-23 = pie. Una linea de texto se compone por celdas
;  HiRes de 8 pixeles: la cubierta entera pasa a papel = fondo, tinta = color del texto con el bitmap de los glifos; la cubierta a medias recibe solo
;  sus pixeles, uno a uno, con `plot` (nucleo). El texto sobre la imagen se escribe tambien en la copia de fondo (text_bg) y manda recomponer los rotulos.
;  Mismo comportamiento que TOOLS/agi_text.py y las ordenes de texto de TOOLS/agi_vm.py.
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_display            ; OVB_DISPLAY
                jp t_display_v          ; OVB_DISPLAY_V
                jp t_clear_lines        ; OVB_CLEAR
                jp t_status             ; OVB_STATUS (una vez por ciclo)
                jp t_status_on          ; OVB_SON
                jp t_status_off         ; OVB_SOFF
                jp t_set_attr           ; OVB_ATTR
                jp t_prompt             ; OVB_PROMPT
                jp t_print              ; OVB_PRINT
                jp t_boxclose           ; OVB_BOXCLOSE
                jp t_setmenu            ; OVB_SETMENU
                jp t_setitem            ; OVB_SETITEM
                jp t_enable             ; OVB_ENABLE
                jp t_disable            ; OVB_DISABLE
                jp t_menuopen           ; OVB_MENUOPEN
                jp t_menunav            ; OVB_MENUNAV
                jp t_menusel            ; OVB_MENUSEL
                jp t_menuclose          ; OVB_MENUCLOSE
                jp t_dlgsave            ; OVB_DLGSAVE
                jp t_dlgload            ; OVB_DLGLOAD
                jp t_dlgdone            ; OVB_DLGDONE

TXT             equ TMPM

t_set_attr:     ld a,(ARGS)
                and 15
                ld (tfg),a
                ld a,(ARGS+1)
                and 15
                ld (tbg),a
                ret

t_display:      ld a,(ARGS)
                ld (dl_row0),a
                ld a,(ARGS+1)
                ld (tcol0),a
                ld a,(ARGS+2)
                jr td_go
t_display_v:    ld a,(ARGS)
                call getv
                ld (dl_row0),a
                ld a,(ARGS+1)
                call getv
                ld (tcol0),a
                ld a,(ARGS+2)
                call getv
td_go:          ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,250
                call build_str
                ld a,(tfg)
                call t_chroma
                ld (dl_fg),a
                ld a,(tbg)
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
td_line:        ld a,(dl_row0)
                cp 24
                ret nc
                ld (dl_ptr),hl
                ld b,0
tl_c:           ld a,(hl)
                or a
                jr z,tl_e
                cp 10
                jr z,tl_e
                inc hl
                inc b
                jr tl_c
tl_e:           ld (tterm),a
                ld a,(tcol0)
                ld c,a
                ld a,42
                sub c
                jr nc,tl_m
                xor a
tl_m:           cp b
                jr c,tl_n
                ld a,b
tl_n:           or a
                jr z,tl_next
                ld (dl_n),a
                ld a,(dl_row0)
                ld (dl_row),a
                ld a,c
                ld (dl_col),a
                push hl
                call draw_line
                pop hl
tl_next:        ld a,(tterm)
                or a
                ret z
                inc hl
                ld a,(dl_row0)
                inc a
                ld (dl_row0),a
                jp td_line

; A = color EGA -> codigo de Chroma
t_chroma:       and 15
                ld e,a
                ld d,0
                ld hl,ega2ch
                add hl,de
                ld a,(hl)
                ret

; ---------------------------------------------------------------------
;  Una linea de texto: dl_ptr, dl_n (1-42), dl_row, dl_col, dl_fg, dl_bg (codigos de Chroma)
; ---------------------------------------------------------------------
draw_line:      ld a,(dl_col)
                ld b,a
                add a,a
                add a,b
                add a,a
                ld (dl_x0),a            ; x0 = col * 6
draw_line_px:   ld a,(dl_x0)            ; (entrada con x0 en pixeles: las ventanas)
                rrca
                rrca
                rrca
                and 31
                ld (dl_ca),a
                ld a,(dl_n)
                ld b,a
                add a,a
                add a,b
                add a,a                 ; 6 * n
                ld b,a
                ld a,(dl_x0)
                add a,b
                dec a
                rrca
                rrca
                rrca
                and 31                  ; celda del ultimo pixel
                ld hl,dl_ca
                sub (hl)
                inc a
                ld (dl_nb),a
                xor a
                ld (dl_k),a
dl_kl:
                ld a,(dl_row)
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(dl_k)
                add a,b
                call t_srow
                ld hl,LB
                ld de,LB+1
                ld bc,67
                ld (hl),0
                ldir
                ld hl,(dl_ptr)
                ld a,(dl_n)
                ld b,a
                ld a,(dl_x0)
                and 7
                ld (dl_s),a
dl_ch:          push bc
                push hl
                ld a,(hl)
                cp 32
                jr c,dl_sp
                cp 128
                jr c,dl_ok
dl_sp:          ld a,32
dl_ok:          sub 32
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,FONT
                add hl,de
                ld a,(dl_k)
                ld e,a
                ld d,0
                add hl,de
                ld a,(hl)
                and $FC
                ld h,a
                ld l,0
                ld de,$FC00
                ld a,(dl_s)
                and 7
                jr z,dl_sd
                ld b,a
dl_sl:          srl h
                rr l
                srl d
                rr e
                djnz dl_sl
dl_sd:          ld a,(dl_s)
                rrca
                rrca
                rrca
                and 31
                ld c,a
                ld b,0
                ld ix,LB
                add ix,bc
                ld a,h
                or (ix+0)
                ld (ix+0),a
                ld a,l
                or (ix+1)
                ld (ix+1),a
                ld a,d
                or (ix+34)
                ld (ix+34),a
                ld a,e
                or (ix+35)
                ld (ix+35),a
                ld a,(dl_s)
                add a,6
                ld (dl_s),a
                pop hl
                inc hl
                pop bc
                djnz dl_ch
                xor a
                ld (dl_j),a
dl_cell:        ld a,(dl_j)
                ld e,a
                ld d,0
                ld hl,LB
                add hl,de
                ld c,(hl)               ; bitmap de los glifos
                ld de,34
                add hl,de
                ld b,(hl)               ; cobertura
                ld a,b
                cp $FF
                jr nz,dl_part
                ld a,(dl_j)
                ld hl,dl_ca
                add a,(hl)
                ld e,a
                ld d,0
                ld hl,(srow)
                add hl,de
                ld a,(dl_bg)
                ld e,a
                ld a,(dl_fg)
                cp e
                jr nz,dl_f2
                ld c,0                  ; una celda de un solo color lleva el bitmap a 0
dl_f2:          ld (hl),c
                ld a,h
                add a,$20
                ld h,a
                ld a,e
                rlca
                rlca
                rlca
                rlca
                ld e,a
                ld a,(dl_fg)
                or e
                ld (hl),a
                jr dl_next
dl_part:        or a
                jr z,dl_next
                ld (dl_m),a
                ld a,c
                ld (dl_b),a
                ld a,(dl_j)
                ld hl,dl_ca
                add a,(hl)
                add a,a
                add a,a
                add a,a
                ld (dl_hx),a
                ld a,$80
                ld (dl_bm),a
dl_pix:         ld a,(dl_m)
                ld hl,dl_bm
                and (hl)
                jr z,dl_pn
                ld a,(dl_b)
                and (hl)
                ld a,(dl_fg)
                jr nz,dl_pc
                ld a,(dl_bg)
dl_pc:          ld (sch),a
                ld a,(dl_hx)
                call plot
dl_pn:          ld hl,dl_hx
                inc (hl)
                ld hl,dl_bm
                srl (hl)
                jr nz,dl_pix
dl_next:        ld hl,dl_j
                inc (hl)
                ld a,(dl_nb)
                cp (hl)
                jp nz,dl_cell
                ld hl,dl_k
                inc (hl)
                ld a,(hl)
                cp 8
                jp nz,dl_kl
                jp text_bg

; A = linea de pantalla -> srow = direccion del bitmap de su primera celda
t_srow:         ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,HR_BM
                add hl,de
                ld (srow),hl
                ld de,$2000
                add hl,de
                ld (sarow),hl
                ret

; ---------------------------------------------------------------------
;  clear.lines: filas A-B con el color C (EGA)
; ---------------------------------------------------------------------
t_clear_lines:  ld a,(ARGS)
                ld (cl_r),a
                ld a,(ARGS+1)
                cp 24
                jr c,cl_e
                ld a,23
cl_e:           ld (cl_end),a
cl_row:         ld a,(cl_end)
                ld hl,cl_r
                cp (hl)
                ret c
                ld a,(hl)
                ld (dl_row),a
                ld a,(ARGS+2)
                call fill_row
                ld hl,cl_r
                inc (hl)
                jr cl_row

; dl_row = fila, A = color EGA: la rellena (bitmap 0, papel = tinta = color)
fill_row:       call t_chroma
                ld c,a
                rlca
                rlca
                rlca
                rlca
                or c
                ld (cl_attr),a
                xor a
                ld (dl_ca),a
                ld a,32
                ld (dl_nb),a
                xor a
                ld (dl_k),a
fr_k:           ld a,(dl_row)
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(dl_k)
                add a,b
                call t_srow
                ld hl,(srow)
                ld b,32
                xor a
fr_b:           ld (hl),a
                inc hl
                djnz fr_b
                ld hl,(srow)
                ld a,h
                add a,$20
                ld h,a
                ld a,(cl_attr)
                ld b,32
fr_a:           ld (hl),a
                inc hl
                djnz fr_a
                ld hl,dl_k
                inc (hl)
                ld a,(hl)
                cp 8
                jr nz,fr_k
                jp text_bg

; ---------------------------------------------------------------------
;  Barra de estado
; ---------------------------------------------------------------------
t_status_on:    ld a,1
                ld (st_on),a
                xor a
                ld (st_valid),a
                ret

t_status_off:   xor a
                ld (st_on),a
                ld (dl_row),a
                jp fill_row             ; A = 0: color 0 (negro)

t_status:       ld a,(st_on)
                or a
                ret z
                ld a,(st_valid)
                or a
                jr z,ts_draw
                ld a,(VARS+3)
                ld hl,st_v3
                cp (hl)
                jr nz,ts_draw
                ld a,(VARS+7)
                ld hl,st_v7
                cp (hl)
                jr nz,ts_draw
                ld a,(FLAGS+9)
                ld hl,st_f9
                cp (hl)
                ret z
ts_draw:        ld a,1
                ld (st_valid),a
                ld a,(VARS+3)
                ld (st_v3),a
                ld a,(VARS+7)
                ld (st_v7),a
                ld a,(FLAGS+9)
                ld (st_f9),a
                xor a
                ld (dl_row),a
                ld a,15
                call fill_row
                ld hl,TXT
                ld (bs_dp),hl
                xor a
                ld (bs_n),a
                ld a,60
                ld (bs_max),a
                ld hl,s_score
                call put_str
                ld a,(st_v3)
                call put_dec
                ld hl,s_of
                call put_str
                ld a,(st_v7)
                call put_dec
                call bs_end
                xor a
                call t_chroma
                ld (dl_fg),a
                ld a,15
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(bs_n)
                ld (dl_n),a
                xor a
                ld (dl_row),a
                ld (dl_col),a
                call draw_line
                ld hl,s_son
                ld a,(st_f9)
                or a
                ld a,8
                jr nz,ts_snd
                ld hl,s_soff
                ld a,9
ts_snd:         ld (dl_n),a
                ld (dl_ptr),hl
                ld a,30
                ld (dl_col),a
                jp draw_line

; HL = cadena terminada en 0 -> al texto de salida (bs_put)
put_str:        ld a,(hl)
                or a
                ret z
                inc hl
                push hl
                call bs_put
                pop hl
                jr put_str

; Linea de entrada (fila 23): "> " + lo escrito + "_"; se pide desde kb_prompt (nucleo) cuando cambia
t_prompt:       ld a,23
                ld (dl_row),a
                xor a
                call fill_row
                ld a,(accin)
                or a
                ret z
                ld hl,TXT
                ld (bs_dp),hl
                xor a
                ld (bs_n),a
                ld a,60
                ld (bs_max),a
                ld hl,s_prompt
                call put_str
                ld hl,INBUF
                call put_str
                ld a,'_'
                call bs_put
                ld a,15
                call t_chroma
                ld (dl_fg),a
                xor a
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(bs_n)
                ld (dl_n),a
                ld a,23
                ld (dl_row),a
                xor a
                ld (dl_col),a
                jp draw_line

s_prompt:       defb "> ",0

; Texto escrito sobre la imagen (filas 1-21): dl_row, dl_ca, dl_nb pasan de la pantalla a la copia de fondo y los rotulos se recomponen
text_bg:        ld a,(dl_nobg)
                or a
                ret nz
                ld a,(picvalid)
                or a
                ret z
                ld a,(dl_row)
                or a
                ret z
                cp 22
                ret nc
                ld a,1
                ld (sw_force),a
                ld a,PG_BGB
                ld de,HR_BM
                call tb_plane
                ld a,PG_BGA
                ld de,HR_ATT
                call tb_plane
                jp map7_back
tb_plane:      ld (tb_base),de
                call map7
                ld a,(dl_row)
                add a,a
                add a,a
                add a,a
                ld (tb_l),a
                ld a,8
                ld (tb_n),a
tb_row:        ld a,(tb_l)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(dl_ca)
                ld e,a
                ld d,0
                add hl,de
                push hl
                ld de,(tb_base)
                add hl,de               ; origen: la pantalla
                ex (sp),hl              ; HL = desplazamiento
                ld de,$DF00
                add hl,de               ; destino: la copia
                ex de,hl
                pop hl
                ld a,(dl_nb)
                ld c,a
                ld b,0
                ldir
                ld hl,tb_l
                inc (hl)
                ld hl,tb_n
                dec (hl)
                jr nz,tb_row
                ret


s_score:        defb " Score:",0
s_of:           defb " of ",0
s_son:          defb "Sound:on"
s_soff:         defb "Sound:off"

tfg:            defb 15
tbg:            defb 0
tcol0:          defb 0
tterm:          defb 0
st_on:          defb 0
st_valid:       defb 0
st_v3:          defb 0
st_v7:          defb 0
st_f9:          defb 0
cl_r:           defb 0
cl_end:         defb 0
cl_attr:        defb 0
dl_ptr:         defw 0
dl_n:           defb 0
dl_row:         defb 0
dl_row0:        defb 0
dl_col:         defb 0
dl_fg:          defb 0
dl_bg:          defb 0
dl_x0:          defb 0
dl_ca:          defb 0
dl_nb:          defb 0
dl_k:           defb 0
dl_s:           defb 0
dl_j:           defb 0
dl_m:           defb 0
dl_b:           defb 0
dl_hx:          defb 0
dl_bm:          defb 0
LB:             defs 68

; ---------------------------------------------------------------------
;  Ventanas de mensaje (print): el nucleo pone pr_msg, pr_row (255 = centrada), pr_col y pr_w y llama a t_print (dibuja) y, despues de esperar una tecla,
;  a t_boxclose (devuelve la imagen limpia). Mismo resultado que agi_text.wrap / box_geom / draw_box: lineas de como mucho pr_w caracteres (30 si 0 o mas de 36),
;  una celda de relleno a cada lado y una fila arriba y otra abajo, blanco con letras negras y un marco rojo de un pixel.
; ---------------------------------------------------------------------
t_print:        ld a,(pr_msg)
                ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,250
                call build_str
                ld a,(pr_w)
                or a
                jr z,tp_w30
                cp 37
                jr c,tp_w
tp_w30:         ld a,30
tp_w:           ld (wr_w),a
                call wrap
                ld a,(wr_n)             ; la linea mas larga
                ld b,a
                ld hl,LN
                ld c,0
tp_m:           ld a,(hl)
                cp c
                jr c,tp_mn
                ld c,a
tp_mn:          ld de,40
                add hl,de
                djnz tp_m
                ld a,c                  ; celdas de ancho = (6 * largo + 7) / 8 + 2
                add a,a
                ld b,a
                add a,a
                add a,b
                add a,7
                rrca
                rrca
                rrca
                and 31
                add a,2
                ld (pr_bw),a
                ld a,(wr_n)
                add a,2
                ld (pr_nr),a
                ld b,a
                ld a,(pr_row)
                cp 255
                jr nz,tp_at
                ld a,21                 ; centrada: fila = 1 + (21 - filas) / 2, celda = (32 - ancho) / 2
                sub b
                srl a
                inc a
                ld (pr_top),a
                ld a,(pr_bw)
                ld b,a
                ld a,32
                sub b
                srl a
                ld (pr_cxl),a
                jr tp_dr
tp_at:          or a                    ; print.at: fila entre 1 y 22 - filas, celda = col * 6 / 8 sin salirse
                jr nz,tp_r1
                ld a,1
tp_r1:          ld c,a
                ld a,22
                sub b
                ld d,a
                ld a,c
                cp d
                jr c,tp_r2
                ld a,d
tp_r2:          ld (pr_top),a
                ld a,(pr_col)
                ld c,a
                add a,a
                add a,c
                add a,a
                rrca
                rrca
                rrca
                and 31
                ld c,a
                ld a,(pr_bw)
                ld b,a
                ld a,32
                sub b
                ld d,a
                ld a,c
                cp d
                jr c,tp_c2
                ld a,d
tp_c2:          ld (pr_cxl),a
tp_dr:          ld a,1                  ; lo que se escribe aqui no pasa a la copia de fondo
                ld (dl_nobg),a
                ld a,(pr_top)
                add a,a
                add a,a
                add a,a
                ld (pr_l0),a
                ld a,(pr_nr)
                add a,a
                add a,a
                add a,a
                ld (pr_ln),a
                ld (pr_k),a
                ld a,(pr_l0)
                ld (pr_l),a
tp_f:           ld a,(pr_l)             ; relleno: bitmap 0, atributos papel blanco y tinta roja
                call pr_addr
                ld de,HR_BM
                add hl,de
                ld a,(pr_bw)
                ld b,a
                xor a
tp_fb:          ld (hl),a
                inc hl
                djnz tp_fb
                ld a,(pr_l)
                call pr_addr
                ld de,HR_ATT
                add hl,de
                ld a,(pr_bw)
                ld b,a
                ld a,$F2
tp_fa:          ld (hl),a
                inc hl
                djnz tp_fa
                ld hl,pr_l
                inc (hl)
                ld hl,pr_k
                dec (hl)
                jr nz,tp_f
                xor a                   ; el texto
                ld (pr_i),a
tp_t:           ld a,(pr_i)
                ld hl,wr_n
                cp (hl)
                jr nc,tp_bd
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de               ; 40 * i
                ld de,LN
                add hl,de
                ld a,(hl)
                or a
                jr z,tp_tn
                ld (dl_n),a
                inc hl
                ld (dl_ptr),hl
                ld a,(pr_top)
                inc a
                ld hl,pr_i
                add a,(hl)
                ld (dl_row),a
                ld a,(pr_cxl)
                inc a
                add a,a
                add a,a
                add a,a
                ld (dl_x0),a
                xor a
                call t_chroma
                ld (dl_fg),a
                ld a,15
                call t_chroma
                ld (dl_bg),a
                call draw_line_px
tp_tn:          ld hl,pr_i
                inc (hl)
                jr tp_t
tp_bd:          ld a,(pr_l0)            ; marco: linea de arriba y de abajo enteras
                call pr_addr
                ld de,HR_BM
                add hl,de
                call pr_ff
                ld a,(pr_l0)
                ld hl,pr_ln
                add a,(hl)
                dec a
                call pr_addr
                ld de,HR_BM
                add hl,de
                call pr_ff
                ld a,(pr_ln)            ; y el pixel de la izquierda y el de la derecha de cada linea
                ld (pr_k),a
                ld a,(pr_l0)
                ld (pr_l),a
tp_s:           ld a,(pr_l)
                call pr_addr
                ld de,HR_BM
                add hl,de
                set 7,(hl)
                ld a,(pr_bw)
                dec a
                ld e,a
                ld d,0
                add hl,de
                set 0,(hl)
                ld hl,pr_l
                inc (hl)
                ld hl,pr_k
                dec (hl)
                jr nz,tp_s
                xor a
                ld (dl_nobg),a
                ret

; A = linea de pantalla -> HL = linea * 32 + pr_cxl
pr_addr:        ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(pr_cxl)
                ld e,a
                ld d,0
                add hl,de
                ret

; HL = byte del bitmap -> pr_bw bytes a 255
pr_ff:          ld a,(pr_bw)
                ld b,a
                ld a,255
pf_l:           ld (hl),a
                inc hl
                djnz pf_l
                ret

; La imagen limpia (copia de fondo) en el rectangulo de la ventana
t_boxclose:     ld a,(picvalid)
                or a
                ret z
                ld a,PG_BGB
                ld de,HR_BM
                call bc_plane
                ld a,PG_BGA
                ld de,HR_ATT
                call bc_plane
                jp map7_back
bc_plane:       ld (bc_base),de
                call map7
                ld a,(pr_l0)
                ld (pr_l),a
                ld a,(pr_ln)
                ld (pr_k),a
bc_row:         ld a,(pr_l)
                call pr_addr
                push hl
                ld de,$DF00
                add hl,de               ; origen: la copia de fondo
                ex (sp),hl              ; HL = desplazamiento
                ld de,(bc_base)
                add hl,de               ; destino: la pantalla
                ex de,hl
                pop hl
                ld a,(pr_bw)
                ld c,a
                ld b,0
                ldir
                ld hl,pr_l
                inc (hl)
                ld hl,pr_k
                dec (hl)
                jr nz,bc_row
                ret

; ---------------------------------------------------------------------
;  Reparto del mensaje (TXT) en lineas de wr_w caracteres, en LN (40 bytes por linea: largo y caracteres) y su numero en wr_n
; ---------------------------------------------------------------------
wrap:           ld hl,LN
                ld (wr_lp),hl
                xor a
                ld (wr_len),a
                ld (wr_n),a
                ld hl,TXT
wr_nx:          ld a,(hl)
                or a
                jp z,wr_end
                cp 10
                jr nz,wr_nn
                inc hl
                push hl
                call wr_flush
                pop hl
                jr wr_nx
wr_nn:          cp 33
                jr c,wr_sk
                cp 128
                jr c,wr_tok
wr_sk:          inc hl
                jr wr_nx
wr_tok:         ld (wr_tp),hl
                ld b,0
wr_c:           ld a,(hl)
                cp 33
                jr c,wr_te
                cp 128
                jr nc,wr_te
                inc hl
                inc b
                jr wr_c
wr_te:          ld (wr_np),hl
                ld a,b
                ld (wr_tl),a
wr_big:         ld a,(wr_w)             ; una palabra mas larga que la linea se parte en trozos
                ld hl,wr_tl
                cp (hl)
                jr nc,wr_fit
                ld a,(wr_len)
                or a
                call nz,wr_flush
                ld a,(wr_w)
                ld b,a
                call wr_copy
                call wr_flush
                ld a,(wr_w)
                ld c,a
                ld b,0
                ld hl,(wr_tp)
                add hl,bc
                ld (wr_tp),hl
                ld hl,wr_tl
                ld a,(hl)
                sub c
                ld (hl),a
                jr wr_big
wr_fit:         ld a,(wr_tl)
                or a
                jr z,wr_af
                ld a,(wr_len)
                or a
                jr z,wr_put
                ld hl,wr_tl
                add a,(hl)
                inc a                   ; largo + 1 + palabra
                ld hl,wr_w
                cp (hl)
                jr c,wr_add
                jr z,wr_add
                call wr_flush
                jr wr_put
wr_add:         ld a,' '
                call wr_ch
wr_put:         ld a,(wr_tl)
                ld b,a
                call wr_copy
wr_af:          ld hl,(wr_np)
                jp wr_nx
wr_end:         jp wr_flush

; B caracteres a partir de wr_tp al final de la linea
wr_copy:        ld hl,(wr_tp)
wc_l:           ld a,b
                or a
                ret z
                ld a,(hl)
                inc hl
                push hl
                push bc
                call wr_ch
                pop bc
                pop hl
                dec b
                jr wc_l

; A = caracter al final de la linea actual
wr_ch:          ld c,a
                ld hl,(wr_lp)
                ld a,(wr_len)
                inc a
                ld e,a
                ld d,0
                add hl,de
                ld (hl),c
                ld hl,wr_len
                inc (hl)
                ret

; cierra la linea actual (como mucho 19)
wr_flush:       ld a,(wr_n)
                cp 19
                jr nc,wf_z
                ld hl,(wr_lp)
                ld a,(wr_len)
                ld (hl),a
                ld de,40
                add hl,de
                ld (wr_lp),hl
                ld hl,wr_n
                inc (hl)
wf_z:           xor a
                ld (wr_len),a
                ret

dl_nobg:        defb 0
wr_w:           defb 0
wr_n:           defb 0
wr_len:         defb 0
wr_lp:          defw 0
wr_tp:          defw 0
wr_np:          defw 0
wr_tl:          defb 0
pr_bw:          defb 0
pr_nr:          defb 0
pr_top:         defb 0
pr_cxl:         defb 0
pr_l0:          defb 0
pr_ln:          defb 0
pr_l:           defb 0
pr_k:           defb 0
pr_i:           defb 0
bc_base:        defw 0
LN:             defs 40*20

tb_base:       defw 0
tb_l:           defb 0
tb_n:           defb 0

; ---------------------------------------------------------------------
;  Menus. Los textos (36 caracteres como mucho) se copian a la reserva mp_pool al hacer set.menu / set.menu.item: mn_tab (titulo, primer elemento, cuantos) e it_tab
;  (texto, controlador, activado). menu.input (nucleo) los abre con la barra en la fila 0 (blanco, el titulo elegido en inverso) y, bajo el titulo, una lista de
;  elementos en las filas 1... (el elegido en inverso, los desactivados en gris), alineada a la celda del titulo sin salirse; al cerrar se devuelve la imagen limpia
;  (t_boxclose) y la barra de estado. Mismo resultado que Interp.draw_menu() de TOOLS/agi_vm.py.
; ---------------------------------------------------------------------
MN_MAX          equ 10
IT_MAX          equ 60
MP_SIZE         equ 1500
MP_LIM          equ mp_pool+MP_SIZE-40

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
                add a,2
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
                ld a,32
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
                ld (hl),' '
                inc hl
                ld c,0
mb_cp:          ld a,(de)
                or a
                jr z,mb_z
                ld (hl),a
                inc hl
                inc de
                inc c
                jr mb_cp
mb_z:           ld (hl),' '
                ld a,c
                add a,2
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
                ld (hl),a
                ld hl,m_j
                inc (hl)
                jr mb_l
mb_e:           xor a
                ld (dl_nobg),a
                ret

; La lista del menu elegido (m_it = el marcado)
mn_drop:        call mn_geom
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

t_menuopen:     ld a,(mn_n)
                or a
                jr nz,mo_ok
                ld a,254
                ld (mn_res),a
                ret
mo_ok:          ld a,255
                ld (mn_res),a
                xor a
                ld (m_it),a
                ld a,(m_only)
                cp 255
                jr nz,mo_sx
                xor a
mo_sx:           ld (m_sel),a
                call mn_bar
                jp mn_drop

; La imagen limpia bajo la lista
mn_restore:     ld a,(pr_ln)
                or a
                ret z
                jp t_boxclose

; mn_dir = 1 arriba, 3 derecha, 5 abajo, 7 izquierda
t_menunav:      ld a,(mn_dir)
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
                xor a
nv_i:           ld (m_it),a
                jp mn_drop
nv_u:           ld a,(m_cnt)
                or a
                ret z
                ld a,(m_it)
                or a
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
                pop af
                ld (m_sel),a
                xor a
                ld (m_it),a
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

t_menuclose:    call mn_restore
                ld a,(st_on)
                or a
                jr z,mc_off
                xor a
                ld (st_valid),a
                ret
mc_off:         xor a
                ld (dl_row),a
                jp fill_row

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
;  Guardar y cargar partida. SAV/GAMEn.SAV (n = 1-9): 32 bytes de descripcion ("Room n  Score m") y los bloques de sf_tab (direccion, largo).
;  La lista de ranuras se arma como un menu de una sola entrada (m_only) al final de las tablas de menus y t_dlgdone la quita.
; ---------------------------------------------------------------------
CMD_FWRITE      equ 56
CMD_FCREATE     equ 71

t_dlgsave:      xor a
                jr dg_go
t_dlgload:      ld a,1
dg_go:          ld (sf_mode),a
                call dg_read
                jp dg_menu

; las descripciones de las 9 ranuras (sf_desc) y si existen (sf_ex)
dg_read:        ld a,1
                ld (dg_i),a
dr_l:           ld a,(dg_i)
                add a,'0'
                ld (sf_nm+8),a
                ld hl,sf_nm
                call f_open
                cp $FF
                jr z,dr_no
                ld (sf_h),a
                call dg_dptr
                ld bc,32
                ld a,(sf_h)
                call f_read_n
                ld a,(sf_h)
                call f_close
                ld a,1
                jr dr_s
dr_no:          call dg_dptr
                ex de,hl
                ld hl,s_empty
dr_c:           ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,dr_c
                xor a
dr_s:           push af
                ld a,(dg_i)
                dec a
                ld e,a
                ld d,0
                ld hl,sf_ex
                add hl,de
                pop af
                ld (hl),a
                ld hl,dg_i
                inc (hl)
                ld a,(hl)
                cp 10
                jr c,dr_l
                ret

; HL = sf_desc + 32 * (dg_i - 1)
dg_dptr:        ld a,(dg_i)
                dec a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,sf_desc
                add hl,de
                ret

; HL = cadena acabada en 0 -> TXT
dg_cp:          ld de,TXT
dg_c2:          ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,dg_c2
                ret

dg_menu:        ld a,(mn_n)
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
                ld a,1
                ld (dg_i),a
dg_il:          ld hl,TXT
                ld a,(dg_i)
                add a,'0'
                ld (hl),a
                inc hl
                ld (hl),' '
                call dg_dptr
                ld de,TXT+2
dg_c:           ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,dg_c
                call mp_cp
                ld a,(it_n)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,it_tab
                add hl,de
                ld (dg_ep),hl
                ld de,(mp_last)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(dg_i)
                ld (hl),a
                ld a,(sf_mode)
                or a
                ld a,1
                jr z,dg_e
                ld a,(dg_i)
                dec a
                ld e,a
                ld d,0
                ld hl,sf_ex
                add hl,de
                ld a,(hl)
dg_e:           ld hl,(dg_ep)
                inc hl
                inc hl
                inc hl
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
                ld hl,dg_i
                inc (hl)
                ld a,(hl)
                cp 10
                jr c,dg_il
                ret

; despues del bucle de menu: se quita la lista y, si se eligio una ranura (mn_res), se guarda o se carga (sv_ok = 1 si se ha cargado)
t_dlgdone:      xor a
                ld (sv_ok),a
                ld a,(bk_mn)
                ld (mn_n),a
                ld a,(bk_it)
                ld (it_n),a
                ld hl,(bk_mp)
                ld (mp_free),hl
                ld a,255
                ld (m_only),a
                ld a,(mn_res)
                cp 255
                ret z
                add a,'0'
                ld (sf_nm+8),a
                ld a,(sf_mode)
                or a
                jp z,sf_save
                jp sf_load

sf_save:        ld hl,sf_nm
                call f_create
                cp $FF
                ret z
                ld (sf_h),a
                call sf_mkdesc
                xor a
                ld (wf_err),a
                ld a,(sf_h)
                ld hl,sf_buf
                ld bc,32
                call f_write_n
                ld hl,sf_tab
sw_l:           ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,d
                or e
                jr z,sw_d
                push hl
                ex de,hl
                ld a,(sf_h)
                call f_write_n
                pop hl
                jr sw_l
sw_d:           ld a,(sf_h)
                jp f_close

sf_load:        ld hl,sf_nm
                call f_open
                cp $FF
                ret z
                ld (sf_h),a
                call h_stop_sound       ; el sonido que suene se para (antes de cambiar las banderas)
                ld a,(sf_h)
                ld hl,sf_buf
                ld bc,32
                call f_read_n
                ld hl,sf_tab
sl_l:           ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,d
                or e
                jr z,sl_d
                push hl
                ex de,hl
                ld a,(sf_h)
                call f_read_n
                pop hl
                jr sl_l
sl_d:           ld a,(sf_h)
                call f_close
                ld a,1
                ld (FLAGS+6),a          ; restore.game acaba de ejecutarse
                ld (sv_ok),a
                xor a
                ld (st_valid),a         ; la barra de estado se redibuja
                ld a,(it_n)             ; los menus vuelven a estar activados
                or a
                ret z
                ld b,a
                ld hl,it_tab+3
sl_e:           ld (hl),1
                inc hl
                inc hl
                inc hl
                inc hl
                djnz sl_e
                ret

; "Room n  Score m" (con la sala v0 y los puntos v3) en sf_buf, 32 bytes
sf_mkdesc:      ld hl,sf_buf
                ld de,sf_buf+1
                ld bc,31
                ld (hl),0
                ldir
                ld hl,sf_buf
                ld de,s_room
                call sd_cp
                ld a,(VARS)
                call sd_dec
                ld de,s_score2
                call sd_cp
                ld a,(VARS+3)
                jp sd_dec
sd_cp:          ld a,(de)
                or a
                ret z
                ld (hl),a
                inc hl
                inc de
                jr sd_cp
sd_dec:         ld d,0
                ld b,100
                call sd_d1
                ld b,10
                call sd_d1
                add a,'0'
                ld (hl),a
                inc hl
                ret
sd_d1:          ld c,'0'-1
sdd_l:           inc c
                sub b
                jr nc,sdd_l
                add a,b
                ld b,a
                ld a,c
                cp '0'
                jr nz,sd_w
                ld a,d
                or a
                jr z,sd_s
                ld a,'0'
sd_w:           ld (hl),a
                inc hl
                ld d,1
sd_s:           ld a,b
                ret

; HL = nombre acabado en 0 -> A = manejador ($FF si no se puede crear): crea el fichero o lo vacia
f_create:       ld b,0
                push hl
fcr_l:          ld a,(hl)
                or a
                jr z,fcr_e
                inc hl
                inc b
                jr fcr_l
fcr_e:          pop hl
                ld a,CMD_FCREATE
                call mcu_send
                ld a,b
                call mcu_send
                inc b
                jr fcr_t
fcr_s:          ld a,(hl)
                inc hl
                call mcu_send
fcr_t:          djnz fcr_s
                jp mcu_recv

; A = manejador, HL = origen, BC = cuantos: en trozos de CHUNK
f_write_n:      ld (wf_h),a
                ld (wf_src),hl
                ld (wf_cnt),bc
fwn_l:          ld bc,(wf_cnt)
                ld a,b
                or c
                ret z
                ld hl,CHUNK
                or a
                sbc hl,bc
                jr c,fwn_full
                ld d,b
                ld e,c
                jr fwn_go
fwn_full:       ld de,CHUNK
fwn_go:         push de
                ld a,CMD_FWRITE
                call mcu_send
                ld a,(wf_h)
                call mcu_send
                ld a,e
                call mcu_send
                ld a,d
                call mcu_send
                ld hl,(wf_src)
fwn_b:          ld a,(hl)
                inc hl
                call mcu_send
                dec de
                ld a,d
                or e
                jr nz,fwn_b
                ld (wf_src),hl
                call mcu_recv
                ld hl,wf_err
                or (hl)
                ld (hl),a
                pop de
                ld hl,(wf_cnt)
                or a
                sbc hl,de
                ld (wf_cnt),hl
                jr fwn_l

sf_nm:          defb "SAV/GAME0.SAV",0
s_sav:          defb "Save game",0
s_rst:          defb "Restore game",0
s_empty:        defb "(empty)",0
s_room:         defb "Room ",0
s_score2:       defb "  Score ",0
sf_tab:         defw VARS,256, FLAGS,256, INV,256, KEYMAP,256, OBJ,1024, STRS,492
                defw horizon,1, blk,5, pctl,1, lastpic,1, mg_n,33, st_on,1, tfg,2, accin,1, ticks,1
                defw 0
sf_mode:        defb 0
sf_h:           defb 0
dg_i:           defb 0
dg_ep:          defw 0
wf_h:           defb 0
wf_err:         defb 0
wf_src:         defw 0
wf_cnt:         defw 0
sf_buf:         defs 32
sf_ex:          defs 9
sf_desc:        defs 9*32

FONT:
                include "font6.inc"
