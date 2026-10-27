; =====================================================================
;  agisw.asm - rotulos anchos al bitmap (se incluye desde agitxt.asm, es parte del overlay)
;
;  Una celda con mas de 6 mosaicos en una fila (los rotulos de las introducciones: hasta 23) no cabe en los sprites (12 por linea): se dibuja en el bitmap,
;  por celdas de 8 pixeles con el borde izquierdo en la celda (lo(x) + 4) / 8, de menor a mayor prioridad, sobre la copia limpia de la imagen (paginas
;  PG_BGB / PG_BGA, que se leen por el bloque 7). Una fila de mosaico con sus 8 posiciones opacas escribe el bitmap y el atributo de la celda tal cual
;  (no depende de lo que hubiera); una a medias parte de la celda de la imagen y pone sus pixeles uno a uno con `plot`.
;  Asi, si un rotulo solo cambia de colores (misma huella de las mascaras, mismo sitio) se vuelve a escribir encima, sin borrar nada: es lo que se ve en
;  las introducciones. Si cambia de forma, de sitio, aparece o desaparece (o se escribe texto sobre la imagen) se restauran los rectangulos de todos los
;  rotulos y se vuelven a escribir. Mismo resultado que Interp.sw_blit() de TOOLS/agi_vm.py.
;  El estado de cada rotulo esta en los bytes 23-31 de su registro de objeto (O_SDR...); SWR lleva el rectangulo y lo que toca hacer.
; =====================================================================

O_SDR           equ 23                  ; bit 0: esta puesto en el bitmap
O_SVW           equ 24                  ; vista, bucle, celda, x, y, prioridad y huella con los que se puso
O_SLP           equ 25
O_SCL           equ 26
O_SX            equ 27
O_SY            equ 28
O_SPR           equ 29
O_SHL           equ 30
O_SHH           equ 31
PG_BGB          equ 31
PG_BGA          equ 32

; A = pagina -> bloque 7 ($E000); map7_back lo devuelve a su pagina
map7:           ld b,a
                ld c,MAP_PORT
                ld a,7
                out (c),a
                ret
map7_back:      ld a,7
                jr map7

; La imagen que acaba de dibujarse (en la pantalla) pasa a las paginas de fondo; ningun rotulo esta puesto
t_bgsave:       ld a,PG_BGB
                call map_page
                ld hl,HR_BM+256
                ld de,LWIN
                ld bc,PLANEB
                ldir
                ld a,PG_BGA
                call map_page
                ld hl,HR_ATT+256
                ld de,LWIN
                ld bc,PLANEB
                ldir
                call unmap_win
                ld ix,OBJ
                ld de,32
                ld b,NOBJ
sqb_l:           ld (ix+O_SDR),0
                add ix,de
                djnz sqb_l
                xor a
                ld (sw_force),a
                ret

; ---------------------------------------------------------------------
;  Que hay que hacer con cada objeto (SWR+4: 0 nada, 1 solo recolorear, 2 restaurar y escribir, 3 solo restaurar)
; ---------------------------------------------------------------------
sw_scan:        xor a
                ld (swfull),a
                ld (sqs_n),a
                ld ix,OBJ
sqs_l:           ld a,(sqs_n)
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,SWR
                add hl,de
                ld (sqs_r),hl
                ld de,4
                add hl,de
                ld (hl),0               ; que hacer
                inc hl
                ld (hl),0               ; es rotulo ahora
                ld a,(ix+O_F1)
                and 3
                cp 3
                jp nz,sqs_nd
                ld a,(picvalid)
                or a
                jp z,sqs_nd
                call cel_open
                jp c,sqs_nd
                ld a,(cv_fl)
                ld c,a
                call unmap_win
                ld a,c
                and 1
                jr z,sqs_nd
                ld hl,(sqs_r)
                ld de,5
                add hl,de
                ld (hl),1
                inc hl
                ld a,(cv_hl)
                ld (hl),a
                inc hl
                ld a,(cv_hh)
                ld (hl),a
                bit 0,(ix+O_SDR)
                jr z,sqs_new
                ld a,(ix+O_VIEW)
                cp (ix+O_SVW)
                jr nz,sqs_new
                ld a,(ix+O_LOOP)
                cp (ix+O_SLP)
                jr nz,sqs_new
                ld a,(ix+O_X)
                cp (ix+O_SX)
                jr nz,sqs_new
                ld a,(ix+O_Y)
                cp (ix+O_SY)
                jr nz,sqs_new
                ld a,(ix+O_PRI)
                cp (ix+O_SPR)
                jr nz,sqs_new
                ld a,(ix+O_CEL)
                cp (ix+O_SCL)
                jr z,sqs_nx              ; ni la celda cambio
                ld a,(cv_hl)
                cp (ix+O_SHL)
                jr nz,sqs_new
                ld a,(cv_hh)
                cp (ix+O_SHH)
                jr nz,sqs_new
                ld hl,(sqs_r)            ; misma forma en el mismo sitio: solo cambian los colores
                ld de,4
                add hl,de
                ld (hl),1
                jr sqs_nx
