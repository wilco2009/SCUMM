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
                jp t_prt                ; OVB_PRINT
                jp t_boxclose           ; OVB_BOXCLOSE
                jp t_gsdraw             ; OVB_GSDRAW
                jp t_clear_rect         ; OVB_CLRRECT
                IF GFX4
                jp t_fontinit           ; OVB_FONT
                ENDIF

TXT             equ TMPM

                IF GFX4
; el plano de una ventana de print: pr_top, pr_nr filas, pr_cxl, pr_bw columnas, celdas transparentes (la ventana es de pixeles de la imagen; solo el texto lleva celdas)
tp_fillbox:     ld a,(pr_top)
                ld (tb_r),a
                ld a,(pr_nr)
                ld (tb_n),a
tfb_l:          ld a,(pr_cxl)
                ld b,a
                ld a,(pr_bw)
                ld e,a
                ld c,0
                ld a,(tb_r)
                call tp_fill
                ld hl,tb_r
                inc (hl)
                ld hl,tb_n
                dec (hl)
                jr nz,tfb_l
                ret

; la ventana de print en la imagen (4 bpp, 4 pixeles por columna): blanco con el marco rojo de un pixel (codigos de Chroma: blanco 15, rojo 2)
tp_pixbox:      ld a,(pr_top)
                add a,a
                add a,a
                add a,a
                sub 8
                ld (pb_y),a
                ld a,(pr_nr)
                add a,a
                add a,a
                add a,a
                ld (pb_h),a
                ld a,(pr_bw)
                add a,a
                ld (pb_wb),a
                xor a
                ld (pb_k),a
pb_l:           ld a,(pb_y)
                ld hl,pb_k
                add a,(hl)
                call im_off
                ld de,HR_BM
                add hl,de
                ld a,(pr_cxl)
                add a,a
                ld e,a
                ld d,0
                add hl,de
                ld a,(pb_wb)
                ld b,a
                ld c,$FF
                ld a,(pb_k)
                or a
                jr z,pb_r
                ld a,(pb_h)
                dec a
                ld d,a
                ld a,(pb_k)
                cp d
                jr nz,pb_f
pb_r:           ld c,$22
pb_f:           push hl
pb_fl:          ld (hl),c
                inc hl
                djnz pb_fl
                pop hl
                ld a,c
                cp $22
                jr z,pb_nx
                ld (hl),$2F             ; el pixel de la izquierda y el de la derecha
                ld a,(pb_wb)
                dec a
                ld e,a
                ld d,0
                add hl,de
                ld (hl),$F2
pb_nx:          ld hl,pb_k
                inc (hl)
                ld a,(pb_h)
                cp (hl)
                jr nz,pb_l
                ret
; Los glifos de 6 pixeles (ASCII 32-127) a la tabla de la FPGA (TFONT, I = $D8): en los codigos 32-127 y, para el texto inverso (bit 7), en los 160-255
t_fontinit:     ld hl,FONT
                ld de,TFONT+256
                ld bc,768
                ldir
                ld hl,FONT
                ld de,TFONT+1280
                ld bc,768
                ldir
                ret
                ENDIF

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
                cp 25
                ret nc
                cp 24                   ; la fila 24 de AGI (la 25a) no cabe en las 24 del HiRes: va a la 23
                jr c,td_ok
                ld a,23
                ld (dl_row0),a
td_ok:
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
                ld a,TCOLS
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


; ---------------------------------------------------------------------
;  clear.lines: filas A-B con el color C (EGA)
; ---------------------------------------------------------------------
t_clear_lines:  ld a,(ARGS)
                cp 24
                jr c,cl_a
                ld a,23
cl_a:           ld (cl_r),a
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
t_prompt:       ld a,22                 ; la linea de entrada en la fila 22, como en AGI (la 23 queda para la fila 24 de los textos)
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
                ld a,(curchar)
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
                ld a,22
                ld (dl_row),a
                xor a
                ld (dl_col),a
                jp draw_line

s_prompt:       defb "> ",0

; get.string: el mensaje (ARGS+1) y lo escrito (INBUF) con el cursor, en (fila ARGS+2, columna ARGS+3)
t_gsdraw:       ld a,(gs_cust)          ; descripcion de una partida: ventana de mensaje con un cuadro negro de 32 caracteres para la linea
                or a
                jr nz,t_gsdesc
                ld a,(ARGS+1)
                ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT+300
                ld c,100
                call build_str
                ld hl,TXT
                ld (bs_dp),hl
                xor a
                ld (bs_n),a
                ld a,(ARGS+3)
                ld c,a
                ld a,TCOLS
                sub c
                ld (bs_max),a
                ld hl,TXT+300
                call put_str
                ld hl,INBUF
                call put_str
                ld a,(curchar)
                call bs_put
                ld a,' '
                call bs_put
                ld a,(tfg)
                call t_chroma
                ld (dl_fg),a
                ld a,(tbg)
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(bs_n)
                ld (dl_n),a
                ld a,(ARGS+2)
                ld (dl_row),a
                ld a,(ARGS+3)
                ld (dl_col),a
                jp draw_line

