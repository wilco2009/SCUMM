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
                IF GFX4
                ret
                ENDIF
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
                IF GFX4
                ret
                ENDIF
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
                IF GFX4
                ret
                ENDIF
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
                IF GFX4
                ret
                ENDIF
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