sqs_new:         ld hl,(sqs_r)
                ld de,4
                add hl,de
                ld (hl),2
                ld a,1
                ld (swfull),a
                jr sqs_nx
sqs_nd:          bit 0,(ix+O_SDR)       ; ya no es un rotulo: si estaba puesto, hay que quitarlo
                jr z,sqs_nx
                ld hl,(sqs_r)
                ld de,4
                add hl,de
                ld (hl),3
                ld a,1
                ld (swfull),a
sqs_nx:          ld de,32
                add ix,de
                ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jp c,sqs_l
                ld a,(sw_force)
                or a
                ret z
                ld a,1
                ld (swfull),a
                ret

; Si algun rotulo cambio de forma, de sitio... se restaura todo lo puesto y se vuelven a escribir todos
sw_restore:     ld a,(swfull)
                or a
                ret z
                xor a
                ld (sqs_n),a
                ld ix,OBJ
sqr_l:           ld a,(sqs_n)
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,SWR
                add hl,de
                ld (sqs_r),hl
                bit 0,(ix+O_SDR)
                jr z,sqr_c
                call restore_sw
sqr_c:           ld hl,(sqs_r)
                ld de,4
                add hl,de
                ld a,(hl)
                cp 3
                jr nz,sqr_k
                ld (ix+O_SDR),0
                jr sqr_n
sqr_k:           inc hl
                ld a,(hl)
                or a
                jr z,sqr_n
                dec hl
                ld (hl),2               ; todos los rotulos se escriben de nuevo
sqr_n:           ld de,32
                add ix,de
                ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sqr_l
                ret

; HL = SWR del objeto: sus celdas y lineas vuelven a la copia limpia de la imagen
restore_sw:     ld hl,(sqs_r)
                ld a,(hl)
                ld (sqz_cx),a
                inc hl
                ld a,(hl)
                or a
                ret z
                ld (sqz_nb),a
                inc hl
                ld a,(hl)
                ld (sqz_y0),a
                inc hl
                ld a,(hl)
                ld (sqz_y1),a
                ld a,PG_BGB
                ld de,HR_BM
                call sqz_plane
                ld a,PG_BGA
                ld de,HR_ATT
                call sqz_plane
                jp map7_back
sqz_plane:       ld (sqz_base),de
                call map7
                ld a,(sqz_y0)
                ld (sqz_l),a
sqz_row:         ld a,(sqz_l)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(sqz_cx)
                ld e,a
                ld d,0
                add hl,de               ; linea * 32 + celda
                push hl
                ld de,(sqz_base)
                add hl,de               ; destino: la pantalla
                ex (sp),hl              ; HL = desplazamiento
                ld de,$DF00             ; origen: la copia (la fila 0 de la imagen es la linea 8)
                add hl,de
                ex de,hl
                pop hl
                ex de,hl                ; HL = origen, DE = destino
                ld a,(sqz_nb)
                ld c,a
                ld b,0
                ldir
                ld hl,sqz_l
                inc (hl)
                ld a,(sqz_y1)
                cp (hl)
                jr nc,sqz_row
                ret

