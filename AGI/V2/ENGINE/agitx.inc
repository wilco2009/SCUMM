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

; codigo y variables comunes a los overlays B (texto) y F (menus): linea de texto, fondo, ventana
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
; ---------------------------------------------------------------------
;  160w (GFX4): el texto va al plano de 40x25 codigos de la FPGA (TPLANE, fila * 40 + columna); 6 pixeles de glifo por columna. Un solo par tinta / papel
;  (blanco sobre negro) y, con el bit 7 del codigo, negro sobre blanco: fondo 0 = normal, cualquier otro = inverso. Codigo 0 = celda transparente (se ve la imagen).
;  Misma salida que agi_text.put_line / fill_row de TOOLS/agi_text.py con AGI_GFX4=1.
; ---------------------------------------------------------------------
                IF GFX4
; A = fila, B = columna -> HL = TPLANE + 40 * fila + columna (conserva B y C)
tp_addr:        ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                ld e,b
                ld d,0
                add hl,de
                ld de,TPLANE
                add hl,de
                ret

; A = fila, B = columna, E = cuantas, C = codigo: las celdas a ese codigo
tp_fill:        push de
                call tp_addr
                pop de
                ld a,e
                or a
                ret z
                ld b,a
tpf_l:          ld (hl),c
                inc hl
                djnz tpf_l
                ret

; (dl_x0 en pixeles: las ventanas lo ponen siempre en un multiplo de 8) -> dl_col
draw_line_px:   ld a,(dl_x0)
                rrca
                rrca
                rrca
                and 31
                ld (dl_col),a
draw_line:      ld a,(dl_col)
                ld c,a
                ld a,TCOLS
                sub c
                ret c
                ret z
                ld hl,dl_n
                cp (hl)
                jr nc,dl_fit
                ld (hl),a
dl_fit:         ld a,(dl_n)
                or a
                ret z
                ld b,a
                ld a,(dl_bg)
                or a
                ld c,128                ; fondo 0: blanco sobre negro (inverso); cualquier otro: negro sobre blanco
                jr z,dlw_n
                ld c,0
dlw_n:          push bc
                ld a,(dl_row)
                ld hl,dl_col
                ld b,(hl)
                call tp_addr
                ex de,hl
                pop bc
                ld hl,(dl_ptr)
dlw_l:          ld a,(hl)
                inc hl
                cp 32
                jr c,dlw_s
                cp 128
                jr c,dlw_o
dlw_s:          ld a,32
dlw_o:          or c
                ld (de),a
                inc de
                djnz dlw_l
                ret

; dl_row = fila, A = color EGA: la rellena de espacios (negros si el color es 0, blancos si no)
fill_row:       and 15
                ld c,160                ; color 0: espacios inversos (negros); si no, blancos
                jr z,fr_c
                ld c,32
fr_c:           ld a,(dl_row)
                ld b,0
                call tp_addr
                ld d,h
                ld e,l
                inc de
                ld (hl),c
                ld bc,TCOLS-1
                ldir
                ret

text_bg:        ret

; Copia del plano de texto antes de abrir una ventana (A = 0 print, 1 menu): en PG_BGA, tras los 5280 bytes de la imagen limpia (bloque 7: $F4A0 y $F888)
tp_save:        ld (tp_slot),a
                ld a,PG_BGA
                call map7
                ld hl,TPLANE
                ld de,$F4A0
                ld a,(tp_slot)
                or a
                jr z,tps_c
                ld de,$F4A0+1000
tps_c:          ld bc,1000
                ldir
                jp map7_back

; El rectangulo de la ventana (filas pr_l0 / 8 ..., pr_ln / 8 filas, columnas pr_cxl ..., pr_bw) vuelve a lo que habia: la copia de tp_save
t_boxclose:     ld a,(pr_ln)
                rrca
                rrca
                rrca
                and 31
                ret z
                ld (tb_n),a
                ld a,(pr_l0)
                rrca
                rrca
                rrca
                and 31
                ld (tb_r),a
                ld hl,$F4A0-TPLANE
                ld a,(tp_slot)
                or a
                jr z,tbc_s
                ld hl,$F4A0-TPLANE+1000
