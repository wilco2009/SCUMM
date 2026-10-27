; =====================================================================
;  agitxt.asm - texto del interprete AGI. Es un OVERLAY: se ensambla aparte en $2000 (compila: pasmo agitxt.asm agitxt.bin tras agivm.asm,
;  que le da sus simbolos por agires.inc), se guarda como TEXT.OVL (u16 tamano + codigo, TOOLS/mkovl.py) y agivm.asm lo carga en la pagina PG_OVL
;  y lo deja mapeado en el bloque 1 ($2000-$3FFF). El nucleo lo llama por la tabla de saltos del principio (OVL_* en agivm.asm).
;
;  Mismo comportamiento que TOOLS/agi_text.py y las ordenes de texto de TOOLS/agi_vm.py: fuente de 6x8 (font6.bin), 42 columnas por 24 filas, fila 0 =
;  barra de estado, 1-21 = imagen, 22-23 = pie. Una linea de texto se compone por celdas HiRes de 8 pixeles: la cubierta entera pasa a papel = fondo,
;  tinta = color del texto con el bitmap de los glifos; la cubierta a medias recibe solo sus pixeles, uno a uno, con `plot` (agispr.asm).
;  El texto sobre la imagen se escribe tambien en la copia de fondo (PG_BGB/PG_BGA) y manda redibujar los sprites que toca.
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_display            ; OVL_DISPLAY
                jp t_display_v          ; OVL_DISPLAY_V
                jp t_clear_lines        ; OVL_CLEAR
                jp t_status             ; OVL_STATUS (una vez por ciclo)
                jp t_status_on          ; OVL_SON
                jp t_status_off         ; OVL_SOFF
                jp t_set_attr           ; OVL_ATTR

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
                call dl_setpic
                ld a,(dl_pic)
                or a
                call nz,dl_prot
                xor a
                ld (dl_k),a
dl_kl:          ld a,(dl_row)
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
                ld a,(dl_pic)
                or a
                ret z
                jp rect_to_bg

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
                ret

; Con dl_row y dl_ca/dl_nb: dl_pic = 1 si la fila es de la imagen (1-21) y ya hay imagen; entonces dl_rect = su rectangulo de celdas
dl_setpic:      xor a
                ld (dl_pic),a
                ld a,(picvalid)
                or a
                ret z
                ld a,(dl_row)
                or a
                ret z
                cp 22
                ret nc
                ld a,1
                ld (dl_pic),a
                ld a,(dl_row)
                dec a
                add a,a
                add a,a
                add a,a
                ld (dl_rect+2),a
                add a,7
                ld (dl_rect+3),a
                ld a,(dl_ca)
                ld (dl_rect),a
                ld a,(dl_nb)
                ld (dl_rect+1),a
                ret

; Los sprites que tocan dl_rect se marcan para redibujar, y su zona vuelve a la imagen limpia
dl_prot:        ld hl,RECT
                ld ix,OBJ
                ld b,NOBJ
pr_l:           push bc
                push hl
                ld de,dl_rect
                call rect_int
                pop hl
                jr nc,pr_n
                set 1,(ix+O_SDR)
pr_n:           pop bc
                ld de,4
                add hl,de
                ld de,32
                add ix,de
                djnz pr_l
                ld hl,dl_rect
                jp restore_rect

; dl_rect de la pantalla a la copia de fondo
rect_to_bg:     ld a,PG_BGB
                ld de,HR_BM+256
                call rb_plane
                ld a,PG_BGA
                ld de,HR_ATT+256
                call rb_plane
                jp unmap_win

rb_plane:       push de
                call map_page
                ld a,(dl_rect+2)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(dl_rect)
                ld e,a
                ld d,0
                add hl,de               ; desplazamiento
                ld d,h
                ld e,l
                ld hl,LWIN
                add hl,de
                ex de,hl                ; DE = destino en la copia, HL = desplazamiento
                pop bc
                add hl,bc               ; HL = origen en pantalla
                ld a,(dl_rect+3)
                ld b,a
                ld a,(dl_rect+2)
                ld c,a
                ld a,b
                sub c
                inc a
                ld (rrows),a
rb_r:           push hl
                push de
                ld a,(dl_rect+1)
                ld c,a
                ld b,0
                ldir
                pop de
                pop hl
                ld bc,32
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                ld a,(rrows)
                dec a
                ld (rrows),a
                jr nz,rb_r
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
                call dl_setpic
                ld a,(dl_pic)
                or a
                call nz,dl_prot
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
                ld a,(dl_pic)
                or a
                ret z
                jp rect_to_bg

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
dl_pic:         defb 0
dl_rect:        defs 4
LB:             defs 68

FONT:
                include "font6.inc"