; ---------------------------------------------------------------------
;  Escribe un rotulo (llamado por spr_obj con la pagina de su bucle mapeada, IX = objeto, rn = su numero)
; ---------------------------------------------------------------------
sw_blit:        ld a,(rn)
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,SWR
                add hl,de
                ld (sw_r),hl
                ld de,4
                add hl,de
                ld a,(hl)
                or a
                jp z,hw_end             ; no hay nada que hacer
                ld a,(ix+O_X)
                call lo16
                ld de,4
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,l
                ld (sw_cx),a            ; celda del borde izquierdo
                ld l,(ix+O_Y)
                ld h,0
                ld a,(cv_h)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld de,9                 ; 8 (barra de estado) + 1
                add hl,de
                ld (sw_top),hl          ; linea de pantalla de la primera fila de la celda (con signo)
                ; rectangulo: celdas
                ld a,(cv_w)
                ld l,a
                ld h,0
                ld de,7
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld b,l                  ; mosaicos de ancho
                ld a,32
                ld hl,sw_cx
                sub (hl)
                jr c,sqk_n0
                jr z,sqk_n0
                cp b
                jr c,sqk_nk
                ld a,b
sqk_nk:          ld (sw_nb),a
                jr sqk_ny
sqk_n0:          xor a
                ld (sw_nb),a
sqk_ny:          ; lineas
                ld hl,(sw_top)
                ld a,(cv_h)
                ld e,a
                ld d,0
                add hl,de
                dec hl                  ; ultima linea
                bit 7,h
                jr nz,sqk_empty
                ld a,h
                or a
                jr nz,sqk_y1c
                ld a,l
                cp 8
                jr c,sqk_empty
                cp 176
                jr c,sqk_y1
sqk_y1c:         ld a,175
sqk_y1:          ld (sw_y1),a
                ld hl,(sw_top)
                bit 7,h
                jr nz,sqk_y0l
                ld a,h
                or a
                jr nz,sqk_empty
                ld a,l
                cp 176
                jr nc,sqk_empty
                cp 8
                jr nc,sqk_y0
sqk_y0l:         ld a,8
sqk_y0:          ld (sw_y0),a
                jr sqk_rect
sqk_empty:       xor a
                ld (sw_nb),a
                ld (sw_y0),a
                ld (sw_y1),a
sqk_rect:        ld hl,(sw_r)
                ld a,(sw_cx)
                ld (hl),a
                inc hl
                ld a,(sw_nb)
                ld (hl),a
                inc hl
                ld a,(sw_y0)
                ld (hl),a
                inc hl
                ld a,(sw_y1)
                ld (hl),a
                ld a,(sw_nb)
                or a
                jp z,sqk_state
                xor a
                ld (sw_i),a
                ld hl,(cv_p)
                ld (sw_p),hl
swt:            ld a,(sw_i)
                ld hl,cv_n
                cp (hl)
                jp nc,sqk_state
                ld hl,(sw_p)
                ld a,(hl)               ; tx
                ld b,a
                ld a,(sw_cx)
                add a,b
                cp 32
                jr nc,swt_nx
                ld (sw_cell),a
                inc hl
                ld a,(hl)               ; ty
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(sw_top)
                add hl,de
                ld (sw_base),hl
                xor a
                ld (sw_r2),a
swr:            ld a,(sw_r2)
                ld e,a
                ld d,0
                ld hl,(sw_base)
                add hl,de
                ld a,h
                or a
                jr nz,swr_nx
                ld a,l
                cp 8
                jr c,swr_nx
                cp 176
                jr nc,swr_nx
                ld (sw_L),a
                ld hl,(sw_p)
                ld a,(sw_r2)
                ld e,a
                ld d,0
                add hl,de
                ld (sw_rp),hl
                ld de,18
                add hl,de
                ld a,(hl)               ; mascara
                or a
                jr z,swr_nx
                ld (sw_m),a
                ld hl,(sw_rp)
                ld de,10
                add hl,de
                ld a,(hl)
                ld (sw_pix),a
                ld hl,(sw_rp)
                ld de,2
                add hl,de
                ld a,(hl)
                ld (sw_col),a
                call blit_cell
swr_nx:         ld hl,sw_r2
                inc (hl)
                ld a,(hl)
                cp 8
                jr c,swr
swt_nx:         ld hl,(sw_p)
                ld de,26
                add hl,de
                ld (sw_p),hl
                ld hl,sw_i
                inc (hl)
                jp swt
sqk_state:       ld (ix+O_SDR),1
                ld a,(ix+O_VIEW)
                ld (ix+O_SVW),a
                ld a,(ix+O_LOOP)
                ld (ix+O_SLP),a
                ld a,(ix+O_CEL)
                ld (ix+O_SCL),a
                ld a,(ix+O_X)
                ld (ix+O_SX),a
                ld a,(ix+O_Y)
                ld (ix+O_SY),a
                ld a,(ix+O_PRI)
                ld (ix+O_SPR),a
                ld a,(cv_hl)
                ld (ix+O_SHL),a
                ld a,(cv_hh)
                ld (ix+O_SHH),a
                jp hw_end

