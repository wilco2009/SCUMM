; =====================================================================
;  hrui.asm - la interfaz en HiRes (rama hires16), 40 columnas de 6 pixeles. La interfaz escribe en UIVB (40 x 8, las filas UI_R0..23) y los mensajes
;  en MSGB (TXT_ROWS x 40; mientras tx_on tapan las filas TXT_ROW.. de la interfaz). hr_ui, una vez por fotograma, pinta en el bitmap y los atributos los
;  grupos de 4 caracteres (4 x 6 = 24 pixeles = 3 bytes) que han cambiado desde la ultima vez (HRUI_PREV guarda los codigos pintados). El texto va centrado
;  (un byte de margen a cada lado: 240 de 256 pixeles). La fuente (TILES, scumm.asm) son las columnas 1-6 de los glifos de la ROM del ZX81, 6 bits por linea.
;  Texto blanco brillante sobre negro (los atributos son de 8 pixeles).
; =====================================================================
HRUI_PREV       equ $DEC0               ; 8 filas x 40 columnas: el codigo que hay pintado en cada celda (en el bloque de atributos: sitio libre)
HU_GL           equ HR_ATT+$1900        ; 4 glifos x 8 lineas (el buffer de abajo del scroll vertical, que no usamos)
hu_r            equ ACSIG+157           ; fila (0-7) y grupo (0-9) que se pintan
hu_g            equ ACSIG+158
hu_src          equ ACSIG+159           ; palabra: detras de los 4 caracteres del grupo

hr_ui:          push ix
                xor a
                ld (hu_r),a
hu_row:         ld a,(hu_r)             ; HL = origen de la fila
                ld c,a
                ld a,(tx_on)
                or a
                jr z,hu_vb
                ld a,c
                cp TXT_ROW-UI_R0
                jr c,hu_vb
                sub TXT_ROW-UI_R0
                call hu_mul40
                ld de,MSGB
                jr hu_sr
hu_vb:          ld a,c
                call hu_mul40
                ld de,UIVB
hu_sr:          add hl,de
                push hl                 ; origen
                ld a,(hu_r)
                call hu_mul40
                ld de,HRUI_PREV
                add hl,de
                ex de,hl                ; DE = lo pintado
                pop hl
                xor a
                ld (hu_g),a
hu_gr:          push hl
                push de
                ld c,4
hu_cmp:         ld a,(de)
                cp (hl)
                jr nz,hu_diff
                inc hl
                inc de
                dec c
                jr nz,hu_cmp
                pop de
                pop hl
                ld bc,4
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                jr hu_next
hu_diff:        pop de
                pop hl
                ldi
                ldi
                ldi
                ldi                     ; lo nuevo pasa a lo pintado
                ld (hu_src),hl
                push hl
                push de
                call hu_group
                pop de
                pop hl
hu_next:        ld a,(hu_g)
                inc a
                ld (hu_g),a
                cp 10
                jr nz,hu_gr
                ld a,(hu_r)
                inc a
                ld (hu_r),a
                cp 24-UI_R0
                jr nz,hu_row
                pop ix
                ret

hu_mul40:       ld l,a                  ; A * 40 -> HL
                ld h,0
                ld e,l
                ld d,h
                add hl,hl
                add hl,hl
                add hl,de
                add hl,hl
                add hl,hl
                add hl,hl
                ret

; pinta el grupo hu_g de la fila hu_r: los 4 codigos estan antes de (hu_src)
hu_group:       ld hl,(hu_src)
                ld bc,-4
                add hl,bc
                ld de,HU_GL
                ld b,4
hg_c:           push bc
                push hl
                ld a,(hl)
                cp 208
                jr nc,hg_s
                ld hl,hu_zero
                jr hg_cp
hg_s:           ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                push de
                ld de,TILES
                add hl,de
                pop de
hg_cp:          ld bc,8
                ldir
                pop hl
                inc hl
                pop bc
                djnz hg_c
                ld a,(hu_g)             ; destino: fila hu_r de la zona de la interfaz, byte 1 + 3 * grupo, linea 0
                ld c,a
                add a,a
                add a,c
                inc a
                ld l,a
                ld a,(hu_r)
                add a,(HR_BM>>8)+UI_R0
                ld h,a
                ld ix,HU_GL
                ld b,8
hg_l:           ld a,(ix+0)             ; x1 << 2 | x2 >> 4
                add a,a
                add a,a
                ld c,a
                ld a,(ix+8)
                srl a
                srl a
                srl a
                srl a
                or c
                ld (hl),a
                inc hl
                ld a,(ix+8)             ; (x2 & 15) << 4 | x3 >> 2
                and 15
                add a,a
                add a,a
                add a,a
                add a,a
                ld c,a
                ld a,(ix+16)
                srl a
                srl a
                or c
                ld (hl),a
                inc hl
                ld a,(ix+16)            ; (x3 & 3) << 6 | x4
                and 3
                rrca
                rrca
                or (ix+24)
                ld (hl),a
                ld de,30
                add hl,de
                inc ix
                djnz hg_l
                ld a,(hu_g)             ; los atributos de esos 3 bytes: blanco brillante sobre negro
                ld c,a
                add a,a
                add a,c
                inc a
                ld l,a
                ld a,(hu_r)
                add a,(HR_ATT>>8)+UI_R0
                ld h,a
                ld b,8
                call hu_clr
hg_a:           ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                ld de,30
                add hl,de
                djnz hg_a
                ret
; A = atributo del texto de la fila hu_r: blanco brillante, o (los mensajes) el color del que habla
hu_clr:         ld a,(tx_on)
                or a
                jr z,hc_w
                ld a,(hu_r)
                cp TXT_ROW-UI_R0
                jr c,hc_w
                ld a,(tx_clr)
                ret
hc_w:           ld a,$0F
                ret
hu_zero:        defs 8,0