; la ventana del mensaje (centrada, 32 de ancho: dos lineas de texto y una de 32 marcas), el cuadro negro encima de esta y la linea escrita (con el cursor) en el
t_gsdesc:       ld a,(gs_cust)          ; la ventana se dibuja una vez (gs_cust 1 -> 3); despues solo el cuadro negro y la linea (si no, parpadea)
                cp 1
                jr nz,gb_go
                ld a,3
                ld (gs_cust),a
                ld hl,s_dsc
                call dg_cp
                ld a,3
                ld (pr_raw),a
                ld a,255
                ld (pr_row),a
                ld a,32
                ld (pr_w),a
                call t_print
                xor a
                ld (pr_raw),a
                ld (pr_w),a
gb_go:          ld a,1
                ld (dl_nobg),a
                IF GFX4
                ld a,(pr_top)           ; el cuadro negro de 32 columnas (la linea de 32 marcas) de la linea
                add a,3
                ld hl,pr_cxl
                ld b,(hl)
                inc b
                ld e,32
                ld c,32
                call tp_fill
                ENDIF
                ld a,(pr_top)
                add a,3
                add a,a
                add a,a
                add a,a
                ld (pr_l),a
                ld a,8
                ld (pr_k),a
                IF GFX4=0
gb_l:           ld a,(pr_l)
                call pr_addr
                inc hl
                push hl
                ld de,HR_BM
                add hl,de
                ld b,24
                xor a
gb_b:           ld (hl),a
                inc hl
                djnz gb_b
                pop hl
                ld de,HR_ATT
                add hl,de
                ld b,24
                ld a,$0F
gb_a:           ld (hl),a
                inc hl
                djnz gb_a
                ld hl,pr_l
                inc (hl)
                ld hl,pr_k
                dec (hl)
                jr nz,gb_l
                ENDIF
                ld hl,TXT
                ld (bs_dp),hl
                xor a
                ld (bs_n),a
                ld a,32
                ld (bs_max),a
                ld hl,INBUF
                call put_str
                ld a,(curchar)
                call bs_put
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(bs_n)
                ld (dl_n),a
                ld a,(pr_top)
                add a,3
                ld (dl_row),a
                ld a,(pr_cxl)
                inc a
                add a,a
                add a,a
                add a,a
                ld (dl_x0),a
                ld a,15
                call t_chroma
                ld (dl_fg),a
                xor a
                call t_chroma
                ld (dl_bg),a
                call draw_line_px
                xor a
                ld (dl_nobg),a
                ret


s_score:        defb " Score:",0
s_of:           defb " of ",0
s_son:          defb "Sound:on"
s_soff:         defb "Sound:off"

tcol0:          defb 0
tterm:          defb 0
st_v3:          defb 0
st_v7:          defb 0
st_f9:          defb 0
cl_r:           defb 0
cl_end:         defb 0

; ---------------------------------------------------------------------
;  Ventanas de mensaje (print): el nucleo pone pr_msg, pr_row (255 = centrada), pr_col y pr_w y llama a t_print (dibuja) y, despues de esperar una tecla,
;  a t_boxclose (devuelve la imagen limpia). Mismo resultado que agi_text.wrap / box_geom / draw_box: lineas de como mucho pr_w caracteres (30 si 0 o mas de 36),
;  una celda de relleno a cada lado y una fila arriba y otra abajo, blanco con letras negras y un marco rojo de un pixel.
; ---------------------------------------------------------------------
; print: cierra antes la ventana que dejo un print no bloqueante (drawMessageBox); con la bandera 15 la ventana se queda abierta, se apaga la bandera y no se espera
; (win_act); si no, el temporizador (v21 en medios segundos, 25 ciclos de espera cada uno; ScummVM lo pone a 0 al cerrar) pasa a pw_lim
t_prt:          ld a,(win_act)
                or a
                jr z,tpr_1
                call t_boxclose
                xor a
                ld (win_act),a
tpr_1:          call t_print
                ld a,(FLAGS+15)
                or a
                jr z,tpr_t
                xor a
                ld (FLAGS+15),a
                inc a
                ld (win_act),a
                ret
tpr_t:          ld a,(VARS+21)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                ld e,a
                ld d,0
                add hl,de
                ld (pw_lim),hl
                xor a
                ld (VARS+21),a
                ret
t_print:        ld a,(pr_raw)           ; 1 = pausa, 2 = reiniciar, 3 = el texto ya esta en TXT; 0 = el mensaje pr_msg de la logica
                or a
                jr z,tp_norm
                cp 4
                jr z,tp_fmt
                cp 3
                jr z,tp_have
                cp 5
                ld hl,s_mem
                jr z,tp_cp
                ld hl,s_pause
                cp 1
                jr z,tp_cp
                ld hl,s_restart
tp_cp:          call dg_cp
                jr tp_have