tbc_s:          ld (tb_off),hl
                ld a,PG_BGA
                call map7
bcw_l:          ld a,(tb_r)
                ld hl,pr_cxl
                ld b,(hl)
                call tp_addr
                ld d,h
                ld e,l
                ld bc,(tb_off)
                add hl,bc
                ld a,(pr_bw)
                ld c,a
                ld b,0
                ldir
                ld hl,tb_r
                inc (hl)
                ld hl,tb_n
                dec (hl)
                jr nz,bcw_l
                call map7_back
                ld a,(tp_slot)
                or a
                ret nz                  ; los menus solo tocan el plano de texto; una ventana de print tambien pinto la imagen
                ld a,(pr_l0)
                sub 8
                ld (pb_y),a
                ld a,(pr_ln)
                ld (pb_h),a
                ld a,(pr_bw)
                add a,a
                ld (pb_wb),a
                xor a
                ld (pb_k),a
ir_l:           ld a,(pb_y)
                ld hl,pb_k
                add a,(hl)
                ld (pb_rr),a
                call im_off
                ld de,HR_BM
                add hl,de
                ld a,(pr_cxl)
                add a,a
                ld e,a
                ld d,0
                add hl,de
                ld (pb_dst),hl          ; destino en la imagen
                ld a,(picvalid)
                or a
                jr z,ir_z
                ld a,(pb_rr)
                ld b,PG_BGB
                cp 102
                jr c,ir_p
                sub 102
                ld b,PG_BGA
ir_p:           call im_off
                ld de,$E000
                add hl,de
                ld a,(pr_cxl)
                add a,a
                ld e,a
                ld d,0
                add hl,de               ; origen: la imagen limpia
                push hl
                ld a,b
                call map7
                pop hl
                ld de,(pb_dst)
                ld a,(pb_wb)
                ld c,a
                ld b,0
                ldir
                jr ir_nx
ir_z:           ld hl,(pb_dst)          ; sin imagen: negro
                ld a,(pb_wb)
                ld b,a
                xor a
ir_zl:          ld (hl),a
                inc hl
                djnz ir_zl
ir_nx:          ld hl,pb_k
                inc (hl)
                ld a,(pb_h)
                cp (hl)
                jr nz,ir_l
                jp map7_back

; A = linea de la imagen -> HL = A * 80 (conserva B y DE)
im_off:         push de
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                pop de
                ret

tp_slot:        defb 0
pb_y:           defb 0
pb_h:           defb 0
pb_wb:          defb 0
pb_k:           defb 0
pb_rr:           defb 0
pb_dst:         defw 0
tb_r:           defb 0
tb_off:         defw 0
                ELSE
draw_line:      ld a,(dl_col)           ; el texto no pasa de la columna 42 (con la suma de 8 bits de abajo, una barra de menu de 43 columnas dibujaba basura)
                ld c,a
                ld a,42
                sub c
                ret c
                ret z
                ld hl,dl_n
                cp (hl)
                jr nc,dl_fit
                ld (hl),a
dl_fit:         ld a,(dl_col)
                ld b,a
                add a,a
                add a,b
                add a,a
                ld (dl_x0),a            ; x0 = col * 6
draw_line_px:
                ld a,(dl_x0)            ; (entrada con x0 en pixeles: las ventanas)
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

; dl_row = fila, A = color EGA: la rellena (bitmap 0, papel = tinta = color)
fill_row:
                call t_chroma
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

; Texto escrito sobre la imagen (filas 1-21): dl_row, dl_ca, dl_nb pasan de la pantalla a la copia de fondo y los rotulos se recomponen
text_bg:
                ld a,(dl_nobg)
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


; La imagen limpia (copia de fondo) en el rectangulo de la ventana
t_boxclose:
                ld a,(picvalid)
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
                ENDIF

; ---------------------------------------------------------------------
;  Reparto del mensaje (TXT) en lineas de wr_w caracteres, en LN (40 bytes por linea: largo y caracteres) y su numero en wr_n
; ---------------------------------------------------------------------

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
bc_base:        defw 0
tb_base:       defw 0
tb_l:           defb 0
tb_n:           defb 0

dl_nobg:        defb 0
FONT:
                include "font6.inc"