; sw_L (8-175), sw_cell (0-31), sw_m, sw_pix, sw_col (tinta*16 + papel)
blit_cell:      ld a,(sw_L)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld (sw_srow),hl         ; linea * 32
                ld a,(sw_cell)
                ld e,a
                ld d,0
                add hl,de
                ld (sw_off),hl
                ld a,(sw_m)
                cp $FF
                jr nz,sqc_part
                ld hl,(sw_off)
                ld de,HR_BM
                add hl,de
                ld a,(sw_pix)
                ld (hl),a
                ld a,h
                add a,$20
                ld h,a
                ld a,(sw_col)
                rrca
                rrca
                rrca
                rrca                    ; papel * 16 + tinta
                ld (hl),a
                ret
sqc_part:        ld a,PG_BGB             ; la celda de la imagen limpia
                call map7
                ld hl,(sw_off)
                ld de,$DF00
                add hl,de
                ld a,(hl)
                ld (sw_t1),a
                ld a,PG_BGA
                call map7
                ld hl,(sw_off)
                ld de,$DF00
                add hl,de
                ld a,(hl)
                ld (sw_t2),a
                call map7_back
                ld hl,(sw_off)
                ld de,HR_BM
                add hl,de
                ld a,(sw_t1)
                ld (hl),a
                ld a,h
                add a,$20
                ld h,a
                ld a,(sw_t2)
                ld (hl),a
                ld hl,(sw_srow)
                ld de,HR_BM
                add hl,de
                ld (srow),hl
                ld a,(sw_cell)
                add a,a
                add a,a
                add a,a
                ld (sw_hx),a
                ld a,$80
                ld (sw_bm),a
sqp_l:           ld a,(sw_m)
                ld hl,sw_bm
                and (hl)
                jr z,sqp_n
                ld a,(sw_pix)
                and (hl)
                ld a,(sw_col)
                jr z,sqp_p
                rrca
                rrca
                rrca
                rrca
sqp_p:           and 15
                ld (sch),a
                ld a,(sw_hx)
                call plot
sqp_n:           ld hl,sw_hx
                inc (hl)
                ld hl,sw_bm
                srl (hl)
                jr nz,sqp_l
                ret

; Texto escrito sobre la imagen (filas 1-21): dl_row, dl_ca, dl_nb pasan de la pantalla a la copia de fondo y los rotulos se reescriben
text_bg:        ld a,(picvalid)
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
                call sqt_plane
                ld a,PG_BGA
                ld de,HR_ATT
                call sqt_plane
                jp map7_back
sqt_plane:       ld (sqt_base),de
                call map7
                ld a,(dl_row)
                add a,a
                add a,a
                add a,a
                ld (sqt_l),a
                ld a,8
                ld (sqt_n),a
sqt_row:         ld a,(sqt_l)
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
                ld de,(sqt_base)
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
                ld hl,sqt_l
                inc (hl)
                ld hl,sqt_n
                dec (hl)
                jr nz,sqt_row
                ret

swfull:         defb 0
sw_force:       defb 0
sqs_n:           defb 0
sqs_r:           defw 0
sw_r:           defw 0
sw_cx:          defb 0
sw_top:         defw 0
sw_nb:          defb 0
sw_y0:          defb 0
sw_y1:          defb 0
sw_i:           defb 0
sw_p:           defw 0
sw_cell:        defb 0
sw_base:        defw 0
sw_r2:          defb 0
sw_L:           defb 0
sw_rp:          defw 0
sw_m:           defb 0
sw_pix:         defb 0
sw_col:         defb 0
sw_off:         defw 0
sw_srow:        defw 0
sw_t1:          defb 0
sw_t2:          defb 0
sw_hx:          defb 0
sw_bm:          defb 0
sqz_cx:          defb 0
sqz_nb:          defb 0
sqz_y0:          defb 0
sqz_y1:          defb 0
sqz_l:           defb 0
sqz_base:        defw 0
sqt_base:        defw 0
sqt_l:           defb 0
sqt_n:           defb 0
SWR:            defs 8*32