tp_norm:        ld a,(pr_msg)
                ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,250
                call build_str
                jr tp_have
tp_fmt:         ld a,(curlg)            ; 4 = el texto esta en TXT y lleva formato (%vN...): se expande
                ld (bs_lg),a
                ld hl,TXT
                ld de,MSGBUF
                ld bc,240
                ldir
                ld de,TXT
                ld c,239
                xor a
                ld (bs_n),a
                ld (bs_dp),de
                ld a,c
                ld (bs_max),a
                call bs_fmt
tp_have:        ld a,(pr_w)
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
                IF GFX4
                ld a,c                  ; 160w: una columna por caracter y una de relleno a cada lado; con dibujo (show.obj), la que quepa su ancho (4 pixeles por columna)
                add a,2
                ld (pr_bw),a
                ld a,(oc_pw)
                or a
                jr z,tp_np
                add a,3
                rrca
                rrca
                and 63
                add a,2
                ld hl,pr_bw
                cp (hl)
                jr c,tp_np
                ld (hl),a
                ELSE
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
                ld a,(oc_pw)            ; show.obj: la ventana cabe el dibujo
                or a
                jr z,tp_np
                add a,7
                rrca
                rrca
                rrca
                and 31
                add a,2
                ld hl,pr_bw
                cp (hl)
                jr c,tp_np
                ld (hl),a
                ENDIF
tp_np:          ld a,(wr_n)
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
                ld a,TCELL
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
                IF GFX4=0
                add a,a
                add a,c
                add a,a
                rrca
                rrca
                rrca
                and 31
                ld c,a
                ENDIF
                ld a,(pr_bw)
                ld b,a
                ld a,TCELL
                sub b
                ld d,a
                ld a,c
                cp d
                jr c,tp_c2
                ld a,d
tp_c2:          ld (pr_cxl),a
tp_dr:          ld a,1                  ; lo que se escribe aqui no pasa a la copia de fondo
                ld (dl_nobg),a
                IF GFX4
                xor a
                call tp_save
                call tp_fillbox
                call tp_pixbox
                ENDIF
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
                IF GFX4=0
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
                ENDIF
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
tp_bd:
                IF GFX4=0
ld a,(pr_l0)            ; marco: linea de arriba y de abajo enteras
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
                ENDIF
                xor a
                ld (dl_nobg),a
                ret

; HL = byte del bitmap -> pr_bw bytes a 255
pr_ff:          ld a,(pr_bw)
                ld b,a
                ld a,255
pf_l:           ld (hl),a
                inc hl
                djnz pf_l
                ret

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

wr_w:           defb 0
wr_n:           defb 0
wr_len:         defb 0
wr_lp:          defw 0
wr_tp:          defw 0
wr_np:          defw 0
wr_tl:          defb 0
pr_nr:          defb 0
pr_l0:          defb 0
pr_ln:          defb 0
pr_l:           defb 0
pr_k:           defb 0
pr_i:           defb 0
LN:             defs 40*20

s_dsc:         defb "How would you like to describe this saved game?",10,"################################",0
; HL = cadena acabada en 0 -> TXT (HL queda tras el 0)
dg_cp:          ld de,TXT
dg_c2:          ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,dg_c2
                ret
s_mem:          defb "Enough memory",0
s_pause:        defb "Game paused.",10,10,"Press any key to continue.",0
s_restart:      defb "Press ENTER to restart",10,"the game.",10,10,"Press ESC to continue",10,"this game.",0
                include "agitx.inc"

; clear.text.rect(fila1, col1, fila2, col2, color): el rectangulo de texto se rellena con el color (espacios con ese fondo); las filas pasan de 23 a 23
t_clear_rect:   ld a,(ARGS+4)
                call t_chroma
                ld (dl_fg),a
                ld (dl_bg),a
                ld a,(ARGS+1)
                ld c,a                  ; C = columna 1
                ld a,(ARGS+3)
                cp TCOLS
                jr c,cr_a
                ld a,TCOLS-1
cr_a:           sub c
                ret c                   ; columna 2 < columna 1: nada
                inc a
                ld (cr_n),a
                ld b,a
                ld hl,TXT
                ld a,' '
cr_s:           ld (hl),a
                inc hl
                djnz cr_s
                ld a,(ARGS+2)
                cp 24
                jr c,cr_e
                ld a,23
cr_e:           ld (cr_end),a
                ld a,(ARGS)
                cp 24
                jr c,cr_b
                ld a,23
cr_b:           ld (cr_row),a
cr_l:           ld a,(cr_n)
                ld (dl_n),a
                ld a,(ARGS+1)
                ld (dl_col),a
                ld a,(cr_row)
                ld (dl_row),a
                ld hl,TXT
                ld (dl_ptr),hl
                call draw_line
                ld a,(cr_end)
                ld hl,cr_row
                cp (hl)
                ret c
                ret z
                inc (hl)
                jr cr_l
cr_n:           defb 0
cr_end:         defb 0
cr_row:         defb 0
