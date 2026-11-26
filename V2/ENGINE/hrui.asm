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
; texto arriba (tecla T, hv_top): una segunda pasada pinta MSGB en las filas 0-3 (la banda fija, que no hace scroll)
TOPPREV         equ $DD00               ; 4 filas x 40: lo pintado en la banda (bloque de atributos: sitio libre)
hu_pass         equ ACSIG+170           ; 0: la zona de la interfaz, 1: la banda de arriba
hu_rb           equ ACSIG+171           ; fila de pantalla de la fila 0 de la pasada
hu_n            equ ACSIG+172           ; filas de la pasada
hu_pv           equ ACSIG+173           ; palabra: lo pintado de la pasada
hu_bk           equ ACSIG+176           ; la tecla B en el fotograma anterior (bit 4 del puerto $7F)
hu_xk           equ ACSIG+177           ; teclas U I J K L del fotograma anterior (1 = pulsada): bits 7 6 3 2 1
hu_dk           equ ACSIG+178           ; la tecla '.' en el fotograma anterior (bit 1 del puerto $7F)
hu_tk           equ ACSIG+175           ; la tecla T en el fotograma anterior (bit 4 del puerto $FB: 0 = pulsada)

hr_ui:          push ix
                call hu_xkey
                call hu_tkey
                ld a,(hv_top)           ; sin nada escrito (HU_DRT) y con las mismas fuentes (tx_on, hv_top) no hay nada que comparar
                add a,a
                ld hl,tx_on
                or (hl)
                ld hl,HU_ST
                cp (hl)
                ld (hl),a
                jr nz,hu_go
                ld hl,(HU_DRT)
                ld a,h
                or l
                jp z,hu_end
hu_go:          ld hl,0
                ld (HU_DRT),hl
                xor a
                ld (hu_pass),a
                ld a,UI_R0
                ld (hu_rb),a
                ld a,24-UI_R0
                ld (hu_n),a
                ld hl,HRUI_PREV
                ld (hu_pv),hl
                xor a
                ld (hu_r),a
hu_row:         ld a,(hu_r)             ; HL = origen de la fila
                ld c,a
                ld a,(hu_pass)
                or a
                ld a,c
                jr nz,hu_ms             ; la banda de arriba: siempre MSGB
                ld a,(hv_top)
                or a
                jr nz,hu_vb             ; con el texto arriba la interfaz no se tapa
                ld a,(tx_on)
                or a
                jr z,hu_vb
                ld a,c
                cp TXT_ROW-UI_R0
                jr c,hu_vb
                sub TXT_ROW-UI_R0
hu_ms:          call hu_mul40
                ld de,MSGB
                jr hu_sr
hu_vb:          ld a,c
                call hu_mul40
                ld de,UIVB
hu_sr:          add hl,de
                push hl                 ; origen
                ld a,(hu_r)
                call hu_mul40
                ld de,(hu_pv)
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
                ld hl,hu_n
                cp (hl)
                jp nz,hu_row
                ld a,(hu_pass)
                or a
                jr nz,hu_end
                ld a,(hv_top)
                or a
                jr z,hu_end
                ld a,1                  ; segunda pasada: la banda de arriba
                ld (hu_pass),a
                xor a
                ld (hu_rb),a
                ld (hu_r),a
                ld a,TXT_ROWS
                ld (hu_n),a
                ld hl,TOPPREV
                ld (hu_pv),hl
                jp hu_row
hu_end:         pop ix
                ret

; teclas extra de A9 (flanco), como el input.cpp/verbs.cpp de ScummVM v2: U/J desplazan el inventario de 2 en 2 (arriba/abajo), I K L (y O, que aqui es el cursor)
; cogen la ranura 0, 2, 3; SHIFT+J ('-') y SHIFT+K ('+') cambian la velocidad del texto (0-9, de 1 en 1; TXSPD)
hu_xkey:        ld a,$FE
                in a,(254)
                and 1
                ld d,a                  ; D = 0 si SHIFT
                ld a,$DF
                in a,(254)
                and $0C
                add a,a
                add a,a
                add a,a
                add a,a                 ; U = bit 7, I = bit 6
                ld b,a
                ld a,$BF
                in a,(254)
                and $0E                 ; J = 3, K = 2, L = 1
                or b
                cpl
                and $CE
                ld hl,hu_xk
                ld b,(hl)
                ld (hl),a
                ld c,a
                ld a,b
                cpl
                and c
                ret z
                ld c,a                  ; C = recien pulsadas
                ld a,d
                or a
                jr z,hx_sh
                ld a,(UI_IFACE)
                bit 6,a
                ret z
                bit 7,c
                jr z,hx_j
                ld a,(UI_INVO)
                cp 2
                ret c
                sub 2
                jr hx_set
hx_j:           bit 3,c
                jr z,hx_o
                ld a,(UI_INVO)
                add a,4
                ld b,a
                call ui_inv_count
                cp b
                ret z
                ret c
                ld a,(UI_INVO)
                add a,2
hx_set:         ld (UI_INVO),a
                ld hl,UI_DIRTY
                set 2,(hl)
                ret
hx_o:           ld a,1
                bit 6,c
                jr nz,hx_pk
                ld a,3
                bit 2,c
                jr nz,hx_pk
                ld a,4
                bit 1,c
                ret z
hx_pk:          ld hl,UI_INVO
                add a,(hl)
                call ui_inv_find
                ld a,h
                or l
                ret z
                ld a,3                  ; zona del inventario: el objeto
                jp uk_set
