; =====================================================================
;  hrui.asm - la interfaz en HiRes (rama hires16): la interfaz y los mensajes siguen escribiendo en la rejilla de caracteres DFILE (33 x 24) como
;  siempre; hr_ui, una vez por fotograma, pinta en el bitmap y los atributos las celdas de las filas UI_R0..23 que han cambiado desde la ultima vez
;  (HRUI_PREV guarda los codigos ya pintados). Los glifos son los 208-255 de scumm.asm (TILES): los 210-255 la fuente, en blanco brillante sobre negro, y
;  los 208-209 las flechas del inventario, en amarillo brillante. Cualquier otro codigo se pinta en negro.
; =====================================================================
HRUI_PREV       equ $DF00
hu_att          equ ACSIG+164           ; (el overlay es de solo lectura: las variables van en RAM)               ; 8 filas x 32 columnas: el codigo que hay pintado en cada celda (en el bloque de atributos: sitio libre)

hr_ui:          ld hl,DFILE+1+UI_R0*33
                ld de,HRUI_PREV
                ld c,0
hu_row:         ld b,0
hu_col:         ld a,(de)
                cp (hl)
                jr z,hu_same
                ld a,(hl)
                call hu_cell
hu_same:        inc hl
                inc de
                inc b
                ld a,b
                cp 32
                jr nz,hu_col
                inc hl                  ; la rejilla tiene 33 columnas
                inc c
                ld a,c
                cp 24-UI_R0
                jr nz,hu_row
                ret

; A = codigo, HL = su celda de la rejilla, DE = su sitio en HRUI_PREV, B = columna, C = fila (0 = UI_R0): lo pinta
hu_cell:        push hl
                push de
                push bc
                ld (de),a
                ld d,a
                ld e,$0F
                cp 210
                jr nc,hu_a
                ld e,$0E
                cp 208
                jr nc,hu_a
                ld e,0
hu_a:           ld a,e
                ld (hu_att),a
                ld a,d
                cp 208
                jr nc,hu_s
                ld hl,hu_zero
                jr hu_d
hu_s:           ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,TILES
                add hl,de
hu_d:           pop bc
                push bc
                ld a,c
                add a,(HR_BM>>8)+UI_R0
                ld d,a
                ld e,b
                ld b,8
hu_b:           ld a,(hl)
                cpl                     ; las formas de TILES estan al reves (el bit 7 del codigo invertia el video)
                ld (de),a
                inc hl
                ld a,e
                add a,32
                ld e,a
                djnz hu_b
                pop bc
                push bc
                ld a,(hu_att)
                ld l,a
                ld a,c
                add a,(HR_ATT>>8)+UI_R0
                ld d,a
                ld e,b
                ld b,8
hu_t:           ld a,l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                djnz hu_t
                pop bc
                pop de
                pop hl
                ret
hu_zero:        defs 8,$FF