hx_sh:          ld a,(TXSPD)
                xor 6
                ld b,a
                bit 3,c                 ; J: '-'
                jr z,hx_k
                or a
                ret z
                dec b
                jr hx_w
hx_k:           bit 2,c                 ; K: '+'
                ret z
                ld a,b
                cp 9
                ret nc
                inc b
hx_w:           ld a,b
                xor 6
                ld (TXSPD),a
                ret

; la tecla T (flanco) alterna la posicion del texto: abajo (filas 20-23, imagen entera) o arriba (filas 0-3 fijas; la sala pierde esas filas)
hu_tkey:        ld a,$7F                ; B (flanco): salta el mensaje en pantalla (como el '.' de ScummVM: se acaba la espera, el nucleo pasa al siguiente trozo o lo da por terminado)
                in a,(254)
                and $10
                ld hl,hu_bk
                ld c,(hl)
                ld (hl),a
                or a
                jr nz,ht_nb
                ld a,c
                or a
                jr z,ht_nb
                ld hl,0
                ld (TALKDLY),hl
                ld hl,(CUTPTR)          ; ademas, con una cutscene con override en marcha, la B es el clic derecho (ESC, scumm.asm kr_esc)
                ld a,h
                or l
                jr z,ht_nb
                push de
                call kr_esc
                pop de
ht_nb:          ld a,$7F                ; '.' (flanco, la VAR_TALKSTOP_KEY de ScummVM): solo acaba la espera del mensaje (no aborta la cutscene, como la B)
                in a,(254)
                and 2
                ld hl,hu_dk
                ld c,(hl)
                ld (hl),a
                or a
                jr nz,ht_nd
                ld a,c
                or a
                jr z,ht_nd
                ld hl,0
                ld (TALKDLY),hl
ht_nd:          ld a,$FB
                in a,(254)
                and $10
                ld hl,hu_tk
                ld c,(hl)
                ld (hl),a
                or a
                ret nz                  ; no esta pulsada
                ld a,c
                or a
                ret z                   ; ya lo estaba
                ld a,(hv_top)
                xor 1
                ld (hv_top),a
                ld hl,HRUI_PREV         ; todo se vuelve a pintar
                ld a,$FF
                ld bc,8*40-1
                call ui_fill
                ld hl,TOPPREV
                ld a,$FF
                ld bc,TXT_ROWS*40-1
                call ui_fill
                ld a,(UI_DIRTY)         ; el inventario se vuelve a dibujar
                or 4
                ld (UI_DIRTY),a
                ld a,(hv_top)
                or a
                jr z,ht_dn
                ld hl,HR_BM             ; arriba: las filas 0-3 (bitmap y atributos) en negro y fuera del scroll
                ld de,HR_BM+1
                ld bc,1023
                ld (hl),0
                ldir
                ld hl,HR_ATT
                ld de,HR_ATT+1
                ld bc,1023
                ld (hl),0
                ldir
                ld a,$F0
                ld (2091),a
                ret
ht_dn:          ld a,255                ; abajo: otra vez todas las filas 0-15 con scroll, y la sala se vuelve a dibujar entera
                ld (2091),a
                ld a,1
                ld (gd_pending),a
                ld (gd_full),a
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
                ld a,(hu_rb)
                ld c,a
                ld a,(hu_r)
                add a,c
                add a,HR_BM>>8
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
                ld a,(hu_rb)
                ld c,a
                ld a,(hu_r)
                add a,c
                add a,HR_ATT>>8
                ld h,a
                call hu_clr             ; B, C, D = los atributos de las 3 celdas de 8 pixeles del grupo
                ld b,a
                ld c,a
                ld d,a
                jr nc,hg_a              ; los mensajes: un solo color
                ld a,(hu_r)
                dec a
                cp 3
                jr nc,hg_a              ; la frase y el inventario: blanco
                push hl                 ; la interfaz (filas 0-3): el color de cada celda sale de UIAT (ui.asm), OR de los dos caracteres que toca:
                ld hl,(hu_src)          ; celda 0 = caracteres 0 y 1 del grupo, celda 1 = 1 y 2, celda 2 = 2 y 3 (6 pixeles por caracter, 8 por celda)
                ld de,UIAT-UIVB-4
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                xor $0F
                ld b,a
                ld a,(hl)
                inc hl
                or (hl)
                xor $0F
                ld c,a
                ld a,(hl)
                inc hl
                or (hl)
                xor $0F
                ld d,a
                pop hl
hg_a:           ld e,8
hg_l2:          ld (hl),b
                inc hl
                ld (hl),c
                inc hl
                ld (hl),d
                ld a,l                  ; siguiente linea (32 bytes mas abajo)
                add a,30
                ld l,a
                dec e
                jr nz,hg_l2
                ret
; A = atributo del texto de la fila hu_r: blanco brillante (carry: es la zona de la interfaz) o (los mensajes, sin carry) el color del que habla
hu_clr:         ld a,(tx_on)
                or a
                jr z,hc_w
                ld a,(hu_pass)
                or a
                jr nz,hc_t              ; la banda: el color del mensaje
                ld a,(hv_top)
                or a
                jr nz,hc_w
                ld a,(hu_r)
                cp TXT_ROW-UI_R0
                jr c,hc_w
hc_t:           ld a,(tx_clr)
                or a
                ret
hc_w:           ld a,$0F
                scf
                ret
